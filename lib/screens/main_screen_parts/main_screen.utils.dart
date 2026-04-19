// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../main_screen.dart';

extension MainScreenUtils on _MainScreenState {
  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  bool? _toNullableBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty || normalized == 'null') return null;
      if (const ['1', 'true', 'yes', 'on', 'enabled', 'active']
          .contains(normalized)) {
        return true;
      }
      if (const ['0', 'false', 'no', 'off', 'disabled', 'inactive']
          .contains(normalized)) {
        return false;
      }
    }
    return null;
  }

  double? _toNullableTaxRate(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final numeric = value.toDouble();
      if (numeric < 0) return null;
      if (numeric > 1.0) return (numeric / 100).clamp(0.0, 1.0);
      return numeric.clamp(0.0, 1.0);
    }
    if (value is String) {
      final cleaned = value.trim().replaceAll('%', '');
      if (cleaned.isEmpty || cleaned.toLowerCase() == 'null') return null;
      final numeric = double.tryParse(cleaned);
      if (numeric == null || numeric < 0) return null;
      if (numeric > 1.0) return (numeric / 100).clamp(0.0, 1.0);
      return numeric.clamp(0.0, 1.0);
    }
    return null;
  }

  double? _findTaxRateInPayload(dynamic payload) {
    final queue = <dynamic>[payload];
    var guard = 0;
    while (queue.isNotEmpty && guard < 250) {
      guard++;
      final node = queue.removeLast();
      final map = _asMap(node);
      if (map != null) {
        for (final key in const [
          'tax_rate',
          'taxRate',
          'tax_percentage',
          'taxPercentage',
          'vat_rate',
          'vat_percentage',
        ]) {
          final parsed = _toNullableTaxRate(map[key]);
          if (parsed != null) return parsed;
        }
        final nestedTaxObject = _asMap(map['taxObject'] ?? map['tax_object']);
        if (nestedTaxObject != null) {
          queue.add(nestedTaxObject);
        }
        for (final value in map.values) {
          if (value is Map || value is List) {
            queue.add(value);
          }
        }
        continue;
      }
      if (node is List) {
        for (final value in node) {
          if (value is Map || value is List) {
            queue.add(value);
          }
        }
      }
    }
    return null;
  }

  bool? _findHasTaxInPayload(dynamic payload) {
    final queue = <dynamic>[payload];
    var guard = 0;
    while (queue.isNotEmpty && guard < 250) {
      guard++;
      final node = queue.removeLast();
      final map = _asMap(node);
      if (map != null) {
        for (final key in const [
          'has_tax',
          'hasTax',
          'tax_enabled',
          'taxEnabled',
          'enable_tax',
          'enableTax',
        ]) {
          final parsed = _toNullableBool(map[key]);
          if (parsed != null) return parsed;
        }
        for (final value in map.values) {
          if (value is Map || value is List) {
            queue.add(value);
          }
        }
        continue;
      }
      if (node is List) {
        for (final value in node) {
          if (value is Map || value is List) {
            queue.add(value);
          }
        }
      }
    }
    return null;
  }
}
