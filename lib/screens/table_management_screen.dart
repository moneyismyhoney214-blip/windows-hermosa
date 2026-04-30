import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../dialogs/waitlist_notify_dialog.dart';
import '../models.dart';
import '../models/waitlist_entry.dart';
import '../services/api/api_constants.dart';
import '../services/api/auth_service.dart';
import '../services/api/device_service.dart';
import '../services/api/table_service.dart';
import '../services/language_service.dart';
import '../services/app_themes.dart';
import '../services/print_orchestrator_service.dart';
import '../services/printer_role_registry.dart';
import '../services/waitlist_assign_controller.dart';
import '../services/waitlist_service.dart';
import '../services/whatsapp_service.dart';
import '../locator.dart';
import '../waiter_module/dialogs/send_cashier_message_dialog.dart';
import '../waiter_module/models/table_pickup_request.dart';
import '../waiter_module/models/waiter_table_event.dart';
import '../waiter_module/services/waiter_controller.dart';
import '../widgets/waitlist_assign_banner.dart';
import '../widgets/waitlist_sheet.dart';

class TableManagementScreen extends StatefulWidget {
  final VoidCallback onBack;
  final Function(TableItem) onTableTap;

  const TableManagementScreen({
    super.key,
    required this.onBack,
    required this.onTableTap,
  });

  @override
  State<TableManagementScreen> createState() => _TableManagementScreenState();
}

class _TableManagementScreenState extends State<TableManagementScreen> {
  final TableService _tableService = getIt<TableService>();
  final WaiterController _waiter = getIt<WaiterController>();

  bool _isLoading = true;
  String? _error;
  List<TableItem> _tables = [];

  final Map<String, bool> _deactivatedTables = {};
  String? _selectedSectionKey;

  /// Latest pickup request per table id. A table with an entry here has
  /// either an outstanding broadcast or a just-claimed/cancelled one
  /// still visible to the cashier for a few seconds.
  final Map<String, TablePickupRequest> _pickupByTable = {};

  /// Table ids where the owning waiter is currently composing the first
  /// order (opened the table but hasn't hit "Send to kitchen" yet). Renders
  /// as "جاري اخذ الطلب" on the card. Cleared when the waiter either sends
  /// the order or releases the table.
  final Set<String> _takingOrderTables = {};

  StreamSubscription<TablePickupRequest>? _pickupUpdateSub;
  StreamSubscription<WaiterTableEventEnvelope>? _tableEventSub;

  @override
  void initState() {
    super.initState();
    translationService.addListener(_onLanguageChanged);
    _pickupUpdateSub = _waiter.onPickupUpdate.listen(_onPickupUpdate);
    _tableEventSub = _waiter.onTableEvent.listen(_onTableEvent);
    _waiter.pickupStore.addListener(_onPickupStoreChanged);
    // Waitlist: hydrate the stores and re-render when active entries
    // change (badge count + "waiting for" pill) or when the host enters
    // table-assign mode.
    unawaited(waitlistService.initialize());
    unawaited(whatsAppService.initialize());
    waitlistService.addListener(_onWaitlistChanged);
    waitlistAssignController.addListener(_onAssignModeChanged);
    _loadTables();
  }

  @override
  void dispose() {
    translationService.removeListener(_onLanguageChanged);
    _pickupUpdateSub?.cancel();
    _tableEventSub?.cancel();
    _waiter.pickupStore.removeListener(_onPickupStoreChanged);
    waitlistService.removeListener(_onWaitlistChanged);
    waitlistAssignController.removeListener(_onAssignModeChanged);
    super.dispose();
  }

  void _onWaitlistChanged() {
    if (mounted) setState(() {});
  }

  void _onAssignModeChanged() {
    if (mounted) setState(() {});
  }

  void _onPickupStoreChanged() {
    if (!mounted) return;
    final next = <String, TablePickupRequest>{};
    for (final req in _waiter.pickupStore.all) {
      // Keep the newest per table (store already sorts newest first).
      next.putIfAbsent(req.tableId, () => req);
    }
    setState(() {
      _pickupByTable
        ..clear()
        ..addAll(next);
    });
  }

  void _onPickupUpdate(TablePickupRequest req) {
    if (!mounted) return;
    // Claim → mutate the local table so the card flips to the familiar
    // "occupied" look without waiting for the next API refresh. Cancel
    // just clears the overlay — the table stays on whatever status it
    // was before the request.
    if (req.isClaimed) {
      final idx = _tables.indexWhere((t) => t.id == req.tableId);
      if (idx >= 0) {
        final t = _tables[idx];
        t.status = TableStatus.occupied;
        t.waiterName = req.claimedByWaiterName;
      }
    }
    setState(() {
      _pickupByTable[req.tableId] = req;
    });
  }

  void _onTableEvent(WaiterTableEventEnvelope envelope) {
    if (!mounted) return;
    if (envelope.fromSelf) return; // cashier shouldn't re-apply its own echoes
    final event = envelope.event;
    final idx = _tables.indexWhere((t) => t.id == event.tableId);
    if (idx < 0) return;
    final t = _tables[idx];
    switch (event.kind) {
      case TableLifecycleKind.takingOrder:
        t.status = TableStatus.occupied;
        if (event.waiterName.isNotEmpty) {
          t.waiterName = event.waiterName;
        }
        _takingOrderTables.add(event.tableId);
        break;
      case TableLifecycleKind.assigned:
      case TableLifecycleKind.updated:
      case TableLifecycleKind.paymentPending:
        t.status = TableStatus.occupied;
        if (event.waiterName.isNotEmpty) {
          t.waiterName = event.waiterName;
        }
        // First real send (or any subsequent update) promotes the table
        // out of the "taking order" state.
        _takingOrderTables.remove(event.tableId);
        break;
      case TableLifecycleKind.paid:
        // Paid-but-still-seated: keep the table occupied until a
        // waiter (or the cashier via 3-dots menu) explicitly releases.
        // Flag isPaid so the card overlays the "paid" check icon; the
        // registry already carries paid=true for re-mount hydration.
        t.status = TableStatus.occupied;
        t.isPaid = true;
        if (event.waiterName.isNotEmpty) {
          t.waiterName = event.waiterName;
        }
        _takingOrderTables.remove(event.tableId);
        break;
      case TableLifecycleKind.released:
        t.status = TableStatus.available;
        t.waiterName = null;
        t.isPaid = false;
        _pickupByTable.remove(event.tableId);
        _takingOrderTables.remove(event.tableId);
        break;
    }
    setState(() {});
  }

  void _requestPickup(TableItem table) {
    final onlineWaiters = _waiter.roster.all
        .where((w) => !w.isViewer)
        .length;
    if (onlineWaiters == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد نادل متصل — لا يمكن إرسال طلب استلام.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    try {
      final req = _waiter.requestTablePickup(
        tableId: table.id,
        tableNumber: table.number,
      );
      if (req == null) return;
      setState(() {
        _pickupByTable[table.id] = req;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إرسال طلب استلام الطاولة ${table.number}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } on StateError catch (e) {
      // Cashier hasn't joined the mesh yet (pre-branch state). Surface
      // instead of silently dropping.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إرسال الطلب: $e')),
      );
    }
  }

  void _cancelPickup(TableItem table) {
    final existing = _pickupByTable[table.id];
    if (existing == null) return;
    _waiter.cancelTablePickup(existing.requestId);
    setState(() {
      _pickupByTable.remove(table.id);
    });
  }

  /// Cashier-driven force-release. Used when a table is stuck in
  /// "paid-but-still-seated" (the waiter ended their shift without
  /// tapping Release, or a ghost paid entry survived a disconnect).
  /// Shows a confirm dialog because this wipes the party's state on
  /// every peer — a mis-tap would make another waiter lose the live
  /// table they were serving.
  Future<void> _forceReleaseTable(TableItem table) async {
    final ownership = _waiter.tableRegistry.lookup(table.id);
    if (ownership == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(LucideIcons.logOut, color: Color(0xFFDC2626)),
            const SizedBox(width: 8),
            Text(
              'تحرير الطاولة ${table.number}',
              style: TextStyle(color: context.appText, fontSize: 17),
            ),
          ],
        ),
        content: Text(
          'هل تريد تحرير الطاولة يدوياً؟ سيتم إزالتها من لوحة النادل '
          '"${ownership.waiterName}" فوراً.',
          style: TextStyle(color: context.appText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(translationService.t('cancel')),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(LucideIcons.logOut, size: 16),
            label: const Text('تحرير الطاولة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _waiter.broadcastTableEvent(TableLifecycleEvent(
      kind: TableLifecycleKind.released,
      tableId: table.id,
      tableNumber: table.number,
      waiterId: ownership.waiterId,
      waiterName: ownership.waiterName,
    ));
    setState(() {
      final idx = _tables.indexWhere((t) => t.id == table.id);
      if (idx >= 0) {
        _tables[idx].status = TableStatus.available;
        _tables[idx].waiterName = null;
        _tables[idx].isPaid = false;
      }
      _takingOrderTables.remove(table.id);
      _pickupByTable.remove(table.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم تحرير الطاولة ${table.number}'),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openSendMessageDialog() async {
    await showDialog<bool>(
      context: context,
      builder: (_) => SendCashierMessageDialog(controller: _waiter),
    );
  }

  Future<void> _migrateTable(TableItem source) async {
    // The group has to be actually seated somewhere before it can be
    // migrated — an available table has no order to move.
    if (source.status == TableStatus.available) return;

    // Destinations: any ACTIVE + available table that isn't the source.
    final destinations = _tables
        .where((t) =>
            t.id != source.id &&
            t.status == TableStatus.available &&
            (_deactivatedTables[t.id] ?? false) == false)
        .toList();
    if (destinations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد طاولة فاضية للنقل إليها.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final picked = await showDialog<TableItem>(
      context: context,
      builder: (ctx) => _MigrateDestinationDialog(
        source: source,
        destinations: destinations,
      ),
    );
    if (picked == null) return;
    if (!mounted) return;

    // Re-validate the destination right before broadcasting. Between
    // dialog open and the cashier picking, a waiter may have claimed
    // the destination (via استلام), a pickup request may be pending
    // on it, or the table may have been deleted/deactivated by admin
    // — we must NOT overwrite it with the source's cart, which would
    // merge two parties' orders.
    final latestIdx = _tables.indexWhere((t) => t.id == picked.id);
    if (latestIdx < 0) {
      // Table was removed from the list entirely.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'الطاولة ${picked.number} لم تعد موجودة — النقل ملغي.',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    final latest = _tables[latestIdx];
    final pending = _pickupByTable[picked.id];
    final stillAvailable = latest.status == TableStatus.available &&
        (_deactivatedTables[picked.id] ?? false) == false &&
        pending?.isClaimed != true &&
        pending?.isPending != true;
    if (!stillAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'الطاولة ${picked.number} لم تعد متاحة — النقل ملغي.',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // Fire the broadcast — the owning waiter will shuffle its cart and
    // re-broadcast release+assign, which our _onTableEvent listener
    // then applies to the local _tables list.
    try {
      final event = _waiter.migrateTable(
        oldTableId: source.id,
        oldTableNumber: source.number,
        newTableId: picked.id,
        newTableNumber: picked.number,
      );
      if (event == null) return;
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر نقل الطاولة: $e')),
      );
      return;
    }

    // Optimistic local flip — the waiter's echo will reaffirm this.
    setState(() {
      final srcIdx = _tables.indexWhere((t) => t.id == source.id);
      if (srcIdx >= 0) {
        _tables[srcIdx].status = TableStatus.available;
        _tables[srcIdx].waiterName = null;
      }
      final dstIdx = _tables.indexWhere((t) => t.id == picked.id);
      if (dstIdx >= 0) {
        _tables[dstIdx].status = TableStatus.occupied;
        _tables[dstIdx].waiterName =
            source.waiterName; // carries to new table
      }
      _pickupByTable.remove(source.id);
    });

    // Print the migration ticket at the kitchen so the chef knows the
    // already-fired order at `source` is now under `picked`. Fire and
    // forget — success/failure is surfaced via a snackbar either way.
    unawaited(_printMigrationTicket(source: source, destination: picked));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم نقل الطاولة ${source.number} إلى الطاولة ${picked.number}',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _printMigrationTicket({
    required TableItem source,
    required TableItem destination,
  }) async {
    try {
      final deviceService = getIt<DeviceService>();
      final roleRegistry = getIt<PrinterRoleRegistry>();
      final orchestrator = getIt<PrintOrchestratorService>();
      await roleRegistry.initialize();

      final devices = await deviceService.getCachedDevices();
      final kitchenPrinters = devices.where((d) {
        final normalized = d.type.trim().toLowerCase();
        if (normalized != 'printer') return false;
        final role = roleRegistry.resolveRole(d);
        return role == PrinterRole.kitchen ||
            role == PrinterRole.kds ||
            role == PrinterRole.bar;
      }).toList(growable: false);

      if (kitchenPrinters.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ تم نقل الطاولة ولكن لا توجد طابعة مطبخ متصلة لطباعة التذكرة',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      final cashierName =
          getIt<AuthService>().getUser()?['name']?.toString().trim() ?? '';
      final migrationItems = <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'من: طاولة ${source.number}',
          'nameAr': 'من: طاولة ${source.number}',
          'quantity': 1,
          'tag': 'FROM',
          'tagAr': 'من',
          'tagPrimary': 'من',
          'tagSecondary': 'FROM',
          'tagColor': 'black',
        },
        <String, dynamic>{
          'name': 'إلى: طاولة ${destination.number}',
          'nameAr': 'إلى: طاولة ${destination.number}',
          'quantity': 1,
          'tag': 'TO',
          'tagAr': 'إلى',
          'tagPrimary': 'إلى',
          'tagSecondary': 'TO',
          'tagColor': 'green',
        },
      ];

      final noteBuffer = StringBuffer()
        ..writeln(
          '⚠️ الطلب الذي كان على الطاولة ${source.number} منقول إلى الطاولة ${destination.number}',
        );
      if (cashierName.isNotEmpty) {
        noteBuffer.writeln('بواسطة الكاشير: $cashierName');
      }

      final migrationId =
          'MIG-${source.number}-${destination.number}-${DateTime.now().millisecondsSinceEpoch}';
      await orchestrator.enqueueKitchenPrint(
        printers: kitchenPrinters,
        orderNumber: migrationId,
        orderType: 'نقل طاولة',
        items: migrationItems,
        note: noteBuffer.toString().trim(),
        tableNumber: destination.number,
        cashierName: cashierName.isEmpty ? null : cashierName,
        isRtl: true,
        primaryLang: 'ar',
      );
    } catch (e) {
      debugPrint('⚠️ migration ticket print failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ تم النقل ولكن تعذر طباعة تذكرة المطبخ: $e'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadTables() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tables = await _tableService.getTables();

      for (var table in tables) {
        _deactivatedTables[table.id] = !table.isActive;
      }

      // Overlay the live waiter-mesh state onto the freshly-loaded list
      // so states survive a navigate-away/back. Before this, the mount
      // only subscribed to *future* events — existing ownership from a
      // still-running shift looked "empty" until the next event fired.
      _hydrateFromRegistry(tables);

      if (mounted) {
        setState(() {
          _tables = tables;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// Mirror the authoritative in-memory registry onto the fresh list of
  /// tables, and replay the pickup store. Runs on every load so the
  /// cashier sees the current state immediately on re-entry.
  void _hydrateFromRegistry(List<TableItem> tables) {
    _takingOrderTables.clear();
    for (final t in tables) {
      final ownership = _waiter.tableRegistry.lookup(t.id);
      if (ownership == null) continue;
      if (_waiter.tableRegistry.paidFor(t.id)) {
        t.isPaid = true;
        // Paid but still seated: treat as occupied until the waiter
        // explicitly releases (see manual availability toggle).
        t.status = TableStatus.occupied;
      } else if (_waiter.tableRegistry.paymentPendingFor(t.id)) {
        t.status = TableStatus.occupied;
      } else {
        t.status = TableStatus.occupied;
      }
      if (ownership.waiterName.isNotEmpty) {
        t.waiterName = ownership.waiterName;
      }
      if (_waiter.tableRegistry.takingOrderFor(t.id)) {
        _takingOrderTables.add(t.id);
      }
    }
    // Replay the pickup store so pending/claimed banners survive nav.
    _pickupByTable.clear();
    for (final req in _waiter.pickupStore.all) {
      _pickupByTable.putIfAbsent(req.tableId, () => req);
    }
  }

  /// Single entry point for every tap on a table card. Routes through
  /// the waitlist assign flow first, then falls back to the default
  /// "open table" behaviour.
  Future<void> _handleTableTap(TableItem table) async {
    final pending = waitlistAssignController.pending;
    if (pending != null) {
      await _tryAssignWaitlistEntry(pending, table);
      return;
    }
    // If this table is already "holding" a notified party, open the
    // normal flow — the cashier is about to seat them.
    final linked = waitlistService.entryForTable(table.id);
    await _checkTableStatus(table);
    // Best-effort cleanup: after the cashier opens the table (order
    // screen), we mark the party as seated. If onTableTap didn't
    // actually open anything (e.g. a lock dialog showed instead) the
    // UI is still correct — the party stays "notified" until manually
    // resolved.
    if (linked != null && table.status == TableStatus.available) {
      unawaited(waitlistService.markSeated(linked.id));
    }
  }

  Future<void> _tryAssignWaitlistEntry(
    WaitlistEntry entry,
    TableItem table,
  ) async {
    if (table.status != TableStatus.available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          content: Text(
            translationService.t('waitlist_assign_table_unavailable'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }
    await WaitlistNotifyDialog.show(
      context,
      entry: entry,
      tableId: table.id,
      tableNumber: table.number,
    );
  }

  Future<void> _openWaitlistSheet() async {
    await WaitlistSheet.show(context);
  }

  Future<void> _checkTableStatus(TableItem table) async {
    final tableDetails = await _tableService.getTableDetails(table.id);

    if (tableDetails == null || !tableDetails.isActive) {
      if (mounted) {
        _deactivatedTables[table.id] = true;
        setState(() {});

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.block, color: Colors.red),
                const SizedBox(width: 8),
                Text(translationService.t('table_unavailable')),
              ],
            ),
            content: Text(
              translationService.t('table_disabled_by_admin'),
              textAlign: TextAlign.right,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(translationService.t('ok')),
              ),
            ],
          ),
        );
      }
    } else {
      // If the detail response has no id (malformed API response), fall back to
      // the original table from the list which always has a valid id.
      final resolvedTable =
          tableDetails.id.trim().isNotEmpty ? tableDetails : table;
      final waiterLabel = resolvedTable.waiterName?.trim() ?? '';
      final isUnavailable = resolvedTable.status != TableStatus.available;

      if (isUnavailable) {
        if (!mounted) return;
        final isReservedState = resolvedTable.status == TableStatus.occupied &&
            waiterLabel.contains('محجوز');
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.event_busy, color: Colors.orange),
                const SizedBox(width: 8),
                Text(isReservedState
                    ? translationService.t('table_reserved')
                    : translationService.t('table_occupied')),
              ],
            ),
            content: Text(
              isReservedState
                  ? translationService.t('table_cannot_create_order_reserved')
                  : translationService.t('table_cannot_create_order_open'),
              textAlign: TextAlign.right,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(translationService.t('ok')),
              ),
            ],
          ),
        );
        return;
      }

      // Table is active and available, proceed.
      widget.onTableTap(resolvedTable);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 1100;

    final filteredTables = _tables;

    return Scaffold(
      backgroundColor: context.appBg,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            // Header Bar
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 12 : 24,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: context.appCardBg,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: isCompact
                  ? Row(
                      children: [
                        IconButton(
                          onPressed: widget.onBack,
                          icon: const Icon(LucideIcons.chevronRight),
                          color: const Color(0xFFF58220),
                        ),
                        Expanded(
                          child: Text(
                            translationService.t('tables_management'),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: context.appText,
                            ),
                          ),
                        ),
                        if (ApiConstants.whatsappEnabled)
                          _WaitlistHeaderIconButton(
                            count: waitlistService.activeCount,
                            onPressed: _openWaitlistSheet,
                          ),
                        if (ApiConstants.haveWaiters)
                          IconButton(
                            onPressed: _openSendMessageDialog,
                            tooltip: 'إرسال رسالة للنوادل',
                            icon: const Icon(LucideIcons.messageSquare),
                            color: const Color(0xFFF58220),
                          ),
                        IconButton(
                          onPressed: _loadTables,
                          icon: const Icon(LucideIcons.refreshCw),
                          color: const Color(0xFFF58220),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: widget.onBack,
                          icon: const Icon(LucideIcons.chevronRight, size: 28),
                          label: Text(translationService.t('back'),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFF58220),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                        Text(translationService.t('tables_management'),
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: context.appText)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (ApiConstants.whatsappEnabled)
                              _WaitlistHeaderActionBtn(
                                count: waitlistService.activeCount,
                                onTap: _openWaitlistSheet,
                              ),
                            if (ApiConstants.haveWaiters) ...[
                              const SizedBox(width: 8),
                              _HeaderActionBtn(
                                icon: LucideIcons.messageSquare,
                                label: 'رسالة للنوادل',
                                onTap: _openSendMessageDialog,
                              ),
                            ],
                            const SizedBox(width: 8),
                            _HeaderActionBtn(
                              icon: LucideIcons.refreshCw,
                              label: translationService.t('refresh'),
                              onTap: _loadTables,
                            ),
                          ],
                        ),
                      ],
                    ),
            ),

            // Waitlist assign banner — collapses to zero height when
            // the host isn't in assign mode.
            const WaitlistAssignBanner(),

            // Content Area
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildErrorView()
                      : filteredTables.isEmpty
                          ? _buildEmptyView()
                          : _buildTableGrid(_tablesForSelectedSection()),
            ),

            // Bottom tabs — one per category, mirrors the reference layout
            // where switching DINE IN / BAR TABLE / VIP TABLE filters the
            // grid above.
            if (!_isLoading && _error == null && _tables.isNotEmpty)
              _buildSectionTabBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.alertCircle, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            translationService.t('error'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadTables,
            icon: const Icon(LucideIcons.refreshCw),
            label: Text(translationService.t('retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.layers, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(translationService.t('no_data'),
              style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildTableGrid(List<TableItem> tables) {
    // Use a single responsive grid for every screen size. The previous
    // free-positioned canvas didn't reflow on resize, so toggling
    // fullscreen made tiles vanish off-screen — the grid below always
    // fills the available width regardless of the parent's constraints.
    return LayoutBuilder(builder: (_, constraints) {
      final w = constraints.maxWidth;
      final double maxExtent = w < 430
          ? 120
          : w < 900
              ? 140
              : 170;
      return GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: maxExtent,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1.0,
        ),
        itemCount: tables.length,
        itemBuilder: (context, index) {
          final table = tables[index];
          final isDeactivated = _deactivatedTables[table.id] ?? false;

          final pickup = _pickupByTable[table.id];
          final hasMeshOwner =
              _waiter.tableRegistry.ownerIdFor(table.id) != null;
          final waitlistHold = waitlistService.entryForTable(table.id);
          final waiterEnabled = ApiConstants.haveWaiters;
          return _NormalTableCard(
            key: ValueKey('table_${table.id}'),
            table: table,
            isDeactivated: isDeactivated,
            compact: true,
            width: double.infinity,
            height: double.infinity,
            onTap: isDeactivated ? null : () => _handleTableTap(table),
            activePickup: pickup,
            onRequestPickup: (isDeactivated || !waiterEnabled)
                ? null
                : () => _requestPickup(table),
            onCancelPickup: (isDeactivated || !waiterEnabled)
                ? null
                : () => _cancelPickup(table),
            onMigrate: (isDeactivated || !waiterEnabled)
                ? null
                : () => _migrateTable(table),
            onReleaseTable: (isDeactivated || !hasMeshOwner || !waiterEnabled)
                ? null
                : () => _forceReleaseTable(table),
            isTakingOrder: _takingOrderTables.contains(table.id),
            guestCount: _waiter.tableRegistry.guestCountFor(table.id),
            holdingForName: waitlistHold?.customerName,
          );
        },
      );
    });
  }

  // Tables for the active bottom-tab section. If no section has been picked
  // yet, default to the first one so the screen is never blank.
  List<TableItem> _tablesForSelectedSection() {
    final sections = _groupBySection(_tables);
    if (sections.isEmpty) return const [];
    _selectedSectionKey ??= sections.first.key;
    final active = sections.firstWhere(
      (s) => s.key == _selectedSectionKey,
      orElse: () => sections.first,
    );
    _selectedSectionKey = active.key;
    return active.tables;
  }

  Widget _buildSectionTabBar() {
    final sections = _groupBySection(_tables);
    if (sections.length <= 1) return const SizedBox.shrink();
    final activeKey = _selectedSectionKey ?? sections.first.key;
    return Container(
      decoration: BoxDecoration(
        color: context.appCardBg,
        border: Border(
          top: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              for (final section in sections)
                Expanded(
                  child: InkWell(
                    onTap: () =>
                        setState(() => _selectedSectionKey = section.key),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: section.key == activeKey
                                ? const Color(0xFFF58220)
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        section.title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: section.key == activeKey
                              ? const Color(0xFFF58220)
                              : context.appText,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Groups tables by `category_name`. The "General" bucket is always
  // present (even when empty) so the user can land on it after a refresh
  // even if the backend now returns a category for every table.
  List<_RestaurantTableSection> _groupBySection(List<TableItem> tables) {
    const generalKey = '__none__';
    final generalTitle = translationService.t('uncategorized_section');
    final order = <String>[generalKey];
    final byKey = <String, _RestaurantTableSection>{
      generalKey: _RestaurantTableSection(
        key: generalKey,
        title: generalTitle,
        tables: [],
      ),
    };
    for (final t in tables) {
      final raw = t.categoryName?.trim();
      final isGeneral = raw == null || raw.isEmpty;
      final key = isGeneral ? generalKey : raw;
      final title = isGeneral ? generalTitle : raw;
      final bucket = byKey.putIfAbsent(key, () {
        order.add(key);
        return _RestaurantTableSection(
            key: key, title: title, tables: []);
      });
      bucket.tables.add(t);
    }
    return [for (final k in order) byKey[k]!];
  }
}

class _RestaurantTableSection {
  final String key;
  final String title;
  final List<TableItem> tables;
  _RestaurantTableSection({
    required this.key,
    required this.title,
    required this.tables,
  });
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.1)
      ..strokeWidth = 1;

    const gridSize = 50.0;

    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


class _NormalTableCard extends StatelessWidget {
  final TableItem table;
  final bool isDeactivated;
  final VoidCallback? onTap;
  final bool compact;
  final double? width;
  final double? height;

  /// Most recent pickup state for this table. When non-null we overlay a
  /// status strip / cancel button; when null and the table is available
  /// we expose the "استلام" action so the cashier can broadcast.
  final TablePickupRequest? activePickup;
  final VoidCallback? onRequestPickup;
  final VoidCallback? onCancelPickup;
  final VoidCallback? onMigrate;
  /// Cashier force-release: clears the waiter's hold on an occupied
  /// table so it becomes available again. Manual only — the cashier
  /// decides when to fire this (no auto-timeout).
  final VoidCallback? onReleaseTable;
  /// Waiter has opened the table and is composing the first order but has
  /// not yet sent it to the kitchen. Shown to the cashier as
  /// "جاري اخذ الطلب" instead of the generic occupied label.
  final bool isTakingOrder;

  /// Number of guests the waiter set for this table (distinct from the
  /// table's capacity `seats`). Null when no active party.
  final int? guestCount;

  /// When non-null the table was handed to this waitlist party but
  /// they haven't arrived yet. Overrides the normal free-state color
  /// so the host doesn't accidentally double-book.
  final String? holdingForName;

  const _NormalTableCard({
    super.key,
    required this.table,
    required this.isDeactivated,
    this.onTap,
    this.compact = false,
    this.width,
    this.height,
    this.activePickup,
    this.onRequestPickup,
    this.onCancelPickup,
    this.onMigrate,
    this.onReleaseTable,
    this.isTakingOrder = false,
    this.guestCount,
    this.holdingForName,
  });

  bool get _isHoldingForWaitlist {
    if (isDeactivated) return false;
    if (table.status != TableStatus.available) return false;
    return holdingForName != null && holdingForName!.trim().isNotEmpty;
  }

  _TablePalette _paletteFor() {
    if (isDeactivated) {
      return const _TablePalette(
        background: Color(0xFFF1F5F9),
        border: Color(0xFFCBD5E1),
        accent: Color(0xFF64748B),
      );
    }
    if (_isHoldingForWaitlist) {
      // Warm amber — mirrors the waiter card + assign banner so the
      // host reads "this table is reserved for an incoming party" at
      // a glance.
      return const _TablePalette(
        background: Color(0xFFFEF3C7),
        border: Color(0xFFF59E0B),
        accent: Color(0xFFB45309),
      );
    }
    switch (table.status) {
      case TableStatus.available:
        return const _TablePalette(
          background: Color(0xFFDCFCE7),
          border: Color(0xFF16A34A),
          accent: Color(0xFF16A34A),
        );
      case TableStatus.occupied:
        return const _TablePalette(
          background: Color(0xFFFFFFFF),
          border: Color(0xFFDC2626),
          accent: Color(0xFFDC2626),
        );
      case TableStatus.printed:
        return const _TablePalette(
          background: Color(0xFFFEF3C7),
          border: Color(0xFFF59E0B),
          accent: Color(0xFFB45309),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _paletteFor();
    final subtitle = _subtitleLabel();

    return SizedBox(
      width: width ?? 140,
      height: height ?? 140,
      child: RepaintBoundary(
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: isDeactivated || !_hasAnyAction()
              ? const <Type, GestureRecognizerFactory>{}
              : <Type, GestureRecognizerFactory>{
                  LongPressGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          LongPressGestureRecognizer>(
                    () => LongPressGestureRecognizer(
                      duration: const Duration(seconds: 2),
                    ),
                    (instance) {
                      instance.onLongPressStart = (details) =>
                          _openActionsMenu(context, details.globalPosition);
                    },
                  ),
                },
          child: Material(
          color: palette.background,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: isDeactivated ? null : onTap,
            borderRadius: BorderRadius.circular(10),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.border, width: 1.4),
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          table.number,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDeactivated
                                ? palette.accent
                                : const Color(0xFF0F172A),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const Spacer(),
                        Align(
                          alignment: AlignmentDirectional.bottomEnd,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.user,
                                  size: 12, color: palette.accent),
                              const SizedBox(width: 2),
                              Text(
                                '${(guestCount != null && guestCount! > 0) ? guestCount : table.seats}',
                                style: TextStyle(
                                  color: palette.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (table.isPaid && !isDeactivated)
                    const PositionedDirectional(
                      bottom: 4,
                      start: 6,
                      child: Icon(
                        LucideIcons.dollarSign,
                        size: 12,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  // 3-dots menu was replaced by a 2-second long-press
                  // anywhere on the card — see RawGestureDetector above.
                  if (!isDeactivated && _showPickupHint())
                    PositionedDirectional(
                      bottom: 4,
                      start: table.isPaid ? 20 : 6,
                      child: _buildPickupHint(),
                    ),
                  if (isDeactivated)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.ban,
                                  color: Colors.white, size: 22),
                              const SizedBox(height: 4),
                              Text(
                                translationService.t('disabled'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }

  String? _subtitleLabel() {
    if (isDeactivated) return null;
    // Holding-for-waitlist overrides every other free-state signal —
    // that table is effectively reserved, so "بانتظار نادل" or similar
    // would confuse the host.
    if (_isHoldingForWaitlist) {
      return translationService.t(
        'waitlist_table_pill_waiting_for',
        args: {'name': holdingForName!},
      );
    }
    if (table.status == TableStatus.occupied && isTakingOrder) {
      return 'جاري اخذ الطلب';
    }
    if (table.status == TableStatus.printed) {
      return translationService.t('printed');
    }
    if (table.status == TableStatus.occupied) {
      final pickup = activePickup;
      if (pickup != null && pickup.isClaimed) {
        return pickup.claimedByWaiterName;
      }
      final name = table.waiterName?.trim() ?? '';
      if (name.isNotEmpty) return name;
      return translationService.t('occupied');
    }
    final pickup = activePickup;
    if (pickup != null && pickup.isPending) return 'بانتظار نادل...';
    if (pickup != null && pickup.isClaimed) {
      return '${pickup.claimedByWaiterName ?? ''} استلم';
    }
    return null;
  }

  bool _showPickupHint() {
    final pickup = activePickup;
    if (pickup != null && pickup.isPending) return true;
    return false;
  }

  Widget _buildPickupHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFF58220).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF58220)),
        ),
      ),
    );
  }

  bool _hasAnyAction() {
    final canPickup = activePickup == null &&
        table.status == TableStatus.available &&
        onRequestPickup != null;
    final canCancelPickup = activePickup != null &&
        activePickup!.isPending &&
        onCancelPickup != null;
    return canPickup ||
        canCancelPickup ||
        onMigrate != null ||
        onReleaseTable != null;
  }

  // Long-press anchor: opens the actions menu at the touch position
  // (instead of a fixed corner-anchored 3-dots button).
  Future<void> _openActionsMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromLTRB(
      globalPosition.dx,
      globalPosition.dy,
      overlay.size.width - globalPosition.dx,
      overlay.size.height - globalPosition.dy,
    );
    final value = await showMenu<String>(
      context: context,
      position: position,
      items: [
        if (activePickup == null &&
            table.status == TableStatus.available &&
            onRequestPickup != null)
          const PopupMenuItem<String>(
            value: 'pickup',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.handMetal,
                    size: 16, color: Color(0xFFF58220)),
                SizedBox(width: 8),
                Text(
                  'استلام',
                  style: TextStyle(
                    color: Color(0xFFF58220),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        if (activePickup != null &&
            activePickup!.isPending &&
            onCancelPickup != null)
          const PopupMenuItem<String>(
            value: 'cancel_pickup',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.x, size: 16, color: Color(0xFFDC2626)),
                SizedBox(width: 8),
                Text(
                  'إلغاء الاستلام',
                  style: TextStyle(
                    color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        if (onMigrate != null)
          const PopupMenuItem<String>(
            value: 'migrate',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.moveRight,
                    size: 16, color: Color(0xFF2563EB)),
                SizedBox(width: 8),
                Text(
                  'نقل إلى طاولة أخرى',
                  style: TextStyle(
                    color: Color(0xFF2563EB),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        if (onReleaseTable != null)
          const PopupMenuItem<String>(
            value: 'release',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.logOut, size: 16, color: Color(0xFFDC2626)),
                SizedBox(width: 8),
                Text(
                  'تحرير الطاولة',
                  style: TextStyle(
                    color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (value == 'pickup' && onRequestPickup != null) onRequestPickup!();
    if (value == 'cancel_pickup' && onCancelPickup != null) onCancelPickup!();
    if (value == 'migrate' && onMigrate != null) onMigrate!();
    if (value == 'release' && onReleaseTable != null) onReleaseTable!();
  }
}

class _TablePalette {
  final Color background;
  final Color border;
  final Color accent;

  const _TablePalette({
    required this.background,
    required this.border,
    required this.accent,
  });
}

class _HeaderActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeaderActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const btnColor = Color(0xFFF58220);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 8,
        ),
        child: Row(
          children: [
            Icon(icon, color: btnColor, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: btnColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

/// Compact icon-only waitlist button for the compact header layout.
class _WaitlistHeaderIconButton extends StatelessWidget {
  final int count;
  final VoidCallback onPressed;

  const _WaitlistHeaderIconButton({
    required this.count,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: translationService.t('waitlist_tooltip'),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        backgroundColor: const Color(0xFFDC2626),
        child: const Icon(LucideIcons.clock),
      ),
      color: const Color(0xFFF58220),
    );
  }
}

/// Full-width waitlist action button matching [_HeaderActionBtn] styling.
class _WaitlistHeaderActionBtn extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _WaitlistHeaderActionBtn({
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const btnColor = Color(0xFFF58220);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Badge(
              isLabelVisible: count > 0,
              label: Text('$count'),
              backgroundColor: const Color(0xFFDC2626),
              child: const Icon(LucideIcons.clock, color: btnColor, size: 18),
            ),
            const SizedBox(width: 8),
            Text(
              translationService.t('waitlist_title'),
              style: const TextStyle(
                color: btnColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _MigrateDestinationDialog extends StatelessWidget {
  final TableItem source;
  final List<TableItem> destinations;

  const _MigrateDestinationDialog({
    required this.source,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...destinations]
      ..sort((a, b) {
        final an = int.tryParse(a.number) ?? 0;
        final bn = int.tryParse(b.number) ?? 0;
        return an.compareTo(bn);
      });
    return AlertDialog(
      backgroundColor: context.appSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(LucideIcons.moveRight, color: Color(0xFF2563EB)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "نقل الطاولة ${source.number} إلى...",
              style: TextStyle(color: context.appText, fontSize: 17),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        height: 360,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 140,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.1,
          ),
          itemCount: sorted.length,
          itemBuilder: (_, i) {
            final t = sorted[i];
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).pop(t),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.appBorder),
                  color: context.appSurfaceAlt,
                ),
                padding: const EdgeInsets.all(10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.armchair,
                        color: context.appSuccess, size: 28),
                    const SizedBox(height: 8),
                    Text(
                      t.number,
                      style: TextStyle(
                        color: context.appText,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${t.seats} أشخاص",
                      style: TextStyle(
                        color: context.appTextMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("إلغاء"),
        ),
      ],
    );
  }
}
