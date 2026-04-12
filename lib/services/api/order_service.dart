import 'dart:convert';
import 'dart:io';

import 'base_client.dart';
import 'api_constants.dart';
import 'package:hermosa_pos/models/booking_invoice.dart';
import 'package:hermosa_pos/services/cache_service.dart';
import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:hermosa_pos/services/offline/connectivity_service.dart';
import 'package:hermosa_pos/locator.dart';

class OrderService {
  final BaseClient _client = BaseClient();
  final CacheService _cache = getIt<CacheService>();
  final OfflineDatabaseService _offlineDb = OfflineDatabaseService();
  final ConnectivityService _connectivity = ConnectivityService();
  final Map<String, Map<String, dynamic>> _lastOrderApiResponses = {};
  bool _skipBookingCreateMetadataEndpoint = false;
  static const String _bookingCreateMetadataDisabledCacheKey =
      'booking_create_metadata_disabled';

  Map<String, Map<String, dynamic>> get lastOrderApiResponses =>
      Map.unmodifiable(_lastOrderApiResponses);

  Map<String, dynamic> _ensureMapResponse(dynamic response) {
    if (response is Map<String, dynamic>) {
      return Map<String, dynamic>.from(response);
    }
    if (response is Map) {
      return response.map((key, value) => MapEntry(key.toString(), value));
    }
    if (response is List) {
      return <String, dynamic>{'data': response};
    }
    if (response == null) {
      return <String, dynamic>{
        'status': 200,
        'message': 'No response body',
        'data': null,
      };
    }
    return <String, dynamic>{'data': response};
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  Map<String, dynamic> _rememberResponse(String key, dynamic response) {
    final normalized = _ensureMapResponse(response);
    _lastOrderApiResponses[key] = Map<String, dynamic>.from(normalized);
    return normalized;
  }

  double _parseFlexibleDouble(dynamic value) {
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value?.toString() ?? '');
    return parsed ?? 0.0;
  }

  String _resolveItemDisplayName(Map<String, dynamic> row) {
    final mealMap = _asStringMap(row['meal']) ?? const <String, dynamic>{};
    final productMap =
        _asStringMap(row['product']) ?? const <String, dynamic>{};
    final name = row['meal_name'] ??
        row['product_name'] ??
        row['item_name'] ??
        row['name'] ??
        mealMap['name'] ??
        productMap['name'];
    final text = name?.toString().trim();
    return (text == null || text.isEmpty) ? 'عنصر' : text;
  }

  String _normalizedItemIdentifier(dynamic value) {
    return value?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';
  }

  Set<String> _itemSignatures(Map<String, dynamic> row) {
    final signatures = <String>{};

    void addSignature(String prefix, dynamic value) {
      final normalized = _normalizedItemIdentifier(value);
      if (normalized.isNotEmpty) {
        signatures.add('$prefix:$normalized');
      }
    }

    addSignature('sales_meal', row['sales_meal_id']);
    addSignature('sales_product', row['sales_product_id']);
    addSignature('booking_meal', row['booking_meal_id']);
    addSignature('booking_product', row['booking_product_id']);
    addSignature('item', row['item_id']);
    addSignature('id', row['id']);
    addSignature('meal', row['meal_id']);
    addSignature('product', row['product_id']);

    if (signatures.isEmpty) {
      final name = _resolveItemDisplayName(row).trim().toLowerCase();
      final quantity =
          (row['quantity'] ?? row['qty'] ?? row['count'] ?? 1).toString().trim();
      final total = _parseFlexibleDouble(
        row['total'] ?? row['amount'] ?? row['price'] ?? row['unit_price'],
      );
      if (name.isNotEmpty) {
        signatures
            .add('name:$name|qty:$quantity|total:${total.toStringAsFixed(2)}');
      }
    }

    return signatures;
  }

  Map<String, dynamic> _normalizeDisplayItemRow(Map<String, dynamic> row) {
    final normalized = Map<String, dynamic>.from(row);
    final quantityRaw =
        normalized['quantity'] ?? normalized['qty'] ?? normalized['count'];
    final quantity = quantityRaw is num
        ? quantityRaw.toInt()
        : int.tryParse(quantityRaw?.toString() ?? '') ?? 1;
    final unitPrice = _parseFlexibleDouble(
      normalized['unit_price'] ??
          normalized['unitPrice'] ??
          normalized['price'],
    );
    final total = _parseFlexibleDouble(normalized['total']);

    normalized['meal_name'] = _resolveItemDisplayName(normalized);
    normalized['quantity'] = quantity;

    if (normalized['unit_price'] == null && unitPrice > 0) {
      normalized['unit_price'] = unitPrice;
    }
    if (normalized['price'] == null && unitPrice > 0) {
      normalized['price'] = unitPrice;
    }
    if (normalized['total'] == null && unitPrice > 0) {
      normalized['total'] = unitPrice * quantity;
    } else if (total <= 0 && unitPrice > 0) {
      normalized['total'] = unitPrice * quantity;
    }

    return normalized;
  }

  Map<String, dynamic> _normalizeRefundedMealRow(Map<String, dynamic> row) {
    final normalized = _normalizeDisplayItemRow(row);
    final normalizedInvoiced =
        normalized['is_invoiced']?.toString().trim().toLowerCase();
    final isInvoiced = normalized['is_invoiced'] == true ||
        normalized['is_invoiced'] == 1 ||
        normalized['is_invoiced'] == '1' ||
        normalizedInvoiced == 'true' ||
        normalizedInvoiced == 'yes';

    if (isInvoiced) {
      normalized['status'] = 'refunded';
      normalized['is_refunded'] = true;
      if (normalized['sales_meal_id'] == null &&
          normalized['sales_product_id'] == null &&
          normalized['id'] != null) {
        normalized['sales_meal_id'] = normalized['id'];
      }
    } else {
      normalized['status'] = 'cancelled';
      normalized['is_cancelled'] = true;
      if (normalized['booking_meal_id'] == null &&
          normalized['booking_product_id'] == null &&
          normalized['id'] != null) {
        normalized['booking_meal_id'] = normalized['id'];
      }
    }

    return normalized;
  }

  String _normalizeBookingIdOrThrow(dynamic rawOrderId) {
    final candidate = rawOrderId?.toString().trim() ?? '';
    if (candidate.isEmpty) {
      throw ApiException('الحقل رقم الحجز مطلوب.', statusCode: 422);
    }

    final numericOnly = candidate.replaceAll(RegExp(r'[^0-9]'), '');
    if (numericOnly.isEmpty) {
      throw ApiException('رقم الحجز غير صالح.', statusCode: 422);
    }

    final parsed = int.tryParse(numericOnly);
    if (parsed == null || parsed <= 0) {
      throw ApiException('رقم الحجز غير صالح.', statusCode: 422);
    }

    return parsed.toString();
  }

  String _digitsOnly(dynamic value) {
    if (value == null) return '';
    return value.toString().replaceAll(RegExp(r'[^0-9]'), '');
  }

  String _todayDateForApi() {
    final now = DateTime.now();
    final year = now.year.toString().padLeft(4, '0');
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return 0;
    final normalized = raw.replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
  }

  Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  Map<String, dynamic>? _decodeErrorBody(ApiException error) {
    final body = error.responseBody;
    if (body is Map<String, dynamic>) {
      return Map<String, dynamic>.from(body);
    }
    if (body is Map) {
      return body.map((k, v) => MapEntry(k.toString(), v));
    }
    if (body is! String) return null;
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    try {
      final parsed = jsonDecode(trimmed);
      return _asStringMap(parsed);
    } catch (_) {
      return null;
    }
  }

  bool _isInvoiceRefundContractMismatch(ApiException error) {
    if ((error.statusCode ?? 0) != 422) return false;
    final body = _decodeErrorBody(error);
    final lowerMessage =
        (body?['message']?.toString() ?? error.message).toLowerCase();
    if (lowerMessage.contains('برجاء تحديد عناصر الاسترجاع')) {
      return true;
    }
    if (lowerMessage.contains('التاريخ') ||
        lowerMessage.contains('المدفوعات') ||
        lowerMessage.contains('طريقة الدفع')) {
      return true;
    }
    final errors = body?['errors'];
    if (errors is Map) {
      final keys = errors.keys.map((e) => e.toString().toLowerCase());
      if (keys.any((k) =>
          k == 'date' ||
          k == 'pays' ||
          k.startsWith('pays.') ||
          k.startsWith('refund_meals') ||
          k.startsWith('refund_products'))) {
        return true;
      }
    }
    return false;
  }

  bool _containsRequiredKeyword(String value) {
    final lower = value.toLowerCase();
    return lower.contains('required') || lower.contains('مطلوب');
  }

  bool _isStatusFieldRequiredValidation(ApiException error) {
    if ((error.statusCode ?? 0) != 422) return false;
    final body = _decodeErrorBody(error);
    final lowerMessage =
        (body?['message']?.toString() ?? error.message).toLowerCase();

    final errors = body?['errors'];
    if (errors is Map) {
      for (final entry in errors.entries) {
        final key = entry.key.toString().toLowerCase();
        if (key != 'status' && !key.startsWith('status.')) continue;

        final value = entry.value;
        if (value is List) {
          if (value.any((item) => _containsRequiredKeyword(item.toString()))) {
            return true;
          }
        } else if (value != null &&
            _containsRequiredKeyword(value.toString())) {
          return true;
        }
      }
    }

    final englishRequired = lowerMessage.contains('status') &&
        _containsRequiredKeyword(lowerMessage);
    final arabicRequired =
        lowerMessage.contains('الحالة') && lowerMessage.contains('مطلوب');
    return englishRequired || arabicRequired;
  }

  bool _shouldRetryStatusUpdate(ApiException error) {
    if (_isStatusFieldRequiredValidation(error)) return true;
    final statusCode = error.statusCode ?? 0;
    if (statusCode == 404 ||
        statusCode == 405 ||
        statusCode == 415 ||
        statusCode == 500) {
      return true;
    }

    final lowerMessage = error.message.toLowerCase();
    return lowerMessage.contains('route_not_found') ||
        lowerMessage.contains('multipart') ||
        lowerMessage.contains('content type') ||
        lowerMessage.contains('unsupported media') ||
        lowerMessage.contains('method not allowed');
  }

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

        if (itemsPayload.isNotEmpty) {
          enriched['items'] = itemsPayload;
          enriched['card'] = itemsPayload;
          enriched['meals'] = itemsPayload;
        }
        if (salesMealsPayload.isNotEmpty) {
          enriched['sales_meals'] = salesMealsPayload;
        }
        return enriched;
      } catch (e) {
        print('⚠️ Could not fetch booking details for invoice: $e');
      }
    }

    if (_hasInvoiceItems(enriched)) {
      final hasSalesMeals = enriched['sales_meals'] is List &&
          (enriched['sales_meals'] as List).isNotEmpty;
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
          final salesMealsPayload = _mapItemsToSalesMeals(source);
          if (salesMealsPayload.isNotEmpty) {
            enriched['sales_meals'] = salesMealsPayload;
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
      final mealMap = _asMap(raw['meal']) ?? const {};
      final mealId = pick(raw['meal_id'] ?? mealMap['id']);
      final productId = pick(raw['product_id'] ?? raw['productId']);
      final bookingMealId = pick(raw['booking_meal_id'] ?? raw['id']);
      final bookingProductId = pick(raw['booking_product_id'] ?? raw['id']);
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

      final resolvedItemName = resolveItemName();
      if (mealId == null && productId == null && fallbackId == null) {
        continue;
      }
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
      });
    }
    return items;
  }

  List<Map<String, dynamic>> _mapItemsToSalesMeals(
    List<Map<String, dynamic>> itemsPayload,
  ) {
    if (itemsPayload.isEmpty) return const <Map<String, dynamic>>[];
    final salesMeals = <Map<String, dynamic>>[];
    for (final item in itemsPayload) {
      final name = item['item_name'] ?? item['meal_name'] ?? item['name'];
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

  bool _isDeliveryOrderType(String type) {
    final normalized = type.trim().toLowerCase();
    return normalized == 'restaurant_delivery' ||
        normalized == 'delivery' ||
        normalized == 'home_delivery';
  }

  String? _normalizeCoordinate(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;
    final parsed = double.tryParse(raw.replaceAll(',', '.'));
    if (parsed == null) return null;
    return parsed.toString();
  }

  Map<String, dynamic> _normalizeBookingPayload(
    Map<String, dynamic> source, {
    bool forceDeliveryCoordinates = false,
  }) {
    final normalized = Map<String, dynamic>.from(source);

    var type = normalized['type']?.toString().trim() ?? '';
    if (type.isEmpty || type.toLowerCase() == 'null') {
      type = 'restaurant_pickup';
    }
    normalized['type'] = type;
    if (normalized['date'] == null || normalized['date'].toString().isEmpty) {
      normalized['date'] = DateTime.now().toIso8601String().split('T').first;
    }

    final cardRaw = normalized['card'];
    final mealsRaw = normalized['meals'];
    final hasCard = cardRaw is List && cardRaw.isNotEmpty;
    final hasMeals = mealsRaw is List && mealsRaw.isNotEmpty;
    if (!hasCard && hasMeals) {
      normalized['card'] = List<dynamic>.from(mealsRaw);
    }
    if (!hasMeals && hasCard) {
      normalized['meals'] = List<dynamic>.from(cardRaw);
    }

    final rawTypeExtra = normalized['type_extra'];
    final typeExtra = rawTypeExtra is Map
        ? rawTypeExtra.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};

    typeExtra.putIfAbsent('car_number', () => null);
    typeExtra.putIfAbsent('table_name', () => null);

    if (_isDeliveryOrderType(type)) {
      final latitude = _normalizeCoordinate(typeExtra['latitude']);
      final longitude = _normalizeCoordinate(typeExtra['longitude']);
      typeExtra['latitude'] =
          latitude ?? (forceDeliveryCoordinates ? '0' : null);
      typeExtra['longitude'] =
          longitude ?? (forceDeliveryCoordinates ? '0' : null);
    } else {
      typeExtra.putIfAbsent('latitude', () => null);
      typeExtra.putIfAbsent('longitude', () => null);
    }

    normalized['type_extra'] = typeExtra;
    return normalized;
  }

  bool _requiresDeliveryCoordsFallback(String message) {
    final lower = message.toLowerCase();
    return lower.contains('latitude') ||
        lower.contains('longitude') ||
        lower.contains('type_extra') ||
        lower.contains('type extra');
  }

  bool _isInvalidType422(String message) {
    final lower = message.toLowerCase();
    return lower.contains('الحقل النوع غير صحيح') ||
        lower.contains('type field is invalid') ||
        (lower.contains('type') && lower.contains('invalid'));
  }

  List<String> _bookingTypeFallbackCandidates(String currentType) {
    final normalized = currentType.trim().toLowerCase();
    const carAliases = <String>[
      'restaurant_parking',
      'cars',
      'car',
      'drive_through',
      'drive-through',
      'parking',
    ];

    if (!carAliases.contains(normalized)) return const [];
    return <String>[
      'restaurant_parking',
      'cars',
      'car',
    ].where((candidate) => candidate != normalized).toList(growable: false);
  }

  bool _isRetryableBookingTransportError(Object error) {
    final message = error.toString().toLowerCase();
    final isHeaderClose =
        message.contains('connection closed before full header');
    final isSocket = message.contains('socketexception');
    final isTimeout =
        message.contains('timeoutexception') || message.contains('timed out');
    final isClientTransport = message.contains('clientexception') &&
        (message.contains('connection') ||
            message.contains('socket') ||
            message.contains('network') ||
            message.contains('handshake'));
    final isTaggedTransport = message.contains('transport_error');
    return isHeaderClose ||
        isSocket ||
        isTimeout ||
        isClientTransport ||
        isTaggedTransport;
  }

  Future<Map<String, dynamic>> _createBookingWithJsonRetry(
    Map<String, dynamic> payload,
  ) async {
    const maxAttempts = 2; // Keep it low to avoid duplicate orders.
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final response = await _client.post(
          ApiConstants.bookingsEndpoint,
          payload,
        );
        return _rememberResponse('create_order', response);
      } catch (e) {
        final hasMoreAttempts = attempt < maxAttempts - 1;
        if (!hasMoreAttempts || !_isRetryableBookingTransportError(e)) {
          rethrow;
        }
        final retryAttempt = attempt + 1;
        print(
          '⚠️ createBooking transport error, retrying JSON request (attempt $retryAttempt/$maxAttempts): $e',
        );
        await Future<void>.delayed(
          Duration(milliseconds: 350 * retryAttempt),
        );
      }
    }
    throw Exception('Failed to create booking request');
  }

  Future<Map<String, dynamic>> _createBookingWithMultipartRetry(
    Map<String, String> fields,
  ) async {
    const maxAttempts = 2; // Keep it low to avoid duplicate orders.
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final response = await _client.postMultipart(
          ApiConstants.bookingsEndpoint,
          fields,
        );
        return _rememberResponse('create_order', response);
      } catch (e) {
        final hasMoreAttempts = attempt < maxAttempts - 1;
        if (!hasMoreAttempts || !_isRetryableBookingTransportError(e)) {
          rethrow;
        }
        final retryAttempt = attempt + 1;
        print(
          '⚠️ createBooking transport error, retrying multipart request (attempt $retryAttempt/$maxAttempts): $e',
        );
        await Future<void>.delayed(
          Duration(milliseconds: 350 * retryAttempt),
        );
      }
    }
    throw Exception('Failed to create booking multipart request');
  }

  Future<Map<String, dynamic>> _createBookingMultipart(
    Map<String, dynamic> bookingData,
  ) async {
    final normalized = _normalizeBookingPayload(
      bookingData,
      forceDeliveryCoordinates: true,
    );
    final fields = <String, String>{
      if (normalized['customer_id'] != null)
        'customer_id': normalized['customer_id'].toString(),
      if (normalized['table_id'] != null)
        'table_id': normalized['table_id'].toString(),
      if (normalized['date'] != null) 'date': normalized['date'].toString(),
      if (normalized['type'] != null) 'type': normalized['type'].toString(),
    };

    final typeExtra = normalized['type_extra'];
    if (typeExtra is Map) {
      final type = normalized['type']?.toString().trim() ?? '';
      for (final entry in typeExtra.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value == null) {
          if (_isDeliveryOrderType(type) &&
              (key == 'latitude' || key == 'longitude')) {
            fields['type_extra[$key]'] = '0';
          } else {
            fields['type_extra[$key]'] = '';
          }
          continue;
        }
        fields['type_extra[$key]'] = value.toString();
      }
    }

    void addItemsToFields(String keyName, dynamic source) {
      if (source is! List || source.isEmpty) return;
      for (var i = 0; i < source.length; i++) {
        final row = source[i];
        if (row is! Map) continue;
        final item = row.map((key, value) => MapEntry(key.toString(), value));

        void addField(String fieldKey, dynamic value) {
          if (value == null) return;
          fields['$keyName[$i][$fieldKey]'] = value.toString();
        }

        addField('item_name', item['item_name'] ?? item['name']);
        addField(
          'meal_id',
          item['meal_id'] ?? item['product_id'] ?? item['productId'],
        );
        addField('price', item['price']);
        addField('unitPrice', item['unitPrice'] ?? item['unit_price']);
        addField('modified_unit_price', item['modified_unit_price']);
        addField('quantity', item['quantity']);
        addField('note', item['note'] ?? item['notes']);

        final addons = item['addons'];
        if (addons is List) {
          for (var j = 0; j < addons.length; j++) {
            final addon = addons[j];
            if (addon is Map) {
              final normalizedAddon = addon.map(
                (key, value) => MapEntry(key.toString(), value),
              );
              final addonId =
                  normalizedAddon['addon_id'] ?? normalizedAddon['id'];
              if (addonId != null) {
                fields['$keyName[$i][addons][$j][addon_id]'] =
                    addonId.toString();
              }
              if (normalizedAddon['name'] != null) {
                fields['$keyName[$i][addons][$j][name]'] =
                    normalizedAddon['name'].toString();
              }
              if (normalizedAddon['price'] != null) {
                fields['$keyName[$i][addons][$j][price]'] =
                    normalizedAddon['price'].toString();
              }
            } else if (addon != null) {
              fields['$keyName[$i][addons][$j][addon_id]'] = addon.toString();
            }
          }
        }
      }
    }

    addItemsToFields('card', normalized['card']);
    addItemsToFields('meals', normalized['meals']);

    return _createBookingWithMultipartRetry(fields);
  }

  /// Create a new booking/order
  /// [paymentType] is 'payment' for pay-now or 'later' for deferred payment
  Future<Map<String, dynamic>> createBooking(
    Map<String, dynamic> bookingData, {
    String paymentType = 'payment',
  }) async {
    // OFFLINE MODE: Save locally and queue for sync
    if (_connectivity.isOffline) {
      return _createBookingOffline(bookingData, paymentType: paymentType);
    }

    final normalizedPayload = _normalizeBookingPayload(bookingData);
    try {
      return await _createBookingWithJsonRetry(normalizedPayload);
    } on ApiException catch (e) {
      final hasMeals = normalizedPayload['meals'] is List;
      final hasCard = normalizedPayload['card'] is List;
      final needsCardFallback =
          hasMeals && !hasCard && e.message.contains('السلة');
      if (needsCardFallback) {
        final fallbackPayload = Map<String, dynamic>.from(normalizedPayload);
        fallbackPayload['card'] = fallbackPayload.remove('meals');
        try {
          return await _createBookingWithJsonRetry(fallbackPayload);
        } on ApiException catch (_) {}
        try {
          return await _createBookingMultipart(fallbackPayload);
        } on ApiException catch (_) {}
      }

      final normalizedType =
          normalizedPayload['type']?.toString().trim().toLowerCase() ?? '';
      final hasUnhandledNullMatch = (e.statusCode ?? 0) >= 500 &&
          e.message.toLowerCase().contains('unhandled match case null');

      if (hasUnhandledNullMatch) {
        final nullSafePayload = Map<String, dynamic>.from(normalizedPayload);
        final typeExtraRaw = nullSafePayload['type_extra'];
        if (typeExtraRaw is Map) {
          nullSafePayload['type_extra'] = typeExtraRaw.map(
            (key, value) => MapEntry(
              key.toString(),
              value ?? '',
            ),
          );
        }

        try {
          return await _createBookingWithJsonRetry(nullSafePayload);
        } on ApiException catch (_) {}

        try {
          return await _createBookingMultipart(nullSafePayload);
        } on ApiException catch (_) {}
      }

      if (e.statusCode == 422 &&
          _isDeliveryOrderType(normalizedType) &&
          _requiresDeliveryCoordsFallback(e.message)) {
        final deliveryFallback = _normalizeBookingPayload(
          normalizedPayload,
          forceDeliveryCoordinates: true,
        );
        try {
          return await _createBookingWithJsonRetry(deliveryFallback);
        } on ApiException catch (_) {}
        try {
          return await _createBookingMultipart(deliveryFallback);
        } on ApiException catch (_) {}
      }

      if (e.statusCode == 422 && _isInvalidType422(e.message)) {
        final candidates = _bookingTypeFallbackCandidates(normalizedType);
        for (final candidateType in candidates) {
          final typeFallbackPayload =
              Map<String, dynamic>.from(normalizedPayload)
                ..['type'] = candidateType;
          try {
            return await _createBookingWithJsonRetry(typeFallbackPayload);
          } on ApiException catch (_) {}
          try {
            return await _createBookingMultipart(typeFallbackPayload);
          } on ApiException catch (_) {}
        }
      }

      if (e.statusCode == 422) {
        try {
          return await _createBookingMultipart(normalizedPayload);
        } on ApiException catch (_) {}
      }
      rethrow;
    }
  }

  /// Create drive-through booking using official payload format.
  Future<Map<String, dynamic>> createDriveThroughBooking({
    required int customerId,
    required List<Map<String, dynamic>> card,
    String? carNumber,
    String? tableName,
    String? latitude,
    String? longitude,
  }) async {
    final payload = <String, dynamic>{
      'customer_id': customerId,
      'card': card,
      'type': 'restaurant_parking',
      'type_extra': {
        'car_number': carNumber,
        'table_name': tableName,
        'latitude': latitude,
        'longitude': longitude,
      },
    };
    return createBooking(payload);
  }

  /// Get bookings list with filters (offline-first)
  Future<Map<String, dynamic>> getBookings({
    String? status,
    String? type,
    String? dateFrom,
    String? dateTo,
    String? search,
    int page = 1,
    int perPage = 20,
    String platform = 'dashboard',
  }) async {
    // OFFLINE MODE
    if (_connectivity.isOffline) {
      return _getBookingsOffline();
    }

    // Check if token is available first
    final token = _client.getToken();
    if (token == null || token.isEmpty) {
      print('⚠️ getBookings: No token available');
      throw UnauthorizedException('No authentication token');
    }

    final queryParams = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
      'platform': platform,
    };
    if (status != null && status.isNotEmpty) queryParams['status'] = status;
    if (type != null) queryParams['type'] = type;
    if (dateFrom != null) queryParams['date_from'] = dateFrom;
    if (dateTo != null) queryParams['date_to'] = dateTo;
    if (search != null && search.isNotEmpty) queryParams['search'] = search;

    final queryString = Uri(queryParameters: queryParams).query;
    final endpoint = queryString.isNotEmpty
        ? '${ApiConstants.bookingsEndpoint}?$queryString'
        : ApiConstants.bookingsEndpoint;
    final cacheKey = 'bookings_${[dateFrom, dateTo, status, search].join('_')}';

    try {
      final response = await _client.get(endpoint);
      final normalized = _rememberResponse('get_all_orders', response);
      if (response != null && page == 1) {
        // Cache the result for resilience
        await _cache.set(
          cacheKey,
          normalized,
          expiry: const Duration(minutes: 30),
        );
        // Save to SQLite for offline
        if (normalized['data'] is List) {
          await _offlineDb.saveServerOrders(
            (normalized['data'] as List).cast<Map<String, dynamic>>(),
            ApiConstants.branchId,
          );
        }
      }
      return normalized;
    } catch (e) {
      // Fallback to offline
      final offline = await _getBookingsOffline();
      if ((offline['data'] as List?)?.isNotEmpty == true) return offline;
      if (page == 1) {
        final cached = await _cache.get(cacheKey);
        if (cached != null) return cached;
      }
      rethrow;
    }
  }

  BookingSettings _emptyBookingSettings() {
    // Safe runtime defaults when backend create-metadata endpoint is unstable.
    return BookingSettings(
      typeOptions: [
        OptionItem(label: 'استلام من الفرع', value: 'restaurant_pickup'),
        OptionItem(label: 'داخل المطعم', value: 'restaurant_internal'),
        OptionItem(label: 'توصيل', value: 'restaurant_delivery'),
        OptionItem(label: 'سيارة', value: 'restaurant_parking'),
      ],
      tableOptions: [],
    );
  }

  String _buildBookingCreateMetadataEndpointWithDefaults() {
    // Backend create endpoint expects these filters; calling without them
    // may trigger "Unhandled match case NULL" on some branches.
    final query = Uri(queryParameters: <String, String>{
      'type': 'meals',
      'is_favourite': '0',
      'category_id': '',
      'is_home': '0',
      'is_delivery': '0',
      'page': '1',
      'search': '',
      'limit': '100',
      'per_page': '100',
    }).query;
    return '${ApiConstants.bookingCreateMetadataEndpoint}?$query';
  }

  BookingSettings? _parseBookingSettingsResponse(dynamic response) {
    final normalized = _ensureMapResponse(response);
    final data = normalized['data'];

    if (data is Map) {
      final mapped = data.map((key, value) => MapEntry(key.toString(), value));
      if (mapped['typeOptions'] is List || mapped['tableOptions'] is List) {
        return BookingSettings.fromJson({'data': mapped});
      }
    }

    if (normalized['typeOptions'] is List ||
        normalized['tableOptions'] is List) {
      return BookingSettings.fromJson({
        'data': {
          'typeOptions': normalized['typeOptions'] ?? const [],
          'tableOptions': normalized['tableOptions'] ?? const [],
        },
      });
    }

    return null;
  }

  Map<String, dynamic> _serializeBookingSettings(BookingSettings settings) {
    return <String, dynamic>{
      'data': {
        'typeOptions': settings.typeOptions
            .map((option) => {'label': option.label, 'value': option.value})
            .toList(),
        'tableOptions': settings.tableOptions
            .map((option) => {'label': option.label, 'value': option.value})
            .toList(),
      },
    };
  }

  /// Get booking settings (types and tables)
  Future<BookingSettings> getBookingSettings() async {
    final token = _client.getToken();
    if (token == null || token.isEmpty) {
      print('⚠️ getBookingSettings: No token available');
      return _emptyBookingSettings();
    }
    if (ApiConstants.branchId <= 0) {
      print('⚠️ getBookingSettings: branchId is 0');
      return _emptyBookingSettings();
    }

    final disabledFlag =
        await _cache.get(_bookingCreateMetadataDisabledCacheKey);
    if (disabledFlag == true) {
      _skipBookingCreateMetadataEndpoint = true;
    }

    final createEndpoint = _buildBookingCreateMetadataEndpointWithDefaults();
    final endpoints = <String>[
      if (!_skipBookingCreateMetadataEndpoint) createEndpoint,
      ApiConstants.bookingsEndpoint,
    ];
    BookingSettings? fallback;

    for (final endpoint in endpoints) {
      try {
        final response = await _client.get(endpoint);

        // 🔍 DEBUG: Print and save raw API response
        print('=' * 70);
        print('🔍 DEBUG: Booking Settings Raw API Response');
        print('📍 Endpoint: $endpoint');

        // Save to file for analysis
        try {
          final file = File('BOOKING_SETTINGS_RAW_RESPONSE.json');
          await file.writeAsString(
            const JsonEncoder.withIndent('  ').convert(response),
          );
          print('💾 Response saved to: BOOKING_SETTINGS_RAW_RESPONSE.json');
        } catch (e) {
          print('⚠️  Could not save response to file: $e');
        }

        print('=' * 70);

        final parsed = _parseBookingSettingsResponse(response);
        if (parsed == null) continue;

        fallback ??= parsed;
        final hasOptions =
            parsed.typeOptions.isNotEmpty || parsed.tableOptions.isNotEmpty;
        if (!hasOptions) continue;

        await _cache.set(
          'booking_settings',
          _serializeBookingSettings(parsed),
          expiry: const Duration(hours: 12),
        );
        return parsed;
      } catch (e) {
        if (endpoint == createEndpoint) {
          final lower = e.toString().toLowerCase();
          final isBackendBug = lower.contains('unhandled match case null') ||
              (e is ApiException && (e.statusCode ?? 0) >= 500);
          if (isBackendBug) {
            _skipBookingCreateMetadataEndpoint = true;
            await _cache.set(
              _bookingCreateMetadataDisabledCacheKey,
              true,
              expiry: const Duration(hours: 6),
            );
            print(
              '⚠️ booking/create metadata endpoint disabled for this session due to backend 5xx.',
            );
          }
        }
        print('⚠️ getBookingSettings failed endpoint=$endpoint error=$e');
      }
    }

    if (fallback != null) {
      await _cache.set(
        'booking_settings',
        _serializeBookingSettings(fallback),
        expiry: const Duration(hours: 12),
      );
      return fallback;
    }

    final cached = await _cache.get('booking_settings');
    if (cached is Map<String, dynamic>) {
      return BookingSettings.fromJson(cached);
    }
    if (cached is Map) {
      return BookingSettings.fromJson(
        cached.map((key, value) => MapEntry(key.toString(), value)),
      );
    }

    final safeFallback = _emptyBookingSettings();
    await _cache.set(
      'booking_settings',
      _serializeBookingSettings(safeFallback),
      expiry: const Duration(hours: 12),
    );
    return safeFallback;
  }

  /// Get create booking page data (for form options)
  Future<Map<String, dynamic>> getBookingCreateData() async {
    final response = await _client.get(
      '${ApiConstants.bookingsEndpoint}/create',
    );
    return _rememberResponse('get_booking_create_data', response);
  }

  /// Create invoice (enriches items from booking details + multipart retry)
  Future<Map<String, dynamic>> createInvoice(
    Map<String, dynamic> invoiceData,
  ) async {
    // OFFLINE MODE: Save invoice locally and queue for sync
    if (_connectivity.isOffline) {
      final localId = await _offlineDb.saveLocalInvoice(
          invoiceData, ApiConstants.branchId);
      await _offlineDb.addToSyncQueue(
        operation: 'CREATE_INVOICE',
        endpoint: ApiConstants.invoicesEndpoint,
        method: 'POST',
        payload: invoiceData,
        localRefTable: 'invoices',
        localRefId: localId,
      );
      return _rememberResponse('create_invoice', {
        'status': 200,
        'data': {'id': localId, '_is_local': true, ...invoiceData},
      });
    }

    final enrichedInvoiceData = await _ensureInvoiceItems(invoiceData);
    final normalizedInvoiceData = _normalizeInvoicePayloadForPostman(
      enrichedInvoiceData,
    );
    try {
      final response = await _client.post(
        ApiConstants.invoicesEndpoint,
        normalizedInvoiceData,
      );
      return _rememberResponse('create_invoice', response);
    } on ApiException catch (e) {
      final status = e.statusCode ?? 0;
      final message = e.userMessage ?? e.message;
      final hasItems = _hasInvoiceItems(enrichedInvoiceData);
      final needsMultipart =
          status == 422 && message.contains('عناصر') && hasItems;
      if (!needsMultipart) rethrow;
      // Retry using multipart/form-data
      return createInvoiceMultipart(enrichedInvoiceData);
    }
  }

  /// Create invoice using multipart/form-data
  /// Some branches validate nested pays only in multipart keys (pays[0][...]).
  Future<Map<String, dynamic>> createInvoiceMultipart(
    Map<String, dynamic> invoiceData,
  ) async {
    final fields = <String, String>{
      if (invoiceData['customer_id'] != null)
        'customer_id': invoiceData['customer_id'].toString(),
      'branch_id':
          (invoiceData['branch_id'] ?? ApiConstants.branchId).toString(),
      if (invoiceData['order_id'] != null)
        'order_id': invoiceData['order_id'].toString(),
      if (invoiceData['booking_id'] != null)
        'booking_id': invoiceData['booking_id'].toString(),
      if (invoiceData['booking_product_id'] != null)
        'booking_product_id': invoiceData['booking_product_id'].toString(),
      if (invoiceData['parent_invoice_id'] != null)
        'parent_invoice_id': invoiceData['parent_invoice_id'].toString(),
      if (invoiceData['promocode_id'] != null)
        'promocode_id': invoiceData['promocode_id'].toString(),
      if (invoiceData['deposit_id'] != null)
        'deposit_id': invoiceData['deposit_id'].toString(),
      if (invoiceData['date'] != null) 'date': invoiceData['date'].toString(),
      'cash_back': (invoiceData['cash_back'] ?? 0).toString(),
      if (invoiceData['promocodeValue'] != null)
        'promocodeValue': invoiceData['promocodeValue'].toString(),
      if (invoiceData['type'] != null) 'type': invoiceData['type'].toString(),
    };
    fields.addAll(_withOrderIdentifierCompatFields(invoiceData));

    final typeExtra = invoiceData['type_extra'];
    if (typeExtra is Map) {
      final normalized = typeExtra.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      for (final entry in normalized.entries) {
        if (entry.value == null) continue;
        fields['type_extra[${entry.key}]'] = entry.value.toString();
      }
    }

    void addItemsToFields(String keyName, dynamic source) {
      if (source is! List || source.isEmpty) return;
      for (var i = 0; i < source.length; i++) {
        final row = source[i];
        if (row is! Map) continue;
        final item = row.map((key, value) => MapEntry(key.toString(), value));
        void addField(String fieldKey, dynamic value) {
          if (value == null) return;
          fields['$keyName[$i][$fieldKey]'] = value.toString();
        }

        addField('item_name', item['item_name'] ?? item['name']);
        addField('meal_id', item['meal_id']);
        addField('price', item['price']);
        addField('unitPrice', item['unitPrice'] ?? item['unit_price']);
        addField('modified_unit_price', item['modified_unit_price']);
        addField('quantity', item['quantity']);
        addField('note', item['note'] ?? item['notes']);

        final addons = item['addons'];
        if (addons is List) {
          for (var j = 0; j < addons.length; j++) {
            final addon = addons[j];
            if (addon is Map) {
              final normalizedAddon = addon.map(
                (key, value) => MapEntry(key.toString(), value),
              );
              final addonId =
                  normalizedAddon['addon_id'] ?? normalizedAddon['id'];
              if (addonId != null) {
                fields['$keyName[$i][addons][$j][addon_id]'] =
                    addonId.toString();
              }
              if (normalizedAddon['name'] != null) {
                fields['$keyName[$i][addons][$j][name]'] =
                    normalizedAddon['name'].toString();
              }
              if (normalizedAddon['price'] != null) {
                fields['$keyName[$i][addons][$j][price]'] =
                    normalizedAddon['price'].toString();
              }
            } else if (addon != null) {
              // Backward compatibility: addons as plain id list.
              fields['$keyName[$i][addons][$j][addon_id]'] = addon.toString();
            }
          }
        }
      }
    }

    addItemsToFields('card', invoiceData['card']);
    addItemsToFields('items', invoiceData['items']);
    addItemsToFields('meals', invoiceData['meals']);
    addItemsToFields('sales_meals', invoiceData['sales_meals']);

    final pays = invoiceData['pays'];
    if (pays is List && pays.isNotEmpty) {
      for (var i = 0; i < pays.length; i++) {
        final pay = pays[i];
        if (pay is! Map) continue;
        final normalized = pay.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        fields['pays[$i][name]'] =
            (normalized['name'] ?? normalized['pay_method'] ?? 'cash')
                .toString();
        fields['pays[$i][pay_method]'] =
            (normalized['pay_method'] ?? 'cash').toString();
        fields['pays[$i][amount]'] = (normalized['amount'] ?? 0).toString();
        fields['pays[$i][index]'] = (normalized['index'] ?? i).toString();
      }
    }

    final response = await _client.postMultipart(
      ApiConstants.invoicesEndpoint,
      fields,
    );
    return _rememberResponse('create_invoice', response);
  }

  /// Calculate invoice totals
  Future<Map<String, dynamic>> calculateInvoice(
    Map<String, dynamic> invoiceData,
  ) async {
    try {
      final response = await _client.post(
        ApiConstants.calculateInvoiceEndpoint,
        invoiceData,
      );
      return _rememberResponse('calculate_invoice', response);
    } on ApiException catch (e) {
      final hasItems = invoiceData['items'] is List;
      final hasCard = invoiceData['card'] is List;
      final needsCardFallback =
          hasItems && !hasCard && e.message.contains('السلة');
      if (!needsCardFallback) rethrow;

      final fallbackPayload = Map<String, dynamic>.from(invoiceData);
      fallbackPayload['card'] = fallbackPayload.remove('items');
      final response = await _client.post(
        ApiConstants.calculateInvoiceEndpoint,
        fallbackPayload,
      );
      return _rememberResponse('calculate_invoice', response);
    }
  }

  /// Get invoices list
  Future<Map<String, dynamic>> getInvoices({
    String? dateFrom,
    String? dateTo,
    String? status,
    String? search,
    String? invoiceType,
    int page = 1,
    int perPage = 20,
  }) async {
    // Check if token is available first
    final token = _client.getToken();
    if (token == null || token.isEmpty) {
      print('⚠️ getInvoices: No token available');
      throw UnauthorizedException('No authentication token');
    }

    final queryParams = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (dateFrom != null) queryParams['date_from'] = dateFrom;
    if (dateTo != null) queryParams['date_to'] = dateTo;
    if (status != null && status.isNotEmpty) queryParams['status'] = status;
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    if (invoiceType != null && invoiceType.isNotEmpty) {
      queryParams['invoice_type'] = invoiceType;
    }

    final queryString =
        queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');
    final endpoint = '${ApiConstants.invoicesEndpoint}?$queryString';

    try {
      final response = await _client.get(endpoint);
      final normalized = _rememberResponse('get_invoices', response);
      if (response != null && page == 1) {
        await _cache.set(
          'invoices_${dateFrom}_$dateTo',
          normalized,
          expiry: const Duration(minutes: 30),
        );
      }
      return normalized;
    } catch (e) {
      if (page == 1) {
        final cached = await _cache.get('invoices_${dateFrom}_$dateTo');
        if (cached != null) return cached;
      }
      rethrow;
    }
  }

  /// Get single invoice details
  Future<Map<String, dynamic>> getInvoice(String invoiceId) async {
    final response = await _client.get(
      ApiConstants.invoiceDetailsEndpoint(invoiceId),
    );
    return _rememberResponse('get_invoice_details', response);
  }

  /// Get invoice helper details (alternative endpoint)
  Future<Map<String, dynamic>> getInvoiceHelper(String invoiceId) async {
    final response = await _client.get(
      '/seller/helpers/branches/${ApiConstants.branchId}/invoices/$invoiceId',
    );
    return _rememberResponse('get_invoice_helper', response);
  }

  /// Get booking invoice
  Future<Map<String, dynamic>> getBookingInvoice(String orderId) async {
    final response = await _client.get(
      ApiConstants.bookingInvoiceEndpoint(orderId),
    );
    return _rememberResponse('get_order_invoices', response);
  }

  /// Get booking/order details
  Future<Map<String, dynamic>> getBookingDetails(String orderId) async {
    final normalizedOrderId = _normalizeBookingIdOrThrow(orderId);
    try {
      final response = await _client.get(
        ApiConstants.bookingDetailsEndpoint(normalizedOrderId),
      );
      return _rememberResponse('get_order_details', response);
    } on ApiException catch (e) {
      final message = e.message.toLowerCase();
      final routeNotFound =
          e.statusCode == 404 && message.contains('route_not_found');
      final bookingItemsError =
          e.statusCode == 500 && message.contains('booking_items');

      if (routeNotFound || bookingItemsError) {
        try {
          final servicesEndpoint =
              '/seller/services/branches/${ApiConstants.branchId}/bookings/$normalizedOrderId';
          final servicesResponse = await _client.get(servicesEndpoint);
          return _rememberResponse('get_order_details', servicesResponse);
        } on ApiException {
          // Continue to graceful fallback below.
        }
      }

      if (routeNotFound || bookingItemsError || e.statusCode == 404) {
        try {
          final fromList =
              await _lookupBookingDetailsFromList(normalizedOrderId);
          if (fromList != null) {
            return fromList;
          }
        } on ApiException {
          // Continue to graceful fallback below.
        }
      }

      if (e.statusCode == 500 && message.contains('booking_items')) {
        return _rememberResponse('get_order_details', {
          'status': 500,
          'message':
              'تعذر جلب تفاصيل الطلب الآن بسبب مشكلة مؤقتة في الخادم، وتم متابعة العمل بالبيانات المتاحة.',
          'data': {
            'id': int.tryParse(normalizedOrderId) ?? normalizedOrderId,
            'order_id': int.tryParse(normalizedOrderId) ?? normalizedOrderId,
            'booking_id': int.tryParse(normalizedOrderId) ?? normalizedOrderId,
            'meals': <dynamic>[],
          },
        });
      }
      rethrow;
    }
  }

  /// Update booking status
  /// API contract differs by environment. Try multiple compatible payload forms.
  Future<Map<String, dynamic>> updateBookingStatus({
    required String orderId,
    required int status,
  }) async {
    final normalizedOrderId = _normalizeBookingIdOrThrow(orderId);
    final primaryEndpoint =
        '/seller/branches/${ApiConstants.branchId}/status/bookings/$normalizedOrderId';
    final legacyEndpoint =
        '/seller/status/branches/${ApiConstants.branchId}/bookings/$normalizedOrderId';
    final statusValue = status.toString();

    // Keep attempts limited to avoid rate limiting.
    final attempts = <Future<dynamic> Function()>[
      () => _client.put(primaryEndpoint, {
            'status': statusValue,
          }),
      () => _client.patch(primaryEndpoint, {
            'status': statusValue,
          }),
      () => _client.patchMultipart(primaryEndpoint, {
            'status': statusValue,
          }),
      () => _client.patchMultipart(legacyEndpoint, {
            'status': statusValue,
          }),
      () => _client.patch(legacyEndpoint, {
            'status': statusValue,
          }),
    ];

    ApiException? lastApiError;
    Object? lastTransportError;

    for (var i = 0; i < attempts.length; i++) {
      final hasMoreAttempts = i < attempts.length - 1;
      try {
        final response = await attempts[i]();
        return _rememberResponse('update_order_status', response);
      } on ApiException catch (e) {
        lastApiError = e;
        // Don't retry on rate limiting errors (422 with "Too Many Attempts")
        if (e.statusCode == 422 &&
            (e.message.contains('Too Many') ||
                e.message.contains('محاولات كثيرة'))) {
          print('⚠️ Rate limited on updateBookingStatus - skipping retries');
          rethrow;
        }
        if (!hasMoreAttempts || !_shouldRetryStatusUpdate(e)) {
          rethrow;
        }
        final attemptNo = i + 1;
        print(
          '⚠️ updateBookingStatus attempt $attemptNo/${attempts.length} failed with ${e.statusCode}: ${e.message}. Trying alternate request format.',
        );
      } catch (e) {
        lastTransportError = e;
        if (!hasMoreAttempts || !_isRetryableBookingTransportError(e)) {
          rethrow;
        }
        final attemptNo = i + 1;
        print(
          '⚠️ updateBookingStatus transport issue on attempt $attemptNo/${attempts.length}: $e. Retrying with alternate request format.',
        );
      }
    }

    if (lastApiError != null) throw lastApiError;
    if (lastTransportError != null) throw lastTransportError;
    throw ApiException('Unable to update booking status');
  }

  /// Refund order preview (source of truth endpoint)
  /// API: GET /seller/refund/branches/{branchId}/bookings/{orderId}
  Future<Map<String, dynamic>> showBookingRefund(String orderId) async {
    final normalizedOrderId = _normalizeBookingIdOrThrow(orderId);
    return _getWithFallbackEndpoints(
      _bookingRefundEndpoints(normalizedOrderId),
      responseKey: 'show_booking_refund',
    );
  }

  /// Process order refund (source of truth endpoint)
  /// API: PATCH /seller/refund/branches/{branchId}/bookings/{orderId}
  Future<Map<String, dynamic>> processBookingRefund({
    required String orderId,
    Map<String, dynamic> payload = const {},
  }) async {
    final normalizedOrderId = _normalizeBookingIdOrThrow(orderId);
    final normalizedPayload = Map<String, dynamic>.from(payload);

    print('🔍 DEBUG processBookingRefund:');
    print('  orderId: $orderId');
    print('  normalizedOrderId: $normalizedOrderId');
    print('  input payload: $payload');

    // Set refund_reason if not provided
    final reason = normalizedPayload['refund_reason']?.toString().trim() ?? '';
    if (reason.isEmpty) {
      normalizedPayload['refund_reason'] = 'طلب العميل';
    }

    // Backend requires 'refund' field as array with IDs
    // Get refund array from payload or resolve from preview
    final refundArray = await _resolveBookingRefundArray(
      normalizedOrderId: normalizedOrderId,
      providedRefund: normalizedPayload['refund'],
    );

    print('  resolved refundArray: $refundArray');
    print('  refundArray.isEmpty: ${refundArray.isEmpty}');

    // Check if refund array is empty - this means no items to refund
    if (refundArray.isEmpty) {
      throw ApiException(
        'لا توجد عناصر قابلة للاسترجاع في هذا الطلب. قد يكون الطلب تم استرجاعه بالفعل أو تم تحويله إلى فاتورة.',
        statusCode: 422,
        userMessage:
            'لا يمكن استرجاع هذا الطلب. قد يكون تم استرجاعه بالفعل أو تم دفعه.',
      );
    }

    // Backend requires 'refund' field as array (cannot be empty!)
    normalizedPayload['refund'] = refundArray;

    print('  final payload: $normalizedPayload');

    return _patchWithFallbackEndpoints(
      _bookingRefundEndpoints(normalizedOrderId),
      normalizedPayload,
      responseKey: 'process_booking_refund',
    );
  }

  /// Send WhatsApp message for a single booking.
  /// API: POST /seller/booking/send-whatsapp/{orderId}
  Future<Map<String, dynamic>> sendOrderWhatsApp({
    required String orderId,
    required String message,
  }) async {
    final response = await _client.post(
      ApiConstants.sendOrderWhatsAppEndpoint(orderId),
      {'message': message},
    );
    return _rememberResponse('send_order_whatsapp', response);
  }

  /// Send WhatsApp message for multiple bookings.
  /// API: POST /seller/booking/send-multi-whatsapp/{branchId}
  Future<Map<String, dynamic>> sendMultiOrdersWhatsApp({
    required List<int> orderIds,
    required String message,
  }) async {
    final response = await _client.post(
      ApiConstants.sendMultiOrdersWhatsAppEndpoint(),
      {'order_ids': orderIds, 'message': message},
    );
    return _rememberResponse('send_multi_orders_whatsapp', response);
  }

  /// Update booking data (table name / notes)
  Future<Map<String, dynamic>> updateBookingData({
    required String orderId,
    String? tableName,
    String? notes,
  }) async {
    final endpoint = '/seller/update-booking-data/$orderId';
    final payload = <String, dynamic>{};
    if (tableName != null) payload['table_name'] = tableName;
    if (notes != null) payload['notes'] = notes;

    final response = await _client.post(endpoint, payload);
    return _rememberResponse('update_order_data', response);
  }

  /// Update print count for booking
  Future<void> updateBookingPrintCount(String orderId) async {
    await _client.post(ApiConstants.bookingPrintCountEndpoint(orderId), {});
  }

  /// Generate kitchen receipt from backend by booking.
  /// Source of truth contract (Postman):
  /// POST /seller/kitchen-receipts/generate-by-booking
  /// body: { "booking_id": <id>, "kitchen_id": <id> }
  Future<Map<String, dynamic>> generateKitchenReceiptByBooking({
    required String bookingId,
    required int kitchenId,
  }) async {
    final normalizedBookingId = _normalizeBookingIdOrThrow(bookingId);
    final safeKitchenId = kitchenId <= 0 ? 1 : kitchenId;

    final response = await _client.post(
      ApiConstants.kitchenReceiptGenerateByBookingEndpoint,
      {
        'booking_id': int.tryParse(normalizedBookingId) ?? normalizedBookingId,
        'kitchen_id': safeKitchenId,
      },
    );
    return _rememberResponse('generate_kitchen_receipt', response);
  }

  /// Refund invoice preview (show only)
  Future<Map<String, dynamic>> showInvoiceRefund(String invoiceId) async {
    final response = await _client.get(ApiConstants.invoiceRefundEndpoint(
      invoiceId,
    ));
    return _rememberResponse('show_invoice_refund', response);
  }

  /// Refund an invoice (backward compatible alias for show endpoint)
  Future<Map<String, dynamic>> refundInvoice(String invoiceId) async {
    return showInvoiceRefund(invoiceId);
  }

  /// Process invoice refund
  /// API: PATCH /seller/refund/branches/{branchId}/invoices/{invoiceId}
  Future<Map<String, dynamic>> processInvoiceRefund({
    required String invoiceId,
    Map<String, dynamic> payload = const {},
  }) async {
    final normalizedPayload = Map<String, dynamic>.from(payload);
    final reason = normalizedPayload['refund_reason']?.toString().trim() ?? '';
    if (reason.isEmpty) {
      normalizedPayload['refund_reason'] = 'طلب العميل';
    }

    final endpoint = ApiConstants.invoiceRefundEndpoint(invoiceId);
    Future<Map<String, dynamic>> submitPatch(
      Map<String, dynamic> patchPayload,
    ) async {
      try {
        final response = await _client.patch(endpoint, patchPayload);
        return _rememberResponse('process_invoice_refund', response);
      } on ApiException catch (e) {
        final lowerMessage = e.message.toLowerCase();
        final expectsMultipart = e.statusCode == 415 ||
            lowerMessage.contains('multipart') ||
            lowerMessage.contains('content type') ||
            lowerMessage.contains('unsupported media');
        if (!expectsMultipart) rethrow;

        final fields = <String, String>{};
        patchPayload.forEach((key, value) {
          if (value == null) return;
          if (value is Map || value is List) {
            fields[key] = jsonEncode(value);
            return;
          }
          fields[key] = value.toString();
        });
        final response = await _client.patchMultipart(endpoint, fields);
        return _rememberResponse('process_invoice_refund', response);
      }
    }

    try {
      return await submitPatch(normalizedPayload);
    } on ApiException catch (e) {
      if (!_isInvoiceRefundContractMismatch(e)) rethrow;
      final compatiblePayload = await _buildInvoiceRefundCompatiblePayload(
        invoiceId: invoiceId,
        originalPayload: normalizedPayload,
      );
      return submitPatch(compatiblePayload);
    }
  }

  /// Update invoice payment methods
  Future<Map<String, dynamic>> updateInvoicePays(
    String invoiceId, {
    required List<Map<String, dynamic>> pays,
    required String date,
  }) async {
    final payload = <String, dynamic>{'pays': pays, 'date': date};
    final response = await _client.patch(
      '/seller/updatePays/branches/${ApiConstants.branchId}/invoices/$invoiceId',
      payload,
    );
    return _rememberResponse('update_invoice_pays', response);
  }

  /// Update invoice employees
  Future<Map<String, dynamic>> updateInvoiceEmployees(
    String invoiceId, {
    required List<int> employeeIds,
  }) async {
    final response = await _client.patch(
      ApiConstants.invoiceEmployeesEndpoint(invoiceId),
      {'employee_ids': employeeIds},
    );
    return _rememberResponse('update_invoice_employees', response);
  }

  /// Update invoice date
  Future<Map<String, dynamic>> updateInvoiceDate({
    required String invoiceId,
    required String date,
  }) async {
    final response = await _client.put(
      '/seller/branches/${ApiConstants.branchId}/invoices/$invoiceId/update-date',
      {'date': date},
    );
    return _rememberResponse('update_invoice_date', response);
  }

  String _toAbsolutePdfUrl(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final needsSlash = !trimmed.startsWith('/');
    return '${ApiConstants.baseUrl}${needsSlash ? '/' : ''}$trimmed';
  }

  bool _looksLikePdfPath(String value) {
    final lower = value.toLowerCase();
    if (lower.endsWith('.pdf')) return true;
    return lower.contains('/pdf');
  }

  String? _extractPdfUrlFromDynamic(dynamic node, {int depth = 0}) {
    if (node == null || depth > 6) return null;

    if (node is String) {
      final value = node.trim();
      if (value.isEmpty || !_looksLikePdfPath(value)) return null;
      return _toAbsolutePdfUrl(value);
    }

    if (node is List) {
      for (final item in node) {
        final extracted = _extractPdfUrlFromDynamic(item, depth: depth + 1);
        if (extracted != null && extracted.isNotEmpty) return extracted;
      }
      return null;
    }

    if (node is Map) {
      final map = node.map((k, v) => MapEntry(k.toString(), v));
      const preferredKeys = [
        'pdf_url',
        'receipt',
        'receipt_url',
        'invoice_pdf',
        'pdf',
        'pdfPath',
        'pdf_path',
        'file',
        'url',
      ];

      for (final key in preferredKeys) {
        final candidate = map[key];
        final extracted = _extractPdfUrlFromDynamic(
          candidate,
          depth: depth + 1,
        );
        if (extracted != null && extracted.isNotEmpty) return extracted;
      }

      for (final entry in map.entries) {
        final extracted = _extractPdfUrlFromDynamic(
          entry.value,
          depth: depth + 1,
        );
        if (extracted != null && extracted.isNotEmpty) return extracted;
      }
    }

    return null;
  }

  bool _isMissingClientPdfBug(ApiException error) {
    final message = error.message.toLowerCase();
    return message.contains('undefined array key') &&
        message.contains('client');
  }

  Future<String?> _resolvePdfUrlFromInvoiceDetails(String invoiceId) async {
    Future<Map<String, dynamic>> loadDetails() => getInvoice(invoiceId);
    Future<Map<String, dynamic>> loadHelper() => getInvoiceHelper(invoiceId);
    final loaders = <Future<Map<String, dynamic>> Function()>[
      loadDetails,
      loadHelper,
    ];

    for (final loader in loaders) {
      try {
        final response = await loader();
        final extracted = _extractPdfUrlFromDynamic(response);
        if (extracted != null && extracted.isNotEmpty) {
          return extracted;
        }
      } on ApiException catch (e) {
        final isNotFound = (e.statusCode ?? 0) == 404 ||
            e.message.toLowerCase().contains('route_not_found');
        if (!isNotFound) {
          // Continue trying alternative sources when available.
          continue;
        }
      } catch (_) {
        // Continue trying alternative sources when available.
      }
    }

    return null;
  }

  /// Get invoice PDF metadata / response
  Future<Map<String, dynamic>> getInvoicePdf(String invoiceId) async {
    final endpoint = ApiConstants.invoicePdfEndpoint(invoiceId);
    final endpointUrl = '${ApiConstants.baseUrl}$endpoint';
    try {
      final response = await _client.get(endpoint);
      final normalized = _rememberResponse('get_invoice_pdf', response);
      final extractedPdfUrl = _extractPdfUrlFromDynamic(normalized);

      if (extractedPdfUrl != null && extractedPdfUrl.isNotEmpty) {
        normalized['pdf_url'] = extractedPdfUrl;
      } else {
        // Backward-compatible fallback for environments that still return
        // a direct PDF response without metadata.
        normalized['pdf_url'] = endpointUrl;
      }

      normalized['pdf_endpoint'] = endpointUrl;
      return normalized;
    } on ApiException catch (e) {
      if (_isMissingClientPdfBug(e)) {
        final fallbackPdfUrl =
            await _resolvePdfUrlFromInvoiceDetails(invoiceId);
        if (fallbackPdfUrl != null && fallbackPdfUrl.isNotEmpty) {
          return _rememberResponse('get_invoice_pdf', {
            'status': 200,
            'message': 'resolved_from_invoice_details',
            'pdf_url': fallbackPdfUrl,
            'pdf_endpoint': endpointUrl,
            'fallback': true,
          });
        }
      }
      rethrow;
    }
  }

  /// Get invoice PDF endpoint that also triggers WhatsApp flow on backend.
  Future<Map<String, dynamic>> getInvoicePdfWithWhatsApp(
      String invoiceId) async {
    final endpoint = ApiConstants.invoicePdfWithWhatsAppEndpoint(invoiceId);
    final endpointUrl = '${ApiConstants.baseUrl}$endpoint';
    final response = await _client.get(endpoint);
    final normalized = _rememberResponse('get_invoice_pdf_whatsapp', response);
    final extractedPdfUrl = _extractPdfUrlFromDynamic(normalized);
    if (extractedPdfUrl != null && extractedPdfUrl.isNotEmpty) {
      normalized['pdf_url'] = extractedPdfUrl;
    } else {
      normalized['pdf_url'] = endpointUrl;
    }
    normalized['pdf_endpoint'] = endpointUrl;
    return normalized;
  }

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
        for (var j = 0; j < addons.length; j++) {
          final addon = addons[j];
          if (addon is Map) {
            final normalized = addon.map((k, v) => MapEntry(k.toString(), v));
            final addonId = normalized['addon_id'] ?? normalized['id'];
            if (addonId != null) {
              fields['card[$i][addons][$j]'] = addonId.toString();
            }
          } else if (addon != null) {
            fields['card[$i][addons][$j]'] = addon.toString();
          }
        }
      }
    }

    final response = await _client.postMultipart(endpoint, fields);
    return _rememberResponse('update_booking_items', response);
  }

  // ═══════════════════════════════════════════════════════════════════
  //  OFFLINE HELPERS
  // ═══════════════════════════════════════════════════════════════════

  /// Create a booking offline - save to local DB and sync queue
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
