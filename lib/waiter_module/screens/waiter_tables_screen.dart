import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../dialogs/booking_details_dialog.dart';
import '../../dialogs/booking_refund_dialog.dart';
import '../../dialogs/edit_order_dialog.dart';
import '../../dialogs/waitlist_notify_dialog.dart';
import '../../dialogs/waitlist_seat_dialog.dart';
import '../../locator.dart';
import '../../models.dart';
import '../../models/booking_invoice.dart';
import '../../models/waitlist_entry.dart';
import '../../services/api/order_service.dart';
import '../../services/api/table_service.dart';
import '../../services/app_themes.dart';
import '../../services/display_app_service.dart';
import '../../services/language_service.dart';
import '../../services/logger_service.dart';
import '../../services/waitlist_assign_controller.dart';
import '../../services/waitlist_service.dart';
import '../../utils/order_status.dart';
import '../../utils/ui_feedback.dart';
import '../../widgets/waitlist_assign_banner.dart';
import '../models/table_migrate_event.dart';
import '../models/waiter_table_event.dart';
import '../services/waiter_billing_service.dart';
import '../services/waiter_cart_store.dart';
import '../services/waiter_controller.dart';
import '../services/waiter_print_dispatcher.dart';
import '../services/waiter_table_customer_store.dart';
import '../services/waiter_table_registry.dart';
import '../theme/waiter_design.dart';
import '../widgets/skeleton_grid.dart';
import '../widgets/waiter_table_card.dart';
import 'waiter_order_screen.dart';

part 'waiter_tables_screen_parts/waiter_tables_screen.helper_widgets.dart';

/// Grid view of every table in the branch, with ownership and status
/// overlaid from the live [WaiterTableRegistry].
class WaiterTablesScreen extends StatefulWidget {
  final WaiterController controller;

  const WaiterTablesScreen({super.key, required this.controller});

  @override
  State<WaiterTablesScreen> createState() => _WaiterTablesScreenState();
}

class _WaiterTablesScreenState extends State<WaiterTablesScreen> {
  final TableService _tableService = getIt<TableService>();
  final WaiterTableRegistry _registry = getIt<WaiterTableRegistry>();

  List<TableItem> _tables = const [];
  bool _loading = true;
  Object? _error;
  String? _selectedSectionKey;
  StreamSubscription<TableMigrateEvent>? _migrateSub;
  StreamSubscription<WaiterTableEventEnvelope>? _lifecycleSub;
  StreamSubscription<String>? _openTableSub;

  @override
  void initState() {
    super.initState();
    _load();
    // Prime tax config so Edit Order dialog opened directly from the grid renders tax-inclusive prices.
    unawaited(getIt<WaiterBillingService>().refreshTaxConfig());
    unawaited(getIt<WaiterTableCustomerStore>().initialize());
    _registry.addListener(_onRegistry);
    // Listen to migrate + lifecycle for optimistic status flips before next getTables() poll.
    _migrateSub = widget.controller.onTableMigrate.listen(_onMigrate);
    _lifecycleSub =
        widget.controller.onTableEvent.listen(_onLifecycle);
    _openTableSub =
        widget.controller.onOpenTableRequest.listen(_onOpenTableRequest);
    waitlistAssignController.addListener(_onAssignModeChanged);
    waitlistService.addListener(_onAssignModeChanged);
  }

  @override
  void dispose() {
    _registry.removeListener(_onRegistry);
    _migrateSub?.cancel();
    _lifecycleSub?.cancel();
    _openTableSub?.cancel();
    waitlistAssignController.removeListener(_onAssignModeChanged);
    waitlistService.removeListener(_onAssignModeChanged);
    super.dispose();
  }

  void _onAssignModeChanged() {
    if (mounted) setState(() {});
    // "Seat now" on already-assigned party → jump straight into that table's order screen.
    final pending = waitlistAssignController.pending;
    if (waitlistAssignController.seatImmediately &&
        pending != null &&
        pending.status == WaitlistStatus.notified &&
        (pending.assignedTableId ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!(waitlistAssignController.seatImmediately &&
            waitlistAssignController.pending?.id == pending.id)) {
          return; // state moved on while we waited for the frame
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
        _openTable(target);
      });
    }
  }

  /// Called instead of `_openTable` when the host has a pending
  /// waitlist entry. Only free tables are valid targets; anything
  /// else gets a soft error snack.
  Future<void> _handleAssignTap(
    WaitlistEntry entry,
    TableItem table,
  ) async {
    final ownerId = _registry.ownerIdFor(table.id);
    final isAvailable =
        ownerId == null && table.status == TableStatus.available;
    if (!isAvailable) {
      UiFeedback.error(context, translationService.t('waitlist_assign_table_unavailable'));
      return;
    }
    // Already held for someone else — don't stack a second party on same table.
    final existingHold = waitlistService.entryForTable(table.id);
    if (existingHold != null && existingHold.id != entry.id) {
      UiFeedback.error(context, 'الطاولة محجوزة بالفعل لـ ${existingHold.customerName}');
      return;
    }
    // "Seat now": mark `notified` (paints pill + syncs to peers) but NOT `seated`
    // until an order commits, so backing out keeps the party queued.
    if (waitlistAssignController.seatImmediately) {
      await waitlistService.markNotified(
        entryId: entry.id,
        tableId: table.id,
        tableNumber: table.number,
      );
      waitlistAssignController.clear();
      if (!mounted) return;
      _openTable(table);
      return;
    }
    await WaitlistNotifyDialog.show(
      context,
      entry: entry,
      tableId: table.id,
      tableNumber: table.number,
    );
  }

  void _onLifecycle(WaiterTableEventEnvelope envelope) {
    if (!mounted) return;
    final event = envelope.event;
    // Deferred setState — lifecycle events can fire mid-build from another screen's initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final idx = _tables.indexWhere((t) => t.id == event.tableId);
      if (idx < 0) return;
      setState(() {
        switch (event.kind) {
          case TableLifecycleKind.released:
            // Optimistic flip to available before next getTables() poll.
            _tables[idx].status = TableStatus.available;
            _tables[idx].waiterName = null;
            _tables[idx].isPaid = false;
            // Drop pinned customer so next walk-in doesn't inherit it.
            try {
              getIt<WaiterTableCustomerStore>().clear(event.tableId);
            } catch (e) {
              Log.d('WaiterTablesScreen', 'clear pinned customer on release failed (non-fatal): $e');
            }
            unawaited(waitlistService.detachSeatedFromTable(event.tableId));
            break;
          case TableLifecycleKind.assigned:
          case TableLifecycleKind.takingOrder:
          case TableLifecycleKind.paymentPending:
          case TableLifecycleKind.paid:
          case TableLifecycleKind.updated:
            // Mirror onto t.status so behaviour stays identical after getTables() reloads.
            _tables[idx].status = TableStatus.occupied;
            break;
        }
      });
    });
  }

  void _onMigrate(TableMigrateEvent event) {
    if (!mounted) return;
    // Deferred post-frame to avoid mid-build setState from synchronous broadcast.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        final srcIdx =
            _tables.indexWhere((t) => t.id == event.oldTableId);
        if (srcIdx >= 0) {
          // Mirror onto backend-reported status so overlay renders "available".
          _tables[srcIdx].status = TableStatus.available;
          _tables[srcIdx].waiterName = null;
        }
        final dstIdx =
            _tables.indexWhere((t) => t.id == event.newTableId);
        if (dstIdx >= 0) {
          _tables[dstIdx].status = TableStatus.occupied;
        }
      });
    });
  }

  void _onRegistry() {
    if (!mounted) return;
    // Defer rebuild — registry can notify mid-build via another screen's initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// Keep every table visible — including ones the current waiter has
  /// already submitted (pay-later, paid-still-seated). The card's
  /// status pill + inline CTAs ("Edit Order", "تحرير الطاولة") signal
  /// what's still actionable. Hiding owned pay-later tables would
  /// strand the Edit Order button on a card the waiter can't reach.
  List<TableItem> _visibleTables() => _tables;

  /// Cancel a pay-later booking — mirrors the cashier's `_cancelBooking`
  /// flow (orders_screen.actions.dart): confirmation prompt → PATCH
  /// status=8 on the backend → fire-and-forget kitchen cancel ticket →
  /// flip the table to released so peers see it free immediately.
  Future<void> _cancelBookingForTable(TableItem table) async {
    final me = widget.controller.session.self;
    if (me == null) return;
    final bookingId = _registry.bookingIdFor(table.id);
    if (bookingId == null || bookingId.isEmpty) {
      UiFeedback.warning(context, translationService.t('waiter_no_active_booking'));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.appSurface,
        title: Text(
          translationService.t('waiter_action_cancel_booking'),
          style: TextStyle(color: context.appText),
        ),
        content: Text(
          translationService.t(
            'waiter_cancel_booking_body',
            args: {'table': table.number},
          ),
          style: TextStyle(color: context.appText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(translationService.t('waiter_cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: Text(translationService.t('waiter_confirm_cancel')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      // Status 8 = cancelled (cashier parity).
      await getIt<OrderService>().updateBookingStatus(
        orderId: bookingId,
        status: 8,
      );
      getIt<DisplayAppService>().notifyOrderCancelled(orderId: bookingId);
    } catch (e) {
      if (!mounted) return;
      UiFeedback.error(context, 'فشل إلغاء الحجز: $e');
      return;
    }

    // Fire-and-forget cancellation ticket so kitchen drops in-prep items.
    try {
      final details = await getIt<OrderService>().getBookingDetails(bookingId);
      final detailData = details['data'] is Map
          ? (details['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : details;
      final bookingNode = detailData['booking'] is Map
          ? (detailData['booking'] as Map)
              .map((k, v) => MapEntry(k.toString(), v))
          : detailData;
      final mealsList = (bookingNode['booking_meals'] ??
          bookingNode['meals'] ??
          bookingNode['items'] ??
          detailData['booking_meals']) as List?;
      if (mealsList != null && mealsList.isNotEmpty) {
        final cancelChanges = mealsList.map((meal) {
          final m = meal is Map
              ? meal.map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{};
          final name = (m['meal_name'] ??
                  m['name'] ??
                  m['item_name'] ??
                  '')
              .toString();
          final qty = int.tryParse(m['quantity']?.toString() ?? '1') ?? 1;
          return OrderChange(type: 'cancel', name: name, quantity: qty);
        }).toList();
        final orderNum = (bookingNode['daily_order_number'] ??
                bookingNode['order_number'] ??
                bookingId)
            .toString();
        unawaited(getIt<WaiterPrintDispatcher>().printKitchenChangeTicket(
          changes: cancelChanges,
          orderNumber: orderNum,
          isFullCancel: true,
        ));
      }
    } catch (e) {
      debugPrint('⚠️ Could not print waiter cancellation ticket: $e');
    }

    // Flush local cart + broadcast released so peers flip card without waiting on poll.
    try {
      getIt<WaiterCartStore>().clearTable(table.id);
    } catch (e) {
      Log.d('WaiterTablesScreen', 'clear local cart on cancel failed (non-fatal): $e');
    }
    widget.controller.broadcastTableEvent(TableLifecycleEvent(
      kind: TableLifecycleKind.released,
      tableId: table.id,
      tableNumber: table.number,
      waiterId: me.id,
      waiterName: me.name,
    ));

    if (!mounted) return;
    UiFeedback.success(context, 'تم إلغاء حجز الطاولة ${table.number}');
  }

  /// Refund / return items on a table's order — reuses the cashier's
  /// booking-refund dialog (which handles partial vs full refunds, the
  /// credit note, and the kitchen cancel ticket). Afterwards we reconcile
  /// the local sent-cart and, if the whole booking is gone, broadcast a
  /// `released` so peers flip the card to free immediately. Same pattern
  /// the Edit-Order flow uses on save.
  Future<void> _refundBookingForTable(TableItem table) async {
    final bookingId = _registry.bookingIdFor(table.id);
    if (bookingId == null || bookingId.isEmpty) {
      UiFeedback.warning(context, translationService.t('waiter_no_active_booking'));
      return;
    }
    final refunded = await showBookingRefundDialog(
      context: context,
      bookingId: bookingId,
      bookingLabel: 'طاولة ${table.number}',
    );
    if (refunded == null) return;

    // Reconcile local cart + broadcast since dialog already PATCHed backend.
    await _reconcileAndBroadcastAfterBackendMutation(table, bookingId);

    if (!mounted) return;
    await _load(silent: true);
    if (!mounted) return;
    UiFeedback.success(context, translationService.t('waiter_bill_success'));
  }

  void _releaseTable(TableItem table) {
    final me = widget.controller.session.self;
    if (me == null) return;
    widget.controller.broadcastTableEvent(TableLifecycleEvent(
      kind: TableLifecycleKind.released,
      tableId: table.id,
      tableNumber: table.number,
      waiterId: me.id,
      waiterName: me.name,
    ));
    // Flush local cart so re-entering doesn't resurface stale items.
    try {
      getIt<WaiterCartStore>().clearTable(table.id);
    } catch (e) {
      Log.d('WaiterTablesScreen', 'clear local cart on release failed (non-fatal): $e');
    }
    if (!mounted) return;
    UiFeedback.success(context, 'تم تحرير الطاولة ${table.number}');
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final tables = await _tableService.getTables();
      if (!mounted) return;
      // Reconcile persisted registry with backend — drop stale rows for tables
      // freed while this waiter was offline.
      final availableIds = tables
          .where((t) => t.isActive && t.status == TableStatus.available)
          .map((t) => t.id);
      _registry.reconcileWithBackend(
        availableIds,
        selfId: widget.controller.session.self?.id,
        // Only keep self-owned takingOrder while order screen is actively open,
        // so a missed `released` (Wi-Fi flap) can't strand the table.
        activeOrderingTableId: widget.controller.activeOrderingTableId,
      );
      setState(() {
        _tables = tables
            .where((t) => t.isActive)
            .toList()
          ..sort((a, b) {
            final aNum = int.tryParse(a.number) ?? 0;
            final bNum = int.tryParse(b.number) ?? 0;
            return aNum.compareTo(bNum);
          });
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent) {
        debugPrint('⚠️ waiter tables silent reload failed: $e');
      } else {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  /// Single tap entry point — routes to either the waitlist assign
  /// flow, the seat-confirmation flow for a held table, or the default
  /// "open table" flow.
  Future<void> _handleTap(TableItem table) async {
    final pending = waitlistAssignController.pending;
    if (pending != null) {
      await _handleAssignTap(pending, table);
      return;
    }
    // Tables held for a waitlisted party are LOCKED — host must confirm via dialog,
    // unless an order's already half-built (re-entry path).
    final held = waitlistService.entryForTable(table.id);
    if (held != null && !getIt<WaiterCartStore>().hasItems(table.id)) {
      final choice = await WaitlistSeatDialog.show(
        context,
        entry: held,
        tableNumber: table.number,
      );
      if (choice == null || !mounted) return;
      if (choice == WaitlistSeatChoice.cancelHold) {
        // Don't drop hold if order already started for this party on another device.
        final snap = _registry.lookup(table.id);
        final hasOrder = _registry.bookingIdFor(table.id) != null ||
            _registry.paymentPendingFor(table.id) ||
            _registry.paidFor(table.id) ||
            ((snap?.itemCount ?? 0) > 0);
        if (hasOrder) {
          UiFeedback.error(context, translationService.t('waitlist_cannot_revert_has_order'));
          return;
        }
        await waitlistService.releaseHold(held.id);
        return;
      }
      // Seat: open order screen. Hold/seated state is settled only on order
      // commit (see `_settleWaitlistHoldOnCommit` in WaiterOrderScreen).
    }
    _openTable(table);
  }

  /// Jump straight into the order-composition screen for [tableId] — wired
  /// to `controller.onOpenTableRequest`, so accepting a cashier pickup
  /// request (or a call pinned to a table) lands the waiter on the table
  /// ready to pick. No-ops if the table isn't known (stale id) or an order
  /// screen is already open for some table.
  Future<void> _onOpenTableRequest(String tableId) async {
    if (!mounted || tableId.isEmpty) return;
    if (widget.controller.activeOrderingTableId != null) return;
    TableItem? target;
    for (final t in _tables) {
      if (t.id == tableId) {
        target = t;
        break;
      }
    }
    if (target == null) {
      // Grid may not have this table yet — refresh once and retry.
      await _load(silent: true);
      if (!mounted) return;
      for (final t in _tables) {
        if (t.id == tableId) {
          target = t;
          break;
        }
      }
    }
    if (target == null || !mounted) return;
    _openTable(target);
  }

  void _openTable(TableItem table) {
    final me = widget.controller.session.self;
    if (me == null) return;

    final ownerId = _registry.ownerIdFor(table.id);
    if (ownerId != null && ownerId != me.id) {
      _showBorrowDialog(table, ownerId);
      return;
    }

    // Backend-locked: server marks table occupied even though registry has no owner
    // (cashier opened it). Block to prevent second-party stacking on seated table.
    if (ownerId == null && table.status != TableStatus.available) {
      _showBackendLockedDialog(table);
      return;
    }

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => WaiterOrderScreen(
              table: table,
              controller: widget.controller,
            ),
          ),
        )
        // Re-sync grid on return so tile doesn't linger on stale takingOrder.
        .then((_) {
      if (mounted) _load(silent: true);
    });
  }

  Future<void> _migrateTable(TableItem source) async {
    final me = widget.controller.session.self;
    if (me == null) return;

    // Re-check ownership in case a stale onMigrate callback fires post-handoff.
    final ownerId = _registry.ownerIdFor(source.id);
    if (ownerId != me.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(translationService.t('waiter_tables_not_owner')),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    // Destinations: unowned + backend-available, excluding self + inactive.
    final destinations = _tables.where((t) {
      if (t.id == source.id) return false;
      if (!t.isActive) return false;
      if (_registry.ownerIdFor(t.id) != null) return false;
      return t.status == TableStatus.available;
    }).toList();

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
      builder: (_) => _WaiterMigrateDestinationDialog(
        source: source,
        destinations: destinations,
      ),
    );
    if (picked == null) return;
    if (!mounted) return;

    // Re-validate — peer may have claimed destination between open and pick.
    final stillFree = _registry.ownerIdFor(picked.id) == null;
    if (!stillFree) {
      UiFeedback.warning(
        context,
        translationService.t(
          'waiter_tables_destination_taken',
          args: {'table': picked.number},
        ),
      );
      return;
    }

    // Persist move on backend first — otherwise getTables() refresh reverts the view.
    final existingBookingId = _registry.bookingIdFor(source.id);
    final cart = getIt<WaiterCartStore>();
    var carriedItems = cart.allItemsFor(source.id);
    final carriedGuests = _registry.guestCountFor(source.id);
    var backendMoved = false;
    if (existingBookingId != null) {
      // Migrate PATCH is full rebuild — 422s with "cart required" if no lines sent.
      // Pull current lines when local cart is empty (order taken on another device).
      if (carriedItems.isEmpty) {
        try {
          final details =
              await getIt<OrderService>().getBookingDetails(existingBookingId);
          final inner = (details['data'] is Map)
              ? Map<String, dynamic>.from(details['data'] as Map)
              : Map<String, dynamic>.from(details);
          carriedItems =
              _extractMealsFromPayload(inner).map(_cartItemFromRawMeal).toList();
        } catch (e) {
          Log.d('catch', 'non-fatal: $e');
        }
      }
      if (carriedItems.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(translationService.t('waiter_tables_move_fetch_failed')),
            backgroundColor: const Color(0xFFDC2626),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
      try {
        await getIt<WaiterBillingService>().updateBookingItems(
          bookingId: existingBookingId,
          table: picked,
          items: carriedItems,
          guests: carriedGuests,
        );
        backendMoved = true;
      } catch (e) {
        if (!mounted) return;
        UiFeedback.error(
          context,
          translationService.t(
            'waiter_tables_move_backend_failed',
            args: {'reason': '$e'},
          ),
        );
        return;
      }
    }

    try {
      widget.controller.migrateTable(
        oldTableId: source.id,
        oldTableNumber: source.number,
        newTableId: picked.id,
        newTableNumber: picked.number,
      );
      // Move the customer↔table binding to the destination.
      unawaited(waitlistService.reassignAssignedTable(
        source.id,
        picked.id,
        toTableNumber: picked.number,
      ));
    } on StateError catch (e) {
      // Mesh rejected migrate post-backend-accept — roll booking back to keep layers in sync.
      if (backendMoved && existingBookingId != null) {
        try {
          await getIt<WaiterBillingService>().updateBookingItems(
            bookingId: existingBookingId,
            table: source,
            items: carriedItems,
            guests: carriedGuests,
          );
        } catch (rollbackError) {
          debugPrint(
              '⚠️ Migrate rollback failed — booking is on ${picked.number} '
              'server-side but mesh rejected the shuffle: $rollbackError');
        }
      }
      if (!mounted) return;
      UiFeedback.info(context, 'تعذر نقل الطاولة: $e');
      return;
    }

    // Only print kitchen migration ticket if booking actually moved on backend.
    if (backendMoved) {
      unawaited(
        getIt<WaiterPrintDispatcher>().printMigrationTicket(
          sourceTableNumber: source.number,
          destinationTableNumber: picked.number,
          waiterName: me.name,
        ),
      );
    }

    if (!mounted) return;
    UiFeedback.success(context, 'تم نقل الطاولة ${source.number} إلى ${picked.number}');
  }

  /// Mirror of the cashier's `_enrichBookingDetailsForDialog`. Without
  /// this, a response shape of `{data: {booking: {...}, meals: [...]}}`
  /// leaves the dialog reading `widget.bookingData['data']['type']` as
  /// null (the real `type` is nested inside `booking`), and items that
  /// carry no price at the top level stay priceless in the edit UI.
  /// Applied once on dialog open.
  Map<String, dynamic> _enrichBookingDetailsForDialog({
    required int orderId,
    required Map<String, dynamic> rawDetails,
  }) {
    var payload = rawDetails['data'] is Map
        ? Map<String, dynamic>.from(rawDetails['data'] as Map)
        : Map<String, dynamic>.from(rawDetails);
    // Flatten `booking` sub-map so dialog's _seedItems + _saveChanges read fields at top level.
    if (payload['booking'] is Map && payload['id'] == null) {
      final inner = Map<String, dynamic>.from(payload['booking'] as Map);
      for (final e in payload.entries) {
        if (e.key != 'booking') inner.putIfAbsent(e.key, () => e.value);
      }
      payload = inner;
    }
    payload['id'] ??= orderId;

    // Build meal-id → row index for price enrichment from canonical `booking_meals`.
    final lookup = <String, Map<String, dynamic>>{};
    for (final key in ['booking_meals', 'meals', 'items']) {
      final raw = payload[key];
      if (raw is! List) continue;
      for (final item in raw) {
        if (item is! Map) continue;
        final row = item.map((k, v) => MapEntry(k.toString(), v));
        final id = (row['id'] ?? row['meal_id'])?.toString();
        if (id != null && id.isNotEmpty) lookup[id] = row;
      }
    }
    for (final key in ['meals', 'items', 'card']) {
      final raw = payload[key];
      if (raw is! List) continue;
      for (final item in raw) {
        if (item is! Map) continue;
        if (item['price'] != null ||
            item['unit_price'] != null ||
            item['total'] != null) {
          continue;
        }
        final mealId = (item['meal_id'] ?? item['id'])?.toString();
        if (mealId == null || !lookup.containsKey(mealId)) continue;
        final src = lookup[mealId]!;
        // In-place mutation enriches the same objects the dialog will render.
        item['price'] ??= src['price'];
        item['unit_price'] ??= src['unit_price'] ?? src['price'];
        item['total'] ??= src['total'] ?? src['price'];
      }
    }
    return payload;
  }

  /// Byte-for-byte port of the cashier's private `_bookingHasInvoice`
  /// helper (orders_screen.helpers.dart:69). An affirmative answer
  /// means the booking has already been invoiced (and therefore
  /// editing it would either fail on the backend or silently leave
  /// the invoice out of sync with the items).
  bool _bookingHasInvoice(Booking booking) {
    final raw = booking.raw;
    bool hasValue(dynamic value) {
      final text = value?.toString().trim().toLowerCase() ?? '';
      return text.isNotEmpty && text != 'null' && text != '0';
    }

    final hasInvoiceFlag = raw['has_invoice'] == true ||
        raw['has_invoice'] == 1 ||
        raw['has_invoice'] == '1';
    final hasInvoiceId =
        hasValue(raw['invoice_id']) || hasValue(raw['invoice_number']);
    final hasBookingInvoiceId =
        hasValue(raw['invoice'] is Map ? (raw['invoice'] as Map)['id'] : null);
    return hasInvoiceFlag || hasInvoiceId || hasBookingInvoiceId;
  }

  bool _isBookingCancelled(Booking booking) {
    final normalized = booking.status.trim().toLowerCase();
    return normalized == '8' ||
        normalized == 'cancelled' ||
        normalized == 'canceled';
  }

  /// Waiter-side mirror of the cashier's `_canCreateInvoiceForBooking`
  /// (orders_screen.helpers.dart:93) — the same rule gates opening
  /// the Edit Order dialog on both sides so the two clients never
  /// disagree on which bookings are editable.
  bool _canEditBooking(Booking booking) {
    if (_isBookingCancelled(booking)) return false;
    if (booking.isPaid) return false;
    if (_bookingHasInvoice(booking)) return false;
    return true;
  }

  /// Extract the meals array from an enriched booking-details payload.
  /// Tries the same keys the cashier's dialog walks so we surface
  /// whichever field the account's API happens to populate.
  List<Map<String, dynamic>> _extractMealsFromPayload(
      Map<String, dynamic> payload) {
    const keys = [
      'meals',
      'booking_meals',
      'booking_products',
      'booking_items',
      'items',
      'invoice_items',
      'sales_meals',
      'card',
      'cart',
    ];
    for (final key in keys) {
      final raw = payload[key];
      if (raw is! List) continue;
      final rows = raw
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      if (rows.isNotEmpty) return rows;
    }
    return const [];
  }

  /// Build a [CartItem] from a raw backend meal map. Used to rehydrate
  /// the local "sent" cart after the EditOrderDialog so the next
  /// pay-later PATCH includes the items the dialog preserved (not just
  /// whatever new drafts the waiter added on top).
  ///
  /// The `Product` is a STUB — we populate only the fields
  /// `WaiterBillingService.updateBookingItems` reads when rebuilding
  /// the payload: `id`, `name`, `price`. Extras ARE parsed from the
  /// meal's `addons`/`extras` sub-list so a subsequent pay-later PATCH
  /// doesn't drop add-ons on a previously-ordered line.
  CartItem _cartItemFromRawMeal(Map<String, dynamic> row) {
    final mealIdRaw = row['meal_id'] ?? row['id'];
    final mealId = mealIdRaw?.toString() ?? '';
    final name = (row['meal_name'] ??
            row['item_name'] ??
            row['name'] ??
            '')
        .toString();
    final qty = _toDouble(row['quantity']) ?? 1.0;
    // `price` is often the LINE total; derive unit price when only total is present.
    final unitPrice = _toDouble(row['unit_price']) ??
        (_toDouble(row['price'])! / (qty == 0 ? 1 : qty));

    // Harvest translations so rehydrated stub has localizedNames (kitchen ticket bilingual).
    final localizedNames = <String, String>{};
    for (final key in const [
      'meal_name_translations',
      'name_translations',
      'translations',
      'localizedNames',
      'localized_names',
      'names',
    ]) {
      final src = row[key];
      if (src is Map) {
        src.forEach((k, v) {
          final code = k.toString().trim().toLowerCase();
          final value = v?.toString().trim() ?? '';
          if (code.isNotEmpty && value.isNotEmpty) {
            localizedNames.putIfAbsent(code, () => value);
          }
        });
      }
    }
    for (final code in const ['ar', 'en', 'es', 'tr', 'hi', 'ur']) {
      final v = (row['name_$code'] ?? row['meal_name_$code'])
          ?.toString()
          .trim();
      if (v != null && v.isNotEmpty) {
        localizedNames.putIfAbsent(code, () => v);
      }
    }
    final nameAr = (row['name_ar'] ??
                row['meal_name_ar'] ??
                row['nameAr'] ??
                localizedNames['ar'] ??
                '')
            .toString();
    final nameEn = (row['name_en'] ??
                row['meal_name_en'] ??
                row['nameEn'] ??
                localizedNames['en'] ??
                '')
            .toString();

    final extras = <Extra>[];
    final addonsRaw = row['addons'] ?? row['extras'];
    if (addonsRaw is List) {
      for (final entry in addonsRaw) {
        if (entry is Map) {
          try {
            extras.add(Extra.fromJson(
                entry.map((k, v) => MapEntry(k.toString(), v))));
          } catch (e) {
            Log.d('catch', 'non-fatal: $e');
          }
        }
      }
    }

    final stubProduct = Product(
      id: mealId,
      name: name,
      nameAr: nameAr,
      nameEn: nameEn,
      price: unitPrice,
      category: '',
      categoryId: row['category_id']?.toString(),
      localizedNames: localizedNames,
    );
    return CartItem(
      cartId: const Uuid().v4(),
      product: stubProduct,
      quantity: qty,
      selectedExtras: extras,
      notes: (row['note'] ?? row['notes'] ?? '').toString(),
    );
  }

  double? _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  /// After a backend booking mutation (edit / refund / cancel) re-pull the
  /// authoritative state once and (a) rebuild this device's local "sent"
  /// cart so a subsequent pay-later PATCH carries the right items, and
  /// (b) broadcast the new state to every peer so their grids + details
  /// dialogs repaint immediately instead of waiting for the next poll —
  /// `released` when nothing's left, `updated` (with the fresh line items)
  /// otherwise.
  Future<void> _reconcileAndBroadcastAfterBackendMutation(
    TableItem table,
    String bookingId,
  ) async {
    try {
      final after = await getIt<OrderService>().getBookingDetails(bookingId);
      // Detail endpoint serves a 500 sentinel on transient hiccup — bail to avoid
      // treating it as "empty booking"; next poll reconciles.
      if (after['status']?.toString().trim() == '500') return;
      final inner = (after['data'] is Map)
          ? Map<String, dynamic>.from(after['data'] as Map)
          : Map<String, dynamic>.from(after);
      inner['id'] ??= int.tryParse(bookingId) ?? bookingId;
      final refreshed = Booking.fromJson(inner);
      final rawMeals = _extractMealsFromPayload(inner);
      final cart = getIt<WaiterCartStore>();
      // Drop local drafts so a stale pay-later PATCH can't clobber the change.
      cart.clearTable(table.id);

      final statusStr = refreshed.status.toString().toLowerCase();
      // Only flip free on *positive* cancellation — empty meals is ambiguous
      // (could be refund-then-keep-open) and risks ghost-free over live booking.
      final cancelled = statusStr == '8' ||
          statusStr == 'cancelled' ||
          statusStr == 'canceled' ||
          statusStr.contains('cancel');

      final snap = _registry.lookup(table.id);
      final me = widget.controller.session.self;
      final regWaiterId = snap?.waiterId ?? '';
      final regWaiterName = snap?.waiterName ?? '';
      // Never emit empty owner on `updated` — registry copies verbatim and wipes waiter.
      final waiterId = regWaiterId.isNotEmpty ? regWaiterId : (me?.id ?? '');
      final waiterName =
          regWaiterName.isNotEmpty ? regWaiterName : (me?.name ?? '');

      if (cancelled) {
        widget.controller.broadcastTableEvent(TableLifecycleEvent(
          kind: TableLifecycleKind.released,
          tableId: table.id,
          tableNumber: table.number,
          waiterId: waiterId,
          waiterName: waiterName,
        ));
        return;
      }
      if (rawMeals.isEmpty) {
        // Booking open but lines unreadable — don't broadcast misleading snapshot.
        return;
      }

      // Live order — rehydrate sent cart from raw rows + broadcast `updated`.
      cart.setSentItems(
        table.id,
        rawMeals.map(_cartItemFromRawMeal).toList(),
      );
      final snapshots = rawMeals.map((row) {
        final qty = _toDouble(row['quantity']) ?? 1.0;
        final unitPrice = _toDouble(row['unit_price']) ??
            ((_toDouble(row['price']) ?? 0) / (qty == 0 ? 1 : qty));
        final name = (row['meal_name'] ??
                row['item_name'] ??
                row['name'] ??
                '')
            .toString();
        final note = (row['note'] ?? row['notes'] ?? '').toString();
        return TableItemSnapshot(
          name: name,
          quantity: qty,
          unitPrice: unitPrice,
          note: note.isEmpty ? null : note,
          mealId: (row['meal_id'] ?? row['id'])?.toString(),
          categoryId: row['category_id']?.toString(),
        );
      }).toList();
      final preTaxTotal =
          snapshots.fold<double>(0, (s, it) => s + it.lineTotal);
      final itemCount =
          snapshots.fold<int>(0, (s, it) => s + it.quantity.round());
      widget.controller.broadcastTableEvent(TableLifecycleEvent(
        kind: TableLifecycleKind.updated,
        tableId: table.id,
        tableNumber: table.number,
        waiterId: waiterId,
        waiterName: waiterName,
        guestCount: snap?.guestCount ?? _registry.guestCountFor(table.id),
        total: preTaxTotal,
        itemCount: itemCount,
        items: snapshots,
        orderId: bookingId,
      ));
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
    }
  }

  /// Opens the cashier's EditOrderDialog against this table's live
  /// pay-later booking. The dialog owns the diff engine + the
  /// updateBookingItems / updateBookingStatus API calls; we only wire
  /// the `onPrintChanges` callback to the waiter's
  /// [WaiterPrintDispatcher] so the kitchen gets an identical change
  /// ticket. After a successful edit we clear the local cart + emit a
  /// released event if the dialog issued a full cancel, so peers see
  /// the table flip back to available without a reload.
  /// Best customer name we know is pinned to this table locally (manual
  /// "link customer" wins, else the waitlist party). The backend often
  /// leaves a booking's `customer_name` at the default "عميل عام" even
  /// when a customer is linked by id, so we override for display.
  String? _localCustomerNameFor(String tableId) {
    final manual = getIt<WaiterTableCustomerStore>().linkFor(tableId);
    if (manual != null && manual.customerName.trim().isNotEmpty) {
      return manual.customerName.trim();
    }
    return waitlistService.customerNameForTable(tableId)?.trim();
  }

  void _applyLocalCustomerName(Map<String, dynamic> data, String tableId) {
    final name = _localCustomerNameFor(tableId);
    if (name != null && name.isNotEmpty) {
      data['customer_name'] = name;
      data['client_name'] = name;
    }
  }

  /// Read-only full order details for a table, pulled fresh from the
  /// backend so it's identical on every waiter device. Reuses the same
  /// enrichment + dialog the cashier's orders screen uses.
  Future<void> _showTableOrderDetails(TableItem table) async {
    final bookingId = _registry.bookingIdFor(table.id);
    if (bookingId == null || bookingId.isEmpty) return;
    Map<String, dynamic> details;
    try {
      final rawDetails =
          await getIt<OrderService>().getBookingDetails(bookingId);
      details = _enrichBookingDetailsForDialog(
        orderId: int.tryParse(bookingId) ?? 0,
        rawDetails: rawDetails,
      );
    } catch (e) {
      if (!mounted) return;
      UiFeedback.error(context, '${translationService.t('waiter_retry')}: $e');
      return;
    }
    if (!mounted) return;
    _applyLocalCustomerName(details, table.id);
    final paymentPending = _registry.paymentPendingFor(table.id);
    final selfId = widget.controller.session.self?.id ?? '';
    final isMine =
        selfId.isNotEmpty && _registry.ownerIdFor(table.id) == selfId;
    await showDialog<void>(
      context: context,
      builder: (_) => BookingDetailsDialog(
        bookingData: details,
        onEditOrder: (isMine && paymentPending)
            ? () => _openEditOrderDialog(table)
            : null,
        onRefund: () => _refundBookingForTable(table),
      ),
    );
  }

  Future<void> _openEditOrderDialog(TableItem table) async {
    if (widget.controller.session.self == null) return;
    final bookingId = _registry.bookingIdFor(table.id);
    if (bookingId == null) {
      UiFeedback.warning(context, translationService.t('waiter_no_active_booking'));
      return;
    }

    Map<String, dynamic> details;
    Booking booking;
    try {
      final rawDetails =
          await getIt<OrderService>().getBookingDetails(bookingId);
      details = _enrichBookingDetailsForDialog(
        orderId: int.tryParse(bookingId) ?? 0,
        rawDetails: rawDetails,
      );
      _applyLocalCustomerName(details, table.id);
      // Belt-and-suspenders unwrap for unanticipated response shapes.
      final inner = (details['data'] is Map)
          ? Map<String, dynamic>.from(details['data'] as Map)
          : Map<String, dynamic>.from(details);
      _applyLocalCustomerName(inner, table.id);
      booking = Booking.fromJson(inner);
      if (booking.id == 0) {
        throw StateError(
            'booking id missing in details response for $bookingId');
      }
    } catch (e) {
      if (!mounted) return;
      UiFeedback.error(context, '${translationService.t('waiter_retry')}: $e');
      return;
    }

    // Two-tier edit guard: _canEditBooking blocks cancelled/paid/invoiced;
    // isOrderLockedValue blocks locked-but-uninvoiced statuses (e.g. delivered).
    if (!_canEditBooking(booking)) {
      if (!mounted) return;
      UiFeedback.warning(context, translationService.t('waiter_edit_not_allowed'));
      return;
    }
    if (isOrderLockedValue(booking.status) ||
        isOrderLockedValue(booking.raw['status'])) {
      if (!mounted) return;
      UiFeedback.warning(context, translationService.t('waiter_edit_locked'));
      return;
    }

    if (!mounted) return;
    final dispatcher = getIt<WaiterPrintDispatcher>();
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => EditOrderDialog(
        booking: booking,
        bookingData: details,
        // Tax rate so dialog prices render tax-inclusive, matching receipt.
        taxRate: getIt<WaiterBillingService>().taxRate,
        onPrintChanges: (
          changes,
          orderNumber, {
          bool isFullCancel = false,
          String? customerName,
          String? employeeName,
        }) {
          unawaited(dispatcher.printKitchenChangeTicket(
            changes: changes,
            orderNumber: orderNumber,
            isFullCancel: isFullCancel,
          ));
        },
      ),
    );
    if (updated != true) return;

    // Reconcile + broadcast so peers don't wait for poll after dialog PATCH.
    await _reconcileAndBroadcastAfterBackendMutation(table, bookingId);

    if (!mounted) return;
    UiFeedback.success(context, translationService.t('waiter_bill_success'));
  }

  void _showBackendLockedDialog(TableItem table) {
    final isReserved = table.status == TableStatus.occupied;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.appSurface,
        title: Row(
          children: [
            Icon(LucideIcons.lock, color: context.appDanger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isReserved
                    ? translationService.t('table_occupied')
                    : translationService.t('table_unavailable'),
                style: TextStyle(color: context.appText),
              ),
            ),
          ],
        ),
        content: Text(
          translationService.t(
            'waiter_table_backend_locked_body',
            args: {'table': table.number},
          ),
          style: TextStyle(color: context.appText),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.appPrimary),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(translationService.t('waiter_close')),
          ),
        ],
      ),
    );
  }

  void _showBorrowDialog(TableItem table, String ownerId) {
    // Waiter-to-waiter calls disabled — only cashier rings; info dialog only.
    final owner = widget.controller.roster.byId(ownerId);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.appSurface,
        title: Text(translationService.t('waiter_table_owned_title')),
        content: Text(
          translationService.t(
            'waiter_table_owned_body',
            args: {
              'table': table.number,
              'name': owner?.name ?? '—',
            },
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.appPrimary),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(translationService.t('waiter_close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const WaitlistAssignBanner(),
        Expanded(child: _buildBody()),
        if (!_loading && _error == null && _tables.isNotEmpty)
          _buildSectionTabBar(),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SkeletonTablesGrid();
    }
    if (_error != null) {
      return _ErrorView(onRetry: _load, error: _error!);
    }
    if (_tables.isEmpty) {
      return _EmptyView(onRefresh: _load);
    }
    final activeTables = _tablesForSelectedSection(_visibleTables());
    return RefreshIndicator(
      color: context.appPrimary,
      onRefresh: _load,
      child: LayoutBuilder(builder: (_, constraints) {
        // Compact tiles, scaling up on desktop so card content fits.
        final w = constraints.maxWidth;
        final double maxExtent = w < 420
            ? 120
            : w < 900
                ? 140
                : 170;
        return GridView.builder(
          padding: const EdgeInsets.all(WaiterSpacing.sm),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxExtent,
            mainAxisSpacing: WaiterSpacing.xs + 2,
            crossAxisSpacing: WaiterSpacing.xs + 2,
            childAspectRatio: 1.0,
          ),
          itemCount: activeTables.length,
          itemBuilder: (_, i) {
            final t = activeTables[i];
            final ownerId = _registry.ownerIdFor(t.id);
            final ownerName = _registry.ownerNameFor(t.id) ??
                (ownerId != null
                    ? widget.controller.roster.byId(ownerId)?.name
                    : null);
            // Build fresh overlay each frame — don't mutate cached TableItem in place
            // or ownership styling leaks across frames.
            final overlaid = t.copyWith(
              status: ownerId != null ? TableStatus.occupied : t.status,
              waiterName: ownerName ?? t.waiterName,
              // Use registry's paidFor since getTables()'s isPaid lags behind `paid` event.
              isPaid: _registry.paidFor(t.id) || t.isPaid,
            );
            // Null-guard session — logout mid-frame flips self to null.
            final selfId = widget.controller.session.self?.id ?? '';
            final isMine = ownerId != null && selfId.isNotEmpty
                ? ownerId == selfId
                : false;
            final paymentPending = _registry.paymentPendingFor(t.id);
            final waitlistHold = waitlistService.entryForTable(t.id);
            return WaiterTableCard(
              key: ValueKey('waiter_table_${t.id}'),
              table: overlaid,
              currentWaiterId: selfId,
              ownerWaiterId: ownerId,
              ownerWaiterName: ownerName,
              guestCount: _registry.guestCountFor(t.id),
              isTakingOrder: _registry.takingOrderFor(t.id),
              paymentPending: paymentPending,
              holdingForName: waitlistHold?.customerName,
              onMigrate:
                  (isMine && !t.isPaid) ? () => _migrateTable(t) : null,
              onEditOrder: (isMine && paymentPending)
                  ? () => _openEditOrderDialog(t)
                  : null,
              // Cancel only for live pay-later booking we own — post-payment is backend-locked.
              onCancelBooking: (isMine && paymentPending && !t.isPaid)
                  ? () => _cancelBookingForTable(t)
                  : null,
              // Refund available regardless of device owner — touches backend only.
              onRefund: (_registry.bookingIdFor(t.id) != null)
                  ? () => _refundBookingForTable(t)
                  : null,
              onReleaseTable: isMine ? () => _releaseTable(t) : null,
              onDetails: (_registry.bookingIdFor(t.id) != null)
                  ? () => _showTableOrderDetails(t)
                  : null,
              onTap: () => _handleTap(t),
            );
          },
        );
      }),
    );
  }

  List<TableItem> _tablesForSelectedSection(List<TableItem> all) {
    final sections = _groupBySection(all);
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
    final sections = _groupBySection(_visibleTables());
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
                                ? context.appPrimary
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
                              ? context.appPrimary
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

  // Groups by `category_name`; General bucket always present so refresh doesn't drop the tab.
  List<_TableSection> _groupBySection(List<TableItem> tables) {
    const generalKey = '__none__';
    final generalTitle = translationService.t('uncategorized_section');
    final order = <String>[generalKey];
    final byKey = <String, _TableSection>{
      generalKey: _TableSection(
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
        return _TableSection(key: key, title: title, tables: []);
      });
      bucket.tables.add(t);
    }
    return [for (final k in order) byKey[k]!];
  }
}
