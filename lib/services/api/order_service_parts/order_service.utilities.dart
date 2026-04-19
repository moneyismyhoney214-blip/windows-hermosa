// ignore_for_file: unused_element, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../order_service.dart';

extension OrderServiceUtilities on OrderService {
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

}
