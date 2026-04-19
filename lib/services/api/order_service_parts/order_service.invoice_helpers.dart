// ignore_for_file: unused_element, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../order_service.dart';

extension OrderServiceInvoiceHelpers on OrderService {
  List<Map<String, dynamic>> _extractBookingRowsFromResponse(dynamic response) {
    final normalized = _ensureMapResponse(response);

    List<Map<String, dynamic>> asRows(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }

    final rootData = normalized['data'];
    if (rootData is List) return asRows(rootData);
    if (rootData is Map) {
      final nestedData = rootData['data'];
      if (nestedData is List) return asRows(nestedData);
      final nestedItems = rootData['items'];
      if (nestedItems is List) return asRows(nestedItems);
    }

    final rootItems = normalized['items'];
    if (rootItems is List) return asRows(rootItems);
    return const [];
  }

  Map<String, dynamic>? _findBookingRowByIdentifier(
    List<Map<String, dynamic>> rows,
    String normalizedOrderId,
  ) {
    if (rows.isEmpty) return null;

    bool exactMatch(Map<String, dynamic> row) {
      const keys = [
        'id',
        'order_id',
        'booking_id',
        'order_number',
        'daily_order_number',
        'booking_number',
      ];

      for (final key in keys) {
        final digits = _digitsOnly(row[key]);
        if (digits.isNotEmpty && digits == normalizedOrderId) {
          return true;
        }
      }
      return false;
    }

    for (final row in rows) {
      if (exactMatch(row)) return row;
    }

    if (normalizedOrderId.length >= 4) {
      for (final row in rows) {
        const keys = [
          'id',
          'order_id',
          'booking_id',
          'order_number',
          'daily_order_number',
          'booking_number',
        ];
        for (final key in keys) {
          final digits = _digitsOnly(row[key]);
          if (digits.isNotEmpty && digits.contains(normalizedOrderId)) {
            return row;
          }
        }
      }
    }

    return null;
  }

  Future<Map<String, dynamic>?> _lookupBookingDetailsFromList(
    String normalizedOrderId,
  ) async {
    final searchResponse = await getBookings(
      page: 1,
      perPage: 100,
      search: normalizedOrderId,
    );
    final rows = _extractBookingRowsFromResponse(searchResponse);
    if (rows.isEmpty) return null;

    final matched =
        _findBookingRowByIdentifier(rows, normalizedOrderId) ?? rows.first;
    return _rememberResponse('get_order_details', {
      'status': 200,
      'message': 'resolved_from_bookings_search',
      'data': matched,
    });
  }

  Map<String, dynamic> _withOrderIdentifierCompat(
    Map<String, dynamic> payload,
  ) {
    final normalized = Map<String, dynamic>.from(payload);
    bool isValid(dynamic v) {
      if (v == null) return false;
      final s = v.toString().trim().toLowerCase();
      return s.isNotEmpty && s != '0' && s != 'null';
    }

    final hasOrderId = isValid(normalized['order_id']);
    final hasBookingId = isValid(normalized['booking_id']);

    // Ensure both IDs are present if one exists and the other is missing/zero.
    if (hasOrderId && !hasBookingId) {
      normalized['booking_id'] = normalized['order_id'];
    } else if (hasBookingId && !hasOrderId) {
      normalized['order_id'] = normalized['booking_id'];
    }

    return normalized;
  }

  bool _hasInvoiceItems(Map<String, dynamic> invoiceData) {
    bool hasList(String key) =>
        invoiceData[key] is List && (invoiceData[key] as List).isNotEmpty;
    return hasList('items') ||
        hasList('card') ||
        hasList('meals') ||
        hasList('sales_meals');
  }

  Future<Map<String, dynamic>> _ensureInvoiceItems(
    Map<String, dynamic> invoiceData,
  ) async {
    final enriched = Map<String, dynamic>.from(invoiceData);
    final normalized = _withOrderIdentifierCompat(enriched);
    final bookingId = normalized['booking_id'] ?? normalized['order_id'];

    // Preserve locally-set discounts: the caller (main_screen) sets discount
    // per item from the cashier's cart. The backend booking_details response
    // may NOT echo those discounts back, so we must keep them.
    final originalSalesMeals = invoiceData['sales_meals'];
    final hasOriginalSalesMeals =
        originalSalesMeals is List && originalSalesMeals.isNotEmpty;

    // Build a lookup: meal_id → list of {discount, discount_type} from the
    // original payload so we can re-inject them after the backend fetch.
    final originalDiscountsByMealId = <String, List<Map<String, dynamic>>>{};
    if (hasOriginalSalesMeals) {
      for (final m in originalSalesMeals) {
        if (m is! Map) continue;
        final mealId = (m['meal_id'] ?? '').toString();
        final discount = m['discount']?.toString() ?? '';
        final discountType = m['discount_type']?.toString() ?? '';
        final numericVal = double.tryParse(discount) ?? 0;
        if (discount.isNotEmpty && numericVal > 0) {
          originalDiscountsByMealId
              .putIfAbsent(mealId, () => [])
              .add({'discount': discount, 'discount_type': discountType});
        }
      }
    }

    void _mergeOriginalDiscounts(List<Map<String, dynamic>> salesMeals) {
      if (originalDiscountsByMealId.isEmpty) return;
      final usedQueues = <String, List<Map<String, dynamic>>>{};
      for (final queue in originalDiscountsByMealId.entries) {
        usedQueues[queue.key] = List.from(queue.value);
      }
      for (final meal in salesMeals) {
        final mealId = (meal['meal_id'] ?? '').toString();
        final existingDiscount = meal['discount']?.toString() ?? '';
        // Only inject if the backend didn't already provide a non-zero discount.
        final numericDiscount = double.tryParse(existingDiscount) ?? 0;
        if (existingDiscount.isEmpty || numericDiscount <= 0) {
          final queue = usedQueues[mealId];
          if (queue != null && queue.isNotEmpty) {
            final orig = queue.removeAt(0);
            meal['discount'] = orig['discount'];
            meal['discount_type'] = orig['discount_type'];
          }
        }
      }
    }

    if (bookingId != null) {
      try {
        final details = await getBookingDetails(bookingId.toString());
        final detailMap =
            _asMap(details['data']) ?? _asMap(details) ?? const {};
        final rawItems = _extractItemsFromBookingDetails(
          Map<String, dynamic>.from(detailMap),
        );
        final itemsPayload = _mapItemsToInvoicePayload(rawItems);
        final salesMealsPayload = _mapItemsToSalesMeals(itemsPayload);

        // Detect if items are salon services
        final hasSalonItems = itemsPayload.any((item) =>
            item.containsKey('service_id') || item.containsKey('employee_id'));

        if (itemsPayload.isNotEmpty) {
          enriched['items'] = itemsPayload;
          enriched['card'] = itemsPayload;
          if (!hasSalonItems) enriched['meals'] = itemsPayload;
        }
        if (salesMealsPayload.isNotEmpty) {
          _mergeOriginalDiscounts(salesMealsPayload);
          if (hasSalonItems) {
            enriched['sales_services'] = salesMealsPayload;
          } else {
            enriched['sales_meals'] = salesMealsPayload;
          }
        } else if (hasOriginalSalesMeals) {
          enriched['sales_meals'] = originalSalesMeals;
        }
        return enriched;
      } catch (e) {
        print('⚠️ Could not fetch booking details for invoice: $e');
      }
    }

    if (_hasInvoiceItems(enriched)) {
      final hasSalesMeals = (enriched['sales_meals'] is List &&
              (enriched['sales_meals'] as List).isNotEmpty) ||
          (enriched['sales_services'] is List &&
              (enriched['sales_services'] as List).isNotEmpty);
      if (!hasSalesMeals) {
        List<Map<String, dynamic>>? source;
        for (final key in const ['items', 'meals', 'card']) {
          final raw = enriched[key];
          if (raw is List && raw.isNotEmpty) {
            source = raw
                .whereType<Map>()
                .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
                .toList();
            if (source.isNotEmpty) break;
          }
        }
        if (source != null && source.isNotEmpty) {
          final salesPayload = _mapItemsToSalesMeals(source);
          if (salesPayload.isNotEmpty) {
            _mergeOriginalDiscounts(salesPayload);
            final hasSalonItems = salesPayload.any((item) =>
                item.containsKey('service_id') || item.containsKey('employee_id'));
            if (hasSalonItems) {
              enriched['sales_services'] = salesPayload;
            } else {
              enriched['sales_meals'] = salesPayload;
            }
          }
        }
      }
    }

    return enriched;
  }

  List<Map<String, dynamic>> _extractItemsFromBookingDetails(
    Map<String, dynamic> payload,
  ) {
    final sections = payload['sections'];
    if (sections is List) {
      final sectionItems = <Map<String, dynamic>>[];
      for (final section in sections) {
        if (section is! Map) continue;
        final sectionMap = section.map((k, v) => MapEntry(k.toString(), v));
        final items = sectionMap['items'];
        if (items is List) {
          for (final item in items) {
            if (item is Map) {
              sectionItems.add(
                item.map((k, v) => MapEntry(k.toString(), v)),
              );
            }
          }
        }
      }
      if (sectionItems.isNotEmpty) return sectionItems;
    }
    const keys = [
      'booking_services',
      'sales_services',
      'meals',
      'booking_meals',
      'booking_products',
      'booking_items',
      'items',
      'invoice_items',
      'sales_meals',
      'card',
      'cart',
    ];
    for (final key in keys) {
      final raw = payload[key];
      if (raw is List) {
        final rows = raw
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
        if (rows.isNotEmpty) return rows;
      }
    }
    for (final nestedKey in const ['data', 'booking', 'order', 'details']) {
      final nested = payload[nestedKey];
      if (nested is Map) {
        final map = nested.map((k, v) => MapEntry(k.toString(), v));
        final rows = _extractItemsFromBookingDetails(
          Map<String, dynamic>.from(map),
        );
        if (rows.isNotEmpty) return rows;
      }
    }
    return const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _mapItemsToInvoicePayload(
    List<Map<String, dynamic>> rawItems,
  ) {
    final items = <Map<String, dynamic>>[];
    for (final raw in rawItems) {
      dynamic pick(dynamic value) => value == null ? null : value;
      final mealMap = _asMap(raw['meal']) ?? _asMap(raw['service']) ?? const {};
      final mealId = pick(raw['meal_id'] ?? raw['service_id'] ?? mealMap['id']);
      final productId = pick(raw['product_id'] ?? raw['productId']);
      final bookingMealId = pick(raw['booking_meal_id'] ?? raw['booking_service_id'] ?? raw['id']);
      final bookingProductId = pick(raw['booking_product_id']);
      final packageServiceId = pick(raw['package_service_id']);
      final employeeId = pick(raw['employee_id']);
      final serviceDate = pick(raw['date']);
      final serviceTime = pick(raw['time']);
      final fallbackId = pick(raw['id']);
      final quantityRaw = raw['quantity'] ?? raw['qty'] ?? raw['count'];
      final quantity = (quantityRaw is num)
          ? quantityRaw.toInt()
          : int.tryParse('$quantityRaw') ?? 1;
      final totalRaw = raw['total'] ?? raw['line_total'];
      final unitRaw = raw['unit_price'] ??
          raw['unitPrice'] ??
          raw['price'] ??
          mealMap['price'];
      var unitPrice = _parseFlexibleDouble(unitRaw);
      final total = _parseFlexibleDouble(totalRaw);
      if (unitPrice <= 0 && total > 0 && quantity > 0) {
        unitPrice = total / quantity;
      }
      String? resolveItemName() {
        final directName = raw['item_name'] ?? raw['meal_name'];
        if (directName != null) return directName.toString();
        final rawName = mealMap['name'];
        if (rawName == null) return null;
        final rawText = rawName.toString();
        final trimmed = rawText.trim();
        if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
          try {
            final parsed = jsonDecode(trimmed);
            final parsedMap = _asStringMap(parsed);
            if (parsedMap != null) {
              return (parsedMap['ar'] ??
                      parsedMap['en'] ??
                      parsedMap.values.first)
                  ?.toString();
            }
          } catch (_) {
            return rawText;
          }
        }
        return rawText;
      }

      final resolvedItemName = resolveItemName() ??
          (raw['service_name'] ?? raw['item_name'])?.toString();
      if (mealId == null && productId == null && fallbackId == null) {
        continue;
      }
      // Detect if this is a salon service item
      final isSalonItem = raw.containsKey('service_id') ||
          raw.containsKey('booking_services') ||
          raw.containsKey('employee_id') ||
          packageServiceId != null;

      if (isSalonItem) {
        items.add({
          'service_id': mealId,
          if (bookingMealId != null) 'booking_service_id': bookingMealId,
          if (resolvedItemName != null) 'service_name': resolvedItemName,
          if (resolvedItemName != null) 'item_name': resolvedItemName,
          if (employeeId != null) 'employee_id': employeeId,
          if (packageServiceId != null) 'package_service_id': packageServiceId,
          if (serviceDate != null) 'date': serviceDate,
          if (serviceTime != null) 'time': serviceTime,
          'quantity': quantity,
          'price': unitPrice,
          'unit_price': unitPrice,
          if (raw['modified_unit_price'] != null) 'modified_unit_price': raw['modified_unit_price'],
          if (raw['discount'] != null) 'discount': raw['discount'],
          if (raw['discount_type'] != null) 'discount_type': raw['discount_type'],
          if (raw['session_numbers'] != null) 'session_numbers': raw['session_numbers'],
        });
      } else {
        items.add({
          if (bookingMealId != null) 'booking_meal_id': bookingMealId,
          if (bookingProductId != null) 'booking_product_id': bookingProductId,
          if (mealId != null) 'meal_id': mealId,
          if (mealId == null && productId != null) 'product_id': productId,
          if (mealId == null && productId == null) 'id': fallbackId,
          if (resolvedItemName != null) 'item_name': resolvedItemName,
          'quantity': quantity,
          'price': unitPrice,
          'unitPrice': unitPrice,
          if (raw['discount'] != null) 'discount': raw['discount'],
          if (raw['discount_type'] != null) 'discount_type': raw['discount_type'],
        });
      }
    }
    return items;
  }

  List<Map<String, dynamic>> _mapItemsToSalesMeals(
    List<Map<String, dynamic>> itemsPayload,
  ) {
    if (itemsPayload.isEmpty) return const <Map<String, dynamic>>[];
    final salesMeals = <Map<String, dynamic>>[];
    for (final item in itemsPayload) {
      final name = item['service_name'] ?? item['item_name'] ?? item['meal_name'] ?? item['name'];
      final quantityRaw = item['quantity'] ?? 1;
      final quantity = (quantityRaw is num)
          ? quantityRaw.toInt()
          : int.tryParse('$quantityRaw') ?? 1;
      final unitRaw =
          item['unit_price'] ?? item['unitPrice'] ?? item['price'] ?? 0;
      final unitPrice = _parseFlexibleDouble(unitRaw);
      final totalRaw = item['total'];
      var total = _parseFlexibleDouble(totalRaw);
      if (total <= 0 && unitPrice > 0 && quantity > 0) {
        total = unitPrice * quantity;
      }

      // Detect salon service item
      final isSalonItem = item.containsKey('service_id') || item.containsKey('employee_id');

      if (isSalonItem) {
        salesMeals.add({
          if (item['service_id'] != null) 'service_id': item['service_id'],
          if (item['booking_service_id'] != null)
            'booking_service_id': item['booking_service_id'],
          if (item['employee_id'] != null) 'employee_id': item['employee_id'],
          if (item['package_service_id'] != null)
            'package_service_id': item['package_service_id'],
          if (name != null) 'service_name': name,
          'quantity': quantity,
          'price': unitPrice,
          'unit_price': unitPrice,
          if (item['modified_unit_price'] != null)
            'modified_unit_price': item['modified_unit_price'],
          if (item['date'] != null) 'date': item['date'],
          if (item['time'] != null) 'time': item['time'],
          if (item['session_numbers'] != null)
            'session_numbers': item['session_numbers'],
          if (item['discount'] != null) 'discount': item['discount'],
          if (item['discount_type'] != null)
            'discount_type': item['discount_type'],
        });
      } else {
        salesMeals.add({
          if (item['booking_meal_id'] != null)
            'booking_meal_id': item['booking_meal_id'],
          if (item['meal_id'] != null) 'meal_id': item['meal_id'],
          if (name != null) 'meal_name': name,
          'quantity': quantity,
          'price': unitPrice,
          'unit_price': unitPrice,
          'total': total,
          if (item['discount'] != null) 'discount': item['discount'],
          if (item['discount_type'] != null)
            'discount_type': item['discount_type'],
        });
      }
    }
    return salesMeals;
  }

  Map<String, dynamic> _normalizeInvoicePayloadForPostman(
    Map<String, dynamic> invoiceData,
  ) {
    final normalized = _withOrderIdentifierCompat(invoiceData);
    if (normalized['date'] == null || normalized['date'].toString().isEmpty) {
      normalized['date'] = DateTime.now().toIso8601String().split('T').first;
    }

    final paysRaw = normalized['pays'];
    if (paysRaw is! List || paysRaw.isEmpty) {
      normalized['pays'] = const [
        {'name': 'دفع نقدي', 'pay_method': 'cash', 'amount': 0, 'index': 0},
      ];
      return normalized;
    }

    normalized['pays'] = paysRaw.asMap().entries.map((entry) {
      final index = entry.key;
      final row = entry.value;
      if (row is! Map) {
        return <String, dynamic>{
          'name': 'دفع نقدي',
          'pay_method': 'cash',
          'amount': 0,
          'index': index,
        };
      }

      final data = row.map((k, v) => MapEntry(k.toString(), v));
      final method = (data['pay_method'] ?? 'cash').toString().trim();
      final amount = data['amount'] ?? 0;
      final isCash = method.toLowerCase() == 'cash';
      return <String, dynamic>{
        'name': data['name'] ?? (isCash ? 'دفع نقدي' : method),
        'pay_method': method,
        'amount': amount,
        'index': data['index'] ?? index,
      };
    }).toList();

    return normalized;
  }

  Map<String, String> _withOrderIdentifierCompatFields(
    Map<String, dynamic> payload,
  ) {
    final fields = <String, String>{};
    final hasOrderId = payload['order_id'] != null;
    final hasBookingId = payload['booking_id'] != null;
    if (hasOrderId) {
      fields['order_id'] = payload['order_id'].toString();
    }
    if (hasBookingId) {
      fields['booking_id'] = payload['booking_id'].toString();
    }
    if (hasOrderId && !hasBookingId) {
      fields['booking_id'] = payload['order_id'].toString();
    }
    return fields;
  }

  bool _isFallbackEligibleApiError(ApiException error) {
    final statusCode = error.statusCode ?? 0;
    final message = error.message.toLowerCase();
    return statusCode == 404 ||
        statusCode == 405 ||
        statusCode == 500 ||
        message.contains('route_not_found') ||
        message.contains('not found');
  }

  List<String> _bookingRefundEndpoints(String orderId) {
    return [
      ApiConstants.bookingRefundEndpoint(orderId),
      '/seller/refund/branches/${ApiConstants.branchId}/booking/$orderId',
      '/seller/branches/${ApiConstants.branchId}/bookings/$orderId/refund',
    ];
  }

  Future<Map<String, dynamic>> _getWithFallbackEndpoints(
    List<String> endpoints, {
    required String responseKey,
  }) async {
    ApiException? lastApiError;

    for (final endpoint in endpoints) {
      try {
        final response = await _client.get(endpoint);
        return _rememberResponse(responseKey, response);
      } on ApiException catch (e) {
        lastApiError = e;
        if (!_isFallbackEligibleApiError(e)) rethrow;
      }
    }

    if (lastApiError != null) throw lastApiError;
    throw ApiException('ENDPOINT_NOT_AVAILABLE');
  }

  Future<Map<String, dynamic>> _patchWithFallbackEndpoints(
    List<String> endpoints,
    Map<String, dynamic> payload, {
    required String responseKey,
  }) async {
    ApiException? lastApiError;

    for (final endpoint in endpoints) {
      try {
        final response = await _client.patch(endpoint, payload);
        return _rememberResponse(responseKey, response);
      } on ApiException catch (e) {
        final lowerMessage = e.message.toLowerCase();
        final expectsMultipart = e.statusCode == 415 ||
            lowerMessage.contains('multipart') ||
            lowerMessage.contains('content type') ||
            lowerMessage.contains('unsupported media');

        if (expectsMultipart) {
          final fields = <String, String>{};
          payload.forEach((key, value) {
            if (value == null) return;
            fields[key] = value.toString();
          });

          try {
            final response = await _client.patchMultipart(endpoint, fields);
            return _rememberResponse(responseKey, response);
          } on ApiException catch (multipartError) {
            lastApiError = multipartError;
            if (!_isFallbackEligibleApiError(multipartError)) rethrow;
            continue;
          }
        }

        lastApiError = e;
        if (!_isFallbackEligibleApiError(e)) rethrow;
      }
    }

    if (lastApiError != null) throw lastApiError;
    throw ApiException('ENDPOINT_NOT_AVAILABLE');
  }

}
