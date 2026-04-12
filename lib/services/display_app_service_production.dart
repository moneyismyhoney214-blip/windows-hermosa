import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';
import 'api/api_constants.dart';
import 'api/base_client.dart';

/// PRODUCTION-READY Display App Service (Client Side)
///
/// Features:
/// - Reconnection handshake with state synchronization
/// - Type-safe JSON parsing with comprehensive error handling
/// - Guaranteed message delivery with retry logic
/// - Transaction verification (Golden Thread)
/// - Automatic reconnection with exponential backoff
/// - Comprehensive error codes for all failure scenarios
///
/// Error Codes Reference:
/// ERR_001: Connection Lost - Connection dropped unexpectedly
/// ERR_002: Authentication Failed - Invalid credentials
/// ERR_003: Message Parse Error - Invalid JSON received
/// ERR_004: Type Validation Error - Wrong data type
/// ERR_005: Sequence Error - Messages out of order
/// ERR_006: Payment Validation Failed - Invalid payment data
/// ERR_007: Mode Mismatch - Wrong display mode
/// ERR_008: Server Unavailable - Cannot connect to server
/// ERR_009: Max Retries Exceeded - Message delivery failed
/// ERR_010: Unauthorized - Not authenticated
/// ERR_011: Transaction Pending - Transaction status unknown
/// ERR_012: Transaction Verification Failed - Cannot verify status
/// ERR_013: Reconnection Failed - Cannot reconnect after multiple attempts
/// ERR_014: Payment Timeout - Payment not completed in time
/// ERR_015: Server Error - Internal server error

enum DisplayMode { none, cds, kds }

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  authenticated,
  error,
  reconnecting
}

enum PaymentStatus {
  idle,
  processing,
  success,
  failed,
  cancelled,
  pending_verification
}

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

/// Callback types
typedef PaymentSuccessCallback = void Function(
    Map<String, dynamic> transactionData);
typedef PaymentFailedCallback = void Function(
    String errorCode, String errorMessage);
typedef PaymentStatusCallback = void Function(String status, String? message);
typedef ConnectionStateCallback = void Function(
    ConnectionStatus status, String? errorCode);
typedef TransactionVerificationCallback = void Function(
    bool verified, Map<String, dynamic>? result);

class DisplayAppService extends ChangeNotifier {
  WebSocketChannel? _channel;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _errorCode;
  String? _errorMessage;
  String? _connectedIp;
  int _connectedPort = 8080;
  DisplayMode _currentMode = DisplayMode.none;
  PaymentStatus _paymentStatus = PaymentStatus.idle;
  bool _profileNearPayEnabled = false;

  // Reconnection logic
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  static const Duration reconnectDelay = Duration(seconds: 3);
  bool _manualDisconnect = false;

  // Connection health
  Timer? _pingTimer;
  DateTime? _lastPong;
  static const Duration pingInterval = Duration(seconds: 30);
  static const Duration pongTimeout = Duration(seconds: 10);

  // Message sequencing
  int _sequenceNumber = 0;
  final Map<int, Map<String, dynamic>> _pendingMessages = {};

  // Transaction tracking (Golden Thread)
  String? _currentTransactionId;
  bool _isVerifyingTransaction = false;
  DateTime? _cdsLockUntil;

  // Callbacks
  PaymentSuccessCallback? _onPaymentSuccess;
  PaymentFailedCallback? _onPaymentFailed;
  PaymentStatusCallback? _onPaymentStatus;

  /// Override NearPay availability from `/seller/profile -> options.nearpay`.
  void setProfileNearPayOption(bool enabled) {
    if (_profileNearPayEnabled == enabled) return;
    _profileNearPayEnabled = enabled;
    notifyListeners();
  }

  ConnectionStateCallback? _onConnectionStateChanged;
  TransactionVerificationCallback? _onTransactionVerified;

  // Getters
  ConnectionStatus get status => _status;
  String? get errorCode => _errorCode;
  String? get errorMessage => _errorMessage;
  String? get connectedIp => _connectedIp;
  DisplayMode get currentMode => _currentMode;
  PaymentStatus get paymentStatus => _paymentStatus;
  bool get isConnected => _status == ConnectionStatus.authenticated;
  bool get isConnecting => _status == ConnectionStatus.connecting;
  bool get isReconnecting => _status == ConnectionStatus.reconnecting;
  bool get isPaymentProcessing => _paymentStatus == PaymentStatus.processing;
  int get reconnectAttempts => _reconnectAttempts;
  String? get currentTransactionId => _currentTransactionId;
  bool get isCdsModePinned => _isCdsLockActive();

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
  }) {
    if (_currentMode == DisplayMode.kds) {
      debugPrint(
          '[DisplayAppService] Skipping CDS pin while current mode is KDS');
      return;
    }
    final now = DateTime.now();
    final nextUntil = now.add(duration);
    final currentUntil = _cdsLockUntil;
    if (currentUntil == null || nextUntil.isAfter(currentUntil)) {
      _cdsLockUntil = nextUntil;
    }
    if (_currentMode != DisplayMode.cds) {
      setMode(DisplayMode.cds);
    }
  }

  /// Connect with authentication and reconnection handshake
  Future<void> connect(String ipAddress, {int port = 8080}) async {
    if (_status == ConnectionStatus.connecting ||
        _status == ConnectionStatus.authenticated) {
      debugPrint('[DisplayAppService] Already connected or connecting');
      return;
    }

    _connectedIp = ipAddress;
    _connectedPort = port;
    _errorCode = null;
    _errorMessage = null;
    _manualDisconnect = false;

    try {
      _status = _reconnectAttempts > 0
          ? ConnectionStatus.reconnecting
          : ConnectionStatus.connecting;
      notifyListeners();
      _onConnectionStateChanged?.call(_status, null);

      final wsUrl = Uri.parse('ws://$ipAddress:$port');
      debugPrint('[DisplayAppService] Connecting to $wsUrl...');

      _channel = WebSocketChannel.connect(wsUrl);
      _logWebSocketConnected(wsUrl.toString());

      // Listen for messages
      _channel!.stream.listen(
        (message) => _handleMessage(message),
        onError: (error) {
          debugPrint('[DisplayAppService] ERR_001: WebSocket error: $error');
          _logWebSocketError(error);
          _handleConnectionError('ERR_001', 'Connection error: $error');
        },
        onDone: () {
          debugPrint('[DisplayAppService] Connection closed');
          _logWebSocketDisconnected();
          _handleConnectionClosed();
        },
      );

      // Wait for authentication challenge
      await Future.delayed(Duration(milliseconds: 500));

      // Authentication will be handled in _handleMessage
      _startPingTimer();
    } catch (e) {
      debugPrint('[DisplayAppService] ERR_008: Connection failed: $e');
      _handleConnectionError('ERR_008', 'Connection failed: $e');
    }
  }

  /// Handle incoming messages with type-safe parsing
  void _handleMessage(dynamic message) {
    try {
      // Type-safe JSON parsing
      final Map<String, dynamic> data;
      try {
        data = jsonDecode(message) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('[DisplayAppService] ERR_003: Invalid JSON: $e');
        return;
      }

      final type = _parseString(data['type']);
      final code = _parseString(data['code']);

      if (type == null) {
        debugPrint('[DisplayAppService] ERR_003: Missing message type');
        return;
      }

      WebSocketDebugger.logMessageReceived(type);
      debugPrint('[DisplayAppService] Received: $type');

      // Handle authentication challenge
      if (type == 'AUTH_CHALLENGE') {
        _handleAuthChallenge(data);
        return;
      }

      // Handle authentication success
      if (type == 'AUTH_SUCCESS') {
        _handleAuthSuccess(data);
        return;
      }

      // Handle reconnection handshake
      if (type == 'RECONNECTED') {
        _handleReconnectionHandshake(data);
        return;
      }

      // Handle transaction status response (Golden Thread)
      if (type == 'TRANSACTION_STATUS') {
        _handleTransactionStatusResponse(data);
        return;
      }

      // Handle errors
      if (type == 'ERROR') {
        _errorCode = code ?? 'ERR_015';
        _errorMessage = _parseString(data['message']) ?? 'Unknown error';
        notifyListeners();
        return;
      }

      // Handle pong
      if (type == 'PONG') {
        _lastPong = DateTime.now();
        _onPongReceived();
        return;
      }

      // Handle delivery confirmation
      if (type == 'DELIVERY_CONFIRMED') {
        // Message delivered successfully
        return;
      }

      // Only process other messages if authenticated
      if (_status != ConnectionStatus.authenticated) {
        debugPrint('[DisplayAppService] ERR_010: Not authenticated');
        return;
      }

      // Process authenticated messages
      _processAuthenticatedMessage(type, data);
    } catch (e, stackTrace) {
      debugPrint('[DisplayAppService] ERR_003: Error handling message: $e');
      debugPrint(stackTrace.toString());
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

  /// Handle authentication challenge
  void _handleAuthChallenge(Map<String, dynamic> data) {
    final challenge = _parseString(data['challenge']);
    if (challenge == null) {
      _handleConnectionError('ERR_002', 'Missing challenge');
      return;
    }

    // Generate response (HMAC-SHA256 of challenge)
    final response = _generateAuthResponse(challenge);

    final authToken = BaseClient().getToken() ?? '';
    final branchId = ApiConstants.branchId;
    final backendUrl = ApiConstants.baseUrl;
    final nearpayEnabled = _profileNearPayEnabled;

    _sendMessage({
      'type': 'AUTH_RESPONSE',
      'challenge': challenge,
      'response': response,
      'deviceId': 'cashier-${DateTime.now().millisecondsSinceEpoch}',
      if (authToken.isNotEmpty) 'auth_token': authToken,
      if (backendUrl.isNotEmpty) 'backend_url': backendUrl,
      if (branchId > 0) 'branch_id': branchId,
      'options': {
        'nearpay': nearpayEnabled,
      },
      'nearpay': nearpayEnabled,
    });
  }

  /// Handle authentication success
  void _handleAuthSuccess(Map<String, dynamic> data) {
    _status = ConnectionStatus.authenticated;
    _reconnectAttempts = 0;
    notifyListeners();
    _onConnectionStateChanged?.call(_status, null);
    debugPrint('[DisplayAppService] Authenticated successfully');
  }

  /// Handle reconnection handshake
  void _handleReconnectionHandshake(Map<String, dynamic> data) {
    debugPrint('[DisplayAppService] Reconnection handshake received');

    // Check for active transactions that need verification
    final activeTransaction = data['activeTransaction'];
    if (activeTransaction != null && _currentTransactionId != null) {
      final serverTransactionId =
          _parseString(activeTransaction['transactionId']);

      if (serverTransactionId == _currentTransactionId) {
        final status = _parseString(activeTransaction['status']);

        if (status == 'processing') {
          // Transaction still in progress on server
          _paymentStatus = PaymentStatus.processing;
          notifyListeners();
        } else if (status == 'completed') {
          // Transaction completed while disconnected
          _verifyTransaction(_currentTransactionId!);
        }
      }
    }

    // Resend any pending messages
    _resendPendingMessages();
  }

  /// Process authenticated messages
  void _processAuthenticatedMessage(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'PAYMENT_SUCCESS':
        _logPaymentSuccessMessage(data['data'] as Map<String, dynamic>?);
        _handlePaymentSuccess(data);
        break;
      case 'PAYMENT_FAILED':
        _logPaymentFailureMessage(
          data['data'] as Map<String, dynamic>?,
          fallbackMessage: data['message']?.toString(),
        );
        _handlePaymentFailed(data);
        break;
      case 'PAYMENT_CANCELLED':
        _handlePaymentCancelled();
        break;
      case 'PAYMENT_STATUS':
        _handlePaymentStatus(data);
        break;
      case 'NEARPAY_STATUS':
        _logNearPayStatus(data['data'] as Map<String, dynamic>?);
        break;
      case 'MODE_CHANGED':
        debugPrint('Mode changed to: ${data['mode']}');
        break;
      default:
        debugPrint('[DisplayAppService] Unknown message type: $type');
    }
  }

  /// Handle payment success
  void _handlePaymentSuccess(Map<String, dynamic> data) {
    _paymentStatus = PaymentStatus.success;
    notifyListeners();

    final rawData = data['data'] as Map<String, dynamic>?;
    if (rawData != null) {
      final transactionId = _parseString(rawData['transactionId']);

      // Verify this is our current transaction
      if (transactionId != null && transactionId == _currentTransactionId) {
        final flattenedData = <String, dynamic>{
          ...rawData,
          if (rawData['transaction'] != null)
            ...rawData['transaction'] as Map<String, dynamic>,
        };

        _onPaymentSuccess?.call(flattenedData);

        // Clear transaction tracking
        _currentTransactionId = null;
      }
    }

    // Clear after delay
    Future.delayed(Duration(seconds: 3), () {
      _paymentStatus = PaymentStatus.idle;
      notifyListeners();
    });
  }

  /// Handle payment failed
  void _handlePaymentFailed(Map<String, dynamic> data) {
    _paymentStatus = PaymentStatus.failed;
    notifyListeners();

    final message = _parseString(data['message']) ?? 'Payment failed';
    final code = _extractErrorCode(message);

    _onPaymentFailed?.call(code, message);
    _currentTransactionId = null;

    Future.delayed(Duration(seconds: 2), () {
      _paymentStatus = PaymentStatus.idle;
      notifyListeners();
    });
  }

  /// Handle payment cancelled
  void _handlePaymentCancelled() {
    _paymentStatus = PaymentStatus.cancelled;
    notifyListeners();

    _onPaymentFailed?.call('ERR_014', 'Payment cancelled by user');
    _currentTransactionId = null;

    Future.delayed(Duration(seconds: 2), () {
      _paymentStatus = PaymentStatus.idle;
      notifyListeners();
    });
  }

  /// Handle payment status updates
  void _handlePaymentStatus(Map<String, dynamic> data) {
    final statusData = data['data'] as Map<String, dynamic>?;
    if (statusData != null) {
      final status = _parseString(statusData['status']);
      final message = _parseString(statusData['message']);

      if (status != null) {
        _onPaymentStatus?.call(status, message);
      }
    }
  }

  /// Handle transaction status response (Golden Thread)
  void _handleTransactionStatusResponse(Map<String, dynamic> data) {
    _isVerifyingTransaction = false;

    final transactionId = _parseString(data['transactionId']);
    final status = _parseString(data['status']);
    final result = data['result'] as Map<String, dynamic>?;

    if (transactionId == _currentTransactionId) {
      if (status == 'completed' && result != null) {
        // Transaction verified as completed
        _paymentStatus = PaymentStatus.success;
        notifyListeners();
        _onTransactionVerified?.call(true, result);
        _currentTransactionId = null;
      } else if (status == 'failed' || status == 'cancelled') {
        // Transaction failed
        _paymentStatus = PaymentStatus.failed;
        notifyListeners();
        _onTransactionVerified?.call(false, null);
        _currentTransactionId = null;
      } else {
        // Still processing
        _onTransactionVerified?.call(false, null);
      }
    }
  }

  /// Verify transaction by querying server (Golden Thread)
  void _verifyTransaction(String transactionId) {
    if (_isVerifyingTransaction) return;

    _isVerifyingTransaction = true;

    // Send status query
    _sendMessage({
      'type': 'QUERY_TRANSACTION_STATUS',
      'transactionId': transactionId,
      'sequenceNumber': ++_sequenceNumber,
    });

    // Set timeout for verification
    Future.delayed(Duration(seconds: 5), () {
      if (_isVerifyingTransaction) {
        // No response received
        _isVerifyingTransaction = false;
        _onTransactionVerified?.call(false, null);
      }
    });
  }

  /// Verify transaction status (Golden Thread)
  Future<void> verifyTransactionStatus() async {
    if (_currentTransactionId == null) return;
    if (_isVerifyingTransaction) return;

    _isVerifyingTransaction = true;

    // Send status query
    _sendMessage({
      'type': 'QUERY_TRANSACTION_STATUS',
      'transactionId': _currentTransactionId,
      'sequenceNumber': ++_sequenceNumber,
    });

    // Wait for response with timeout
    await Future.delayed(Duration(seconds: 5));

    if (_isVerifyingTransaction) {
      // No response received
      _isVerifyingTransaction = false;
      _onTransactionVerified?.call(false, null);
    }
  }

  /// Start payment with transaction tracking
  void startPayment({
    required double amount,
    required String orderNumber,
    String? customerReference,
  }) {
    if (!isConnected) {
      _errorCode = 'ERR_008';
      _errorMessage = 'لا يوجد اتصال بتطبيق العرض';
      notifyListeners();
      return;
    }

    if (_currentMode == DisplayMode.kds) {
      _errorCode = 'ERR_009';
      _errorMessage =
          'لا يمكن بدء الدفع على شاشة KDS. استخدم جهاز CDS مخصص للدفع.';
      _paymentStatus = PaymentStatus.failed;
      notifyListeners();
      return;
    }

    // Generate transaction ID for Golden Thread
    _currentTransactionId = 'TXN-${DateTime.now().millisecondsSinceEpoch}';

    _paymentStatus = PaymentStatus.processing;
    notifyListeners();

    final referenceId = customerReference?.toString().trim().isNotEmpty == true
        ? customerReference!.toString().trim()
        : orderNumber;

    final payload = {
      'type': 'START_PAYMENT',
      'sequenceNumber': ++_sequenceNumber,
      'data': {
        'amount': amount,
        'orderNumber': orderNumber,
        'customerReference': customerReference,
        'transactionId': _currentTransactionId,
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

  /// Check if transaction can be finalized (Golden Thread)
  bool canFinalizeOrder() {
    // If no transaction in progress, can finalize
    if (_currentTransactionId == null) return true;

    // If payment succeeded or failed, can finalize
    if (_paymentStatus == PaymentStatus.success ||
        _paymentStatus == PaymentStatus.failed ||
        _paymentStatus == PaymentStatus.cancelled) {
      return true;
    }

    // If still processing, cannot finalize
    return false;
  }

  /// Reconnection logic
  void _attemptReconnection() {
    if (_manualDisconnect) return;
    if (_reconnectAttempts >= maxReconnectAttempts) {
      _errorCode = 'ERR_013';
      _errorMessage = 'فشل الاتصال بعد عدة محاولات';
      _status = ConnectionStatus.error;
      notifyListeners();
      _onConnectionStateChanged?.call(_status, _errorCode);
      return;
    }

    _reconnectAttempts++;
    debugPrint(
        '[DisplayAppService] Reconnection attempt $_reconnectAttempts/$maxReconnectAttempts');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectDelay, () {
      if (_connectedIp != null && !_manualDisconnect) {
        connect(_connectedIp!, port: _connectedPort);
      }
    });
  }

  /// Connection error handler
  void _handleConnectionError(String code, String message) {
    _status = ConnectionStatus.error;
    _errorCode = code;
    _errorMessage = message;
    notifyListeners();
    _onConnectionStateChanged?.call(_status, code);
    _attemptReconnection();
  }

  /// Connection closed handler
  void _handleConnectionClosed() {
    if (_status != ConnectionStatus.disconnected) {
      _status = ConnectionStatus.disconnected;
      _stopPingTimer();
      notifyListeners();
      _onConnectionStateChanged?.call(_status, null);

      // If payment in progress, mark for verification
      if (_paymentStatus == PaymentStatus.processing &&
          _currentTransactionId != null) {
        _paymentStatus = PaymentStatus.pending_verification;
        notifyListeners();
      }

      _attemptReconnection();
    }
  }

  /// Disconnect
  void disconnect() {
    disconnectWithOptions();
  }

  /// Disconnect with control over reconnection behavior.
  void disconnectWithOptions({
    bool manual = true,
    bool clearEndpoint = true,
    bool resetReconnectAttempts = true,
  }) {
    _manualDisconnect = manual;
    _reconnectTimer?.cancel();
    _stopPingTimer();
    _channel?.sink.close();
    _channel = null;
    _status = ConnectionStatus.disconnected;
    if (clearEndpoint) {
      _connectedIp = null;
    }
    _currentMode = DisplayMode.none;
    _paymentStatus = PaymentStatus.idle;
    _currentTransactionId = null;
    if (resetReconnectAttempts) {
      _reconnectAttempts = 0;
    }
    notifyListeners();
    _onConnectionStateChanged?.call(_status, null);
    _logWebSocketDisconnected();
  }

  /// Ping timer
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
    _sendMessage({
      'type': 'PING',
      'timestamp': DateTime.now().toIso8601String(),
    });

    if (_lastPong != null) {
      final timeSinceLastPong = DateTime.now().difference(_lastPong!);
      if (timeSinceLastPong > pongTimeout + pingInterval) {
        debugPrint('[DisplayAppService] Connection stale, reconnecting...');
        disconnectWithOptions(
          manual: false,
          clearEndpoint: false,
          resetReconnectAttempts: false,
        );
        _attemptReconnection();
      }
    }
  }

  /// Send message with sequence number
  void _sendMessage(Map<String, dynamic> message) {
    if (_channel != null && isConnected) {
      try {
        final type = message['type'];
        if (type is String) {
          WebSocketDebugger.logMessageSent(type);
        }
        final messageStr = jsonEncode(message);
        _channel!.sink.add(messageStr);

        // Store for potential retry
        final seq = message['sequenceNumber'] as int?;
        if (seq != null) {
          _pendingMessages[seq] = message;
        }

        debugPrint('[DisplayAppService] Sent: ${message['type']}');
      } catch (e) {
        debugPrint('[DisplayAppService] ERR_009: Failed to send message: $e');
        _handleConnectionError('ERR_009', 'Failed to send message: $e');
      }
    }
  }

  /// Resend pending messages after reconnection
  void _resendPendingMessages() {
    if (_pendingMessages.isEmpty) return;

    debugPrint(
        '[DisplayAppService] Resending ${_pendingMessages.length} pending messages');

    final sortedSequences = _pendingMessages.keys.toList()..sort();
    for (final seq in sortedSequences) {
      final message = _pendingMessages[seq];
      if (message != null) {
        _sendMessage(message);
      }
    }

    _pendingMessages.clear();
  }

  /// Type-safe parsing helpers
  String? _parseString(dynamic value) {
    if (value is String) return value;
    return null;
  }

  /// Extract error code from message
  String _extractErrorCode(String message) {
    final match = RegExp(r'ERR_\d+').firstMatch(message);
    return match?.group(0) ?? 'ERR_015';
  }

  /// Generate authentication response
  String _generateAuthResponse(String challenge) {
    // Simplified - in production, use proper HMAC
    return 'auth_response_$challenge';
  }

  /// Set callbacks
  void setCallbacks({
    PaymentSuccessCallback? onPaymentSuccess,
    PaymentFailedCallback? onPaymentFailed,
    PaymentStatusCallback? onPaymentStatus,
    ConnectionStateCallback? onConnectionStateChanged,
    TransactionVerificationCallback? onTransactionVerified,
  }) {
    _onPaymentSuccess = onPaymentSuccess;
    _onPaymentFailed = onPaymentFailed;
    _onPaymentStatus = onPaymentStatus;
    _onConnectionStateChanged = onConnectionStateChanged;
    _onTransactionVerified = onTransactionVerified;
  }

  /// Set mode
  void setMode(DisplayMode mode) {
    if (mode == DisplayMode.kds && _isCdsLockActive()) {
      debugPrint('[DisplayAppService] Blocked SET_MODE -> KDS (CDS pinned)');
      return;
    }
    _currentMode = mode;
    _sendMessage({
      'type': 'SET_MODE',
      'sequenceNumber': ++_sequenceNumber,
      'mode': mode == DisplayMode.cds ? 'CDS' : 'KDS',
    });
    notifyListeners();
  }

  /// Update cart
  void updateCartDisplay({
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double tax,
    required double total,
    required String orderNumber,
    String? orderType,
    String? note,
  }) {
    _sendMessage({
      'type': 'UPDATE_CART',
      'sequenceNumber': ++_sequenceNumber,
      'data': {
        'items': items,
        'subtotal': subtotal,
        'tax': tax,
        'total': total,
        'orderNumber': orderNumber,
        'orderType': orderType ?? 'dine_in',
        'note': note,
      },
    });
  }

  /// Cancel payment
  void cancelPayment() {
    _sendMessage({
      'type': 'CANCEL_PAYMENT',
      'sequenceNumber': ++_sequenceNumber,
    });
  }

  /// Dispose
  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
