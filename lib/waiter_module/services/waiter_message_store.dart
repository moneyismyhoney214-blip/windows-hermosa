import 'package:flutter/foundation.dart';

import '../models/waiter_message.dart';

/// In-memory feed of waiter notifications (broadcast calls + their
/// acceptance state). Replaces the old per-peer thread model — the new
/// UX is a single notifications list rather than 1-to-1 chats.
///
/// Newest items live at the end; UIs typically render in reverse. We cap
/// the total to avoid runaway memory during long shifts.
class WaiterMessageStore extends ChangeNotifier {
  static const int _maxItems = 200;

  final List<WaiterMessage> _items = [];

  /// All notifications, oldest first.
  List<WaiterMessage> get all => List.unmodifiable(_items);

  /// Count of unread notifications (tab badge). Accepted broadcasts are
  /// never "unread" for anyone but the recipient of the original call.
  int get unreadCount =>
      _items.where((m) => !m.read && !m.isAccepted).length;

  /// Total broadcasts still waiting for someone to accept.
  int get pendingCount =>
      _items.where((m) => m.isBroadcast && !m.isAccepted).length;

  /// Record a new incoming or outgoing notification. Duplicate ids
  /// (e.g. echo from peer) are merged so the list never shows the same
  /// message twice.
  void record({
    required WaiterMessage message,
    required bool incoming,
  }) {
    final existingIndex = _items.indexWhere((m) => m.id == message.id);
    if (existingIndex >= 0) {
      final existing = _items[existingIndex];
      // Preserve acceptance data from whichever copy already has it.
      _items[existingIndex] = existing.copyWith(
        acceptedByWaiterId: existing.acceptedByWaiterId ??
            message.acceptedByWaiterId,
        acceptedByWaiterName: existing.acceptedByWaiterName ??
            message.acceptedByWaiterName,
        acceptedAt: existing.acceptedAt ?? message.acceptedAt,
        read: existing.read || message.read,
      );
    } else {
      _items.add(incoming ? message : message.copyWith(read: true));
      if (_items.length > _maxItems) {
        _items.removeRange(0, _items.length - _maxItems);
      }
    }
    notifyListeners();
  }

  /// Mark [messageId] as accepted by [waiterId]/[waiterName].
  ///
  /// Conflict resolution mirrors the pickup store: the claim with the
  /// **earlier** [at] wins, ties broken by waiter id alphabetically — so
  /// every device converges on the same accepter even when two waiters tap
  /// "accept" within the same few hundred ms. Without this, A's device kept
  /// A, B's kept B, and passive devices latched onto whichever ACCEPTED
  /// arrived first → permanent disagreement on "تم الاستلام بواسطة X".
  void markAccepted({
    required String messageId,
    required String waiterId,
    required String waiterName,
    DateTime? at,
  }) {
    final i = _items.indexWhere((m) => m.id == messageId);
    if (i < 0) return;
    final existing = _items[i];
    final incomingAt = at ?? DateTime.now();
    final prevId = existing.acceptedByWaiterId;
    final prevAt = existing.acceptedAt;
    if (prevId != null && prevAt != null) {
      if (prevId == waiterId) return; // same claimant — idempotent
      final cmp = prevAt.compareTo(incomingAt);
      if (cmp < 0) return; // stored claim is earlier — it wins
      if (cmp == 0 && prevId.compareTo(waiterId) <= 0) return; // tie → lower id
      // else: the incoming claim is earlier (or ties with a lower id) — override.
    }
    _items[i] = existing.copyWith(
      acceptedByWaiterId: waiterId,
      acceptedByWaiterName: waiterName,
      acceptedAt: incomingAt,
    );
    notifyListeners();
  }

  /// Mark everything as read (called when the user opens the tab).
  void markAllRead() {
    var changed = false;
    for (var i = 0; i < _items.length; i++) {
      if (!_items[i].read) {
        _items[i] = _items[i].copyWith(read: true);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }
}
