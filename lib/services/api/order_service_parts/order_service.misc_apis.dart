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

    // `/seller/refunded-meals/...` is the restaurant cashier endpoint —
    // it returns 422 "غير مسموح بهذه العملية!" for salon branches. The
    // equivalent refund history for salon lives in Credit Note records:
    // `GET /seller/branches/{id}/refunds` lists CNs (each a refund
    // invoice) and `GET /seller/branches/{id}/refunds/{cnId}` exposes
    // the per-line `items[]` keyed by the original invoice's
    // `original_invoice_number`. Aggregate matching CNs so the cashier
    // sees the refunded services even though the restaurant endpoint
    // returns 422.
    if (ApiConstants.branchModule == 'salons') {
      return _fetchSalonRefundedItems(
        bookingId: normalizedBookingId,
        invoiceId: normalizedInvoiceId,
      );
    }

    try {
      final response = await _client.get(
        ApiConstants.refundedMealsEndpoint(
          bookingId:
              normalizedBookingId.isNotEmpty ? normalizedBookingId : null,
          invoiceId: normalizedBookingId.isEmpty &&
                  normalizedInvoiceId.isNotEmpty
              ? normalizedInvoiceId
              : null,
        ),
      );
      final normalized = _rememberResponse('get_refunded_meals', response);
      return _extractBookingRowsFromResponse(normalized);
    } on ApiException catch (e) {
      // Defensive: if the backend ever flips the 422 message for a
      // restaurant branch (e.g. permissions), return an empty list rather
      // than letting it propagate as a user-facing error — the dialog can
      // still render the invoice without the refunded-meals overlay.
      if (e.statusCode == 422 &&
          (e.message.contains('غير مسموح') ||
              (e.userMessage ?? '').contains('غير مسموح'))) {
        return const <Map<String, dynamic>>[];
      }
      rethrow;
    }
  }

  /// Salon-only: aggregate refunded service rows by walking the
  /// branch's Credit Note (refund invoice) list and matching against the
  /// target invoice's `original_invoice_number`. The CN detail's
  /// `invoice.items[]` contains one entry per refunded service with
  /// `service_name`, `quantity`, `total`, `total_tax`, `employee_name`
  /// and `booking_number` — enough to render the same "refunds" overlay
  /// the restaurant flow uses.
  Future<List<Map<String, dynamic>>> _fetchSalonRefundedItems({
    required String bookingId,
    required String invoiceId,
  }) async {
    if (invoiceId.isEmpty && bookingId.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    // Build the candidate identifiers we'll match the CN's
    // `original_invoice_number` and `booking_number` against. The backend
    // exposes the invoice's *number* (e.g. "53158" → "#IN-53158") on the
    // CN, NOT the invoice id (e.g. 454238). The caller usually passes
    // the id, so we resolve the number via `getInvoice` once before
    // walking the CN pages — without this, every comparison would miss
    // and the dialog would still report "لا توجد مرتجعات".
    final invoiceTargets = <String>{};
    if (invoiceId.isNotEmpty) {
      invoiceTargets.add(invoiceId);
      invoiceTargets.add('#IN-$invoiceId');
      invoiceTargets.add('IN-$invoiceId');
      try {
        final invoiceDetail = await getInvoice(invoiceId);
        final invData = invoiceDetail['data'];
        final invMap = invData is Map ? invData : invoiceDetail;
        final invInner =
            (invMap['invoice'] is Map ? invMap['invoice'] : invMap) as Map;
        final invNumber = invInner['invoice_number']?.toString().trim() ??
            '';
        if (invNumber.isNotEmpty) {
          // Stored "#IN-53158", "IN-53158" and bare "53158" all match.
          final stripped = invNumber.replaceFirst(RegExp(r'^#?IN-?'), '');
          invoiceTargets
            ..add(invNumber)
            ..add(invNumber.startsWith('#') ? invNumber.substring(1) : '#$invNumber')
            ..add('#IN-$stripped')
            ..add('IN-$stripped')
            ..add(stripped);
        }
      } catch (_) {
        // Tolerate failure — id-only match still works for the rare
        // backend that includes the bare id in `original_invoice_number`.
      }
    }
    final bookingTargets = <String>{};
    if (bookingId.isNotEmpty) {
      bookingTargets.add(bookingId);
      bookingTargets.add('#BOK-$bookingId');
      bookingTargets.add('BOK-$bookingId');
    }

    bool refundReferencesTarget(Map<String, dynamic> refundOrInvoice) {
      final originalInv =
          refundOrInvoice['original_invoice_number']?.toString() ?? '';
      if (invoiceTargets.isNotEmpty) {
        for (final target in invoiceTargets) {
          if (originalInv.endsWith(target) || originalInv == target) {
            return true;
          }
        }
      }
      // Booking-level match: scan items for booking_number reference.
      final items = refundOrInvoice['items'];
      if (bookingTargets.isNotEmpty && items is List) {
        for (final item in items.whereType<Map>()) {
          final bookingNumber = item['booking_number']?.toString() ?? '';
          for (final target in bookingTargets) {
            if (bookingNumber.endsWith(target) || bookingNumber == target) {
              return true;
            }
          }
        }
      }
      return false;
    }

    try {
      // Walk a small number of pages — refund history grows over time but
      // recent refunds for a freshly opened invoice are at the top of
      // page 1. Cap at 3 pages to bound the worst-case latency.
      final aggregated = <Map<String, dynamic>>[];
      for (var page = 1; page <= 3; page++) {
        final listResponse = await _client.get(
          '/seller/branches/${ApiConstants.branchId}/refunds?page=$page&per_page=15',
        );
        final listData =
            listResponse is Map ? listResponse['data'] : listResponse;
        if (listData is! List || listData.isEmpty) break;

        for (final refund in listData) {
          if (refund is! Map) continue;
          final m = refund.map((k, v) => MapEntry(k.toString(), v));
          final refundId = m['id']?.toString() ?? '';
          if (refundId.isEmpty) continue;

          // Fetch the full CN detail — `original_invoice_number` and the
          // refunded items only live there, not on the list rows.
          Map<String, dynamic>? invoiceMap;
          try {
            final detail = await _client.get(
              '/seller/branches/${ApiConstants.branchId}/refunds/$refundId',
            );
            final detailData = detail is Map ? detail['data'] : null;
            final invoiceRaw = detailData is Map
                ? (detailData['invoice'] ?? detailData)
                : null;
            if (invoiceRaw is Map) {
              invoiceMap =
                  invoiceRaw.map((k, v) => MapEntry(k.toString(), v));
            }
          } catch (_) {
            continue;
          }
          if (invoiceMap == null) continue;
          if (!refundReferencesTarget(invoiceMap)) continue;

          final items = invoiceMap['items'];
          if (items is! List) continue;
          for (final item in items.whereType<Map>()) {
            final row =
                item.map((k, v) => MapEntry(k.toString(), v));
            // Tag the row so the merge / display layers know it's a
            // salon-style refund and pick the with-tax `total_tax` for
            // the amount column. Also forward the CN context for
            // display (e.g. "مسترجع في #CN-821").
            row['is_refunded'] = true;
            row['refund_invoice_number'] = invoiceMap['invoice_number'];
            row['refund_id'] = refundId;
            row['refund_date'] = invoiceMap['date'];
            // Existing display widgets read `meal_name` / `name` first;
            // CN items expose only `item_name`, so mirror it.
            if (row['meal_name'] == null && row['item_name'] != null) {
              row['meal_name'] = row['item_name'];
            }
            aggregated.add(row);
          }
        }

        // Stop early when the page returned a partial / empty list — the
        // backend pages this list 15 at a time, so anything shorter than
        // 15 means we're at the end.
        if (listData.length < 15) break;
      }
      return aggregated;
    } catch (e) {
      // Don't surface a red banner from the refund-history overlay —
      // returning empty just hides it; the rest of the invoice/booking
      // dialog still renders.
      print('⚠️ salon refunded-items lookup failed: $e');
      return const <Map<String, dynamic>>[];
    }
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
    // Slot-availability cache is keyed on (employee, service, date) and
    // any item edit can free or consume a slot. Drop the whole cache so
    // the next picker open is forced to re-query the backend.
    try {
      getIt<SalonEmployeeService>().invalidateAvailableTimesCache();
    } catch (_) {}
    return _rememberResponse('update_booking_items', response);
  }
}
