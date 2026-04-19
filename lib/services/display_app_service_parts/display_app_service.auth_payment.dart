// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../display_app_service.dart';

extension DisplayAppServiceAuthPayment on DisplayAppService {
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

}
