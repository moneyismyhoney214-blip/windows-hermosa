import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

enum PrinterRole {
  kitchen,
  cashierReceipt,
  kds,
  bar,
  general,
}

extension PrinterRoleX on PrinterRole {
  String get storageValue {
    switch (this) {
      case PrinterRole.kitchen:
        return 'kitchen';
      case PrinterRole.cashierReceipt:
        return 'cashier_receipt';
      case PrinterRole.kds:
        return 'kds';
      case PrinterRole.bar:
        return 'bar';
      case PrinterRole.general:
        return 'general';
    }
  }

  String get labelAr {
    switch (this) {
      case PrinterRole.kitchen:
        return 'طابعة المطبخ';
      case PrinterRole.cashierReceipt:
        return 'طابعة الكاشير (إيصال)';
      case PrinterRole.kds:
        return 'طابعة KDS';
      case PrinterRole.bar:
        return 'طابعة البار';
      case PrinterRole.general:
        return 'طابعة عامة';
    }
  }

  static PrinterRole fromStorage(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'kitchen':
        return PrinterRole.kitchen;
      case 'cashier_receipt':
      case 'cashier':
      case 'receipt':
        return PrinterRole.cashierReceipt;
      case 'kds':
        return PrinterRole.kds;
      case 'bar':
        return PrinterRole.bar;
      default:
        return PrinterRole.general;
    }
  }
}

class PrinterRoleRegistry {
  static const String _storageKey = 'printer_role_registry_v1';

  final Map<String, PrinterRole> _explicitRoles = <String, PrinterRole>{};
  bool _loaded = false;

  Future<void> initialize() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final id = entry.key.toString().trim();
            if (id.isEmpty) continue;
            _explicitRoles[id] =
                PrinterRoleX.fromStorage(entry.value?.toString());
          }
        }
      }
    } catch (e) {
      // Keep default heuristic behavior if registry cannot be loaded.
      print('⚠️ Failed to load printer role registry: $e');
    } finally {
      _loaded = true;
    }
  }

  Future<void> setRole(String deviceId, PrinterRole role) async {
    final id = deviceId.trim();
    if (id.isEmpty) {
      print('⚠️ setRole called with EMPTY deviceId!');
      return;
    }
    await initialize();
    _explicitRoles[id] = role;
    await _persist();
    print('✅ setRole: "$id" → ${role.storageValue} (total: ${_explicitRoles.length} roles saved)');
    // Verify it was saved
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_storageKey);
    print('💾 Persisted roles: $saved');
  }

  Future<void> clearRole(String deviceId) async {
    final id = deviceId.trim();
    if (id.isEmpty) return;
    await initialize();
    _explicitRoles.remove(id);
    await _persist();
  }

  bool hasExplicitRole(String deviceId) {
    return _explicitRoles.containsKey(deviceId);
  }

  PrinterRole resolveRole(DeviceConfig device) {
    final explicit = _explicitRoles[device.id];
    if (explicit != null) {
      print('🏷️ Role [${device.name}] id=${device.id} → EXPLICIT: ${explicit.storageValue}');
      return explicit;
    }
    final inferred = _inferRole(device);
    print('🏷️ Role [${device.name}] id=${device.id} → INFERRED: ${inferred.storageValue} (name="${device.name}" type="${device.type}")');
    return inferred;
  }

  String roleLabelFor(DeviceConfig device) {
    return resolveRole(device).labelAr;
  }

  Map<String, PrinterRole> get explicitRoles =>
      Map<String, PrinterRole>.unmodifiable(_explicitRoles);

  PrinterRole _inferRole(DeviceConfig device) {
    final bucket =
        '${device.name} ${device.type} ${device.model}'.toLowerCase().trim();

    bool containsAny(List<String> terms) =>
        terms.any((term) => bucket.contains(term));

    if (containsAny(const ['[kds]', ' kds ', 'kitchen', 'مطبخ'])) {
      return PrinterRole.kds;
    }
    if (containsAny(const ['[bar]', ' bar ', 'بار'])) {
      return PrinterRole.bar;
    }
    if (containsAny(
        const ['[cashier]', 'cashier', 'receipt', 'فاتورة', 'كاشير'])) {
      return PrinterRole.cashierReceipt;
    }
    if (containsAny(const ['kitchen_printer', 'طبخ'])) {
      return PrinterRole.kitchen;
    }

    // Keep kitchen routing safe by default for unknown printers.
    return PrinterRole.general;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, String>{
        for (final entry in _explicitRoles.entries)
          entry.key: entry.value.storageValue,
      };
      await prefs.setString(_storageKey, jsonEncode(payload));
    } catch (e) {
      print('⚠️ Failed to persist printer role registry: $e');
    }
  }
}
