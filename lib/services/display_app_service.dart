library display_app_service;

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


part 'display_app_service_parts/display_app_service.lifecycle.dart';
part 'display_app_service_parts/display_app_service.messaging.dart';
part 'display_app_service_parts/display_app_service.auth_payment.dart';
part 'display_app_service_parts/display_app_service.api.dart';
part 'display_app_service_parts/display_app_service.internals.dart';

// Static constants relocated from DisplayAppService class to library-level
// so extensions can reference them without qualification. Values verbatim.
const int maxReconnectAttempts = 60;
const Duration reconnectDelay = Duration(seconds: 2);
const Duration pingInterval = Duration(seconds: 30);
const Duration pongTimeout = Duration(seconds: 10);
const Duration staleConnectionThreshold = Duration(minutes: 3);
const Duration _minCartSyncInterval = Duration(milliseconds: 250);

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
  int _connectGeneration = 0;

  // Connection health check
  Timer? _pingTimer;
  DateTime? _lastPong;

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

  @override
  void dispose() {
    translationService.removeListener(_handleLanguageChanged);
    disconnect();
    super.dispose();
  }


}
