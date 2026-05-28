// Receipt / KDS payload builders — split from main_screen.payment.dart for size.
// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, library_private_types_in_public_api
part of '../main_screen.dart';

extension MainScreenPaymentReceipt on _MainScreenState {
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
    // Receipt construction lives in a shared service so the waiter
    // module (lib/waiter_module/services/waiter_print_dispatcher.dart)
    // uses the exact same logic. Any tweak to the printed receipt
    // header/items/totals goes there — don't reintroduce a local copy
    // here or the two entry points will drift again.
    final cache = ReceiptBuilderCache()
      ..sellerInfo = _cachedSellerInfo
      ..branchMap = _cachedBranchMap
      ..sellerNameEn = _cachedSellerNameEn
      ..branchAddressEn = _cachedBranchAddressEn;

    final result = ReceiptBuilderService.build(
      orderId: orderId,
      invoiceNumber: invoiceNumber,
      orderItems: orderItems,
      orderTotal: orderTotal,
      orderType: orderType,
      type: type,
      pays: pays,
      invoicePayload: invoicePayload,
      carNumber: carNumber,
      tableNumber: tableNumber,
      discountAmount: discountAmount,
      discountPercentage: discountPercentage,
      discountName: discountName,
      isTaxEnabled: _isTaxEnabled,
      taxRate: _taxRate,
      userNameFallback: _userName,
      cache: cache,
      // Same offline-resilient fallbacks the waiter dispatcher uses
      // (waiter_print_dispatcher.dart:_buildReceiptData). The cashier
      // used to skip these, which is why its receipt rendered shorter
      // than the waiter's: when the invoice payload didn't nest seller
      // info (logo URL, English name, branch address, phone, CR), there
      // was no second source to fall back to. Pulling them in here aligns
      // the cashier's printed/preview receipt with the waiter's.
      authUser: getIt<AuthService>().getUser(),
      branchReceiptCache: getIt<BranchService>().cachedBranchReceiptInfo,
      activeMenuListName: _activeMenuListName,
      menuListPriceType: _menuListPriceType,
      isMenuListActive: _isMenuListActive,
      // Salon catalog prices already include VAT, so the receipt builder
      // must NOT gross up the line items again. _grossOrderTotal in
      // main_screen.cart.dart treats salon cart sums as already-with-tax;
      // mirror that contract here so the printed line matches the
      // totals block (e.g. 359 invoice -> 359 line, not 395).
      itemsAlreadyTaxInclusive: _isSalonMode,
    );

    // The service mirrors any fresh seller/branch info it pulled out
    // of `invoicePayload` into [cache]; copy it back onto the state
    // so the next successive print keeps the fallback chain warm.
    _cachedSellerInfo = cache.sellerInfo;
    _cachedBranchMap = cache.branchMap;
    _cachedSellerNameEn = cache.sellerNameEn;
    _cachedBranchAddressEn = cache.branchAddressEn;

    return result;
  }

  String _payMethodArabicLabel(String method) => ReceiptBuilderService.payMethodArabicLabel(method);

  String _buildPaymentMethodLabel({
    required String type,
    required List<Map<String, dynamic>> pays,
  }) => ReceiptBuilderService.buildPaymentMethodLabel(type: type, pays: pays);

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
