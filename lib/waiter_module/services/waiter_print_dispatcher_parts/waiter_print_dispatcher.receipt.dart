// Cashier-receipt internals — split from waiter_print_dispatcher.dart for size.
part of '../waiter_print_dispatcher.dart';

extension WaiterPrintDispatcherReceipt on WaiterPrintDispatcher {

  // ---------------------------------------------------------------------------
  // Cashier receipt (pay-now)
  // ---------------------------------------------------------------------------

  /// Builds [OrderReceiptData] for the waiter's pay-now print + preview.
  /// Single source of truth for both paths: parallel bilingual fetch
  /// (matches the cashier's `resolveInvoicePayloadForPreview` in
  /// `main_screen.payment.dart:1020-1107`), warms the branch cache, then
  /// delegates to the shared [ReceiptBuilderService]. The on-screen preview
  /// and the printed paper therefore stay byte-identical.
  Future<OrderReceiptData> buildCashierReceiptData({
    required String? invoiceId,
    String? invoiceNumber,
    String? dailyOrderNumber,
    required List<CartItem> items,
    required double totalInclVat,
    required double vatRate,
    required String tableNumber,
    required String waiterName,
    required List<Map<String, dynamic>> pays,
  }) async {
    final invoicePayload = (invoiceId != null && invoiceId.isNotEmpty)
        ? await _fetchBilingualInvoicePayload(invoiceId)
        : null;
    await _warmBranchReceiptCache();
    return _buildReceiptData(
      invoicePayload: invoicePayload,
      // Only fall back to the invoice_number passed by the caller;
      // NEVER fall back to the invoice_id (= booking id). The receipt
      // template renders `invoiceNumber` in the "رقم الفاتورة: IN-xxx"
      // header, so substituting a booking id like "63" there made the
      // printed invoice look like an order id. Empty is better than
      // wrong — the downstream renderer handles a missing invoice
      // number gracefully by omitting the line.
      fallbackInvoiceNumber: invoiceNumber ?? '',
      dailyOrderNumber: dailyOrderNumber,
      items: items,
      totalInclVat: totalInclVat,
      vatRate: vatRate,
      tableNumber: tableNumber,
      waiterName: waiterName,
      pays: pays,
    );
  }

  /// Prints prebuilt [OrderReceiptData] to the cashier-role printers.
  /// Use when the caller already built the data (e.g. for a preview
  /// dialog) so we don't refetch the invoice. Honors `autoPrintCashier`
  /// + `autoPrintCustomerSecondCopy` toggles; returns `true` if at least
  /// one physical print landed.
  Future<bool> printPrebuiltCashierReceipt(OrderReceiptData receiptData) async {
    try {
      return await _printPrebuiltCashierReceiptInternal(receiptData);
    } catch (e) {
      debugPrint('⚠️ printPrebuiltCashierReceipt aborted: $e');
      return false;
    }
  }

  /// Convenience: build the receipt data + print in one call. Use when
  /// no preview is needed; otherwise prefer
  /// [buildCashierReceiptData] + [printPrebuiltCashierReceipt] so the
  /// invoice fetch happens exactly once.
  Future<bool> printCashierReceipt({
    required String invoiceId,
    String? invoiceNumber,
    String? dailyOrderNumber,
    required List<CartItem> items,
    required double totalInclVat,
    required double vatRate,
    required String tableNumber,
    required String waiterName,
    required List<Map<String, dynamic>> pays,
  }) async {
    try {
      // Cheap pref check first so we don't pay the bilingual fetch cost
      // when auto-print is off.
      final autoPrint = await _readBool(
        WaiterDevicePrefKeys.autoPrintCashier,
        fallback: true,
      );
      if (!autoPrint) return false;
      final receiptData = await buildCashierReceiptData(
        invoiceId: invoiceId,
        invoiceNumber: invoiceNumber,
        dailyOrderNumber: dailyOrderNumber,
        items: items,
        totalInclVat: totalInclVat,
        vatRate: vatRate,
        tableNumber: tableNumber,
        waiterName: waiterName,
        pays: pays,
      );
      return await _printPrebuiltCashierReceiptInternal(receiptData);
    } catch (e) {
      debugPrint('⚠️ printCashierReceipt aborted: $e');
      return false;
    }
  }

  Future<bool> _printPrebuiltCashierReceiptInternal(
    OrderReceiptData receiptData,
  ) async {
    final autoPrint = await _readBool(
      WaiterDevicePrefKeys.autoPrintCashier,
      fallback: true,
    );
    if (!autoPrint) return false;

    final printers = await _loadPrinters();
    if (printers.isEmpty) return false;
    final cashierPrinters = await _cashierRolePrinters(printers);
    if (cashierPrinters.isEmpty) return false;

    final secondCopy = await _readBool(
      WaiterDevicePrefKeys.autoPrintCustomerSecondCopy,
      fallback: false,
    );
    final totalCopies = secondCopy ? 2 : 1;

    var anyPrinted = false;
    // No language overrides — let print_listener resolve from
    // printerLanguageSettings (primary, secondary, allow_secondary). Same
    // contract the cashier's _autoPrintReceiptCopies uses, so toggling
    // bilingual / monolingual in the printer settings affects both paths
    // identically.
    for (var copy = 0; copy < totalCopies; copy++) {
      for (final printer in cashierPrinters) {
        try {
          await _printerService
              .printReceipt(
                printer,
                receiptData,
                jobType: copy == 0 ? 'cashier' : 'cashier_copy_${copy + 1}',
              )
              .timeout(const Duration(seconds: 12));
          anyPrinted = true;
        } catch (e) {
          // A broken printer shouldn't fail the pay-now flow, but a
          // silent swallow makes "nothing printed" impossible to debug.
          debugPrint('⚠️ cashier receipt print to ${printer.name} failed: $e');
        }
      }
      if (copy + 1 < totalCopies) {
        // Thermal printers sometimes merge back-to-back jobs; gap
        // between copies lets the cutter reset. Same 400ms the cashier
        // uses in _autoPrintReceiptCopies.
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    return anyPrinted;
  }

  /// Fetches the canonical invoice payload in the user's current locale
  /// AND in English in parallel, then merges en fields (`branch_address_en`,
  /// `branch_district_en`, `seller_name_en`, per-item `item_name_en`) into
  /// the primary payload. The merge lets the receipt builder render a
  /// bilingual receipt with proper English item names without making the
  /// caller wait for two sequential round-trips.
  ///
  /// Mirrors `main_screen.payment.dart:1020-1107` byte-for-byte so the
  /// waiter's printed receipt matches the cashier's when both are running
  /// against the same invoice.
  ///
  /// The backend wraps everything under `data` — `{status, message, data:
  /// {invoice, branch, qr_image, ...}, ...}` — so the unwrap-`data`-first
  /// rule applies before returning to the receipt builder. Returns null
  /// (not an envelope) when both fetches fail.
  Future<Map<String, dynamic>?> _fetchBilingualInvoicePayload(
    String invoiceId,
  ) async {
    final savedLang = ApiConstants.acceptLanguage;

    // NOTE: these two fetches MUST run sequentially. `OrderService.getInvoice`
    // builds its `Accept-Language` header from the global `ApiConstants`
    // *when its async chain actually executes* — not when the Future is
    // created. Kicking both off "in parallel" and then flipping the global
    // to 'en' makes BOTH requests go out in English, so the primary-locale
    // payload comes back English too and the merge is a no-op (the waiter's
    // receipt then prints in English on every non-English device).
    Map<String, dynamic>? arResp;
    try {
      final r = await _orderService
          .getInvoice(invoiceId)
          .timeout(const Duration(seconds: 3));
      arResp = _asMap(r) ?? r;
    } catch (e) {
      debugPrint('⚠️ waiter getInvoice($invoiceId) [primary locale] failed: $e');
      return null;
    }

    Map<String, dynamic>? enResp;
    if (savedLang.toLowerCase() != 'en') {
      try {
        ApiConstants.setAcceptLanguage('en');
        final r = await _orderService
            .getInvoice(invoiceId)
            .timeout(const Duration(seconds: 3));
        enResp = _asMap(r) ?? r;
      } catch (e) {
        debugPrint('⚠️ waiter getInvoice($invoiceId) [en] failed (non-fatal): $e');
        enResp = null;
      } finally {
        ApiConstants.setAcceptLanguage(savedLang);
      }
    }

    // Work on a defensive copy: `getInvoice` also stashes its response in
    // OrderService's last-response cache (a *shallow* copy — nested maps and
    // lists are shared), so mutating the payload in place would pollute the
    // cache for subsequent readers.
    final arData = _asMap(arResp['data']) ?? arResp;
    final arPayload = Map<String, dynamic>.from(arData);

    if (enResp != null) {
      try {
        final enData = _asMap(enResp['data']) ?? enResp;
        final enBranch = _asMap(enData['branch']);
        final enInvoice = _asMap(enData['invoice']) ?? enData;
        arPayload['branch_address_en'] = enBranch?['address'];
        arPayload['branch_district_en'] = enBranch?['district'];
        arPayload['seller_name_en'] = enBranch?['seller_name'];

        final enItems = enInvoice['items'];
        // Locate the AR items list, cloning the container(s) on the way so
        // the `item_name_en` writes below don't touch the shared cache copy.
        List? srcItems;
        void Function(List)? writeBack;
        final invMap = _asMap(arPayload['invoice']);
        if (invMap != null && invMap['items'] is List) {
          final inv = Map<String, dynamic>.from(invMap);
          srcItems = inv['items'] as List;
          arPayload['invoice'] = inv;
          writeBack = (list) => inv['items'] = list;
        } else if (arPayload['items'] is List) {
          srcItems = arPayload['items'] as List;
          writeBack = (list) => arPayload['items'] = list;
        }
        if (srcItems != null && writeBack != null && enItems is List) {
          final cloned = <dynamic>[];
          for (var i = 0; i < srcItems.length; i++) {
            final src = srcItems[i];
            if (src is Map) {
              final m = Map<String, dynamic>.from(src);
              if (i < enItems.length && enItems[i] is Map) {
                m['item_name_en'] = (enItems[i] as Map)['item_name'];
              }
              cloned.add(m);
            } else {
              cloned.add(src);
            }
          }
          writeBack(cloned);
        }
      } catch (e) {
        debugPrint('⚠️ waiter bilingual merge failed (non-fatal): $e');
      }
    }

    return arPayload;
  }

  /// Ensures the BranchService branch/seller/logo cache is populated —
  /// the cashier prewarms this at session start; the waiter has to do it
  /// on demand. Without it (and if `getInvoice` returned a payload that
  /// doesn't nest branch.seller), the printed header loses the logo, tax
  /// number, and commercial register. The print runs even if warm-up
  /// throws; the cache miss just means the receipt may render shorter
  /// for this one print.
  Future<void> _warmBranchReceiptCache() async {
    if (_branchService.cachedBranchReceiptInfo != null) return;
    try {
      await _branchService
          .fetchAndCacheBranchReceiptInfo()
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('⚠️ waiter branch receipt cache warm-up failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Receipt data adapter — delegates to ReceiptBuilderService
  // ---------------------------------------------------------------------------
  //
  // The waiter reuses the exact same receipt-building logic the cashier
  // runs (lib/services/receipt_builder_service.dart). This adapter only
  // does two waiter-specific things:
  //   1. Convert the in-memory CartItem list into the Map<String, dynamic>
  //      shape the service was originally written for (name/nameAr/nameEn/
  //      localizedNames/quantity/unitPrice/total/extras-with-translations).
  //   2. Pass in the offline fallback sources the waiter has access to —
  //      the auth-profile (for tax/logo on first-print before getInvoice)
  //      and BranchService.cachedBranchReceiptInfo (uploaded logo URL).
  //
  // No receipt field is resolved here; every picker lives in the service.
  OrderReceiptData _buildReceiptData({
    required Map<String, dynamic>? invoicePayload,
    required String fallbackInvoiceNumber,
    String? dailyOrderNumber,
    required List<CartItem> items,
    required double totalInclVat,
    required double vatRate,
    required String tableNumber,
    required String waiterName,
    required List<Map<String, dynamic>> pays,
  }) {
    // CartItem → Map adapter. The service expects the cashier-style
    // order-item shape (see main_screen.payment._buildOrderReceiptData).
    final orderItems = items.map((it) {
      final nameAr = it.product.nameAr.isNotEmpty
          ? it.product.nameAr
          : it.product.name;
      final nameEn = it.product.nameEn.isNotEmpty
          ? it.product.nameEn
          : it.product.name;
      final extras = it.selectedExtras.map((e) {
        final entry = <String, dynamic>{
          'id': e.id,
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
      }).toList(growable: false);
      // Per-line discount snapshot — same keys the cashier's
      // _buildOrderItemsSnapshot emits so ReceiptBuilderService can
      // populate ReceiptItem with original/discount/free metadata. Without
      // this, waiter receipts would print every discounted line at full
      // price even though the totals block subtracts the discount.
      final extrasSum = it.selectedExtras
          .fold<double>(0.0, (sum, e) => sum + e.price);
      final originalUnitPrice = it.product.price + extrasSum;
      final qty = it.quantity > 0 ? it.quantity : 0.0;
      final originalTotal = originalUnitPrice * qty;
      final lineTotal = it.totalPrice;
      final discountAbs =
          (originalTotal - lineTotal).clamp(0.0, originalTotal).toDouble();
      final discountPctValue =
          it.discountType == DiscountType.percentage && it.discount > 0
              ? it.discount.clamp(0.0, 100.0).toDouble()
              : 0.0;
      final isFree = it.isFree || (originalTotal > 0 && lineTotal <= 0.001);

      return <String, dynamic>{
        'name': nameAr.isNotEmpty ? nameAr : nameEn,
        'nameAr': nameAr,
        'nameEn': nameEn,
        if (it.product.localizedNames.isNotEmpty)
          'localizedNames': it.product.localizedNames,
        'quantity': it.quantity,
        'unitPrice': it.product.price,
        'total': lineTotal,
        'original_unit_price': originalUnitPrice,
        'original_total': originalTotal,
        'discount_amount': discountAbs,
        'discount_percentage': discountPctValue,
        'discount_type': it.discountType == DiscountType.percentage
            ? 'percentage'
            : 'amount',
        'is_free': isFree,
        // Per-item note (e.g. "بدون ثوم"). Cashier passes this through
        // at main_screen.payment.dart:1043 — omitting it dropped the
        // waiter's printed receipt below the cashier's whenever the
        // order had any item-level instructions.
        if (it.notes.trim().isNotEmpty) 'notes': it.notes.trim(),
        if (extras.isNotEmpty) 'extras': extras,
        if (it.product.categoryId != null)
          'category_id': it.product.categoryId,
      };
    }).toList(growable: false);

    // Unwrap the API envelope (backend wraps everything under
    // `data`) to match what the cashier passes to the service —
    // the cashier does the same unwrap at main_screen.payment:2573.
    final effectivePayload = invoicePayload == null
        ? null
        : (_asMap(invoicePayload['data']) ?? invoicePayload);

    return ReceiptBuilderService.build(
      orderId: fallbackInvoiceNumber,
      invoiceNumber: fallbackInvoiceNumber.isEmpty ? null : fallbackInvoiceNumber,
      orderItems: orderItems,
      orderTotal: totalInclVat,
      // Dine-in is the only waiter context; the service will prefer
      // whatever the invoice payload tells it over this seed value.
      orderType: 'restaurant_internal',
      // pay-now only — pay-later never reaches printCashierReceipt.
      type: 'payment',
      pays: pays,
      invoicePayload: effectivePayload,
      tableNumber: tableNumber,
      dailyOrderNumber: dailyOrderNumber,
      isTaxEnabled: vatRate > 0,
      taxRate: vatRate,
      userNameFallback: waiterName.isEmpty ? null : waiterName,
      // Session-scoped cache — same role the cashier's
      // `_cachedSellerInfo / _cachedBranchMap / ...` plays. The service
      // will read it as a fallback when the current invoice payload
      // doesn't nest seller info AND will write fresh values into it
      // on each call, so the next print on the same session keeps the
      // header complete (logo, tax number, commercial register).
      cache: _receiptCache,
      // Always pass the offline-resilient fallbacks (auth profile +
      // BranchService cache). The cashier path now does the same in
      // main_screen.payment._buildOrderReceiptData, so both entry points
      // resolve seller logo, English name, branch address, phone, and
      // commercial register from an identical pool of sources — the
      // printed ticket is byte-for-byte the same on either side.
      authUser: _authService.getUser(),
      branchReceiptCache: _branchService.cachedBranchReceiptInfo,
    );
  }

  Map<String, dynamic>? _asMap(Object? v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return null;
  }
}
