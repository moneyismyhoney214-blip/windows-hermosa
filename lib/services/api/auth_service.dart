import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'api_constants.dart';
import 'base_client.dart';
import '../../models/branch.dart';
import '../nearpay/nearpay_service.dart';

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';
  static const String _branchIdKey = 'branch_id';
  static const String _sellerIdKey = 'seller_id';
  static const String _currencyKey = 'currency';
  String? _cachedToken;
  Map<String, dynamic>? _cachedUser;
  List<Map<String, dynamic>> _cachedLoginBranches = [];
  bool _isInitialized = false;

  // Singleton
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  int? _extractBranchIdFromMap(Map<String, dynamic> map) {
    final direct = _toInt(map['branch_id'] ?? map['current_branch_id']);
    if (direct != null && direct > 0) return direct;

    final branch = map['branch'];
    if (branch is Map) {
      final nested = _toInt(branch['id'] ?? branch['branch_id']);
      if (nested != null && nested > 0) return nested;
    }
    return null;
  }

  int _resolveBranchIdFromLoginPayload(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is! Map<String, dynamic>) return 0;

    final fromData = _extractBranchIdFromMap(data);
    if (fromData != null) return fromData;

    final user = data['user'];
    if (user is Map<String, dynamic>) {
      final fromUser = _extractBranchIdFromMap(user);
      if (fromUser != null) return fromUser;
    }

    final branches = data['branches'];
    if (branches is List && branches.isNotEmpty) {
      final first = branches.first;
      if (first is Map<String, dynamic>) {
        final fromBranches = _toInt(first['id'] ?? first['branch_id']) ?? 0;
        if (fromBranches > 0) return fromBranches;
      } else if (first is Map) {
        final id = _toInt(first['id'] ?? first['branch_id']) ?? 0;
        if (id > 0) return id;
      }
    }

    return 0;
  }

  String? _extractTokenFromPayload(Map<String, dynamic> payload) {
    String? asNonEmpty(dynamic value) {
      final text = value?.toString().trim();
      if (text == null || text.isEmpty || text == 'null') return null;
      return text;
    }

    final data = payload['data'];
    if (data is Map) {
      final map = data.map((k, v) => MapEntry(k.toString(), v));
      final direct = asNonEmpty(
        map['token'] ?? map['access_token'] ?? map['jwt'] ?? map['auth_token'],
      );
      if (direct != null) return direct;

      final auth = map['auth'];
      if (auth is Map) {
        final authMap = auth.map((k, v) => MapEntry(k.toString(), v));
        final authToken = asNonEmpty(
          authMap['token'] ??
              authMap['access_token'] ??
              authMap['jwt'] ??
              authMap['auth_token'],
        );
        if (authToken != null) return authToken;
      }
    }

    return asNonEmpty(
      payload['token'] ??
          payload['access_token'] ??
          payload['jwt'] ??
          payload['auth_token'],
    );
  }

  Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  List<Map<String, dynamic>> _coerceBranchList(dynamic raw) {
    if (raw is List) {
      return raw
          .map(_asStringMap)
          .whereType<Map<String, dynamic>>()
          .where((item) {
        final id = _toInt(item['id'] ?? item['branch_id']);
        return id != null && id > 0;
      }).toList();
    }

    final map = _asStringMap(raw);
    if (map == null) return [];

    for (final key in const ['data', 'branches', 'items', 'results']) {
      final nested = _coerceBranchList(map[key]);
      if (nested.isNotEmpty) return nested;
    }

    final id = _toInt(map['id'] ?? map['branch_id']);
    if (id != null && id > 0) {
      return [map];
    }
    return [];
  }

  List<Map<String, dynamic>> _mergeUniqueBranchMaps(
    Iterable<List<Map<String, dynamic>>> sources,
  ) {
    final byId = <int, Map<String, dynamic>>{};
    for (final source in sources) {
      for (final branch in source) {
        final id = _toInt(branch['id'] ?? branch['branch_id']);
        if (id == null || id <= 0) continue;
        byId.putIfAbsent(id, () => branch);
      }
    }
    return byId.values.toList();
  }

  Future<int> _resolveBranchIdFromProfileBranches() async {
    try {
      final branches = await getBranchesRaw();
      if (branches.isEmpty) return 0;

      final first = branches.first;
      final resolved = _toInt(first['id'] ?? first['branch_id']) ?? 0;
      if (resolved <= 0) return 0;

      if (first['taxObject'] is Map) {
        final taxObject = (first['taxObject'] as Map)
            .map((k, v) => MapEntry(k.toString(), v));
        final currency = taxObject['currency']?.toString().trim();
        if (currency != null && currency.isNotEmpty) {
          ApiConstants.currency = currency;
        }
      }

      return resolved;
    } catch (e) {
      print('⚠️ Failed to resolve branch from profile branches: $e');
      return 0;
    }
  }

  /// Initialize the auth service - must be called before using
  Future<void> initialize({bool force = false}) async {
    if (_isInitialized && !force) return;
    await _loadTokenFromStorage();
    if (_cachedToken != null && _cachedToken!.isNotEmpty) {
      // Do not block app startup on network-bound validation.
      unawaited(_validateStoredBranchForCurrentAccount());
    }
    _isInitialized = true;
  }

  Future<void> _validateStoredBranchForCurrentAccount() async {
    if (_cachedToken == null || _cachedToken!.isEmpty) return;

    try {
      final branches = await getBranchesRaw();
      if (branches.isEmpty) return;

      final availableIds = branches
          .map((b) => _toInt(b['id'] ?? b['branch_id']))
          .whereType<int>()
          .where((id) => id > 0)
          .toSet();
      if (availableIds.isEmpty) return;

      if (!availableIds.contains(ApiConstants.branchId)) {
        final fallbackId = availableIds.first;
        ApiConstants.branchId = fallbackId;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_branchIdKey, fallbackId);
        print('🔁 Stored branch corrected to account branch: $fallbackId');
      }
    } catch (e) {
      print('⚠️ Skipping stored branch validation: $e');
    }
  }

  /// Load token from SharedPreferences on startup
  Future<void> _loadTokenFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString(_tokenKey);
    final userJson = prefs.getString(_userKey);
    if (userJson != null) {
      _cachedUser = jsonDecode(userJson);
    }
    // Load branch ID from storage
    final savedBranchId = prefs.getInt(_branchIdKey);
    if (savedBranchId != null) {
      ApiConstants.branchId = savedBranchId;
      print('🏪 Branch ID loaded from storage: $savedBranchId');
    }
    // Load Seller ID
    final savedSellerId = prefs.getInt(_sellerIdKey);
    if (savedSellerId != null) {
      ApiConstants.sellerId = savedSellerId;
      print('👤 Seller ID loaded from storage: $savedSellerId');
    }
    // Load Currency
    final savedCurrency = prefs.getString(_currencyKey);
    if (savedCurrency != null) {
      ApiConstants.currency = savedCurrency;
      print('💰 Currency loaded from storage: $savedCurrency');
    }
    if (_cachedToken != null) {
      BaseClient().setToken(_cachedToken!);
      print('📦 Token loaded from storage');
    } else {
      print('📦 No token found in storage');
    }
  }

  /// Save token to SharedPreferences
  Future<void> _saveTokenToStorage(
      String token, Map<String, dynamic>? user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    if (user != null) {
      await prefs.setString(_userKey, jsonEncode(user));
    }
    // Save branch ID, Seller ID & Currency
    await prefs.setInt(_branchIdKey, ApiConstants.branchId);
    await prefs.setInt(_sellerIdKey, ApiConstants.sellerId);
    await prefs.setString(_currencyKey, ApiConstants.currency);
    print('💾 Branch, Seller ID & Currency saved to storage');
  }

  /// Clear token from SharedPreferences
  Future<void> _clearTokenFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_branchIdKey);
    await prefs.remove(_sellerIdKey);
    await prefs.remove(_currencyKey);
    // Reset defaults
    ApiConstants.branchId = 0;
    ApiConstants.sellerId = 1;
    ApiConstants.currency = 'ر.س';
    print('🗑️ Session data cleared from storage');
  }

  /// Login with email and password using MultipartRequest
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String rememberMe = '0',
  }) async {
    final uri = Uri.parse(
        '${ApiConstants.authBaseUrl}${ApiConstants.jwtLoginEndpoint}');

    var request = http.MultipartRequest('POST', uri);
    request.fields['email'] = email;
    request.fields['password'] = password;
    request.fields['remember_me'] = rememberMe;

    // Add required headers
    request.headers.addAll(ApiConstants.defaultHeaders);

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final jsonData = jsonDecode(response.body);
      print(
          '📥 Login response received: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...');

      // Extract token from supported response variants.
      String? token;
      if (jsonData is Map) {
        final responseMap = jsonData.map((k, v) => MapEntry(k.toString(), v));
        print('🔍 Response keys: ${responseMap.keys.toList()}');
        token = _extractTokenFromPayload(responseMap);

        final data = responseMap['data'];
        if (data is Map) {
          final normalizedData = data.map((k, v) => MapEntry(k.toString(), v));
          print('🔍 Data keys: ${normalizedData.keys.toList()}');
          final user = normalizedData['user'];
          if (user is Map<String, dynamic>) {
            _cachedUser = user;
          } else if (user is Map) {
            _cachedUser = user.map((k, v) => MapEntry(k.toString(), v));
          }
        } else {
          final user = responseMap['user'];
          if (user is Map<String, dynamic>) {
            _cachedUser = user;
          } else if (user is Map) {
            _cachedUser = user.map((k, v) => MapEntry(k.toString(), v));
          }
        }
      }

      print('🔍 Token extracted: ${token != null ? "FOUND" : "NULL"}');

      if (token != null && token.isNotEmpty) {
        _cachedToken = token;
        // Set token in BaseClient for authenticated requests
        BaseClient().setToken(token);
        // Prevent stale branch leaks from previous sessions/accounts.
        ApiConstants.branchId = 0;

        if (jsonData is Map) {
          _cachedLoginBranches = _coerceBranchList(jsonData);
        }

        var resolvedBranchId = 0;
        if (jsonData is Map) {
          resolvedBranchId = _resolveBranchIdFromLoginPayload(
            jsonData.map((k, v) => MapEntry(k.toString(), v)),
          );
        }
        if (resolvedBranchId <= 0) {
          resolvedBranchId = await _resolveBranchIdFromProfileBranches();
        }

        if (resolvedBranchId > 0) {
          ApiConstants.branchId = resolvedBranchId;
          print(
              '🏪 Branch ID set to: ${ApiConstants.branchId} from login payload');
        } else {
          print(
              '⚠️ No valid branch_id in login payload. Branch remains unset (0).');
        }

        // Extract currency from first branch if available
        if (jsonData is Map &&
            jsonData['data'] is Map &&
            jsonData['data']['branches'] is List) {
          final branches = jsonData['data']['branches'] as List;
          if (branches.isNotEmpty && branches.first is Map) {
            final branchData = branches.first as Map;
            if (branchData['taxObject'] is Map &&
                branchData['taxObject']['currency'] != null) {
              ApiConstants.currency =
                  branchData['taxObject']['currency'].toString();
              print(
                  '💰 Currency set to: ${ApiConstants.currency} from login response');
            }
          }
        }

        // Set Seller ID from User ID or seller_id field
        if (_cachedUser != null) {
          dynamic sId = _cachedUser!['seller_id'] ?? _cachedUser!['id'];
          if (sId != null) {
            if (sId is String) {
              ApiConstants.sellerId = int.tryParse(sId) ?? 81;
            } else if (sId is int) {
              ApiConstants.sellerId = sId;
            }
          }
          print(
              '👤 Seller ID set to: ${ApiConstants.sellerId} from login response');
        }

        // Persist session with resolved branch/currency/seller.
        await _saveTokenToStorage(token, _cachedUser);
        print('✅ Token set successfully and saved to storage');
      } else {
        print('❌ No token found in response. Full response: $jsonData');
        throw Exception('لم يتم استلام رمز المصادقة');
      }

      return jsonData;
    } else {
      final errorBody = response.body;
      print('Login failed: ${response.statusCode} → $errorBody');
      throw Exception('فشل تسجيل الدخول: ${response.statusCode}');
    }
  }

  /// Login with email (alias for login)
  Future<Map<String, dynamic>> loginWithEmail({
    required String email,
    required String password,
    int rememberMe = 0,
  }) async {
    return login(
        email: email, password: password, rememberMe: rememberMe.toString());
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    // Initialize if not already done
    if (!_isInitialized) {
      await initialize();
    }
    // Load from storage if not cached
    if (_cachedToken == null) {
      final prefs = await SharedPreferences.getInstance();
      _cachedToken = prefs.getString(_tokenKey);
      if (_cachedToken != null) {
        BaseClient().setToken(_cachedToken!);
      }
    }
    return _cachedToken != null && _cachedToken!.isNotEmpty;
  }

  Future<bool> ensureSessionReady({bool requireBranch = true}) async {
    await initialize();
    final token = _cachedToken?.trim();
    if (token == null || token.isEmpty) return false;

    BaseClient().setToken(token);

    if (!requireBranch) return true;
    if (ApiConstants.branchId > 0) return true;

    final resolvedBranchId = await _resolveBranchIdFromProfileBranches();
    if (resolvedBranchId <= 0) return false;

    ApiConstants.branchId = resolvedBranchId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_branchIdKey, resolvedBranchId);
    await prefs.setString(_currencyKey, ApiConstants.currency);
    return true;
  }

  /// Get current auth token
  String? getToken() => _cachedToken;

  /// Get cached user data
  Map<String, dynamic>? getUser() => _cachedUser;

  /// Logout - clear token
  Future<void> logout() async {
    try {
      final client = BaseClient();
      // Perform API logout with specific headers requested
      await client.post(
        ApiConstants.logoutEndpoint,
        {},
        headers: {
          'Accept-Platform': 'dashboard',
          'Accept-ISO': 'SAU',
          'Accept-Language': ApiConstants.acceptLanguage,
        },
      );
    } catch (e) {
      print('⚠️ API Logout failed: $e');
    } finally {
      _cachedToken = null;
      _cachedUser = null;
      BaseClient().clearToken();
      NearPayService().clearCache();
      await _clearTokenFromStorage();
    }
  }

  /// Get user profile from API
  Future<Map<String, dynamic>> getProfile() async {
    final client = BaseClient();
    bool isTransientTransportError(Object error) {
      final msg = error.toString().toLowerCase();
      return msg.contains('connection closed before full header') ||
          msg.contains('clientexception') ||
          msg.contains('socketexception') ||
          msg.contains('transport_error');
    }

    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await client.get(ApiConstants.profileEndpoint);
        if (response['data'] != null) {
          final data = response['data'];
          if (data is Map<String, dynamic>) {
            _cachedUser = data;
          } else if (data is Map) {
            _cachedUser = data.map((k, v) => MapEntry(k.toString(), v));
          }
        }
        return response;
      } catch (e) {
        lastError = e;
        if (!isTransientTransportError(e) || attempt == 2) {
          break;
        }
        await Future.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
    }

    if (_cachedUser != null) {
      print('⚠️ getProfile failed, returning cached user data');
      return {
        'status': 200,
        'message': 'cached_profile_fallback',
        'data': _cachedUser,
      };
    }

    throw lastError ?? Exception('Failed to load profile');
  }

  /// Get user's branches as raw data
  Future<List<Map<String, dynamic>>> getBranchesRaw() async {
    final client = BaseClient();
    final collected = <List<Map<String, dynamic>>>[];

    if (_cachedLoginBranches.isNotEmpty) {
      collected.add(List<Map<String, dynamic>>.from(_cachedLoginBranches));
    }

    for (final endpoint in [
      ApiConstants.profileBranchesEndpoint,
      ApiConstants.branchesEndpoint,
    ]) {
      try {
        final response = await client.get(endpoint);
        final branches = _coerceBranchList(response);
        if (branches.isNotEmpty) {
          collected.add(branches);
        }
      } catch (e) {
        print('⚠️ Failed to load branches from $endpoint: $e');
      }
    }

    final merged = _mergeUniqueBranchMaps(collected);
    if (merged.isNotEmpty) {
      return merged;
    }

    return List<Map<String, dynamic>>.from(_cachedLoginBranches);
  }

  /// Get user's branches as Branch objects
  Future<List<Branch>> getBranches() async {
    final rawBranches = await getBranchesRaw();
    final parsed = <Branch>[];
    for (final branchJson in rawBranches) {
      try {
        parsed.add(Branch.fromJson(branchJson));
      } catch (e) {
        print('⚠️ Skipping invalid branch payload: $e');
      }
    }
    return parsed;
  }

  /// Get first branch name
  Future<String?> getBranchName() async {
    final branches = await getBranches();
    if (branches.isNotEmpty) {
      return branches.first.name;
    }
    return null;
  }

  /// Update the active branch and persist it
  Future<void> updateActiveBranch(Branch branch) async {
    ApiConstants.branchId = branch.id;
    ApiConstants.currency = branch.taxObject.currency;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_branchIdKey, ApiConstants.branchId);
    await prefs.setString(_currencyKey, ApiConstants.currency);

    print('🔄 Active Branch updated to: ${branch.name} (ID: ${branch.id})');
  }
}
