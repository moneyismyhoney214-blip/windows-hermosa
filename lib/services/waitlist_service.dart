import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/waitlist_entry.dart';
import '../models/waitlist_mesh_event.dart';

/// Type for the broadcast hook — invoked after every local mutation.
/// The hook is responsible for putting the delta on the wire (the
/// service itself doesn't depend on the mesh layer).
typedef WaitlistBroadcaster = void Function(WaitlistMeshEvent event);

/// Singleton store for the restaurant's walk-in waitlist.
///
/// Hard rules:
///   * Every mutation goes through here — UI reads via [entries] /
///     [addListener] and never touches SharedPreferences directly.
///   * Persistence is fire-and-forget: the in-memory list is the source
///     of truth for the current session, disk is the durable mirror.
///   * The service survives tab switches and both modules (cashier +
///     waiter) share the same instance so a party added on one side
///     appears on the other immediately.
///   * Cross-device sync is wired by [WaitlistMeshBridge] via
///     [registerBroadcaster] + [applyRemote]. The service knows nothing
///     about the transport — it just emits deltas through the hook.
class WaitlistService extends ChangeNotifier {
  static final WaitlistService _instance = WaitlistService._internal();
  factory WaitlistService() => _instance;
  WaitlistService._internal();

  static const String _storageKey = 'waitlist_entries_v1';

  /// Active + historical parties. The UI filters by [WaitlistEntry.isActive]
  /// where it needs the live queue. We keep the rest so "seated" / "cancelled"
  /// rows can appear in a history view later without re-loading.
  final List<WaitlistEntry> _entries = [];

  bool _initialized = false;
  Future<void>? _initFuture;

  /// Injected by [WaitlistMeshBridge] once the mesh is up. Left null
  /// when the app runs without peers — all mutations still work
  /// locally in that mode.
  WaitlistBroadcaster? _broadcaster;

  /// A **read-only view** of the current list, sorted oldest-first
  /// (the host wants to seat whoever's been waiting longest).
  List<WaitlistEntry> get entries {
    final sorted = [..._entries]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(sorted);
  }

  /// Only the parties still actively waiting or already notified but
  /// not yet seated — this is what the badge count + sheet list show.
  List<WaitlistEntry> get active =>
      entries.where((e) => e.isActive).toList(growable: false);

  /// Historical rows: seated + cancelled. Newest-first for the
  /// history screen, since you usually want to scan recent outcomes.
  List<WaitlistEntry> get history {
    final sorted = _entries.where((e) => !e.isActive).toList()
      ..sort((a, b) {
        // Seated → notifiedAt; cancelled → createdAt (best proxy).
        final aStamp = a.notifiedAt ?? a.createdAt;
        final bStamp = b.notifiedAt ?? b.createdAt;
        return bStamp.compareTo(aStamp);
      });
    return List.unmodifiable(sorted);
  }

  /// Unseated count for the badge on the header button.
  int get activeCount => _entries.where((e) => e.isActive).length;

  /// Find the entry currently linked to a table, if any.
  /// Used to paint a "في انتظار: NAME" pill on the matching table card.
  WaitlistEntry? entryForTable(String tableId) {
    for (final e in _entries) {
      if (e.status == WaitlistStatus.notified &&
          e.assignedTableId == tableId) {
        return e;
      }
    }
    return null;
  }

  /// The backend customer id of whichever party was sent to [tableId] —
  /// regardless of whether they're still `notified` or already `seated`
  /// (the order screen reads this when billing, by which point the party
  /// has been marked seated). Cancelled entries are ignored. Returns null
  /// when there's no linked customer.
  String? customerIdForTable(String tableId) {
    for (final e in _entries.reversed) {
      if (e.assignedTableId == tableId &&
          e.status != WaitlistStatus.cancelled &&
          e.customerId != null) {
        return e.customerId;
      }
    }
    return null;
  }

  /// Display name of whichever party was sent to [tableId] (notified or
  /// seated), ignoring cancelled rows. Used by the waiter order screen to
  /// label the linked customer when there's no manual binding to read.
  String? customerNameForTable(String tableId) {
    for (final e in _entries.reversed) {
      if (e.assignedTableId == tableId &&
          e.status != WaitlistStatus.cancelled &&
          e.customerName.isNotEmpty) {
        return e.customerName;
      }
    }
    return null;
  }

  /// Snapshot used when catching up a freshly-joined peer.
  WaitlistMeshSnapshot buildSnapshot() =>
      WaitlistMeshSnapshot(entries: List.unmodifiable(_entries));

  /// Lazy init — safe to call from anywhere (and repeatedly). Only
  /// hits disk on the first call per process.
  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initFuture ??= _loadFromDisk();
  }

  /// Wire the mesh transport. Called once by the bridge; passing
  /// `null` detaches it (e.g. after sign-out tears down the mesh).
  void registerBroadcaster(WaitlistBroadcaster? broadcaster) {
    _broadcaster = broadcaster;
  }

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _entries
            ..clear()
            ..addAll(
              decoded
                  .whereType<Map<String, dynamic>>()
                  .map(WaitlistEntry.fromJson),
            );
        }
      }
    } catch (e, st) {
      // Corrupt prefs — reset silently rather than crash; host can re-add parties.
      developer.log(
        'WaitlistService: failed to decode stored entries — starting empty',
        error: e,
        stackTrace: st,
      );
      _entries.clear();
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode(_entries.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, payload);
    } catch (e, st) {
      developer.log(
        'WaitlistService: persist failed — in-memory state kept',
        error: e,
        stackTrace: st,
      );
    }
  }

  void _broadcast(WaitlistMeshEvent event) {
    final hook = _broadcaster;
    if (hook == null) return;
    try {
      hook(event);
    } catch (e, st) {
      developer.log(
        'WaitlistService: broadcaster threw — local state still correct',
        error: e,
        stackTrace: st,
      );
    }
  }

  // --- Local mutations. applyRemote/applySnapshot skip the broadcaster to avoid echo loops. ---

  Future<WaitlistEntry> add(WaitlistEntry entry) async {
    _entries.add(entry);
    notifyListeners();
    _broadcast(WaitlistMeshEvent.added(entry));
    await _persist();
    return entry;
  }

  Future<void> update(WaitlistEntry updated) async {
    final idx = _entries.indexWhere((e) => e.id == updated.id);
    if (idx < 0) return;
    _entries[idx] = updated;
    notifyListeners();
    _broadcast(WaitlistMeshEvent.updated(updated));
    await _persist();
  }

  Future<void> remove(String id) async {
    final before = _entries.length;
    _entries.removeWhere((e) => e.id == id);
    if (_entries.length == before) return;
    notifyListeners();
    _broadcast(WaitlistMeshEvent.removed(id));
    await _persist();
  }

  Future<void> cancel(String id) async {
    final idx = _entries.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final updated = _entries[idx].copyWith(status: WaitlistStatus.cancelled);
    _entries[idx] = updated;
    notifyListeners();
    _broadcast(WaitlistMeshEvent.cancelled(updated));
    await _persist();
  }

  /// Mark a party as notified AND link them to the table they'll take.
  /// Returns the updated entry so callers can reuse it (e.g. for snackbar
  /// text) without a second lookup.
  Future<WaitlistEntry?> markNotified({
    required String entryId,
    required String tableId,
    required String tableNumber,
    DateTime? at,
  }) async {
    final idx = _entries.indexWhere((e) => e.id == entryId);
    if (idx < 0) return null;
    final updated = _entries[idx].copyWith(
      status: WaitlistStatus.notified,
      assignedTableId: tableId,
      assignedTableNumber: tableNumber,
      notifiedAt: at ?? DateTime.now(),
    );
    _entries[idx] = updated;
    notifyListeners();
    _broadcast(WaitlistMeshEvent.notified(updated));
    await _persist();
    return updated;
  }

  /// Called when the cashier/waiter finally opens the table the party
  /// was assigned to. Closes out the entry so the queue shortens.
  Future<void> markSeated(String entryId) async {
    final idx = _entries.indexWhere((e) => e.id == entryId);
    if (idx < 0) return;
    final updated = _entries[idx].copyWith(status: WaitlistStatus.seated);
    _entries[idx] = updated;
    notifyListeners();
    _broadcast(WaitlistMeshEvent.seated(updated));
    await _persist();
  }

  /// Undo a table hold: the party that was `notified` onto [tableId] goes
  /// back to plain `waiting` and the table is freed (its assigned-table
  /// fields are cleared). Backs the "Cancel hold" action in the
  /// seat-confirmation dialog. No-op if the entry isn't currently holding
  /// that table.
  Future<void> releaseHold(String entryId) async {
    final idx = _entries.indexWhere((e) => e.id == entryId);
    if (idx < 0) return;
    final e = _entries[idx];
    if (e.status != WaitlistStatus.notified) return;
    final updated = e.copyWith(
      status: WaitlistStatus.waiting,
      clearAssignedTable: true,
      clearNotifiedAt: true,
    );
    _entries[idx] = updated;
    notifyListeners();
    _broadcast(WaitlistMeshEvent.updated(updated));
    await _persist();
  }

  /// Called when [tableId] is released (party done / booking cancelled).
  /// Detaches any already-`seated` row that was pinned to that table so a
  /// later walk-in on the same table doesn't get mis-attributed to the
  /// previous party (via [customerIdForTable] / [customerNameForTable]).
  /// `notified` rows are deliberately left alone — they're still a live
  /// hold on the table (e.g. a "Seat now" party whose order screen the
  /// waiter opened then backed out of with an empty cart).
  Future<void> detachSeatedFromTable(String tableId) async {
    if (tableId.isEmpty) return;
    var changed = false;
    for (int i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      if (e.status == WaitlistStatus.seated && e.assignedTableId == tableId) {
        final updated = e.copyWith(clearAssignedTable: true);
        _entries[i] = updated;
        _broadcast(WaitlistMeshEvent.updated(updated));
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      await _persist();
    }
  }

  /// Follow a table migration: re-point any `notified` / `seated` entry
  /// from [fromTableId] to [toTableId] so the customer↔table binding moves
  /// with the order (otherwise `customerIdForTable(newTable)` returns null
  /// and the migrated table shows up as an anonymous walk-in). Broadcast so
  /// every device converges. No-op when nothing is pinned to the source.
  Future<void> reassignAssignedTable(
    String fromTableId,
    String toTableId, {
    String? toTableNumber,
  }) async {
    if (fromTableId.isEmpty || toTableId.isEmpty || fromTableId == toTableId) {
      return;
    }
    var changed = false;
    for (int i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      if (e.assignedTableId != fromTableId) continue;
      if (e.status != WaitlistStatus.notified &&
          e.status != WaitlistStatus.seated) {
        continue;
      }
      final updated = e.copyWith(
        assignedTableId: toTableId,
        assignedTableNumber: (toTableNumber != null && toTableNumber.isNotEmpty)
            ? toTableNumber
            : e.assignedTableNumber,
      );
      _entries[i] = updated;
      _broadcast(WaitlistMeshEvent.updated(updated));
      changed = true;
    }
    if (changed) {
      notifyListeners();
      await _persist();
    }
  }

  /// Purges historical rows (seated / cancelled). Wired to a future
  /// "clear history" action in the settings.
  Future<void> clearHistory() async {
    _entries.removeWhere((e) => !e.isActive);
    notifyListeners();
    await _persist();
    // Not broadcast: history pruning is local-only housekeeping.
  }

  // --- Remote application (never re-broadcasts) ---

  /// Apply a delta received from another device. Mirrors every branch
  /// of the local mutations above **without** calling [_broadcast] —
  /// otherwise we'd bounce the event back to the sender forever.
  ///
  /// Last-write-wins on conflicts: we don't reject older events. In
  /// practice the mesh is low-latency enough that the "newer is better"
  /// assumption holds; if we ever see real conflicts we can add a
  /// per-entry lastAppliedAt gate.
  Future<void> applyRemote(WaitlistMeshEvent event) async {
    final idx = _entries.indexWhere((e) => e.id == event.entryId);
    switch (event.kind) {
      case WaitlistMeshKind.added:
        if (event.entry == null) return;
        if (idx >= 0) {
          // Race: id collision (rare with UUIDs) — treat as update.
          _entries[idx] = event.entry!;
        } else {
          _entries.add(event.entry!);
        }
        break;
      case WaitlistMeshKind.updated:
      case WaitlistMeshKind.notified:
      case WaitlistMeshKind.seated:
      case WaitlistMeshKind.cancelled:
        if (event.entry == null) return;
        if (idx >= 0) {
          _entries[idx] = event.entry!;
        } else {
          // Joined late and never saw the original add — accept as-is for queue consistency.
          _entries.add(event.entry!);
        }
        break;
      case WaitlistMeshKind.removed:
        if (idx < 0) return;
        _entries.removeAt(idx);
        break;
    }
    notifyListeners();
    await _persist();
  }

  /// Replace the queue with a full snapshot from a peer. Used as the
  /// catch-up after we join a LAN that already has parties queued.
  ///
  /// Merge strategy: union by id, snapshot wins on conflicts. Any
  /// entries we had that aren't in the snapshot are kept (they may be
  /// local-only history rows the peer already cleared).
  Future<void> applySnapshot(WaitlistMeshSnapshot snapshot) async {
    final incoming = {for (final e in snapshot.entries) e.id: e};
    bool changed = false;
    for (int i = 0; i < _entries.length; i++) {
      final fresh = incoming.remove(_entries[i].id);
      if (fresh != null && !_sameEntry(_entries[i], fresh)) {
        _entries[i] = fresh;
        changed = true;
      }
    }
    if (incoming.isNotEmpty) {
      _entries.addAll(incoming.values);
      changed = true;
    }
    if (changed) {
      notifyListeners();
      await _persist();
    }
  }

  bool _sameEntry(WaitlistEntry a, WaitlistEntry b) {
    return a.id == b.id &&
        a.customerName == b.customerName &&
        a.phoneNumber == b.phoneNumber &&
        a.partySize == b.partySize &&
        a.notes == b.notes &&
        a.status == b.status &&
        a.notifiedAt == b.notifiedAt &&
        a.assignedTableId == b.assignedTableId &&
        a.assignedTableNumber == b.assignedTableNumber;
  }
}

/// Global accessor — mirrors the convention used by translationService,
/// themeService, etc.
final waitlistService = WaitlistService();
