// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../main_screen.dart';

extension MainScreenPayment on _MainScreenState {
  Future<void> _handlePay() async {
    if (_cart.isEmpty) return;

    print(
      '🧾 [PAY] open_tender start type=$_selectedOrderType table=${_selectedTable?.id ?? '-'} lastTable=${_lastSelectedTable?.id ?? '-'} cart=${_cart.length}',
    );

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
      print('🧾 [PAY] missing table -> queue pending & go tables');
      _queuePendingPaymentAfterTableSelection(
        type: 'open_tender',
        showLoadingOverlay: true,
        showSuccessDialog: true,
        clearCartOnSuccess: false,
        isNearPayCardFlow: false,
      );
      setState(() {
        // Clear any empty-id ghost table so the next selection starts fresh.
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
    print(
      '🧾 [PAY] open_tender ready table=${_selectedTable?.id ?? '-'} lastTable=${_lastSelectedTable?.id ?? '-'}',
    );

    final tenderEnabledMethods = _effectiveEnabledPayMethodsForTender();

    if (!mounted) return;
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (context) => PaymentTenderDialog(
        total: _totalAmount,
        taxRate: _taxRate,
        enabledMethods: tenderEnabledMethods,
        promocodes: _cachedPromoCodes,
        appliedPromoCode: _activePromoCode,
        onPromoCodeChanged: _applyPromoCode,
        onNoteChanged: (note) {
          _orderNotesController.text = note;
        },
        onConfirm: () async {
          Navigator.pop(context); // Close tender
          print('🧾 [PAY] confirm (single) -> processPayment');
          await _processPayment(type: 'payment');
        },
        onConfirmWithPays: (pays) async {
          Navigator.pop(context); // Close tender
          print('🧾 [PAY] confirm (pays=${pays.length}) -> processPayment');
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

          // NearPay now runs locally inside the cashier (no remote CDS/Display
          // App handshake required). Dispatch straight to _processNearPayPayment
          // which calls NearPayBootstrap.ensureInitialized() itself.
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
    );
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

    // Mirror the reference validation: amount must be > 0 and < 100,000 SAR
    if (paymentAmount <= 0 || paymentAmount > 100000) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('مبلغ غير صالح: ${paymentAmount.toStringAsFixed(2)}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Status notifier for dialog updates
    final ValueNotifier<String> statusNotifier = ValueNotifier<String>(
      'جاري تهيئة NearPay...',
    );
    bool isWaitingDialogOpen = true;

    // Show waiting dialog while the SDK native overlay appears
    showDialog(
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
                  'المبلغ: ${paymentAmount.toStringAsFixed(2)} ${ApiConstants.currency}',
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
    );

    void closeWaitingDialog() {
      if (isWaitingDialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        isWaitingDialogOpen = false;
      }
    }

    try {
      // 1️⃣ Ensure NearPay is fully bootstrapped (SDK + JWT + terminal).
      statusNotifier.value = 'جاري تجهيز الجهاز...';
      final ready = await NearPayBootstrap.ensureInitialized();
      if (!ready) {
        closeWaitingDialog();
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.error, color: Colors.red, size: 32),
                  SizedBox(width: 8),
                  Text('NearPay غير جاهز'),
                ],
              ),
              content: const Text(
                'تعذر تهيئة NearPay. تأكد من الاتصال بالإنترنت وتفعيل NFC.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(translationService.t('ok')),
                ),
              ],
            ),
          );
        }
        return;
      }

      // 2️⃣ Generate session UUID (same pattern as reference socket_service).
      final sessionId = const Uuid().v4();
      final referenceId = _selectedCustomer?.id.toString() ?? sessionId;

      statusNotifier.value = 'ضع البطاقة على الجهاز...';

      // 3️⃣ Execute purchase directly on the local NearPay SDK.
      final service = getIt<np_local.NearPayService>();
      final result = await service.executePurchaseWithSession(
        amount: paymentAmount,
        sessionId: sessionId,
        referenceId: referenceId,
        onStatusUpdate: (status) {
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
        },
      );

      closeWaitingDialog();

      if (result.success) {
        // 4️⃣ Success — chain into the normal invoice/receipt pipeline.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(translationService.t('payment_success')),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
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
        // 5️⃣ Failure — show error dialog, keep cart intact.
        final errorMessage = result.errorMessage ?? 'فشل الدفع';
        if (mounted) {
          showDialog(
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
          );
        }
      }
    } catch (e) {
      closeWaitingDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الدفع: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handlePayLater() async {
    if (_cart.isEmpty) return;
    // Pay Later: create booking only, no invoice, show success dialog
    await _processPayment(
      type: 'later',
      showSuccessDialog: true,
      clearCartOnSuccess: true,
    );
  }

  String _normalizePayMethod(String? method) {
    final rawInput = (method ?? '').trim();
    if (rawInput.isEmpty) return 'cash';
    final raw = rawInput.toLowerCase();
    final compact = raw.replaceAll(RegExp(r'[\\s_\\-]+'), '');

    if (raw.contains('آجل') || raw.contains('اجل') || raw.contains('بالآجل')) {
      return 'pay_later';
    }
    if (raw.contains('بيتي') ||
        raw.contains('بيتي كاش') ||
        raw.contains('بيتيكاش')) {
      return 'petty_cash';
    }
    if (raw.contains('تابي')) return 'tabby';
    if (raw.contains('تمارا')) return 'tamara';
    if (raw.contains('كيتا')) return 'keeta';
    if (raw.contains('ماي فاتورة') ||
        raw.contains('ماي_فاتورة') ||
        raw.contains('مايفاتورة')) {
      return 'my_fatoorah';
    }
    if (raw.contains('جاهز')) return 'jahez';
    if (raw.contains('طلبات')) return 'talabat';
    if (raw.contains('هنقر') || raw.contains('هنجر')) return 'hunger_station';
    if (raw.contains('تحويل')) return 'bank_transfer';
    if (raw.contains('محفظة')) return 'wallet';
    if (raw.contains('شيك')) return 'cheque';
    if (raw.contains('بينيفت') || raw.contains('بنفت')) return 'benefit';
    if (raw.contains('اس تي سي') ||
        raw.contains('stc') ||
        raw.contains('اس_تي_سي')) {
      return 'stc';
    }
    if (raw.contains('مدى')) return 'mada';
    if (raw.contains('بطاقة') ||
        raw.contains('فيزا') ||
        raw.contains('ماستر')) {
      return 'card';
    }
    if (raw.contains('نقد')) return 'cash';

    switch (compact) {
      case 'cash':
      case 'cashpayment':
        return 'cash';
      case 'pettycash':
      case 'petty_cash':
        return 'petty_cash';
      case 'paylater':
      case 'pay_later':
      case 'postpaid':
      case 'deferred':
        return 'pay_later';
      case 'card':
      case 'creditcard':
      case 'debitcard':
        return 'card';
      case 'mada':
        return 'mada';
      case 'visa':
      case 'mastercard':
        return 'visa';
      case 'benefit':
      case 'benefitpay':
      case 'benefit_pay':
        return 'benefit';
      case 'stc':
      case 'stcpay':
      case 'stc_pay':
        return 'stc';
      case 'bank':
      case 'banktransfer':
      case 'bank_transfer':
      case 'transfer':
        return 'bank_transfer';
      case 'wallet':
      case 'ewallet':
      case 'electronicwallet':
        return 'wallet';
      case 'cheque':
      case 'check':
        return 'cheque';
      case 'tabby':
      case 'taby':
        return 'tabby';
      case 'tamara':
        return 'tamara';
      case 'keeta':
      case 'kita':
        return 'keeta';
      case 'myfatoorah':
      case 'my_fatoorah':
      case 'myfatora':
      case 'myfatoora':
      case 'my_fatoora':
        return 'my_fatoorah';
      case 'jahez':
      case 'gahez':
        return 'jahez';
      case 'talabat':
        return 'talabat';
      case 'hungerstation':
      case 'hunger_station':
      case 'hunger':
        return 'hunger_station';
      default:
        return 'cash';
    }
  }

  bool _isCashOnlyPayment(List<Map<String, dynamic>> pays) {
    if (pays.isEmpty) return false;
    bool hasPositiveAmount = false;
    for (final pay in pays) {
      final amount = (pay['amount'] as num?)?.toDouble() ??
          double.tryParse(pay['amount']?.toString() ?? '') ??
          0.0;
      if (amount <= 0) continue;
      hasPositiveAmount = true;
      final normalized = _normalizePayMethod(pay['pay_method']?.toString());
      if (normalized != 'cash') return false;
    }
    return hasPositiveAmount;
  }

  Future<void> _showCashPaymentSuccessOnCds({
    required DisplayAppService displayService,
    required List<Map<String, dynamic>> pays,
  }) async {
    if (!_isCdsEnabled) return;
    if (!displayService.isConnected && !displayService.isPresentationActive) return;

    displayService.pinCdsModeTemporarily(duration: const Duration(seconds: 12));
    displayService.updatePaymentStatus('success');

    await Future.delayed(const Duration(seconds: 3));
    displayService.clearPaymentDisplay();
  }

  bool _isMethodEnabledForInvoice(String normalizedMethod) {
    if (normalizedMethod == 'card' &&
        _isProfileNearPayEnabled &&
        !_isCdsEnabled) {
      return false;
    }

    if (_enabledPayMethods[normalizedMethod] == true) return true;
    if (normalizedMethod == 'card') {
      return _enabledPayMethods['mada'] == true ||
          _enabledPayMethods['visa'] == true ||
          _enabledPayMethods['benefit'] == true;
    }
    return false;
  }

  bool _hasAnyEnabledPayMethod() {
    const supported = {
      'cash',
      'card',
      'mada',
      'visa',
      'benefit',
      'stc',
      'bank_transfer',
      'wallet',
      'cheque',
      'petty_cash',
      'pay_later',
      'tabby',
      'tamara',
      'keeta',
      'my_fatoorah',
      'jahez',
      'talabat',
      'hunger_station',
    };
    for (final entry in _enabledPayMethods.entries) {
      if (supported.contains(entry.key) && entry.value == true) {
        if (_isProfileNearPayEnabled &&
            !_isCdsEnabled &&
            (entry.key == 'card' ||
                entry.key == 'mada' ||
                entry.key == 'visa' ||
                entry.key == 'benefit')) {
          continue;
        }
        return true;
      }
    }
    return false;
  }

  Map<String, bool> _effectiveEnabledPayMethodsForTender() {
    final effective = Map<String, bool>.from(_enabledPayMethods);
    // "Pay later" is a booking status, not a valid invoice pay_method.
    effective['pay_later'] = false;
    // NearPay handles card payments — keep them visible for split payment
    // but the actual NearPay flow is triggered in _processPayment.
    return effective;
  }

  List<Map<String, dynamic>> _buildNormalizedPays(
    List<Map<String, dynamic>>? pays, {
    double? targetTotal,
  }) {
    final effectiveTotal = targetTotal ?? _totalAmount;

    String resolveAllowedMethod(String method) {
      final normalized = _normalizePayMethod(method);
      if (_isMethodEnabledForInvoice(normalized)) return normalized;
      const fallbackCandidates = [
        'cash',
        'card',
        'stc',
        'bank_transfer',
        'wallet',
        'cheque',
      ];
      for (final candidate in fallbackCandidates) {
        if (_isMethodEnabledForInvoice(candidate)) return candidate;
      }
      throw Exception(
        'لا توجد طرق دفع مفعّلة لهذا الفرع. يرجى تفعيل طريقة دفع من لوحة التحكم.',
      );
    }

    if (pays == null || pays.isEmpty) {
      final method = resolveAllowedMethod('cash');
      return [
        {
          'name': method == 'card' ? 'دفع بطاقة' : 'دفع نقدي',
          'pay_method': method,
          'amount': double.parse(effectiveTotal.toStringAsFixed(2)),
          'index': 0,
        },
      ];
    }

    return pays.asMap().entries.map((entry) {
      final index = entry.key;
      final pay = entry.value;
      final method = resolveAllowedMethod(pay['pay_method']?.toString() ?? '');
      final amount = (pay['amount'] as num?)?.toDouble() ??
          double.tryParse(pay['amount']?.toString() ?? '') ??
          0.0;
      final roundedAmount = double.parse(amount.toStringAsFixed(2));
      return {
        'name': pay['name']?.toString().trim().isNotEmpty == true
            ? pay['name']
            : method,
        'pay_method': method,
        'amount': roundedAmount,
        'index': index,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _buildUpdatePaysPayload(
    List<Map<String, dynamic>> pays,
    double invoiceTotal, {
    bool preserveCardAmounts = false,
  }) {
    double round2(double value) => double.parse(value.toStringAsFixed(2));
    num toBackendAmount(double value) {
      final rounded = round2(value);
      final asInt = rounded.roundToDouble();
      if ((rounded - asInt).abs() < 0.000001) {
        return asInt.toInt();
      }
      return rounded;
    }

    final normalized = <Map<String, dynamic>>[];
    double sum = 0.0;
    var outIndex = 0;

    for (final pay in pays) {
      final method = _normalizePayMethod(pay['pay_method']?.toString() ?? '');
      final amount = (pay['amount'] as num?)?.toDouble() ??
          double.tryParse(pay['amount']?.toString() ?? '') ??
          0.0;
      if (amount <= 0) continue;
      final roundedAmount = round2(amount);
      normalized.add({
        'name': pay['name']?.toString().trim().isNotEmpty == true
            ? pay['name']
            : (method == 'card' ? 'البطاقة' : 'دفع نقدي'),
        'pay_method': method,
        'amount': toBackendAmount(roundedAmount),
        'index': outIndex++,
      });
      sum += roundedAmount;
    }

    if (normalized.isEmpty) {
      return [
        {
          'name': 'دفع نقدي',
          'pay_method': 'cash',
          'amount': toBackendAmount(invoiceTotal),
          'index': 0,
        }
      ];
    }

    int resolveAdjustmentIndex() {
      if (!preserveCardAmounts || normalized.isEmpty) {
        return normalized.length - 1;
      }
      for (var i = normalized.length - 1; i >= 0; i--) {
        final method =
            _normalizePayMethod(normalized[i]['pay_method']?.toString() ?? '');
        if (method != 'card') return i;
      }
      return normalized.length - 1;
    }

    final targetTotal = round2(invoiceTotal);
    final currentTotal = round2(sum);
    final diff = round2(targetTotal - currentTotal);
    // Adjust even for a 0.01 difference to satisfy backend strict validation.
    if (diff.abs() >= 0.01) {
      final adjustmentIndex = resolveAdjustmentIndex();
      final currentAmount =
          (normalized[adjustmentIndex]['amount'] as num?)?.toDouble() ?? 0.0;
      normalized[adjustmentIndex]['amount'] = toBackendAmount(
        (currentAmount + diff).clamp(0.0, double.infinity),
      );
    }

    // Final safety pass: force exact 2-decimal total by correcting last pay.
    final recomputedSum = round2(normalized.fold<double>(
      0.0,
      (acc, p) => acc + ((p['amount'] as num?)?.toDouble() ?? 0.0),
    ));
    final finalDiff = round2(targetTotal - recomputedSum);
    if (finalDiff != 0 && normalized.isNotEmpty) {
      final adjustmentIndex = resolveAdjustmentIndex();
      final currentAmount =
          (normalized[adjustmentIndex]['amount'] as num?)?.toDouble() ?? 0.0;
      normalized[adjustmentIndex]['amount'] = toBackendAmount(
        (currentAmount + finalDiff).clamp(0.0, double.infinity),
      );
    }

    return normalized;
  }

  List<int> _toAddonIdList(List<Extra> extras) {
    final ids = <int>[];
    for (final extra in extras) {
      final parsedId = int.tryParse(extra.id.toString().trim());
      if (parsedId != null) ids.add(parsedId);
    }
    return ids;
  }

  Future<bool> _waitForKdsAck(
    DisplayAppService displayService,
    String orderId, {
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    final targetOrderId = orderId.trim();
    if (targetOrderId.isEmpty) return false;

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final ackId = displayService.lastOrderAckId?.trim();
      final ackAt = displayService.lastOrderAckAt;
      if (ackId == targetOrderId &&
          ackAt != null &&
          DateTime.now().difference(ackAt) <= const Duration(seconds: 8)) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }
    return false;
  }

  Future<bool> _dispatchOrderToKdsWithAck({
    required DisplayAppService displayService,
    required String orderId,
    required String orderNumber,
    required String orderType,
    required List<Map<String, dynamic>> items,
    String? note,
    required double total,
    Map<String, dynamic>? invoice,
    bool allowModeSwitchFallback = true,
  }) async {
    void send() {
      displayService.sendOrderToKitchen(
        orderId: orderId,
        orderNumber: orderNumber,
        orderType: orderType,
        items: items,
        note: note,
        total: total,
        invoice: invoice,
        switchMode: false,
      );
    }

    send();

    if (!displayService.isConnected) {
      // Message will remain queued until websocket reconnects.
      return false;
    }

    var acked = await _waitForKdsAck(displayService, orderId);
    if (acked) {
      return true;
    }

    if (!allowModeSwitchFallback) {
      return false;
    }

    final canSwitchToKds = _isKdsEnabled &&
        displayService.isConnected &&
        displayService.currentMode != DisplayMode.kds &&
        !displayService.isPaymentProcessing;

    if (canSwitchToKds) {
      displayService.setMode(DisplayMode.kds, force: true);
      await Future.delayed(const Duration(milliseconds: 250));
      send();
      acked = await _waitForKdsAck(
        displayService,
        orderId,
        timeout: const Duration(milliseconds: 1200),
      );
    }

    return acked;
  }

  Future<void> _processPayment({
    required String type,
    List<Map<String, dynamic>>? pays,
    bool showLoadingOverlay = true,
    bool showSuccessDialog = true,
    bool clearCartOnSuccess = true,
    bool isNearPayCardFlow = false,
  }) async {
    print(
      '🧾 [PAY] process start type=$type orderType=$_selectedOrderType table=${_selectedTable?.id ?? '-'} lastTable=${_lastSelectedTable?.id ?? '-'} cart=${_cart.length} pays=${pays?.length ?? 0} nearPay=$isNearPayCardFlow',
    );
    if (_cart.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(translationService.t('cart_empty_error')),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (type == 'payment' && !_hasAnyEnabledPayMethod()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'لا توجد طرق دفع مفعّلة لهذا الفرع. فعّل طريقة دفع من لوحة التحكم ثم أعد المحاولة.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final carNumber = _carNumberController.text.trim();
    if (_isCarOrderType() && carNumber.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _trUi(
                'رقم السيارة مطلوب لطلبات السيارات',
                'Car number is required for car orders',
              ),
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    if (!mounted) return;

    final resolvedTableSelection = _selectedTable ?? _lastSelectedTable;
    if (_selectedTable == null && resolvedTableSelection != null && mounted) {
      setState(() => _selectedTable = resolvedTableSelection);
    }
    final selectedTableForValidation = resolvedTableSelection;
    final requiresTableForBookingValidation =
        _isTableOrderType(_selectedOrderType);
    if (requiresTableForBookingValidation &&
        selectedTableForValidation == null) {
      print('🧾 [PAY] process missing table -> queue & go tables');
      if (type == 'payment') {
        _queuePendingPaymentAfterTableSelection(
          type: type,
          pays: pays,
          showLoadingOverlay: showLoadingOverlay,
          showSuccessDialog: showSuccessDialog,
          clearCartOnSuccess: clearCartOnSuccess,
          isNearPayCardFlow: isNearPayCardFlow,
        );
      }
      setState(() => _activeTab = 'tables');
      return;
    }

    // Loading overlay intentionally suppressed — payment proceeds in the
    // background without blocking the UI. The matching Navigator.pop guards
    // below short-circuit because no dialog was pushed.
    showLoadingOverlay = false;

    try {
      final orderService = getIt<OrderService>();
      final displayService = getIt<DisplayAppService>();
      if (type == 'payment' && _isCdsEnabled) {
        displayService.pinCdsModeTemporarily(
          duration: const Duration(seconds: 18),
        );
      }
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final grossOrderTotal = _grossOrderTotal;
      double appliedDiscountAmount =
          _resolveEffectiveDiscountAmount(grossOrderTotal);
      double orderTotal =
          (grossOrderTotal - appliedDiscountAmount).clamp(0.0, double.infinity);
      double payableTotal = orderTotal;
      String? promoCodeId = _activePromoCode?.id;
      String? promoCodeValue = _activePromoCode?.code.trim();
      String? promoDiscountType = _activePromoCode == null
          ? null
          : (_activePromoCode!.type == DiscountType.percentage
              ? 'percentage'
              : 'fixed');
      var promoRemovedDueToExpiry = false;

      bool isExpiredPromoMessage(String message) {
        final normalized = message.trim().toLowerCase();
        if (normalized.isEmpty) return false;
        final hasPromoToken = normalized.contains('برومو') ||
            normalized.contains('promo') ||
            normalized.contains('promocode');
        final hasExpiredToken = normalized.contains('انتهت') ||
            normalized.contains('منتهي') ||
            normalized.contains('صلاحية') ||
            normalized.contains('expire');
        return hasPromoToken && hasExpiredToken;
      }

      void clearActivePromoSelectionLocally() {
        if (_activePromoCode == null) return;
        _applyPromoCode(null);
      }

      Map<String, dynamic>? asStringKeyMap(dynamic value) {
        if (value is Map<String, dynamic>) return value;
        if (value is Map) {
          return value.map((key, val) => MapEntry(key.toString(), val));
        }
        return null;
      }

      Future<Map<String, dynamic>?> resolveInvoicePayloadForPreview(
        String? invoiceId,
        Map<String, dynamic>? fallbackPayload,
      ) async {
        if (invoiceId == null || invoiceId.trim().isEmpty) {
          return fallbackPayload;
        }

        // FAST PATH: Use pre-cached branch/seller data instead of API calls
        if (_cachedBranchMap != null && _cachedSellerInfo != null) {
          debugPrint('⏱️ [PRINT_TIMER] FAST PATH — using cached data (0ms)');
          final synthesized = Map<String, dynamic>.from(fallbackPayload ?? {});
          if (!synthesized.containsKey('branch')) {
            synthesized['branch'] = _cachedBranchMap;
          }
          synthesized['branch_address_en'] ??= _cachedBranchAddressEn;
          synthesized['branch_district_en'] ??= _cachedBranchAddressEn;
          synthesized['seller_name_en'] ??= _cachedSellerNameEn;
          return synthesized;
        }

        debugPrint('⏱️ [PRINT_TIMER] SLOW PATH — cache miss (branchMap=${_cachedBranchMap != null}, sellerInfo=${_cachedSellerInfo != null}), calling API...');
        try {
          final savedLang = ApiConstants.acceptLanguage;

          // Fetch Arabic + English in parallel (saves ~2 seconds)
          final arFuture = orderService
              .getInvoice(invoiceId)
              .timeout(const Duration(seconds: 3));
          // English fetch: set header, call, restore
          final enFuture = () async {
            try {
              ApiConstants.setAcceptLanguage('en');
              final resp = await orderService
                  .getInvoice(invoiceId)
                  .timeout(const Duration(seconds: 3));
              return resp;
            } catch (_) {
              return null;
            } finally {
              ApiConstants.setAcceptLanguage(savedLang);
            }
          }();

          final results = await Future.wait([arFuture, enFuture]);
          final detailsResponse = results[0];
          final enResponse = results[1];

          final detailsMap = asStringKeyMap(detailsResponse);
          final detailsData = asStringKeyMap(detailsMap?['data']);
          final arPayload = (detailsData != null && detailsData.isNotEmpty)
              ? detailsData
              : (detailsMap != null && detailsMap.isNotEmpty ? detailsMap : null);

          // Merge English fields into Arabic payload
          if (arPayload != null && enResponse != null) {
            try {
              final enMap = asStringKeyMap(enResponse);
              final enData = asStringKeyMap(enMap?['data']) ?? enMap;

              if (enData != null) {
                final enBranch = asStringKeyMap(enData['branch']);
                final enInvoice = asStringKeyMap(enData['invoice']) ?? enData;
                arPayload['branch_address_en'] = enBranch?['address'];
                arPayload['branch_district_en'] = enBranch?['district'];
                arPayload['seller_name_en'] = enBranch?['seller_name'];
                final arItems = (arPayload['invoice'] is Map)
                    ? (arPayload['invoice'] as Map)['items']
                    : arPayload['items'];
                final enItems = enInvoice['items'];
                if (arItems is List && enItems is List) {
                  for (var i = 0; i < arItems.length && i < enItems.length; i++) {
                    if (arItems[i] is Map && enItems[i] is Map) {
                      arItems[i]['item_name_en'] = enItems[i]['item_name'];
                    }
                  }
                }
              }
            } catch (_) {}
          }
          if (arPayload != null) return arPayload;
        } catch (e) {
          debugPrint(
            '⚠️ Could not load invoice details for preview (invoice_id=$invoiceId): $e',
          );
        }
        return fallbackPayload;
      }

      String? firstNonEmptyText(
        List<dynamic> values, {
        bool allowZero = true,
      }) {
        for (final value in values) {
          final text = value?.toString().trim();
          if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
            continue;
          }
          if (!allowZero) {
            final normalized = text.startsWith('#') ? text.substring(1) : text;
            final parsed = int.tryParse(normalized);
            if (parsed != null && parsed == 0) {
              continue;
            }
          }
          return text;
        }
        return null;
      }

      String normalizeDisplayOrderRef(String raw) {
        final value = raw.trim();
        if (value.isEmpty) return value;
        if (value.startsWith('#')) return value;
        if (RegExp(r'^\d+$').hasMatch(value)) return '#$value';
        return value;
      }

      final cartItemsForOrder =
          _cart.where((item) => item.quantity > 0).toList();
      if (cartItemsForOrder.isEmpty) {
        throw Exception(translationService.t('cart_empty_error'));
      }
      final selectedTableForOrder = resolvedTableSelection;
      print(
        '🧾 [PAY] order table resolved=${selectedTableForOrder?.id ?? '-'}',
      );
      final bookingOrderType =
          _resolveOrderTypeForBooking(selectedTableForOrder);
      final requiresTableForBooking = _isTableOrderType(_selectedOrderType);
      String? resolvedTableName;
      if (selectedTableForOrder != null) {
        final rawName = selectedTableForOrder.number.trim();
        resolvedTableName =
            rawName.isNotEmpty ? rawName : selectedTableForOrder.id.trim();
      }
      final hasResolvedTableName =
          resolvedTableName != null && resolvedTableName.trim().isNotEmpty;

      // Backend enforces table_name for dine-in/table order types.
      if (requiresTableForBooking &&
          (selectedTableForOrder == null || !hasResolvedTableName)) {
        if (type == 'payment') {
          _queuePendingPaymentAfterTableSelection(
            type: type,
            pays: pays,
            showLoadingOverlay: showLoadingOverlay,
            showSuccessDialog: showSuccessDialog,
            clearCartOnSuccess: clearCartOnSuccess,
            isNearPayCardFlow: isNearPayCardFlow,
          );
        }
        if (showLoadingOverlay && mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _trUi(
                  'اختر طاولة صالحة قبل إكمال العملية',
                  'Select a valid table before continuing',
                ),
              ),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() => _activeTab = 'tables');
        }
        return;
      }

      final orderItemsSnapshot = cartItemsForOrder.map(
        (item) {
          final categoryName = item.product.category.trim();
          // Prefer the category ID already on the product (from the API);
          // fall back to name-based resolution only when not available.
          final categoryId =
              (item.product.categoryId?.trim().isNotEmpty == true)
                  ? item.product.categoryId!.trim()
                  : _resolveCategoryIdByName(categoryName);
          String arName = item.product.nameAr;
          String enName = item.product.nameEn;
          final fallbackName = item.product.name;
          
          // Always try to split the combined name for bilingual support
          if (enName.trim().isEmpty && fallbackName.contains(' - ')) {
            arName = fallbackName.split(' - ').first.trim();
            enName = fallbackName.split(' - ').last.trim();
          } else if (arName.trim().isEmpty) {
            arName = fallbackName;
          }
          // If arName is still empty after split, use fallbackName
          if (arName.trim().isEmpty) {
            arName = fallbackName;
          }

          return {
            'name': fallbackName,
            'nameAr': arName,
            'nameEn': enName,
            'localizedNames': item.product.localizedNames,
            'category_name': categoryName,
            if (categoryId != null && categoryId.isNotEmpty)
              'category_id': categoryId,
            'quantity': item.quantity,
            'unitPrice': item.product.price,
            'total': item.totalPrice,
            'notes': item.notes,
            // Include per-extra translations so the kitchen ticket can print
            // the addon in the cashier's invoice language even when the
            // backend doesn't (or hasn't yet) returned `addons_translations`.
            'extras': item.selectedExtras.map((e) {
              final entry = <String, dynamic>{
                'name': e.name,
                'price': e.price,
              };
              if (e.optionTranslations.isNotEmpty ||
                  e.attributeTranslations.isNotEmpty) {
                entry['translations'] = <String, Map<String, String>>{
                  if (e.optionTranslations.isNotEmpty)
                    'option': e.optionTranslations,
                  if (e.attributeTranslations.isNotEmpty)
                    'attribute': e.attributeTranslations,
                };
              }
              return entry;
            }).toList(),
          };
        },
      ).toList();
      final kdsItemsPayload = cartItemsForOrder.map(
        (item) {
          final categoryName = item.product.category.trim();
          final categoryId =
              (item.product.categoryId?.trim().isNotEmpty == true)
                  ? item.product.categoryId!.trim()
                  : _resolveCategoryIdByName(categoryName);
          final basePrice = item.product.price;
          final extrasPrice =
              item.selectedExtras.fold<double>(0.0, (sum, e) => sum + e.price);
          final originalUnitPrice = basePrice + extrasPrice;
          final originalTotal = originalUnitPrice * item.quantity;

          return {
            'cartId': item.cartId,
            'meal_id': item.product.id,
            'productId': item.product.id,
            'name': item.product.name,
            'category_name': categoryName,
            if (categoryId != null) 'category_id': categoryId,
            'quantity': item.quantity,
            'extras': item.selectedExtras.map((e) => {'name': e.name}).toList(),
            'notes': item.notes,
            // ✅ Discount information for KDS
            'original_unit_price': originalUnitPrice,
            'original_total': originalTotal,
            'final_total': item.totalPrice,
            'discount': item.discount,
            'discount_type': item.discountType == DiscountType.percentage
                ? 'percentage'
                : 'amount',
            'is_free': item.isFree,
          };
        },
      ).toList();
      bool kdsOrderDispatched = false;
      bool kdsScreenReceivedOrder = false;

      // Step 1: Create Booking
      print('📝 Creating booking with order type: $bookingOrderType');
      print('📝 _selectedOrderType: $_selectedOrderType');
      final Map<String, dynamic> bookingData;
      if (_isSalonMode) {
        // Salon booking: determine type based on cart contents
        // If any cart item has package_service_id, use 'packageServices', else null
        final hasPackageItems = cartItemsForOrder.any((item) =>
            item.salonData != null && item.salonData!['package_service_id'] != null);
        bookingData = <String, dynamic>{
          'type': hasPackageItems ? 'packageServices' : null,
          'date': dateStr,
          if (_selectedCustomer != null)
            'customer_id': _selectedCustomer!.id.toString(),
          'type_extra': {
            'car_number': null,
            'table_name': null,
            'latitude': null,
            'longitude': null,
          },
        };
      } else {
        bookingData = <String, dynamic>{
          'type': bookingOrderType,
          'date': dateStr,
          if (selectedTableForOrder != null)
            'table_id': selectedTableForOrder.id,
          if (_selectedCustomer != null)
            'customer_id': _selectedCustomer!.id.toString(),
          'type_extra': {
            if (carNumber.isNotEmpty) 'car_number': carNumber,
            if (requiresTableForBooking && selectedTableForOrder != null) ...{
              'table_name': resolvedTableName,
              'table_id': selectedTableForOrder.id,
            },
            'latitude': null,
            'longitude': null,
          },
        };
      }
      print('🧾 Booking payload table: '
          'type=$bookingOrderType '
          'table_id=${selectedTableForOrder?.id} '
          'table_name=$resolvedTableName');

      // Snapshot order-level discount & promo BEFORE _clearCart() resets them.
      final snapshotOrderDiscount = _orderDiscount;
      final snapshotOrderDiscountType = _orderDiscountType;
      final snapshotIsOrderFree = _isOrderFree;
      final snapshotPromo = _activePromoCode;

      // Resolve effective per-item discount for API.
      // The API only accepts per-item discount fields, so any order-level
      // discount (manual / promo / free) must be converted to a per-item
      // percentage and combined with existing per-item discounts.
      double _resolveItemApiDiscount(CartItem item) {
        // Start with the item's own discount as a percentage.
        double itemPct = 0;
        if (item.isFree) {
          itemPct = 100;
        } else if (item.discount > 0) {
          if (item.discountType == DiscountType.percentage) {
            itemPct = item.discount.clamp(0, 100);
          } else {
            final basePrice = item.product.price +
                item.selectedExtras.fold<double>(0, (s, e) => s + e.price);
            final qty = item.quantity < 1 ? 1.0 : item.quantity;
            final lineTotal = basePrice * qty;
            itemPct = lineTotal > 0 ? (item.discount / lineTotal * 100).clamp(0, 100) : 0;
          }
        }
        // Layer on order-level discount (using snapshot, not live state).
        if (snapshotIsOrderFree) {
          return 100;
        }

        // Layer manual order discount.
        if (snapshotOrderDiscount > 0) {
          double orderPct;
          if (snapshotOrderDiscountType == DiscountType.percentage) {
            orderPct = snapshotOrderDiscount.clamp(0, 100);
          } else {
            orderPct = grossOrderTotal > 0
                ? (snapshotOrderDiscount / grossOrderTotal * 100).clamp(0, 100)
                : 0;
          }
          final remainAfterItem = 100 - itemPct;
          itemPct = (itemPct + remainAfterItem * orderPct / 100).clamp(0, 100);
        }

        // Layer promo code discount.
        if (snapshotPromo != null) {
          double promoPct;
          if (snapshotPromo.type == DiscountType.percentage) {
            promoPct = snapshotPromo.discount.clamp(0, 100);
          } else {
            // Fixed amount promo — compute effective % relative to gross.
            double promoAmount = snapshotPromo.discount;
            if (snapshotPromo.maxDiscount != null &&
                promoAmount > snapshotPromo.maxDiscount!) {
              promoAmount = snapshotPromo.maxDiscount!;
            }
            promoPct = grossOrderTotal > 0
                ? (promoAmount / grossOrderTotal * 100).clamp(0, 100)
                : 0;
          }
          final remainAfterPrev = 100 - itemPct;
          itemPct = (itemPct + remainAfterPrev * promoPct / 100).clamp(0, 100);
        }

        return itemPct;
      }

      // Build items in API-compatible "card" shape.
      final List<Map<String, dynamic>> cartItems = [];
      if (_isSalonMode) {
        // Salon card format: uses service_id, employee_id, date, time, etc.
        for (var item in cartItemsForOrder) {
          final salon = item.salonData ?? <String, dynamic>{};
          final effectiveDiscount = _resolveItemApiDiscount(item);
          cartItems.add({
            'package_service_id': salon['package_service_id'],
            'item_name': salon['item_name'] ?? item.product.name,
            'service_id': salon['service_id'] ??
                int.tryParse(item.product.id) ??
                item.product.id,
            'minutes': salon['minutes'] ?? 0,
            'employee_name': salon['employee_name'] ?? '',
            'employee_id': salon['employee_id'],
            'date': salon['date'] ?? dateStr,
            'time': salon['time'] ?? '',
            'session_numbers': salon['session_numbers'] ?? 0,
            'quantity': item.quantity.round().clamp(1, 9999),
            'price': item.product.price,
            'unitPrice': item.product.price,
            'modified_unit_price': salon['modified_unit_price'],
            if (item.notes.isNotEmpty) 'note': item.notes,
            if (effectiveDiscount > 0) 'discount': effectiveDiscount,
            if (effectiveDiscount > 0) 'discount_type': '%',
          });
        }
      } else {
        // Restaurant card format
        for (var item in cartItemsForOrder) {
          final addonIds = _toAddonIdList(item.selectedExtras);
          final effectiveDiscount = _resolveItemApiDiscount(item);
          cartItems.add({
            'item_name': item.product.name,
            'meal_id': item.product.id,
            'price': item.product.price,
            'unitPrice': item.product.price,
            'modified_unit_price': null,
            'quantity': item.quantity.round().clamp(1, 9999),
            'addons': addonIds,
            if (item.notes.isNotEmpty) 'note': item.notes,
            if (effectiveDiscount > 0) 'discount': effectiveDiscount,
            if (effectiveDiscount > 0) 'discount_type': '%',
          });
        }
      }
      // Keep both keys for compatibility across accounts.
      bookingData['card'] = cartItems;
      if (!_isSalonMode) bookingData['meals'] = cartItems;

      final bookingResponse = await orderService.createBooking(
        bookingData,
        paymentType: type,
      );
      final bookingDataResponse = bookingResponse['data'];
      final bookingDataMap = asStringKeyMap(bookingDataResponse);
      final bookingNode = asStringKeyMap(bookingDataMap?['booking']);
      final orderNode = asStringKeyMap(bookingDataMap?['order']);
      final orderId = firstNonEmptyText([
        bookingNode?['id'],
        bookingDataMap?['booking_id'],
        bookingDataMap?['id'],
      ]);
      final backendOrderId = firstNonEmptyText(
        [
          orderNode?['id'],
          bookingDataMap?['order_id'],
          bookingNode?['order_id'],
        ],
        allowZero: false,
      );
      final backendDailyOrderNumber = firstNonEmptyText(
        [
          bookingNode?['daily_order_number'],
          orderNode?['order_number'],
          bookingDataMap?['daily_order_number'],
          bookingDataMap?['order_number'],
          bookingNode?['order_number'],
        ],
        allowZero: false,
      );
      final bookingProductIds = <dynamic>[];
      final bookingProductsData = <Map<String, dynamic>>[];
      final bookingMealsData = <Map<String, dynamic>>[];
      dynamic extractBookingProductId(dynamic node) {
        if (node is Map) {
          if (node['booking_product_id'] != null) {
            return node['booking_product_id'];
          }
          for (final value in node.values) {
            final found = extractBookingProductId(value);
            if (found != null) return found;
          }
        } else if (node is List) {
          for (final item in node) {
            final found = extractBookingProductId(item);
            if (found != null) return found;
          }
        }
        return null;
      }

      if (bookingDataResponse is Map) {
        final bookingProducts = bookingDataResponse['booking_products'];
        if (bookingProducts is List) {
          for (final p in bookingProducts) {
            final productMap = asStringKeyMap(p);
            if (productMap != null) {
              bookingProductsData.add(productMap);
              if (productMap['id'] != null) {
                bookingProductIds.add(productMap['id']);
              }
            }
          }
        }

        // Extract booking meals (restaurant) or booking services (salon)
        final bookingMeals = bookingDataResponse['booking_meals'];
        if (bookingMeals is List) {
          for (final m in bookingMeals) {
            final mealMap = asStringKeyMap(m);
            if (mealMap != null) {
              bookingMealsData.add(mealMap);
            }
          }
        }
        // Salon: also check booking_services
        final bookingServices = bookingDataResponse['booking_services'];
        if (bookingServices is List) {
          for (final s in bookingServices) {
            final sMap = asStringKeyMap(s);
            if (sMap != null) {
              bookingMealsData.add(sMap);
            }
          }
        }
      }

      if (orderId == null) {
        final backendMessage = bookingResponse['message']?.toString();
        throw Exception(
          ErrorHandler.normalizeBackendMessage(
            backendMessage,
            defaultMessage: 'فشل إنشاء الطلب',
          ),
        );
      }
      final displayOrderRef = normalizeDisplayOrderRef(
        firstNonEmptyText(
              [
                backendDailyOrderNumber,
                backendOrderId,
                orderId,
              ],
              allowZero: false,
            ) ??
            orderId,
      );
      print(
        'ℹ️ Booking/Order mapping resolved: booking.id=$orderId order.id=${backendOrderId ?? '-'} order_number=${backendDailyOrderNumber ?? '-'}',
      );
      _lastCreatedBookingId = orderId;

      // ═══════════════════════════════════════════════════════════════
      // FAST PATH: Close loading + show success immediately after booking
      // Invoice creation, KDS, printing all happen in the background
      // ═══════════════════════════════════════════════════════════════
      if (showLoadingOverlay && mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (clearCartOnSuccess) {
        _clearCart();
      }

      if (mounted) {
        final successOrderRef = normalizeDisplayOrderRef(displayOrderRef);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(translationService.t('order_saved_with_number', args: {'number': successOrderRef.toString()})),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Show "Thank you" on customer display immediately
      if (type == 'payment') {
        unawaited(
          _showCashPaymentSuccessOnCds(
            displayService: displayService,
            pays: pays?.whereType<Map<String, dynamic>>().toList() ?? const [],
          ),
        );
      }

      // ═══════════════════════════════════════════════════════════════
      // BACKGROUND: Everything below runs without blocking the UI
      // ═══════════════════════════════════════════════════════════════

      // Fire-and-forget: table reservation doesn't block payment
      if (selectedTableForOrder != null) {
        final tableCapture = selectedTableForOrder;
        unawaited(() async {
          final synced = await _syncTableReservationForOrder(
            tableCapture,
            reserved: true,
          );
          if (!synced && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _trUi(
                    'تم إنشاء الطلب ولكن تعذر تحديث حالة الطاولة تلقائياً. يرجى التحقق من شاشة الطاولات.',
                    'Order was created, but table status could not be updated automatically. Please verify from tables screen.',
                  ),
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }());
      }
      // Fire-and-forget: KDS dispatch runs in background, doesn't block payment
      if (_isKdsEnabled) {
        unawaited(() async {
          try {
            final firstDispatchAcked = await _dispatchOrderToKdsWithAck(
              displayService: displayService,
              orderId: orderId,
              orderNumber: displayOrderRef,
              orderType: bookingOrderType,
              items: kdsItemsPayload,
              note: _orderNotesController.text.isNotEmpty
                  ? _orderNotesController.text
                  : null,
              total: orderTotal,
              invoice: _buildKdsInvoicePayload(
                bookingId: orderId,
                orderId: backendOrderId,
                orderNumber: displayOrderRef,
                invoiceId: null,
                invoiceNumber: null,
                type: type,
                orderTotal: orderTotal,
                grossOrderTotal: grossOrderTotal,
                discountAmount: appliedDiscountAmount,
                promoCodeId: promoCodeId,
                promoCode: promoCodeValue,
                promoDiscountType: promoDiscountType,
                orderItems: orderItemsSnapshot,
                cashFloatSnapshot: _buildCashFloatSnapshot(),
              ),
            );
            kdsOrderDispatched = true;
            kdsScreenReceivedOrder = firstDispatchAcked;
          } catch (e) {
            debugPrint('⚠️ Failed to dispatch NEW_ORDER after booking #$orderId: $e');
          }
        }());
      }

      // Fallback extraction runs in background - doesn't block invoice creation
      Future<void>? bookingDetailsFuture;
      if (bookingProductIds.isEmpty) {
        bookingDetailsFuture = () async {
          try {
            final bookingDetails = await orderService.getBookingDetails(orderId);
            final detailsData = bookingDetails['data'];
            final detected = extractBookingProductId(detailsData);
            if (detected != null) {
              bookingProductIds.add(detected);
            }

            if (detailsData is Map) {
              final detailsMeals = detailsData['booking_meals'];
              if (detailsMeals is List) {
                for (final m in detailsMeals) {
                  final mealMap = asStringKeyMap(m);
                  if (mealMap != null) {
                    bookingMealsData.add(mealMap);
                  }
                }
              }
            }
          } catch (e) {
            debugPrint(
                '⚠️ Could not fetch booking details for booking_product_id: $e');
          }
        }();
      }

      // Step 2: Create Invoice (if payment)
      // This runs AFTER loading is already closed - errors here show as snackbar
      // Wait for booking details if still running (runs parallel with KDS dispatch)
      try {
      if (bookingDetailsFuture != null) await bookingDetailsFuture;
      final dynamic primaryBookingProductId =
          bookingProductIds.isNotEmpty ? bookingProductIds.first : null;
      if (primaryBookingProductId != null) {
        debugPrint('ℹ️ booking_product_id detected: $primaryBookingProductId');
      }
      String? invoiceNumber;
      String? invoiceId;
      Map<String, dynamic>? invoicePayload;
      List<Map<String, dynamic>> normalizedPays = const [];
      if (type == 'payment') {
        double extractExpectedInvoiceTotal(dynamic response, double fallback) {
          if (response is! Map) return fallback;
          final map = response.map((k, v) => MapEntry(k.toString(), v));
          final candidates = <dynamic>[
            map['total'],
            map['invoice_total'],
            map['grand_total'],
            if (map['data'] is Map) (map['data'] as Map)['total'],
            if (map['data'] is Map) (map['data'] as Map)['invoice_total'],
            if (map['data'] is Map) (map['data'] as Map)['grand_total'],
            if (map['data'] is Map) (map['data'] as Map)['total_with_tax'],
          ];
          for (final c in candidates) {
            if (c is num) return c.toDouble();
            if (c is String) {
              final parsed = double.tryParse(c);
              if (parsed != null) return parsed;
            }
          }
          return fallback;
        }

        List<Map<String, dynamic>> clonePaysList(dynamic rawPays) {
          if (rawPays is! List) return <Map<String, dynamic>>[];
          return rawPays
              .whereType<Map>()
              .map((entry) => entry.map((k, v) => MapEntry(k.toString(), v)))
              .toList();
        }

        double sumPaysAmounts(List<Map<String, dynamic>> pays) {
          var sum = 0.0;
          for (final pay in pays) {
            final amount = (pay['amount'] as num?)?.toDouble() ??
                double.tryParse(pay['amount']?.toString() ?? '') ??
                0.0;
            if (amount <= 0) continue;
            sum += amount;
          }
          return double.parse(sum.toStringAsFixed(2));
        }

        // Calculate invoice first using official API payload
        final List<Map<String, dynamic>> calcItems;
        final String calcItemsKey;
        if (_isSalonMode) {
          calcItemsKey = 'sales_services';
          calcItems = cartItemsForOrder.map((item) {
            final salon = item.salonData ?? <String, dynamic>{};
            return {
              'service_id': salon['service_id'] ?? int.tryParse(item.product.id),
              'service_name': salon['item_name'] ?? item.product.name,
              'employee_id': salon['employee_id'] ?? '',
              'quantity': item.quantity.round().clamp(1, 9999),
              'price': item.product.price,
              'unit_price': item.product.price,
              'modified_unit_price': salon['modified_unit_price'] ?? '',
              'package_service_id': salon['package_service_id'] ?? '',
              'date': salon['date'] ?? '',
              'time': salon['time'] ?? '',
              'session_numbers': salon['session_numbers'] ?? '',
              'booking_service_id': salon['booking_service_id'] ?? '',
              'discount': '',
              'discount_type': '%',
            };
          }).toList();
        } else {
          calcItemsKey = 'items';
          calcItems = cartItemsForOrder
              .map(
                (item) => {
                  'meal_id': int.tryParse(item.product.id) ?? item.product.id,
                  'quantity': item.quantity.round().clamp(1, 9999),
                  'price': item.product.price,
                },
              )
              .toList();
        }
        final calculationPayload = {
          calcItemsKey: calcItems,
          'discount': _orderDiscount,
          if (promoCodeId != null) 'promocode_id': promoCodeId,
          if (promoCodeValue != null && promoCodeValue.isNotEmpty)
            'promocodeValue': promoCodeValue,
          if (promoCodeValue != null && promoCodeValue.isNotEmpty)
            'promocode_name': promoCodeValue,
          if (promoDiscountType != null) 'discount_type': promoDiscountType,
          if (_isSalonMode && _selectedDepositId != null)
            'deposit_id': _selectedDepositId,
        };
        try {
          final calcResponse = await orderService.calculateInvoice(
            calculationPayload,
          );
          payableTotal = extractExpectedInvoiceTotal(calcResponse, orderTotal);
          if ((payableTotal - payableTotal.roundToDouble()).abs() <= 0.02) {
            payableTotal = payableTotal.roundToDouble();
          } else {
            payableTotal = double.parse(payableTotal.toStringAsFixed(2));
          }
        } on ApiException catch (e) {
          if (e.statusCode == 422 &&
              !promoRemovedDueToExpiry &&
              isExpiredPromoMessage(e.message)) {
            promoRemovedDueToExpiry = true;
            promoCodeId = null;
            promoCodeValue = null;
            promoDiscountType = null;
            clearActivePromoSelectionLocally();
            appliedDiscountAmount =
                _resolveEffectiveDiscountAmount(grossOrderTotal);
            orderTotal = (grossOrderTotal - appliedDiscountAmount)
                .clamp(0.0, double.infinity);
            payableTotal = double.parse(orderTotal.toStringAsFixed(2));
            print(
              '♻️ Promo expired while calculating invoice; continuing without promo',
            );
          } else {
            // Non-blocking: some accounts reject calculate payload variants
            // while still accepting create invoice payload.
            print(
                '⚠️ Calculate invoice failed, continuing to create invoice: $e');
          }
        } catch (e) {
          // Non-blocking: some accounts reject calculate payload variants
          // while still accepting create invoice payload.
          print(
              '⚠️ Calculate invoice failed, continuing to create invoice: $e');
        }
        normalizedPays = _buildNormalizedPays(
          pays,
          targetTotal: payableTotal,
        );
        normalizedPays = _buildUpdatePaysPayload(
          normalizedPays,
          payableTotal,
          preserveCardAmounts: isNearPayCardFlow,
        );
        final hasCardPayment = normalizedPays.any((pay) {
          final method = _normalizePayMethod(pay['pay_method']?.toString());
          return method == 'card';
        });
        if (_isProfileNearPayEnabled && hasCardPayment && !isNearPayCardFlow) {
          throw Exception('دفع البطاقة يجب أن يتم عبر NearPay فقط');
        }

        // Create invoice using official payload format:
        // customer_id, order_id, date, pays
        final invoiceItems = cartItemsForOrder.map(
          (item) {
            final addonIds = _toAddonIdList(item.selectedExtras);
            final effectiveDiscount = _resolveItemApiDiscount(item);
            final salon = item.salonData ?? <String, dynamic>{};
            final isSalonItem = _isSalonMode && salon.isNotEmpty;

            if (isSalonItem) {
              return {
                'service_id': salon['service_id'] ?? int.tryParse(item.product.id),
                'service_name': salon['item_name'] ?? item.product.name,
                'employee_id': salon['employee_id'] ?? '',
                'quantity': item.quantity.round().clamp(1, 9999),
                'price': item.product.price,
                'unit_price': item.product.price,
                'modified_unit_price': salon['modified_unit_price'] ?? '',
                'package_service_id': salon['package_service_id'] ?? '',
                'date': salon['date'] ?? '',
                'time': salon['time'] ?? '',
                'session_numbers': salon['session_numbers'] ?? '',
                'booking_service_id': salon['booking_service_id'] ?? '',
                'discount': effectiveDiscount > 0 ? effectiveDiscount : '',
                'discount_type': '%',
                'addons': [],
              };
            }

            return {
              'item_name': item.product.name,
              'meal_id': int.tryParse(item.product.id) ?? item.product.id,
              'price': item.product.price,
              'unitPrice': item.product.price,
              'modified_unit_price': null,
              'quantity': item.quantity.round().clamp(1, 9999),
              'addons': addonIds,
              if (item.notes.isNotEmpty) 'note': item.notes,
              if (effectiveDiscount > 0) 'discount': effectiveDiscount,
              if (effectiveDiscount > 0) 'discount_type': '%',
            };
          },
        ).toList();
        int toSafeInt(dynamic value, {int fallback = 1}) {
          if (value is int) return value;
          if (value is num) return value.toInt();
          if (value is String) return int.tryParse(value) ?? fallback;
          return fallback;
        }

        double toSafeDouble(dynamic value, {double fallback = 0.0}) {
          if (value is num) return value.toDouble();
          if (value is String) return double.tryParse(value) ?? fallback;
          return fallback;
        }

        final mealNameById = <String, String>{};
        final mealPriceById = <String, double>{};
        // Build a queue of local cart discounts per meal_id so we can
        // inject the discount the cashier applied (the backend booking_meals
        // response may not echo these back).
        final mealDiscountQueue = <String, List<CartItem>>{};
        for (final item in cartItemsForOrder) {
          final mealId =
              (int.tryParse(item.product.id) ?? item.product.id).toString();
          mealNameById.putIfAbsent(mealId, () => item.product.name);
          mealPriceById.putIfAbsent(mealId, () => item.product.price);
          mealDiscountQueue.putIfAbsent(mealId, () => []).add(item);
        }

        final salesMeals = <Map<String, dynamic>>[];
        final usedBookingMealIds = <int>{};

        // Prefer booking_meals response because it contains canonical booking IDs.
        for (final meal in bookingMealsData) {
          final bookingMealIdRaw = meal['id'] ?? meal['booking_meal_id'];
          final bookingMealId = toSafeInt(bookingMealIdRaw, fallback: 0);
          if (bookingMealId <= 0 ||
              usedBookingMealIds.contains(bookingMealId)) {
            continue;
          }

          final mealIdRaw = meal['meal_id'] ?? meal['product_id'];
          final mealIdStr = mealIdRaw?.toString() ?? '';
          final quantity =
              toSafeInt(meal['quantity'], fallback: 1).clamp(1, 9999);
          final unitPrice = toSafeDouble(
            meal['unit_price'] ?? meal['price'] ?? mealPriceById[mealIdStr],
            fallback: 0.0,
          );
          final totalPrice = toSafeDouble(
            meal['total'] ?? meal['price'],
            fallback: unitPrice * quantity,
          );

          // Use the local cart item to compute the effective API discount
          // (combines per-item + order-level discounts as a single %).
          final localQueue = mealDiscountQueue[mealIdStr];
          final localItem =
              (localQueue != null && localQueue.isNotEmpty) ? localQueue.removeAt(0) : null;

          String discountValue = meal['discount']?.toString() ?? '';
          String discountTypeValue = meal['discount_type']?.toString() ?? '%';

          if (localItem != null) {
            final effectiveDiscount = _resolveItemApiDiscount(localItem);
            if (effectiveDiscount > 0) {
              discountValue = effectiveDiscount.toString();
              discountTypeValue = '%';
            }
          }

          salesMeals.add({
            'booking_meal_id': bookingMealId,
            'meal_id': int.tryParse(mealIdStr) ?? mealIdRaw ?? mealIdStr,
            'quantity': quantity,
            'meal_name':
                meal['meal_name']?.toString() ?? mealNameById[mealIdStr] ?? '',
            'unit_price': unitPrice,
            'price': totalPrice,
            'total': totalPrice,
            'discount': discountValue,
            'discount_type': discountTypeValue,
            'notes': meal['notes']?.toString() ?? '',
          });
          usedBookingMealIds.add(bookingMealId);
        }

        // Do not fabricate sales_meals IDs from booking_products IDs.
        // If booking_meals is unavailable, we rely on items/card payload variants.

        final hasValidSalesMealBookingIds = salesMeals.isNotEmpty &&
            salesMeals.every(
              (m) => toSafeInt(m['booking_meal_id'], fallback: 0) > 0,
            );
        // Always use normalizedPays (already adjusted to payableTotal) instead
        // of recalculating from salesMeals totals, which may differ from the
        // backend invoice total due to rounding, taxes, or booking discounts.
        final paysForSalesMeals = normalizedPays;
        if (invoiceItems.isEmpty) {
          throw Exception('يجب أن تحتوي الفاتورة علي عناصر.');
        }

        final bookingIdValue = int.tryParse(orderId) ?? orderId;
        final orderIdValue =
            backendOrderId != null && int.tryParse(backendOrderId) != null
                ? int.parse(backendOrderId)
                : (backendOrderId ?? bookingIdValue);
        final bookingCustomerMap = asStringKeyMap(bookingDataMap?['customer']);
        final customerIdValue = _selectedCustomer?.id ??
            bookingDataMap?['customer_id'] ??
            bookingCustomerMap?['id'];
        final promoFields = <String, dynamic>{
          if (promoCodeId != null) 'promocode_id': promoCodeId,
          if (promoCodeValue != null && promoCodeValue.isNotEmpty)
            'promocodeValue': promoCodeValue,
          if (promoCodeValue != null && promoCodeValue.isNotEmpty)
            'promocode_name': promoCodeValue,
          if (promoDiscountType != null) 'discount_type': promoDiscountType,
        };
        // For salon: use sales_services key; for restaurant: use sales_meals/items/meals
        final invoiceDataBase = <String, dynamic>{
          if (customerIdValue != null) 'customer_id': customerIdValue,
          'branch_id': ApiConstants.branchId,
          'order_id': orderIdValue,
          'booking_id': bookingIdValue,
          if (primaryBookingProductId != null && !_isSalonMode)
            'booking_product_id': primaryBookingProductId,
          if (_isSalonMode && _selectedDepositId != null)
            'deposit_id': _selectedDepositId,
          ...promoFields,
          'cash_back': 0,
          'date': dateStr,
          'pays': normalizedPays,
          if (_isSalonMode) 'sales_services': invoiceItems
          else ...{
            'items': invoiceItems,
            'card': invoiceItems,
            'meals': invoiceItems,
            if (hasValidSalesMealBookingIds) 'sales_meals': salesMeals,
          },
        };
        final invoiceDataBookingOnly =
            Map<String, dynamic>.from(invoiceDataBase)..remove('order_id');
        final isCashOnlyPayment = normalizedPays.length == 1 &&
            _normalizePayMethod(
                  normalizedPays.first['pay_method']?.toString(),
                ) ==
                'cash';
        final depositField = (_isSalonMode && _selectedDepositId != null)
            ? <String, dynamic>{'deposit_id': _selectedDepositId}
            : <String, dynamic>{};
        final invoiceDataCashPostman = <String, dynamic>{
          if (customerIdValue != null) 'customer_id': customerIdValue,
          'branch_id': ApiConstants.branchId,
          'booking_id': bookingIdValue,
          'date': dateStr,
          'pays': normalizedPays,
          ...promoFields,
          ...depositField,
        };
        final invoiceDataCashWithSalesMeals = <String, dynamic>{
          if (customerIdValue != null) 'customer_id': customerIdValue,
          'branch_id': ApiConstants.branchId,
          'booking_id': bookingIdValue,
          'date': dateStr,
          'pays': paysForSalesMeals,
          ...promoFields,
          ...depositField,
          if (_isSalonMode) 'sales_services': invoiceItems
          else ...{
            if (hasValidSalesMealBookingIds) 'sales_meals': salesMeals,
            if (!hasValidSalesMealBookingIds) 'items': invoiceItems,
          },
        };
        final invoiceDataPostmanPaysOnly = <String, dynamic>{
          if (customerIdValue != null) 'customer_id': customerIdValue,
          'branch_id': ApiConstants.branchId,
          'booking_id': bookingIdValue,
          'date': dateStr,
          'pays': normalizedPays,
          ...promoFields,
          ...depositField,
        };
        final invoiceDataBackendExact = <String, dynamic>{
          if (customerIdValue != null) 'customer_id': customerIdValue,
          'branch_id': ApiConstants.branchId,
          'booking_id': bookingIdValue,
          'date': dateStr,
          'pays': paysForSalesMeals,
          ...depositField,
          if (_isSalonMode) 'sales_services': invoiceItems
          else if (hasValidSalesMealBookingIds) 'sales_meals': salesMeals,
        };
        final invoiceDataWithItems = <String, dynamic>{
          ...invoiceDataBase,
          // Some accounts require items payload even with order_id.
          'items': invoiceItems,
          'card': invoiceItems,
          'meals': invoiceItems,
          if (hasValidSalesMealBookingIds) 'sales_meals': salesMeals,
        };
        final invoiceDataWithItemsBookingOnly =
            Map<String, dynamic>.from(invoiceDataWithItems)..remove('order_id');
        print('📝 Creating invoice with order type: $bookingOrderType');
        final invoiceDataLegacyCard = <String, dynamic>{
          if (customerIdValue != null) 'customer_id': customerIdValue,
          'branch_id': ApiConstants.branchId,
          'date': dateStr,
          'card': invoiceItems,
          'pays': normalizedPays,
          ...promoFields,
          'type': bookingOrderType,
          'type_extra': {
            'car_number': carNumber.isEmpty ? null : carNumber,
            'table_name': selectedTableForOrder?.number,
            'latitude': null,
            'longitude': null,
          },
        };

        Map<String, dynamic> invoiceResponse;
        Object? lastInvoiceError;
        final attempts = <Map<String, dynamic>>[];
        if (isCashOnlyPayment) {
          if (hasValidSalesMealBookingIds) {
            attempts.addAll([
              {
                'label': 'json_cash_with_sales_meals',
                'run': () =>
                    orderService.createInvoice(invoiceDataCashWithSalesMeals),
                'payload': invoiceDataCashWithSalesMeals,
              },
              {
                'label': 'multipart_backend_exact',
                'run': () => orderService.createInvoiceMultipart(
                      invoiceDataBackendExact,
                    ),
                'payload': invoiceDataBackendExact,
              },
              {
                'label': 'multipart_cash_with_sales_meals',
                'run': () => orderService
                    .createInvoiceMultipart(invoiceDataCashWithSalesMeals),
                'payload': invoiceDataCashWithSalesMeals,
              },
            ]);
          } else if (hasValidSalesMealBookingIds) {
            attempts.add({
              'label': 'multipart_backend_exact',
              'run': () => orderService.createInvoiceMultipart(
                    invoiceDataBackendExact,
                  ),
              'payload': invoiceDataBackendExact,
            });
          }
          // Keep cashier-cash flow closest to Postman contract as fallback.
          attempts.addAll([
            {
              'label': 'json_cash_postman_exact',
              'run': () => orderService.createInvoice(invoiceDataCashPostman),
              'payload': invoiceDataCashPostman,
            },
            {
              'label': 'multipart_cash_postman_exact',
              'run': () =>
                  orderService.createInvoiceMultipart(invoiceDataCashPostman),
              'payload': invoiceDataCashPostman,
            },
            {
              'label': 'json_postman_pays_only',
              'run': () =>
                  orderService.createInvoice(invoiceDataPostmanPaysOnly),
              'payload': invoiceDataPostmanPaysOnly,
            },
            {
              'label': 'json_booking_only_base',
              'run': () => orderService.createInvoice(invoiceDataBookingOnly),
              'payload': invoiceDataBookingOnly,
            },
            {
              'label': 'json_order_booking_base',
              'run': () => orderService.createInvoice(invoiceDataBase),
              'payload': invoiceDataBase,
            },
          ]);
        } else {
          if (hasValidSalesMealBookingIds) {
            attempts.addAll([
              {
                'label': 'json_non_cash_with_sales_meals',
                'run': () =>
                    orderService.createInvoice(invoiceDataCashWithSalesMeals),
                'payload': invoiceDataCashWithSalesMeals,
              },
              {
                'label': 'multipart_non_cash_with_sales_meals',
                'run': () => orderService
                    .createInvoiceMultipart(invoiceDataCashWithSalesMeals),
                'payload': invoiceDataCashWithSalesMeals,
              },
            ]);
          }
          attempts.addAll([
            {
              'label': 'json_postman_pays_only',
              'run': () =>
                  orderService.createInvoice(invoiceDataPostmanPaysOnly),
              'payload': invoiceDataPostmanPaysOnly,
            },
            {
              'label': 'multipart_postman_pays_only',
              'run': () => orderService
                  .createInvoiceMultipart(invoiceDataPostmanPaysOnly),
              'payload': invoiceDataPostmanPaysOnly,
            },
            {
              'label': 'json_order_booking_base',
              'run': () => orderService.createInvoice(invoiceDataBase),
              'payload': invoiceDataBase,
            },
            {
              'label': 'json_booking_only_base',
              'run': () => orderService.createInvoice(invoiceDataBookingOnly),
              'payload': invoiceDataBookingOnly,
            },
            {
              'label': 'json_order_booking_with_items',
              'run': () => orderService.createInvoice(invoiceDataWithItems),
              'payload': invoiceDataWithItems,
            },
            {
              'label': 'json_booking_only_with_items',
              'run': () =>
                  orderService.createInvoice(invoiceDataWithItemsBookingOnly),
              'payload': invoiceDataWithItemsBookingOnly,
            },
            {
              'label': 'multipart_order_booking_with_items',
              'run': () =>
                  orderService.createInvoiceMultipart(invoiceDataWithItems),
              'payload': invoiceDataWithItems,
            },
            {
              'label': 'multipart_booking_only_with_items',
              'run': () => orderService
                  .createInvoiceMultipart(invoiceDataWithItemsBookingOnly),
              'payload': invoiceDataWithItemsBookingOnly,
            },
            {
              'label': 'json_legacy_card_payload',
              'run': () => orderService.createInvoice(invoiceDataLegacyCard),
              'payload': invoiceDataLegacyCard,
            },
            {
              'label': 'multipart_legacy_card_payload',
              'run': () =>
                  orderService.createInvoiceMultipart(invoiceDataLegacyCard),
              'payload': invoiceDataLegacyCard,
            },
          ]);
        }
        if (!isCashOnlyPayment && bookingProductIds.length > 1) {
          for (final bookingProductId in bookingProductIds.skip(1)) {
            final withSpecificBookingProduct =
                Map<String, dynamic>.from(invoiceDataWithItems)
                  ..['booking_product_id'] = bookingProductId;
            attempts.add({
              'label': 'json_with_items_booking_product_$bookingProductId',
              'run': () =>
                  orderService.createInvoice(withSpecificBookingProduct),
              'payload': withSpecificBookingProduct,
            });
            attempts.add({
              'label': 'multipart_with_items_booking_product_$bookingProductId',
              'run': () => orderService
                  .createInvoiceMultipart(withSpecificBookingProduct),
              'payload': withSpecificBookingProduct,
            });
          }
        }
        if (!isNearPayCardFlow &&
            !isCashOnlyPayment &&
            _isMethodEnabledForInvoice('cash')) {
          final fallbackInvoiceData = <String, dynamic>{
            ...invoiceDataWithItems,
            'pays': [
              {
                'name': 'دفع نقدي',
                'pay_method': 'cash',
                'amount': payableTotal,
                'index': 0,
              },
            ],
          };
          attempts.add({
            'label': 'json_cash_fallback_with_items',
            'run': () => orderService.createInvoice(fallbackInvoiceData),
            'payload': fallbackInvoiceData,
          });

          final fallbackInvoiceDataBookingOnly = <String, dynamic>{
            ...invoiceDataWithItemsBookingOnly,
            'pays': [
              {
                'name': 'دفع نقدي',
                'pay_method': 'cash',
                'amount': payableTotal,
                'index': 0,
              },
            ],
          };
          attempts.add({
            'label': 'multipart_cash_fallback_with_items',
            'run': () => orderService
                .createInvoiceMultipart(fallbackInvoiceDataBookingOnly),
            'payload': fallbackInvoiceDataBookingOnly,
          });
        }

        Map<String, dynamic>? resolvedInvoice;
        String? resolvedAttemptLabel;
        double? resolvedAttemptPaysTotal;
        var checkedForExistingInvoice = false;
        Future<bool> tryResolveExistingInvoice() async {
          try {
            final bookingDetails =
                await orderService.getBookingDetails(orderId);
            final bookingDetailsMap = asStringKeyMap(bookingDetails['data']);
            final hasInvoice = bookingDetailsMap?['has_invoice'] == true;
            final existingInvoiceId =
                bookingDetailsMap?['invoice_id']?.toString();
            if (hasInvoice &&
                existingInvoiceId != null &&
                existingInvoiceId.isNotEmpty) {
              resolvedInvoice =
                  await orderService.getInvoice(existingInvoiceId);
              resolvedAttemptLabel = 'existing_invoice_on_booking';
              print(
                'ℹ️ booking already has invoice, reusing invoice_id=$existingInvoiceId',
              );
              return true;
            }
          } catch (lookupError) {
            print(
              '⚠️ booking already used but existing invoice lookup failed: $lookupError',
            );
          }
          return false;
        }

        double? extractExpectedPaysTotalFromMessage(String message) {
          final match = RegExp(r'\(([\d.]+)\)').firstMatch(message);
          if (match == null) return null;
          final raw = match.group(1);
          if (raw == null || raw.isEmpty) return null;
          return double.tryParse(raw);
        }

        List<Map<String, dynamic>> normalizePaysToExactTotal(
          dynamic rawPays,
          double expectedTotal,
        ) {
          final paysList = rawPays is List
              ? rawPays
                  .whereType<Map>()
                  .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
                  .toList()
              : <Map<String, dynamic>>[];
          if (paysList.isEmpty) {
            return [
              {'pay_method': 'cash', 'amount': expectedTotal},
            ];
          }

          final normalized = <Map<String, dynamic>>[];
          for (var i = 0; i < paysList.length; i++) {
            final pay = paysList[i];
            final method = _normalizePayMethod(pay['pay_method']?.toString());
            final amount = (pay['amount'] as num?)?.toDouble() ??
                double.tryParse(pay['amount']?.toString() ?? '') ??
                0.0;
            normalized.add({
              ...pay,
              'pay_method': method,
              'amount': amount,
              if (pay['index'] == null) 'index': i,
            });
          }

          final adjusted = _buildUpdatePaysPayload(
            normalized,
            expectedTotal,
            preserveCardAmounts: isNearPayCardFlow,
          );
          for (var i = 0; i < adjusted.length; i++) {
            final method = adjusted[i]['pay_method']?.toString() ?? 'cash';
            adjusted[i] = {
              ...normalized[i],
              'pay_method': method,
              'amount': adjusted[i]['amount'],
              if (normalized[i]['index'] == null) 'index': i,
            };
          }
          return adjusted;
        }

        void stripPromoFieldsFromPayload(Map<String, dynamic> payload) {
          payload.remove('promocode_id');
          payload.remove('promocodeValue');
          payload.remove('promocode_name');
          payload.remove('discount_type');
        }

        void stripPromoFromAllAttemptPayloads(double targetTotal) {
          for (final attempt in attempts) {
            final payload = attempt['payload'];
            if (payload is! Map<String, dynamic>) continue;
            stripPromoFieldsFromPayload(payload);
            if (payload.containsKey('pays')) {
              payload['pays'] = normalizePaysToExactTotal(
                payload['pays'],
                targetTotal,
              );
            }
          }
        }

        final retriedAfterPaysAdjustment = <String>{};
        for (var i = 0; i < attempts.length; i++) {
          final attempt = attempts[i];
          final attemptLabel =
              attempt['label']?.toString() ?? 'unknown_attempt';
          final runner =
              attempt['run'] as Future<Map<String, dynamic>> Function();
          final payload = attempt['payload'];
          try {
            final payloadJson =
                payload is Map ? jsonEncode(payload) : '$payload';
            print('📤 createInvoice payload [$attemptLabel]: $payloadJson');
          } catch (e) {
            print(
                '📤 createInvoice payload [$attemptLabel]: <non-serializable> ($e)');
          }
          try {
            resolvedInvoice = await runner();
            resolvedAttemptLabel = attemptLabel;
            if (payload is Map<String, dynamic>) {
              final copiedPays = clonePaysList(payload['pays']);
              if (copiedPays.isNotEmpty) {
                final paysTotal = sumPaysAmounts(copiedPays);
                if (paysTotal > 0) {
                  resolvedAttemptPaysTotal = paysTotal;
                }
              }
            }
            print('✅ createInvoice success via: $attemptLabel');
            break;
          } on ApiException catch (e) {
            lastInvoiceError = e;
            final status = e.statusCode ?? 0;
            // Stop early on auth/permission errors.
            if (status == 401 || status == 403) rethrow;
            if (!checkedForExistingInvoice) {
              checkedForExistingInvoice = true;
              if (await tryResolveExistingInvoice()) {
                break;
              }
            }

            if (status == 422 &&
                !promoRemovedDueToExpiry &&
                isExpiredPromoMessage(e.message)) {
              promoRemovedDueToExpiry = true;
              promoCodeId = null;
              promoCodeValue = null;
              promoDiscountType = null;
              clearActivePromoSelectionLocally();
              appliedDiscountAmount =
                  _resolveEffectiveDiscountAmount(grossOrderTotal);
              orderTotal = (grossOrderTotal - appliedDiscountAmount)
                  .clamp(0.0, double.infinity);
              payableTotal = double.parse(orderTotal.toStringAsFixed(2));
              normalizedPays = _buildNormalizedPays(
                pays,
                targetTotal: payableTotal,
              );
              normalizedPays = _buildUpdatePaysPayload(
                normalizedPays,
                payableTotal,
                preserveCardAmounts: isNearPayCardFlow,
              );
              stripPromoFromAllAttemptPayloads(payableTotal);
              retriedAfterPaysAdjustment.clear();
              print(
                '♻️ Promo expired during invoice creation; removed promo and retrying without it',
              );
              i--;
              continue;
            }

            final expectedTotal =
                extractExpectedPaysTotalFromMessage(e.message);
            if (status == 422 &&
                expectedTotal != null &&
                payload is Map<String, dynamic> &&
                payload.containsKey('pays') &&
                !retriedAfterPaysAdjustment.contains(attemptLabel)) {
              final currentPays = payload['pays'];
              final adjustedPays = normalizePaysToExactTotal(
                currentPays,
                expectedTotal,
              );
              payload['pays'] = adjustedPays;
              retriedAfterPaysAdjustment.add(attemptLabel);
              print(
                '♻️ Adjusted pays for [$attemptLabel] to match backend total=$expectedTotal and retrying same attempt',
              );
              i--;
              continue;
            }

            print(
              '⚠️ createInvoice failed [$attemptLabel] status=$status message=${e.message} payloadKeys=${payload is Map ? payload.keys.toList() : 'unknown'}',
            );
          } catch (e) {
            lastInvoiceError = e;
            print('⚠️ createInvoice failed [$attemptLabel] error=$e');
          }
        }

        if (resolvedInvoice == null) {
          if (lastInvoiceError is ApiException) {
            final normalizedMessage = lastInvoiceError.message;
            final bookingAlreadyUsed =
                normalizedMessage.contains('رقم الحجز') &&
                    (normalizedMessage.contains('مستخدمة') ||
                        normalizedMessage.contains('مُستخدمة') ||
                        normalizedMessage.contains('مستخدم'));

            if (bookingAlreadyUsed) {
              try {
                final bookingDetails =
                    await orderService.getBookingDetails(orderId);
                final bookingDetailsMap =
                    asStringKeyMap(bookingDetails['data']);
                final hasInvoice = bookingDetailsMap?['has_invoice'] == true;
                final existingInvoiceId =
                    bookingDetailsMap?['invoice_id']?.toString();
                if (hasInvoice &&
                    existingInvoiceId != null &&
                    existingInvoiceId.isNotEmpty) {
                  resolvedInvoice =
                      await orderService.getInvoice(existingInvoiceId);
                  resolvedAttemptLabel = 'existing_invoice_on_booking';
                  print(
                    'ℹ️ booking already has invoice, reusing invoice_id=$existingInvoiceId',
                  );
                }
              } catch (lookupError) {
                print(
                  '⚠️ booking already used but existing invoice lookup failed: $lookupError',
                );
              }
            }

            if (resolvedInvoice == null) {
              throw lastInvoiceError;
            }
          }
          if (resolvedInvoice == null) {
            throw Exception('فشل إنشاء الفاتورة بعد جميع محاولات الربط');
          }
        }
        if (resolvedAttemptLabel != null) {
          print('📌 invoice creation strategy used: $resolvedAttemptLabel');
        }
        invoiceResponse = resolvedInvoice!;
        invoiceNumber = invoiceResponse['data']?['invoice_number']?.toString();
        final invoiceDataMap = asStringKeyMap(invoiceResponse['data']);
        invoiceId = invoiceDataMap?['id']?.toString();
        final rawInvoicePayload = invoiceResponse['data'];
        if (rawInvoicePayload is Map<String, dynamic>) {
          invoicePayload = rawInvoicePayload;
        } else if (rawInvoicePayload is Map) {
          invoicePayload = rawInvoicePayload
              .map((key, value) => MapEntry(key.toString(), value));
        }

        if (invoiceId != null && invoiceId.isNotEmpty) {
          final resolvedPaysTotal = resolvedAttemptPaysTotal;
          final finalInvoiceTotal =
              (resolvedPaysTotal != null && resolvedPaysTotal > 0)
                  ? resolvedPaysTotal
                  : extractExpectedInvoiceTotal(
                      invoiceResponse,
                      payableTotal,
                    );
          final updatePaysSource = normalizedPays;
          var updatePaysPayload =
              _buildUpdatePaysPayload(updatePaysSource, finalInvoiceTotal);
          final skipUpdatePays = <String>{
            'multipart_backend_exact',
            'json_cash_with_sales_meals',
            'multipart_cash_with_sales_meals',
            'json_cash_postman_exact',
            'multipart_cash_postman_exact',
            'json_postman_pays_only',
            'multipart_postman_pays_only',
            'existing_invoice_on_booking',
          }.contains(resolvedAttemptLabel);

          final invoiceIdValue = invoiceId;
          unawaited(() async {
            if (invoiceIdValue.isEmpty) {
              return;
            }
            try {
              await orderService.updateInvoiceDate(
                invoiceId: invoiceIdValue,
                date: dateStr,
              );

              if (skipUpdatePays) {
                print(
                  'ℹ️ Skipping updatePays for invoice_id=$invoiceId to avoid duplicate/cancelled invoices on backend.',
                );
                return;
              }

              await orderService.updateInvoicePays(
                invoiceIdValue,
                pays: updatePaysPayload,
                date: dateStr,
              );
            } on ApiException catch (e) {
              if (skipUpdatePays) return;
              final expectedTotal =
                  extractExpectedPaysTotalFromMessage(e.message);
              if ((e.statusCode ?? 0) == 422 && expectedTotal != null) {
                updatePaysPayload = _buildUpdatePaysPayload(
                  updatePaysSource,
                  expectedTotal,
                );
                print(
                  '♻️ Adjusted updatePays payload to backend total=$expectedTotal and retrying',
                );
                try {
                  await orderService.updateInvoicePays(
                    invoiceIdValue,
                    pays: updatePaysPayload,
                    date: dateStr,
                  );
                } on ApiException catch (retryError) {
                  final retryExpectedTotal =
                      extractExpectedPaysTotalFromMessage(
                            retryError.message,
                          ) ??
                          expectedTotal;
                  if ((retryError.statusCode ?? 0) == 422 &&
                      retryExpectedTotal > 0) {
                    final preferredMethod =
                        updatePaysPayload.first['pay_method']?.toString() ??
                            normalizedPays
                                .firstWhere(
                                  (p) =>
                                      p['pay_method']
                                          ?.toString()
                                          .trim()
                                          .isNotEmpty ==
                                      true,
                                  orElse: () => {'pay_method': 'cash'},
                                )['pay_method']
                                .toString();
                    final forcedPayload = _buildUpdatePaysPayload(
                      [
                        {
                          'name': preferredMethod == 'card'
                              ? 'البطاقة'
                              : 'دفع نقدي',
                          'pay_method': preferredMethod,
                          'amount': retryExpectedTotal,
                          'index': 0,
                        },
                      ],
                      retryExpectedTotal,
                    );
                    print(
                      '♻️ Final updatePays fallback with exact backend total=$retryExpectedTotal method=$preferredMethod',
                    );
                    await orderService.updateInvoicePays(
                      invoiceIdValue,
                      pays: forcedPayload,
                      date: dateStr,
                    );
                  }
                }
              }
            } catch (e) {
              print(
                  '⚠️ updateInvoicePays failed for invoice_id=$invoiceId: $e');
            }
          }());
        }
      }

      if (type == 'payment') {
        // Fire-and-forget: don't block payment completion for cash recording
        unawaited(_recordCashTransaction(normalizedPays));
        // CDS success already shown in fast-path above
      }

      // Capture table name before it gets cleared by table release
      final capturedTableNumber = _selectedTable?.number
          ?? _lastSelectedTable?.number
          ?? selectedTableForOrder?.number;

      if (type == 'payment') {
        TableItem? tableToRelease = selectedTableForOrder;
        if (tableToRelease == null) {
          final bookingTableMap = asStringKeyMap(bookingDataMap?['table']);
          final bookingTableId = firstNonEmptyText(
            [
              bookingNode?['table_id'],
              bookingDataMap?['table_id'],
              bookingTableMap?['id'],
            ],
            allowZero: false,
          );
          if (bookingTableId != null && bookingTableId.isNotEmpty) {
            try {
              tableToRelease =
                  await _tableService.getTableDetails(bookingTableId);
              if (tableToRelease == null) {
                final tables = await _tableService.getTables();
                for (final candidate in tables) {
                  if (candidate.id == bookingTableId) {
                    tableToRelease = candidate;
                    break;
                  }
                }
              }
              if (tableToRelease != null) {
                print(
                  'ℹ️ Resolved table for release from booking payload table_id=$bookingTableId',
                );
              }
            } catch (e) {
              print(
                '⚠️ Could not resolve table for release booking=$orderId table_id=$bookingTableId error=$e',
              );
            }
          }
        }
        if (tableToRelease != null) {
          // Fire-and-forget: don't block payment for table release
          final tableToReleaseCapture = tableToRelease;
          unawaited(() async {
            await _syncTableReservationForOrder(
              tableToReleaseCapture,
              reserved: false,
            );
            if (mounted &&
                (_selectedTable?.id == tableToReleaseCapture.id ||
                    _lastSelectedTable?.id == tableToReleaseCapture.id)) {
              setState(() {
                _selectedTable = null;
                _lastSelectedTable = null;
              });
            }
          }());
        }
      }

      print('💰 DISCOUNT DEBUG: appliedDiscount=$appliedDiscountAmount, orderTotal=$orderTotal, gross=$grossOrderTotal, promo=${_activePromoCode?.code}/${_activePromoCode?.discount}, manualDiscount=$_orderDiscount, isFree=$_isOrderFree');

      final _printTimerStart = DateTime.now();
      debugPrint('⏱️ [PRINT_TIMER] START enrichment');

      // Use payableTotal (server-confirmed) not orderTotal (local estimate)
      // Use displayOrderRef (daily order number) not orderId (booking ID)
      final providerTypeCode = _resolveDeliveryProviderTypeCode();
      final receiptOrderType = providerTypeCode ??
          ((_isMenuListActive && _activeMenuListName.isNotEmpty)
              ? '$bookingOrderType ($_activeMenuListName)'
              : bookingOrderType);
      // Fetch enriched invoice payload (seller info, QR, etc.) before building receipt
      final enrichedPayload = await resolveInvoicePayloadForPreview(
        invoiceId,
        invoicePayload,
      );
      if (enrichedPayload != null) {
        invoicePayload = enrichedPayload;
      }

      // Enrich orderItems with meal_name_translations from booking API
      // so the receipt can resolve names for the invoice language
      try {
        List<dynamic> receiptApiItems = const [];
        final invItems = invoicePayload?['items'] ?? invoicePayload?['sales_meals'];
        if (invItems is List && invItems.isNotEmpty) {
          receiptApiItems = invItems;
        } else if (orderId.isNotEmpty) {
          final orderService = getIt<OrderService>();
          final bd = await orderService.getBookingDetails(orderId);
          final bn = (bd['data'] is Map && bd['data']['booking'] is Map)
              ? bd['data']['booking'] : (bd['data'] ?? bd);
          final bi = (bn is Map) ? (bn['booking_meals'] ?? bn['meals'] ?? bn['items']) : null;
          if (bi is List) receiptApiItems = bi;
        }
        if (receiptApiItems.isNotEmpty) {
          for (var i = 0; i < orderItemsSnapshot.length && i < receiptApiItems.length; i++) {
            final apiItem = receiptApiItems[i];
            if (apiItem is! Map) continue;
            final mt = apiItem['meal_name_translations'];
            if (mt is! Map) continue;
            final existing = orderItemsSnapshot[i]['localizedNames'];
            final merged = <String, String>{};
            if (existing is Map) {
              for (final e in existing.entries) {
                merged[e.key.toString()] = e.value?.toString() ?? '';
              }
            }
            for (final e in mt.entries) {
              final val = e.value?.toString().trim() ?? '';
              if (val.isNotEmpty) merged[e.key.toString()] = val;
            }
            orderItemsSnapshot[i] = <String, Object>{...orderItemsSnapshot[i], 'localizedNames': merged};
          }
        }
      } catch (e) {
        print('⚠️ Receipt enrichment failed: $e');
      }

      final receiptData = _buildOrderReceiptData(
        orderId: displayOrderRef,
        invoiceNumber: invoiceNumber,
        orderItems: orderItemsSnapshot,
        orderTotal: payableTotal,
        orderType: receiptOrderType,
        type: type,
        pays: normalizedPays,
        invoicePayload: invoicePayload,
        carNumber: carNumber,
        tableNumber: capturedTableNumber,
        discountAmount:
            _isOrderFree ? grossOrderTotal
            : (appliedDiscountAmount > 0 ? appliedDiscountAmount : null),
        discountPercentage: _activePromoCode?.type == DiscountType.percentage
            ? _activePromoCode?.discount
            : (_isOrderFree ? 100.0
                : (_orderDiscountType == DiscountType.percentage && _orderDiscount > 0
                    ? _orderDiscount : null)),
        discountName: _isOrderFree
            ? _trUi('طلب مجاني', 'Free Order')
            : (_activePromoCode != null
                ? '${_trUi('كوبون', 'Coupon')}: ${_activePromoCode!.code}'
                : (_orderDiscount > 0
                    ? (_orderDiscountType == DiscountType.percentage
                        ? '${_trUi('خصم', 'Discount')} ${_orderDiscount.toStringAsFixed(0)}%'
                        : _trUi('خصم يدوي', 'Manual Discount'))
                    : null)),
      );
      unawaited(() async {
        // Push a final order payload to KDS with resolved invoice/promo/cash-float
        // so kitchen screens always render the latest financial context.
        if (_isKdsEnabled && kdsOrderDispatched) {
          try {
            displayService.sendOrderToKitchen(
              orderId: orderId,
              orderNumber: displayOrderRef,
              orderType: bookingOrderType,
              items: kdsItemsPayload,
              note: _orderNotesController.text.isNotEmpty
                  ? _orderNotesController.text
                  : null,
              total: orderTotal,
              invoice: _buildKdsInvoicePayload(
                bookingId: orderId,
                orderId: backendOrderId,
                orderNumber: displayOrderRef,
                invoiceId: invoiceId,
                invoiceNumber: invoiceNumber,
                type: type,
                orderTotal: orderTotal,
                grossOrderTotal: grossOrderTotal,
                discountAmount: appliedDiscountAmount,
                promoCodeId: promoCodeId,
                promoCode: promoCodeValue,
                promoDiscountType: promoDiscountType,
                orderItems: orderItemsSnapshot,
                cashFloatSnapshot: _buildCashFloatSnapshot(),
              ),
              switchMode: false,
            );
          } catch (e) {
            print('⚠️ Failed to push final KDS payload for #$orderId: $e');
          }
        }

        // Fallback dispatch in case early dispatch didn't happen.
        if (_isKdsEnabled && !kdsScreenReceivedOrder) {
          try {
            final fallbackDispatchAcked = await _dispatchOrderToKdsWithAck(
              displayService: displayService,
              orderId: orderId,
              orderNumber: displayOrderRef,
              orderType: bookingOrderType,
              items: kdsItemsPayload,
              note: _orderNotesController.text.isNotEmpty
                  ? _orderNotesController.text
                  : null,
              total: orderTotal,
              invoice: _buildKdsInvoicePayload(
                bookingId: orderId,
                orderId: backendOrderId,
                orderNumber: displayOrderRef,
                invoiceId: invoiceId,
                invoiceNumber: invoiceNumber,
                type: type,
                orderTotal: orderTotal,
                grossOrderTotal: grossOrderTotal,
                discountAmount: appliedDiscountAmount,
                promoCodeId: promoCodeId,
                promoCode: promoCodeValue,
                promoDiscountType: promoDiscountType,
                orderItems: orderItemsSnapshot,
                cashFloatSnapshot: _buildCashFloatSnapshot(),
              ),
            );
            kdsOrderDispatched = true;
            kdsScreenReceivedOrder =
                kdsScreenReceivedOrder || fallbackDispatchAcked;
            if (fallbackDispatchAcked) {
              print('✅ NEW_ORDER fallback dispatch to KDS with ACK: #$orderId');
            } else {
              print(
                '⚠️ Fallback NEW_ORDER dispatch sent but ACK still not confirmed: #$orderId',
              );
            }
          } catch (e) {
            print('⚠️ Failed fallback dispatching NEW_ORDER #$orderId: $e');
          }
        }

        final kdsHandledThisPayment =
            type == 'payment' && kdsScreenReceivedOrder;
        final shouldDispatchKitchenPrint =
            !kdsHandledThisPayment || _allowPrintWithKds;
        if (shouldDispatchKitchenPrint) {
          try {
            // Enrich kitchen items with bilingual names.
            // Source 1: invoicePayload (available for type=payment)
            // Source 2: booking details API (fallback for type=later/deferred)
            List<dynamic> apiItemsList = const [];

            // Try invoicePayload first
            final invoiceItems = (invoicePayload?['items']) ??
                (invoicePayload?['sales_meals']) ??
                (invoicePayload?['meals']);
            if (invoiceItems is List && invoiceItems.isNotEmpty) {
              apiItemsList = invoiceItems;
              print('🔍 ENRICH: using invoicePayload items (${invoiceItems.length})');
            } else {
              print('🔍 ENRICH: invoicePayload is ${invoicePayload == null ? "NULL" : "empty items"}');
            }

            // Fallback: fetch booking details for bilingual names
            if (apiItemsList.isEmpty && orderId.isNotEmpty) {
              try {
                final orderService = getIt<OrderService>();
                final bookingDetails = await orderService.getBookingDetails(orderId);
                final bookingData = bookingDetails['data'] ?? bookingDetails;
                // API returns nested structure: { booking: { meals: [...] }, booking_services: [...] }
                final bookingNode = (bookingData is Map && bookingData['booking'] is Map)
                    ? bookingData['booking']
                    : bookingData;
                print('🔍 ENRICH: bookingNode keys=${bookingNode is Map ? bookingNode.keys.toList() : "NOT_MAP"}');
                final bookingItems = (bookingNode is Map)
                    ? (bookingNode['meals'] ??
                        bookingNode['items'] ??
                        bookingNode['sales_meals'] ??
                        bookingNode['booking_meals'] ??
                        bookingNode['card'])
                    : null;
                if (bookingItems is List && bookingItems.isNotEmpty) {
                  apiItemsList = bookingItems;
                  final firstItem = bookingItems[0];
                  print('🔍 ENRICH: booking items found (${bookingItems.length}), first item keys=${firstItem is Map ? firstItem.keys.toList() : "NOT_MAP"}');
                  if (firstItem is Map) {
                    print('🔍 ENRICH: first item_name="${firstItem['item_name']}" meal_name="${firstItem['meal_name']}" name="${firstItem['name']}" name_en="${firstItem['name_en']}"');
                  }
                } else {
                  print('🔍 ENRICH: no booking items found (bookingItems=${bookingItems?.runtimeType})');
                }
              } catch (e) {
                print('⚠️ Could not fetch booking details for bilingual names: $e');
              }
            }

            // Resolve printer language (local, device-scoped) for kitchen item names
            final String kitchenPriLang = printerLanguageSettings.primary;

            final enrichedItems = orderItemsSnapshot.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = Map<String, dynamic>.from(entry.value);

              if (idx < apiItemsList.length) {
                final apiItem = apiItemsList[idx];
                if (apiItem is Map) {
                  // Merge meal_name_translations into localizedNames
                  final mealTranslations = apiItem['meal_name_translations'];
                  if (mealTranslations is Map) {
                    final existing = item['localizedNames'];
                    final merged = existing is Map
                        ? Map<String, String>.from(existing.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')))
                        : <String, String>{};
                    for (final te in mealTranslations.entries) {
                      final val = te.value?.toString().trim() ?? '';
                      if (val.isNotEmpty) {
                        merged[te.key.toString()] = val;
                      }
                    }
                    item['localizedNames'] = merged;
                    item['meal_name_translations'] = mealTranslations;
                  }

                  // Copy addons_translations
                  final addonsTranslations = apiItem['addons_translations'];
                  if (addonsTranslations is List) {
                    item['addons_translations'] = addonsTranslations;
                  }

                  // Try item_name (combined bilingual: "عربي - English")
                  final currentNameEn = item['nameEn']?.toString().trim() ?? '';
                  if (currentNameEn.isEmpty) {
                    final apiName = (apiItem['item_name'] ??
                        apiItem['meal_name'] ??
                        apiItem['name'])?.toString() ?? '';
                    if (apiName.contains(' - ')) {
                      item['nameAr'] = apiName.split(' - ').first.trim();
                      item['nameEn'] = apiName.split(' - ').last.trim();
                    }
                    // Also try explicit name_en field
                    if ((item['nameEn']?.toString().trim() ?? '').isEmpty) {
                      final explicitEn = (apiItem['name_en'] ??
                          apiItem['item_name_en'] ??
                          apiItem['meal_name_en'])?.toString().trim() ?? '';
                      if (explicitEn.isNotEmpty) {
                        item['nameEn'] = explicitEn;
                      }
                    }
                  }
                }
              }

              // Resolve item name based on invoice primary language
              final localizedNames = item['localizedNames'];
              if (localizedNames is Map) {
                final resolvedName = localizedNames[kitchenPriLang]?.toString().trim() ?? '';
                if (resolvedName.isNotEmpty) {
                  item['name'] = resolvedName;
                } else if (kitchenPriLang == 'en' && (item['nameEn']?.toString().trim() ?? '').isNotEmpty) {
                  item['name'] = item['nameEn'];
                }
              }

              return item;
            }).toList();

            await _triggerKitchenPrint(
              orderId: orderId,
              invoiceNumber: invoiceNumber,
              orderItems: enrichedItems,
              dailyOrderNumber: displayOrderRef,
              capturedTableNumber: capturedTableNumber,
              carNumber: carNumber,
            );
          } catch (_) {}
        } else {
          print(
            'ℹ️ Kitchen printer dispatch skipped for #$orderId because KDS handled this paid order and print-with-KDS is disabled.',
          );
        }

        // Clear Customer Display System after successful order
        if (_isCdsEnabled &&
            (displayService.isConnected || displayService.isPresentationActive)) {
          displayService.clearCart();
        }
      }());

      // Loading already closed and cart already cleared above (fast path)

      if (type == 'payment') {
        final elapsed = DateTime.now().difference(_printTimerStart).inMilliseconds;
        debugPrint('⏱️ [PRINT_TIMER] PRINT after ${elapsed}ms (enrichment + build)');
        unawaited(
          _autoPrintReceiptCopies(
            receiptData: receiptData,
            invoiceId: invoiceId,
          ),
        );
      }
      } catch (invoiceError) {
        // Invoice/post-booking error - booking already succeeded, show warning
        if (mounted) {
          debugPrint('⚠️ Post-booking error (booking OK, invoice failed): $invoiceError');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _trUi(
                  'تم حفظ الطلب بنجاح ولكن تعذر إصدار الفاتورة. يمكنك إصدارها من شاشة الطلبات.',
                  'Order saved but invoice creation failed. You can create it from the orders screen.',
                ),
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      // Close loading if still open (booking failed before fast-path dismiss)
      if (showLoadingOverlay && mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Show error
      if (mounted) {
        final userMessage = ErrorHandler.toUserMessage(
          e,
          fallback: 'تعذر حفظ الطلب حاليًا. حاول مرة أخرى.',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessage),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: () {
                unawaited(
                  _processPayment(
                    type: type,
                    pays: pays,
                    showLoadingOverlay: showLoadingOverlay,
                    showSuccessDialog: showSuccessDialog,
                    clearCartOnSuccess: clearCartOnSuccess,
                    isNearPayCardFlow: isNearPayCardFlow,
                  ),
                );
              },
            ),
          ),
        );
      }
    }
  }

  OrderReceiptData _buildOrderReceiptData({
    required String orderId,
    String? invoiceNumber,
    required List<Map<String, dynamic>> orderItems,
    required double orderTotal,
    required String orderType,
    required String type,
    required List<Map<String, dynamic>> pays,
    Map<String, dynamic>? invoicePayload,
    String carNumber = '',
    String? tableNumber,
    double? discountAmount,
    double? discountPercentage,
    String? discountName,
  }) {
    final subtotal = _subtotalFromTaxInclusiveTotal(orderTotal);
    final vat = _taxFromTaxInclusiveTotal(orderTotal);
    final branch = invoicePayload?['branch'];
    final seller = invoicePayload?['seller'];
    final invoice = invoicePayload?['invoice'];
    final branchMap = branch is Map ? branch : null;
    final sellerMap = seller is Map ? seller : null;
    // The API nests seller inside branch (branch.seller), not at root
    final nestedSeller = branchMap?['seller'];
    final nestedSellerMap = nestedSeller is Map ? nestedSeller : null;
    final originalSeller = branchMap?['original_seller'];
    final originalSellerMap = originalSeller is Map ? originalSeller : null;
    final invoiceMap = invoice is Map ? invoice : null;

    String? firstNonEmptyString(List<dynamic> values) {
      for (final value in values) {
        final text = value?.toString().trim();
        if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
          return text;
        }
      }
      return null;
    }

    List<ReceiptPayment> parsePaymentsList(dynamic paysRaw) {
      final paysList = paysRaw is List ? paysRaw : const [];
      final parsedPayments = <ReceiptPayment>[];

      double parseNumLocal(dynamic value) {
        if (value is num) return value.toDouble();
        if (value is String) return double.tryParse(value) ?? 0.0;
        return 0.0;
      }

      for (final pay in paysList) {
        final map = pay is Map ? pay : null;
        if (map == null) continue;
        final method = (map['pay_method'] ?? map['method'] ?? map['name'])
            ?.toString()
            .trim()
            .toLowerCase();
        final numericAmount = parseNumLocal(map['amount'] ?? map['value'] ?? map['paid'] ?? map['total']);
        if (method == null || method.isEmpty) continue;

        String label = 'نقدي';
        switch (method) {
          case 'cash':
          case 'نقدي':
          case 'كاش':
            label = 'نقدي';
            break;
          case 'card':
          case 'mada':
          case 'visa':
          case 'benefit':
          case 'benefit_pay':
          case 'benefit pay':
          case 'بطاقة':
          case 'مدى':
          case 'فيزا':
          case 'ماستر':
          case 'ماستر كارد':
          case 'بينيفت':
          case 'بينيفت باي':
            label = 'بطاقة';
            break;
          case 'stc':
          case 'stc_pay':
          case 'stc pay':
          case 'اس تي سي':
          case 'اس تي سي باي':
            label = 'STC Pay';
            break;
          case 'bank_transfer':
          case 'bank':
          case 'bank transfer':
          case 'تحويل بنكي':
          case 'تحويل بنكى':
            label = 'تحويل بنكي';
            break;
          case 'wallet':
          case 'المحفظة':
          case 'المحفظة الالكترونية':
          case 'المحفظة الإلكترونية':
            label = 'محفظة';
            break;
          case 'cheque':
          case 'check':
          case 'شيك':
            label = 'شيك';
            break;
          case 'petty_cash':
          case 'petty cash':
          case 'بيتي كاش':
            label = 'بيتي كاش';
            break;
          case 'pay_later':
          case 'postpaid':
          case 'deferred':
          case 'pay later':
          case 'الدفع بالآجل':
          case 'الدفع بالاجل':
            label = 'الدفع بالآجل';
            break;
          case 'tabby':
          case 'تابي':
            label = 'تابي';
            break;
          case 'tamara':
          case 'تمارا':
            label = 'تمارا';
            break;
          case 'keeta':
          case 'كيتا':
            label = 'كيتا';
            break;
          case 'my_fatoorah':
          case 'myfatoorah':
          case 'my fatoorah':
          case 'ماي فاتورة':
          case 'ماي فاتوره':
            label = 'ماي فاتورة';
            break;
          case 'jahez':
          case 'جاهز':
            label = 'جاهز';
            break;
          case 'talabat':
          case 'طلبات':
            label = 'طلبات';
            break;
          case 'hunger_station':
          case 'hungerstation':
          case 'هنقر ستيشن':
          case 'هنقر':
            label = 'هنقر ستيشن';
            break;
          default:
            label = method;
        }
        parsedPayments.add(ReceiptPayment(methodLabel: label, amount: numericAmount));
      }
      return parsedPayments;
    }

    // Extract branch address & mobile for receipt header.
    // Combine district + address when both exist (matches the old paper
    // receipt layout that showed "الحي، العنوان"); fall back to whichever
    // is available.
    final _branchDistrict = (branchMap?['district']?.toString() ?? '').trim();
    final _branchStreet = (firstNonEmptyString([
          branchMap?['address'],
          sellerMap?['address'],
          invoiceMap?['branch_address'],
          invoicePayload?['address'],
        ]) ?? '')
        .trim();
    final branchAddress = (_branchDistrict.isNotEmpty &&
            _branchStreet.isNotEmpty &&
            _branchDistrict != _branchStreet)
        ? '$_branchDistrict، $_branchStreet'
        : (_branchStreet.isNotEmpty ? _branchStreet : _branchDistrict);
    // English fields from merged payload
    final branchAddressEn = firstNonEmptyString([
      invoicePayload?['branch_address_en'],
      invoicePayload?['branch_district_en'],
    ]);
    final sellerNameEn = firstNonEmptyString([
      invoicePayload?['seller_name_en'],
    ]);
    final branchMobile = firstNonEmptyString([
      branchMap?['mobile'],
      branchMap?['phone'],
      sellerMap?['mobile'],
      sellerMap?['phone'],
      invoiceMap?['branch_mobile'],
      invoicePayload?['mobile'],
    ]);

    // Cache seller + branch info from this payload for future receipts
    if (nestedSellerMap != null && nestedSellerMap.isNotEmpty) {
      _cachedSellerInfo = Map<String, dynamic>.from(nestedSellerMap);
    } else if (originalSellerMap != null && originalSellerMap.isNotEmpty) {
      _cachedSellerInfo = Map<String, dynamic>.from(originalSellerMap);
    }
    if (branchMap != null && branchMap.isNotEmpty) {
      _cachedBranchMap = Map<String, dynamic>.from(branchMap);
    }
    if (invoicePayload != null) {
      _cachedBranchAddressEn ??= invoicePayload['branch_address_en']?.toString();
      _cachedSellerNameEn ??= invoicePayload['seller_name_en']?.toString();
    }

    // Extract tax number (API nests it in branch.seller.tax_number)
    // Fallback to cached seller info from previous successful invoice
    final taxNumber = firstNonEmptyString([
      nestedSellerMap?['tax_number'],
      originalSellerMap?['tax_number'],
      branchMap?['tax_number'],
      sellerMap?['tax_number'],
      nestedSellerMap?['vat_number'],
      originalSellerMap?['vat_number'],
      branchMap?['vat_number'],
      sellerMap?['vat_number'],
      invoiceMap?['tax_number'],
      invoiceMap?['vat_number'],
      invoicePayload?['tax_number'],
      invoicePayload?['vat_number'],
      _cachedSellerInfo?['tax_number'],
      _cachedSellerInfo?['vat_number'],
    ]);

    // Extract commercial register number (same nesting pattern)
    final commercialRegNumber = firstNonEmptyString([
      nestedSellerMap?['commercial_register_number'],
      nestedSellerMap?['commercial_register'],
      originalSellerMap?['commercial_register_number'],
      originalSellerMap?['commercial_register'],
      branchMap?['commercial_register_number'],
      sellerMap?['commercial_register_number'],
      branchMap?['commercial_register'],
      sellerMap?['commercial_register'],
      branchMap?['commercial_number'],
      sellerMap?['commercial_number'],
      nestedSellerMap?['cr_number'],
      originalSellerMap?['cr_number'],
      branchMap?['cr_number'],
      sellerMap?['cr_number'],
      invoiceMap?['commercial_register_number'],
      invoiceMap?['commercial_register'],
      invoiceMap?['commercial_number'],
      invoiceMap?['cr_number'],
      invoicePayload?['commercial_register_number'],
      invoicePayload?['commercial_register'],
      invoicePayload?['commercial_number'],
      invoicePayload?['cr_number'],
      _cachedSellerInfo?['commercial_register_number'],
      _cachedSellerInfo?['commercial_register'],
      _cachedSellerInfo?['commercial_number'],
      _cachedSellerInfo?['cr_number'],
    ]);

    // Extract QR code (for base64 QR)
    final qrValue = (invoiceMap?['qr_image'] ??
            invoiceMap?['zatca_qr_image'] ??
            invoicePayload?['qr_image'])
        ?.toString();

    // Extract ZATCA QR image URL (separate from base64 QR)
    final zatcaQrImageUrl =
        (invoiceMap?['zatca_qr_image'] ?? invoicePayload?['zatca_qr_image'])
            ?.toString();

    // Extract seller logo from branch.seller.logo or branch.original_seller.logo
    String? logoUrl;
    if (branchMap != null) {
      final branchSeller = branchMap['seller'];
      final originalSeller = branchMap['original_seller'];

      if (branchSeller is Map && branchSeller['logo'] != null) {
        logoUrl = branchSeller['logo'].toString();
      } else if (originalSeller is Map && originalSeller['logo'] != null) {
        final logo = originalSeller['logo'].toString();
        // If logo starts with /, prepend base URL
        if (logo.startsWith('/')) {
          logoUrl = 'https://portal.hermosaapp.com$logo';
        } else {
          logoUrl = logo;
        }
      }
    }

    final invoiceDateTime = (invoiceMap?['ISO8601'] ??
            invoiceMap?['date'] ??
            invoicePayload?['created_at'])
        ?.toString();

    // Extract cashier name
    final cashierName = (invoiceMap?['cashier'] is Map
            ? (invoiceMap?['cashier']['fullname'] ??
                invoiceMap?['cashier']['name'])
            : invoiceMap?['cashier_name'] ??
                invoicePayload?['cashier_name'] ??
                invoicePayload?['user_name'])
        ?.toString();

    // Use cashier name as seller name
    final sellerName = cashierName;
    final branchName = (branchMap?['seller_name'] ??
            invoicePayload?['table_name'] ??
            _selectedTable?.number)
        ?.toString();
    // Extract menu list suffix (e.g. "(هنقرستيشن)") from orderType if present
    String menuListSuffix = '';
    String baseOrderType = orderType;
    final parenIdx = orderType.indexOf('(');
    if (parenIdx > 0) {
      menuListSuffix = ' ${orderType.substring(parenIdx).trim()}';
      baseOrderType = orderType.substring(0, parenIdx).trim();
    }
    // If the client already resolved a delivery-provider type code
    // (e.g. `hungerstation_delivery`), prefer it over the generic `type: services`
    // the backend stores — the API doesn't track the delivery provider.
    final baseLower = baseOrderType.toLowerCase();
    final isClientProviderCode = baseLower.startsWith('hungerstation_') ||
        baseLower.startsWith('hunger_station_') ||
        baseLower.startsWith('talabat_') ||
        baseLower.startsWith('jahez_') ||
        baseLower.startsWith('gahez_');
    final rawResolvedOrderType = isClientProviderCode
        ? baseOrderType
        : _normalizeOrderTypeValue(
            firstNonEmptyString([
                  invoiceMap?['type'],
                  invoiceMap?['booking_type'],
                  invoiceMap?['order_type'],
                  invoicePayload?['type'],
                  invoicePayload?['booking_type'],
                  invoicePayload?['order_type'],
                  baseOrderType,
                ]) ??
                baseOrderType,
          );
    final resolvedOrderType = menuListSuffix.isNotEmpty
        ? '$rawResolvedOrderType$menuListSuffix'
        : rawResolvedOrderType;

    // Extract the actual daily order number from the invoice payload.
    // The API stores it under booking/order sub-objects or at the root level.
    final bookingNode = invoicePayload?['booking'];
    final orderNode = invoicePayload?['order'];
    final bookingNodeMap = bookingNode is Map ? bookingNode : null;
    final orderNodeMap = orderNode is Map ? orderNode : null;
    final resolvedDailyOrderNumber = firstNonEmptyString([
      invoiceMap?['daily_order_number'],
      invoiceMap?['order_number'],
      bookingNodeMap?['daily_order_number'],
      bookingNodeMap?['order_number'],
      orderNodeMap?['daily_order_number'],
      orderNodeMap?['order_number'],
      invoicePayload?['daily_order_number'],
      invoicePayload?['order_number'],
    ]);

    // Extract correct invoice number from the payload (not booking ID).
    final resolvedInvoiceNumber = firstNonEmptyString([
          invoiceNumber,
          invoiceMap?['invoice_number'],
          invoicePayload?['invoice_number'],
        ]) ??
        '';

    // Extract English seller name from "تكانة | Takana" or from merged en field
    String resolvedSellerNameEn;
    if (sellerNameEn != null && sellerNameEn.isNotEmpty) {
      resolvedSellerNameEn = sellerNameEn;
    } else if (sellerName != null && sellerName.contains('|')) {
      resolvedSellerNameEn = sellerName.split('|').last.trim();
    } else {
      resolvedSellerNameEn = sellerName ?? _userName;
    }

    String resolvedSellerNameAr;
    if (sellerName != null && sellerName.contains('|')) {
      resolvedSellerNameAr = sellerName.split('|').first.trim();
    } else {
      resolvedSellerNameAr = sellerName ?? _userName;
    }

    // English address (from merged en payload or fallback)
    final resolvedBranchAddressEn = branchAddressEn ?? branchAddress ?? '';

    return OrderReceiptData(
      invoiceNumber: resolvedInvoiceNumber,
      issueDateTime: invoiceDateTime ?? DateTime.now().toIso8601String(),
      sellerNameAr: resolvedSellerNameAr,
      sellerNameEn: resolvedSellerNameEn,
      vatNumber: taxNumber ?? '',
      branchName: branchName ?? '',
      carNumber: carNumber,
      // Table number threads through to the invoice header so dine-in
      // receipts carry the table label the cashier selected at checkout.
      // Previous builds dropped this on the floor because the builder
      // wasn't forwarding it to OrderReceiptData at all.
      tableNumber: tableNumber?.trim().isNotEmpty == true ? tableNumber : null,
      branchAddressEn: resolvedBranchAddressEn,
      items: () {
        // Merge bilingual item names from invoice API into cart items
        final apiItems = (invoiceMap is Map ? invoiceMap['items'] : null) ??
            (invoicePayload?['items']);
        final apiItemsList = apiItems is List ? apiItems : const [];

        // Resolve printer language (local, device-scoped) for item names
        final String invoicePri = printerLanguageSettings.primary;
        final String invoiceSec = printerLanguageSettings.secondary;

        return orderItems.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          final cartName = item['name']?.toString() ?? '';
          final localizedNames = item['localizedNames'];
          final namesMap = localizedNames is Map
              ? Map<String, String>.from(
                  localizedNames.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')))
              : <String, String>{};

          // Try to get bilingual name from API (format: "عربي - English")
          String arName = item['nameAr']?.toString() ?? cartName;
          String enName = item['nameEn']?.toString() ?? '';

          if (idx < apiItemsList.length) {
            final apiItem = apiItemsList[idx];
            final apiName = (apiItem is Map ? apiItem['item_name']?.toString() : null) ?? '';
            if (apiName.contains(' - ')) {
              arName = apiName.split(' - ').first.trim();
              enName = apiName.split(' - ').last.trim();
            } else if (apiName.isNotEmpty) {
              arName = apiName;
            }
          }

          // Fallback: split cart name if it has " - "
          if (enName.isEmpty && cartName.contains(' - ')) {
            arName = cartName.split(' - ').first.trim();
            enName = cartName.split(' - ').last.trim();
          }

          // Ensure namesMap has ar/en from resolved values
          if (!namesMap.containsKey('ar') || namesMap['ar']!.isEmpty) {
            if (arName.isNotEmpty) namesMap['ar'] = arName;
          }
          if (!namesMap.containsKey('en') || namesMap['en']!.isEmpty) {
            if (enName.isNotEmpty) namesMap['en'] = enName;
          }

          // Resolve name based on invoice language settings
          String resolveName(String langCode) {
            if (namesMap.containsKey(langCode) && namesMap[langCode]!.isNotEmpty) {
              return namesMap[langCode]!;
            }
            // Fallback: English → Arabic → cart name
            if (enName.isNotEmpty) return enName;
            return arName.isNotEmpty ? arName : cartName;
          }

          final primaryName = resolveName(invoicePri);
          final secondaryName = resolveName(invoiceSec);

          final rawQty = (item['quantity'] as num?)?.toDouble() ?? 0;
          final rawUnitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0;
          final rawTotal = (item['total'] as num?)?.toDouble() ?? 0;

          final multiplier = _isTaxEnabled ? (1.0 + _taxRate) : 1.0;

          // Convert extras to ReceiptAddon list. Pulls per-language names
          // from the `translations.option` map the cart attaches when the
          // product's addons came from the API — this is what lets the
          // cashier invoice print the addon in the chosen invoice language
          // (Spanish, English, …) instead of only Arabic.
          final rawExtras = item['extras'];
          final addons = <ReceiptAddon>[];
          if (rawExtras is List) {
            for (final e in rawExtras) {
              if (e is Map) {
                final name = e['name']?.toString() ?? '';
                if (name.isEmpty) continue;
                final price = (e['price'] is num)
                    ? (e['price'] as num).toDouble()
                    : double.tryParse(e['price']?.toString() ?? '') ?? 0.0;

                final translations = e['translations'];
                final optionMap = (translations is Map)
                    ? translations['option']
                    : null;
                final localized = <String, String>{};
                if (optionMap is Map) {
                  for (final entry in optionMap.entries) {
                    final v = entry.value?.toString().trim() ?? '';
                    if (v.isEmpty) continue;
                    localized[entry.key.toString().trim().toLowerCase()] = v;
                  }
                }

                addons.add(ReceiptAddon(
                  nameAr: localized['ar']?.isNotEmpty == true
                      ? localized['ar']!
                      : name,
                  nameEn: localized['en']?.isNotEmpty == true
                      ? localized['en']!
                      : name,
                  price: price,
                  localizedNames: localized,
                ));
              }
            }
          }

          return ReceiptItem(
            nameAr: primaryName,
            nameEn: secondaryName.isNotEmpty ? secondaryName : primaryName,
            quantity: rawQty,
            unitPrice: rawUnitPrice * multiplier,
            total: rawTotal * multiplier,
            addons: addons.isNotEmpty ? addons : null,
          );
        }).toList();
      }(),
      totalExclVat: subtotal,
      vatAmount: vat,
      totalInclVat: orderTotal,
      paymentMethod: _buildPaymentMethodLabel(type: type, pays: pays),
      payments: parsePaymentsList(pays),
      qrCodeBase64: qrValue ?? '',
      sellerLogo: logoUrl,
      zatcaQrImage: zatcaQrImageUrl,
      branchAddress: branchAddress,
      branchMobile: branchMobile,
      commercialRegisterNumber: commercialRegNumber,
      cashierName: cashierName ?? _userName,
      orderType: resolvedOrderType,
      orderNumber: resolvedDailyOrderNumber ?? orderId,  // orderId is now displayOrderRef (daily order#)
      orderDiscountAmount: discountAmount,
      orderDiscountPercentage: discountPercentage,
      orderDiscountName: discountName,
    );
  }

  String _payMethodArabicLabel(String method) {
    switch (method) {
      case 'cash':
        return 'نقدي';
      case 'card':
        return 'بطاقة';
      case 'mada':
        return 'مدى';
      case 'visa':
        return 'فيزا';
      case 'stc':
        return 'STC Pay';
      case 'bank_transfer':
        return 'تحويل بنكي';
      case 'wallet':
        return 'محفظة';
      case 'cheque':
        return 'شيك';
      case 'benefit':
        return 'Benefit Pay';
      case 'tabby':
        return 'Tabby';
      case 'tamara':
        return 'Tamara';
      case 'keeta':
        return 'Keeta';
      case 'my_fatoorah':
        return 'ماي فاتورة';
      case 'jahez':
        return 'جاهز';
      case 'talabat':
        return 'طلبات';
      case 'hunger_station':
        return 'هنقر ستيشن';
      case 'petty_cash':
        return 'بيتي كاش';
      case 'pay_later':
        return 'دفع لاحق';
      default:
        return method.isNotEmpty ? method : 'دفع';
    }
  }

  String _buildPaymentMethodLabel({
    required String type,
    required List<Map<String, dynamic>> pays,
  }) {
    if (type != 'payment') return 'دفع لاحق';
    if (pays.isEmpty) return 'دفع';

    // Split payment: show method + amount for each
    if (pays.length > 1) {
      final parts = pays.map((pay) {
        final method = _normalizePayMethod(pay['pay_method']?.toString());
        final label = _payMethodArabicLabel(method);
        final amount = pay['amount'];
        if (amount != null) {
          final amountStr = (amount is num)
              ? amount.toStringAsFixed(2)
              : (double.tryParse(amount.toString()) ?? 0).toStringAsFixed(2);
          return '$label ($amountStr)';
        }
        return label;
      }).toList();
      return parts.join(' - ');
    }

    // Single payment
    final method = _normalizePayMethod(pays.first['pay_method']?.toString());
    return _payMethodArabicLabel(method);
  }

  Map<String, dynamic> _buildKdsInvoicePayload({
    required String bookingId,
    String? orderId,
    String? orderNumber,
    String? invoiceId,
    String? invoiceNumber,
    required String type,
    required double orderTotal,
    required double grossOrderTotal,
    required double discountAmount,
    String? promoCodeId,
    String? promoCode,
    String? promoDiscountType,
    required List<Map<String, dynamic>> orderItems,
    Map<String, dynamic>? cashFloatSnapshot,
  }) {
    final resolvedOrderId =
        (orderId ?? '').trim().isNotEmpty ? orderId!.trim() : bookingId;
    final resolvedOrderNumber = orderNumber?.trim();
    final originalSubtotal = _subtotalFromTaxInclusiveTotal(grossOrderTotal);
    final originalVat = _taxFromTaxInclusiveTotal(grossOrderTotal);
    final discountedSubtotal = _subtotalFromTaxInclusiveTotal(orderTotal);
    final discountedVat = _taxFromTaxInclusiveTotal(orderTotal);
    final taxPercentage = double.parse((_taxRate * 100).toStringAsFixed(4));

    return {
      'bookingId': bookingId,
      'booking_id': bookingId,
      'orderId': resolvedOrderId,
      'order_id': resolvedOrderId,
      if (resolvedOrderNumber != null && resolvedOrderNumber.isNotEmpty)
        'orderNumber': resolvedOrderNumber,
      if (resolvedOrderNumber != null && resolvedOrderNumber.isNotEmpty)
        'order_number': resolvedOrderNumber,
      if (invoiceId != null) 'invoiceId': invoiceId,
      'invoiceNumber': invoiceNumber ?? 'KDS-$bookingId',
      'source': 'cashier',
      'invoiceType': type == 'payment' ? 'sales' : 'kitchen',
      'paymentStatus': type == 'payment' ? 'paid' : 'pending',
      'subtotal': discountedSubtotal,
      'tax': discountedVat,
      'tax_rate': _taxRate,
      'tax_percentage': taxPercentage,
      'has_tax': _isTaxEnabled,
      'total': orderTotal,
      'original_subtotal': originalSubtotal,
      'original_tax': originalVat,
      'original_total': grossOrderTotal,
      'discount': discountAmount,
      'createdAt': DateTime.now().toIso8601String(),
      'items': orderItems
          .map(
            (item) => {
              'name': item['name'],
              'quantity': item['quantity'],
              'unitPrice': item['unitPrice'],
              'total': item['total'],
              'notes': item['notes'],
              'extras': item['extras'],
              // ✅ Include discount details per item
              'original_unit_price': item['original_unit_price'],
              'original_total': item['original_total'],
              'final_total': item['final_total'],
              'discount': item['discount'],
              'discount_type': item['discount_type'],
              'is_free': item['is_free'],
            },
          )
          .toList(),
      if (promoCode != null && promoCode.isNotEmpty)
        'promo': {
          if (promoCodeId != null && promoCodeId.isNotEmpty) 'id': promoCodeId,
          'code': promoCode,
          'discount_type': promoDiscountType ?? 'fixed',
          'discount_amount': discountAmount,
        },
      if (cashFloatSnapshot != null) 'cash_float': cashFloatSnapshot,
    };
  }
}
