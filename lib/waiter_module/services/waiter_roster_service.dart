import 'package:flutter/foundation.dart';

import '../models/waiter.dart';

/// In-memory view of all waiters currently on the LAN.
///
/// Fed by mDNS discovery events and by WAITER_ANNOUNCE / WAITER_STATUS /
/// WAITER_LEAVE / HEARTBEAT wire messages. Widgets listen for live updates.
///
/// Peers that stop heartbeating are marked offline by [sweepStale]; they
/// stay in the roster (so the cashier can still see "Ali was handling
/// table 5 before losing connection") but in offline state.
class WaiterRosterService extends ChangeNotifier {
  final Map<String, Waiter> _byId = {};

  /// A peer is considered stale (= went offline) if no wire message has
  /// been received from it within this window.
  static const Duration staleThreshold = Duration(seconds: 45);

  List<Waiter> get all => _byId.values.toList(growable: false)
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Waiter? byId(String id) => _byId[id];

  bool upsert(Waiter w) {
    final existing = _byId[w.id];
    if (existing == null) {
      _byId[w.id] = w.copyWith(lastSeen: DateTime.now());
      notifyListeners();
      return true;
    }
    final merged = existing.copyWith(
      name: w.name.isNotEmpty ? w.name : existing.name,
      status: w.status,
      host: w.host ?? existing.host,
      port: w.port ?? existing.port,
      lastSeen: DateTime.now(),
    );
    final changed = merged.name != existing.name ||
        merged.status != existing.status ||
        merged.host != existing.host ||
        merged.port != existing.port;
    _byId[w.id] = merged;
    if (changed) notifyListeners();
    return changed;
  }

  void markOffline(String id) {
    final w = _byId[id];
    if (w == null) return;
    _byId[id] = w.copyWith(status: WaiterStatus.offline);
    notifyListeners();
  }

  void remove(String id) {
    if (_byId.remove(id) != null) notifyListeners();
  }

  void clear() {
    if (_byId.isEmpty) return;
    _byId.clear();
    notifyListeners();
  }

  /// Refresh a peer's `lastSeen` without changing any other field. Called
  /// for every inbound wire message so a silently-listening peer doesn't
  /// get reaped on the next sweep.
  void touch(String id) {
    final w = _byId[id];
    if (w == null) return;
    _byId[id] = w.copyWith(lastSeen: DateTime.now());
    // No notify — staleness change doesn't need a rebuild, but touching
    // updates the sweep window.
  }

  /// Scan the roster and mark any peer whose [Waiter.lastSeen] is older
  /// than [staleThreshold] as offline. Returns the ids that flipped to
  /// offline so callers (e.g. the controller) can react — for instance,
  /// the table registry may want to update the visible state for tables
  /// owned by those waiters.
  List<String> sweepStale({DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).subtract(staleThreshold);
    final flipped = <String>[];
    _byId.forEach((id, w) {
      if (w.status == WaiterStatus.offline) return;
      final ls = w.lastSeen;
      if (ls == null || ls.isBefore(cutoff)) {
        _byId[id] = w.copyWith(status: WaiterStatus.offline);
        flipped.add(id);
      }
    });
    if (flipped.isNotEmpty) notifyListeners();
    return flipped;
  }
}
