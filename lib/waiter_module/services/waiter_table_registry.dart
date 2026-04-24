import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/waiter.dart';
import '../models/waiter_table_event.dart';

/// Exposed snapshot the cashier can render for its Details dialog.
typedef WaiterTableSnapshot = _TableOwnership;

/// Authoritative-on-this-device view of "which waiter owns which table".
///
/// Every waiter and the cashier all subscribe to [TableLifecycleEvent]s
/// coming from the WaiterController; this store collapses those events into
/// a simple "who owns table X?" map that the UI can query.
class WaiterTableRegistry extends ChangeNotifier {
  final Map<String, _TableOwnership> _byTableId = {};

  /// Scope key for the persistence slot. When a waiter signs in the
  /// controller calls [hydrate] with their identity; every subsequent
  /// [apply] then writes to the same slot. Clearing / switching waiters
  /// flips this so the next session doesn't pick up the previous
  /// shift's rows.
  String? _persistScope;
  Timer? _persistDebounce;

  static const String _persistKeyPrefix = 'waiter_table_registry_v2_';

  /// Build the persistence scope so the same device serving two waiters
  /// (shared Sunmi tablet) never leaks one's state into the other's
  /// view. We include both branch and waiter name because:
  ///   - branchId changes when the cashier signs into a different
  ///     branch on the same hardware
  ///   - name changes when a different waiter signs in
  ///
  /// `Uri.encodeComponent` is deliberate: a naive
  /// `replaceAll(\s+, "_")` collapses `"Ali Ahmed"` and `"Ali  Ahmed"`
  /// (one vs two internal spaces) to the same key, which on a shared
  /// tablet would leak one waiter's pay-later tables into the other's
  /// grid. `encodeComponent` emits `%20` per space so every distinct
  /// input produces a distinct key.
  static String _scopeFor({required String branchId, required String name}) {
    final safeBranch = Uri.encodeComponent(branchId.trim());
    final safeName = Uri.encodeComponent(name.trim());
    return '${safeBranch}_$safeName';
  }

  _TableOwnership? lookup(String tableId) => _byTableId[tableId];

  String? ownerIdFor(String tableId) => _byTableId[tableId]?.waiterId;
  String? ownerNameFor(String tableId) => _byTableId[tableId]?.waiterName;
  int? guestCountFor(String tableId) => _byTableId[tableId]?.guestCount;
  double? totalFor(String tableId) => _byTableId[tableId]?.total;
  int? itemCountFor(String tableId) => _byTableId[tableId]?.itemCount;
  List<TableItemSnapshot> itemsFor(String tableId) =>
      _byTableId[tableId]?.items ?? const <TableItemSnapshot>[];
  bool paymentPendingFor(String tableId) =>
      _byTableId[tableId]?.paymentPending ?? false;
  bool paidFor(String tableId) => _byTableId[tableId]?.paid ?? false;
  bool takingOrderFor(String tableId) =>
      _byTableId[tableId]?.takingOrder ?? false;
  String? bookingIdFor(String tableId) => _byTableId[tableId]?.orderId;

  /// Every (tableId, ownership) pair owned by [waiterId]. Used by the
  /// controller to snapshot this device's tables to a newly-joined peer
  /// so late joiners don't see an empty registry.
  Iterable<MapEntry<String, _TableOwnership>> ownedBy(String waiterId) sync* {
    for (final entry in _byTableId.entries) {
      if (entry.value.waiterId == waiterId) yield entry;
    }
  }

  void apply(TableLifecycleEvent event) {
    final prev = _byTableId[event.tableId];
    switch (event.kind) {
      case TableLifecycleKind.takingOrder:
        _byTableId[event.tableId] = _TableOwnership(
          waiterId: event.waiterId,
          waiterName: event.waiterName,
          tableNumber: event.tableNumber,
          guestCount: event.guestCount ?? prev?.guestCount,
          total: event.total ?? prev?.total,
          itemCount: event.itemCount ?? prev?.itemCount ?? 0,
          items: event.items ?? prev?.items ?? const [],
          paymentPending: false,
          paid: false,
          takingOrder: true,
          // Preserve the backend bookingId across lifecycle events —
          // without this, a pay-later booking's orderId would be wiped
          // by any subsequent takingOrder/assigned event, and the next
          // "Create Invoice" would fall back to creating a brand-new
          // booking. Root cause of the "invoice creates a second
          // booking" bug. If the incoming event carries a fresh
          // orderId we prefer it; otherwise we keep the one we had.
          orderId: event.orderId ?? prev?.orderId,
        );
        break;
      case TableLifecycleKind.assigned:
        _byTableId[event.tableId] = _TableOwnership(
          waiterId: event.waiterId,
          waiterName: event.waiterName,
          tableNumber: event.tableNumber,
          guestCount: event.guestCount ?? prev?.guestCount,
          total: event.total ?? prev?.total,
          itemCount: event.itemCount ?? prev?.itemCount,
          items: event.items ?? prev?.items ?? const [],
          paymentPending: false,
          paid: false,
          takingOrder: false,
          orderId: event.orderId ?? prev?.orderId,
        );
        break;
      case TableLifecycleKind.released:
        _byTableId.remove(event.tableId);
        break;
      case TableLifecycleKind.updated:
        _byTableId[event.tableId] = (prev ?? _empty(event)).copyWith(
          waiterId: event.waiterId,
          waiterName: event.waiterName,
          tableNumber: event.tableNumber.isNotEmpty
              ? event.tableNumber
              : prev?.tableNumber,
          guestCount: event.guestCount,
          total: event.total,
          itemCount: event.itemCount,
          items: event.items,
          // Any real update (items sent) clears the "taking order" flag.
          takingOrder: false,
          // Preserve orderId if this update carries one, else keep the
          // existing (copyWith defaults to `this.orderId` anyway, but
          // being explicit here avoids a future maintainer wondering
          // whether this case drops the bookingId like takingOrder/
          // assigned used to).
          orderId: event.orderId ?? prev?.orderId,
        );
        break;
      case TableLifecycleKind.paymentPending:
        _byTableId[event.tableId] = (prev ?? _empty(event)).copyWith(
          paymentPending: true,
          paid: false,
          total: event.total,
          itemCount: event.itemCount,
          items: event.items,
          orderId: event.orderId ?? prev?.orderId,
        );
        break;
      case TableLifecycleKind.paid:
        _byTableId[event.tableId] = (prev ?? _empty(event)).copyWith(
          paymentPending: false,
          paid: true,
          total: event.total,
        );
        break;
    }
    notifyListeners();
    // Commit-level events — released / paid / paymentPending — flush
    // to disk immediately instead of waiting for the 300ms debounce.
    // A force-kill in that window after a waiter taps "Release" or a
    // pay-later commit would otherwise resurrect the closed table on
    // next launch, which is exactly the kind of amnesia this layer is
    // meant to prevent.
    switch (event.kind) {
      case TableLifecycleKind.released:
      case TableLifecycleKind.paid:
      case TableLifecycleKind.paymentPending:
        _persistDebounce?.cancel();
        unawaited(_flushPersist());
        break;
      case TableLifecycleKind.takingOrder:
      case TableLifecycleKind.assigned:
      case TableLifecycleKind.updated:
        _schedulePersist();
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  /// Pull the registry rows saved for this waiter on this device. Safe
  /// to call repeatedly — rehydrating while rows exist replaces the
  /// cursor with the disk snapshot so a mid-session re-login can't
  /// duplicate entries.
  ///
  /// Called by [WaiterController.start] right after the session is
  /// confirmed so the waiter reopening the app sees their pay-later
  /// tables / ownership / booking ids again instead of a blank grid.
  Future<void> hydrate({
    required String branchId,
    required String name,
    required String selfId,
  }) async {
    _persistScope = _scopeFor(branchId: branchId, name: name);
    try {
      final prefs = await SharedPreferences.getInstance();
      final primaryKey = '$_persistKeyPrefix$_persistScope';
      final backupKey = '$primaryKey.bak';
      // Dual-slot read: if the primary blob is corrupt (power-loss
      // mid-write on a cheap Sunmi filesystem), the backup is the
      // pre-commit snapshot we wrote BEFORE the primary. Worst case
      // we lose the last edit but keep everything prior.
      Map? decoded;
      for (final key in [primaryKey, backupKey]) {
        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        try {
          final parsed = jsonDecode(raw);
          if (parsed is Map) {
            decoded = parsed;
            break;
          }
        } catch (e) {
          debugPrint(
              '⚠️ WaiterTableRegistry: slot "$key" corrupt ($e), trying next');
        }
      }
      if (decoded == null) return;
      _byTableId.clear();
      decoded.forEach((key, value) {
        if (key is! String || value is! Map) return;
        try {
          final loaded = _TableOwnership.fromJson(
            value.map((k, v) => MapEntry(k.toString(), v)),
          );
          // The persistence key is already scoped to this waiter, so
          // any row we pull out is by definition ours. Rewrite the
          // waiterId/Name to the CURRENT session identity so
          // `ownedBy(self.id)` picks these rows up when we HELLO
          // peers — without this, a reinstall / device-id regen
          // would leave hydrated rows with a stale waiterId that no
          // longer matches and our snapshot push would miss them.
          _byTableId[key] = loaded.copyWith(
            waiterId: selfId,
            waiterName: name,
          );
        } catch (e) {
          debugPrint('⚠️ WaiterTableRegistry.hydrate: skipped bad row $key ($e)');
        }
      });
      if (_byTableId.isNotEmpty) notifyListeners();
    } catch (e) {
      debugPrint('⚠️ WaiterTableRegistry.hydrate failed: $e');
    }
  }

  /// Debounced write. Every `apply` calls us; batching within 300ms
  /// keeps the disk IO quiet during a flurry of broadcasts (e.g. a
  /// mesh HELLO fanning out a peer's roster).
  void _schedulePersist() {
    if (_persistScope == null) return;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 300), _flushPersist);
  }

  Future<void> _flushPersist() async {
    final scope = _persistScope;
    if (scope == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{};
      _byTableId.forEach((k, v) {
        map[k] = v.toJson();
      });
      final encoded = jsonEncode(map);
      final primaryKey = '$_persistKeyPrefix$scope';
      final backupKey = '$primaryKey.bak';
      // Dual-slot write: update the backup FIRST (so if we die now, the
      // backup still matches the prior primary); THEN update the
      // primary. A kernel panic between the two leaves primary stale
      // but backup current-or-prior — either way hydrate can recover.
      await prefs.setString(backupKey, encoded);
      await prefs.setString(primaryKey, encoded);
    } catch (e) {
      debugPrint('⚠️ WaiterTableRegistry persist failed: $e');
    }
  }

  /// Drop the on-disk rows for the current scope. Called on sign-out so
  /// the next user of this device starts with a clean slate instead of
  /// inheriting the prior shift's state.
  Future<void> clearPersisted() async {
    final scope = _persistScope;
    _persistDebounce?.cancel();
    _persistScope = null;
    if (scope == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final primaryKey = '$_persistKeyPrefix$scope';
      await prefs.remove(primaryKey);
      await prefs.remove('$primaryKey.bak');
    } catch (e) {
      debugPrint('⚠️ WaiterTableRegistry clearPersisted failed: $e');
    }
  }

  _TableOwnership _empty(TableLifecycleEvent event) => _TableOwnership(
        waiterId: event.waiterId,
        waiterName: event.waiterName,
        tableNumber: event.tableNumber,
      );

  /// Drop registry rows for tables that the backend now reports as
  /// freely available. Used after `getTables()` to evict ghost entries
  /// from the persisted snapshot when the source of truth has moved
  /// on — e.g. the cashier closed a pay-later booking on this device's
  /// behalf while the waiter was offline. Only evicts `paid` / `paymentPending`
  /// rows; `takingOrder` is transient local-only state.
  void reconcileWithBackend(Iterable<String> availableTableIds) {
    if (_byTableId.isEmpty) return;
    final evicted = <String>[];
    for (final id in availableTableIds) {
      final row = _byTableId[id];
      if (row == null) continue;
      if (row.paid || row.paymentPending) {
        _byTableId.remove(id);
        evicted.add(id);
      }
    }
    if (evicted.isNotEmpty) {
      debugPrint(
          '🧹 WaiterTableRegistry reconcile evicted ${evicted.length} stale row(s): $evicted');
      notifyListeners();
      _persistDebounce?.cancel();
      unawaited(_flushPersist());
    }
  }

  void clearForWaiter(String waiterId) {
    final removed =
        _byTableId.keys.where((k) => _byTableId[k]?.waiterId == waiterId).toList();
    for (final k in removed) {
      _byTableId.remove(k);
    }
    if (removed.isNotEmpty) {
      notifyListeners();
      _schedulePersist();
    }
  }

  /// Drop every ownership record. Used on branch switch / logout so the
  /// next session doesn't inherit the previous shift's table state.
  ///
  /// Returns a future that completes only after the on-disk persistence
  /// key has been removed. Callers that re-login immediately (same
  /// waiter, same device) MUST await this — otherwise a race with
  /// [hydrate]'s read would resurrect the just-cleared state.
  Future<void> clearAll() async {
    final hadRows = _byTableId.isNotEmpty;
    _byTableId.clear();
    if (hadRows) notifyListeners();
    // Await the disk wipe so a subsequent hydrate() on the same
    // SharedPreferences instance observes the cleared key instead of
    // racing against an in-flight remove.
    await clearPersisted();
  }
}

@immutable
class _TableOwnership {
  final String waiterId;
  final String waiterName;
  final String tableNumber;
  final int? guestCount;
  final double? total;
  final int? itemCount;
  final List<TableItemSnapshot> items;
  final bool paymentPending;
  final bool paid;
  final bool takingOrder;
  /// Backend booking id for the active order on this table. Stashed so
  /// the waiter's "Edit Order" reuses `updateBookingItems` on the same
  /// record instead of creating a duplicate booking.
  final String? orderId;

  const _TableOwnership({
    required this.waiterId,
    required this.waiterName,
    this.tableNumber = '',
    this.guestCount,
    this.total,
    this.itemCount,
    this.items = const [],
    this.paymentPending = false,
    this.paid = false,
    this.takingOrder = false,
    this.orderId,
  });

  Map<String, dynamic> toJson() => {
        'waiterId': waiterId,
        'waiterName': waiterName,
        'tableNumber': tableNumber,
        if (guestCount != null) 'guestCount': guestCount,
        if (total != null) 'total': total,
        if (itemCount != null) 'itemCount': itemCount,
        if (items.isNotEmpty)
          'items': items.map((e) => e.toJson()).toList(),
        'paymentPending': paymentPending,
        'paid': paid,
        'takingOrder': takingOrder,
        if (orderId != null) 'orderId': orderId,
      };

  factory _TableOwnership.fromJson(Map<String, dynamic> j) {
    final rawItems = j['items'];
    return _TableOwnership(
      waiterId: j['waiterId']?.toString() ?? '',
      waiterName: j['waiterName']?.toString() ?? '',
      tableNumber: j['tableNumber']?.toString() ?? '',
      guestCount: (j['guestCount'] as num?)?.toInt(),
      total: (j['total'] as num?)?.toDouble(),
      itemCount: (j['itemCount'] as num?)?.toInt(),
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((m) => TableItemSnapshot.fromJson(
                  m.map((k, v) => MapEntry(k.toString(), v))))
              .toList()
          : const [],
      paymentPending: j['paymentPending'] == true,
      paid: j['paid'] == true,
      takingOrder: j['takingOrder'] == true,
      orderId: j['orderId']?.toString(),
    );
  }

  _TableOwnership copyWith({
    String? waiterId,
    String? waiterName,
    String? tableNumber,
    int? guestCount,
    double? total,
    int? itemCount,
    List<TableItemSnapshot>? items,
    bool? paymentPending,
    bool? paid,
    bool? takingOrder,
    String? orderId,
  }) {
    return _TableOwnership(
      waiterId: waiterId ?? this.waiterId,
      waiterName: waiterName ?? this.waiterName,
      tableNumber: tableNumber ?? this.tableNumber,
      guestCount: guestCount ?? this.guestCount,
      total: total ?? this.total,
      itemCount: itemCount ?? this.itemCount,
      items: items ?? this.items,
      paymentPending: paymentPending ?? this.paymentPending,
      paid: paid ?? this.paid,
      takingOrder: takingOrder ?? this.takingOrder,
      orderId: orderId ?? this.orderId,
    );
  }
}

// Silences the unused import of Waiter — reserved for future getters that
// need the full Waiter object.
// ignore: unused_element
Type _waiterRef() => Waiter;
