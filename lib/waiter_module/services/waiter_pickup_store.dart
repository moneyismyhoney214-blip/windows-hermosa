import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/table_pickup_request.dart';

/// In-memory pickup registry. Lives on every peer (cashier + waiters) so
/// every device converges to the same claim/cancel state without a
/// central server. State is ephemeral by design — a pickup is a
/// conversation that either settles within ~10s or gets cancelled, so
/// persisting across app restarts would just surface stale notifications
/// when the next shift starts.
class WaiterPickupStore extends ChangeNotifier {
  /// Oldest requests are auto-trimmed beyond this cap so a long-lived
  /// cashier session doesn't accumulate cruft.
  static const int _capacity = 50;

  /// A pending request older than this is considered dead (no waiter
  /// answered). The UI hides it automatically.
  static const Duration pendingTtl = Duration(minutes: 3);

  /// Even claimed/cancelled entries disappear after this window so the
  /// notification list doesn't grow forever.
  static const Duration terminalTtl = Duration(minutes: 10);

  final LinkedHashMap<String, TablePickupRequest> _byId =
      LinkedHashMap<String, TablePickupRequest>();

  UnmodifiableListView<TablePickupRequest> get all {
    _gc();
    // Newest first so the banner / message screen shows the latest item.
    final list = _byId.values.toList()
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    return UnmodifiableListView(list);
  }

  /// Returns only requests where the local viewer can still act on them
  /// — neither claimed, nor cancelled, nor TTL-expired.
  List<TablePickupRequest> get pending =>
      all.where((r) => r.isPending).toList(growable: false);

  TablePickupRequest? byId(String requestId) => _byId[requestId];

  /// Store a new request we just sent or received off the wire. Ignores
  /// duplicates (same requestId) so repeated HELLO catch-up pushes or
  /// mDNS double-deliveries don't double-count.
  bool recordRequest(TablePickupRequest req) {
    if (_byId.containsKey(req.requestId)) return false;
    _byId[req.requestId] = req;
    _trim();
    _gc();
    notifyListeners();
    return true;
  }

  /// Mark a request as claimed with a deterministic conflict-resolution
  /// rule so every device converges on the same winner even when two
  /// waiters tap accept within the same few hundred ms.
  ///
  /// Rules, in order:
  ///   1. If the request was cancelled — terminal, incoming claim is
  ///      dropped and the request stays cancelled.
  ///   2. If no claim is stored yet — accept the incoming claim.
  ///   3. If a claim is already stored — the claim with the **earlier**
  ///      timestamp wins. Ties broken by waiter id alphabetically so
  ///      every peer picks the same winner.
  TablePickupRequest? markClaimed({
    required String requestId,
    required String waiterId,
    required String waiterName,
    DateTime? at,
  }) {
    final existing = _byId[requestId];
    if (existing == null) return null;
    if (existing.cancelled) return existing;

    final incomingAt = at ?? DateTime.now();
    final existingAt = existing.claimedAt;
    final existingId = existing.claimedByWaiterId;

    if (existingAt != null && existingId != null) {
      // Prefer the earlier timestamp; if timestamps match, tiebreak on
      // waiter id so every peer agrees. "Already same" bails out.
      if (existingId == waiterId) return existing;
      final cmp = existingAt.compareTo(incomingAt);
      if (cmp < 0) return existing; // existing is earlier — wins
      if (cmp == 0 && existingId.compareTo(waiterId) <= 0) return existing;
      // Otherwise the incoming claim is earlier / alphabetically wins;
      // fall through to override.
    }

    final updated = existing.copyWith(
      claimedByWaiterId: waiterId,
      claimedByWaiterName: waiterName,
      claimedAt: incomingAt,
    );
    _byId[requestId] = updated;
    notifyListeners();
    return updated;
  }

  TablePickupRequest? markCancelled(String requestId) {
    final existing = _byId[requestId];
    if (existing == null) return null;
    if (existing.cancelled) return existing;
    // If already claimed, we keep the claimed state (a cancellation
    // arriving after a successful claim is moot — the table is assigned).
    if (existing.isClaimed) return existing;
    final updated = existing.copyWith(cancelled: true);
    _byId[requestId] = updated;
    notifyListeners();
    return updated;
  }

  void clear() {
    if (_byId.isEmpty) return;
    _byId.clear();
    notifyListeners();
  }

  void _trim() {
    while (_byId.length > _capacity) {
      // LinkedHashMap preserves insertion order — drop the head.
      final oldestKey = _byId.keys.first;
      _byId.remove(oldestKey);
    }
  }

  void _gc() {
    final now = DateTime.now();
    final toRemove = <String>[];
    _byId.forEach((id, req) {
      if (req.isClaimed || req.cancelled) {
        final terminalAge = now.difference(req.claimedAt ?? req.requestedAt);
        if (terminalAge > terminalTtl) toRemove.add(id);
      } else {
        final age = now.difference(req.requestedAt);
        if (age > pendingTtl) toRemove.add(id);
      }
    });
    for (final id in toRemove) {
      _byId.remove(id);
    }
  }
}
