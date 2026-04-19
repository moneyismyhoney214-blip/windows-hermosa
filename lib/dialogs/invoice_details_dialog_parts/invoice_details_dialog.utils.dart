// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../invoice_details_dialog.dart';

extension InvoiceDetailsDialogUtils on _InvoiceDetailsDialogState {
  double _parsePrice(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      var cleaned = value.replaceAll(',', '').trim();
      final currency = ApiConstants.currency.trim();
      if (currency.isNotEmpty) {
        cleaned = cleaned.replaceAll(currency, '');
      }
      cleaned = cleaned
          .replaceAll('SAR', '')
          .replaceAll('QAR', '')
          .replaceAll('RS', '')
          .replaceAll('ر.س', '')
          .replaceAll(RegExp(r'[^\d.\-]'), '');
      return double.tryParse(cleaned) ?? 0.0;
    }
    return 0.0;
  }

  String _formatRefundAmount(double value) {
    final safe = value <= 0 ? 0.0 : value;
    return safe.toStringAsFixed(2);
  }

  String _formatRefundCandidateSubtitle(_RefundCandidate candidate) {
    final parts = <String>[];
    if (candidate.quantity > 0) {
      parts.add('الكمية: ${candidate.quantity}');
    }
    if (candidate.total > 0) {
      parts.add(
        'الإجمالي: ${candidate.total.toStringAsFixed(2)} ${ApiConstants.currency}',
      );
    }
    if (parts.isEmpty) {
      parts.add('رقم العنصر: ${candidate.id}');
    }
    return parts.join(' • ');
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  List<Map<String, dynamic>> _extractItems(
    Map<String, dynamic> data,
    Map<String, dynamic> payload,
  ) {
    List<Map<String, dynamic>> normalizeList(dynamic source) {
      if (source is! List) return const [];
      return source
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }

    final possibleKeys = [
      'meals',
      'booking_meals',
      'booking_products',
      'sales_meals',
      'items',
      'invoice_items',
      'products',
      'order_items',
      'card',
      'cart',
    ];
    final nodes = [data, payload];

    for (final node in nodes) {
      for (final key in possibleKeys) {
        final items = normalizeList(node[key]);
        if (items.isNotEmpty) {
          return items.map((row) {
            final meal = _asMap(row['meal']) ?? const <String, dynamic>{};
            return <String, dynamic>{
              ...row,
              if (row['meal_name'] == null &&
                  meal['name']?.toString().isNotEmpty == true)
                'meal_name': meal['name'],
              if (row['quantity'] == null) 'quantity': 1,
              if (row['unit_price'] == null && row['price'] != null)
                'unit_price': row['price'],
              if (row['total'] == null && row['price'] != null)
                'total': row['price'],
            };
          }).toList();
        }
      }
    }

    final nestedCandidates = [
      data['data'],
      data['booking'],
      data['invoice'],
      payload['data'],
      payload['booking'],
      payload['invoice'],
    ];
    for (final candidate in nestedCandidates) {
      final nested = _asMap(candidate);
      if (nested == null) continue;
      final extracted = _extractItems(nested, const <String, dynamic>{});
      if (extracted.isNotEmpty) return extracted;
    }

    return [];
  }

  List<_RefundCandidate> _extractRefundCandidates(
    Map<String, dynamic> data,
    Map<String, dynamic> payload,
    Map<String, dynamic> previewPayload,
  ) {
    final candidates = <_RefundCandidate>[];

    void addCandidate({
      required _RefundCandidateType type,
      required int id,
      required String name,
      required double total,
      required int quantity,
    }) {
      if (id <= 0) return;
      candidates.add(
        _RefundCandidate(
          id: id,
          type: type,
          name: name,
          total: total,
          quantity: quantity,
        ),
      );
    }

    int? parseId(dynamic value) {
      if (value == null) return null;
      final digits = value.toString().replaceAll(RegExp(r'[^0-9]'), '');
      final parsed = int.tryParse(digits);
      return parsed != null && parsed > 0 ? parsed : null;
    }

    String resolveName(Map<String, dynamic> map) {
      final name = map['meal_name'] ??
          map['product_name'] ??
          map['item_name'] ??
          map['name'] ??
          map['title'];
      final text = name?.toString().trim();
      return (text == null || text.isEmpty) ? 'عنصر' : text;
    }

    int resolveQty(Map<String, dynamic> map) {
      final raw = map['quantity'] ?? map['qty'] ?? map['count'];
      final parsed = int.tryParse(raw?.toString() ?? '');
      return parsed ?? 1;
    }

    double resolveTotal(Map<String, dynamic> map) {
      return _parsePrice(
        map['total'] ?? map['amount'] ?? map['price'] ?? map['unit_price'],
      );
    }

    void addFromList(
      dynamic source, {
      required _RefundCandidateType type,
      required List<String> idKeys,
    }) {
      if (source is! List) return;
      for (final row in source.whereType<Map>()) {
        final map = row.map((k, v) => MapEntry(k.toString(), v));
        int? id;
        for (final key in idKeys) {
          id ??= parseId(map[key]);
        }
        id ??= parseId(map['id']);
        if (id == null) continue;
        addCandidate(
          type: type,
          id: id,
          name: resolveName(map),
          total: resolveTotal(map),
          quantity: resolveQty(map),
        );
      }
    }

    addFromList(
      previewPayload['sales_meals'] ?? previewPayload['meals'],
      type: _RefundCandidateType.meal,
      idKeys: const ['sales_meal_id', 'meal_id', 'item_id'],
    );
    addFromList(
      previewPayload['sales_products'] ?? previewPayload['products'],
      type: _RefundCandidateType.product,
      idKeys: const ['sales_product_id', 'product_id', 'item_id'],
    );

    if (candidates.isNotEmpty) {
      return candidates;
    }

    final items = _extractItems(data, payload);
    for (final item in items) {
      final id = parseId(
        item['sales_meal_id'] ??
            item['sales_product_id'] ??
            item['meal_id'] ??
            item['product_id'] ??
            item['item_id'] ??
            item['id'],
      );
      if (id == null) continue;

      final type =
          item['sales_product_id'] != null || item['product_id'] != null
              ? _RefundCandidateType.product
              : item['sales_meal_id'] != null || item['meal_id'] != null
                  ? _RefundCandidateType.meal
                  : _RefundCandidateType.unknown;

      addCandidate(
        type: type,
        id: id,
        name: resolveName(item),
        total: resolveTotal(item),
        quantity: resolveQty(item),
      );
    }

    return candidates;
  }
}
