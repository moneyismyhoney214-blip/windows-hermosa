// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../display_app_service.dart';

extension DisplayAppServiceLifecycle on DisplayAppService {
  void setCashFloatSnapshot(
    Map<String, dynamic> snapshot, {
    bool sync = true,
  }) {
    _cashFloatSnapshot = Map<String, dynamic>.from(snapshot);
    if (sync && isConnected) {
      unawaited(_sendKdsContext());
    }
  }

  /// Override NearPay availability from `/seller/profile -> options.nearpay`.
  /// `true` enables NearPay support; `false/null` keeps normal capability flow.
  void setProfileNearPayOption(bool enabled) {
    if (_profileNearPayEnabled == enabled) return;
    _profileNearPayEnabled = enabled;
    notifyListeners();
    // If NearPay just became enabled and the WebSocket auth handshake already
    // completed (race: auto-reconnect fired before _loadUserData returned),
    // send a late NEARPAY_INIT so the Display App can bootstrap NearPay now.
    if (enabled && isConnected) {
      unawaited(_sendNearPayInit());
    }
  }

  bool _isCdsLockActive([DateTime? now]) {
    final until = _cdsLockUntil;
    if (until == null) return false;
    final ref = now ?? DateTime.now();
    if (ref.isBefore(until)) return true;
    _cdsLockUntil = null;
    return false;
  }

  void pinCdsModeTemporarily({
    Duration duration = const Duration(seconds: 8),
    bool enforceNow = true,
  }) {
    if (_currentMode == DisplayMode.kds) {
      debugPrint('Skipping CDS pin while the current display session is KDS.');
      return;
    }

    final now = DateTime.now();
    final nextUntil = now.add(duration);
    final currentUntil = _cdsLockUntil;
    if (currentUntil == null || nextUntil.isAfter(currentUntil)) {
      _cdsLockUntil = nextUntil;
    }

    if (!enforceNow) return;
    if (_currentMode != DisplayMode.cds) {
      setMode(DisplayMode.cds);
      return;
    }
    _scheduleCartSync(force: true, delay: const Duration(milliseconds: 120));
  }

  Future<bool> waitUntilConnected({
    Duration timeout = const Duration(seconds: 6),
    Duration pollInterval = const Duration(milliseconds: 150),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (isConnected) return true;
      if (_status == ConnectionStatus.error ||
          _status == ConnectionStatus.disconnected) {
        return false;
      }
      await Future.delayed(pollInterval);
    }
    return isConnected;
  }

  Future<void> connectWithMode(
    String ipAddress, {
    required DisplayMode mode,
    int port = 8080,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    Future<bool> tryConnect(int targetPort) async {
      await connect(ipAddress, port: targetPort);
      return waitUntilConnected(timeout: timeout);
    }

    var ok = await tryConnect(port);

    // Fallback for stale/wrong configured ports in device settings.
    if (!ok && port != 8080) {
      ok = await tryConnect(8080);
    }

    if (!ok) {
      throw Exception('تعذر الاتصال بشاشة العرض');
    }

    setMode(mode, force: true);
  }

  double _toDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  double _resolveTaxRate({
    required double subtotal,
    required double tax,
    double? providedRate,
  }) {
    if (providedRate != null) {
      return providedRate.clamp(0.0, 1.0).toDouble();
    }
    if (subtotal <= 0 || tax <= 0) return 0.0;
    return (tax / subtotal).clamp(0.0, 1.0).toDouble();
  }

  DisplayAppService() {
    _loadSavedConnection();
    translationService.addListener(_handleLanguageChanged);
    _initPresentation();
  }

  /// Initialize the Presentation API for dual-screen devices.
  /// If a secondary display is found, automatically show the customer display.
  Future<void> _initPresentation() async {
    if (_presentationInitialized) return;
    _presentationInitialized = true;

    try {
      await _presentationService.initialize();

      // Listen for meal availability toggles from the secondary display
      _presentationService.onMealAvailabilityToggle = (data) {
        final mealId = data['mealId']?.toString() ?? '';
        final isDisabled = data['isDisabled'] == true;
        if (mealId.isEmpty) return;
        _notifyMealAvailabilityListeners({
          'meal_id': mealId,
          'product_id': data['productId']?.toString() ?? mealId,
          'meal_name': data['mealName']?.toString() ?? 'Meal',
          'category_name': data['categoryName']?.toString(),
          'is_disabled': isDisabled,
        });
      };

      if (_presentationService.hasSecondaryDisplay &&
          !_presentationService.isPresentationShowing) {
        debugPrint('[DisplayApp] Dual-screen device detected, showing presentation');
        await _presentationService.showPresentation();
      }
    } catch (e) {
      debugPrint('[DisplayApp] Presentation init failed (non-fatal): $e');
    }
  }

  String get _currentLanguageCode => translationService.currentLanguageCode;

  void _handleLanguageChanged() {
    final languageCode = _currentLanguageCode;

    // Mirror to secondary display via Presentation API (works even if WebSocket disconnected)
    if (_presentationService.isPresentationShowing) {
      unawaited(_presentationService.setLanguage(languageCode));
    }

    if (!isConnected) return;
    _sendMessage({
      'type': 'LANGUAGE_CHANGED',
      'lang': languageCode,
      'language_code': languageCode,
    });
    if (_lastCartPayload != null) {
      final payload = Map<String, dynamic>.from(_lastCartPayload!);
      final rawData = payload['data'];
      if (rawData is Map<String, dynamic>) {
        payload['data'] = {
          ...rawData,
          'lang': languageCode,
          'language_code': languageCode,
        };
      }
      _lastCartPayload = payload;
      _scheduleCartSync(force: true);
    }
    unawaited(_sendKdsContext());
  }

  /// Load saved device info from SharedPreferences
  Future<void> _loadSavedConnection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString('display_device_id') ?? const Uuid().v4();
      await prefs.setString('display_device_id', _deviceId!);

      _connectedIp = prefs.getString('display_last_ip');
      _connectedPort = prefs.getInt('display_last_port') ?? 8080;
      final shouldAutoReconnect =
          prefs.getBool('display_auto_reconnect') ?? false;

      if (_connectedIp != null) {
        debugPrint('Found saved display device: $_connectedIp');
        if (shouldAutoReconnect) {
          _attemptAutoReconnectToSavedDevice();
        } else {
          debugPrint('Auto-reconnect is disabled for saved display device');
        }
      }
    } catch (e) {
      debugPrint('Error loading saved connection: $e');
      _deviceId = const Uuid().v4();
    }
  }

  void _attemptAutoReconnectToSavedDevice() {
    if (_autoReconnectAttempted) return;
    final savedIp = _connectedIp?.trim() ?? '';
    if (savedIp.isEmpty) return;
    if (_status == ConnectionStatus.connected ||
        _status == ConnectionStatus.connecting ||
        _status == ConnectionStatus.reconnecting) {
      return;
    }

    _autoReconnectAttempted = true;
    final savedPort = _connectedPort;
    Future.delayed(const Duration(milliseconds: 350), () {
      if (_connectedIp?.trim().isEmpty ?? true) return;
      if (_status == ConnectionStatus.connected ||
          _status == ConnectionStatus.connecting ||
          _status == ConnectionStatus.reconnecting) {
        return;
      }
      unawaited(connect(savedIp, port: savedPort));
    });
  }

  /// Save current connection info
  Future<void> _saveConnection(String ip, int port) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('display_last_ip', ip);
      await prefs.setInt('display_last_port', port);
      await prefs.setBool('display_auto_reconnect', true);
    } catch (e) {
      debugPrint('Error saving connection: $e');
    }
  }

  Future<void> _clearSavedConnection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('display_last_ip');
      await prefs.remove('display_last_port');
      await prefs.remove('display_auto_reconnect');
    } catch (e) {
      debugPrint('Error clearing saved connection: $e');
    }
  }

  /// Connection Management with automatic reconnection
  Future<void> connect(String ipAddress, {int port = 8080}) async {
    if (_status == ConnectionStatus.connecting ||
        _status == ConnectionStatus.connected ||
        _status == ConnectionStatus.reconnecting) {
      if (_connectedIp == ipAddress && _connectedPort == port) {
        debugPrint('Already connected to this device, skipping...');
        return;
      } else {
        // Different device, disconnect first
        disconnect();
      }
    }

    _connectedIp = ipAddress;
    _connectedPort = port;
    _errorMessage = null;
    final int connectGeneration = ++_connectGeneration;
    _status = _reconnectAttempts > 0
        ? ConnectionStatus.reconnecting
        : ConnectionStatus.connecting;
    notifyListeners();
    _onConnectionStateChanged?.call(_status);

    // Save for next time
    await _saveConnection(ipAddress, port);

    try {
      final wsUrl = Uri.parse('ws://$ipAddress:$port');
      debugPrint('Connecting to Display App at $wsUrl...');

      final channel = WebSocketChannel.connect(wsUrl);
      await channel.ready.timeout(const Duration(seconds: 5));

      if (connectGeneration != _connectGeneration ||
          _status == ConnectionStatus.disconnected) {
        await channel.sink.close();
        return;
      }

      _channel = channel;
      _logWebSocketConnected(wsUrl.toString());

      // Listen for messages with error handling
      channel.stream.listen(
        (message) => _handleMessage(message),
        onError: (error) {
          if (_channel != channel) return;
          debugPrint('WebSocket error: $error');
          _logWebSocketError(error);
          _handleConnectionError(ErrorHandler.websocketErrorMessage(error));
        },
        onDone: () {
          if (_channel != channel) return;
          debugPrint('WebSocket connection closed');
          _logWebSocketDisconnected();
          _handleConnectionClosed();
        },
      );

      // Timeout for authentication
      Future.delayed(const Duration(seconds: 5), () {
        if (_status == ConnectionStatus.connecting && _authToken == null) {
          _handleConnectionError(
              'انتهت مهلة المصادقة. تأكد من تشغيل تطبيق العرض.');
        }
      });
    } catch (e) {
      debugPrint('Connection error: $e');
      _handleConnectionError(ErrorHandler.websocketErrorMessage(e));
    }
  }
}
