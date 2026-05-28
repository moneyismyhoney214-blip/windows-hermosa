import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../dialogs/booking_details_dialog.dart';
import '../dialogs/booking_refund_dialog.dart';
import '../dialogs/edit_order_dialog.dart';
import '../dialogs/waitlist_notify_dialog.dart';
import '../dialogs/waitlist_seat_dialog.dart';
import '../locator.dart';
import '../models.dart';
import '../models/booking_invoice.dart';
import '../models/waitlist_entry.dart';
import '../services/api/api_constants.dart';
import '../services/api/auth_service.dart';
import '../services/api/device_service.dart';
import '../services/api/order_service.dart';
import '../services/api/table_service.dart';
import '../services/app_themes.dart';
import '../services/cashier_mesh_bootstrap.dart';
import '../services/language_service.dart';
import '../services/logger_service.dart';
import '../services/print_orchestrator_service.dart';
import '../services/printer_role_registry.dart';
import '../services/waitlist_assign_controller.dart';
import '../services/waitlist_service.dart';
import '../services/whatsapp_service.dart';
import '../utils/order_status.dart';
import '../utils/ui_feedback.dart';
import '../waiter_module/dialogs/send_cashier_message_dialog.dart';
import '../waiter_module/models/table_pickup_request.dart';
import '../waiter_module/models/waiter_table_event.dart';
import '../waiter_module/services/waiter_controller.dart';
import '../waiter_module/widgets/waiter_status_chip.dart';
import '../widgets/waitlist_assign_banner.dart';
import '../widgets/waitlist_sheet.dart';

part 'table_management_screen_parts/table_management_screen.helper_widgets.dart';
part 'table_management_screen_parts/table_management_screen.builders.dart';

class TableManagementScreen extends StatefulWidget {
  final VoidCallback onBack;
  final Function(TableItem) onTableTap;

  /// Print an order-change ticket to the kitchen printers. Same callback
  /// the orders screen wires into [EditOrderDialog] — passed through so the
  /// cashier can edit a table's order straight from the tables grid and
  /// still get the kitchen "changes" ticket.
  final void Function(
    List<OrderChange> changes,
    String orderNumber, {
    bool isFullCancel,
    String? customerName,
    String? employeeName,
  })? onPrintOrderChanges;

  const TableManagementScreen({
    super.key,
    required this.onBack,
    required this.onTableTap,
    this.onPrintOrderChanges,
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

  /// `tableId -> bookingId` for busy tables whose order was NOT created through the waiter mesh.
  /// Filled from recent-bookings so long-press actions appear for cashier-created orders.
  final Map<String, String> _bookingByTable = {};

  /// Latest pickup request per table id (outstanding broadcast or recently-claimed/cancelled).
  final Map<String, TablePickupRequest> _pickupByTable = {};

  /// Table ids where a waiter is composing the first order (renders "جاري اخذ الطلب").
  final Set<String> _takingOrderTables = {};

  StreamSubscription<TablePickupRequest>? _pickupUpdateSub;
  StreamSubscription<WaiterTableEventEnvelope>? _tableEventSub;
  /// Backstop poll for stale "taking order" rows; no-ops when nothing is pending.
  Timer? _stalenessTimer;
  /// Continuous ~40s reconcile so out-of-band order changes mirror into the waiter mesh.
  Timer? _reconcileTimer;
  /// Re-entrancy guard against overlapping `_hydrateFromRegistry` passes.
  bool _loadingTables = false;

  @override
  void initState() {
    super.initState();
    translationService.addListener(_onLanguageChanged);
    _pickupUpdateSub = _waiter.onPickupUpdate.listen(_onPickupUpdate);
    _tableEventSub = _waiter.onTableEvent.listen(_onTableEvent);
    _waiter.pickupStore.addListener(_onPickupStoreChanged);
    // Waitlist: hydrate stores; re-render on active-entry changes or assign-mode.
    unawaited(waitlistService.initialize());
    unawaited(whatsAppService.initialize());
    waitlistService.addListener(_onWaitlistChanged);
    waitlistAssignController.addListener(_onAssignModeChanged);
    _stalenessTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (mounted && !_loadingTables && _takingOrderTables.isNotEmpty) {
        unawaited(_loadTables(silent: true));
      }
    });
    _reconcileTimer = Timer.periodic(const Duration(seconds: 40), (_) {
      if (mounted && !_loadingTables) {
        unawaited(_loadTables(silent: true));
      }
    });
    _loadTables();
  }

  @override
  void dispose() {
    translationService.removeListener(_onLanguageChanged);
    _pickupUpdateSub?.cancel();
    _tableEventSub?.cancel();
    _stalenessTimer?.cancel();
    _reconcileTimer?.cancel();
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
    // "Seat now" on a party already assigned → open that table directly.
    final pending = waitlistAssignController.pending;
    if (waitlistAssignController.seatImmediately &&
        pending != null &&
        pending.status == WaitlistStatus.notified &&
        (pending.assignedTableId ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!(waitlistAssignController.seatImmediately &&
            waitlistAssignController.pending?.id == pending.id)) {
          return;
        }
        TableItem? target;
        for (final t in _tables) {
          if (t.id == pending.assignedTableId) {
            target = t;
            break;
          }
        }
        if (target == null) return;
        waitlistAssignController.clear();
        unawaited(waitlistService.markSeated(pending.id));
        _checkTableStatus(target);
      });
    }
  }

  void _onPickupStoreChanged() {
    if (!mounted) return;
    final next = <String, TablePickupRequest>{};
    for (final req in _waiter.pickupStore.all) {
      // Store is newest-first; keep first per table.
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
    // Claim flips local table to occupied; cancel only clears overlay.
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
    if (envelope.fromSelf) return;
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
        // Promote out of "taking order" on first send / update.
        _takingOrderTables.remove(event.tableId);
        break;
      case TableLifecycleKind.paid:
        // Paid-but-still-seated: stays occupied until explicit release.
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
        // Detach waitlist row so future walk-in isn't mis-attributed.
        unawaited(waitlistService.detachSeatedFromTable(event.tableId));
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
        SnackBar(
          content: Text(translationService.t('no_waiter_online_pickup')),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
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
      UiFeedback.success(
        context,
        translationService.t(
          'pickup_request_sent_for_table',
          args: {'number': table.number},
        ),
      );
    } on StateError catch (e) {
      UiFeedback.info(
        context,
        translationService.t('request_send_failed_n', args: {'error': '$e'}),
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

  /// Cashier-driven force-release for stuck "paid-but-still-seated" tables; confirms because mis-tap wipes state on all peers.
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
              translationService.t(
                'release_table_n',
                args: {'number': table.number},
              ),
              style: TextStyle(color: context.appText, fontSize: 17),
            ),
          ],
        ),
        content: Text(
          translationService.t(
            'release_table_body_n',
            args: {'name': ownership.waiterName},
          ),
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
            label: Text(translationService.t('release_table_btn')),
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
    UiFeedback.success(
      context,
      translationService.t(
        'table_released_n',
        args: {'number': table.number},
      ),
    );
  }

  Future<void> _refundTableBooking(TableItem table, String bookingId) async {
    final refunded = await showBookingRefundDialog(
      context: context,
      bookingId: bookingId,
      bookingLabel: translationService.t(
        'waiter_booking_table_label',
        args: {'table': table.number},
      ),
    );
    if (refunded != null && mounted) {
      await _reconcileTableAfterBookingMutation(table, bookingId);
    }
  }

  Future<void> _cancelTableBooking(TableItem table, String bookingId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.appSurface,
        title: Text(translationService.t('cancel_booking_title'),
            style: TextStyle(color: ctx.appText)),
        content: Text(
          translationService.t(
            'confirm_cancel_table_booking_n',
            args: {'number': table.number},
          ),
          style: TextStyle(color: ctx.appText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(translationService.t('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(translationService.t('yes_cancel')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // Build kitchen cancel ticket from current lines before status 8.
    List<OrderChange> cancelChanges = const [];
    try {
      final details = await getIt<OrderService>().getBookingDetails(bookingId);
      final inner = (details['data'] is Map)
          ? Map<String, dynamic>.from(details['data'] as Map)
          : Map<String, dynamic>.from(details);
      for (final key in const ['meals', 'booking_meals', 'items']) {
        final v = inner[key];
        if (v is List && v.isNotEmpty) {
          cancelChanges = v.whereType<Map>().map((m) {
            final mm = m.map((k, val) => MapEntry(k.toString(), val));
            return OrderChange(
              type: 'cancel',
              name: (mm['meal_name'] ?? mm['item_name'] ?? mm['name'] ?? '')
                  .toString(),
              quantity:
                  int.tryParse(mm['quantity']?.toString() ?? '1') ?? 1,
            );
          }).toList();
          break;
        }
      }
    } catch (e) {
      Log.d('TableManagementScreen', 'extract meals for cancel ticket failed (non-fatal): $e');
    }
    try {
      await getIt<OrderService>().updateBookingStatus(
        orderId: bookingId,
        status: 8,
      );
    } catch (e) {
      if (!mounted) return;
      UiFeedback.error(
        context,
        translationService.t(
          'cancel_booking_failed_n',
          args: {'error': '$e'},
        ),
      );
      return;
    }
    if (cancelChanges.isNotEmpty) {
      widget.onPrintOrderChanges
          ?.call(cancelChanges, bookingId, isFullCancel: true);
    }
    if (!mounted) return;
    UiFeedback.success(
      context,
      translationService.t(
        'table_booking_cancelled_n',
        args: {'number': table.number},
      ),
    );
    await _reconcileTableAfterBookingMutation(table, bookingId);
  }

  /// After a booking is mutated, re-pull state and broadcast `released`/`updated` to all peers.
  Future<void> _reconcileTableAfterBookingMutation(
    TableItem table,
    String bookingId,
  ) async {
    try {
      final after = await getIt<OrderService>().getBookingDetails(bookingId);
      // 500 sentinel from detail endpoint is a transient hiccup; skip and rely on getTables reload.
      if (after['status']?.toString().trim() == '500') {
        if (mounted) await _loadTables(silent: true);
        return;
      }
      final inner = (after['data'] is Map)
          ? Map<String, dynamic>.from(after['data'] as Map)
          : Map<String, dynamic>.from(after);
      final refreshed = Booking.fromJson(inner);
      final statusStr = refreshed.status.toString().toLowerCase();
      List<Map<String, dynamic>> rawMeals = const [];
      for (final key in const [
        'meals',
        'booking_meals',
        'booking_products',
        'booking_items',
        'items',
        'invoice_items',
      ]) {
        final v = inner[key];
        if (v is List) {
          final rows = v
              .whereType<Map>()
              .map((e) => e.map((k, val) => MapEntry(k.toString(), val)))
              .toList();
          if (rows.isNotEmpty) {
            rawMeals = rows;
            break;
          }
        }
      }
      // Only release on positive cancellation evidence — empty meals alone is ambiguous.
      final cancelled = statusStr == '8' ||
          statusStr == 'cancelled' ||
          statusStr == 'canceled' ||
          statusStr.contains('cancel');
      final waiterId = _waiter.tableRegistry.ownerIdFor(table.id) ?? '';
      final waiterName = _waiter.tableRegistry.ownerNameFor(table.id) ?? '';
      if (cancelled) {
        _waiter.broadcastTableEvent(TableLifecycleEvent(
          kind: TableLifecycleKind.released,
          tableId: table.id,
          tableNumber: table.number,
          waiterId: waiterId,
          waiterName: waiterName,
        ));
      } else if (rawMeals.isNotEmpty) {
        double toD(Object? x) {
          if (x is num) return x.toDouble();
          return double.tryParse(x?.toString() ?? '') ?? 0;
        }

        final snapshots = rawMeals.map((row) {
          var qty = toD(row['quantity'] ?? 1);
          if (qty == 0) qty = 1;
          final unit = row['unit_price'] != null
              ? toD(row['unit_price'])
              : toD(row['price']) / qty;
          final note = (row['note'] ?? row['notes'] ?? '').toString();
          return TableItemSnapshot(
            name: (row['meal_name'] ?? row['item_name'] ?? row['name'] ?? '')
                .toString(),
            quantity: qty,
            unitPrice: unit,
            note: note.isEmpty ? null : note,
            mealId: (row['meal_id'] ?? row['id'])?.toString(),
            categoryId: row['category_id']?.toString(),
          );
        }).toList();
        final preTax = snapshots.fold<double>(0, (s, it) => s + it.lineTotal);
        final cnt = snapshots.fold<int>(0, (s, it) => s + it.quantity.round());
        _waiter.broadcastTableEvent(TableLifecycleEvent(
          kind: TableLifecycleKind.updated,
          tableId: table.id,
          tableNumber: table.number,
          waiterId: waiterId,
          waiterName: waiterName,
          guestCount: _waiter.tableRegistry.guestCountFor(table.id),
          total: preTax,
          itemCount: cnt,
          items: snapshots,
          orderId: bookingId,
        ));
      }
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
      // Peers will reconcile on their next getTables() poll.
    }
    if (mounted) await _loadTables(silent: true);
  }

  Future<Map<String, dynamic>?> _fetchBookingDetailsForTable(
    String bookingId,
  ) async {
    try {
      return await getIt<OrderService>().getBookingDetails(bookingId);
    } catch (e) {
      if (mounted) {
        UiFeedback.info(
          context,
          translationService.t(
            'order_details_fetch_failed_n',
            args: {'error': '$e'},
          ),
        );
      }
      return null;
    }
  }

  Future<void> _showTableOrderDetails(
    TableItem table,
    String bookingId,
  ) async {
    final details = await _fetchBookingDetailsForTable(bookingId);
    if (details == null || !mounted) return;
    _applyWaitlistCustomerName(details, table.id);
    await showDialog<void>(
      context: context,
      builder: (_) => BookingDetailsDialog(
        bookingData: details,
        onEditOrder: table.isPaid
            ? null
            : () => _editTableOrder(table, bookingId, prefetched: details),
        onRefund: () => _refundTableBooking(table, bookingId),
      ),
    );
  }

  /// Prefer waitlist party name over backend default "عميل عام" for tables.
  void _applyWaitlistCustomerName(Map<String, dynamic> data, String tableId) {
    final name = waitlistService.customerNameForTable(tableId)?.trim();
    if (name != null && name.isNotEmpty) {
      data['customer_name'] = name;
      data['client_name'] = name;
    }
  }

  Future<void> _editTableOrder(
    TableItem table,
    String bookingId, {
    Map<String, dynamic>? prefetched,
  }) async {
    final details = prefetched ?? await _fetchBookingDetailsForTable(bookingId);
    if (details == null || !mounted) return;
    _applyWaitlistCustomerName(details, table.id);
    final data = details['data'] is Map
        ? Map<String, dynamic>.from(details['data'] as Map)
        : Map<String, dynamic>.from(details);
    // Ensure booking id present so EditOrderDialog PATCHes the right record.
    data['id'] ??= int.tryParse(bookingId) ?? bookingId;
    _applyWaitlistCustomerName(data, table.id);
    final booking = Booking.fromJson(data);
    // Closed/cancelled/invoiced/paid bookings can't be edited (same gate as orders screen).
    if (table.isPaid ||
        isOrderLockedValue(booking.status) ||
        isOrderLockedValue(data['status'])) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(duration: const Duration(seconds: 3), content: Text(translationService.t('order_no_edit'))),
      );
      return;
    }
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => EditOrderDialog(
        booking: booking,
        bookingData: details,
        onPrintChanges: widget.onPrintOrderChanges,
      ),
    );
    if (updated == true && mounted) {
      await _reconcileTableAfterBookingMutation(table, bookingId);
    }
  }

  Future<void> _openSendMessageDialog() async {
    await showDialog<bool>(
      context: context,
      builder: (_) => SendCashierMessageDialog(controller: _waiter),
    );
  }

  Future<void> _migrateTable(TableItem source) async {
    if (source.status == TableStatus.available) return;

    // Destinations: active + available tables (excluding source).
    final destinations = _tables
        .where((t) =>
            t.id != source.id &&
            t.status == TableStatus.available &&
            (_deactivatedTables[t.id] ?? false) == false)
        .toList();
    if (destinations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(translationService.t('waiter_tables_no_empty_target')),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
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

    // Re-validate destination right before broadcasting to avoid merging two parties' carts.
    final latestIdx = _tables.indexWhere((t) => t.id == picked.id);
    if (latestIdx < 0) {
      UiFeedback.warning(
        context,
        translationService.t(
          'table_no_longer_exists_move_cancelled',
          args: {'number': picked.number},
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
      UiFeedback.warning(
        context,
        translationService.t(
          'waiter_tables_destination_taken',
          args: {'table': picked.number},
        ),
      );
      return;
    }

    // Broadcast: owning waiter shuffles cart and re-broadcasts release+assign.
    try {
      final event = _waiter.migrateTable(
        oldTableId: source.id,
        oldTableNumber: source.number,
        newTableId: picked.id,
        newTableNumber: picked.number,
      );
      if (event == null) return;
      // Move customer↔table binding so migrated table keeps the same customer (mesh-synced).
      unawaited(waitlistService.reassignAssignedTable(
        source.id,
        picked.id,
        toTableNumber: picked.number,
      ));
    } on StateError catch (e) {
      if (!mounted) return;
      UiFeedback.info(
        context,
        translationService.t(
          'table_move_failed_n',
          args: {'error': '$e'},
        ),
      );
      return;
    }

    // Optimistic local flip; waiter echo reaffirms.
    setState(() {
      final srcIdx = _tables.indexWhere((t) => t.id == source.id);
      if (srcIdx >= 0) {
        _tables[srcIdx].status = TableStatus.available;
        _tables[srcIdx].waiterName = null;
      }
      final dstIdx = _tables.indexWhere((t) => t.id == picked.id);
      if (dstIdx >= 0) {
        _tables[dstIdx].status = TableStatus.occupied;
        _tables[dstIdx].waiterName = source.waiterName;
      }
      _pickupByTable.remove(source.id);
    });

    // Migration ticket: tell kitchen the fired order moved; failures surface via snackbar.
    unawaited(_printMigrationTicket(source: source, destination: picked));

    if (!mounted) return;
    UiFeedback.success(
      context,
      translationService.t(
        'table_moved_n_to_n',
        args: {'from': source.number, 'to': picked.number},
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
          SnackBar(
            content: Text(
              '⚠️ ${translationService.t('table_moved_no_kitchen_printer')}',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
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
      UiFeedback.warning(
        context,
        '⚠️ ${translationService.t('migration_ticket_print_failed_n', args: {'error': '$e'})}',
      );
    }
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadTables({bool silent = false}) async {
    if (_loadingTables) return;
    _loadingTables = true;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final tables = await _tableService.getTables();

      for (var table in tables) {
        _deactivatedTables[table.id] = !table.isActive;
      }

      // Evict ghost rows before mirroring registry; preserve broadcast pay-later bookings.
      _waiter.tableRegistry.reconcileWithBackend(
        tables
            .where((t) => t.isActive && t.status == TableStatus.available)
            .map((t) => t.id),
        selfId: _waiter.session.self?.id,
        evictCommitted: false,
      );

      // Overlay live mesh state so existing ownership survives navigate-away/back.
      _hydrateFromRegistry(tables);

      if (mounted) {
        setState(() {
          _tables = tables;
          _isLoading = false;
        });
      }

      // Resolve booking ids for cashier-created tables not on the mesh.
      unawaited(_refreshTableBookings(tables));
    } catch (e) {
      if (mounted) {
        if (silent) {
          // Transient hiccup on silent refresh — keep existing list.
          debugPrint('⚠️ table_management silent refresh failed: $e');
        } else {
          setState(() {
            _error = e.toString();
            _isLoading = false;
          });
        }
      }
    } finally {
      _loadingTables = false;
    }
  }

  /// Reconcile recent-bookings against waiter-mesh registry: rebuilds [_bookingByTable] and
  /// re-broadcasts missed deltas (paymentPending for new, released for closed). Conservative —
  /// only acts on positive evidence; never touches takingOrder/assigned/paid rows.
  Future<void> _refreshTableBookings(List<TableItem> tables) async {
    final activeById = <String, TableItem>{
      for (final t in tables)
        if (t.isActive) t.id: t,
    };
    if (activeById.isEmpty) {
      if (_bookingByTable.isNotEmpty && mounted) {
        setState(_bookingByTable.clear);
      }
      return;
    }
    try {
      final resp = await getIt<OrderService>().getBookings(perPage: 100);
      final data = resp['data'];
      if (data is! List) return;

      bool isTruthy(dynamic v) =>
          v == true || v == 1 || v == '1' || v.toString().toLowerCase() == 'true';

      // tableId -> highest-id live bookingId (not paid, not cancelled).
      final liveBookingByTable = <String, int>{};
      final closedBookingIds = <String>{};
      final knownBookingIds = <String>{};
      // bookingId -> {total, itemCount} for enriching mesh broadcast.
      final liveBookingMeta = <String, ({double total, int itemCount})>{};

      for (final raw in data) {
        if (raw is! Map) continue;
        final m = raw.cast<String, dynamic>();
        final bid = int.tryParse(
            (m['booking_id'] ?? m['id'] ?? '').toString().trim());
        if (bid == null) continue;
        final bidStr = bid.toString();
        knownBookingIds.add(bidStr);
        final statusStr = (m['status'] ?? '').toString().trim();
        final statusLower = statusStr.toLowerCase();
        final cancelled = statusStr == '8' ||
            statusLower.contains('cancel');
        final paid = isTruthy(m['is_paid']) ||
            (statusStr.isNotEmpty && isOrderLockedValue(statusStr));
        final closed = cancelled || paid;
        if (closed) closedBookingIds.add(bidStr);

        final tableId =
            (m['table_id'] ?? m['restaurant_table_id'])?.toString().trim();
        if (tableId == null ||
            tableId.isEmpty ||
            !activeById.containsKey(tableId)) {
          continue;
        }
        if (closed) continue;
        final cur = liveBookingByTable[tableId];
        if (cur == null || bid > cur) {
          liveBookingByTable[tableId] = bid;
          final total = (m['grand_total'] ?? m['total'] ?? m['total_price']);
          final totalNum = (total is num)
              ? total.toDouble()
              : double.tryParse(total?.toString() ?? '') ?? 0.0;
          final meals = m['booking_meals'] ?? m['meals'] ?? m['booking_products'];
          final count = (meals is List) ? meals.length : 0;
          liveBookingMeta[bidStr] = (total: totalNum, itemCount: count);
        }
      }

      if (!mounted) return;
      setState(() {
        _bookingByTable
          ..clear()
          ..addEntries(liveBookingByTable.entries
              .map((e) => MapEntry(e.key, e.value.toString())));
      });

      // Re-broadcast deltas the mesh missed.
      final mesh = getIt<CashierMeshBootstrap>();
      final reg = _waiter.tableRegistry;

      // (a) live backend booking unknown to registry → pending
      for (final entry in liveBookingByTable.entries) {
        final tableId = entry.key;
        final bidStr = entry.value.toString();
        final table = activeById[tableId];
        if (table == null) continue;
        // Don't pre-empt a waiter mid-compose; they'll broadcast on send.
        if (reg.takingOrderFor(tableId)) continue;
        final knownOrderId = reg.bookingIdFor(tableId);
        if (knownOrderId != null && knownOrderId.trim() == bidStr) continue;
        final meta = liveBookingMeta[bidStr];
        mesh.broadcastCashierTableState(
          tableId: tableId,
          tableNumber: table.number,
          reserved: true,
          bookingId: bidStr,
          total: meta?.total,
          itemCount: meta?.itemCount,
        );
        if (table.status == TableStatus.available) {
          table.status = TableStatus.occupied;
        }
      }

      // (b) registry pay-later row whose booking is now closed → release
      for (final table in activeById.values) {
        final snap = reg.lookup(table.id);
        if (snap == null) continue;
        if (!reg.paymentPendingFor(table.id)) continue;
        final orderId = reg.bookingIdFor(table.id)?.trim();
        if (orderId == null || orderId.isEmpty) continue;
        // Only act on positive evidence (id is in fetched list AND closed).
        if (!knownBookingIds.contains(orderId)) continue;
        if (!closedBookingIds.contains(orderId)) continue;
        if (liveBookingByTable.containsKey(table.id)) continue;
        mesh.broadcastCashierTableState(
          tableId: table.id,
          tableNumber: table.number,
          reserved: false,
        );
        table.status = TableStatus.available;
        table.waiterName = null;
        table.isPaid = false;
        _takingOrderTables.remove(table.id);
        unawaited(waitlistService.detachSeatedFromTable(table.id));
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('⚠️ table_management booking reconcile failed: $e');
    }
  }

  /// Resolve live booking id: registry first (waiter-created), then backend-derived map.
  String? _bookingIdForTable(String tableId) {
    final fromRegistry = _waiter.tableRegistry.bookingIdFor(tableId);
    if (fromRegistry != null && fromRegistry.trim().isNotEmpty) {
      return fromRegistry;
    }
    final fromBackend = _bookingByTable[tableId];
    if (fromBackend != null && fromBackend.trim().isNotEmpty) {
      return fromBackend;
    }
    return null;
  }

  /// Mirror in-memory registry onto fresh table list and replay pickup store on every load.
  void _hydrateFromRegistry(List<TableItem> tables) {
    _takingOrderTables.clear();
    for (final t in tables) {
      final ownership = _waiter.tableRegistry.lookup(t.id);
      if (ownership == null) continue;
      if (_waiter.tableRegistry.paidFor(t.id)) {
        t.isPaid = true;
        // Paid but still seated → occupied until explicit release.
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
    _pickupByTable.clear();
    for (final req in _waiter.pickupStore.all) {
      _pickupByTable.putIfAbsent(req.tableId, () => req);
    }
  }

  /// Single entry for table-card taps: waitlist assign flow first, then default open.
  Future<void> _handleTableTap(TableItem table) async {
    final pending = waitlistAssignController.pending;
    if (pending != null) {
      await _tryAssignWaitlistEntry(pending, table);
      return;
    }
    // A table held for a notified waitlist party is locked until confirmed/dropped.
    final held = waitlistService.entryForTable(table.id);
    if (held != null) {
      final choice = await WaitlistSeatDialog.show(
        context,
        entry: held,
        tableNumber: table.number,
      );
      if (choice == null || !mounted) return;
      if (choice == WaitlistSeatChoice.cancelHold) {
        final reg = _waiter.tableRegistry;
        final snap = reg.lookup(table.id);
        final hasOrder = reg.bookingIdFor(table.id) != null ||
            reg.paymentPendingFor(table.id) ||
            reg.paidFor(table.id) ||
            ((snap?.itemCount ?? 0) > 0);
        if (hasOrder) {
          UiFeedback.error(context, translationService.t('waitlist_cannot_revert_has_order'));
          return;
        }
        await waitlistService.releaseHold(held.id);
        return;
      }
      await waitlistService.markSeated(held.id);
      if (!mounted) return;
      await _checkTableStatus(table);
      return;
    }
    // Use live mesh state: prevent starting a second cart on an in-progress/paid table.
    final regSnap = _waiter.tableRegistry.lookup(table.id);
    if (regSnap != null) {
      final msg = _waiter.tableRegistry.takingOrderFor(table.id)
          ? 'نادل يقوم بأخذ طلب على هذه الطاولة الآن'
          : 'هذه الطاولة بها طلب مفتوح — اضغط مطوّلاً لإدارته';
      UiFeedback.error(context, msg);
      return;
    }
    await _checkTableStatus(table);
  }

  Future<void> _tryAssignWaitlistEntry(
    WaitlistEntry entry,
    TableItem table,
  ) async {
    if (table.status != TableStatus.available) {
      UiFeedback.error(context, translationService.t('waitlist_assign_table_unavailable'));
      return;
    }
    final existingHold = waitlistService.entryForTable(table.id);
    if (existingHold != null && existingHold.id != entry.id) {
      UiFeedback.error(context, 'الطاولة محجوزة بالفعل لـ ${existingHold.customerName}');
      return;
    }
    // "Seat now": hold + open, skipping waiting-message dialog.
    if (waitlistAssignController.seatImmediately) {
      await waitlistService.markNotified(
        entryId: entry.id,
        tableId: table.id,
        tableNumber: table.number,
      );
      waitlistAssignController.clear();
      if (!mounted) return;
      await _checkTableStatus(table);
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

  /// Bottom sheet listing every waiter on the LAN with live status (free/busy/on break).
  Future<void> _openWaitersSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AnimatedBuilder(
          animation: _waiter.roster,
          builder: (ctx, _) {
            final waiters = _waiter.roster.all
                .where((w) => !w.isViewer)
                .toList()
              ..sort((a, b) => a.name.compareTo(b.name));
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.appBorder,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(LucideIcons.users, color: context.appPrimary),
                        const SizedBox(width: 8),
                        Text(
                          'النوادل',
                          style: TextStyle(
                            color: context.appText,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (waiters.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Text(
                          'لا يوجد نادل متصل حالياً',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.appTextMuted),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(ctx).height * 0.5,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: waiters.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: context.appBorder.withValues(alpha: 0.5),
                          ),
                          itemBuilder: (_, i) {
                            final w = waiters[i];
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: context.appPrimary
                                        .withValues(alpha: 0.12),
                                    child: Text(
                                      w.name.isNotEmpty
                                          ? w.name.substring(0, 1)
                                          : '؟',
                                      style: TextStyle(
                                        color: context.appPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      w.name.isEmpty ? 'نادل' : w.name,
                                      style: TextStyle(
                                        color: context.appText,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  WaiterStatusChip(status: w.status),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _checkTableStatus(TableItem table) async {
    final tableDetails = await _tableService.getTableDetails(table.id);

    if (tableDetails == null || !tableDetails.isActive) {
      if (mounted) {
        _deactivatedTables[table.id] = true;
        setState(() {});

        unawaited(showDialog(
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
        ));
      }
    } else {
      // Fall back to list table if detail response is missing an id.
      final resolvedTable =
          tableDetails.id.trim().isNotEmpty ? tableDetails : table;
      final waiterLabel = resolvedTable.waiterName?.trim() ?? '';
      final isUnavailable = resolvedTable.status != TableStatus.available;

      if (isUnavailable) {
        if (!mounted) return;
        final isReservedState = resolvedTable.status == TableStatus.occupied &&
            waiterLabel.contains('محجوز');
        unawaited(showDialog(
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
        ));
        return;
      }

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
      // Full-screen (no parent AppBar) — own safe-area handling.
      body: SafeArea(
        child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
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
                        // Waitlist available when venue has waiters or WhatsApp notifications.
                        if (ApiConstants.whatsappEnabled ||
                            ApiConstants.haveWaiters)
                          _WaitlistHeaderIconButton(
                            count: waitlistService.activeCount,
                            onPressed: _openWaitlistSheet,
                          ),
                        if (ApiConstants.haveWaiters) ...[
                          IconButton(
                            onPressed: _openWaitersSheet,
                            tooltip: 'النوادل',
                            icon: const Icon(LucideIcons.users),
                            color: const Color(0xFFF58220),
                          ),
                          IconButton(
                            onPressed: _openSendMessageDialog,
                            tooltip: 'إرسال رسالة للنوادل',
                            icon: const Icon(LucideIcons.messageSquare),
                            color: const Color(0xFFF58220),
                          ),
                        ],
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
                            if (ApiConstants.whatsappEnabled ||
                                ApiConstants.haveWaiters)
                              _WaitlistHeaderActionBtn(
                                count: waitlistService.activeCount,
                                onTap: _openWaitlistSheet,
                              ),
                            if (ApiConstants.haveWaiters) ...[
                              const SizedBox(width: 8),
                              _HeaderActionBtn(
                                icon: LucideIcons.users,
                                label: 'النوادل',
                                onTap: _openWaitersSheet,
                              ),
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

            const WaitlistAssignBanner(),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildErrorView()
                      : filteredTables.isEmpty
                          ? _buildEmptyView()
                          : _buildTableGrid(_tablesForSelectedSection()),
            ),

            // Bottom category tabs filter the grid above.
            if (!_isLoading && _error == null && _tables.isNotEmpty)
              _buildSectionTabBar(),
          ],
        ),
        ),
      ),
    );
  }
}
