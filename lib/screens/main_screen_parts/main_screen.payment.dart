// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, avoid_dynamic_calls, library_private_types_in_public_api
part of '../main_screen.dart';

extension MainScreenPayment on _MainScreenState {
  Future<void> _handlePay() async {
    if (_cart.isEmpty) return;

    Log.d('pay',
        'open_tender start type=$_selectedOrderType '
        'table=${_selectedTable?.id ?? '-'} '
        'lastTable=${_lastSelectedTable?.id ?? '-'} '
        'cart=${_cart.length}');

    final resolvedTableSelection = _selectedTable ?? _lastSelectedTable;
    if (_selectedTable == null && resolvedTableSelection != null && mounted) {
      setState(() => _selectedTable = resolvedTableSelection);
    }
    final selectedTableForValidation = resolvedTableSelection;
    final requiresTableForBookingValidation =
        _isTableOrderType(_selectedOrderType);
    if (requiresTableForBookingValidation &&
        (selectedTableForValidation == null ||
            selectedTableForValidation.id.trim().isEmpty)) {
      Log.d('pay', 'missing table — queue pending and route to tables');
      _queuePendingPaymentAfterTableSelection(
        type: 'open_tender',
        showLoadingOverlay: true,
        showSuccessDialog: true,
        clearCartOnSuccess: false,
        isNearPayCardFlow: false,
      );
      setState(() {
        // Clear empty-id ghost table so next selection starts fresh.
        if (_selectedTable != null && _selectedTable!.id.trim().isEmpty) {
          _selectedTable = null;
          _lastSelectedTable = null;
        }
        _activeTab = 'tables';
      });
      return;
    }

    if (!_hasAnyEnabledPayMethod()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 3),
          content: Text(
            'لا توجد طرق دفع مفعّلة لهذا الفرع. فعّل طريقة دفع من لوحة التحكم ثم أعد المحاولة.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_selectedTable != null) {
      _lastSelectedTable = _selectedTable;
    }
    Log.d('pay',
        'open_tender ready '
        'table=${_selectedTable?.id ?? '-'} '
        'lastTable=${_lastSelectedTable?.id ?? '-'}');

    final tenderEnabledMethods = _effectiveEnabledPayMethodsForTender();

    // Refresh deposits before tender so picker reflects available deposits (handles pre-load race / prior failed fetch).
    if (_isSalonMode && _selectedCustomer != null) {
      await _loadCustomerDeposits(_selectedCustomer!.id);
    }
    debugPrint(
        '💰 [DEPOSIT] opening tender salon=$_isSalonMode customer=${_selectedCustomer?.id} '
        'deposits=${_customerDeposits.length} selected=$_selectedDepositId');

    if (!mounted) return;
    unawaited(showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (context) => PaymentTenderDialog(
        total: _totalAmount,
        taxRate: _taxRate,
        enabledMethods: tenderEnabledMethods,
        promocodes: _cachedPromoCodes,
        appliedPromoCode: _activePromoCode,
        onPromoCodeChanged: _applyPromoCode,
        availableDeposits: _isSalonMode ? _customerDeposits : const [],
        selectedDepositId: _isSalonMode ? _selectedDepositId : null,
        onSelectDeposit: _isSalonMode
            ? (id) => setState(() => _selectedDepositId = id)
            : null,
        onNoteChanged: (note) {
          _orderNotesController.text = note;
        },
        onConfirm: () async {
          Navigator.pop(context); // Close tender
          Log.d('pay', '🧾 [PAY] confirm (single) -> processPayment');
          await _processPayment(type: 'payment');
        },
        onConfirmWithPays: (pays) async {
          Navigator.pop(context); // Close tender
          Log.d('pay', '🧾 [PAY] confirm (pays=${pays.length}) -> processPayment');
          final normalizedPays = _buildNormalizedPays(pays);
          final cardAmount = normalizedPays
              .where((pay) =>
                  _normalizePayMethod(pay['pay_method']?.toString()) == 'card')
              .fold<double>(
                0.0,
                (sum, pay) =>
                    sum +
                    ((pay['amount'] as num?)?.toDouble() ??
                        double.tryParse(pay['amount']?.toString() ?? '') ??
                        0.0),
              );

          // NearPay runs locally; dispatch to _processNearPayPayment which calls bootstrap itself.
          if (cardAmount > 0 && _isProfileNearPayEnabled) {
            await _processNearPayPayment(
              paysForInvoice: normalizedPays,
              nearPayAmount: cardAmount,
            );
            return;
          }

          await _processPayment(type: 'payment', pays: normalizedPays);
        },
      ),
    ));
  }

  /// Process NearPay payment using the local SDK.
  ///
  /// Mirrors the reference implementation from
  /// `display_app/lib/services/socket_service.dart::_handleStartPayment` —
  /// but runs entirely in-process (no WebSocket round-trip) because the
  /// NearPay SDK is now embedded in the cashier app.
  Future<void> _processNearPayPayment({
    required List<Map<String, dynamic>> paysForInvoice,
    required double nearPayAmount,
  }) async {
    final paymentAmount = nearPayAmount <= 0 ? _totalAmount : nearPayAmount;

    // Reference validation: amount must be > 0 and < 100,000 SAR.
    if (paymentAmount <= 0 || paymentAmount > 100000) {
      if (mounted) {
        UiFeedback.error(context, 'مبلغ غير صالح: ${paymentAmount.toStringAsFixed(ApiConstants.digitsNumber)}');
      }
      return;
    }

    final ValueNotifier<String> statusNotifier = ValueNotifier<String>(
      'جاري تهيئة NearPay...',
    );
    bool isWaitingDialogOpen = true;

    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ValueListenableBuilder<String>(
        valueListenable: statusNotifier,
        builder: (context, status, child) {
          return AlertDialog(
            title: const Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Expanded(
                  child: Text('جاري الدفع...', style: TextStyle(fontSize: 18)),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  status,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'المبلغ: ${paymentAmount.toStringAsFixed(ApiConstants.digitsNumber)} ${ApiConstants.currency}',
                ),
                const SizedBox(height: 8),
                const Text(
                  'اتبع تعليمات NearPay على الشاشة',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    ));

    void closeWaitingDialog() {
      if (isWaitingDialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        isWaitingDialogOpen = false;
      }
    }

    // Mirror NearPay onto the built-in CDS overlay (same states as external WebSocket CDS).
    final presentation = PresentationService();
    unawaited(presentation.startPayment({
      'amount': paymentAmount,
      'payment_method': 'nearpay',
      'timestamp': DateTime.now().toIso8601String(),
    }));

    try {
      // iOS lacks local SDK — defer to paired display_app over WebSocket and rely on the dispatcher's readiness check.
      statusNotifier.value = 'جاري تجهيز الجهاز...';
      final ready = RemoteNearPayDispatcher.isRequired
          ? true
          : await NearPayBootstrap.ensureInitialized();
      if (!ready) {
        closeWaitingDialog();
        unawaited(presentation.updatePaymentStatus(
          'failed',
          message: 'تعذر تهيئة NearPay. تأكد من الاتصال بالإنترنت وتفعيل NFC.',
        ));
        if (mounted) {
          unawaited(showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 32),
                  const SizedBox(width: 8),
                  Text(translationService.t('nearpay_not_ready_title')),
                ],
              ),
              content: Text(
                translationService.t('nearpay_init_failed_body'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(translationService.t('ok')),
                ),
              ],
            ),
          ));
        }
        return;
      }

      final sessionId = const Uuid().v4();
      final referenceId = _selectedCustomer?.id.toString() ?? sessionId;

      statusNotifier.value = 'ضع البطاقة على الجهاز...';

      // Execute purchase: Android drives the embedded SDK; iOS forwards over WebSocket to paired display_app.
      void mapStatus(String status) {
        if (!isWaitingDialogOpen) return;
        final lower = status.toLowerCase().trim();
        if (lower.isEmpty) {
          statusNotifier.value = 'جاري الدفع...';
        } else if (lower.contains('ضع البطاقة') ||
            lower.contains('waiting') ||
            lower.contains('reader')) {
          statusNotifier.value = status;
        } else if (lower.contains('pin')) {
          statusNotifier.value = 'أدخل الرقم السري...';
        } else if (lower.contains('success') ||
            lower.contains('✅')) {
          statusNotifier.value = 'تم الدفع بنجاح';
        } else {
          statusNotifier.value = status;
        }
      }

      final np_local.NearPayPaymentResult result;
      if (RemoteNearPayDispatcher.isRequired) {
        result = await RemoteNearPayDispatcher.instance.requestRemotePurchase(
          amount: paymentAmount,
          sessionId: sessionId,
          referenceId: referenceId,
          onStatusUpdate: mapStatus,
        );
      } else {
        final service = getIt<np_local.NearPayService>();
        result = await service.executePurchaseWithSession(
          amount: paymentAmount,
          sessionId: sessionId,
          referenceId: referenceId,
          onStatusUpdate: mapStatus,
        );
      }

      closeWaitingDialog();

      if (result.success) {
        unawaited(presentation.updatePaymentStatus('success'));
        if (mounted) {
          UiFeedback.success(context, translationService.t('payment_success'));
        }

        await _processPayment(
          type: 'payment',
          pays: paysForInvoice,
          showLoadingOverlay: false,
          showSuccessDialog: false,
          clearCartOnSuccess: true,
          isNearPayCardFlow: true,
        );
      } else {
        final errorMessage = result.errorMessage ?? 'فشل الدفع';
        unawaited(presentation.updatePaymentStatus(
          'failed',
          message: errorMessage,
        ));
        if (mounted) {
          unawaited(showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 32),
                  const SizedBox(width: 8),
                  Text(translationService.t('payment_failed_msg')),
                ],
              ),
              content: Text(errorMessage),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(translationService.t('ok')),
                ),
              ],
            ),
          ));
        }
      }
    } catch (e) {
      closeWaitingDialog();
      unawaited(presentation.updatePaymentStatus(
        'failed',
        message: 'خطأ في الدفع: $e',
      ));
      if (mounted) {
        UiFeedback.error(context, 'خطأ في الدفع: $e');
      }
    }
  }

  Future<void> _handlePayLater() async {
    if (_cart.isEmpty) return;
    await _processPayment(
      type: 'later',
      showSuccessDialog: true,
      clearCartOnSuccess: true,
    );
  }

  /// Salon-only: confirms the cart as a booked appointment.
  ///
  /// Mirrors the salon dashboard's "حجز موعد" button — the request hits
  /// `/seller/branches/{id}/bookings?book_appointment&create_order` so the
  /// backend files it as a confirmed appointment in the calendar instead
  /// of an order awaiting payment. On success the cart is cleared and we
  /// route the cashier to the "الحجوزات" tab so they can review the new
  /// row immediately.
  Future<void> _handleAddBooking() async {
    if (!_isSalonMode || _cart.isEmpty) return;
    if (_effectiveRequireCustomerSelection && _selectedCustomer == null) {
      UiFeedback.warning(context, _trUi('* اختيار العميل مطلوب', '* Customer is required'));
      return;
    }

    final fields = <String, String>{};
    fields['customer_id'] = _selectedCustomer?.id.toString() ?? '';

    for (var i = 0; i < _cart.length; i++) {
      final item = _cart[i];
      final salon = item.salonData ?? const <String, dynamic>{};
      final p = 'card[$i]';

      final price = item.product.price;
      final qtyStr = item.quantity == item.quantity.roundToDouble()
          ? item.quantity.toInt().toString()
          : item.quantity.toString();

      fields['$p[package_service_id]'] =
          salon['package_service_id']?.toString() ?? '';
      fields['$p[item_name]'] = item.product.name;
      fields['$p[service_id]'] =
          (salon['service_id'] ?? item.product.id).toString();
      fields['$p[minutes]'] = (salon['minutes'] ?? '').toString();
      fields['$p[employee_name]'] = salon['employee_name']?.toString() ?? '';
      fields['$p[employee_id]'] = salon['employee_id']?.toString() ?? '';
      fields['$p[date]'] = (salon['date']?.toString().isNotEmpty == true)
          ? salon['date'].toString()
          : DateFormat('yyyy-MM-dd').format(DateTime.now());
      fields['$p[time]'] = (salon['time']?.toString().isNotEmpty == true)
          ? salon['time'].toString()
          : DateFormat('HH:mm').format(DateTime.now());
      fields['$p[session_numbers]'] =
          (salon['session_numbers'] ?? 0).toString();
      fields['$p[quantity]'] = qtyStr;
      fields['$p[price]'] = _formatBookingPrice(price);
      fields['$p[unitPrice]'] = _formatBookingPrice(price);
      fields['$p[modified_unit_price]'] = '';
    }

    fields['type'] = '';
    fields['type_extra[car_number]'] = '';
    fields['type_extra[table_name]'] = '';
    fields['type_extra[latitude]'] = '';
    fields['type_extra[longitude]'] = '';

    final endpoint =
        '${ApiConstants.bookingsEndpoint}?book_appointment&create_order';

    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ));

    // Snapshot cart BEFORE the network round-trip so post-booking turn-slip print survives the on-success cart clear.
    final cartSnapshotForPrint = List<CartItem>.from(_cart);

    try {
      final client = BaseClient();
      final response = await client.postMultipart(endpoint, fields);
      // Drop salon slot cache so a second booking can't re-pick the consumed time.
      try {
        getIt<SalonEmployeeService>().invalidateAvailableTimesCache();
      } catch (e) {
        Log.d('MainScreenPayment', 'invalidate salon slot cache after booking commit failed (non-fatal): $e');
      }
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // close spinner

      String? bookingId;
      if (response is Map<String, dynamic>) {
        final data = response['data'];
        if (data is Map) {
          bookingId =
              (data['id'] ?? data['booking_id'] ?? data['booking']?['id'])
                  ?.toString();
        }
      }

      // Fire per-service turn ticket on every kitchen/KDS/bar printer — same path as cashier "دفع لاحقاً".
      if (bookingId != null && bookingId.isNotEmpty) {
        unawaited(
          _triggerSalonTurnPrint(
            orderId: bookingId,
            cartSnapshot: cartSnapshotForPrint,
          ),
        );
      }

      _clearCart();
      setState(() {
        _activeTab = 'bookings';
      });
      UiFeedback.success(context, bookingId != null && bookingId.isNotEmpty
                ? _trUi('تم إنشاء الحجز #$bookingId',
                    'Booking #$bookingId created')
                : _trUi('تم إنشاء الحجز', 'Booking created'));
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // close spinner
      UiFeedback.error(context, _trUi('فشل إنشاء الحجز: $e', 'Failed to create booking: $e'));
    }
  }
}
