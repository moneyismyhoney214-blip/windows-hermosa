// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../display_app_service.dart';

extension DisplayAppServiceMessaging on DisplayAppService {
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
}
