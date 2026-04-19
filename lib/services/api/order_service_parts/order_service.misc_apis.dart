// ignore_for_file: unused_element, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../order_service.dart';

extension OrderServiceMiscApis on OrderService {
  /// Send invoice on WhatsApp directly.
  Future<Map<String, dynamic>> sendInvoiceWhatsApp({
    required String invoiceId,
    int? branchId,
    String? message,
  }) async {
    final payload = <String, dynamic>{
      'invoice_id': int.tryParse(invoiceId) ?? invoiceId,
      'branch_id': branchId ?? ApiConstants.branchId,
    };
    final normalizedMessage = message?.trim();
    if (normalizedMessage != null && normalizedMessage.isNotEmpty) {
      payload['message'] = normalizedMessage;
    }

    final response = await _client.post(
      ApiConstants.sendInvoiceWhatsAppEndpoint,
      payload,
    );
    return _rememberResponse('send_invoice_whatsapp', response);
  }

  /// Get refunds statistics
  Future<Map<String, dynamic>> getRefundStatistics() async {
    final response = await _client.get(
      '/seller/statistics/branches/${ApiConstants.branchId}/refunds',
    );
    return _rememberResponse('get_refund_statistics', response);
  }

  /// Get payment methods
  Future<Map<String, dynamic>> getPaymentMethods({
    String? type,
    bool withoutDeferred = true,
  }) async {
    final queryParams = <String, String>{};
    if (type != null) queryParams['type'] = type;
    if (withoutDeferred) queryParams['without_deferred'] = 'true';

    final queryString =
        queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');
    final endpoint = queryString.isNotEmpty
        ? '${ApiConstants.payMethodsEndpoint}?$queryString'
        : ApiConstants.payMethodsEndpoint;

    try {
      final response = await _client.get(endpoint);
      return _rememberResponse('get_payment_methods', response);
    } on ApiException catch (e) {
      if (e.statusCode == 422) {
        return _rememberResponse('get_payment_methods', {
          'status': 422,
          'message': 'طرق الدفع غير مُعدّة — تم استخدام الدفع النقدي تلقائيًا',
          'data': [
            {'pay_method': 'cash', 'name': 'دفع نقدي', 'enabled': true},
          ],
        });
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getRefundedMeals({
    String? bookingId,
    String? invoiceId,
  }) async {
    final normalizedBookingId = _digitsOnly(bookingId);
    final normalizedInvoiceId = _digitsOnly(invoiceId);
    if (normalizedBookingId.isEmpty && normalizedInvoiceId.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final response = await _client.get(
      ApiConstants.refundedMealsEndpoint(
        bookingId: normalizedBookingId.isNotEmpty ? normalizedBookingId : null,
        invoiceId: normalizedBookingId.isEmpty && normalizedInvoiceId.isNotEmpty
            ? normalizedInvoiceId
            : null,
      ),
    );
    final normalized = _rememberResponse('get_refunded_meals', response);
    return _extractBookingRowsFromResponse(normalized);
  }

  List<Map<String, dynamic>> mergeRefundedMealsWithItems(
    List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> refundedMeals,
  ) {
    final merged = items
        .map(
            (item) => _normalizeDisplayItemRow(Map<String, dynamic>.from(item)))
        .toList(growable: true);
    final normalizedRefunds = refundedMeals
        .map(
          (item) => _normalizeRefundedMealRow(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);

    if (normalizedRefunds.isEmpty) return merged;

    final signatureIndex = <String, int>{};

    void indexRow(int index, Map<String, dynamic> row) {
      for (final signature in _itemSignatures(row)) {
        signatureIndex.putIfAbsent(signature, () => index);
      }
    }

    for (var i = 0; i < merged.length; i++) {
      indexRow(i, merged[i]);
    }

    for (final refund in normalizedRefunds) {
      int? matchIndex;
      for (final signature in _itemSignatures(refund)) {
        final existingIndex = signatureIndex[signature];
        if (existingIndex != null) {
          matchIndex = existingIndex;
          break;
        }
      }

      if (matchIndex != null) {
        final existing = merged[matchIndex];
        final existingRefunded = existing['is_refunded'] == true ||
            existing['is_cancelled'] == true ||
            existing['status'] == 'refunded' ||
            existing['status'] == 'cancelled';

        if (!existingRefunded) {
          merged.add(_normalizeDisplayItemRow(refund));
          indexRow(merged.length - 1, merged.last);
          continue;
        }

        final existingCopy = Map<String, dynamic>.from(existing);
        final enriched = Map<String, dynamic>.from(existingCopy)..addAll(refund);
        if (enriched['addons'] == null && existingCopy['addons'] != null) {
          enriched['addons'] = existingCopy['addons'];
        }
        if (enriched['add_ons'] == null && existingCopy['add_ons'] != null) {
          enriched['add_ons'] = existingCopy['add_ons'];
        }
        merged[matchIndex] = _normalizeDisplayItemRow(enriched);
        indexRow(matchIndex, merged[matchIndex]);
        continue;
      }

      merged.add(_normalizeDisplayItemRow(refund));
      indexRow(merged.length - 1, merged.last);
    }

    return merged;
  }

  Future<Map<String, dynamic>> updateBookingItems({
    required String orderId,
    required List<Map<String, dynamic>> items,
    String? orderType,
    String? notes,
    String? updatedAt,
    Map<String, dynamic>? typeExtra,
  }) async {
    final normalizedOrderId = _normalizeBookingIdOrThrow(orderId);
    final endpoint =
        '/seller/branches/${ApiConstants.branchId}/bookings/$normalizedOrderId?create_order';

    final fields = <String, String>{
      '_method': 'PATCH',
      'customer_id': '',
    };
    if (orderType != null && orderType.trim().isNotEmpty) {
      fields['type'] = orderType.trim();
    }
    if (notes != null) {
      fields['notes'] = notes;
    }
    if (typeExtra != null) {
      for (final entry in typeExtra.entries) {
        fields['type_extra[${entry.key}]'] = entry.value?.toString() ?? '';
      }
    }

    for (var i = 0; i < items.length; i++) {
      final row = items[i];
      final item = row.map((k, v) => MapEntry(k.toString(), v));

      final mealId = item['meal_id'] ?? item['product_id'] ?? item['item_id'] ?? item['id'];
      final name = item['item_name'] ?? item['meal_name'] ?? item['name'] ?? '';
      final price = item['price'] ?? item['unit_price'] ?? item['unitPrice'] ?? '';
      final unitPrice = item['unitPrice'] ?? item['unit_price'] ?? item['price'] ?? '';
      final quantity = item['quantity'] ?? 1;

      if (name.toString().isNotEmpty) {
        fields['card[$i][item_name]'] = name.toString();
      }
      if (mealId != null) {
        fields['card[$i][meal_id]'] = mealId.toString();
      }
      fields['card[$i][price]'] = price.toString();
      fields['card[$i][unitPrice]'] = unitPrice.toString();
      fields['card[$i][modified_unit_price]'] = (item['modified_unit_price'] ?? '').toString();
      fields['card[$i][quantity]'] = quantity.toString();

      final discount = item['discount'];
      if (discount != null && discount.toString().isNotEmpty) {
        fields['card[$i][discount]'] = discount.toString();
        fields['card[$i][discount_type]'] = (item['discount_type'] ?? '%').toString();
      }
      final note = item['note'] ?? item['notes'];
      if (note != null && note.toString().isNotEmpty) {
        fields['card[$i][note]'] = note.toString();
      }

      final addons = item['addons'];
      if (addons is List) {
        var addonIndex = 0;
        for (final addon in addons) {
          int? numericId;
          if (addon is Map) {
            final normalized = addon.map((k, v) => MapEntry(k.toString(), v));
            final addonId = normalized['addon_id'] ?? normalized['id'];
            numericId = int.tryParse(addonId.toString().trim());
          } else if (addon != null) {
            numericId = int.tryParse(addon.toString().trim());
          }
          if (numericId != null) {
            fields['card[$i][addons][$addonIndex]'] = numericId.toString();
            addonIndex++;
          }
        }
      }
    }

    final response = await _client.postMultipart(endpoint, fields);
    return _rememberResponse('update_booking_items', response);
  }
}
