// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../display_app_service.dart';

extension DisplayAppServiceInternals on DisplayAppService {
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
