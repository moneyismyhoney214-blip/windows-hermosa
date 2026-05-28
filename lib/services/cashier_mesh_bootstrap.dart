import 'dart:async';

import 'package:flutter/foundation.dart';

import '../locator.dart';
import '../models.dart';
import '../waiter_module/models/waiter_table_event.dart';
import '../waiter_module/services/waiter_config_store.dart';
import '../waiter_module/services/waiter_controller.dart';
import 'category_printer_route_registry.dart';
import 'display_app_service.dart';
import 'kitchen_printer_route_registry.dart';
import 'logger_service.dart';
import 'printer_role_registry.dart';
import 'waitlist_mesh_bridge.dart';
import 'waitlist_service.dart';
import 'whatsapp_service.dart';

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
  VoidCallback? _whatsAppListener;

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

    // Attach listeners once; repeated starts (branch switch) must not duplicate subs.
    await _attachListeners();

    _started = true;

    // attach() is idempotent — tears down old subs before re-wiring.
    unawaited(waitlistService.initialize());
    waitlistMeshBridge.attach(controller);

    // Push first snapshot so cashiers booting after waiters don't leave them on stale config.
    unawaited(broadcastKitchenPrintersConfig());
    unawaited(broadcastKdsEndpoint());
    _broadcastWhatsAppConfig();
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
      } catch (e) {
        Log.w('cashier-mesh', 'display listener detach failed', error: e);
      }
      _displayListener = null;
    }
    final waListener = _whatsAppListener;
    if (waListener != null) {
      try {
        whatsAppService.removeListener(waListener);
      } catch (e) {
        Log.w('cashier-mesh', 'WhatsApp listener detach failed', error: e);
      }
      _whatsAppListener = null;
    }
    waitlistMeshBridge.detach();
    try {
      await controller.stop();
    } catch (e) {
      Log.w('cashier-mesh', 'mesh controller stop failed', error: e);
    }
    _started = false;
  }

  Future<void> _attachListeners() async {
    _helloSub ??= controller.onPeerHello.listen(_handlePeerHello);
    _syncReqSub ??= controller.onConfigSyncRequest.listen(_handleSyncRequest);
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
    if (_whatsAppListener == null) {
      // Re-push WAWP creds on change — critical for BranchService's first post-login seed.
      void onWaChange() => _broadcastWhatsAppConfig();
      whatsAppService.addListener(onWaChange);
      _whatsAppListener = onWaChange;
    }
  }

  // --- Public broadcast entry points (printers_tab_view + MainScreen) ---

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

  /// Push a table-state change ORIGINATING on this cashier device into the
  /// waiter mesh so every waiter screen mirrors it in real time. The cashier
  /// is normally a passive viewer of table state, but when it creates a
  /// pay-later booking, settles an invoice, cancels a booking, etc. itself,
  /// the waiter module otherwise keeps showing the table as free until its
  /// next manual refresh.
  ///
  /// [reserved] true → the table now has an open (pay-later) order
  /// ([TableLifecycleKind.paymentPending]); false → the table is now free
  /// ([TableLifecycleKind.released]).
  void broadcastCashierTableState({
    required String tableId,
    required String tableNumber,
    required bool reserved,
    String? bookingId,
    double? total,
    int? itemCount,
  }) {
    if (!_started) return;
    final tid = tableId.trim();
    if (tid.isEmpty) return;
    final self = controller.session.self;
    if (self == null) return;
    final bid =
        (bookingId != null && bookingId.trim().isNotEmpty) ? bookingId.trim() : null;
    try {
      controller.broadcastTableEvent(TableLifecycleEvent(
        kind: reserved
            ? TableLifecycleKind.paymentPending
            : TableLifecycleKind.released,
        tableId: tid,
        tableNumber: tableNumber.trim(),
        // Cashier isn't a waiter — keep owner blank so waiter cards don't claim a phantom owner.
        waiterId: '',
        waiterName: '',
        total: reserved ? total : null,
        itemCount: reserved ? itemCount : null,
        orderId: reserved ? bid : null,
      ));
      debugPrint(
          '📤 TABLE_${reserved ? 'PAYMENT_PENDING' : 'RELEASED'} table=$tid booking=${bid ?? '-'} (cashier-originated)');
    } catch (e) {
      debugPrint('⚠️ broadcastCashierTableState failed: $e');
    }
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

  // --- Per-peer push for catch-up ---

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
      final wa = _snapshotWhatsApp();
      if (wa != null) {
        controller.pushWhatsAppConfigTo(peerId, wa);
      }
    } catch (e) {
      debugPrint('⚠️ _pushSnapshotsTo($peerId) failed: $e');
    }
  }

  /// Broadcast the WAWP credentials to every connected waiter. No debounce
  /// needed — these only change when BranchService seeds them after login
  /// (once) or the merchant edits branch settings (rare).
  void _broadcastWhatsAppConfig() {
    if (!_started) return;
    final payload = _snapshotWhatsApp();
    if (payload == null) return;
    controller.broadcastWhatsAppConfig(payload);
    debugPrint('📤 CONFIG_WHATSAPP (instance="${payload['instance_id']}")');
  }

  /// `{instance_id, access_token}` from the live WAWP config, or null when
  /// the branch has no credentials configured (nothing to share).
  Map<String, dynamic>? _snapshotWhatsApp() {
    final cfg = whatsAppService.config;
    if (!cfg.isApiReady) return null;
    return <String, dynamic>{
      'instance_id': cfg.instanceId,
      'access_token': cfg.accessToken,
    };
  }

  // --- Snapshot composition ---

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
      // Only sync kitchen-side roles; general-role printers may not be reachable from waiter LAN.
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
    // Empty host = "no endpoint"; still broadcast (enabled:false) so waiters clear stale state.
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
