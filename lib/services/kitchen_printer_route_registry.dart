import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Stores manual kitchen -> printer routing for kitchen ticket dispatch.
///
/// - One kitchen can map to one or many printers
/// - One printer can map to one or many kitchens
/// - If no manual mapping exists, resolver falls back to deterministic balancing
class KitchenPrinterRouteRegistry {
  static const String _storageKey = 'kitchen_printer_route_registry_v1';

  final Map<String, Set<int>> _printerKitchenMap = <String, Set<int>>{};
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

            final kitchenIds = <int>{};
            final value = entry.value;
            if (value is List) {
              for (final item in value) {
                final parsed = _toKitchenId(item);
                if (parsed != null) kitchenIds.add(parsed);
              }
            }
            if (kitchenIds.isNotEmpty) {
              _printerKitchenMap[printerId] = kitchenIds;
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ Failed to load kitchen printer routes: $e');
    } finally {
      _loaded = true;
    }
  }

  Future<void> setKitchenAssignmentsForPrinter(
    String printerId,
    Iterable<int> kitchenIds,
  ) async {
    await initialize();
    final normalizedPrinterId = printerId.trim();
    if (normalizedPrinterId.isEmpty) return;

    final normalizedKitchenIds =
        kitchenIds.map((id) => _toKitchenId(id)).whereType<int>().toSet();

    if (normalizedKitchenIds.isEmpty) {
      _printerKitchenMap.remove(normalizedPrinterId);
    } else {
      _printerKitchenMap[normalizedPrinterId] = normalizedKitchenIds;
    }

    await _persist();
  }

  Future<void> clearPrinterAssignments(String printerId) async {
    await initialize();
    final normalizedPrinterId = printerId.trim();
    if (normalizedPrinterId.isEmpty) return;
    _printerKitchenMap.remove(normalizedPrinterId);
    await _persist();
  }

  List<int> kitchenIdsForPrinter(String printerId) {
    final values = _printerKitchenMap[printerId.trim()];
    if (values == null || values.isEmpty) return const <int>[];
    final sorted = values.toList()..sort();
    return sorted;
  }

  int assignedKitchenCountForPrinter(String printerId) {
    return _printerKitchenMap[printerId.trim()]?.length ?? 0;
  }

  bool hasAnyAssignments() {
    return _printerKitchenMap.values.any((set) => set.isNotEmpty);
  }

  bool hasAssignmentsForKitchen(int kitchenId) {
    final normalized = _toKitchenId(kitchenId);
    if (normalized == null) return false;
    for (final entry in _printerKitchenMap.entries) {
      if (entry.value.contains(normalized)) return true;
    }
    return false;
  }

  Set<String> assignedPrinterIds() {
    return _printerKitchenMap.keys.toSet();
  }

  List<String> resolvePrinterIdsForKitchen({
    required int kitchenId,
    required List<String> availablePrinterIds,
    List<int> knownKitchenIds = const <int>[],
  }) {
    final normalizedKitchenId = _toKitchenId(kitchenId);
    if (normalizedKitchenId == null) return const <String>[];

    final available = availablePrinterIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (available.isEmpty) return const <String>[];

    final explicit = <String>[];
    for (final entry in _printerKitchenMap.entries) {
      if (!available.contains(entry.key)) continue;
      if (entry.value.contains(normalizedKitchenId)) {
        explicit.add(entry.key);
      }
    }
    if (explicit.isNotEmpty) {
      explicit.sort();
      return explicit;
    }

    final assignedPrinters =
        assignedPrinterIds().intersection(available.toSet());
    if (assignedPrinters.isEmpty) {
      return _resolveBalancedFallback(
        kitchenId: normalizedKitchenId,
        candidatePrinterIds: available,
        knownKitchenIds: knownKitchenIds,
      );
    }

    final unassignedPrinters =
        available.where((id) => !assignedPrinters.contains(id)).toList();
    if (unassignedPrinters.isNotEmpty) {
      return _resolveBalancedFallback(
        kitchenId: normalizedKitchenId,
        candidatePrinterIds: unassignedPrinters,
        knownKitchenIds: knownKitchenIds,
      );
    }

    // Last fallback: all available printers.
    return available;
  }

  List<String> _resolveBalancedFallback({
    required int kitchenId,
    required List<String> candidatePrinterIds,
    required List<int> knownKitchenIds,
  }) {
    if (candidatePrinterIds.isEmpty) return const <String>[];
    if (candidatePrinterIds.length == 1) return candidatePrinterIds;

    final kitchens = knownKitchenIds
        .map((id) => _toKitchenId(id))
        .whereType<int>()
        .toSet()
        .toList()
      ..sort();
    if (!kitchens.contains(kitchenId)) {
      kitchens.add(kitchenId);
      kitchens.sort();
    }

    final kitchenIndex = kitchens.indexOf(kitchenId);
    if (kitchenIndex < 0) return <String>[candidatePrinterIds.first];

    final printerIndex = kitchenIndex % candidatePrinterIds.length;
    return <String>[candidatePrinterIds[printerIndex]];
  }

  int? _toKitchenId(dynamic value) {
    if (value is int) return value > 0 ? value : null;
    if (value is num) {
      final asInt = value.toInt();
      return asInt > 0 ? asInt : null;
    }
    final parsed = int.tryParse(value?.toString().trim() ?? '');
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, List<int>>{};
      for (final entry in _printerKitchenMap.entries) {
        if (entry.value.isEmpty) continue;
        final list = entry.value.toList()..sort();
        payload[entry.key] = list;
      }
      await prefs.setString(_storageKey, jsonEncode(payload));
    } catch (e) {
      print('⚠️ Failed to persist kitchen printer routes: $e');
    }
  }
}
