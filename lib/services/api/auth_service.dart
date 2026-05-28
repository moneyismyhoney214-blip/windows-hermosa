// ignore_for_file: avoid_dynamic_calls
// JSON wire-boundary layer — dynamic accesses accepted pending typed-model refactor.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../customer_display/nearpay/secure_credential_manager.dart';
import '../../locator.dart';
import '../../models/branch.dart';
import '../../waiter_module/services/mesh_auth_service.dart';
import '../logger_service.dart';
import '../nearpay/nearpay_service.dart';
import '../security/secure_token_store.dart';
import '../whatsapp_service.dart';
import 'api_constants.dart';
import 'base_client.dart';
import 'branch_service.dart';

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'user_data';
  static const String _branchIdKey = 'branch_id';
  static const String _sellerIdKey = 'seller_id';
  static const String _currencyKey = 'currency';
  static const String _hasTaxKey = 'has_tax';
  static const String _taxPercentageKey = 'tax_percentage';
  static const String _digitsNumberKey = 'digits_number';
  static const String _haveWaitersKey = 'have_waiters';
  static const String _whatsappEnabledKey = 'whatsapp_enabled';
  static const String _branchCountryIdKey = 'branch_country_id';
  String? _cachedToken;
  Map<String, dynamic>? _cachedUser;
  List<Map<String, dynamic>> _cachedLoginBranches = [];
  bool _isInitialized = false;

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
        final existing = byId[id];
        if (existing == null) {
          byId[id] = Map<String, dynamic>.from(branch);
          continue;
        }
        // Fill missing keys from later sources; don't clobber non-null first-source values.
        branch.forEach((key, value) {
          final cur = existing[key];
          final curIsEmpty = cur == null ||
              (cur is String && cur.isEmpty) ||
              (cur is Map && cur.isEmpty) ||
              (cur is List && cur.isEmpty);
          if (curIsEmpty && value != null) {
            existing[key] = value;
          }
        });
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
        _applyTaxObject(first['taxObject']);
      }

      return resolved;
    } catch (e) {
      Log.w('auth', 'failed to resolve branch from profile branches', error: e);
      return 0;
    }
  }

  /// Mirror a backend `taxObject` payload onto the global ApiConstants.
  /// Accepts either the canonical shape returned by `/seller/login` and
  /// `/seller/filters/branches/{id}/getTax`:
  ///
  /// ```json
  /// { "has_tax": true, "tax_percentage": 15,
  ///   "digits_number": 2, "currency": "ر.س" }
  /// ```
  ///
  /// or any subset of those keys. Missing fields keep the existing
  /// values. Returns true when at least one field was updated, so
  /// callers can decide whether to persist.
  bool _applyTaxObject(dynamic raw) {
    if (raw is! Map) return false;
    final tax = raw.map((k, v) => MapEntry(k.toString(), v));
    var changed = false;

    final hasTaxRaw = tax['has_tax'] ?? tax['hasTax'];
    if (hasTaxRaw != null) {
      final parsed = _coerceBool(hasTaxRaw);
      if (parsed != null) {
        ApiConstants.hasTax = parsed;
        changed = true;
      }
    }

    final percentageRaw = tax['tax_percentage'] ?? tax['taxPercentage'];
    if (percentageRaw != null) {
      final pct = _coerceNum(percentageRaw);
      if (pct != null) {
        // Backend may send 15 (percent) or 0.15 (rate). Normalize both.
        final percent = pct > 1.0 ? pct : pct * 100.0;
        ApiConstants.taxPercentage = percent.round();
        ApiConstants.taxRate = (percent / 100.0).clamp(0.0, 1.0).toDouble();
        changed = true;
      }
    }

    final digitsRaw = tax['digits_number'] ?? tax['digitsNumber'];
    if (digitsRaw != null) {
      final digits = _coerceNum(digitsRaw);
      if (digits != null) {
        ApiConstants.digitsNumber = digits.round();
        changed = true;
      }
    }

    final currencyRaw = tax['currency']?.toString().trim();
    if (currencyRaw != null && currencyRaw.isNotEmpty) {
      ApiConstants.currency = currencyRaw;
      changed = true;
    }

    if (changed) {
      Log.d('auth',
          'tax config applied → hasTax=${ApiConstants.hasTax} '
          'percentage=${ApiConstants.taxPercentage}% '
          'rate=${ApiConstants.taxRate} currency=${ApiConstants.currency}');
    }
    return changed;
  }

  bool? _coerceBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final s = value.trim().toLowerCase();
      if (['1', 'true', 'yes', 'on', 'active'].contains(s)) return true;
      if (['0', 'false', 'no', 'off', 'inactive'].contains(s)) return false;
    }
    return null;
  }

  num? _coerceNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value.trim());
    return null;
  }

  /// Persist the current tax config alongside the active session.
  Future<void> _persistTaxConfig(SharedPreferences prefs) async {
    await prefs.setBool(_hasTaxKey, ApiConstants.hasTax);
    await prefs.setInt(_taxPercentageKey, ApiConstants.taxPercentage);
    await prefs.setInt(_digitsNumberKey, ApiConstants.digitsNumber);
    await prefs.setString(_currencyKey, ApiConstants.currency);
  }

  /// Initialize the auth service - must be called before using
  Future<void> initialize({bool force = false}) async {
    if (_isInitialized && !force) return;
    await _loadTokenFromStorage();
    if (_cachedToken != null && _cachedToken!.isNotEmpty) {
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
        Log.i('auth', 'stored branch corrected to account branch: $fallbackId');
      }
    } catch (e) {
      Log.w('auth', 'skipping stored branch validation', error: e);
    }
  }

  /// Load token from secure storage on startup. Non-credential branch
  /// settings (tax, currency, module, etc.) stay in SharedPreferences —
  /// they're configuration, not secrets.
  Future<void> _loadTokenFromStorage() async {
    // SecureTokenStore migrates any legacy SharedPreferences-resident token on first run.
    _cachedToken = await secureTokenStore.readToken();
    final userJson = await secureTokenStore.readUser();
    if (userJson != null) {
      try {
        final decoded = jsonDecode(userJson);
        if (decoded is Map) {
          _cachedUser = decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } catch (e) {
        Log.w('auth', 'cached user JSON is corrupt — dropping', error: e);
        await secureTokenStore.deleteUser();
      }
    }

    // Corrupt prefs file (seen on Linux when a giant cache write was
    // interrupted) shouldn't take down session restore — defaults are valid.
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      Log.w('auth', 'SharedPreferences unavailable — using defaults', error: e);
    }
    if (prefs != null) {
      final savedBranchId = prefs.getInt(_branchIdKey);
      if (savedBranchId != null) {
        ApiConstants.branchId = savedBranchId;
      }
      final savedSellerId = prefs.getInt(_sellerIdKey);
      if (savedSellerId != null) {
        ApiConstants.sellerId = savedSellerId;
      }
      final savedCurrency = prefs.getString(_currencyKey);
      if (savedCurrency != null) {
        ApiConstants.currency = savedCurrency;
      }
      // Tax config defaults stay in place when prefs are missing — cold start needs valid math.
      final savedHasTax = prefs.getBool(_hasTaxKey);
      if (savedHasTax != null) ApiConstants.hasTax = savedHasTax;
      final savedTaxPct = prefs.getInt(_taxPercentageKey);
      if (savedTaxPct != null) {
        ApiConstants.taxPercentage = savedTaxPct;
        ApiConstants.taxRate = (savedTaxPct / 100.0).clamp(0.0, 1.0).toDouble();
      }
      final savedDigits = prefs.getInt(_digitsNumberKey);
      if (savedDigits != null) ApiConstants.digitsNumber = savedDigits;
      final savedModule = prefs.getString('branch_module');
      if (savedModule != null) {
        ApiConstants.branchModule = savedModule;
      }
      final savedHaveWaiters = prefs.getBool(_haveWaitersKey);
      if (savedHaveWaiters != null) {
        ApiConstants.haveWaiters = savedHaveWaiters;
      }
      final savedWhatsapp = prefs.getBool(_whatsappEnabledKey);
      if (savedWhatsapp != null) {
        ApiConstants.whatsappEnabled = savedWhatsapp;
      }
      final savedCountryId = prefs.getInt(_branchCountryIdKey);
      if (savedCountryId != null && savedCountryId > 0) {
        ApiConstants.branchCountryId = savedCountryId;
      }
    }
    if (_cachedToken != null && _cachedToken!.isNotEmpty) {
      BaseClient().setToken(_cachedToken!);
      Log.d('auth', 'session restored from secure storage');
    } else {
      Log.d('auth', 'no stored session');
    }
  }

  /// Save token to secure storage + non-credential settings to prefs.
  Future<void> _saveTokenToStorage(
      String token, Map<String, dynamic>? user) async {
    await secureTokenStore.writeToken(token);
    if (user != null) {
      await secureTokenStore.writeUser(jsonEncode(user));
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_branchIdKey, ApiConstants.branchId);
    await prefs.setInt(_sellerIdKey, ApiConstants.sellerId);
    await _persistTaxConfig(prefs);
    if (ApiConstants.branchModule.isNotEmpty) {
      await prefs.setString('branch_module', ApiConstants.branchModule);
    }
    Log.d('auth', 'session persisted (token in secure storage)');
  }

  /// Clear all session state from both secure and shared storage.
  Future<void> _clearTokenFromStorage() async {
    await secureTokenStore.clearAll();
    final prefs = await SharedPreferences.getInstance();
    // Remove legacy plaintext keys too, in case the migration hadn't run yet.
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_branchIdKey);
    await prefs.remove(_sellerIdKey);
    await prefs.remove(_currencyKey);
    await prefs.remove(_hasTaxKey);
    await prefs.remove(_taxPercentageKey);
    await prefs.remove(_digitsNumberKey);
    await prefs.remove('branch_module');
    await prefs.remove(_haveWaitersKey);
    await prefs.remove(_whatsappEnabledKey);
    await prefs.remove(_branchCountryIdKey);
    ApiConstants.branchId = 0;
    ApiConstants.sellerId = 1;
    ApiConstants.currency = 'ر.س';
    ApiConstants.hasTax = true;
    ApiConstants.taxPercentage = 15;
    ApiConstants.taxRate = 0.15;
    ApiConstants.digitsNumber = 2;
    ApiConstants.branchModule = '';
    ApiConstants.haveWaiters = true;
    ApiConstants.whatsappEnabled = true;
    ApiConstants.branchCountryId = 1;
    // Drop previous branch's WAWP creds so next session starts clean.
    whatsAppService.clearBackendCredentials();
    Log.d('auth', 'session data cleared');
  }

  /// Login with email and password using MultipartRequest
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String rememberMe = '0',
  }) async {
    final uri = Uri.parse(
        '${ApiConstants.authBaseUrl}${ApiConstants.jwtLoginEndpoint}');

    final request = http.MultipartRequest('POST', uri);
    request.fields['email'] = email;
    request.fields['password'] = password;
    request.fields['remember_me'] = rememberMe;

    request.headers.addAll(ApiConstants.defaultHeaders);

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200 || response.statusCode == 201) {
      // NEVER log the body — leaks token prefix + PII to logcat/syslog.
      final jsonData = jsonDecode(response.body);

      String? token;
      if (jsonData is Map) {
        final responseMap = jsonData.map((k, v) => MapEntry(k.toString(), v));
        token = _extractTokenFromPayload(responseMap);

        final data = responseMap['data'];
        if (data is Map) {
          final normalizedData = data.map((k, v) => MapEntry(k.toString(), v));
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

      Log.d('auth', 'login response parsed — token ${token != null ? "found" : "missing"}');

      if (token != null && token.isNotEmpty) {
        _cachedToken = token;
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
          Log.d('auth',
              'branch resolved from login payload: ${ApiConstants.branchId}');
        } else {
          Log.w('auth',
              'no valid branch_id in login payload; branch remains unset');
        }

        // Pull taxObject from the resolved branch — multi-branch accounts need per-branch VAT.
        if (jsonData is Map &&
            jsonData['data'] is Map &&
            jsonData['data']['branches'] is List) {
          final branches = jsonData['data']['branches'] as List;
          Map? matchedBranch;
          for (final entry in branches) {
            if (entry is! Map) continue;
            final id = _toInt(entry['id'] ?? entry['branch_id']);
            if (id != null && id == resolvedBranchId) {
              matchedBranch = entry;
              break;
            }
          }
          matchedBranch ??=
              (branches.isNotEmpty && branches.first is Map)
                  ? branches.first as Map
                  : null;
          if (matchedBranch != null && matchedBranch['taxObject'] is Map) {
            _applyTaxObject(matchedBranch['taxObject']);
          }
        }

        if (_cachedUser != null) {
          final dynamic sId = _cachedUser!['seller_id'] ?? _cachedUser!['id'];
          if (sId != null) {
            if (sId is String) {
              ApiConstants.sellerId = int.tryParse(sId) ?? 81;
            } else if (sId is int) {
              ApiConstants.sellerId = sId;
            }
          }
        }

        await _saveTokenToStorage(token, _cachedUser);
        Log.i('auth', 'login successful — session persisted');
      } else {
        // Don't echo jsonData — account-tier hints leak to logcat via USB.
        Log.w('auth', 'login response did not contain a token');
        throw Exception('لم يتم استلام رمز المصادقة');
      }

      return jsonData;
    } else {
      // Don't log body — may include email-tied validation messages.
      Log.w('auth', 'login failed (HTTP ${response.statusCode})');
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

  // --- Forgot password: 3-step signed-route flow; callers pass data.signed_route back unchanged. ---

  Map<String, String> _forgotHeaders() => {
        'Accept': 'application/json',
        'Accept-Language': ApiConstants.acceptLanguage,
      };

  Map<String, dynamic> _parseJsonBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return const {};
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (e) {
      // Malformed JSON is a real bug — surface in crash reports.
      Log.w('auth', 'response body was not valid JSON', error: e);
    }
    return const {};
  }

  String? _extractSignedRoute(Map<String, dynamic> payload) {
    final data = payload['data'];
    if (data is Map) {
      final route = data['signed_route']?.toString();
      if (route != null && route.isNotEmpty) return route;
    }
    final flat = payload['signed_route']?.toString();
    if (flat != null && flat.isNotEmpty) return flat;
    return null;
  }

  /// Step 1 — request an OTP for [identifier] (mobile number OR email).
  /// Returns the `signed_route` the caller must pass to [checkResetCode]
  /// once the user types the code.
  ///
  /// The backend uses two different form fields depending on the
  /// identifier shape: `mobile` for phone numbers, `email` for anything
  /// containing an `@`. We auto-detect so callers don't have to thread
  /// a flag through their UI.
  Future<String> sendForgotPasswordCode(String identifier) async {
    final uri = Uri.parse(
        '${ApiConstants.forgotBaseUrl}${ApiConstants.forgotEndpoint}');
    final trimmed = identifier.trim();
    final fieldName = trimmed.contains('@') ? 'email' : 'mobile';
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_forgotHeaders())
      ..fields[fieldName] = trimmed;
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final parsed = _parseJsonBody(response.body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      final route = _extractSignedRoute(parsed);
      if (route == null) {
        throw Exception(parsed['message']?.toString() ??
            'Forgot password: missing signed_route in response');
      }
      return route;
    }
    throw Exception(parsed['message']?.toString() ??
        'Forgot password failed: ${response.statusCode}');
  }

  /// Step 2 — POST the [otp] to the [signedRoute] returned by step 1.
  /// Returns the next `signed_route` to feed into [resetForgottenPassword].
  Future<String> checkResetCode({
    required String signedRoute,
    required String otp,
  }) async {
    final uri = Uri.parse('${ApiConstants.forgotBaseUrl}$signedRoute');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_forgotHeaders())
      ..fields['otp'] = otp.trim();
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final parsed = _parseJsonBody(response.body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      final route = _extractSignedRoute(parsed);
      if (route == null) {
        throw Exception(parsed['message']?.toString() ??
            'Invalid reset code: missing signed_route in response');
      }
      return route;
    }
    throw Exception(parsed['message']?.toString() ??
        'Invalid reset code: ${response.statusCode}');
  }

  /// Step 3 — POST the new [password] to the [signedRoute] returned by
  /// step 2. Server identifies the account via `employee_id` embedded in
  /// the signed path, so no auth token is required.
  Future<Map<String, dynamic>> resetForgottenPassword({
    required String signedRoute,
    required String password,
  }) async {
    final uri = Uri.parse('${ApiConstants.forgotBaseUrl}$signedRoute');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_forgotHeaders())
      ..fields['password'] = password
      ..fields['password_confirmation'] = password;
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final parsed = _parseJsonBody(response.body);
    if (response.statusCode == 200 || response.statusCode == 201) {
      return parsed;
    }
    throw Exception(parsed['message']?.toString() ??
        'Password reset failed: ${response.statusCode}');
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    if (!_isInitialized) {
      await initialize();
    }
    // Defensive re-read for the case where _cachedToken was cleared mid-rebuild.
    if (_cachedToken == null) {
      _cachedToken = await secureTokenStore.readToken();
      if (_cachedToken != null && _cachedToken!.isNotEmpty) {
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

  /// True when the signed-in user is an employee with the WAITER role.
  /// Matches the `/seller/employees` payload where `role` is set to
  /// "WAITER" (case-insensitive).
  bool isWaiter() {
    final user = _cachedUser;
    if (user == null) return false;
    final candidates = <dynamic>[
      user['role'],
      user['user_role'],
      user['employee_role'],
      user['type'],
    ];
    for (final value in candidates) {
      final token = value?.toString().trim().toLowerCase();
      if (token != null && token.isNotEmpty) {
        if (token == 'waiter') return true;
      }
    }
    return false;
  }

  /// True when the signed-in user has the OWNER role (case-insensitive).
  /// Used to gate owner-only features such as the per-cashier filter on the
  /// daily closing report.
  bool isOwner() {
    final user = _cachedUser;
    if (user == null) return false;
    final candidates = <dynamic>[
      user['role'],
      user['user_role'],
      user['employee_role'],
      user['type'],
    ];
    for (final value in candidates) {
      final token = value?.toString().trim().toLowerCase();
      if (token != null && token.isNotEmpty) {
        if (token == 'owner') return true;
      }
    }
    return false;
  }

  /// Logout - clear token
  Future<void> logout() async {
    try {
      final client = BaseClient();
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
      Log.w('auth', 'API logout failed (local state will still be cleared)',
          error: e);
    } finally {
      _cachedToken = null;
      _cachedUser = null;
      BaseClient().clearToken();
      NearPayService().clearCache();
      // Wipe per-session BranchService caches so next user on shared tablet doesn't inherit.
      try {
        getIt<BranchService>().clearSessionCaches();
      } catch (e) {
        Log.w('auth', 'logout: BranchService.clearSessionCaches failed',
            error: e);
      }
      // Drop NearPay merchant credentials cache so next account can't reuse from memory.
      try {
        secureCredentialManager.clearCache();
      } catch (e) {
        Log.w('auth', 'logout: NearPay credential cache clear failed',
            error: e);
      }
      // Wipe mesh MAC key — fresh login derives a new one per branch+seller.
      try {
        getIt<MeshAuthService>().clear();
      } catch (e) {
        Log.w('auth', 'logout: MeshAuthService.clear failed', error: e);
      }
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
      Log.w('auth', 'getProfile failed — returning cached user data');
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
        Log.w('auth', 'failed to load branches from $endpoint', error: e);
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
        Log.w('auth', 'skipping invalid branch payload', error: e);
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

  /// Refresh the cached `have_waiters` flag for the active branch and
  /// persist it. Used at session bootstrap to pick up changes the
  /// backend made between app runs without forcing the user to reselect
  /// the branch.
  Future<void> persistHaveWaiters(bool value) async {
    ApiConstants.haveWaiters = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_haveWaitersKey, value);
  }

  /// Same flow as [persistHaveWaiters] but for the `whatsapp_status` flag.
  Future<void> persistWhatsappEnabled(bool value) async {
    ApiConstants.whatsappEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_whatsappEnabledKey, value);
  }

  /// Update the active branch and persist it. Pulls VAT/currency from
  /// the branch's `taxObject` so the global state stays consistent with
  /// the branch the user is operating in.
  Future<void> updateActiveBranch(Branch branch) async {
    ApiConstants.branchId = branch.id;
    ApiConstants.branchModule = branch.module;
    ApiConstants.haveWaiters = branch.haveWaiters;
    ApiConstants.whatsappEnabled = branch.whatsappStatus;
    if (branch.countryId > 0) {
      ApiConstants.branchCountryId = branch.countryId;
    }

    final tax = branch.taxObject;
    ApiConstants.hasTax = tax.hasTax;
    ApiConstants.taxPercentage = tax.taxPercentage;
    ApiConstants.taxRate =
        (tax.taxPercentage / 100.0).clamp(0.0, 1.0).toDouble();
    ApiConstants.digitsNumber = tax.digitsNumber;
    if (tax.currency.trim().isNotEmpty) {
      ApiConstants.currency = tax.currency;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_branchIdKey, ApiConstants.branchId);
    await _persistTaxConfig(prefs);
    await prefs.setString('branch_module', branch.module);
    await prefs.setBool(_haveWaitersKey, branch.haveWaiters);
    await prefs.setBool(_whatsappEnabledKey, branch.whatsappStatus);
    if (branch.countryId > 0) {
      await prefs.setInt(_branchCountryIdKey, branch.countryId);
    }

    Log.d('auth',
        'active branch → id=${branch.id} module=${branch.module} '
        'hasTax=${ApiConstants.hasTax} '
        'taxPercentage=${ApiConstants.taxPercentage}% '
        'haveWaiters=${branch.haveWaiters} '
        'whatsappEnabled=${branch.whatsappStatus} '
        'country=${branch.countryId}');
  }
}
