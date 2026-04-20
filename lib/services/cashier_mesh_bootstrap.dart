import 'dart:async';

import 'package:flutter/foundation.dart';

import '../locator.dart';
import '../models.dart';
import '../waiter_module/services/waiter_config_store.dart';
import '../waiter_module/services/waiter_controller.dart';
import 'category_printer_route_registry.dart';
import 'display_app_service.dart';
import 'kitchen_printer_route_registry.dart';
import 'printer_role_registry.dart';

typedef DevicesProvider = List<DeviceConfig> Function();

/// Cashier-side glue that:
///   1. Joins the waiter LAN mesh as a viewer so we can broadcast config.
///   2. Composes kitchen-printer + KDS-endpoint snapshots from the three
///      local registries + the live device list.
///   3. Pushes the snapshots on every peer HELLO (catch-up) and on every
///      cashier-side mutation.
///
/// This lives in `lib/services/` (not `lib/waiter_module/`) because it is
/// a cashier concern — the waiter module is the *consumer* of snapshots
/// it produces.
class CashierMeshBootstrap {
  final WaiterController controller;
  final WaiterConfigStore configStore;

  DevicesProvider? _devicesProvider;
  StreamSubscription<String>? _helloSub;
  StreamSubscription<String>? _syncReqSub;
  VoidCallback? _displayListener;

  Timer? _printerDebounce;
  Timer? _kdsDebounce;

  /// Monotonically increasing payload version. Clock-based so cross-device
  /// pushes against the same waiter converge to the newest. On a single
  /// cashier this is just `DateTime.now().millisecondsSinceEpoch`; we keep
  /// a floor to guarantee strict increase even if the system clock steps
  /// backwards.
  int _lastVersion = 0;

  bool _started = false;
  bool get isStarted => _started;

  CashierMeshBootstrap({
    required this.controller,
    required this.configStore,
  });

  /// Wire the device-list source. Safe to call multiple times; the latest
  /// provider wins so hot-reload-replaced states don't leak.
  void setDevicesProvider(DevicesProvider provider) {
    _devicesProvider = provider;
  }

  /// Start the cashier as a viewer on the mesh. Also subscribes to:
  ///   - onPeerHello → push both snapshots to the late joiner
  ///   - onConfigSyncRequest → same
  ///   - DisplayAppService changes → rebroadcast KDS endpoint
  Future<void> start({
    required String name,
    required String branchId,
  }) async {
    try {
      await controller.ensureViewer(name: name, branchId: branchId);
    } catch (e, st) {
      debugPrint('⚠️ CashierMeshBootstrap.ensureViewer failed: $e');
      debugPrintStack(stackTrace: st);
      return;
    }

    // Attach listeners once even across repeated start calls (e.g. branch
    // switch restarts the controller but we don't want duplicate subs).
    await _attachListeners();

    _started = true;

    // Push a first snapshot so a cashier that came up AFTER waiters have
    // been running doesn't leave them stuck on stale config.
    unawaited(broadcastKitchenPrintersConfig());
    unawaited(broadcastKdsEndpoint());
  }

  Future<void> stop() async {
    _printerDebounce?.cancel();
    _printerDebounce = null;
    _kdsDebounce?.cancel();
    _kdsDebounce = null;
    await _helloSub?.cancel();
    _helloSub = null;
    await _syncReqSub?.cancel();
    _syncReqSub = null;
    final listener = _displayListener;
    if (listener != null) {
      try {
        getIt<DisplayAppService>().removeListener(listener);
      } catch (_) {}
      _displayListener = null;
    }
    try {
      await controller.stop();
    } catch (_) {}
    _started = false;
  }

  Future<void> _attachListeners() async {
    if (_helloSub == null) {
      _helloSub = controller.onPeerHello.listen(_handlePeerHello);
    }
    if (_syncReqSub == null) {
      _syncReqSub =
          controller.onConfigSyncRequest.listen(_handleSyncRequest);
    }
    if (_displayListener == null) {
      final display = getIt<DisplayAppService>();
      String? lastIp = display.connectedIp;
      int? lastPort = display.connectedPort;
      void onChange() {
        final ip = display.connectedIp;
        final port = display.connectedPort;
        if (ip != lastIp || port != lastPort) {
          lastIp = ip;
          lastPort = port;
          _scheduleKdsBroadcast();
        }
      }
      display.addListener(onChange);
      _displayListener = onChange;
    }
  }

  // ---------------------------------------------------------------------------
  // Public broadcast entry points (called from printers_tab_view + MainScreen)
  // ---------------------------------------------------------------------------

  /// Compose + broadcast the latest printer snapshot. Safe to call from
  /// any printer mutation callsite; internally debounced (250 ms) so a
  /// burst of name/IP edits doesn't spam the network.
  Future<void> broadcastKitchenPrintersConfig() async {
    _schedulePrinterBroadcast();
  }

  /// Compose + broadcast the cashier's current KDS endpoint.
  Future<void> broadcastKdsEndpoint() async {
    _scheduleKdsBroadcast();
  }

  void _schedulePrinterBroadcast() {
    _printerDebounce?.cancel();
    _printerDebounce =
        Timer(const Duration(milliseconds: 250), _doBroadcastPrinters);
  }

  void _scheduleKdsBroadcast() {
    _kdsDebounce?.cancel();
    _kdsDebounce =
        Timer(const Duration(milliseconds: 250), _doBroadcastKds);
  }

  Future<void> _doBroadcastPrinters() async {
    if (!_started) return;
    try {
      final payload = await _snapshotKitchenPrinters();
      if (payload == null) return;
      controller.broadcastKitchenPrintersConfig(payload);
      debugPrint(
          '📤 CONFIG_KITCHEN_PRINTERS v=${payload['version']} (${(payload['printers'] as List).length} printers)');
    } catch (e, st) {
      debugPrint('⚠️ broadcastKitchenPrintersConfig failed: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> _doBroadcastKds() async {
    if (!_started) return;
    try {
      final payload = _snapshotKdsEndpoint();
      if (payload == null) return;
      controller.broadcastKdsEndpoint(payload);
      debugPrint(
          '📤 CONFIG_KDS_ENDPOINT v=${payload['version']} ${payload['host']}:${payload['port']} enabled=${payload['enabled']}');
    } catch (e) {
      debugPrint('⚠️ broadcastKdsEndpoint failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Per-peer push for catch-up
  // ---------------------------------------------------------------------------

  Future<void> _handlePeerHello(String peerId) async {
    await _pushSnapshotsTo(peerId);
  }

  Future<void> _handleSyncRequest(String peerId) async {
    await _pushSnapshotsTo(peerId);
  }

  Future<void> _pushSnapshotsTo(String peerId) async {
    if (!_started) return;
    try {
      final printers = await _snapshotKitchenPrinters();
      if (printers != null) {
        controller.pushKitchenPrintersConfigTo(peerId, printers);
      }
      final kds = _snapshotKdsEndpoint();
      if (kds != null) {
        controller.pushKdsEndpointTo(peerId, kds);
      }
    } catch (e) {
      debugPrint('⚠️ _pushSnapshotsTo($peerId) failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Snapshot composition
  // ---------------------------------------------------------------------------

  int _nextVersion() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final v = now <= _lastVersion ? _lastVersion + 1 : now;
    _lastVersion = v;
    return v;
  }

  Future<Map<String, dynamic>?> _snapshotKitchenPrinters() async {
    final provider = _devicesProvider;
    if (provider == null) {
      debugPrint(
          'ℹ️ CashierMeshBootstrap: no devicesProvider yet — skipping printer broadcast');
      return null;
    }
    final devices = provider().toList(growable: false);

    final roleRegistry = getIt<PrinterRoleRegistry>();
    final categoryRegistry = getIt<CategoryPrinterRouteRegistry>();
    final kitchenRouteRegistry = getIt<KitchenPrinterRouteRegistry>();
    await roleRegistry.initialize();
    await categoryRegistry.initialize();
    await kitchenRouteRegistry.initialize();

    final printers = <Map<String, dynamic>>[];
    for (final d in devices) {
      if (!_isPhysicalPrinter(d)) continue;
      final role = roleRegistry.resolveRole(d);
      // Only sync kitchen-side roles. Cashier receipts stay on the
      // cashier device; general-role printers can't be assumed to be
      // reachable from the waiter LAN.
      if (role != PrinterRole.kitchen &&
          role != PrinterRole.kds &&
          role != PrinterRole.bar) {
        continue;
      }
      printers.add(<String, dynamic>{
        'id': d.id,
        'name': d.name,
        'ip': d.ip,
        'port': d.port,
        'type': d.type,
        'model': d.model,
        'connection_type': d.connectionType.name,
        if (d.bluetoothAddress != null && d.bluetoothAddress!.isNotEmpty)
          'bluetooth_address': d.bluetoothAddress,
        'paper_width_mm': d.paperWidthMm,
        'copies': d.copies,
        'role': role.storageValue,
        'kitchen_ids': kitchenRouteRegistry.kitchenIdsForPrinter(d.id),
        'category_ids': categoryRegistry.categoryIdsForPrinter(d.id),
      });
    }

    return <String, dynamic>{
      'version': _nextVersion(),
      'printers': printers,
    };
  }

  Map<String, dynamic>? _snapshotKdsEndpoint() {
    DisplayAppService? display;
    try {
      display = getIt<DisplayAppService>();
    } catch (_) {
      return null;
    }
    final host = display.connectedIp?.trim() ?? '';
    final port = display.connectedPort;
    // Empty host → "no endpoint" — still broadcast so waiters can clear
    // stale state. `enabled:false` lets the receiver know not to
    // reconnect.
    return <String, dynamic>{
      'version': _nextVersion(),
      'host': host,
      'port': port,
      'enabled': host.isNotEmpty,
    };
  }

  bool _isPhysicalPrinter(DeviceConfig device) {
    final normalized = device.type.trim().toLowerCase();
    if (device.id.startsWith('kitchen:')) return false;
    if (_isDisplayDeviceType(normalized)) return false;
    return normalized == 'printer';
  }

  bool _isDisplayDeviceType(String type) {
    final normalized = type.trim().toLowerCase();
    return normalized == 'kds' ||
        normalized == 'kitchen_screen' ||
        normalized == 'order_viewer' ||
        normalized == 'cds' ||
        normalized == 'customer_display';
  }
}
