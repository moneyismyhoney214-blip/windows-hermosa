// ignore_for_file: library_private_types_in_public_api
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

  /// A `takingOrder` row ("جاري اخذ الطلب") with no booking is treated as
  /// stranded once it's been sitting unchanged this long — long enough that
  /// a waiter actually composing an order (who flips the table to `updated`
  /// the moment they add the first item) is never caught by it, short
  /// enough that a walked-away / force-killed waiter's pill self-clears.
  static const Duration _takingOrderStaleAfter = Duration(minutes: 5);

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
          // Preserve bookingId across lifecycle events — prevents the "invoice creates a second booking" bug.
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
          // Explicit orderId preservation (copyWith default behavior, made explicit for clarity).
          orderId: event.orderId ?? prev?.orderId,
        );
        break;
      case TableLifecycleKind.paymentPending:
        // Drop out-of-order paymentPending after paid in SAME billing session (scoped by orderId).
        final sameSession = prev?.paid == true &&
            prev?.orderId != null &&
            prev!.orderId == event.orderId;
        if (sameSession) {
          debugPrint(
            '⚠️ WaiterTableRegistry: dropping out-of-order paymentPending '
            'for table ${event.tableId} — row already paid for orderId '
            '${prev.orderId}',
          );
          return;
        }
        _byTableId[event.tableId] = (prev ?? _empty(event)).copyWith(
          paymentPending: true,
          paid: false,
          // Clear takingOrder so a row that never got an `updated` event doesn't stick on "جاري اخذ الطلب".
          takingOrder: false,
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
          // Invoiced table isn't taking order — clear flag so card flips to paid state.
          takingOrder: false,
          total: event.total,
          // Lock orderId on paid so paymentPending guard can scope rejection to this billing session.
          orderId: event.orderId ?? prev?.orderId,
        );
        break;
    }
    notifyListeners();
    // Commit-level events flush immediately — force-kill within 300ms debounce would resurrect closed tables.
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

  // --- Persistence ---

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
      // Dual-slot read for power-loss-mid-write recovery on cheap Sunmi filesystems.
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
          // Drop legacy persisted takingOrder rows that would resurrect a stuck pill.
          if (loaded.takingOrder) return;
          // Rewrite waiterId/Name to CURRENT session so reinstall / device-id regen doesn't lose ownership.
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

  // Serialize persist writes so the backup→primary pair stays atomic against the next flush.
  Future<void> _persistTail = Future<void>.value();

  Future<void> _flushPersist() {
    _persistTail = _persistTail.then((_) => _flushPersistOnce());
    return _persistTail;
  }

  Future<void> _flushPersistOnce() async {
    final scope = _persistScope;
    if (scope == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{};
      _byTableId.forEach((k, v) {
        // Don't persist transient takingOrder rows — they'd resurrect a stuck "جاري اخذ الطلب" on relaunch.
        if (v.takingOrder) return;
        map[k] = v.toJson();
      });
      final encoded = jsonEncode(map);
      final primaryKey = '$_persistKeyPrefix$scope';
      final backupKey = '$primaryKey.bak';
      // Backup first, then primary — survives mid-write kernel panic.
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
    // Chain wipe onto persist tail so an in-flight setString can't resurrect cleared rows.
    _persistTail = _persistTail.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final primaryKey = '$_persistKeyPrefix$scope';
        await prefs.remove(primaryKey);
        await prefs.remove('$primaryKey.bak');
      } catch (e) {
        debugPrint('⚠️ WaiterTableRegistry clearPersisted failed: $e');
      }
    });
    return _persistTail;
  }

  _TableOwnership _empty(TableLifecycleEvent event) => _TableOwnership(
        waiterId: event.waiterId,
        waiterName: event.waiterName,
        tableNumber: event.tableNumber,
      );

  /// Drop registry rows for tables that the backend now reports as
  /// freely available. Used after `getTables()` to evict ghost entries
  /// when the source of truth has moved on.
  ///
  /// Evicts, for a table the backend says is `available`:
  ///   * `takingOrder` rows — transient ("the order screen is open"); the
  ///     backend never sees a booking for one. Kept ONLY when this device
  ///     currently has the order screen open for that exact table
  ///     ([activeOrderingTableId] == id) — otherwise the backend's
  ///     "available" wins, so a `released` that never reached us (Wi-Fi
  ///     flap / force-kill) can't strand the table at "جاري اخذ الطلب".
  ///   * draft-only rows — no booking id, but with items: the waiter opened
  ///     the table, dropped an item in, and walked away without sending; no
  ///     booking exists, so the backend is right that the table is free.
  ///   * `paid` / `paymentPending` rows — the booking was closed/cancelled
  ///     elsewhere while this device was offline. Suppressed when
  ///     [evictCommitted] is false (the cashier passes false: it owns the
  ///     close flow, and a momentarily-stale `getTables` read mustn't drop a
  ///     pay-later booking it just saw broadcast). Also suppressed — always —
  ///     for a committed row this device owns ([selfId] matches and it carries
  ///     a booking id): the booking write may simply not have surfaced in the
  ///     `getTables` snapshot yet; it clears on the matching `released`/`paid`.
  ///
  /// [selfId] — this device's waiter id (for the `takingOrder` self-owned
  /// check). [activeOrderingTableId] — the table this device currently has
  /// the order-composition screen open for, if any.
  void reconcileWithBackend(
    Iterable<String> availableTableIds, {
    String? selfId,
    String? activeOrderingTableId,
    bool evictCommitted = true,
  }) {
    if (_byTableId.isEmpty) return;
    final evicted = <String>[];
    for (final id in availableTableIds) {
      final row = _byTableId[id];
      if (row == null) continue;
      // Mid-order on this device for this table — keep it; booking doesn't exist yet.
      if (row.takingOrder &&
          selfId != null &&
          selfId.isNotEmpty &&
          row.waiterId == selfId &&
          activeOrderingTableId != null &&
          activeOrderingTableId == id) {
        continue;
      }
      final committed = row.paid || row.paymentPending;
      final hasBooking = row.orderId != null && row.orderId!.isNotEmpty;
      // Self-owned committed booking is authoritative — backend table list lags booking writes.
      final selfCommitted = committed &&
          hasBooking &&
          selfId != null &&
          selfId.isNotEmpty &&
          row.waiterId == selfId;
      // Only stale takingOrder rows get evicted — fresh ones are still mid-compose on a peer.
      final takingOrderStale = row.takingOrder &&
          DateTime.now().difference(row.touchedAt) > _takingOrderStaleAfter;
      final draftWithItems =
          !committed && !row.takingOrder && !hasBooking && (row.itemCount ?? 0) > 0;
      // Self-owned draft with items — cart still holds them locally and the waiter will return
      // to send/pay. Backend hasn't seen a booking yet, but the table is "ours" — don't flip it
      // back to green just because getTables() lags the local cart. Manual "تحرير الطاولة" still releases.
      final selfDraft = draftWithItems &&
          selfId != null &&
          selfId.isNotEmpty &&
          row.waiterId == selfId;
      final shouldEvict = (committed && evictCommitted && !selfCommitted) ||
          takingOrderStale ||
          (draftWithItems && !selfDraft);
      if (shouldEvict) {
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

  /// Drop only the transient `takingOrder` rows owned by [waiterId] — used
  /// when that waiter goes offline (force-killed / left the building) so a
  /// "جاري اخذ الطلب" pill the cashier is still showing for them clears
  /// fast, without disturbing their committed (pay-later / paid / sent)
  /// tables, which the cashier still needs to close out.
  void dropTakingOrderForWaiter(String waiterId) {
    final removed = _byTableId.keys
        .where((k) {
          final row = _byTableId[k];
          return row != null && row.waiterId == waiterId && row.takingOrder;
        })
        .toList();
    for (final k in removed) {
      _byTableId.remove(k);
    }
    if (removed.isNotEmpty) {
      debugPrint(
          '🧹 WaiterTableRegistry: dropped ${removed.length} takingOrder row(s) '
          'for offline waiter $waiterId: $removed');
      notifyListeners();
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
    // Await disk wipe so subsequent hydrate() observes the cleared key.
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

  /// When this row was (re)created. Only consulted for `takingOrder` rows:
  /// a "جاري اخذ الطلب" that's been sitting unchanged this long with no
  /// booking is treated as stranded (the waiter walked away / force-killed
  /// and the `released` never arrived) and gets reconciled away. While it's
  /// still fresh the cashier keeps showing the pill — that's the whole
  /// point: the previous "evict any takingOrder row the backend reports
  /// available" rule wiped the pill off the cashier the moment a waiter
  /// opened a table.
  final DateTime touchedAt;

  _TableOwnership({
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
    DateTime? touchedAt,
  }) : touchedAt = touchedAt ?? DateTime.now();

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
        'touchedAt': touchedAt.toIso8601String(),
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
      touchedAt: DateTime.tryParse(j['touchedAt']?.toString() ?? ''),
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
    DateTime? touchedAt,
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
      touchedAt: touchedAt ?? this.touchedAt,
    );
  }
}

// Silences unused import of Waiter — reserved for future getters.
// ignore: unused_element
Type _waiterRef() => Waiter;
