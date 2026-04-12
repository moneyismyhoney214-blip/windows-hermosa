import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'security/security_config.dart';
import 'api/error_handler.dart';
import 'api/api_constants.dart';
import 'api/base_client.dart';
import 'api/order_service.dart';
import '../locator.dart';
import 'api/product_service.dart';
import 'kds_meal_availability_service.dart';
import 'language_service.dart';
import 'nearpay/nearpay_service.dart';
import 'presentation_service.dart';

enum DisplayMode { none, cds, kds }

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
  reconnecting
}

enum PaymentStatus { idle, processing, success, failed, cancelled }

class WebSocketDebugger {
  static int _messagesSent = 0;
  static int _messagesReceived = 0;
  static final Map<String, int> _messageTypesSent = {};
  static final Map<String, int> _messageTypesReceived = {};

  static void logMessageSent(String type) {
    _messagesSent++;
    _messageTypesSent[type] = (_messageTypesSent[type] ?? 0) + 1;
    debugPrint(
      '📤 [Cashier] Message #$_messagesSent sent: $type '
      '(total $type: ${_messageTypesSent[type]})',
    );
  }

  static void logMessageReceived(String type) {
    _messagesReceived++;
    _messageTypesReceived[type] = (_messageTypesReceived[type] ?? 0) + 1;
    debugPrint(
      '📥 [Cashier] Message #$_messagesReceived received: $type '
      '(total $type: ${_messageTypesReceived[type]})',
    );
  }

  static void printStats() {
    debugPrint('📊 [Cashier] ═══════════════════════════════════════');
    debugPrint('📊 [Cashier] WebSocket Statistics:');
    debugPrint('📊 [Cashier]   Messages Sent: $_messagesSent');
    debugPrint('📊 [Cashier]   Messages Received: $_messagesReceived');
    debugPrint('📊 [Cashier]   Sent by type:');
    _messageTypesSent.forEach((type, count) {
      debugPrint('📊 [Cashier]     $type: $count');
    });
    debugPrint('📊 [Cashier]   Received by type:');
    _messageTypesReceived.forEach((type, count) {
      debugPrint('📊 [Cashier]     $type: $count');
    });
    debugPrint('📊 [Cashier] ═══════════════════════════════════════');
  }
}

/// Order ready callback - called when order should be sent to kitchen
typedef OrderReadyCallback = void Function({
  required String orderId,
  required String orderNumber,
  required List<Map<String, dynamic>> items,
  double? total,
  String? note,
});

/// Callback types for payment responses
typedef PaymentSuccessCallback = void Function(
    Map<String, dynamic> transactionData);
typedef PaymentFailedCallback = void Function(String errorMessage);
typedef PaymentCancelledCallback = void Function();
typedef PaymentStatusCallback = void Function(String status, String? message);
typedef ConnectionStateCallback = void Function(ConnectionStatus status);

class DisplayAppService extends ChangeNotifier {
  WebSocketChannel? _channel;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _errorMessage;
  String? _connectedIp;
  int _connectedPort = 8080;
  DisplayMode _currentMode = DisplayMode.none;
  PaymentStatus _paymentStatus = PaymentStatus.idle;

  // Authentication configuration
  String get _authSecret => SecurityConfig.wsSharedSecret;
  String? _deviceId;
  String? _authToken;

  // Reconnection logic
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 60;
  static const Duration reconnectDelay = Duration(seconds: 2);
  int _connectGeneration = 0;

  // Connection health check
  Timer? _pingTimer;
  DateTime? _lastPong;
  static const Duration pingInterval = Duration(seconds: 30);
  static const Duration pongTimeout = Duration(seconds: 10);
  static const Duration staleConnectionThreshold = Duration(minutes: 3);

  // Callbacks
  PaymentSuccessCallback? _onPaymentSuccess;
  PaymentFailedCallback? _onPaymentFailed;
  PaymentCancelledCallback? _onPaymentCancelled;
  PaymentStatusCallback? _onPaymentStatus;
  OrderReadyCallback? _onOrderReady;
  ConnectionStateCallback? _onConnectionStateChanged;
  final List<void Function(Map<String, dynamic>)> _mealAvailabilityListeners =
      [];

  // Store current order data for KDS
  Map<String, dynamic>? _currentOrderData;

  // NearPay capability flag
  bool _supportsNearPay = false;
  bool _profileNearPayEnabled = false;
  Map<String, dynamic>? _cashFloatSnapshot;

  // Presentation API for dual-screen devices (e.g. Sunmi D2s)
  final PresentationService _presentationService = PresentationService();
  bool _presentationInitialized = false;

  // Stronger cart sync state (survives reconnect/mode switching races)
  Map<String, dynamic>? _lastCartPayload;
  String? _lastCartFingerprint;
  DateTime? _lastCartSentAt;
  bool _hasPendingCartSync = false;
  Timer? _cartSyncTimer;
  static const Duration _minCartSyncInterval = Duration(milliseconds: 250);
  final List<Map<String, dynamic>> _outboundQueue = <Map<String, dynamic>>[];
  DateTime? _lastCartAckAt;
  String? _lastOrderAckId;
  DateTime? _lastOrderAckAt;
  bool _autoReconnectAttempted = false;
  DateTime? _cdsLockUntil;
  DisplayMode? _modeBeforePayment;

  ConnectionStatus get status => _status;
  String? get errorMessage => _errorMessage;
  String? get connectedIp => _connectedIp;
  int get connectedPort => _connectedPort;
  DisplayMode get currentMode => _currentMode;
  PaymentStatus get paymentStatus => _paymentStatus;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isConnecting => _status == ConnectionStatus.connecting;
  bool get isReconnecting => _status == ConnectionStatus.reconnecting;
  bool get isPaymentProcessing => _paymentStatus == PaymentStatus.processing;
  int get reconnectAttempts => _reconnectAttempts;
  bool get supportsNearPay =>
      (_supportsNearPay || _profileNearPayEnabled) &&
      _currentMode == DisplayMode.cds;
  DateTime? get lastCartAckAt => _lastCartAckAt;
  String? get lastOrderAckId => _lastOrderAckId;
  DateTime? get lastOrderAckAt => _lastOrderAckAt;
  bool get isCdsModePinned => _isCdsLockActive();

  /// Check if NearPay payment is available
  bool get isNearPayAvailable => isConnected && supportsNearPay;

  /// Whether this device has a built-in secondary display (dual-screen POS).
  bool get isDualScreenDevice => _presentationService.isDualScreenDevice;

  /// Whether the presentation is actively showing on a secondary display.
  bool get isPresentationActive => _presentationService.isPresentationShowing;

  /// The presentation service instance for direct access if needed.
  PresentationService get presentationService => _presentationService;

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

  void _handleConnectionError(String error) {
    _status = ConnectionStatus.error;
    _errorMessage = error;
    if (_lastCartPayload != null) {
      _hasPendingCartSync = true;
    }
    notifyListeners();
    _onConnectionStateChanged?.call(_status);
    _attemptReconnection();
  }

  void _handleConnectionClosed() {
    if (_status != ConnectionStatus.disconnected) {
      _status = ConnectionStatus.disconnected;
      _stopPingTimer();
      if (_lastCartPayload != null) {
        _hasPendingCartSync = true;
      }
      notifyListeners();
      _onConnectionStateChanged?.call(_status);
      _attemptReconnection();
    }
  }

  void _attemptReconnection() {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      debugPrint('Max reconnection attempts reached');
      _errorMessage =
          'فشل الاتصال بعد عدة محاولات. يرجى التحقق من: 1) تشغيل تطبيق العرض 2) نفس شبكة الواي فاي 3) صحة عنوان IP';
      _status = ConnectionStatus.error;
      notifyListeners();
      return;
    }

    _reconnectAttempts++;
    final cappedFactor = _reconnectAttempts.clamp(1, 8);
    final retryDelay = Duration(
      milliseconds: reconnectDelay.inMilliseconds * cappedFactor,
    );
    debugPrint(
        'Attempting reconnection $_reconnectAttempts/$maxReconnectAttempts in ${retryDelay.inSeconds}s...');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(retryDelay, () {
      if (_connectedIp != null) {
        connect(_connectedIp!, port: _connectedPort);
      }
    });
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (timer) {
      _sendPing();
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _sendPing() {
    if (!isConnected) return;

    debugPrint('💓 [Cashier] Sending heartbeat to Display App');
    _sendMessage(
        {'type': 'PING', 'timestamp': DateTime.now().toIso8601String()});

    // Check if we received a pong recently
    if (_lastPong != null) {
      final timeSinceLastPong = DateTime.now().difference(_lastPong!);
      if (timeSinceLastPong > staleConnectionThreshold) {
        debugPrint('Connection appears stale, reconnecting...');
        disconnect(clearEndpoint: false, resetReconnectAttempts: false);
        _attemptReconnection();
      }
    }
  }

  void disconnect({
    bool clearEndpoint = true,
    bool resetReconnectAttempts = true,
  }) {
    _connectGeneration++;
    _reconnectTimer?.cancel();
    _stopPingTimer();
    _cartSyncTimer?.cancel();
    _cartSyncTimer = null;
    _channel?.sink.close();
    _channel = null;
    _status = ConnectionStatus.disconnected;
    if (clearEndpoint) {
      _connectedIp = null;
      _connectedPort = 8080;
      unawaited(_clearSavedConnection());
    }
    _currentMode = DisplayMode.none;
    _paymentStatus = PaymentStatus.idle;
    _currentOrderData = null;
    _modeBeforePayment = null;
    if (resetReconnectAttempts) {
      _reconnectAttempts = 0;
    }
    _authToken = null;
    notifyListeners();
    _onConnectionStateChanged?.call(_status);
    debugPrint('Disconnected from Display App');
    _logWebSocketDisconnected();
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final type = data['type']?.toString();
      if (type != null) {
        WebSocketDebugger.logMessageReceived(type);
      }
      debugPrint('Display App Response: $type');

      switch (type) {
        case 'AUTH_CHALLENGE':
          _handleAuthChallenge(data['challenge']);
          break;

        case 'AUTH_SUCCESS':
          _handleAuthSuccess(data);
          break;

        case 'RECONNECTED':
          debugPrint('Handshake successful: ${data['message']}');
          _handleAuthSuccess(data);
          break;

        case 'CONNECTED':
          debugPrint('Display App ready: ${data['message']}');
          break;

        case 'PONG':
          _lastPong = DateTime.now();
          _onPongReceived();
          break;

        case 'CART_UPDATED':
          _lastCartAckAt = DateTime.now();
          notifyListeners();
          break;

        case 'ORDER_RECEIVED':
          final payload = data['data'];
          if (payload is Map && payload['orderId'] != null) {
            _lastOrderAckId = payload['orderId'].toString();
            unawaited(
                _updateBackendOrderStatus(_lastOrderAckId, 2)); // 2 = Preparing
          } else if (data['orderId'] != null) {
            unawaited(_updateBackendOrderStatus(data['orderId'], 2));
          }
          _lastOrderAckAt = DateTime.now();
          notifyListeners();
          break;

        case 'ERROR':
          _errorMessage = ErrorHandler.normalizeBackendMessage(
            data['message']?.toString(),
            defaultMessage: 'تعذر إكمال العملية على شاشة العرض.',
          );
          if (data['code'] == 'ERR_002') {
            debugPrint('Authentication failed: ${data['message']}');
            disconnect();
          }
          notifyListeners();
          break;

        case 'MODE_CHANGED':
          debugPrint('Display App mode changed to: ${data['mode']}');
          final mode = data['mode'].toString().toUpperCase();
          final nextMode = (mode == 'CDS')
              ? DisplayMode.cds
              : (mode == 'KDS' ? DisplayMode.kds : DisplayMode.none);
          if (nextMode == DisplayMode.kds && _isCdsLockActive()) {
            debugPrint(
              'Ignoring MODE_CHANGED -> KDS because CDS mode is pinned.',
            );
            _currentMode = DisplayMode.cds;
            _supportsNearPay = true;
            _sendMessage({
              'type': 'SET_MODE',
              'mode': 'CDS',
              'lang': _currentLanguageCode,
              'language_code': _currentLanguageCode,
            });
            _scheduleCartSync(
              force: true,
              delay: const Duration(milliseconds: 250),
            );
            notifyListeners();
            break;
          }
          _currentMode = nextMode;
          _supportsNearPay = (_currentMode == DisplayMode.cds);
          if (_currentMode == DisplayMode.cds) {
            _scheduleCartSync(
                force: true, delay: const Duration(milliseconds: 250));
          }
          notifyListeners();
          break;

        case 'PAYMENT_SUCCESS':
          _logPaymentSuccessMessage(data['data'] as Map<String, dynamic>?);
          final rawData = data['data'];
          if (rawData is Map<String, dynamic>) {
            final flattenedData = <String, dynamic>{...rawData};
            final transaction = rawData['transaction'];
            if (transaction is Map) {
              flattenedData.addAll(Map<String, dynamic>.from(transaction));
            } else if (transaction != null) {
              flattenedData['transaction'] = transaction;
            }
            _handlePaymentSuccess(flattenedData);
          } else {
            _handlePaymentSuccess(<String, dynamic>{});
          }
          break;

        case 'PAYMENT_FAILED':
          _logPaymentFailureMessage(
            data['data'] as Map<String, dynamic>?,
            fallbackMessage: data['message']?.toString(),
          );
          _handlePaymentFailed(ErrorHandler.normalizeBackendMessage(
            data['message']?.toString(),
            defaultMessage: 'فشلت عملية الدفع.',
          ));
          break;

        case 'PAYMENT_CANCELLED':
          _handlePaymentCancelled();
          break;

        case 'PAYMENT_STATUS':
          final status =
              data['data'] != null ? data['data']['status'] : data['status'];
          final msg =
              data['data'] != null ? data['data']['message'] : data['message'];
          debugPrint('Display App payment status: $status');
          if (_onPaymentStatus != null && status != null) {
            _onPaymentStatus!(status.toString(), msg?.toString());
          }
          break;
        case 'NEARPAY_STATUS':
          _logNearPayStatus(data['data'] as Map<String, dynamic>?);
          break;

        case 'ORDER_COMPLETED':
          debugPrint('Order completed in KDS: ${data['orderId']}');
          // When KDS bumps an order (marks it as done), update status to 3 (انتهي/Ended)
          // Status 4 = جاري التحضير (Preparing) - set when order is sent to KDS
          // Status 3 = انتهي (Ended) - set when KDS bumps the order
          unawaited(_updateBackendOrderStatus(data['orderId'], 3)); // 3 = Ended
          break;

        case 'ORDER_READY':
          debugPrint('Order ready in KDS: ${data['orderId']}');
          // ORDER_READY event also means the order is ended in KDS context
          unawaited(_updateBackendOrderStatus(data['orderId'], 3)); // 3 = Ended
          break;

        case 'MEAL_DISABLED_SYNC':
          final payload = data['data'];
          if (payload is Map<String, dynamic>) {
            _notifyMealAvailabilityListeners(payload);
          } else if (payload is Map) {
            _notifyMealAvailabilityListeners(
              payload.map((k, v) => MapEntry(k.toString(), v)),
            );
          }
          break;

        case 'ORDER_UNDO_SYNC':
          debugPrint('Order undo sync received: ${data['data']}');
          // Could revert to 2 if needed: unawaited(_updateBackendOrderStatus(data['data']?['order_id'], 2));
          break;

        case 'ORDER_STATUS_UPDATE':
          debugPrint('Order status update received: ${data['data']}');
          final statusData = data['data'];
          if (statusData is Map) {
            final orderIdStatus = statusData['order_id'] ?? statusData['id'];
            final statusValue = statusData['status'];
            if (orderIdStatus != null && statusValue != null) {
              final statusInt = statusValue is int
                  ? statusValue
                  : int.tryParse(statusValue.toString());
              if (statusInt != null) {
                if (statusInt == 8) {
                  debugPrint(
                      'Ignoring auto status=8 from Display App; cancellation must be manual in cashier.');
                  break;
                }
                unawaited(_updateBackendOrderStatus(orderIdStatus, statusInt));
              }
            }
          }
          break;

        case 'ORDER_COMPLETED_SYNC':
          debugPrint('Order completed sync received: ${data['data']}');
          final orderIdSync = data['data'] is Map
              ? data['data']['order_id'] ?? data['data']['id']
              : null;
          // When KDS bumps an order, update to status 3 (انتهي/Ended)
          unawaited(_updateBackendOrderStatus(orderIdSync, 3));
          break;
      }
    } catch (e) {
      debugPrint('Error handling message from Display App: $e');
      _errorMessage = 'تم استلام بيانات غير صالحة من شاشة العرض.';
      notifyListeners();
    }
  }

  void _logNearPayStatus(Map<String, dynamic>? data) {
    if (data == null) {
      debugPrint('❌ [Cashier] Received NEARPAY_STATUS with null data');
      return;
    }

    final ready = data['ready'] == true || data['success'] == true;
    final message =
        data['message_ar'] ?? data['userMessage'] ?? data['message'] ?? '';
    final failedAt = data['failed_at'] ?? data['failedAt'];
    final errors = (data['errors'] as List<dynamic>?) ?? const [];
    final warnings = (data['warnings'] as List<dynamic>?) ?? const [];

    debugPrint('📡 [Cashier] ═══════════════════════════════════════');
    debugPrint('📡 [Cashier] NEARPAY_STATUS Received:');
    debugPrint('📡 [Cashier]   Ready: $ready');
    debugPrint('📡 [Cashier]   Message: $message');
    if (failedAt != null) {
      debugPrint('📡 [Cashier]   Failed At: $failedAt');
    }
    if (errors.isNotEmpty) {
      debugPrint('📡 [Cashier]   Errors:');
      for (final error in errors) {
        debugPrint('📡 [Cashier]     - $error');
      }
    }
    if (warnings.isNotEmpty) {
      debugPrint('📡 [Cashier]   Warnings:');
      for (final warning in warnings) {
        debugPrint('📡 [Cashier]     - $warning');
      }
    }
    debugPrint('📡 [Cashier] ═══════════════════════════════════════');
  }

  void _logPaymentSuccessMessage(Map<String, dynamic>? data) {
    if (data == null) {
      debugPrint('❌ [Cashier] Received PAYMENT_SUCCESS with null data');
      return;
    }

    debugPrint('✅ [Cashier] ═══════════════════════════════════════');
    debugPrint('✅ [Cashier] PAYMENT_SUCCESS Received:');
    debugPrint('✅ [Cashier]   Transaction ID: ${data['transactionId']}');
    debugPrint('✅ [Cashier]   Session ID: ${data['sessionId']}');
    debugPrint('✅ [Cashier]   Reference: ${data['referenceId']}');
    debugPrint('✅ [Cashier]   Amount: ${data['amount']}');
    debugPrint('✅ [Cashier]   Backend Status: ${data['backend_status']}');
    debugPrint('✅ [Cashier]   Verified: ${data['verified']}');
    if (data['warning'] != null) {
      debugPrint('⚠️  [Cashier]   Warning: ${data['warning']}');
    }
    debugPrint('✅ [Cashier] ═══════════════════════════════════════');
  }

  void _logPaymentFailureMessage(
    Map<String, dynamic>? data, {
    String? fallbackMessage,
  }) {
    if (data == null) {
      debugPrint('❌ [Cashier] Received PAYMENT_FAILED with null data');
      if (fallbackMessage != null) {
        debugPrint('❌ [Cashier]   Message: $fallbackMessage');
      }
      return;
    }

    debugPrint('❌ [Cashier] ═══════════════════════════════════════');
    debugPrint('❌ [Cashier] PAYMENT_FAILED Received:');
    debugPrint('❌ [Cashier]   Error: ${data['error'] ?? fallbackMessage}');
    debugPrint('❌ [Cashier]   Reference: ${data['referenceId']}');
    debugPrint('❌ [Cashier]   Session ID: ${data['sessionId']}');
    debugPrint('❌ [Cashier]   Backend Status: ${data['backend_status']}');
    if (data['warning'] != null) {
      debugPrint('⚠️  [Cashier]   Warning: ${data['warning']}');
    }
    debugPrint('❌ [Cashier] ═══════════════════════════════════════');
  }

  void _logWebSocketConnected(String url) {
    debugPrint('🔌 [Cashier] WebSocket connected to Display App');
    debugPrint('🔌 [Cashier]   URL: $url');
    debugPrint('🔌 [Cashier]   Timestamp: ${DateTime.now().toIso8601String()}');
  }

  void _logWebSocketDisconnected() {
    debugPrint('🔌 [Cashier] WebSocket disconnected from Display App');
    debugPrint('🔌 [Cashier]   Timestamp: ${DateTime.now().toIso8601String()}');
  }

  void _logWebSocketError(dynamic error) {
    debugPrint('❌ [Cashier] WebSocket error: $error');
  }

  void _onPongReceived() {
    debugPrint('💓 [Cashier] Heartbeat response received from Display App');
  }

  Future<void> _updateBackendOrderStatus(dynamic orderIdRaw, int status) async {
    if (orderIdRaw == null) return;
    final orderId = orderIdRaw.toString().trim();
    if (orderId.isEmpty) return;
    if (status == 8) {
      debugPrint(
          'Skipping auto status=8 update for order $orderId; cancellation must be manual in cashier.');
      return;
    }

    try {
      final orderService = getIt<OrderService>();
      await orderService.updateBookingStatus(orderId: orderId, status: status);
      debugPrint('KDS Status Sync: updated order $orderId to status $status');
    } on ApiException catch (e) {
      // Silently ignore rate limiting errors to avoid spamming logs
      if (e.statusCode == 422 &&
          (e.message.contains('Too Many') ||
              e.message.contains('محاولات كثيرة'))) {
        debugPrint(
            'KDS Status Sync: Rate limited for order $orderId - will retry later');
        return;
      }
      debugPrint(
          'KDS Status Sync Error: could not update order $orderId to status $status - $e');
    } catch (e) {
      debugPrint(
          'KDS Status Sync Error: could not update order $orderId to status $status - $e');
    }
  }

  void _handleAuthChallenge(String challenge) {
    debugPrint('Responding to auth challenge...');
    final hmac = Hmac(sha256, utf8.encode(_authSecret));
    final response =
        base64Url.encode(hmac.convert(utf8.encode(challenge)).bytes);

    final authToken = BaseClient().getToken() ?? '';
    final branchId = ApiConstants.branchId;
    final backendUrl = ApiConstants.baseUrl;
    final nearpayEnabled = _profileNearPayEnabled;

    // Send AUTH_RESPONSE immediately — never delay the handshake for a JWT fetch.
    // If the JWT is already cached it travels with AUTH_RESPONSE; otherwise
    // NEARPAY_INIT (sent after AUTH_SUCCESS) will deliver it.
    final cachedJwt = NearPayService().cachedToken;
    _sendMessage({
      'type': 'AUTH_RESPONSE',
      'challenge': challenge,
      'response': response,
      'deviceId': _deviceId,
      if (authToken.isNotEmpty) 'auth_token': authToken,
      if (backendUrl.isNotEmpty) 'backend_url': backendUrl,
      if (branchId > 0) 'branch_id': branchId,
      if (nearpayEnabled && cachedJwt != null) 'jwt_token': cachedJwt,
      'options': {'nearpay': nearpayEnabled},
      'nearpay': nearpayEnabled,
    });
  }

  void _handleAuthSuccess(Map<String, dynamic> data) {
    _authToken = data['token'];
    _status = ConnectionStatus.connected;
    _lastPong = DateTime.now();
    _reconnectAttempts = 0;
    _errorMessage = null;

    final mode = data['currentMode']?.toString().toUpperCase();
    if (mode == 'CDS') {
      _currentMode = DisplayMode.cds;
    } else if (mode == 'KDS') {
      _currentMode = DisplayMode.kds;
    }

    _supportsNearPay =
        data['supportsNearPay'] ?? (_currentMode == DisplayMode.cds);

    if (_isCdsLockActive() && _currentMode != DisplayMode.cds) {
      _currentMode = DisplayMode.cds;
      _supportsNearPay = true;
      _sendMessage({
        'type': 'SET_MODE',
        'mode': 'CDS',
        'lang': _currentLanguageCode,
        'language_code': _currentLanguageCode,
      });
    }

    _startPingTimer();
    _flushOutboundQueue();
    _scheduleCartSync(force: true, delay: const Duration(milliseconds: 200));
    if (_currentMode == DisplayMode.kds) {
      unawaited(_sendKdsContext());
    }
    if (_currentMode == DisplayMode.cds) {
      unawaited(_sendKdsContext());
    }

    // If NearPay is enabled, always send NEARPAY_INIT after auth succeeds.
    // This is belt-and-suspenders: AUTH_RESPONSE already carries the JWT, but
    // if the profile loaded after the auth challenge fired (race condition),
    // this guarantees the Display App receives the init regardless.
    if (_profileNearPayEnabled || _supportsNearPay) {
      unawaited(_sendNearPayInit());
    }

    notifyListeners();
    _onConnectionStateChanged?.call(_status);
    debugPrint('Authenticated and connected successfully to Display App');
  }

  Future<void> _sendNearPayInit() async {
    final authToken = BaseClient().getToken() ?? '';
    final branchId = ApiConstants.branchId;
    final backendUrl = ApiConstants.baseUrl;
    if (authToken.isEmpty || backendUrl.isEmpty || branchId <= 0) return;

    // Display App handles JWT + terminal config fetch internally
    _sendMessage({
      'type': 'NEARPAY_INIT',
      'auth_token': authToken,
      'backend_url': backendUrl,
      'branch_id': branchId,
      'options': {'nearpay': true},
      'nearpay': true,
    });
  }

  void _handlePaymentSuccess(Map<String, dynamic> transactionData) {
    _paymentStatus = PaymentStatus.success;
    _mirrorPaymentStatusToPresentation('success');
    notifyListeners();

    // Automatically send order to kitchen after successful payment
    _sendOrderToKitchenAfterPayment();

    if (_onPaymentSuccess != null) {
      _onPaymentSuccess!(transactionData);
    }

    _restoreModeAfterPaymentIfNeeded();

    // Clear payment status after a delay
    Future.delayed(const Duration(seconds: 3), () {
      _paymentStatus = PaymentStatus.idle;
      _currentOrderData = null;
      notifyListeners();
    });
  }

  /// Send order to kitchen after successful payment
  void _sendOrderToKitchenAfterPayment() {
    if (_currentOrderData == null) {
      debugPrint('No order data available to send to kitchen');
      return;
    }

    final orderId = (_currentOrderData!['orderId'] ?? '').toString().trim();
    final orderNumber =
        (_currentOrderData!['orderNumber'] ?? '').toString().trim();
    final items =
        _currentOrderData!['items'] as List<Map<String, dynamic>>? ?? [];
    final total = _toDouble(_currentOrderData!['total']);
    final note = _currentOrderData!['note'] as String?;

    if (orderId.isEmpty || orderNumber.isEmpty) {
      debugPrint('Skipping auto-send to KDS: missing real order id/number');
      return;
    }

    // Send to KDS
    sendOrderToKitchen(
      orderId: orderId,
      orderNumber: orderNumber,
      orderType: _currentOrderData!['orderType'] ?? 'dine_in',
      items: items,
      note: note,
      total: total,
    );

    // Call the callback if set
    if (_onOrderReady != null) {
      _onOrderReady!(
        orderId: orderId,
        orderNumber: orderNumber,
        items: items,
        total: total,
        note: note,
      );
    }

    debugPrint(
        'Order sent to kitchen automatically after payment: $orderNumber');
  }

  void _handlePaymentFailed(String errorMessage) {
    _paymentStatus = PaymentStatus.failed;
    _mirrorPaymentStatusToPresentation('failed', message: errorMessage);
    notifyListeners();

    if (_onPaymentFailed != null) {
      _onPaymentFailed!(errorMessage);
    }

    _restoreModeAfterPaymentIfNeeded();

    // Clear payment status after a delay
    Future.delayed(const Duration(seconds: 2), () {
      _paymentStatus = PaymentStatus.idle;
      notifyListeners();
    });
  }

  void _handlePaymentCancelled() {
    _paymentStatus = PaymentStatus.cancelled;
    _mirrorPaymentStatusToPresentation('cancelled');
    notifyListeners();

    if (_onPaymentCancelled != null) {
      _onPaymentCancelled!();
    }

    _restoreModeAfterPaymentIfNeeded();

    // Clear payment status after a delay
    Future.delayed(const Duration(seconds: 2), () {
      _paymentStatus = PaymentStatus.idle;
      notifyListeners();
    });
  }

  // Set callbacks
  void setCallbacks({
    PaymentSuccessCallback? onPaymentSuccess,
    PaymentFailedCallback? onPaymentFailed,
    PaymentCancelledCallback? onPaymentCancelled,
    PaymentStatusCallback? onPaymentStatus,
    OrderReadyCallback? onOrderReady,
    ConnectionStateCallback? onConnectionStateChanged,
  }) {
    _onPaymentSuccess = onPaymentSuccess;
    _onPaymentFailed = onPaymentFailed;
    _onPaymentCancelled = onPaymentCancelled;
    _onPaymentStatus = onPaymentStatus;
    _onOrderReady = onOrderReady;
    _onConnectionStateChanged = onConnectionStateChanged;
  }

  // Clear callbacks
  void clearCallbacks() {
    _onPaymentSuccess = null;
    _onPaymentFailed = null;
    _onPaymentCancelled = null;
    _onOrderReady = null;
    _onConnectionStateChanged = null;
  }

  // Send Commands to Display App

  void setMode(DisplayMode mode, {bool force = false}) {
    if (mode == DisplayMode.kds && _isCdsLockActive() && !force) {
      debugPrint('Blocked SET_MODE -> KDS while CDS mode is pinned.');
      return;
    }
    if (force) {
      _cdsLockUntil = null;
    }
    _currentMode = mode;
    // CDS mode supports NearPay payments
    _supportsNearPay = (mode == DisplayMode.cds);
    _sendMessage({
      'type': 'SET_MODE',
      'mode': mode == DisplayMode.cds ? 'CDS' : 'KDS',
      'lang': _currentLanguageCode,
      'language_code': _currentLanguageCode,
    });
    if (mode == DisplayMode.kds) {
      unawaited(_sendKdsContext());
    }
    if (mode == DisplayMode.cds) {
      unawaited(_sendKdsContext());
      _scheduleCartSync(force: true, delay: const Duration(milliseconds: 350));
    }
    _mirrorModeToPresentation(mode);
    notifyListeners();
  }

  void _restoreModeAfterPaymentIfNeeded({
    Duration delay = const Duration(milliseconds: 450),
  }) {
    final targetMode = _modeBeforePayment;
    _modeBeforePayment = null;
    if (targetMode == null || targetMode == DisplayMode.cds) {
      return;
    }

    Future.delayed(delay, () {
      if (!isConnected) return;
      if (_paymentStatus == PaymentStatus.processing) return;
      if (_isCdsLockActive()) return;
      if (_currentMode == targetMode) return;
      setMode(targetMode, force: true);
    });
  }

  void updateCartDisplay({
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double tax,
    required double total,
    required String orderNumber,
    String? orderType,
    String? note,
    String? promoCode,
    String? promoCodeId,
    String? promoDiscountType,
    double? discountAmount,
    double? originalTotal,
    double? discountedTotal,
    double? taxRate,
    bool? hasTax,
    bool? isOrderFree,
    String? orderDiscountType,
    double? orderDiscountValue,
    double? orderDiscountPercent,
    String? discountSource,
    Map<String, dynamic>? cashFloatSnapshot,
  }) {
    final resolvedTaxRate = _resolveTaxRate(
      subtotal: subtotal,
      tax: tax,
      providedRate: taxRate,
    );
    final taxPercentage = double.parse(
      (resolvedTaxRate * 100).toStringAsFixed(4),
    );
    final resolvedHasTax = hasTax ?? resolvedTaxRate > 0;

    // Store order data for later use with KDS
    _currentOrderData = {
      'orderId': '',
      'orderNumber': orderNumber,
      'items': items,
      'subtotal': subtotal,
      'tax': tax,
      'tax_rate': resolvedTaxRate,
      'tax_percentage': taxPercentage,
      'has_tax': resolvedHasTax,
      'total': total,
      'orderType': orderType ?? 'dine_in',
      'note': note,
      if (promoCode != null) 'promocodeValue': promoCode,
      if (promoCodeId != null) 'promocode_id': promoCodeId,
      if (promoDiscountType != null) 'discount_type': promoDiscountType,
      if (discountAmount != null) 'discount_amount': discountAmount,
      if (promoCode != null && promoCode.isNotEmpty)
        'promo': {
          if (promoCodeId != null) 'id': promoCodeId,
          'code': promoCode,
          if (promoDiscountType != null) 'discount_type': promoDiscountType,
          if (discountAmount != null) 'discount_amount': discountAmount,
        },
      if (originalTotal != null) 'original_total': originalTotal,
      if (discountedTotal != null) 'discounted_total': discountedTotal,
      if (isOrderFree != null) 'is_order_free': isOrderFree,
      if (isOrderFree != null) 'isOrderFree': isOrderFree,
      if (orderDiscountType != null) 'order_discount_type': orderDiscountType,
      if (orderDiscountValue != null)
        'order_discount_value': orderDiscountValue,
      if (orderDiscountPercent != null)
        'order_discount_percent': orderDiscountPercent,
      if (discountSource != null) 'discount_source': discountSource,
      if (cashFloatSnapshot != null)
        'cash_float': Map<String, dynamic>.from(cashFloatSnapshot),
      'currency': ApiConstants.currency,
      'lang': _currentLanguageCode,
      'language_code': _currentLanguageCode,
    };

    _lastCartPayload = {
      'type': 'UPDATE_CART',
      'data': {
        'items': items,
        'subtotal': subtotal,
        'tax': tax,
        'tax_rate': resolvedTaxRate,
        'tax_percentage': taxPercentage,
        'has_tax': resolvedHasTax,
        'total': total,
        'orderNumber': orderNumber,
        'orderType': orderType ?? 'dine_in',
        'note': note,
        if (promoCode != null) 'promocodeValue': promoCode,
        if (promoCodeId != null) 'promocode_id': promoCodeId,
        if (promoDiscountType != null) 'discount_type': promoDiscountType,
        if (discountAmount != null) 'discount_amount': discountAmount,
        if (promoCode != null && promoCode.isNotEmpty)
          'promo': {
            if (promoCodeId != null) 'id': promoCodeId,
            'code': promoCode,
            if (promoDiscountType != null) 'discount_type': promoDiscountType,
            if (discountAmount != null) 'discount_amount': discountAmount,
          },
        if (originalTotal != null) 'original_total': originalTotal,
        if (discountedTotal != null) 'discounted_total': discountedTotal,
        if (isOrderFree != null) 'is_order_free': isOrderFree,
        if (isOrderFree != null) 'isOrderFree': isOrderFree,
        if (orderDiscountType != null) 'order_discount_type': orderDiscountType,
        if (orderDiscountValue != null)
          'order_discount_value': orderDiscountValue,
        if (orderDiscountPercent != null)
          'order_discount_percent': orderDiscountPercent,
        if (discountSource != null) 'discount_source': discountSource,
        if (cashFloatSnapshot != null)
          'cash_float': Map<String, dynamic>.from(cashFloatSnapshot),
        'currency': ApiConstants.currency,
        'lang': _currentLanguageCode,
        'language_code': _currentLanguageCode,
      },
    };

    _scheduleCartSync();
  }

  void forceResendCartState() {
    _scheduleCartSync(force: true);
  }

  void sendOrderToKitchen({
    required String orderId,
    required String orderNumber,
    required String orderType,
    required List<Map<String, dynamic>> items,
    String? note,
    double? total,
    Map<String, dynamic>? invoice,
    bool switchMode = false,
  }) {
    _sendMessage({
      'type': 'NEW_ORDER',
      'data': {
        'id': orderId,
        'orderNumber': orderNumber,
        'type': orderType,
        'items': items,
        'note': note,
        'total': total,
        'status': 'preparing',
        'createdAt': DateTime.now().toIso8601String(),
        'sendToKds': true,
        if (invoice != null) 'invoice': invoice,
      },
    });

    // Optional mode switch (disabled by default to keep CDS customer view stable).
    if (switchMode) {
      setMode(DisplayMode.kds);
    }
  }

  void clearCart() {
    _currentOrderData = null;
    _sendMessage({
      'type': 'UPDATE_CART',
      'data': {
        'items': [],
        'subtotal': 0.0,
        'tax': 0.0,
        'total': 0.0,
        'orderNumber': '',
        'currency': ApiConstants.currency,
        'lang': _currentLanguageCode,
        'language_code': _currentLanguageCode,
      },
    });
  }

  // ========== PAYMENT COMMANDS ==========

  /// Start payment process on Display App
  /// This shows the "Tap to Pay" screen on CDS
  /// Payment request is sent FROM Cashier TO Display App
  void startPayment({
    required double amount,
    required String orderNumber,
    String? customerReference,
  }) {
    if (!isConnected) {
      debugPrint('Cannot start payment: not connected to Display App');
      _errorMessage = 'لا يوجد اتصال بتطبيق العرض';
      notifyListeners();
      return;
    }

    if (_currentMode == DisplayMode.cds) {
      _modeBeforePayment = null;
    }

    if (_currentMode == DisplayMode.kds) {
      debugPrint(
          'Blocked payment start on KDS session; CDS device is required.');
      _paymentStatus = PaymentStatus.failed;
      _errorMessage =
          'لا يمكن بدء الدفع على شاشة KDS. استخدم جهاز CDS مخصص للدفع.';
      notifyListeners();
      return;
    }

    pinCdsModeTemporarily(duration: const Duration(seconds: 18));
    _paymentStatus = PaymentStatus.processing;
    notifyListeners();

    // If display is currently in KDS, force switch to CDS before starting payment.
    // This prevents "Pay" from silently failing after auto KDS switch.
    if (_currentMode != DisplayMode.cds) {
      _modeBeforePayment = _currentMode;
      debugPrint(
          'Display in $_currentMode, switching to CDS before payment...');
      setMode(DisplayMode.cds);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!isConnected) {
          _paymentStatus = PaymentStatus.failed;
          _errorMessage = 'انقطع الاتصال أثناء بدء الدفع';
          notifyListeners();
          return;
        }
        _sendStartPaymentMessage(
          amount: amount,
          orderNumber: orderNumber,
          customerReference: customerReference,
        );
      });
      return;
    }

    _sendStartPaymentMessage(
      amount: amount,
      orderNumber: orderNumber,
      customerReference: customerReference,
    );
  }

  void _sendStartPaymentMessage({
    required double amount,
    required String orderNumber,
    String? customerReference,
  }) {
    final referenceId = customerReference?.toString().trim().isNotEmpty == true
        ? customerReference!.toString().trim()
        : orderNumber;

    final payload = {
      'type': 'START_PAYMENT',
      'data': {
        'amount': amount,
        'orderNumber': orderNumber,
        'customerReference': customerReference,
        'reference_id': referenceId,
        'payment_method': 'nearpay',
        'timestamp': DateTime.now().toIso8601String(),
      },
    };

    debugPrint('💳 [Cashier] ═══════════════════════════════════════');
    debugPrint('💳 [Cashier] Sending NearPay Payment Request:');
    debugPrint('💳 [Cashier]   Amount: $amount SAR');
    debugPrint('💳 [Cashier]   Reference: $referenceId');
    debugPrint('💳 [Cashier]   Timestamp: ${DateTime.now().toIso8601String()}');
    debugPrint('💳 [Cashier]   Full Payload: ${jsonEncode(payload)}');
    debugPrint('💳 [Cashier] ═══════════════════════════════════════');

    _sendMessage(payload);
    _mirrorPaymentStartToPresentation(payload['data'] as Map<String, dynamic>);

    debugPrint('✅ [Cashier] Payment request sent to Display App');
  }

  Future<void> testNearPayCommunication() async {
    debugPrint('🧪 [Cashier] ═══════════════════════════════════════');
    debugPrint('🧪 [Cashier] Starting NearPay Communication Test');
    debugPrint('🧪 [Cashier] ═══════════════════════════════════════');

    if (!isConnected) {
      debugPrint('❌ [Cashier] Test failed: WebSocket not connected');
      return;
    }
    debugPrint('✅ [Cashier] WebSocket is connected');

    final referenceId =
        'TEST-${DateTime.now().millisecondsSinceEpoch.toString()}';
    debugPrint('🧪 [Cashier] Sending test payment request...');
    startPayment(
      amount: 1.0,
      orderNumber: referenceId,
      customerReference: referenceId,
    );

    debugPrint('🧪 [Cashier] Test payment sent - check Display App logs');
    debugPrint('🧪 [Cashier] Waiting for response (30 seconds timeout)...');

    await Future.delayed(const Duration(seconds: 30));
    WebSocketDebugger.printStats();
  }

  /// Update payment status during processing
  void updatePaymentStatus(String status, {String? message}) {
    _sendMessage({
      'type': 'UPDATE_PAYMENT_STATUS',
      'status': status,
      'message': message,
    });
    _mirrorPaymentStatusToPresentation(status, message: message);
  }

  /// Notify Display App that payment was successful
  /// This will automatically send order to KDS
  void notifyPaymentSuccess(Map<String, dynamic> transactionData) {
    _paymentStatus = PaymentStatus.success;
    notifyListeners();

    _sendMessage({
      'type': 'PAYMENT_SUCCESS',
      'data': transactionData,
    });
  }

  /// Notify Display App that payment failed
  void notifyPaymentFailed(String errorMessage) {
    _paymentStatus = PaymentStatus.failed;
    notifyListeners();

    _sendMessage({
      'type': 'PAYMENT_FAILED',
      'message': errorMessage,
    });
  }

  /// Cancel ongoing payment
  void cancelPayment() {
    _paymentStatus = PaymentStatus.cancelled;
    notifyListeners();

    _sendMessage({
      'type': 'CANCEL_PAYMENT',
    });
  }

  /// Clear payment display (return to normal cart view)
  void clearPaymentDisplay() {
    _paymentStatus = PaymentStatus.idle;
    notifyListeners();
    _restoreModeAfterPaymentIfNeeded(delay: const Duration(milliseconds: 200));

    _sendMessage({
      'type': 'CLEAR_PAYMENT',
    });
  }

  /// Mark order as completed in KDS
  void markOrderCompleted(String orderId) {
    _sendMessage({
      'type': 'ORDER_COMPLETED',
      'orderId': orderId,
    });
  }

  /// Mark order as ready in KDS
  void markOrderReady(String orderId) {
    _sendMessage({
      'type': 'ORDER_READY',
      'orderId': orderId,
    });
  }

  /// Push direct booking status sync to display app/KDS.
  void sendOrderStatusUpdateToDisplay({
    required String orderId,
    required int status,
  }) {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) return;
    _sendMessage({
      'type': 'ORDER_STATUS_UPDATE',
      'data': {
        'order_id': normalizedOrderId,
        'status': status,
        'timestamp': DateTime.now().toIso8601String(),
      },
    });
  }

  /// Notify display app that an invoice was created.
  ///
  /// The display app currently doesn't consume a dedicated invoice-created
  /// message, so this is a no-op beyond logging. Keeping the method allows
  /// callers to remain stable without breaking compilation.
  void notifyInvoiceCreated({
    required String orderId,
    int? invoiceId,
    String? invoiceNumber,
    String? orderNumber,
    double? total,
  }) {
    final normalizedOrderId = orderId.trim();
    if (normalizedOrderId.isEmpty) return;
    debugPrint(
      'ℹ️ Invoice created (no-op): orderId=$normalizedOrderId '
      'invoiceId=${invoiceId ?? '-'} '
      'invoiceNumber=${invoiceNumber ?? '-'} '
      'orderNumber=${orderNumber ?? '-'} '
      'total=${total ?? '-'}',
    );
  }

  void _sendMessage(Map<String, dynamic> message) {
    final bool isAuthMessage = message['type'] == 'AUTH_RESPONSE';

    if (_channel != null && (isConnected || isAuthMessage)) {
      try {
        final type = message['type'];
        if (type is String) {
          WebSocketDebugger.logMessageSent(type);
        }
        _channel!.sink.add(jsonEncode(message));
        debugPrint('Sent to Display App: $message');
      } catch (e) {
        debugPrint('Error sending message to Display App: $e');
        _handleConnectionError(ErrorHandler.websocketErrorMessage(e));
      }
    } else {
      _queueMessageForReconnect(message);
      debugPrint('Cannot send message: not connected (status: $_status)');
    }
  }

  void addMealAvailabilityListener(
    void Function(Map<String, dynamic>) listener,
  ) {
    _mealAvailabilityListeners.add(listener);
  }

  void removeMealAvailabilityListener(
    void Function(Map<String, dynamic>) listener,
  ) {
    _mealAvailabilityListeners.remove(listener);
  }

  void _notifyMealAvailabilityListeners(Map<String, dynamic> payload) {
    for (final listener in List<void Function(Map<String, dynamic>)>.from(
      _mealAvailabilityListeners,
    )) {
      try {
        listener(payload);
      } catch (e) {
        debugPrint('Meal availability listener error: $e');
      }
    }
  }

  Future<void> _sendKdsContext() async {
    try {
      final productService = getIt<ProductService>();
      final mealAvailabilityService = getIt<KdsMealAvailabilityService>();
      final categories = await productService.getMealCategories();
      final products = await _fetchAllProductsSnapshot(productService);
      final authToken = BaseClient().getToken() ?? '';
      final contextData = <String, dynamic>{
        'role': 'cashier',
        'device_type': 'cashier',
        'branch_id': ApiConstants.branchId.toString(),
        'auth_token': authToken,
        'generated_at': DateTime.now().toIso8601String(),
        'currency': ApiConstants.currency,
        'lang': _currentLanguageCode,
        'language_code': _currentLanguageCode,
        'categories': categories
            .map((category) => {
                  'id': category.id,
                  'name': category.name,
                })
            .toList(),
        'products': products,
        'disabled_meals': mealAvailabilityService.disabledMeals.values
            .where((e) => e.isDisabled)
            .map((e) => e.toJson())
            .toList(),
        if (_cashFloatSnapshot != null) 'cash_float': _cashFloatSnapshot,
      };

      // Send via WebSocket
      if (isConnected) {
        _sendMessage({'type': 'KDS_CONTEXT', 'data': contextData});
      }

      // Mirror to secondary display via Presentation API
      if (_presentationService.isPresentationShowing) {
        unawaited(_presentationService.updateCatalogContext(contextData));
      }
    } catch (e) {
      debugPrint('Failed to send KDS context: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAllProductsSnapshot(
    ProductService productService,
  ) async {
    const int maxPages = 20;
    final results = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    for (var page = 1; page <= maxPages; page++) {
      final pageItems = await productService.getProducts(page: page);
      if (pageItems.isEmpty) break;

      for (final product in pageItems) {
        if (product.id.isEmpty || seenIds.contains(product.id)) continue;
        seenIds.add(product.id);
        results.add({
          'id': product.id,
          'name': product.name,
          'category': product.category,
          'price': product.price,
          'is_active': product.isActive,
          'image': product.image,
        });
      }
    }
    return results;
  }

  void _queueMessageForReconnect(Map<String, dynamic> message) {
    final type = message['type']?.toString();
    if (type == null) return;
    if (type == 'NEW_ORDER') {
      _outboundQueue.add(Map<String, dynamic>.from(message));
      return;
    }
    if (type == 'UPDATE_CART') {
      _lastCartPayload = Map<String, dynamic>.from(message);
      _hasPendingCartSync = true;
    }
  }

  void _flushOutboundQueue() {
    if (!isConnected || _outboundQueue.isEmpty) return;
    final pending = List<Map<String, dynamic>>.from(_outboundQueue);
    _outboundQueue.clear();
    for (final message in pending) {
      _sendMessage(message);
    }
  }

  @override
  void dispose() {
    translationService.removeListener(_handleLanguageChanged);
    disconnect();
    super.dispose();
  }

  String _cartFingerprint(Map<String, dynamic> payload) {
    final data = payload['data'];
    return data is Map<String, dynamic>
        ? jsonEncode(data)
        : jsonEncode(payload);
  }

  void _scheduleCartSync({
    bool force = false,
    Duration delay = Duration.zero,
  }) {
    if (_lastCartPayload == null) return;
    _hasPendingCartSync = true;
    _cartSyncTimer?.cancel();
    _cartSyncTimer = Timer(delay, () {
      _sendLatestCart(force: force);
    });
  }

  void _sendLatestCart({bool force = false}) {
    final payload = _lastCartPayload;
    if (payload == null) return;

    // Always mirror to secondary display via Presentation API,
    // even if WebSocket is not connected (dual-screen devices
    // don't need WebSocket for the built-in second screen).
    _mirrorCartToPresentation(payload);

    if (!isConnected) {
      _hasPendingCartSync = true;
      return;
    }

    final now = DateTime.now();
    final fingerprint = _cartFingerprint(payload);
    final tooSoon = _lastCartSentAt != null &&
        now.difference(_lastCartSentAt!) < _minCartSyncInterval;
    final samePayload = _lastCartFingerprint == fingerprint;
    final shouldSkip = !force && !_hasPendingCartSync && samePayload && tooSoon;
    if (shouldSkip) {
      return;
    }

    _sendMessage(payload);
    _lastCartSentAt = now;
    _lastCartFingerprint = fingerprint;
    _hasPendingCartSync = false;
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  PRESENTATION API BRIDGE (dual-screen devices)
  // ═════════════════════════════════════════════════════════════════════════

  /// Mirror cart data to the secondary display via Presentation API.
  void _mirrorCartToPresentation(Map<String, dynamic> payload) {
    if (!_presentationService.isPresentationShowing) return;
    final data = payload['data'];
    if (data is Map<String, dynamic>) {
      unawaited(_presentationService.updateCart(data));
    }
  }

  /// Mirror mode changes to the secondary display via Presentation API.
  void _mirrorModeToPresentation(DisplayMode mode) {
    if (!_presentationService.isPresentationShowing) return;
    final modeStr = mode == DisplayMode.cds ? 'CDS' : 'KDS';
    unawaited(_presentationService.setMode(modeStr));
  }

  /// Mirror payment start to the secondary display via Presentation API.
  void _mirrorPaymentStartToPresentation(Map<String, dynamic> paymentData) {
    if (!_presentationService.isPresentationShowing) return;
    unawaited(_presentationService.startPayment(paymentData));
  }

  /// Mirror payment status to the secondary display via Presentation API.
  void _mirrorPaymentStatusToPresentation(String status, {String? message}) {
    if (!_presentationService.isPresentationShowing) return;
    unawaited(_presentationService.updatePaymentStatus(status, message: message));
  }

  /// Show a status overlay on the secondary display (e.g. refund confirmation).
  void showStatusOverlayOnPresentation(Map<String, dynamic> overlay) {
    if (!_presentationService.isPresentationShowing) return;
    unawaited(_presentationService.showStatusOverlay(overlay));
  }

  /// Clear the status overlay on the secondary display.
  void clearStatusOverlayOnPresentation() {
    if (!_presentationService.isPresentationShowing) return;
    unawaited(_presentationService.clearStatusOverlay());
  }
}
