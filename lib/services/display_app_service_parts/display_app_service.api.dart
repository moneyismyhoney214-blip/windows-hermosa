// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../display_app_service.dart';

extension DisplayAppServiceApi on DisplayAppService {
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
}
