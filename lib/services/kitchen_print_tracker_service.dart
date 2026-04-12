import 'dart:convert';

import 'cache_service.dart';

class KitchenPrintTrackerService {
  static const String _cacheKey = 'kitchen_print_tracker_v1';
  static const Duration _orderTtl = Duration(hours: 36);

  final CacheService _cache;
  bool _initialized = false;
  final Map<String, _OrderPrintState> _orders = {};

  KitchenPrintTrackerService(this._cache);

  Future<void> initialize() async {
    if (_initialized) return;
    final raw = await _cache.get(_cacheKey);
    if (raw is Map) {
      for (final entry in raw.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is! Map) continue;
        final itemsRaw = value['items'];
        if (itemsRaw is! Map) continue;
        final updatedAtRaw = value['updated_at']?.toString();
        final updatedAt = updatedAtRaw != null
            ? DateTime.tryParse(updatedAtRaw)
            : null;
        final items = <String, double>{};
        for (final itemEntry in itemsRaw.entries) {
          final itemKey = itemEntry.key.toString();
          final qty = _toSafeDouble(itemEntry.value, fallback: 0.0);
          if (qty <= 0) continue;
          items[itemKey] = qty;
        }
        if (items.isEmpty) continue;
        _orders[key] = _OrderPrintState(
          items: items,
          updatedAt: updatedAt ?? DateTime.now(),
        );
      }
    }
    _pruneExpired();
    _initialized = true;
  }

  String buildOrderKey(String orderNumber, {Map<String, dynamic>? templateMeta}) {
    final normalizedOrder = _normalizeOrderNumber(orderNumber);
    final date = _normalizeText(templateMeta?['date']);
    if (date.isNotEmpty) {
      return '$date#$normalizedOrder';
    }
    return normalizedOrder;
  }

  List<Map<String, dynamic>> filterNewItems({
    required String orderKey,
    required List<Map<String, dynamic>> items,
  }) {
    final state = _orders[orderKey];
    final printed = state?.items ?? const <String, double>{};
    final filtered = <Map<String, dynamic>>[];

    for (final rawItem in items) {
      final item = Map<String, dynamic>.from(rawItem);
      final originalQty = _toSafeDouble(item['quantity'], fallback: 1.0);
      if (originalQty <= 0) continue;

      final signature = _itemSignature(item);
      final printedQty = printed[signature] ?? 0.0;
      final remainingQty = originalQty - printedQty;
      if (remainingQty <= 0.0001) continue;

      item['quantity'] = remainingQty;
      _adjustTotals(item, originalQuantity: originalQty);
      filtered.add(item);
    }

    return filtered;
  }

  bool hasTrackedItemsForOrder({
    required String orderNumber,
    Map<String, dynamic>? templateMeta,
  }) {
    final normalized = _normalizeOrderNumber(orderNumber);
    if (normalized.isEmpty) return false;

    final keysToCheck = <String>{
      buildOrderKey(normalized, templateMeta: templateMeta),
      normalized,
    };
    final suffix = '#$normalized';

    for (final entry in _orders.entries) {
      if (entry.value.items.isEmpty) continue;
      if (keysToCheck.contains(entry.key) || entry.key.endsWith(suffix)) {
        return true;
      }
    }
    return false;
  }

  Future<void> markPrinted({
    required String orderKey,
    required List<Map<String, dynamic>> items,
  }) async {
    if (items.isEmpty) return;
    final state = _orders.putIfAbsent(
      orderKey,
      () => _OrderPrintState(items: <String, double>{}, updatedAt: DateTime.now()),
    );

    for (final item in items) {
      final qty = _toSafeDouble(item['quantity'], fallback: 1.0);
      if (qty <= 0) continue;
      final signature = _itemSignature(item);
      state.items[signature] = (state.items[signature] ?? 0.0) + qty;
    }
    state.updatedAt = DateTime.now();
    await _persist();
  }

  Future<void> _persist() async {
    _pruneExpired();
    final payload = <String, dynamic>{};
    for (final entry in _orders.entries) {
      payload[entry.key] = {
        'updated_at': entry.value.updatedAt.toIso8601String(),
        'items': entry.value.items,
      };
    }
    await _cache.set(_cacheKey, payload);
  }

  void _pruneExpired() {
    final cutoff = DateTime.now().subtract(_orderTtl);
    _orders.removeWhere((_, state) => state.updatedAt.isBefore(cutoff));
  }

  String _normalizeOrderNumber(String value) {
    var normalized = value.trim();
    if (normalized.startsWith('#')) {
      normalized = normalized.substring(1);
    }
    return normalized.isEmpty ? value.trim() : normalized;
  }

  String _normalizeText(dynamic value) {
    final text = value?.toString().trim().toLowerCase() ?? '';
    if (text.isEmpty) return '';
    return text.replaceAll(RegExp(r'\s+'), ' ');
  }

  String _itemSignature(Map<String, dynamic> item) {
    final id = _normalizeText(_firstNonEmptyText([
      item['id'],
      item['meal_id'],
      item['product_id'],
      item['productId'],
      item['booking_meal_id'],
      item['booking_product_id'],
    ]));
    final name = _normalizeText(_firstNonEmptyText([
      item['name'],
      item['meal_name'],
      item['item_name'],
      item['title'],
    ]));
    final category = _normalizeText(_firstNonEmptyText([
      item['category_id'],
      item['categoryId'],
      item['category_name'],
      item['category'],
      item['section_id'],
      item['section_name'],
    ]));
    final notes = _normalizeText(_firstNonEmptyText([
      item['notes'],
      item['note'],
    ]));
    final extras = _extractExtras(item);
    final unitPrice = _toSafeDouble(
      item['unitPrice'] ?? item['unit_price'] ?? item['price'],
      fallback: 0.0,
    );

    final payload = {
      'id': id,
      'name': name,
      'category': category,
      'extras': extras,
      'notes': notes,
      'unitPrice': unitPrice > 0 ? unitPrice.toStringAsFixed(3) : '',
    };
    return jsonEncode(payload);
  }

  List<String> _extractExtras(Map<String, dynamic> item) {
    final rawExtras = item['extras'] ?? item['addons'];
    if (rawExtras is! List) return const <String>[];

    final extras = <String>[];
    for (final entry in rawExtras) {
      if (entry is String) {
        final normalized = _normalizeText(entry);
        if (normalized.isNotEmpty) extras.add(normalized);
        continue;
      }
      if (entry is Map) {
        final map = entry.map((k, v) => MapEntry(k.toString(), v));
        final name = _normalizeText(_firstNonEmptyText([
          map['name'],
          map['title'],
          map['addon_name'],
          map['operation_name'],
        ]));
        if (name.isNotEmpty) extras.add(name);
      }
    }
    extras.sort();
    return extras;
  }

  void _adjustTotals(Map<String, dynamic> item, {required double originalQuantity}) {
    final newQty = _toSafeDouble(item['quantity'], fallback: originalQuantity);
    if (newQty <= 0) return;
    final unitPrice = _toSafeDouble(
      item['unitPrice'] ?? item['unit_price'] ?? item['price'],
      fallback: 0.0,
    );
    final total = _toSafeDouble(
      item['total'] ?? item['line_total'] ?? item['price_total'],
      fallback: 0.0,
    );

    if (unitPrice > 0) {
      item['total'] = double.parse((unitPrice * newQty).toStringAsFixed(3));
      return;
    }
    if (total > 0 && originalQuantity > 0) {
      item['total'] =
          double.parse((total * (newQty / originalQuantity)).toStringAsFixed(3));
    }
  }

  String? _firstNonEmptyText(Iterable<dynamic> candidates) {
    for (final candidate in candidates) {
      final text = candidate?.toString().trim();
      if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return null;
  }

  double _toSafeDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class _OrderPrintState {
  final Map<String, double> items;
  DateTime updatedAt;

  _OrderPrintState({required this.items, required this.updatedAt});
}
