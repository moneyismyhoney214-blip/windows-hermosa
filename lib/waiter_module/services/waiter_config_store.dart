import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/display_app_service.dart';
import '../../locator.dart';

/// Canonical kitchen-printer snapshot the cashier pushes to every waiter.
///
/// Phase 1 stores it locally and makes it available to future phases (e.g.
/// direct-print-from-waiter) via [WaiterConfigStore.kitchenPrinters]. It
/// is NOT consulted by any print path today.
@immutable
class SyncedKitchenPrinter {
  final String id;
  final String name;
  final String ip;
  final String port;
  final String type;
  final String model;
  final String connectionType;
  final String? bluetoothAddress;
  final int paperWidthMm;
  final int copies;
  final String role;
  final List<int> kitchenIds;
  final List<String> categoryIds;

  const SyncedKitchenPrinter({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.type,
    required this.model,
    required this.connectionType,
    required this.bluetoothAddress,
    required this.paperWidthMm,
    required this.copies,
    required this.role,
    required this.kitchenIds,
    required this.categoryIds,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'ip': ip,
        'port': port,
        'type': type,
        'model': model,
        'connection_type': connectionType,
        if (bluetoothAddress != null && bluetoothAddress!.isNotEmpty)
          'bluetooth_address': bluetoothAddress,
        'paper_width_mm': paperWidthMm,
        'copies': copies,
        'role': role,
        'kitchen_ids': kitchenIds,
        'category_ids': categoryIds,
      };

  factory SyncedKitchenPrinter.fromJson(Map<String, dynamic> j) {
    List<int> asIntList(dynamic v) {
      if (v is! List) return const <int>[];
      final out = <int>[];
      for (final item in v) {
        if (item is int) {
          out.add(item);
        } else if (item is num) {
          out.add(item.toInt());
        } else {
          final parsed = int.tryParse(item?.toString() ?? '');
          if (parsed != null) out.add(parsed);
        }
      }
      return out;
    }

    List<String> asStringList(dynamic v) {
      if (v is! List) return const <String>[];
      return v
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }

    return SyncedKitchenPrinter(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      ip: j['ip']?.toString() ?? '',
      port: j['port']?.toString() ?? '9100',
      type: j['type']?.toString() ?? 'printer',
      model: j['model']?.toString() ?? '',
      connectionType: j['connection_type']?.toString() ?? 'wifi',
      bluetoothAddress: j['bluetooth_address']?.toString(),
      paperWidthMm: j['paper_width_mm'] is int
          ? j['paper_width_mm'] as int
          : int.tryParse(j['paper_width_mm']?.toString() ?? '') ?? 58,
      copies: j['copies'] is int
          ? j['copies'] as int
          : int.tryParse(j['copies']?.toString() ?? '') ?? 1,
      role: j['role']?.toString() ?? 'kitchen',
      kitchenIds: asIntList(j['kitchen_ids']),
      categoryIds: asStringList(j['category_ids']),
    );
  }
}

@immutable
class SyncedKitchenPrintersConfig {
  final int version;
  final List<SyncedKitchenPrinter> printers;

  const SyncedKitchenPrintersConfig({
    required this.version,
    required this.printers,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'printers': printers.map((p) => p.toJson()).toList(growable: false),
      };

  factory SyncedKitchenPrintersConfig.fromJson(Map<String, dynamic> j) {
    final int version = j['version'] is int
        ? j['version'] as int
        : int.tryParse(j['version']?.toString() ?? '') ?? 0;
    final rawPrinters = j['printers'];
    final printers = <SyncedKitchenPrinter>[];
    if (rawPrinters is List) {
      for (final raw in rawPrinters) {
        if (raw is Map<String, dynamic>) {
          printers.add(SyncedKitchenPrinter.fromJson(raw));
        } else if (raw is Map) {
          printers.add(SyncedKitchenPrinter.fromJson(
              raw.map((k, v) => MapEntry(k.toString(), v))));
        }
      }
    }
    return SyncedKitchenPrintersConfig(version: version, printers: printers);
  }
}

@immutable
class SyncedKdsEndpoint {
  final int version;
  final String host;
  final int port;
  final bool enabled;

  const SyncedKdsEndpoint({
    required this.version,
    required this.host,
    required this.port,
    required this.enabled,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': version,
        'host': host,
        'port': port,
        'enabled': enabled,
      };

  factory SyncedKdsEndpoint.fromJson(Map<String, dynamic> j) {
    final int version = j['version'] is int
        ? j['version'] as int
        : int.tryParse(j['version']?.toString() ?? '') ?? 0;
    final int port = j['port'] is int
        ? j['port'] as int
        : int.tryParse(j['port']?.toString() ?? '') ?? 8080;
    return SyncedKdsEndpoint(
      version: version,
      host: j['host']?.toString() ?? '',
      port: port,
      enabled: j['enabled'] == true || j['enabled']?.toString() == 'true',
    );
  }
}

/// Cashier-authoritative config mirrored on the waiter device.
///
/// Hydrated from SharedPreferences on boot, then kept in sync by
/// [WaiterController] when it receives CONFIG_KITCHEN_PRINTERS /
/// CONFIG_KDS_ENDPOINT wire messages.
class WaiterConfigStore extends ChangeNotifier {
  static const String _kitchenPrintersKey = 'waiter_synced_kitchen_printers_v1';
  static const String _kdsEndpointKey = 'waiter_synced_kds_endpoint_v1';

  SyncedKitchenPrintersConfig? _kitchenPrinters;
  SyncedKdsEndpoint? _kdsEndpoint;
  bool _loaded = false;

  SyncedKitchenPrintersConfig? get kitchenPrinters => _kitchenPrinters;
  SyncedKdsEndpoint? get kdsEndpoint => _kdsEndpoint;

  Future<void> initialize() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      final rawPrinters = prefs.getString(_kitchenPrintersKey);
      if (rawPrinters != null && rawPrinters.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawPrinters);
          if (decoded is Map<String, dynamic>) {
            _kitchenPrinters = SyncedKitchenPrintersConfig.fromJson(decoded);
            debugPrint(
                '📥 WaiterConfigStore: loaded ${_kitchenPrinters!.printers.length} synced printers (v=${_kitchenPrinters!.version})');
          }
        } catch (e) {
          debugPrint('⚠️ WaiterConfigStore: failed to decode printers: $e');
        }
      }

      final rawKds = prefs.getString(_kdsEndpointKey);
      if (rawKds != null && rawKds.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawKds);
          if (decoded is Map<String, dynamic>) {
            _kdsEndpoint = SyncedKdsEndpoint.fromJson(decoded);
            debugPrint(
                '📥 WaiterConfigStore: loaded KDS endpoint ${_kdsEndpoint!.host}:${_kdsEndpoint!.port} (v=${_kdsEndpoint!.version})');
          }
        } catch (e) {
          debugPrint('⚠️ WaiterConfigStore: failed to decode KDS endpoint: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ WaiterConfigStore.initialize: $e');
    } finally {
      _loaded = true;
    }
  }

  /// Accept a snapshot from the cashier. Rejects older versions to keep
  /// out-of-order deliveries from clobbering newer state.
  Future<bool> applyKitchenPrinters(Map<String, dynamic> payload) async {
    await initialize();
    final incoming = SyncedKitchenPrintersConfig.fromJson(payload);
    final existing = _kitchenPrinters;
    if (existing != null && incoming.version <= existing.version) {
      debugPrint(
          '↩️ WaiterConfigStore: rejecting stale printers v=${incoming.version} (stored v=${existing.version})');
      return false;
    }
    _kitchenPrinters = incoming;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kitchenPrintersKey, jsonEncode(incoming.toJson()));
    } catch (e) {
      debugPrint('⚠️ WaiterConfigStore: failed to persist printers: $e');
    }
    debugPrint(
        '✅ WaiterConfigStore: applied ${incoming.printers.length} printers (v=${incoming.version})');
    notifyListeners();
    return true;
  }

  /// Accept a KDS endpoint snapshot. When the host/port change we
  /// reconnect the existing [DisplayAppService] so the waiter's next
  /// NEW_ORDER flows to the cashier's chosen KDS.
  Future<bool> applyKdsEndpoint(Map<String, dynamic> payload) async {
    await initialize();
    final incoming = SyncedKdsEndpoint.fromJson(payload);
    final existing = _kdsEndpoint;
    if (existing != null && incoming.version <= existing.version) {
      debugPrint(
          '↩️ WaiterConfigStore: rejecting stale KDS endpoint v=${incoming.version} (stored v=${existing.version})');
      return false;
    }
    _kdsEndpoint = incoming;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kdsEndpointKey, jsonEncode(incoming.toJson()));
    } catch (e) {
      debugPrint('⚠️ WaiterConfigStore: failed to persist KDS endpoint: $e');
    }
    debugPrint(
        '✅ WaiterConfigStore: KDS endpoint → ${incoming.host}:${incoming.port} enabled=${incoming.enabled} (v=${incoming.version})');
    notifyListeners();
    await _applyKdsEndpointToLiveService(incoming);
    return true;
  }

  /// Reapply whatever is in storage to the live [DisplayAppService]. Used
  /// at waiter startup so a hydrated endpoint from the last session is
  /// reflected on the socket immediately instead of waiting for the next
  /// cashier broadcast.
  Future<void> reapplyKdsEndpointToLiveService() async {
    final endpoint = _kdsEndpoint;
    if (endpoint == null) return;
    await _applyKdsEndpointToLiveService(endpoint);
  }

  Future<void> _applyKdsEndpointToLiveService(SyncedKdsEndpoint e) async {
    if (!e.enabled || e.host.trim().isEmpty) return;
    DisplayAppService? display;
    try {
      display = getIt<DisplayAppService>();
    } catch (err) {
      debugPrint(
          '⚠️ WaiterConfigStore: DisplayAppService not registered yet: $err');
      return;
    }
    final currentIp = display.connectedIp?.trim();
    final currentPort = display.connectedPort;
    if (currentIp == e.host.trim() && currentPort == e.port) {
      return; // already pointed at the synced endpoint
    }
    try {
      await display.connect(e.host.trim(), port: e.port);
      debugPrint(
          '🔌 WaiterConfigStore: reconnected DisplayApp to ${e.host}:${e.port}');
    } catch (err) {
      debugPrint('⚠️ WaiterConfigStore: DisplayApp connect failed: $err');
    }
  }
}
