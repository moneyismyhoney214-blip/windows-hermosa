// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, avoid_dynamic_calls, library_private_types_in_public_api
part of '../main_screen.dart';

extension MainScreenPaymentHelpers on _MainScreenState {
  String _formatBookingPrice(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(ApiConstants.digitsNumber.clamp(0, 4));
  }

  // Thin shims that delegate to pure logic in `lib/controllers/payment_logic.dart`; new code should call `PaymentLogic.*` directly.
  String _normalizePayMethod(String? method) =>
      PaymentLogic.normalizePayMethod(method);

  bool _isCashOnlyPayment(List<Map<String, dynamic>> pays) =>
      PaymentLogic.isCashOnlyPayment(pays);

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

  // Delegates to `PaymentMethodPolicy` (pure); screen owns the live state.
  bool _isMethodEnabledForInvoice(String normalizedMethod) =>
      PaymentMethodPolicy.isMethodEnabledForInvoice(
        normalizedMethod: normalizedMethod,
        enabledPayMethods: _enabledPayMethods,
        isProfileNearPayEnabled: _isProfileNearPayEnabled,
        isCdsEnabled: _isCdsEnabled,
      );

  bool _hasAnyEnabledPayMethod() => PaymentMethodPolicy.hasAnyEnabledPayMethod(
        enabledPayMethods: _enabledPayMethods,
        isProfileNearPayEnabled: _isProfileNearPayEnabled,
        isCdsEnabled: _isCdsEnabled,
      );

  Map<String, bool> _effectiveEnabledPayMethodsForTender() {
    final effective = PaymentMethodPolicy.effectiveForTender(_enabledPayMethods);
    // NearPay handles card payments — keep visible for split; actual flow triggered in _processPayment.
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
          // Round to branch currency precision; BHD (3 decimals) would otherwise trigger 422.
          'amount': ApiConstants.roundMoney(effectiveTotal),
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
      final roundedAmount = ApiConstants.roundMoney(amount);
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

  int _pow10(int n) {
    var r = 1;
    for (var i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }

  List<Map<String, dynamic>> _buildUpdatePaysPayload(
    List<Map<String, dynamic>> pays,
    double invoiceTotal, {
    bool preserveCardAmounts = false,
  }) {
    double round2(double value) => ApiConstants.roundMoney(value);
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
    // Adjust at branch currency precision (0.01 SAR, 0.001 BHD) — backend strict-validates `sum(payments) == invoice.total`.
    final adjustmentEpsilon =
        1.0 / _pow10(ApiConstants.digitsNumber.clamp(0, 6));
    if (diff.abs() >= adjustmentEpsilon) {
      final adjustmentIndex = resolveAdjustmentIndex();
      final currentAmount =
          (normalized[adjustmentIndex]['amount'] as num?)?.toDouble() ?? 0.0;
      normalized[adjustmentIndex]['amount'] = toBackendAmount(
        (currentAmount + diff).clamp(0.0, double.infinity),
      );
    }

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
      // Message remains queued until websocket reconnects.
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

  /// Merges backend-supplied translation maps into the `localizedNames`
  /// field of each row in [orderItemsSnapshot] so the receipt renderer
  /// can pick the cashier-configured language. Mutates the snapshot in
  /// place (each entry is replaced with a new map that has the merged
  /// translations). Pure data prep — no rendering decisions live here.
  Future<void> _enrichOrderItemsWithTranslations({
    required List<Map<String, Object>> orderItemsSnapshot,
    required Map<String, dynamic>? invoicePayload,
    required String orderId,
  }) async {
    try {
      List<dynamic> receiptApiItems = const [];
      final invItems = invoicePayload?['items'] ??
          invoicePayload?['sales_meals'] ??
          invoicePayload?['sales_services'];
      if (invItems is List && invItems.isNotEmpty) {
        receiptApiItems = invItems;
      } else if (orderId.isNotEmpty) {
        final orderService = getIt<OrderService>();
        final bd = await orderService.getBookingDetails(orderId);
        final bn = (bd['data'] is Map && bd['data']['booking'] is Map)
            ? bd['data']['booking']
            : (bd['data'] ?? bd);
        final bi = (bn is Map)
            ? (bn['booking_meals'] ??
                bn['booking_services'] ??
                bn['meals'] ??
                bn['items'])
            : null;
        if (bi is List) receiptApiItems = bi;
      }
      if (receiptApiItems.isEmpty) return;

      for (var i = 0;
          i < orderItemsSnapshot.length && i < receiptApiItems.length;
          i++) {
        final apiItem = receiptApiItems[i];
        if (apiItem is! Map) continue;
        // Prefer explicit `*_name_translations`; fall back to legacy `service_name`/`meal_name` map shape.
        Map<dynamic, dynamic>? translationMap;
        final explicit = apiItem['meal_name_translations'] ??
            apiItem['service_name_translations'] ??
            apiItem['name_translations'];
        if (explicit is Map) {
          translationMap = explicit;
        } else if (apiItem['service_name'] is Map) {
          translationMap = apiItem['service_name'] as Map;
        } else if (apiItem['meal_name'] is Map) {
          translationMap = apiItem['meal_name'] as Map;
        }
        if (translationMap == null) continue;
        final existing = orderItemsSnapshot[i]['localizedNames'];
        final merged = <String, String>{};
        if (existing is Map) {
          for (final e in existing.entries) {
            merged[e.key.toString()] = e.value?.toString() ?? '';
          }
        }
        for (final e in translationMap.entries) {
          final val = e.value?.toString().trim() ?? '';
          if (val.isNotEmpty) merged[e.key.toString()] = val;
        }
        orderItemsSnapshot[i] = <String, Object>{
          ...orderItemsSnapshot[i],
          'localizedNames': merged,
        };
      }
    } catch (e) {
      Log.w('pay', 'order-items translation enrichment failed', error: e);
    }
  }

  /// Release the table this payment was placed on, mirroring the
  /// reservation state back to the waiter mesh and clearing the local
  /// `_selectedTable` selection if it still matches. Resolves the table
  /// from the booking payload when [selectedTableForOrder] is null —
  /// e.g. when the cashier paid for a deferred booking whose table is
  /// no longer the current selection. Fire-and-forget on the caller side.
  Future<void> _releaseTableAfterPayment({
    required String orderId,
    required TableItem? selectedTableForOrder,
    required Map<String, dynamic>? bookingDataMap,
    required Map<String, dynamic>? bookingNode,
  }) async {
    TableItem? tableToRelease = selectedTableForOrder;
    if (tableToRelease == null) {
      final bookingTableMap = pph.asStringKeyMap(bookingDataMap?['table']);
      final bookingTableId = pph.firstNonEmptyText(
        [
          bookingNode?['table_id'],
          bookingDataMap?['table_id'],
          bookingTableMap?['id'],
        ],
        allowZero: false,
      );
      if (bookingTableId != null && bookingTableId.isNotEmpty) {
        try {
          tableToRelease = await _tableService.getTableDetails(bookingTableId);
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
            Log.d('pay',
                'ℹ️ Resolved table for release from booking payload table_id=$bookingTableId');
          }
        } catch (e) {
          Log.w('pay',
              '⚠️ Could not resolve table for release booking=$orderId table_id=$bookingTableId error=$e');
        }
      }
    }
    if (tableToRelease == null) return;

    final tableToReleaseCapture = tableToRelease;
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
  }

  // Prefers in-memory branch/seller cache; falls back to parallel AR+EN invoice fetches merged so the printer can render either language.
  Future<Map<String, dynamic>?> _resolveInvoicePayloadForPreview(
    String? invoiceId,
    Map<String, dynamic>? fallbackPayload, {
    required OrderService orderService,
  }) async {
    if (invoiceId == null || invoiceId.trim().isEmpty) {
      return fallbackPayload;
    }

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

    debugPrint(
        '⏱️ [PRINT_TIMER] SLOW PATH — cache miss (branchMap=${_cachedBranchMap != null}, sellerInfo=${_cachedSellerInfo != null}), calling API...');
    try {
      final savedLang = ApiConstants.acceptLanguage;

      // Parallel AR+EN fetches save ~2s on cold path.
      final arFuture = orderService
          .getInvoice(invoiceId)
          .timeout(const Duration(seconds: 3));
      final enFuture = () async {
        try {
          ApiConstants.setAcceptLanguage('en');
          final resp = await orderService
              .getInvoice(invoiceId)
              .timeout(const Duration(seconds: 3));
          return resp;
        } catch (e) {
          Log.d('catch', 'non-fatal: $e');
          return null;
        } finally {
          ApiConstants.setAcceptLanguage(savedLang);
        }
      }();

      final results = await Future.wait([arFuture, enFuture]);
      final detailsResponse = results[0];
      final enResponse = results[1];

      final detailsMap = pph.asStringKeyMap(detailsResponse);
      final detailsData = pph.asStringKeyMap(detailsMap?['data']);
      final arPayload = (detailsData != null && detailsData.isNotEmpty)
          ? detailsData
          : (detailsMap != null && detailsMap.isNotEmpty ? detailsMap : null);

      if (arPayload != null && enResponse != null) {
        try {
          final enMap = pph.asStringKeyMap(enResponse);
          final enData = pph.asStringKeyMap(enMap?['data']) ?? enMap;

          if (enData != null) {
            final enBranch = pph.asStringKeyMap(enData['branch']);
            final enInvoice = pph.asStringKeyMap(enData['invoice']) ?? enData;
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
        } catch (e) {
          Log.d('MainScreenPaymentProcess',
              'merge EN item names into AR invoice preview failed (non-fatal): $e');
        }
      }
      if (arPayload != null) return arPayload;
    } catch (e) {
      debugPrint(
        '⚠️ Could not load invoice details for preview (invoice_id=$invoiceId): $e',
      );
    }
    return fallbackPayload;
  }

  // Receipt-bound snapshot of the cart; must preserve original cart order.
  List<Map<String, Object>> _buildOrderItemsSnapshot(
    List<CartItem> cartItemsForOrder,
  ) {
    return cartItemsForOrder.map<Map<String, Object>>((item) {
      final categoryName = item.product.category.trim();
      final categoryId = (item.product.categoryId?.trim().isNotEmpty == true)
          ? item.product.categoryId!.trim()
          : _resolveCategoryIdByName(categoryName);
      String arName = item.product.nameAr;
      String enName = item.product.nameEn;
      final fallbackName = item.product.name;

      if (enName.trim().isEmpty && fallbackName.contains(' - ')) {
        arName = fallbackName.split(' - ').first.trim();
        enName = fallbackName.split(' - ').last.trim();
      } else if (arName.trim().isEmpty) {
        arName = fallbackName;
      }
      if (arName.trim().isEmpty) {
        arName = fallbackName;
      }

      // Per-line discount snapshot. `CartItem.totalPrice` already applies
      // the discount (or zeros the line when `isFree`); we capture the
      // pre-discount baseline + the absolute discount amount here so the
      // receipt renderer can show "Original 100 / Discount -25 / FREE".
      final extrasPrice =
          item.selectedExtras.fold<double>(0.0, (sum, e) => sum + e.price);
      final originalUnitPrice = item.product.price + extrasPrice;
      final qty = item.quantity > 0 ? item.quantity : 0.0;
      final originalTotal = originalUnitPrice * qty;
      final lineTotal = item.totalPrice;
      final discountAbs =
          (originalTotal - lineTotal).clamp(0.0, originalTotal).toDouble();
      final discountPctValue =
          item.discountType == DiscountType.percentage && item.discount > 0
              ? item.discount.clamp(0.0, 100.0).toDouble()
              : 0.0;
      final isFree = item.isFree || (originalTotal > 0 && lineTotal <= 0.001);

      return <String, Object>{
        'name': fallbackName,
        'nameAr': arName,
        'nameEn': enName,
        'localizedNames': item.product.localizedNames,
        'category_name': categoryName,
        if (categoryId != null && categoryId.isNotEmpty)
          'category_id': categoryId,
        'quantity': item.quantity,
        'unitPrice': item.product.price,
        'total': lineTotal,
        'notes': item.notes,
        // Discount payload — consumed by ReceiptBuilderService when it
        // constructs ReceiptItem so the printed receipt + WhatsApp PDF
        // can show "Discount 25%" / "FREE" lines on each item.
        'original_unit_price': originalUnitPrice,
        'original_total': originalTotal,
        'discount_amount': discountAbs,
        'discount_percentage': discountPctValue,
        'discount_type':
            item.discountType == DiscountType.percentage ? 'percentage' : 'amount',
        'is_free': isFree,
        // Per-extra translations let the kitchen ticket print addons in invoice language when `addons_translations` is missing.
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
    }).toList();
  }

  // KDS dispatch payload — KDS schema is independent of the receipt schema.
  List<Map<String, dynamic>> _buildKdsItemsPayload(
    List<CartItem> cartItemsForOrder,
  ) {
    return cartItemsForOrder.map((item) {
      final categoryName = item.product.category.trim();
      final categoryId = (item.product.categoryId?.trim().isNotEmpty == true)
          ? item.product.categoryId!.trim()
          : _resolveCategoryIdByName(categoryName);
      final basePrice = item.product.price;
      final extrasPrice =
          item.selectedExtras.fold<double>(0.0, (sum, e) => sum + e.price);
      final originalUnitPrice = basePrice + extrasPrice;
      final originalTotal = originalUnitPrice * item.quantity;

      return <String, dynamic>{
        'cartId': item.cartId,
        'meal_id': item.product.id,
        'productId': item.product.id,
        'name': item.product.name,
        'category_name': categoryName,
        if (categoryId != null) 'category_id': categoryId,
        'quantity': item.quantity,
        'extras': item.selectedExtras.map((e) => {'name': e.name}).toList(),
        'notes': item.notes,
        'original_unit_price': originalUnitPrice,
        'original_total': originalTotal,
        'final_total': item.totalPrice,
        'discount': item.discount,
        'discount_type': item.discountType == DiscountType.percentage
            ? 'percentage'
            : 'amount',
        'is_free': item.isFree,
      };
    }).toList();
  }
}
