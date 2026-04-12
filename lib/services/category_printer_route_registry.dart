import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Stores manual category -> printer routing for kitchen printing.
///
/// Mapping model:
/// - key: printer device id (e.g. printer:12)
/// - value: set of category ids (as strings)
class CategoryPrinterRouteRegistry {
  static const String _storageKey = 'category_printer_route_registry_v1';

  final Map<String, Set<String>> _printerCategoryMap = <String, Set<String>>{};
  bool _loaded = false;

  Future<void> initialize() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final printerId = entry.key.toString().trim();
            if (printerId.isEmpty) continue;

            final values = <String>{};
            final rawValue = entry.value;
            if (rawValue is List) {
              for (final item in rawValue) {
                final normalized = _normalizeCategoryId(item);
                if (normalized != null) values.add(normalized);
              }
            }
            if (values.isNotEmpty) {
              _printerCategoryMap[printerId] = values;
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ Failed to load category printer routes: $e');
    } finally {
      _loaded = true;
    }
  }

  Future<void> setCategoryAssignmentsForPrinter(
    String printerId,
    Iterable<String> categoryIds,
  ) async {
    await initialize();
    final normalizedPrinterId = printerId.trim();
    if (normalizedPrinterId.isEmpty) return;

    final normalizedCategoryIds =
        categoryIds.map(_normalizeCategoryId).whereType<String>().toSet();

    if (normalizedCategoryIds.isEmpty) {
      _printerCategoryMap.remove(normalizedPrinterId);
    } else {
      _printerCategoryMap[normalizedPrinterId] = normalizedCategoryIds;
    }
    await _persist();
  }

  Future<void> clearPrinterAssignments(String printerId) async {
    await initialize();
    final normalizedPrinterId = printerId.trim();
    if (normalizedPrinterId.isEmpty) return;
    _printerCategoryMap.remove(normalizedPrinterId);
    await _persist();
  }

  List<String> categoryIdsForPrinter(String printerId) {
    final set = _printerCategoryMap[printerId.trim()];
    if (set == null || set.isEmpty) return const <String>[];
    final sorted = set.toList()..sort();
    return sorted;
  }

  int assignedCategoryCountForPrinter(String printerId) {
    return _printerCategoryMap[printerId.trim()]?.length ?? 0;
  }

  bool hasAnyAssignments() {
    return _printerCategoryMap.values.any((set) => set.isNotEmpty);
  }

  bool hasAssignmentsForPrinter(String printerId) {
    return (_printerCategoryMap[printerId.trim()]?.isNotEmpty ?? false);
  }

  List<String> resolvePrinterIdsForCategoryId({
    required String categoryId,
    required List<String> availablePrinterIds,
  }) {
    final normalizedCategoryId = _normalizeCategoryId(categoryId);
    if (normalizedCategoryId == null) return const <String>[];

    final available = availablePrinterIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    final matched = <String>[];
    for (final entry in _printerCategoryMap.entries) {
      if (!available.contains(entry.key)) continue;
      if (entry.value.contains(normalizedCategoryId)) {
        matched.add(entry.key);
      }
    }
    matched.sort();
    return matched;
  }

  String? resolveSinglePrinterIdForCategoryId({
    required String categoryId,
    required List<String> availablePrinterIds,
  }) {
    final resolved = resolvePrinterIdsForCategoryId(
      categoryId: categoryId,
      availablePrinterIds: availablePrinterIds,
    );
    if (resolved.isEmpty) return null;
    return resolved.first;
  }

  Future<void> assignCategoryToPrinter({
    required String categoryId,
    String? printerId,
  }) async {
    await initialize();
    final normalizedCategoryId = _normalizeCategoryId(categoryId);
    if (normalizedCategoryId == null) return;

    // Keep mapping deterministic: a category maps to at most one printer.
    final emptyPrinterIds = <String>[];
    for (final entry in _printerCategoryMap.entries) {
      entry.value.remove(normalizedCategoryId);
      if (entry.value.isEmpty) {
        emptyPrinterIds.add(entry.key);
      }
    }
    for (final id in emptyPrinterIds) {
      _printerCategoryMap.remove(id);
    }

    final normalizedPrinterId = printerId?.trim();
    if (normalizedPrinterId != null && normalizedPrinterId.isNotEmpty) {
      final assigned = _printerCategoryMap.putIfAbsent(
        normalizedPrinterId,
        () => <String>{},
      );
      assigned.add(normalizedCategoryId);
    }

    await _persist();
  }

  String? _normalizeCategoryId(dynamic value) {
    final token = value?.toString().trim();
    if (token == null || token.isEmpty) return null;
    return token;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, List<String>>{};
      for (final entry in _printerCategoryMap.entries) {
        if (entry.value.isEmpty) continue;
        final values = entry.value.toList()..sort();
        payload[entry.key] = values;
      }
      await prefs.setString(_storageKey, jsonEncode(payload));
    } catch (e) {
      print('⚠️ Failed to persist category printer routes: $e');
    }
  }
}
