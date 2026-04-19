// ignore_for_file: unused_element, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../order_service.dart';

extension OrderServiceRefundLogic on OrderService {
  List<int> _extractIdList(
    dynamic source, {
    List<String> preferredKeys = const [
      'id',
      'item_id',
      'sales_meal_id',
      'sales_product_id',
    ],
  }) {
    final ids = <int>[];

    void tryAdd(dynamic raw) {
      final parsed = int.tryParse(_digitsOnly(raw));
      if (parsed != null && parsed > 0) ids.add(parsed);
    }

    if (source is List) {
      for (final item in source) {
        if (item is Map) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          bool added = false;
          for (final key in preferredKeys) {
            if (map.containsKey(key)) {
              tryAdd(map[key]);
              added = true;
            }
          }
          if (!added) {
            for (final value in map.values) {
              tryAdd(value);
            }
          }
        } else {
          tryAdd(item);
        }
      }
    } else if (source is Map) {
      final map = source.map((k, v) => MapEntry(k.toString(), v));
      for (final key in preferredKeys) {
        if (map.containsKey(key)) {
          tryAdd(map[key]);
        }
      }
    } else {
      tryAdd(source);
    }

    return ids.toSet().toList();
  }

  List<Map<String, dynamic>> _normalizeRefundPays(
    dynamic paysSource, {
    required double fallbackAmount,
  }) {
    final rows = <Map<String, dynamic>>[];

    String normalizePayMethod(Map<String, dynamic> row) {
      final method = (row['pay_method'] ??
              row['payMethod'] ??
              row['method'] ??
              row['type'] ??
              row['payment_method'] ??
              row['paymentMethod'])
          ?.toString()
          .trim();
      return (method == null || method.isEmpty) ? 'cash' : method;
    }

    double normalizeAmount(Map<String, dynamic> row) {
      final amount = _toDouble(
        row['amount'] ??
            row['value'] ??
            row['total'] ??
            row['price'] ??
            row['pay'],
      );
      return amount > 0 ? amount : fallbackAmount;
    }

    if (paysSource is List) {
      for (final item in paysSource) {
        final map = _asStringMap(item);
        if (map == null) continue;
        rows.add({
          'pay_method': normalizePayMethod(map),
          'amount': normalizeAmount(map),
        });
      }
    }

    if (rows.isEmpty) {
      rows.add({
        'pay_method': 'cash',
        'amount': fallbackAmount > 0 ? fallbackAmount : 0.01,
      });
    }

    return rows;
  }

  List<dynamic> _normalizeBookingRefundArray(dynamic source) {
    if (source is List) {
      // Filter out null values and empty strings, keep only valid items
      final filtered = source
          .where((item) => item != null && item.toString().trim().isNotEmpty)
          .toList();
      // If we have valid items, return them
      if (filtered.isNotEmpty) return filtered;
      // If list was empty or all nulls, return empty list (will trigger fallback)
      return const <dynamic>[];
    }
    if (source is Map) {
      return [source];
    }
    final digits = _digitsOnly(source);
    if (digits.isNotEmpty) {
      final parsed = int.tryParse(digits);
      if (parsed != null && parsed > 0) {
        return [parsed];
      }
    }
    final text = source?.toString().trim() ?? '';
    if (text.isNotEmpty && text.toLowerCase() != 'null') {
      return [text];
    }
    return const <dynamic>[];
  }

  List<dynamic> _extractBookingRefundArrayFromPreview(dynamic source) {
    final identifiers = <dynamic>[];

    void tryAdd(dynamic value) {
      if (value == null) return;
      if (value is Map || value is List) return;
      final digits = _digitsOnly(value);
      if (digits.isNotEmpty) {
        final parsed = int.tryParse(digits);
        if (parsed != null && parsed > 0) {
          identifiers.add(parsed);
          return;
        }
      }
    }

    void scanList(List<dynamic> rows) {
      for (final row in rows) {
        if (row is Map) {
          final map = row.map((k, v) => MapEntry(k.toString(), v));
          bool addedId = false;
          for (final key in const [
            'booking_meal_id',
            'booking_product_id',
            'sales_meal_id',
            'sales_product_id',
            'item_id',
            'id',
          ]) {
            if (map[key] != null) {
              tryAdd(map[key]);
              addedId = true;
              break;
            }
          }
          if (!addedId) tryAdd(map);
        } else {
          tryAdd(row);
        }
      }
    }

    final root = _asStringMap(source);
    if (root == null) return const <dynamic>[];

    final directRefund = _normalizeBookingRefundArray(root['refund']);
    if (directRefund.isNotEmpty) return directRefund;

    void scanDeep(Map<String, dynamic> map) {
      for (final key in const [
        'refund',
        'refunds',
        'items',
        'meals',
        'booking_meals',
        'booking_products',
        'sales_meals',
        'sales_products',
        'products',
      ]) {
        final rows = map[key];
        if (rows is List && rows.isNotEmpty) {
          scanList(rows);
        }
      }
      for (final value in map.values) {
        if (value is Map) {
          scanDeep(value.map((k, v) => MapEntry(k.toString(), v)));
        }
      }
    }

    scanDeep(root);

    if (identifiers.isNotEmpty) return identifiers.toSet().toList();
    return const <dynamic>[];
  }

  Future<List<dynamic>> _resolveBookingRefundArray({
    required String normalizedOrderId,
    required dynamic providedRefund,
  }) async {
    print('🔍 DEBUG _resolveBookingRefundArray:');
    print('  normalizedOrderId: $normalizedOrderId');
    print('  providedRefund: $providedRefund');

    final direct = _normalizeBookingRefundArray(providedRefund);
    print('  direct from providedRefund: $direct');
    if (direct.isNotEmpty) return direct;

    try {
      print('  Calling showBookingRefund...');
      final preview = await showBookingRefund(normalizedOrderId);

      // Print full response safely
      final previewStr = preview.toString();
      if (previewStr.length > 500) {
        print(
            '  preview response (first 500 chars): ${previewStr.substring(0, 500)}...');
      } else {
        print('  preview response (full): $previewStr');
      }

      final fromPreview = _extractBookingRefundArrayFromPreview(preview);
      print('  fromPreview: $fromPreview');
      if (fromPreview.isNotEmpty) return fromPreview;

      final previewData = _asStringMap(preview['data']) ?? const {};
      print('  previewData keys: ${previewData.keys.toList()}');

      final fromPreviewData =
          _extractBookingRefundArrayFromPreview(previewData);
      print('  fromPreviewData: $fromPreviewData');
      if (fromPreviewData.isNotEmpty) return fromPreviewData;

      // Check sales_meals for IDs
      final salesMeals = previewData['sales_meals'];
      if (salesMeals is List && salesMeals.isNotEmpty) {
        print('  Found sales_meals: ${salesMeals.length} items');
        final ids = <dynamic>[];
        for (final item in salesMeals) {
          if (item is Map) {
            final map = item.map((k, v) => MapEntry(k.toString(), v));
            final id = map['sales_meal_id'] ?? map['id'];
            if (id != null) {
              ids.add(id);
              print('    - sales_meal_id: $id');
            }
          }
        }
        print('  Extracted sales_meal IDs: $ids');
        if (ids.isNotEmpty) return ids;
      }

      // Check sales_products for IDs
      final salesProducts = previewData['sales_products'];
      if (salesProducts is List && salesProducts.isNotEmpty) {
        print('  Found sales_products: ${salesProducts.length} items');
        final ids = <dynamic>[];
        for (final item in salesProducts) {
          if (item is Map) {
            final map = item.map((k, v) => MapEntry(k.toString(), v));
            final id = map['sales_product_id'] ?? map['id'];
            if (id != null) {
              ids.add(id);
              print('    - sales_product_id: $id');
            }
          }
        }
        print('  Extracted sales_product IDs: $ids');
        if (ids.isNotEmpty) return ids;
      }

      // Check booking_meals for IDs
      final bookingMeals = previewData['booking_meals'];
      if (bookingMeals is List && bookingMeals.isNotEmpty) {
        print('  Found booking_meals: ${bookingMeals.length} items');
        final ids = <dynamic>[];
        for (final item in bookingMeals) {
          if (item is Map) {
            final map = item.map((k, v) => MapEntry(k.toString(), v));
            final id = map['booking_meal_id'] ?? map['id'];
            if (id != null) {
              ids.add(id);
              print('    - booking_meal_id: $id');
            }
          }
        }
        print('  Extracted booking_meal IDs: $ids');
        if (ids.isNotEmpty) return ids;
      }

      // Check booking_products for IDs
      final bookingProducts = previewData['booking_products'];
      if (bookingProducts is List && bookingProducts.isNotEmpty) {
        print('  Found booking_products: ${bookingProducts.length} items');
        final ids = <dynamic>[];
        for (final item in bookingProducts) {
          if (item is Map) {
            final map = item.map((k, v) => MapEntry(k.toString(), v));
            final id = map['booking_product_id'] ?? map['id'];
            if (id != null) {
              ids.add(id);
              print('    - booking_product_id: $id');
            }
          }
        }
        print('  Extracted booking_product IDs: $ids');
        if (ids.isNotEmpty) return ids;
      }

      // Check if collection exists and has items
      final collection = previewData['collection'];
      if (collection is List && collection.isNotEmpty) {
        print('  Found collection: ${collection.length} items');
        final ids = <dynamic>[];
        for (final item in collection) {
          if (item is Map) {
            final map = item.map((k, v) => MapEntry(k.toString(), v));
            final id = map['id'] ??
                map['booking_meal_id'] ??
                map['booking_product_id'] ??
                map['sales_meal_id'] ??
                map['sales_product_id'];
            if (id != null) {
              ids.add(id);
              print('    - collection id: $id');
            }
          }
        }
        print('  Extracted collection IDs: $ids');
        if (ids.isNotEmpty) return ids;
      }

      // Check meals (generic)
      final meals = previewData['meals'];
      if (meals is List && meals.isNotEmpty) {
        print('  Found meals: ${meals.length} items');
        final ids = <dynamic>[];
        for (final item in meals) {
          if (item is Map) {
            final map = item.map((k, v) => MapEntry(k.toString(), v));
            final id = map['id'] ?? map['meal_id'];
            if (id != null) {
              ids.add(id);
              print('    - meal id: $id');
            }
          }
        }
        print('  Extracted meal IDs: $ids');
        if (ids.isNotEmpty) return ids;
      }

      // Check products (generic)
      final products = previewData['products'];
      if (products is List && products.isNotEmpty) {
        print('  Found products: ${products.length} items');
        final ids = <dynamic>[];
        for (final item in products) {
          if (item is Map) {
            final map = item.map((k, v) => MapEntry(k.toString(), v));
            final id = map['id'] ?? map['product_id'];
            if (id != null) {
              ids.add(id);
              print('    - product id: $id');
            }
          }
        }
        print('  Extracted product IDs: $ids');
        if (ids.isNotEmpty) return ids;
      }

      print('  ⚠️ No refund items found in preview');
      print('  ⚠️ Preview data structure: ${previewData.keys.toList()}');
    } catch (e, stackTrace) {
      print('  ❌ Error in _resolveBookingRefundArray: $e');
      print('  ❌ Stack trace: $stackTrace');
    }

    // Return empty array - backend may not accept this
    print('  ⚠️ WARNING: Returning empty array - backend may reject this!');
    return [];
  }

  Future<Map<String, dynamic>> _buildInvoiceRefundCompatiblePayload({
    required String invoiceId,
    required Map<String, dynamic> originalPayload,
  }) async {
    final payload = Map<String, dynamic>.from(originalPayload);

    Map<String, dynamic> refundPreview = const <String, dynamic>{};
    final mealTotalById = <int, double>{};
    final productTotalById = <int, double>{};

    try {
      final previewResponse = await showInvoiceRefund(invoiceId);
      refundPreview = _asStringMap(previewResponse['data']) ?? const {};

      final meals = refundPreview['sales_meals'];
      if (meals is List) {
        for (final row in meals.whereType<Map>()) {
          final map = row.map((k, v) => MapEntry(k.toString(), v));
          final id = int.tryParse(_digitsOnly(map['sales_meal_id']));
          if (id == null) continue;
          mealTotalById[id] = _toDouble(map['total']);
        }
      }

      final products = refundPreview['sales_products'];
      if (products is List) {
        for (final row in products.whereType<Map>()) {
          final map = row.map((k, v) => MapEntry(k.toString(), v));
          final id = int.tryParse(_digitsOnly(map['sales_product_id']));
          if (id == null) continue;
          productTotalById[id] = _toDouble(map['total']);
        }
      }
    } catch (_) {
      // Keep fallback logic resilient even if preview endpoint is unavailable.
    }

    final refundMealIds = _extractIdList(
      payload['refund_meals'],
      preferredKeys: const ['sales_meal_id', 'item_id', 'id'],
    );
    final refundProductIds = _extractIdList(
      payload['refund_products'],
      preferredKeys: const ['sales_product_id', 'item_id', 'id'],
    );

    final legacyItemIds = _extractIdList(
      payload['refund_items'],
      preferredKeys: const [
        'sales_meal_id',
        'sales_product_id',
        'item_id',
        'id'
      ],
    );
    for (final id in legacyItemIds) {
      if (mealTotalById.containsKey(id)) {
        refundMealIds.add(id);
        continue;
      }
      if (productTotalById.containsKey(id)) {
        refundProductIds.add(id);
        continue;
      }
      // When backend type is unknown, assume meal to preserve legacy behavior.
      refundMealIds.add(id);
    }

    if (refundMealIds.isEmpty &&
        refundProductIds.isEmpty &&
        mealTotalById.isNotEmpty) {
      refundMealIds.add(mealTotalById.keys.first);
    }

    if (refundMealIds.isNotEmpty) {
      payload['refund_meals'] = refundMealIds.toSet().toList();
    }
    if (refundProductIds.isNotEmpty) {
      payload['refund_products'] = refundProductIds.toSet().toList();
    }
    payload.remove('refund_items');

    double selectedAmount = 0;
    for (final id in refundMealIds) {
      selectedAmount += mealTotalById[id] ?? 0;
    }
    for (final id in refundProductIds) {
      selectedAmount += productTotalById[id] ?? 0;
    }
    if (selectedAmount <= 0) {
      const amountKeys = [
        'refund_total',
        'refund_amount',
        'amount',
        'total',
        'grand_total',
      ];
      for (final key in amountKeys) {
        selectedAmount = _toDouble(payload[key]);
        if (selectedAmount > 0) break;
        selectedAmount = _toDouble(refundPreview[key]);
        if (selectedAmount > 0) break;
      }
    }
    if (selectedAmount <= 0) selectedAmount = 0.01;

    payload['date'] = (payload['date']?.toString().trim().isNotEmpty ?? false)
        ? payload['date']
        : _todayDateForApi();
    payload['pays'] = _normalizeRefundPays(
      payload['pays'],
      fallbackAmount: selectedAmount,
    );
    return payload;
  }

}
