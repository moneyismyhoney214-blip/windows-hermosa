import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import 'api/api_constants.dart';
import 'logger_service.dart';

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
        // Salon branches rename the kitchen role to "طابعة الأدوار" because
        // the ticket printed is a per-service turn slip, not a kitchen order.
        // Restaurant wording stays untouched.
        return ApiConstants.branchModule == 'salons'
            ? 'طابعة الأدوار'
            : 'طابعة المطبخ';
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

/// Persisted map of `printerDeviceId → assigned role`. Used to override
/// the heuristic role-inference in [_inferRole] when the cashier has
/// manually tagged a printer in settings.
///
/// **Storage**: lives in `flutter_secure_storage` (Android Keystore /
/// iOS Keychain). A one-time migration on the first read pulls any
/// legacy plaintext entry out of `SharedPreferences` and writes it
/// into secure storage, then deletes the SharedPrefs entry. Printer
/// device IDs aren't a credential, but the audit flagged any device
/// identifier in SharedPrefs as readable via ADB backup on rooted
/// devices, so moving them lines up the storage policy across the
/// app.
class PrinterRoleRegistry {
  PrinterRoleRegistry({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const String _storageKey = 'printer_role_registry_v1';

  final FlutterSecureStorage _secureStorage;
  final Map<String, PrinterRole> _explicitRoles = <String, PrinterRole>{};
  bool _loaded = false;

  Future<void> initialize() async {
    if (_loaded) return;
    try {
      var raw = await _secureStorage.read(key: _storageKey);

      // One-time migration of the legacy SharedPrefs entry into secure
      // storage. The plaintext blob is dropped from SharedPrefs once
      // copied so it stops being included in ADB backups.
      if (raw == null) {
        final legacy = await _readLegacySharedPrefs();
        if (legacy != null) {
          raw = legacy;
          await _secureStorage.write(key: _storageKey, value: legacy);
          await _deleteLegacySharedPrefs();
          Log.i('printer-role',
              'migrated legacy SharedPrefs entry to secure storage');
        }
      }

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
      Log.w('printer-role', 'failed to load registry', error: e);
    } finally {
      _loaded = true;
    }
  }

  Future<void> setRole(String deviceId, PrinterRole role) async {
    final id = deviceId.trim();
    if (id.isEmpty) {
      Log.w('printer-role', 'setRole called with empty deviceId');
      return;
    }
    await initialize();
    _explicitRoles[id] = role;
    await _persist();
    Log.d('printer-role',
        'setRole "$id" → ${role.storageValue} (${_explicitRoles.length} total)');
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
      Log.d('printer-role',
          'resolve ${device.name} (${device.id}) → EXPLICIT ${explicit.storageValue}');
      return explicit;
    }
    final inferred = _inferRole(device);
    Log.d('printer-role',
        'resolve ${device.name} (${device.id}) → INFERRED ${inferred.storageValue}');
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

    // Default to kitchen so unrecognized printers still receive kitchen tickets.
    return PrinterRole.kitchen;
  }

  Future<void> _persist() async {
    try {
      final payload = <String, String>{
        for (final entry in _explicitRoles.entries)
          entry.key: entry.value.storageValue,
      };
      await _secureStorage.write(
        key: _storageKey,
        value: jsonEncode(payload),
      );
    } catch (e) {
      Log.w('printer-role', 'failed to persist', error: e);
    }
  }

  // ────────────────────────────────────────────────────────────────────
  // Legacy SharedPreferences migration helpers
  // ────────────────────────────────────────────────────────────────────

  Future<String?> _readLegacySharedPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_storageKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteLegacySharedPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      // Non-fatal — if the cleanup fails, the value still lives in
      // secure storage. Next migration check will be a no-op since the
      // primary read path hits secure storage first.
      Log.w('printer-role',
          'failed to delete legacy SharedPrefs entry post-migration',
          error: e);
    }
  }
}
