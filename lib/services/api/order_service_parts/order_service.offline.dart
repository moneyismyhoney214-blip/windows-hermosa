// ignore_for_file: unused_element, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../order_service.dart';

extension OrderServiceOffline on OrderService {

  // ═══════════════════════════════════════════════════════════════════
  //  OFFLINE HELPERS
  // ═══════════════════════════════════════════════════════════════════

  /// Create a booking offline - save to local DB and sync queue,
  /// and also save in POS sync format for POST /sync/pos upload.
  Future<Map<String, dynamic>> _createBookingOffline(
      Map<String, dynamic> bookingData,
      {String paymentType = 'payment'}) async {
    final localId = await _offlineDb.saveLocalOrder(
        bookingData, ApiConstants.branchId,
        paymentType: paymentType);

    // Add to sync queue
    await _offlineDb.addToSyncQueue(
      operation: 'CREATE_BOOKING',
      endpoint: ApiConstants.bookingsEndpoint,
      method: 'POST',
      payload: bookingData,
      localRefTable: 'orders',
      localRefId: localId,
    );

    // Also save as a pending POS sale for /sync/pos upload
    try {
      final saleUuid = _uuid.v4();
      final posProducts = _convertBookingToPosSaleProducts(bookingData);
      final posPayments = _convertBookingToPosSalePayments(bookingData);
      final total = _parseFlexibleDouble(
          bookingData['total'] ?? bookingData['final_total'] ?? 0);

      await _posDb.savePendingSale(
        uuid: saleUuid,
        locationId: ApiConstants.branchId,
        contactId: int.tryParse(
            (bookingData['customer_id'] ?? '1').toString()),
        products: posProducts,
        payments: posPayments,
        finalTotal: total,
        rawPayload: _buildSyncPosPayloadFromBooking(bookingData),
      );
    } catch (e) {
      print('⚠️ Failed to save POS sale (non-fatal): $e');
    }

    return _rememberResponse('create_booking_offline', {
      'status': 200,
      'message': 'تم حفظ الطلب محلياً — سيتم المزامنة عند عودة الاتصال',
      'data': {
        'id': localId,
        'booking_number': localId,
        '_is_local': true,
        '_is_synced': false,
        ...bookingData,
      },
    });
  }

  /// Convert booking card/meals items into POST /sync/pos products format.
  List<Map<String, dynamic>> _convertBookingToPosSaleProducts(
      Map<String, dynamic> bookingData) {
    final items = bookingData['card'] ??
        bookingData['meals'] ??
        bookingData['items'] ??
        [];
    if (items is! List) return [];

    final products = <Map<String, dynamic>>[];
    for (final item in items) {
      if (item is! Map) continue;
      final m = item.map((k, v) => MapEntry(k.toString(), v));
      final price = _parseFlexibleDouble(
          m['price'] ?? m['unitPrice'] ?? m['unit_price'] ?? 0);
      final quantity = _parseFlexibleDouble(m['quantity'] ?? 1);
      final tax = _parseFlexibleDouble(m['tax'] ?? m['item_tax'] ?? 0);

      products.add({
        'product_type': 'single',
        'unit_price': price,
        'line_discount_type': 'fixed',
        'line_discount_amount': 0,
        'item_tax': tax,
        'tax_id': m['tax_id'] ?? 1,
        'sell_line_note': m['notes'] ?? '',
        'product_id': m['meal_id'] ?? m['product_id'] ?? m['id'],
        'variation_id': m['variation_id'] ?? m['meal_id'] ?? m['product_id'] ?? m['id'],
        'enable_stock': m['enable_stock'] ?? 0,
        'quantity': quantity,
        'product_unit_id': m['product_unit_id'] ?? 1,
        'sub_unit_id': m['sub_unit_id'] ?? 1,
        'base_unit_multiplier': 1,
        'unit_price_inc_tax': price + tax,
      });
    }
    return products;
  }

  /// Convert booking pays into POST /sync/pos payment format.
  List<Map<String, dynamic>> _convertBookingToPosSalePayments(
      Map<String, dynamic> bookingData) {
    final pays = bookingData['pays'] ?? bookingData['payment'] ?? [];
    if (pays is! List || pays.isEmpty) {
      // Default: single cash payment for the full total
      final total = _parseFlexibleDouble(
          bookingData['total'] ?? bookingData['final_total'] ?? 0);
      return [
        {
          'amount': total,
          'method': 'cash',
          'card_number': '',
          'card_holder_name': '',
          'card_transaction_number': '',
          'card_type': 'credit',
          'card_month': '',
          'card_year': '',
          'card_security': '',
          'cheque_number': '',
          'bank_account_number': '',
          'note': '',
        }
      ];
    }

    return pays.map<Map<String, dynamic>>((p) {
      if (p is! Map) return {'amount': 0, 'method': 'cash'};
      final m = p.map((k, v) => MapEntry(k.toString(), v));
      return {
        'amount': _parseFlexibleDouble(m['amount'] ?? m['pay'] ?? 0),
        'method': m['method'] ?? m['pay_method'] ?? 'cash',
        'card_number': m['card_number'] ?? '',
        'card_holder_name': m['card_holder_name'] ?? '',
        'card_transaction_number': m['card_transaction_number'] ?? '',
        'card_type': m['card_type'] ?? 'credit',
        'card_month': m['card_month'] ?? '',
        'card_year': m['card_year'] ?? '',
        'card_security': m['card_security'] ?? '',
        'cheque_number': m['cheque_number'] ?? '',
        'bank_account_number': m['bank_account_number'] ?? '',
        'note': m['note'] ?? '',
      };
    }).toList();
  }

  /// Build the full POST /sync/pos payload from booking data.
  Map<String, dynamic> _buildSyncPosPayloadFromBooking(
      Map<String, dynamic> bookingData) {
    final products = _convertBookingToPosSaleProducts(bookingData);
    final payments = _convertBookingToPosSalePayments(bookingData);
    final total = _parseFlexibleDouble(
        bookingData['total'] ?? bookingData['final_total'] ?? 0);
    final discount = _parseFlexibleDouble(bookingData['discount'] ?? 0);
    final discountType =
        (bookingData['discount_type'] ?? 'percentage').toString();

    // Convert products list to indexed map
    final productsMap = <String, dynamic>{};
    for (var i = 0; i < products.length; i++) {
      productsMap['${i + 1}'] = products[i];
    }

    return {
      'location_id': ApiConstants.branchId,
      'contact_id': bookingData['customer_id'] ?? 1,
      'sub_type': '',
      'search_product': '',
      'pay_term_number': '',
      'pay_term_type': '',
      'price_group': 0,
      'sell_price_tax': 'includes',
      'products': productsMap,
      'discount_type': discountType,
      'discount_amount': discount,
      'rp_redeemed': 0,
      'rp_redeemed_amount': 0,
      'tax_rate_id': null,
      'tax_calculation_amount': 0,
      'shipping_details': '',
      'shipping_address': '',
      'shipping_status': '',
      'delivered_to': '',
      'delivery_person': '',
      'shipping_charges': 0,
      'advance_balance': 0,
      'payment': payments,
      'payment_change_return': {
        'method': 'cash',
        'card_number': '',
        'card_holder_name': '',
        'card_transaction_number': '',
        'card_type': 'credit',
        'card_month': '',
        'card_year': '',
        'card_security': '',
        'cheque_number': '',
        'bank_account_number': '',
      },
      'sale_note': bookingData['notes'] ?? '',
      'staff_note': '',
      'change_return': 0,
      'additional_notes': '',
      'is_suspend': 0,
      'is_credit_sale': 0,
      'final_total': total,
      'discount_type_modal': discountType,
      'discount_amount_modal': discount,
      'status': 'final',
    };
  }

  /// Get bookings from local database
  Future<Map<String, dynamic>> _getBookingsOffline() async {
    try {
      final localOrders =
          await _offlineDb.getOrders(ApiConstants.branchId);
      return {
        'status': 200,
        'data': localOrders,
        '_offline': true,
      };
    } catch (e) {
      return {
        'status': 200,
        'data': [],
        '_offline': true,
      };
    }
  }
}
