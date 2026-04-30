import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../dialogs/edit_order_dialog.dart';
import '../../dialogs/waitlist_notify_dialog.dart';
import '../../locator.dart';
import '../../models.dart';
import '../../models/booking_invoice.dart';
import '../../models/waitlist_entry.dart';
import '../../services/api/order_service.dart';
import '../../services/api/table_service.dart';
import '../../services/app_themes.dart';
import '../../services/language_service.dart';
import '../../services/waitlist_assign_controller.dart';
import '../../services/waitlist_service.dart';
import '../../utils/order_status.dart';
import '../../widgets/waitlist_assign_banner.dart';
import '../models/table_migrate_event.dart';
import '../models/waiter_table_event.dart';
import '../services/waiter_billing_service.dart';
import '../services/waiter_cart_store.dart';
import '../services/waiter_controller.dart';
import '../services/waiter_print_dispatcher.dart';
import '../services/waiter_table_registry.dart';
import '../theme/waiter_design.dart';
import '../widgets/skeleton_grid.dart';
import '../widgets/waiter_table_card.dart';
import 'waiter_order_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
    // Prime the tax config so an Edit Order dialog opened directly
    // from the grid (without visiting the order screen first) renders
    // tax-inclusive prices instead of the raw pre-tax numbers. The
    // order screen hydrates tax itself on its own init, so the
    // double-hydrate on that path is a no-op short-circuited by the
    // billing service's internal caching.
    unawaited(getIt<WaiterBillingService>().refreshTaxConfig());
    _registry.addListener(_onRegistry);
    // Registry application now lives in WaiterController (for both
    // incoming and self-broadcast paths) so every device stays in
    // sync. We only need to listen for the ChangeNotifier signal
    // above to trigger a rebuild; no need to apply here.
    //
    // We do have to listen to migrate + lifecycle events separately,
    // though: the registry's release/assign broadcast removes/adds an
    // entry cleanly, but the local `_tables[id].status` still reads
    // from the last getTables() snapshot. Without an optimistic flip,
    // a freshly-released table keeps showing "مشغول" until the grid
    // reloads — same optimistic pattern the cashier applies.
    _migrateSub = widget.controller.onTableMigrate.listen(_onMigrate);
    _lifecycleSub =
        widget.controller.onTableEvent.listen(_onLifecycle);
    // Re-render whenever the shared assign controller flips — we need
    // to show/hide the banner and intercept tap routing.
    waitlistAssignController.addListener(_onAssignModeChanged);
    // Re-render when a waitlist entry is added / notified / seated so
    // the holdingForName pill updates in real time when the change
    // originated on a peer device.
    waitlistService.addListener(_onAssignModeChanged);
  }

  @override
  void dispose() {
    _registry.removeListener(_onRegistry);
    _migrateSub?.cancel();
    _lifecycleSub?.cancel();
    waitlistAssignController.removeListener(_onAssignModeChanged);
    waitlistService.removeListener(_onAssignModeChanged);
    super.dispose();
  }

  void _onAssignModeChanged() {
    if (mounted) setState(() {});
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

  void _onLifecycle(WaiterTableEventEnvelope envelope) {
    if (!mounted) return;
    final event = envelope.event;
    // Same deferred-setState pattern as _onRegistry — lifecycle events
    // often fire from initState of another screen (e.g. WaiterOrderScreen
    // announcing `takingOrder`), which would otherwise land setState
    // inside the parent's build pass.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final idx = _tables.indexWhere((t) => t.id == event.tableId);
      if (idx < 0) return;
      setState(() {
        switch (event.kind) {
          case TableLifecycleKind.released:
            // The owning waiter tapped "تحرير الطاولة" (or a full-cancel
            // in Edit Order fired release). Flip local backend-status to
            // available so the overlay's fallback path (`ownerId==null
            // ? occupied : t.status`) renders the card as free now,
            // instead of waiting for the next getTables() poll.
            _tables[idx].status = TableStatus.available;
            _tables[idx].waiterName = null;
            _tables[idx].isPaid = false;
            break;
          case TableLifecycleKind.assigned:
          case TableLifecycleKind.takingOrder:
          case TableLifecycleKind.paymentPending:
          case TableLifecycleKind.paid:
          case TableLifecycleKind.updated:
            // Registry overlay already forces occupied when ownerId is
            // set, but mirroring it onto t.status keeps behaviour
            // identical after getTables() reloads.
            _tables[idx].status = TableStatus.occupied;
            break;
        }
      });
    });
  }

  void _onMigrate(TableMigrateEvent event) {
    if (!mounted) return;
    // Deferred to post-frame for the same reason _onRegistry is — the
    // event may fire mid-build when the owning waiter initiates the
    // migrate and WaiterController.migrateTable synchronously
    // broadcasts down the stream.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        final srcIdx =
            _tables.indexWhere((t) => t.id == event.oldTableId);
        if (srcIdx >= 0) {
          // Registry already knows there's no owner; mirror that onto
          // the backend-reported status so the overlay renders
          // "available" instead of stale "occupied".
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
    // Registry notifications can fire mid-build — e.g. opening the order
    // screen broadcasts a "taking order" lifecycle event during its
    // initState, which reaches WaiterTableRegistry.apply() and notifies
    // us while this screen is still in the same frame's build pass.
    // Defer the rebuild to the next frame so setState doesn't land
    // inside someone else's build.
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
    // Local cart flush so re-entering a freshly-released table doesn't
    // resurface stale items from the previous party.
    try {
      getIt<WaiterCartStore>().clearTable(table.id);
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم تحرير الطاولة ${table.number}'),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tables = await _tableService.getTables();
      if (!mounted) return;
      // Reconcile the persisted registry with the authoritative backend
      // list: if a table comes back as available (e.g. the cashier
      // closed a pay-later booking while this waiter was offline),
      // drop the stale registry row so the card doesn't keep showing
      // an Edit Order button for a booking that no longer exists.
      final availableIds = tables
          .where((t) => t.isActive && t.status == TableStatus.available)
          .map((t) => t.id);
      _registry.reconcileWithBackend(availableIds);
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
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Single tap entry point — routes to either the waitlist assign
  /// flow or the default "open table" flow, and marks any linked
  /// waitlist entry as seated when the waiter is about to open the
  /// table it was assigned to.
  Future<void> _handleTap(TableItem table) async {
    final pending = waitlistAssignController.pending;
    if (pending != null) {
      await _handleAssignTap(pending, table);
      return;
    }
    final linked = waitlistService.entryForTable(table.id);
    _openTable(table);
    if (linked != null) {
      unawaited(waitlistService.markSeated(linked.id));
    }
  }

  void _openTable(TableItem table) {
    final me = widget.controller.session.self;
    if (me == null) return;

    final ownerId = _registry.ownerIdFor(table.id);
    if (ownerId != null && ownerId != me.id) {
      _showBorrowDialog(table, ownerId);
      return;
    }

    // Backend-locked path: the cashier (or another device outside the
    // waiter mesh) opened this table so the server marks it occupied/
    // printed even though our in-memory registry has no owner. Tapping
    // through would let the waiter start a second party on a seated
    // table. Same rule the cashier's screen enforces via
    // _checkTableStatus → "الطاولة محجوزة / غير متاحة".
    if (ownerId == null && table.status != TableStatus.available) {
      _showBackendLockedDialog(table);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WaiterOrderScreen(
          table: table,
          controller: widget.controller,
        ),
      ),
    );
  }

  Future<void> _migrateTable(TableItem source) async {
    final me = widget.controller.session.self;
    if (me == null) return;

    // The waiter can only migrate a table they own — the card-level guard
    // enforces this, but we re-check here so a stale onMigrate callback
    // firing after ownership change doesn't slip through.
    final ownerId = _registry.ownerIdFor(source.id);
    if (ownerId != me.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا تملك هذه الطاولة — لا يمكن نقلها.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Destinations: tables not owned by any waiter AND backend-status is
    // available. Skip self + inactive tables.
    final destinations = _tables.where((t) {
      if (t.id == source.id) return false;
      if (!t.isActive) return false;
      if (_registry.ownerIdFor(t.id) != null) return false;
      return t.status == TableStatus.available;
    }).toList();

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
      builder: (_) => _WaiterMigrateDestinationDialog(
        source: source,
        destinations: destinations,
      ),
    );
    if (picked == null) return;
    if (!mounted) return;

    // Re-validate right before broadcasting — between open and pick a
    // peer may have claimed the destination.
    final stillFree = _registry.ownerIdFor(picked.id) == null;
    if (!stillFree) {
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

    // Persist the move on the backend first — without this, the booking
    // stays pinned to the old table server-side and the next getTables()
    // refresh reverts the view. Mirrors the cashier's edit-order path of
    // PATCHing the booking via updateBookingItems with the new table_id
    // and table_name in type_extra.
    final existingBookingId = _registry.bookingIdFor(source.id);
    final cart = getIt<WaiterCartStore>();
    final carriedItems = cart.allItemsFor(source.id);
    final carriedGuests = _registry.guestCountFor(source.id);
    var backendMoved = false;
    if (existingBookingId != null) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر نقل الحجز على الخادم: $e'),
            backgroundColor: const Color(0xFFDC2626),
            duration: const Duration(seconds: 4),
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
    } on StateError catch (e) {
      // Mesh-side guard rejected the migrate after the backend had
      // already accepted the move. Roll the booking back to the source
      // table so the two layers don't diverge — otherwise a refresh
      // would show the booking under `picked` while the waiter mesh
      // still treats `source` as the owner.
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر نقل الطاولة: $e')),
      );
      return;
    }

    // Fire the kitchen "نقل طاولة" ticket only if we actually moved a
    // booking on the backend. Without this guard, a waiter claiming a
    // table then moving it before taking any order would send the
    // kitchen a FROM/TO ticket for food that doesn't exist.
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم نقل الطاولة ${source.number} إلى ${picked.number}',
        ),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
      ),
    );
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
    // Flatten the `booking` sub-map so id / daily_order_number /
    // type / notes / updated_at surface at the top level where the
    // dialog's _seedItems + _saveChanges read them.
    if (payload['booking'] is Map && payload['id'] == null) {
      final inner = Map<String, dynamic>.from(payload['booking'] as Map);
      for (final e in payload.entries) {
        if (e.key != 'booking') inner.putIfAbsent(e.key, () => e.value);
      }
      payload = inner;
    }
    payload['id'] ??= orderId;

    // Build a meal-id → row index for price enrichment. Some item
    // arrays (especially `meals`/`items`) come back without prices;
    // `booking_meals` is the canonical source.
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
        // In-place mutation — payload holds references to the original
        // list entries, so this enriches the same objects the dialog
        // will render.
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
    // Backend returns either `unit_price` or `price`; `price` is often
    // the LINE total so derive unit price when only total is present.
    final unitPrice = _toDouble(row['unit_price']) ??
        (_toDouble(row['price'])! / (qty == 0 ? 1 : qty));

    // Harvest translations from the backend meal row. The booking
    // details endpoint serves `meal_name_translations` (sometimes
    // `name_translations` or `translations` on older accounts). We
    // also accept separate `name_ar`/`name_en` columns. Without this,
    // the rehydrated Product stub has empty localizedNames and the
    // kitchen ticket / cashier receipt renders the item in one
    // language only — the bug the user hit on edit-order re-entry.
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
    // Also mine dedicated per-language columns (name_ar, name_en, …)
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
          } catch (_) {
            // Malformed extra — skip rather than crash the rehydrate.
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

  /// Opens the cashier's EditOrderDialog against this table's live
  /// pay-later booking. The dialog owns the diff engine + the
  /// updateBookingItems / updateBookingStatus API calls; we only wire
  /// the `onPrintChanges` callback to the waiter's
  /// [WaiterPrintDispatcher] so the kitchen gets an identical change
  /// ticket. After a successful edit we clear the local cart + emit a
  /// released event if the dialog issued a full cancel, so peers see
  /// the table flip back to available without a reload.
  Future<void> _openEditOrderDialog(TableItem table) async {
    final me = widget.controller.session.self;
    if (me == null) return;
    final bookingId = _registry.bookingIdFor(table.id);
    if (bookingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(translationService.t('waiter_no_active_booking')),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
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
      // Unwrap `data` if still wrapped after enrichment (enrichment
      // already flattens it, but keep this belt-and-suspenders for
      // shapes we didn't anticipate).
      final inner = (details['data'] is Map)
          ? Map<String, dynamic>.from(details['data'] as Map)
          : Map<String, dynamic>.from(details);
      booking = Booking.fromJson(inner);
      if (booking.id == 0) {
        throw StateError(
            'booking id missing in details response for $bookingId');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${translationService.t('waiter_retry')}: $e'),
          backgroundColor: const Color(0xFFDC2626),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    // Cashier-parity edit guards. Two separate checks:
    //   1. _canEditBooking — blocks cancelled / paid / already-invoiced
    //      bookings. Same rule the cashier's orders screen uses before
    //      offering the "تعديل الطلب" button.
    //   2. isOrderLockedValue — blocks status codes 3/5/6/7/8 (closed
    //      / delivered / cancelled). A booking can be locked without
    //      being invoiced (e.g. status=5 "delivered") so the two
    //      guards are not redundant.
    // Without these, the waiter could open Edit Order on a closed
    // booking and the backend would either accept a nonsensical edit
    // or reject with a raw ApiException surfaced as an unhelpful toast.
    if (!_canEditBooking(booking)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(translationService.t('waiter_edit_not_allowed')),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    if (isOrderLockedValue(booking.status) ||
        isOrderLockedValue(booking.raw['status'])) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(translationService.t('waiter_edit_locked')),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    if (!mounted) return;
    final dispatcher = getIt<WaiterPrintDispatcher>();
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => EditOrderDialog(
        booking: booking,
        bookingData: details,
        // Hand the branch tax rate through so prices in the dialog
        // render tax-inclusive, matching what the waiter sees on the
        // order screen + on the cashier receipt. Without this the
        // dialog would show pre-tax numbers only, confusing the
        // waiter into thinking items were cheaper than they are.
        taxRate: getIt<WaiterBillingService>().taxRate,
        onPrintChanges: (changes, orderNumber, {bool isFullCancel = false}) {
          // Fire-and-forget. The dispatcher already swallows printer
          // errors so a down printer never blocks the edit save.
          unawaited(dispatcher.printKitchenChangeTicket(
            changes: changes,
            orderNumber: orderNumber,
            isFullCancel: isFullCancel,
          ));
        },
      ),
    );
    if (updated != true) return;

    // The dialog PATCHed the backend. We now need to re-sync the local
    // "sent" cart with the backend's authoritative state — if we just
    // wipe it, a subsequent pay-later from the order screen would
    // overwrite the edited booking with only whatever fresh drafts the
    // waiter adds, losing the items the dialog kept.
    //
    // Also detect the full-cancel case (meals empty or status=8) and
    // broadcast a `released` event so peers see the table flip to
    // available immediately instead of waiting for the next
    // getTables() poll.
    try {
      final after =
          await getIt<OrderService>().getBookingDetails(bookingId);
      final innerAfter = (after['data'] is Map)
          ? Map<String, dynamic>.from(after['data'] as Map)
          : Map<String, dynamic>.from(after);
      final refreshed = Booking.fromJson(innerAfter);
      final cart = getIt<WaiterCartStore>();
      // Drafts don't survive an external edit; clear them so the
      // waiter's next entry to the order screen starts from a clean
      // slate on top of the backend's items.
      cart.clearTable(table.id);
      final isFullyCancelled = refreshed.meals.isEmpty ||
          refreshed.status.toString() == '8' ||
          refreshed.status.toLowerCase() == 'cancelled' ||
          refreshed.status.toLowerCase() == 'canceled';
      if (!isFullyCancelled) {
        // Rebuild sent-items from the RAW meal rows (so add-ons and
        // per-item notes survive) rather than from the stripped-down
        // `Booking.meals` list which drops extras. A subsequent
        // updateBookingItems PATCH from the order screen now includes
        // everything the dialog kept, preserving the full server state.
        final rawMeals = _extractMealsFromPayload(innerAfter);
        cart.setSentItems(
          table.id,
          rawMeals.map(_cartItemFromRawMeal).toList(),
        );
      } else {
        widget.controller.broadcastTableEvent(TableLifecycleEvent(
          kind: TableLifecycleKind.released,
          tableId: table.id,
          tableNumber: table.number,
          waiterId: me.id,
          waiterName: me.name,
        ));
      }
    } catch (_) {
      // Non-fatal — the backend edit already happened. On the next
      // getTables() refresh the state will reconcile; the worst case
      // is the waiter sees a stale `sent` list until they pull the
      // tables grid or release the table.
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(translationService.t('waiter_bill_success')),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
      ),
    );
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
    // Waiter-to-waiter calls are disabled — only the cashier rings the
    // bell. We still show an info dialog so the tapping waiter knows
    // the table is taken instead of letting them silently overwrite.
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
        // Uniform compact tiles — matches the reference layout where many
        // tables fit per row on a tablet landscape. Tile size scales up on
        // desktop so card content (table number + handle icons) fits.
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
            final overlaid = t
              ..status = ownerId != null ? TableStatus.occupied : t.status
              ..waiterName = ownerName ?? t.waiterName;
            final isMine = ownerId != null &&
                ownerId == widget.controller.session.self!.id;
            final paymentPending = _registry.paymentPendingFor(t.id);
            final waitlistHold = waitlistService.entryForTable(t.id);
            return WaiterTableCard(
              key: ValueKey('waiter_table_${t.id}'),
              table: overlaid,
              currentWaiterId: widget.controller.session.self!.id,
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
              onReleaseTable: isMine ? () => _releaseTable(t) : null,
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

  // Groups tables by `category_name` returned from the API. The "General"
  // bucket is always present (even when empty) so refreshing while every
  // table happens to have a category doesn't drop the General tab.
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

class _TableSection {
  final String key;
  final String title;
  final List<TableItem> tables;
  _TableSection({
    required this.key,
    required this.title,
    required this.tables,
  });
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final Object error;
  const _ErrorView({required this.onRetry, required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.alertCircle,
              size: 42, color: context.appDanger),
          const SizedBox(height: 8),
          Text(translationService.t('waiter_tables_load_failed'),
              style: TextStyle(color: context.appText)),
          const SizedBox(height: 4),
          Text('$error',
              style: TextStyle(color: context.appTextMuted, fontSize: 12)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.rotateCcw),
            label: Text(translationService.t('waiter_retry')),
          ),
        ],
      ),
    );
  }
}

/// Grid picker shown to the waiter so they can choose which empty table
/// to relocate the current party to.
class _WaiterMigrateDestinationDialog extends StatelessWidget {
  final TableItem source;
  final List<TableItem> destinations;

  const _WaiterMigrateDestinationDialog({
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
              'نقل الطاولة ${source.number} إلى...',
              style: TextStyle(color: context.appText, fontSize: 17),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        height: 320,
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 120,
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
                        color: context.appSuccess, size: 26),
                    const SizedBox(height: 6),
                    Text(
                      t.number,
                      style: TextStyle(
                        color: context.appText,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${t.seats} أشخاص',
                      style: TextStyle(
                        color: context.appTextMuted,
                        fontSize: 10,
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
          child: Text(translationService.t('waiter_cancel')),
        ),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyView({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.armchair,
              size: 42, color: context.appTextMuted),
          const SizedBox(height: 8),
          Text(translationService.t('waiter_tables_empty'),
              style: TextStyle(color: context.appText)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(LucideIcons.rotateCcw),
            label: Text(translationService.t('waiter_retry')),
          ),
        ],
      ),
    );
  }
}
