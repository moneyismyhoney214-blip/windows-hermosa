/// NearPay Service - Display App Side
///
/// Handles NearPay SDK initialization and payment processing.
/// This service is initialized when the Cashier App sends NearPay credentials
/// via WebSocket after successful login.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:flutter_terminal_sdk/flutter_terminal_sdk.dart';
import 'package:flutter_terminal_sdk/models/purchase_callbacks.dart';
import 'package:flutter_terminal_sdk/models/card_reader_callbacks.dart';
import 'package:flutter_terminal_sdk/models/data/payment_scheme.dart';
import 'package:flutter_terminal_sdk/models/nearpay_user_response.dart';
import 'package:flutter_terminal_sdk/models/terminal_connection_response.dart';
import 'package:flutter_terminal_sdk/models/terminal_response.dart';
import 'package:flutter_terminal_sdk/models/terminal_sdk_initialization_listener.dart';
import 'package:flutter_terminal_sdk/models/data/ui_dock_position.dart';

import '../../services/presentation_service.dart';

import 'app_logger.dart';
import 'nearpay_backend_service.dart';
import 'nearpay_config_service.dart';

/// NearPay Service Singleton
///
/// Manages the NearPay SDK lifecycle:
/// 1. Receives init data from Cashier App via WebSocket
/// 2. Fetches JWT token from backend
/// 3. Initializes the SDK
/// 4. Connects to terminal
/// 5. Processes payments
class NearPayService {
  static final NearPayService _instance = NearPayService._internal();
  factory NearPayService() => _instance;
  NearPayService._internal();

  // SDK instance
  FlutterTerminalSdk? _sdk;
  TerminalModel? _connectedTerminal;

  // JWT token management
  DateTime? _jwtExpiresAt;
  bool _isReady = false;

  // Configuration from Cashier
  String? _backendUrl;
  String? _authToken;
  int? _branchId;

  // Terminal data
  String? _terminalUuid;
  String? _tid;
  String? _userUuid;
  NearPayBackendService? _apiService;
  String _lastSdkEnvironment = 'UNKNOWN';

  bool _paymentInFlight = false;
  Future<void>? _initializeInFlight;
  Future<TerminalModel>? _jwtLoginInFlight;

  String? _normalizeBackendUrl(String? value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.contains('portal.hermosaapp.com')) {
      return 'https://portal.hermosaapp.com';
    }
    if (raw.endsWith('/seller')) {
      return raw.substring(0, raw.length - '/seller'.length);
    }
    return raw;
  }

  Environment _resolveSdkEnvironment() {
    const forced = String.fromEnvironment('NEARPAY_SDK_ENV', defaultValue: '');
    final normalizedForced = forced.trim().toLowerCase();
    if (normalizedForced == 'sandbox') return Environment.sandbox;
    if (normalizedForced == 'production') return Environment.production;
    if (normalizedForced == 'internal') return Environment.internal;

    // Safety: release builds should default to production unless explicitly overridden.
    if (kReleaseMode) return Environment.production;

    final backend = (_backendUrl ?? '').toLowerCase();
    const sandboxHints = <String>[
      'sandbox',
      'staging',
      'dev',
      'localhost',
      '127.0.0.1',
      '.local',
    ];
    final looksSandbox = sandboxHints.any((hint) => backend.contains(hint));
    return looksSandbox ? Environment.sandbox : Environment.production;
  }

  void _npLog(String message, {Object? error, StackTrace? stackTrace}) {
    final timestamp = DateTime.now().toIso8601String();
    final fullMessage = '[$timestamp] $message';

    developer.log(
      '[NearPay] $fullMessage',
      name: 'NearPay',
      error: error,
      stackTrace: stackTrace,
    );
    AppLogger.logNearPay(fullMessage);

    // Also print to console for immediate visibility
    if (kDebugMode) {
      print('🔷 NearPay: $fullMessage');
      if (error != null) {
        print('   Error: $error');
        if (stackTrace != null) {
          print('   Stack: $stackTrace');
        }
      }
    }
  }

  void _npLogDetail(String title, Map<String, dynamic> details) {
    final timestamp = DateTime.now().toIso8601String();
    final detailsStr = details.entries
        .map((e) => '   ${e.key}: ${e.value}')
        .join('\n');
    final fullMessage = '[$timestamp] 📋 $title\n$detailsStr';

    developer.log('[NearPay] $fullMessage', name: 'NearPay');
    AppLogger.logNearPay(fullMessage);

    if (kDebugMode) {
      debugPrint('📋 NearPay: $title');
      details.forEach((key, value) {
        debugPrint('   $key: $value');
      });
    }
  }

  Future<void> _logDeveloperCertLoaded() async {
    try {
      final cert = await rootBundle.load('assets/certs/developer_cert.pem');
      developer.log(
        '[NearPay] developer_cert.pem loaded — ${cert.lengthInBytes} bytes',
        name: 'NearPay',
      );
      AppLogger.logNearPay(
        'developer_cert.pem loaded — ${cert.lengthInBytes} bytes',
      );
    } catch (e, stackTrace) {
      developer.log(
        '[NearPay] developer_cert.pem load failed: $e',
        name: 'NearPay',
        error: e,
        stackTrace: stackTrace,
      );
      AppLogger.logNearPay('developer_cert.pem load failed: $e');
      if (kDebugMode) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: e,
            stack: stackTrace,
            library: 'NearPay',
            context: ErrorDescription('developer_cert.pem load failed'),
          ),
        );
      }
    }
  }

  String _mask(String? value, {int visible = 4}) {
    if (value == null || value.isEmpty) return 'MISSING';
    if (value.length <= visible) {
      return '${value.substring(0, value.length)}***';
    }
    return '${value.substring(0, visible)}***';
  }

  String _maskId(String? value) => _mask(value, visible: 6);

  /// Safely decode base64 JWT part (for logging header/payload structure)
  String _safeBase64Decode(String part) {
    try {
      final normalized = base64Url.normalize(part);
      final decoded = utf8.decode(base64Url.decode(normalized));
      // Return max 200 chars
      return decoded.length > 200 ? '${decoded.substring(0, 200)}...' : decoded;
    } catch (e) {
      return 'DECODE_ERROR: $e';
    }
  }

  /// Extract only the keys from JWT payload (not values — no secrets)
  String _safePayloadKeys(String part) {
    try {
      final normalized = base64Url.normalize(part);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final map = jsonDecode(decoded);
      if (map is Map) {
        return _extractKeys(map).join(', ');
      }
      return 'NOT_A_MAP';
    } catch (e) {
      return 'DECODE_ERROR: $e';
    }
  }

  /// Recursively extract keys from nested map
  List<String> _extractKeys(Map map, [String prefix = '']) {
    final keys = <String>[];
    for (final entry in map.entries) {
      final key = prefix.isEmpty ? '${entry.key}' : '$prefix.${entry.key}';
      keys.add(key);
      if (entry.value is Map) {
        keys.addAll(_extractKeys(entry.value as Map, key));
      }
    }
    return keys;
  }

  // Getters
  bool get isReady => _isReady;
  TerminalModel? get connectedTerminal => _connectedTerminal;
  bool get isInitialized => _sdk != null;
  String? get userUuid => _userUuid;

  NearPayBackendService _requireApiService() {
    if (_backendUrl == null ||
        _authToken == null ||
        _authToken!.isEmpty ||
        _branchId == null) {
      throw Exception(
        'NearPay init data missing — did Cashier send nearpay_init?',
      );
    }
    return _apiService ??= NearPayBackendService(
      baseUrl: _backendUrl!,
      authToken: _authToken!,
      branchId: _branchId!,
    );
  }

  Future<TerminalModel> _jwtLoginWithLock(String jwt) async {
    final inFlight = _jwtLoginInFlight;
    if (inFlight != null) {
      _npLog('⏳ jwtLogin already running — joining existing task');
      return inFlight;
    }
    if (_sdk == null) {
      throw Exception('NearPay SDK not initialized');
    }

    final pending = _sdk!.jwtLogin(jwt: jwt);
    _jwtLoginInFlight = pending;
    try {
      return await pending;
    } finally {
      if (identical(_jwtLoginInFlight, pending)) {
        _jwtLoginInFlight = null;
      }
    }
  }

  Future<void> _persistUserUuid(String? userUuid) async {
    final normalized = userUuid?.trim();
    if (normalized == null || normalized.isEmpty) {
      return;
    }
    _userUuid = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('np_terminal_user_uuid', normalized);
  }

  Future<String?> _loadSavedUserUuid() async {
    final current = _userUuid?.trim();
    if (current != null && current.isNotEmpty) {
      return current;
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('np_terminal_user_uuid')?.trim();
    if (saved != null && saved.isNotEmpty) {
      _userUuid = saved;
      return saved;
    }
    return null;
  }

  // Reserved fallback for the full documented SDK flow.
  // ignore: unused_element
  Future<NearpayUser> _resolveActiveUser() async {
    if (_sdk == null) {
      throw Exception('NearPay SDK not initialized');
    }

    final savedUserUuid = await _loadSavedUserUuid();
    if (savedUserUuid != null && savedUserUuid.isNotEmpty) {
      _npLog('🔄 Resolving active user via getUser(uuid)...');
      _npLogDetail('User Resolution Params', {
        'user_uuid': _maskId(savedUserUuid),
      });
      try {
        final user = await _sdk!.getUser(uuid: savedUserUuid);
        await _persistUserUuid(user.userUUID);
        _npLog('✅ Active user resolved from saved userUUID');
        return user;
      } catch (e) {
        _npLog('⚠️ getUser(saved userUUID) failed: $e');
      }
    }

    _npLog('🔄 Falling back to SDK getUsers()...');
    final sdkUsers = await _sdk!.getUsers();
    final validUsers = sdkUsers.where((u) {
      final uuid = u.userUUID?.trim();
      return uuid != null && uuid.isNotEmpty;
    }).toList();

    if (validUsers.isEmpty) {
      throw Exception('No authenticated SDK users found after jwtLogin');
    }

    final resolvedUser = validUsers.first;
    await _persistUserUuid(resolvedUser.userUUID);
    _npLog('✅ Active user resolved from getUsers() fallback');
    return resolvedUser;
  }

  TerminalConnectionModel? _selectTerminalConnection(
    List<TerminalConnectionModel> terminals,
  ) {
    if (terminals.isEmpty) return null;

    for (final terminal in terminals) {
      if (_terminalUuid != null &&
          _terminalUuid!.isNotEmpty &&
          terminal.uuid == _terminalUuid) {
        return terminal;
      }
      if (_tid != null && _tid!.isNotEmpty && terminal.tid == _tid) {
        return terminal;
      }
    }

    return terminals.first;
  }

  Future<List<TerminalConnectionModel>> _listUserTerminals(
    NearpayUser user, {
    String? filter,
  }) async {
    if (_sdk == null) {
      throw Exception('NearPay SDK not initialized');
    }
    final userUuid = user.userUUID?.trim();
    if (userUuid == null || userUuid.isEmpty) {
      throw Exception('User UUID missing - cannot list terminals');
    }

    _npLog('🔄 Listing terminals for active user...');
    _npLogDetail('List Terminals Params', {
      'user_uuid': _maskId(userUuid),
      'page': '1',
      'page_size': '10',
      'filter': filter ?? 'NULL',
    });

    final terminals = await _sdk!.getTerminalList(
      userUuid,
      page: 1,
      pageSize: 10,
      filter: filter,
    );

    _npLogDetail('List Terminals Result', {
      'count': terminals.length.toString(),
      'terminals': terminals
          .map((terminal) => '${terminal.tid}|${_maskId(terminal.uuid)}')
          .join(', '),
    });
    return terminals;
  }

  // Reserved fallback for the full documented SDK flow.
  // ignore: unused_element
  Future<TerminalModel> _connectTerminalUsingDocumentedFlow(
    NearpayUser user,
  ) async {
    if (_sdk == null) {
      throw Exception('NearPay SDK not initialized');
    }

    final filterCandidates = <String?>[
      _tid?.trim(),
      _terminalUuid?.trim(),
      null,
    ];

    List<TerminalConnectionModel> terminals = const [];
    for (final candidate in filterCandidates) {
      final next = await _listUserTerminals(user, filter: candidate);
      if (next.isNotEmpty) {
        terminals = next;
        break;
      }
    }

    if (terminals.isEmpty) {
      throw Exception('No terminals found for authenticated user');
    }

    final selectedTerminal = _selectTerminalConnection(terminals);
    if (selectedTerminal == null) {
      throw Exception('Failed to select terminal from authenticated user list');
    }

    _npLog('🔄 Connecting terminal using documented flow...');
    _npLogDetail('Connect Terminal Params', {
      'tid': selectedTerminal.tid,
      'user_uuid': _maskId(selectedTerminal.userUUID),
      'terminal_uuid': _maskId(selectedTerminal.uuid),
    });

    final connectedTerminal = await _sdk!.connectTerminal(
      tid: selectedTerminal.tid,
      userUUID: selectedTerminal.userUUID,
      terminalUUID: selectedTerminal.uuid,
    );

    _tid = selectedTerminal.tid;
    _terminalUuid = selectedTerminal.uuid;
    await _persistUserUuid(selectedTerminal.userUUID);

    _npLog('✅ Terminal connected using listTerminals -> connectTerminal flow');
    return connectedTerminal;
  }

  /// Save initialization data received from Cashier App via WebSocket
  ///
  /// Cashier sends: {
  ///   'type': 'nearpay_init',
  ///   'data': {
  ///     'branch_id': 60,
  ///     'backend_url': 'https://portal.hermosaapp.com',
  ///     'auth_token': 'bearer_token_here'
  ///   }
  /// }
  Future<void> saveInitData(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? readString(dynamic value) {
        final text = value?.toString().trim();
        if (text == null || text.isEmpty) return null;
        return text;
      }

      final rawBranch = data['branch_id'];
      if (rawBranch is int) {
        _branchId = rawBranch;
      } else if (rawBranch is String) {
        _branchId = int.tryParse(rawBranch);
      } else if (rawBranch is double) {
        _branchId = rawBranch.toInt();
      }
      _backendUrl = _normalizeBackendUrl(data['backend_url']?.toString());
      _authToken = data['auth_token']?.toString();
      final environment = _resolveSdkEnvironment();
      final environmentLabel = environment.name;
      // Accept terminal data if provided by Cashier
      _tid =
          readString(data['terminal_tid']) ??
          readString(data['terminalTid']) ??
          readString(data['tid']) ??
          _tid;
      _terminalUuid =
          readString(data['terminal_id']) ??
          readString(data['terminalId']) ??
          readString(data['terminal_uuid']) ??
          readString(data['terminalUUID']) ??
          readString(data['id']) ??
          _terminalUuid;

      final terminalMap = data['terminal'];
      if (terminalMap is Map) {
        _tid =
            readString(terminalMap['terminal_tid']) ??
            readString(terminalMap['terminalTid']) ??
            readString(terminalMap['tid']) ??
            _tid;
        _terminalUuid =
            readString(terminalMap['terminal_id']) ??
            readString(terminalMap['terminalId']) ??
            readString(terminalMap['terminal_uuid']) ??
            readString(terminalMap['terminalUUID']) ??
            readString(terminalMap['id']) ??
            _terminalUuid;
      }
      _apiService = null;

      // If Cashier payload doesn't include terminal IDs, fetch once from backend now.
      // This avoids NOT_SET/MISSING state before the full initialization flow starts.
      if ((_tid == null || _terminalUuid == null) &&
          _branchId != null &&
          _backendUrl != null &&
          _authToken != null &&
          _authToken!.isNotEmpty) {
        try {
          _npLog(
            'ℹ️ terminal_tid/terminal_id missing in init payload — '
            'fetching from backend config endpoint...',
          );
          final api = _requireApiService();
          final config = await api.fetchTerminalConfig();
          _tid = config.terminalTid;
          _terminalUuid = config.terminalId;
          _npLog(
            '✅ Terminal IDs preloaded from backend config '
            '(tid=${_maskId(_tid)}, id=${_maskId(_terminalUuid)})',
          );
        } catch (e) {
          _npLog('⚠️ Could not preload terminal IDs from backend: $e');
        }
      }

      // Persist to storage for recovery
      if (_branchId != null) {
        await prefs.setInt('np_branch_id', _branchId!);
      }
      if (_backendUrl != null) {
        await prefs.setString('np_backend_url', _backendUrl!);
      }
      if (_authToken != null) {
        await prefs.setString('np_auth_token', _authToken!);
      }
      if (_tid != null) {
        await prefs.setString('np_terminal_tid', _tid!);
      }
      if (_terminalUuid != null) {
        await prefs.setString('np_terminal_uuid', _terminalUuid!);
      }
      await prefs.setString(
        'np_google_project_number',
        NearPayConfigService.googleCloudProjectNumber.toString(),
      );
      await prefs.setString('np_environment', environmentLabel);

      _npLog('✅ Init data saved');
      _npLog('   → branch_id: $_branchId');
      _npLog('   → backend_url: $_backendUrl');
      _npLog('   → auth_token: ${_mask(_authToken)}');
      _npLog('   → terminal_tid: ${_tid ?? "NOT_SET"}');
      _npLog('   → terminal_id: ${_mask(_terminalUuid)}');
      _npLog('   → sdk_environment: $environmentLabel');
    } catch (e) {
      _npLog('❌ Error saving init data: $e', error: e);
      rethrow;
    }
  }

  Future<void> _initializeSdkIfNeeded() async {
    final nearPayConfig = NearPayConfigService();
    if (_sdk != null && nearPayConfig.isSdkInitialized) return;
    if (_sdk != null && !nearPayConfig.isSdkInitialized) {
      _sdk = null;
    }

    _npLog('🔄 Starting NearPay SDK Initialization...');
    _npLogDetail('SDK Init Start', {
      'time': DateTime.now().toIso8601String(),
      'kDebugMode': '$kDebugMode',
      'kReleaseMode': '$kReleaseMode',
    });

    await _logDeveloperCertLoaded();

    _npLogDetail('NearPay Config Status', nearPayConfig.getStatusSummary());

    try {
      _npLog('⏳ Checking NFC availability...');
      final nfcAvailable = await nearPayConfig.isNfcAvailable;
      final nfcEnabled = await nearPayConfig.isNfcEnabled;

      _npLogDetail('NFC Status', {
        'available': '$nfcAvailable',
        'enabled': '$nfcEnabled',
        'required': 'true (NearPay needs NFC to read cards)',
      });

      nearPayConfig.markNfcStatus(available: nfcAvailable, enabled: nfcEnabled);

      if (!nfcAvailable) {
        _npLog('❌ CRITICAL: Device has NO NFC hardware - NearPay cannot work');
        _npLog('   → This device cannot process payments via NearPay');
        throw Exception(
          'NFC hardware not available — NearPay requires NFC to read cards',
        );
      }

      if (!nfcEnabled) {
        _npLog('⚠️ WARNING: NFC is available but disabled');
        _npLog('   → User must enable NFC in Settings');
      }
    } catch (e, stackTrace) {
      _npLog('❌ NFC status check failed: $e', error: e, stackTrace: stackTrace);
      rethrow;
    }

    _sdk = FlutterTerminalSdk();

    final environment = _resolveSdkEnvironment();
    final envLabel = environment.name.toUpperCase();
    _lastSdkEnvironment = envLabel;

    _npLogDetail('SDK Environment Configuration', {
      'environment': envLabel,
      'kReleaseMode': '$kReleaseMode',
      'country': NearPayConfigService.country,
      'googleCloudProjectNumber': NearPayConfigService.googleCloudProjectNumber
          .toString(),
      'appId': NearPayConfigService.androidApplicationId,
    });

    const huaweiSafetyDetectApiKey = '';

    _npLogDetail('SDK Init Parameters', {
      'env': environment.toString(),
      'country': NearPayConfigService.country,
      'gcp': NearPayConfigService.googleCloudProjectNumber.toString(),
      'appId': NearPayConfigService.androidApplicationId,
      'huaweiKey': _mask(huaweiSafetyDetectApiKey),
      'release': kReleaseMode.toString(),
      'debug': kDebugMode.toString(),
    });

    final initListener = TerminalSDKInitializationListener(
      onInitializationFailure: (error) {
        _npLog('❌ SDK initialization callback FAILED');
        _npLogDetail('SDK Init Failure Details', {
          'error': error.toString(),
          'timestamp': DateTime.now().toIso8601String(),
        });
      },
      onInitializationSuccess: () {
        _npLog('✅ SDK initialization callback SUCCESS');
        _npLogDetail('SDK Init Success', {
          'timestamp': DateTime.now().toIso8601String(),
          'environment': envLabel,
        });
      },
    );

    // Mirror the NearPay reader UI onto the customer-facing secondary
    // screen when one is attached (e.g. Sunmi D2s / D3 mini). When no
    // secondary display is present we keep the SDK single-display so the
    // customer dock doesn't sit on the wrong screen.
    final hasSecondDisplay = PresentationService().hasSecondaryDisplay;
    final supportSecond = hasSecondDisplay
        ? SupportSecondDisplay.enable
        : SupportSecondDisplay.disable;
    final secondDock =
        hasSecondDisplay ? UiDockPosition.BOTTOM_CENTER : null;

    _npLogDetail('SDK Display Configuration', {
      'hasSecondaryDisplay': hasSecondDisplay.toString(),
      'supportSecondDisplay': supportSecond.name,
      'uiDockPosition': 'BOTTOM_CENTER',
      'secondDisplayDockPosition': secondDock?.name ?? 'NONE',
    });

    try {
      final initStartTime = DateTime.now();
      _npLog('⏳ Calling SDK.initialize() - this may take 5-30 seconds...');

      await _sdk!.initialize(
        environment: environment,
        googleCloudProjectNumber: NearPayConfigService.googleCloudProjectNumber,
        huaweiSafetyDetectApiKey: huaweiSafetyDetectApiKey,
        country: Country.sa, // ✅ Saudi Arabia (NOT Turkey)
        initializationListener: initListener,
        // UI Dock Position - NearPay Reader UI will appear at bottom center
        uiDockPosition: UiDockPosition.BOTTOM_CENTER,
        secondDisplayDockPosition: secondDock,
        supportSecondDisplay: supportSecond,
      );

      final initEndTime = DateTime.now();
      final initDuration = initEndTime.difference(initStartTime);

      _npLog('✅ SDK initialization completed successfully');
      _npLogDetail('SDK Init Timing', {
        'duration_ms': initDuration.inMilliseconds.toString(),
        'started_at': initStartTime.toIso8601String(),
        'completed_at': initEndTime.toIso8601String(),
        'ui_dock_position': 'BOTTOM_CENTER',
      });

      nearPayConfig.markSdkInitialized();

      _npLog('✅ NearPay SDK fully initialized for country: SA');
    } catch (e, stackTrace) {
      _npLogDetail('SDK Initialization FAILED', {
        'error_type': e.runtimeType.toString(),
        'error_message': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      });

      _npLog('❌ SDK initialize failed: $e', error: e, stackTrace: stackTrace);

      // Provide detailed network error information
      if (e.toString().contains('SocketTimeoutException')) {
        _npLog('🔴 NETWORK TIMEOUT - Cannot reach NearPay servers');
        _npLogDetail('Network Error Details', {
          'error_type': 'SocketTimeoutException',
          'possible_causes': 'Firewall, DNS, IP blocked, or slow network',
          'timeout_ms': '15000',
          'advice':
              'Check device internet, firewall settings, or contact NearPay support',
        });
      } else if (e.toString().contains('No network')) {
        _npLog('🔴 NO NETWORK - Device is not connected to internet');
        _npLogDetail('Network Error Details', {
          'error_type': 'No Network',
          'advice': 'Check WiFi or mobile data connection',
        });
      }

      rethrow;
    }
  }

  /// Fetch JWT token from backend API
  ///
  /// POST /seller/nearpay/auth/token
  /// Body: {"branch_id": 60, "terminal_tid": "021...", "terminal_id": "890..."}
  ///
  /// The terminal_tid and terminal_id are populated by [_fetchTerminalData]
  /// which MUST run before this method.
  ///
  /// Response: {
  ///   "success": true,
  ///   "data": {
  ///     "token": "eyJ...",
  ///     "expires_at": 1773400778,
  ///     "expires_in": 3600
  ///   }
  /// }
  Future<NearPayJwtPayload> _fetchJwtPayload() async {
    try {
      final api = _requireApiService();
      final jwtStartTime = DateTime.now();

      _npLog('🔄 Fetching JWT token...');
      _npLogDetail('JWT Request Start', {
        'endpoint': '${api.baseUrl}/seller/nearpay/auth/token',
        'method': 'POST',
        'branch_id': '$_branchId',
        'terminal_tid': _tid ?? 'NOT_SET',
        'terminal_id': _terminalUuid ?? 'NOT_SET',
        'timestamp': jwtStartTime.toIso8601String(),
      });

      final payload = await api.fetchJwtToken(
        terminalTid: _tid,
        terminalId: _terminalUuid,
      );
      final jwtEndTime = DateTime.now();
      final jwtDuration = jwtEndTime.difference(jwtStartTime);

      final jwtClientUuid = payload.clientUuid?.trim();
      if (jwtClientUuid != null && jwtClientUuid.isNotEmpty) {
        if (_userUuid != null &&
            _userUuid!.isNotEmpty &&
            _userUuid != jwtClientUuid) {
          _npLog(
            'ℹ️ Replacing cached userUUID with JWT client_uuid '
            '(cached=${_maskId(_userUuid)}, jwt=${_maskId(jwtClientUuid)})',
          );
        }
        _userUuid = jwtClientUuid;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('np_terminal_user_uuid', jwtClientUuid);
        _npLog('✅ userUUID extracted from JWT payload');
      }

      final expiresAt = payload.expiresAt;
      if (expiresAt != null) {
        _jwtExpiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
      } else if (payload.expiresIn != null) {
        // Store the actual expiry time; _ensureFreshJwt() already subtracts
        // a 5-minute safety buffer when checking.
        _jwtExpiresAt = DateTime.now().add(
          Duration(seconds: payload.expiresIn!),
        );
      } else {
        _jwtExpiresAt = DateTime.now().add(const Duration(minutes: 55));
      }

      _npLog('✅ JWT fetched successfully');
      _npLogDetail('JWT Token Details', {
        'token_length': payload.token.length.toString(),
        'expires_at': _jwtExpiresAt?.toIso8601String() ?? 'UNKNOWN',
        'expires_in_seconds': payload.expiresIn?.toString() ?? 'UNKNOWN',
        'jwt_client_uuid': _maskId(payload.clientUuid),
        'jwt_terminal_id': _maskId(payload.terminalIdInToken),
        'fetch_time_ms': jwtDuration.inMilliseconds.toString(),
        'timestamp': jwtEndTime.toIso8601String(),
      });

      return payload;
    } catch (e, stackTrace) {
      _npLogDetail('JWT Fetch Failed', {
        'error_type': e.runtimeType.toString(),
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      });

      if (e.toString().contains('SocketException')) {
        _npLog('🔴 NETWORK ERROR during JWT fetch');
        _npLogDetail('Network Error - JWT', {
          'error_type': 'SocketException',
          'backend_url': _backendUrl ?? 'UNKNOWN',
          'possible_causes': 'Network unreachable, firewall, DNS issue',
          'advice': 'Check internet connection and backend URL',
        });
      } else if (e.toString().contains('timeout')) {
        _npLog('🔴 TIMEOUT during JWT fetch');
        _npLogDetail('Timeout Error - JWT', {
          'error_type': 'TimeoutException',
          'timeout_seconds': '15-30',
          'advice': 'Network too slow or backend is unresponsive',
        });
      }

      _npLog('❌ Error fetching JWT: $e', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Fetch terminal config from backend API
  ///
  /// GET /seller/nearpay/terminal/config?branch_id={{branch_id}}
  ///
  /// Response: {
  ///   "success": true,
  ///   "data": {
  ///     "terminal_tid": "0211920500119205",
  ///     "terminal_id": "89056584-...",
  ///     "expires_in": "3600",
  ///     "expires_at": "2026-03-24T15:21:09.344576Z"
  ///   }
  /// }
  Future<Map<String, String>> _fetchTerminalData() async {
    try {
      final api = _requireApiService();
      final terminalStartTime = DateTime.now();

      _npLog('🔄 Fetching terminal config...');
      _npLogDetail('Terminal Config Fetch Start', {
        'endpoint':
            '${api.baseUrl}/seller/nearpay/terminal/config?branch_id=$_branchId',
        'method': 'GET',
        'branch_id': '$_branchId',
        'timestamp': terminalStartTime.toIso8601String(),
      });

      final config = await api.fetchTerminalConfig();
      final terminalDuration = DateTime.now().difference(terminalStartTime);

      _npLog('✅ Terminal config fetched');
      _npLogDetail('Terminal Config Details', {
        'terminal_tid': _maskId(config.terminalTid),
        'terminal_id': _maskId(config.terminalId),
        'expires_in': config.expiresIn?.toString() ?? 'NULL',
        'fetch_time_ms': terminalDuration.inMilliseconds.toString(),
      });

      _tid = config.terminalTid;
      _terminalUuid = config.terminalId;

      String? backendUserUuid;
      try {
        backendUserUuid = await api.fetchTerminalUserUuid(
          terminalId: config.terminalId,
          terminalTid: config.terminalTid,
        );
      } catch (e) {
        _npLog(
          '⚠️ Could not fetch terminal user_uuid from terminals endpoint: $e',
        );
      }

      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('np_terminal_tid', _tid!);
      await prefs.setString('np_terminal_uuid', _terminalUuid!);
      if (_userUuid != null && _userUuid!.isNotEmpty) {
        await prefs.setString('np_terminal_user_uuid', _userUuid!);
      }
      if (backendUserUuid != null && backendUserUuid.isNotEmpty) {
        await prefs.setString('np_backend_user_uuid', backendUserUuid);
      }

      final result = <String, String>{
        'tid': config.terminalTid,
        'terminalUUID': config.terminalId,
      };
      if (backendUserUuid != null && backendUserUuid.isNotEmpty) {
        result['userUUID'] = backendUserUuid;
      }
      return result;
    } catch (e) {
      _npLog('⚠️ Terminal config fetch failed: $e — trying saved data');
    }

    // Fallback: use saved terminal data from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final savedTid = _tid ?? prefs.getString('np_terminal_tid');
    final savedUuid = _terminalUuid ?? prefs.getString('np_terminal_uuid');
    final savedUserUuid = _userUuid ?? prefs.getString('np_terminal_user_uuid');

    if (savedTid != null && savedUuid != null) {
      _npLog('✅ Using saved terminal data');
      _npLogDetail('Saved Terminal Details', {
        'tid': _maskId(savedTid),
        'uuid': _maskId(savedUuid),
        'user_uuid': _maskId(savedUserUuid),
        'source': 'SharedPreferences',
      });
      _tid = savedTid;
      _terminalUuid = savedUuid;
      if (savedUserUuid != null && savedUserUuid.isNotEmpty) {
        _userUuid = savedUserUuid;
      }
      final result = <String, String>{
        'tid': savedTid,
        'terminalUUID': savedUuid,
      };
      if (savedUserUuid != null && savedUserUuid.isNotEmpty) {
        result['userUUID'] = savedUserUuid;
      }
      return result;
    }

    _npLog('❌ No terminal data available — API failed and no saved data');
    throw Exception(
      'No terminal data available. Terminal endpoint returned error and '
      'no saved terminal data found. Please contact support.',
    );
  }

  /// Initialize NearPay SDK completely
  ///
  /// Steps:
  /// 1. Initialize SDK with Saudi Arabia configuration
  /// 2. Fetch terminal config from backend (sets _tid / _terminalUuid)
  /// 3. Fetch JWT token from backend (sends terminal_tid & terminal_id)
  /// 4. Login with JWT to get terminal model (contains user data)
  /// 5. Connect to terminal
  Future<void> initialize() async {
    final inFlight = _initializeInFlight;
    if (inFlight != null) {
      _npLog('⏳ NearPay initialize already running — joining existing task');
      await inFlight;
      return;
    }

    final pending = _doInitialize();
    _initializeInFlight = pending;
    try {
      await pending;
    } finally {
      if (identical(_initializeInFlight, pending)) {
        _initializeInFlight = null;
      }
    }
  }

  Future<void> _doInitialize() async {
    final initStartTime = DateTime.now();
    const buildTag = String.fromEnvironment(
      'NEARPAY_BUILD_TAG',
      defaultValue: 'unset',
    );
    _isReady = false;

    _npLog('═══════════════════════════════════════════════════════════');
    _npLog('🚀 NEARPAY COMPLETE INITIALIZATION STARTED');
    _npLog('═══════════════════════════════════════════════════════════');

    _npLogDetail('Initialization Start', {
      'timestamp': initStartTime.toIso8601String(),
      'build_tag': buildTag,
      'branch_id': '$_branchId',
      'backend_url': _backendUrl ?? 'NOT SET',
      'has_auth_token': '${_authToken != null && _authToken!.isNotEmpty}',
    });

    try {
      // Step 1: Initialize SDK
      _npLog('📍 STEP 1/5: Initializing NearPay SDK...');
      final step1StartTime = DateTime.now();
      await _initializeSdkIfNeeded();
      final step1Duration = DateTime.now().difference(step1StartTime);
      _npLogDetail('Step 1 Complete', {
        'duration_ms': step1Duration.inMilliseconds.toString(),
        'sdk_initialized': '${_sdk != null}',
      });

      // Step 2: Fetch terminal data from backend (needed for JWT request)
      _npLog('📍 STEP 2/5: Fetching terminal data from backend...');
      final step2StartTime = DateTime.now();
      final terminalData = await _fetchTerminalData();
      final step2Duration = DateTime.now().difference(step2StartTime);
      _npLogDetail('Step 2 Complete - Terminal Data', {
        'duration_ms': step2Duration.inMilliseconds.toString(),
        'tid': _maskId(terminalData['tid']),
        'terminal_uuid': _maskId(terminalData['terminalUUID']),
        'result': '✅',
      });

      // Step 3: Fetch JWT token (now includes terminal_tid & terminal_id)
      _npLog('📍 STEP 3/5: Fetching JWT token from backend...');
      final step3StartTime = DateTime.now();
      final jwtPayload = await _fetchJwtPayload();
      final jwt = jwtPayload.token;
      final step3Duration = DateTime.now().difference(step3StartTime);
      _npLogDetail('Step 3 Complete', {
        'duration_ms': step3Duration.inMilliseconds.toString(),
        'jwt_obtained': '✅',
      });

      // Step 4: Login with JWT
      _npLog('📍 STEP 4/5: Logging in with JWT token...');
      final step4StartTime = DateTime.now();

      // Log JWT details for debugging (first/last chars only — no secrets)
      final jwtPreview = jwt.length > 20
          ? '${jwt.substring(0, 10)}...${jwt.substring(jwt.length - 10)}'
          : '(too short!)';
      _npLogDetail('Step 4 - JWT Token Info', {
        'jwt_length': jwt.length.toString(),
        'jwt_preview': jwtPreview,
        'jwt_parts': jwt.split('.').length.toString(),
        'header': jwt.split('.').isNotEmpty
            ? _safeBase64Decode(jwt.split('.')[0])
            : 'MISSING',
        'payload_keys': jwt.split('.').length > 1
            ? _safePayloadKeys(jwt.split('.')[1])
            : 'MISSING',
        'has_signature':
            (jwt.split('.').length == 3 && jwt.split('.')[2].isNotEmpty)
                .toString(),
      });

      TerminalModel terminalModel;
      try {
        _npLog('⏳ Calling SDK jwtLogin()...');
        terminalModel = await _jwtLoginWithLock(jwt);
        final step4Duration = DateTime.now().difference(step4StartTime);
        _npLogDetail('Step 4 Complete - JWT Login', {
          'duration_ms': step4Duration.inMilliseconds.toString(),
          'user_uuid': _maskId(terminalModel.client),
          'terminal_tid': terminalModel.tid ?? 'NULL',
          'terminal_uuid': _maskId(terminalModel.terminalUUID),
          'terminal_name': terminalModel.name ?? 'NULL',
          'result': '✅',
        });
      } catch (e, stackTrace) {
        final step4Duration = DateTime.now().difference(step4StartTime);
        _npLogDetail('Step 4 FAILED - JWT Login Error', {
          'duration_ms': step4Duration.inMilliseconds.toString(),
          'error': e.toString(),
          'error_type': e.runtimeType.toString(),
          'error_message_contains_network': e
              .toString()
              .toLowerCase()
              .contains('network')
              .toString(),
          'error_message_contains_timeout': e
              .toString()
              .toLowerCase()
              .contains('timeout')
              .toString(),
          'error_message_contains_unauthorized': e
              .toString()
              .toLowerCase()
              .contains('unauthorized')
              .toString(),
          'error_message_contains_developer': e
              .toString()
              .toLowerCase()
              .contains('developer')
              .toString(),
          'jwt_length': jwt.length.toString(),
          'sdk_initialized': (_sdk != null).toString(),
          'timestamp': DateTime.now().toIso8601String(),
        });
        _npLog(
          '❌ JWT login failed after ${step4Duration.inMilliseconds}ms: $e',
          error: e,
          stackTrace: stackTrace,
        );
        rethrow;
      }

      final modelClient = terminalModel.client?.trim();
      _npLogDetail('Step 4 - jwtLogin Result Analysis', {
        'terminalModel.client': modelClient ?? 'NULL',
        'terminalModel.tid': terminalModel.tid ?? 'NULL',
        'terminalModel.terminalUUID': terminalModel.terminalUUID ?? 'NULL',
        'terminalModel.name': terminalModel.name ?? 'NULL',
        '_userUuid_before': _userUuid ?? 'NULL',
      });

      if (modelClient != null && modelClient.isNotEmpty) {
        await _persistUserUuid(modelClient);
        _npLog(
          '✅ JWT login successful - userUUID obtained from sdk: ${_maskId(modelClient)}',
        );
      } else {
        _npLog(
          '⚠️ jwtLogin returned empty client — SDK has NO registered users',
        );
        _npLog(
          'ℹ️ keeping existing userUUID from JWT payload: ${_maskId(_userUuid)}',
        );
      }

      // Probe: call getUsers() from Dart side to confirm SDK user state
      try {
        final sdkUsers = await _sdk!.getUsers();
        _npLogDetail('Step 4 - SDK getUsers() Probe (Dart side)', {
          'user_count': sdkUsers.length.toString(),
          'users': sdkUsers.map((u) => '${u.userUUID}|${u.name}').join(', '),
        });
        if (sdkUsers.isNotEmpty &&
            (modelClient == null || modelClient.isEmpty)) {
          final firstUser = sdkUsers.first;
          if (firstUser.userUUID != null && firstUser.userUUID!.isNotEmpty) {
            await _persistUserUuid(firstUser.userUUID);
            _npLog(
              '✅ Got userUUID from getUsers() fallback: ${_maskId(_userUuid)}',
            );
          }
        }
      } catch (e) {
        _npLog('⚠️ getUsers() probe failed: $e');
      }

      // Keep backend terminal IDs authoritative. jwtLogin can return a dynamic
      // UUID that does not match /terminal/config terminal_id.
      if (terminalModel.tid != null) _tid = terminalModel.tid;
      if (_terminalUuid == null && terminalModel.terminalUUID != null) {
        _terminalUuid = terminalModel.terminalUUID;
      } else if (terminalModel.terminalUUID != null &&
          _terminalUuid != null &&
          terminalModel.terminalUUID != _terminalUuid) {
        _npLog(
          'ℹ️ jwtLogin returned a different terminalUUID; keeping backend '
          'terminal_id for connectTerminal '
          '(backend=${_maskId(_terminalUuid)}, jwt=${_maskId(terminalModel.terminalUUID)})',
        );
      }
      final prefs = await SharedPreferences.getInstance();
      if (_tid != null) await prefs.setString('np_terminal_tid', _tid!);
      if (_terminalUuid != null) {
        await prefs.setString('np_terminal_uuid', _terminalUuid!);
      }
      if (_userUuid != null) {
        await prefs.setString('np_terminal_user_uuid', _userUuid!);
      }

      // Step 5: Use the terminal returned by jwtLogin directly.
      // jwtLogin already returns a ready Terminal — no need to resolve a
      // User or call connectTerminal (the SDK does not register a User
      // during JWT auth, so getUserByUUID would always fail).
      _npLog('📍 STEP 5/5: Using terminal from jwtLogin...');
      _connectedTerminal = terminalModel;

      // Wait for the terminal to finish its internal initialization
      // (key loading, server handshake, etc.).
      _npLog('⏳ Waiting for terminal to become ready...');
      const maxWait = Duration(seconds: 60);
      const pollInterval = Duration(seconds: 2);
      final waitStart = DateTime.now();
      bool terminalReady = false;
      while (DateTime.now().difference(waitStart) < maxWait) {
        try {
          terminalReady = await terminalModel.isTerminalReady();
          if (terminalReady) break;
        } catch (e) {
          _npLog('⚠️ isTerminalReady() check failed: $e');
        }
        await Future<void>.delayed(pollInterval);
      }

      _npLogDetail('Step 5 Complete - Terminal from jwtLogin', {
        'tid': _tid ?? 'NULL',
        'terminal_uuid': _maskId(_terminalUuid),
        'terminal_name': terminalModel.name ?? 'NULL',
        'terminal_ready': terminalReady.toString(),
        'wait_ms': DateTime.now()
            .difference(waitStart)
            .inMilliseconds
            .toString(),
        'result': terminalReady ? '✅' : '⚠️ not ready',
      });

      if (!terminalReady) {
        _npLog(
          '⚠️ Terminal did not become ready within ${maxWait.inSeconds}s — continuing anyway',
        );
      }

      _isReady = true;
      final initTotalDuration = DateTime.now().difference(initStartTime);

      _npLog('═══════════════════════════════════════════════════════════');
      _npLog('✅✅✅ NEARPAY INITIALIZATION COMPLETE ✅✅✅');
      _npLog('═══════════════════════════════════════════════════════════');

      _npLogDetail('Initialization Summary', {
        'total_time_ms': initTotalDuration.inMilliseconds.toString(),
        'status': '🟢 READY',
        'terminal_id': _maskId(_tid),
        'user_uuid': _maskId(_userUuid),
        'nfc_available': '✅',
        'sdk_version': 'NearPay Terminal SDK',
        'environment': _lastSdkEnvironment,
        'completed_at': DateTime.now().toIso8601String(),
      });
    } catch (e, stackTrace) {
      _isReady = false;

      _npLog('═══════════════════════════════════════════════════════════');
      _npLog('❌❌❌ NEARPAY INITIALIZATION FAILED ❌❌❌');
      _npLog('═══════════════════════════════════════════════════════════');

      _npLogDetail('Initialization Error', {
        'error_type': e.runtimeType.toString(),
        'error_message': e.toString(),
        'total_time_ms': DateTime.now()
            .difference(initStartTime)
            .inMilliseconds
            .toString(),
        'timestamp': DateTime.now().toIso8601String(),
        'status': '🔴 FAILED',
      });

      _npLog(
        '❌ NearPay initialization failed: $e',
        error: e,
        stackTrace: stackTrace,
      );

      // Provide helpful troubleshooting info
      if (e.toString().contains('SocketTimeout') ||
          e.toString().contains('No network')) {
        _npLog('');
        _npLog('💡 TROUBLESHOOTING: Network Connectivity Issue');
        _npLogDetail('Network Troubleshooting', {
          'issue': 'Cannot reach NearPay servers',
          'check_1': 'Device has WiFi/Mobile data enabled',
          'check_2': 'No firewall blocking port 443',
          'check_3': 'DNS is resolving portal.hermosaapp.com',
          'check_4': 'Try connecting to a different network',
          'contact': 'Reach out to NearPay support if issue persists',
        });
      }

      rethrow;
    }
  }

  Future<void> initializeSdkOnly() async {
    await _initializeSdkIfNeeded();
  }

  Future<NearPayJwtPayload> fetchJwtPayloadForHealthCheck() async {
    return _fetchJwtPayload();
  }

  Future<TerminalModel> jwtLoginForHealthCheck(String jwt) async {
    final model = await _jwtLoginWithLock(jwt);
    await _persistUserUuid(model.client);
    return model;
  }

  Future<Map<String, String>> fetchTerminalDataForHealthCheck() async {
    return _fetchTerminalData();
  }

  /// Mark the terminal returned by jwtLogin as the active terminal.
  /// With JWT auth the SDK does not register a User, so connectTerminal
  /// (which calls getUserByUUID) will always fail.  Instead we reuse the
  /// TerminalModel that jwtLogin already gave us.
  void applyTerminalForHealthCheck({
    required TerminalModel terminal,
    required String terminalId,
    required String terminalUUID,
  }) {
    _tid = terminalId;
    _terminalUuid = terminalUUID;
    _connectedTerminal = terminal;
    _isReady = true;
  }

  /// Ensure JWT is fresh before processing payment
  Future<void> _ensureFreshJwt() async {
    if (_jwtExpiresAt != null &&
        DateTime.now().isBefore(
          _jwtExpiresAt!.subtract(const Duration(minutes: 5)),
        )) {
      return;
    }
    _npLog('🔄 JWT expired or missing — refreshing...');
    if (_sdk == null) {
      await initialize();
      return;
    }
    final jwtPayload = await _fetchJwtPayload();
    final jwt = jwtPayload.token;
    final terminalModel = await _jwtLoginWithLock(jwt);
    await _persistUserUuid(terminalModel.client);

    _connectedTerminal = terminalModel;

    // Wait for terminal readiness after JWT refresh
    const maxWait = Duration(seconds: 30);
    const pollInterval = Duration(seconds: 2);
    final waitStart = DateTime.now();
    while (DateTime.now().difference(waitStart) < maxWait) {
      try {
        if (await terminalModel.isTerminalReady()) break;
      } catch (_) {}
      await Future<void>.delayed(pollInterval);
    }
    _isReady = _connectedTerminal != null;
  }

  Future<bool> ensureReady() async {
    if (_isReady && _connectedTerminal != null) return true;
    final config = NearPayConfigService();
    final shouldInit = await config.shouldInitializeSdk;
    if (!shouldInit) {
      _npLog('NearPay ensureReady failed: shouldInitializeSdk=false');
      return false;
    }
    try {
      await initialize();
      return _isReady && _connectedTerminal != null;
    } catch (e, stackTrace) {
      _npLog(
        'NearPay ensureReady failed: $e',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<bool> initializeAndConnect() async {
    return ensureReady();
  }

  Future<NearPayPurchaseSession> createPurchaseSession({
    required double amount,
    required String referenceId,
  }) async {
    final api = _requireApiService();
    final amountInHalalas = (amount * 100).round();
    _npLog(
      'Creating NearPay session: amount=$amountInHalalas halalas '
      'reference=$referenceId',
    );
    final session = await api.createPurchaseSession(
      amountInHalalas: amountInHalalas,
      referenceId: referenceId,
    );
    _npLog('✅ Session created: ${session.sessionId}');
    return session;
  }

  /// Get session status from backend
  Future<Map<String, dynamic>> getSessionStatus({
    required String terminalId,
    required String sessionId,
  }) async {
    final api = _requireApiService();
    _npLog('Getting session status: terminal=$terminalId session=$sessionId');
    final status = await api.getSessionStatus(
      terminalId: terminalId,
      sessionId: sessionId,
    );
    _npLog('✅ Session status retrieved: ${status['status']}');
    return status;
  }

  Future<NearPayPaymentResult> executePurchase({
    required double amount,
    required String sessionId,
    required String referenceId,
    required Function(String status) onStatusUpdate,
  }) async {
    _npLog('🔍 executePurchase called: amount=$amount session=$sessionId');
    _npLog(
      '🔍 _paymentInFlight=$_paymentInFlight _isReady=$_isReady _connectedTerminal=${_connectedTerminal != null ? "SET(uuid=${_connectedTerminal!.terminalUUID})" : "NULL"}',
    );
    if (_paymentInFlight) {
      _npLog('⚠️ executePurchase BLOCKED — _paymentInFlight=true');
      return NearPayPaymentResult.failure(
        referenceId: referenceId,
        message: 'عملية دفع أخرى قيد التنفيذ',
      );
    }
    _paymentInFlight = true;
    final completer = Completer<NearPayPaymentResult>();

    try {
      _npLog('🔍 Calling purchase()...');
      await purchase(
        amount: amount,
        intentUUID: sessionId,
        customerReferenceNumber: referenceId,
        onStatusUpdate: onStatusUpdate,
        onSuccess: (transactionId) {
          if (!completer.isCompleted) {
            completer.complete(
              NearPayPaymentResult.success(
                referenceId: referenceId,
                transactionId: transactionId,
                amount: amount,
              ),
            );
          }
        },
        onFailure: (message) {
          if (!completer.isCompleted) {
            completer.complete(
              NearPayPaymentResult.failure(
                referenceId: referenceId,
                message: message,
              ),
            );
          }
        },
      );
    } catch (e) {
      _npLog('❌ executePurchase EXCEPTION: $e');
      _paymentInFlight = false;
      return NearPayPaymentResult.failure(
        referenceId: referenceId,
        message: e.toString(),
      );
    }

    NearPayPaymentResult result;
    try {
      result = await completer.future.timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          return NearPayPaymentResult.failure(
            referenceId: referenceId,
            message: 'انتهت مهلة عملية الدفع',
          );
        },
      );
    } finally {
      _paymentInFlight = false;
    }
    return result;
  }

  /// Execute purchase with session ID from backend
  /// This is an alias for executePurchase that uses sessionId as intentUUID
  Future<NearPayPaymentResult> executePurchaseWithSession({
    required double amount,
    required String sessionId,
    required String referenceId,
    required Function(String status) onStatusUpdate,
  }) async {
    return executePurchase(
      amount: amount,
      sessionId: sessionId,
      referenceId: referenceId,
      onStatusUpdate: onStatusUpdate,
    );
  }

  /// Process a payment transaction
  ///
  /// [amount] - Payment amount in SAR
  /// [onSuccess] - Called with transaction ID on success
  /// [onFailure] - Called with error message on failure
  /// [onStatusUpdate] - Called with status updates during payment
  Future<void> purchase({
    required double amount,
    required String intentUUID,
    String? customerReferenceNumber,
    required Function(String transactionId) onSuccess,
    required Function(String message) onFailure,
    required Function(String status) onStatusUpdate,
  }) async {
    if (!_isReady || _connectedTerminal == null) {
      throw Exception('NearPay not ready — call initialize() first');
    }

    await _ensureFreshJwt();

    final transactionUuid = intentUUID.trim().isNotEmpty
        ? intentUUID.trim()
        : DateTime.now().millisecondsSinceEpoch.toString();
    final reference = customerReferenceNumber?.trim();
    final amountInCents = (amount * 100).round(); // Convert to halalas

    if (amount <= 1 && amountInCents <= 100) {
      _npLog(
        '⚠️ Amount looks very small. Verify units (SAR vs halalas). '
        'amount=$amount, halalas=$amountInCents',
      );
    }

    bool anyCallback = false;
    bool terminalOutcomeFired = false;
    bool purchaseResolved = false;
    Timer? noCallbackTimer;
    // Watchdog that runs after the user dismisses the NearPay reader UI. When
    // the user presses Cancel the native SDK fires onReaderDismissed /
    // onReaderClosed but NEVER fires onTransactionPurchaseCompleted or
    // onSendTransactionFailure. Without this watchdog the outer Completer
    // would sit idle until its 120s timeout, keeping _paymentInFlight=true
    // and blocking every new payment attempt with "عملية دفع أخرى قيد التنفيذ".
    Timer? cancelWatchdog;
    void flagCallback() {
      if (!anyCallback) {
        anyCallback = true;
        noCallbackTimer?.cancel();
      }
    }

    void resolveWithFailure(String message) {
      if (purchaseResolved) return;
      purchaseResolved = true;
      cancelWatchdog?.cancel();
      onFailure(message);
    }

    void resolveWithSuccess(String transactionId) {
      if (purchaseResolved) return;
      purchaseResolved = true;
      cancelWatchdog?.cancel();
      onSuccess(transactionId);
    }

    noCallbackTimer = Timer(const Duration(seconds: 20), () {
      if (!anyCallback) {
        _npLog('⚠️ No NearPay callbacks fired within 20s of purchase()');
      }
    });

    _npLog('═══════════════════════════════════════════════════════════');
    _npLog('💳 STARTING PAYMENT TRANSACTION');
    _npLog('═══════════════════════════════════════════════════════════');

    _npLogDetail('Payment Details', {
      'amount_sar': '$amount',
      'amount_halalas': '$amountInCents',
      'transaction_uuid': transactionUuid,
      'reference': reference ?? transactionUuid,
      'scheme': 'MADA',
      'timestamp': DateTime.now().toIso8601String(),
    });

    bool nfcAvailable;
    try {
      final availability = await NfcManager.instance.checkAvailability();
      nfcAvailable = availability == NfcAvailability.enabled;
    } catch (e, stackTrace) {
      _npLog(
        '❌ NFC availability check failed: $e',
        error: e,
        stackTrace: stackTrace,
      );
      onFailure('NFC غير مفعّل على هذا الجهاز — فعّله من الإعدادات');
      return;
    }
    if (!nfcAvailable) {
      const message = 'NFC غير مفعّل على هذا الجهاز — فعّله من الإعدادات';
      _npLog('❌ NFC unavailable: aborting purchase');
      onFailure(message);
      return;
    }

    try {
      _npLog('Calling connectedTerminal.purchase()');
      await _connectedTerminal!.purchase(
        intentUUID: transactionUuid,
        amount: amountInCents,
        scheme: PaymentScheme.MADA, // Use MADA scheme for Saudi Arabia
        customerReferenceNumber: reference?.isNotEmpty == true
            ? reference
            : transactionUuid,
        callbacks: PurchaseCallbacks(
          // Card reader callbacks
          cardReaderCallbacks: CardReaderCallbacks(
            onReaderDisplayed: () {
              flagCallback();
              _npLog('callback.onReaderDisplayed (NearPay native UI shown)');
              onStatusUpdate('ظهرت شاشة الدفع - قرّب البطاقة');
            },
            onReaderDismissed: () {
              flagCallback();
              _npLog('callback.onReaderDismissed');
              onStatusUpdate('تم إغلاق شاشة الدفع');
              // Start a short watchdog. If no terminal outcome callback
              // arrives within 2s, treat the dismissal as a user cancel and
              // fail the purchase so the _paymentInFlight flag can reset.
              if (!terminalOutcomeFired && !purchaseResolved) {
                cancelWatchdog?.cancel();
                cancelWatchdog = Timer(const Duration(seconds: 2), () {
                  if (!terminalOutcomeFired && !purchaseResolved) {
                    _npLog(
                      '⏱ Reader dismissed without a terminal outcome — '
                      'treating as user cancel',
                    );
                    resolveWithFailure('تم إلغاء عملية الدفع');
                  }
                });
              }
            },
            onReaderClosed: () {
              flagCallback();
              _npLog('callback.onReaderClosed');
              onStatusUpdate('تم إغلاق شاشة القارئ');
              if (!terminalOutcomeFired && !purchaseResolved) {
                cancelWatchdog ??= Timer(const Duration(seconds: 2), () {
                  if (!terminalOutcomeFired && !purchaseResolved) {
                    _npLog(
                      '⏱ Reader closed without a terminal outcome — '
                      'treating as user cancel',
                    );
                    resolveWithFailure('تم إلغاء عملية الدفع');
                  }
                });
              }
            },
            onReadingStarted: () {
              flagCallback();
              _npLog('callback.onReadingStarted');
              onStatusUpdate('ضع البطاقة');
            },
            onReaderWaiting: () {
              flagCallback();
              _npLog('callback.onReaderWaiting');
              onStatusUpdate('في انتظار البطاقة...');
            },
            onReaderReading: () {
              flagCallback();
              _npLog('callback.onReaderReading');
              onStatusUpdate('جاري القراءة...');
            },
            onPinEntering: () {
              flagCallback();
              _npLog('callback.onPinEntering');
              onStatusUpdate('أدخل الرقم السري');
            },
            onReaderFinished: () {
              flagCallback();
              _npLog('callback.onReaderFinished');
              onStatusUpdate('اكتملت القراءة');
            },
            onReaderRetry: () {
              flagCallback();
              _npLog('callback.onReaderRetry');
              onStatusUpdate('حاول مرة أخرى');
            },
            onReaderError: (msg) {
              flagCallback();
              _npLog('callback.onReaderError: $msg');
              onStatusUpdate('خطأ: $msg');
            },
            onCardReadSuccess: () {
              flagCallback();
              _npLog('callback.onCardReadSuccess');
              onStatusUpdate('تمت قراءة البطاقة ✅');
            },
            onCardReadFailure: (msg) {
              flagCallback();
              _npLog('callback.onCardReadFailure: $msg');
              onStatusUpdate('فشل القراءة: $msg');
            },
          ),
          // Transaction callbacks
          onTransactionPurchaseCompleted: (response) {
            flagCallback();
            terminalOutcomeFired = true;
            cancelWatchdog?.cancel();
            // Extract transaction ID from response
            // Structure: PurchaseResponse -> details -> transactions -> last -> id
            String transactionId = transactionUuid; // Fallback

            try {
              final lastTransaction = response.getLastTransaction();
              if (lastTransaction?.id != null) {
                transactionId = lastTransaction!.id!;
                _npLog('✅ Transaction ID from response: $transactionId');
              } else if (lastTransaction?.referenceId != null) {
                transactionId = lastTransaction!.referenceId!;
                _npLog('✅ Transaction ID from referenceId: $transactionId');
              }
              _npLog(
                'callback.onTransactionPurchaseCompleted '
                'status=${response.status} '
                'lastStatus=${lastTransaction?.status} '
                'amountOther=${lastTransaction?.amountOther}',
              );
            } catch (e) {
              _npLog(
                '⚠️ Could not extract transaction ID from response: $e',
                error: e,
              );
            }

            resolveWithSuccess(transactionId);
          },
          onSendTransactionFailure: (msg) {
            flagCallback();
            terminalOutcomeFired = true;
            cancelWatchdog?.cancel();
            _npLog('callback.onSendTransactionFailure: $msg');
            resolveWithFailure(msg);
          },
        ),
      );
    } catch (e, stackTrace) {
      _npLog('❌ Payment error: $e', error: e, stackTrace: stackTrace);
      cancelWatchdog?.cancel();
      resolveWithFailure('فشل الدفع: ${e.toString()}');
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  RECONCILIATION (per NearPay TerminalSDK documentation)
  // ═════════════════════════════════════════════════════════════════════════

  /// End-of-day reconciliation (تقارير الإقفالية اليومية)
  Future<void> reconcile() async {
    if (!_isReady || _connectedTerminal == null) {
      throw Exception('NearPay not ready');
    }

    await _ensureFreshJwt();
    _npLog('🔄 Starting reconciliation...');

    try {
      await _connectedTerminal!.reconcile();
      _npLog('✅ Reconciliation completed');
    } catch (e, stackTrace) {
      _npLog('❌ Reconciliation failed: $e', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  LOGOUT & RESET (per NearPay TerminalSDK documentation)
  // ═════════════════════════════════════════════════════════════════════════

  /// Reset service state (on logout)
  /// Calls SDK logout per documentation before clearing local state.
  Future<void> reset() async {
    // Call SDK logout if we have a user UUID (per documentation)
    if (_sdk != null && _userUuid != null && _userUuid!.isNotEmpty) {
      try {
        _npLog('🔄 Calling SDK logout for user: ${_maskId(_userUuid)}');
        await _sdk!.logout(uuid: _userUuid!);
        _npLog('✅ SDK logout successful');
      } catch (e) {
        _npLog('⚠️ SDK logout failed (continuing with local reset): $e');
      }
    }

    _sdk = null;
    _connectedTerminal = null;
    _jwtExpiresAt = null;
    _isReady = false;
    _backendUrl = null;
    _authToken = null;
    _branchId = null;
    _tid = null;
    _terminalUuid = null;
    _userUuid = null;
    _apiService = null;
    _paymentInFlight = false;
    _initializeInFlight = null;
    _jwtLoginInFlight = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('np_branch_id');
    await prefs.remove('np_backend_url');
    await prefs.remove('np_auth_token');
    await prefs.remove('np_google_project_number');
    await prefs.remove('np_environment');
    await prefs.remove('np_terminal_tid');
    await prefs.remove('np_terminal_uuid');
    await prefs.remove('np_terminal_user_uuid');

    _npLog('🔄 NearPay service reset');
  }

  /// Get service status for debugging
  Map<String, dynamic> getStatus() {
    return {
      'isReady': _isReady,
      'isInitialized': _sdk != null,
      'hasTerminal': _connectedTerminal != null,
      'branchId': _branchId,
      'backendUrl': _backendUrl,
      'authToken': _authToken != null ? 'PRESENT' : 'MISSING',
      'jwtExpiresAt': _jwtExpiresAt?.toIso8601String(),
      'tid': _tid,
      'terminalUuid': _terminalUuid,
    };
  }
}

class NearPayPaymentResult {
  final bool success;
  final String referenceId;
  final String? transactionId;
  final double? amount;
  final String? errorMessage;

  const NearPayPaymentResult._({
    required this.success,
    required this.referenceId,
    this.transactionId,
    this.amount,
    this.errorMessage,
  });

  factory NearPayPaymentResult.success({
    required String referenceId,
    required String transactionId,
    required double amount,
  }) {
    return NearPayPaymentResult._(
      success: true,
      referenceId: referenceId,
      transactionId: transactionId,
      amount: amount,
    );
  }

  factory NearPayPaymentResult.failure({
    required String referenceId,
    required String message,
  }) {
    return NearPayPaymentResult._(
      success: false,
      referenceId: referenceId,
      errorMessage: message,
    );
  }
}
