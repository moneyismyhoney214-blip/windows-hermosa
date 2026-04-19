import 'package:flutter/foundation.dart';

import '../../models.dart';

/// Per-table carts living only on the waiter device.
///
/// Tracks two lists per table:
///   * `_carts[tableId]` — the current draft (not yet sent to the kitchen)
///   * `_sent[tableId]`  — everything already sent in previous rounds, kept so
///                        the waiter and the cashier can see the full history
///                        of the table without re-querying the backend.
///
/// Guests are also persisted per-table so "number of people" survives when
/// the waiter reopens the screen.
class WaiterCartStore extends ChangeNotifier {
  final Map<String, List<CartItem>> _carts = {};
  final Map<String, List<CartItem>> _sent = {};
  final Map<String, int> _guestCounts = {};

  List<CartItem> itemsFor(String tableId) =>
      List.unmodifiable(_carts[tableId] ?? const <CartItem>[]);

  List<CartItem> sentItemsFor(String tableId) =>
      List.unmodifiable(_sent[tableId] ?? const <CartItem>[]);

  /// Union of sent + current draft — useful for billing / cashier display.
  List<CartItem> allItemsFor(String tableId) {
    final out = <CartItem>[];
    out.addAll(_sent[tableId] ?? const []);
    out.addAll(_carts[tableId] ?? const []);
    return List.unmodifiable(out);
  }

  int? guestsFor(String tableId) => _guestCounts[tableId];

  bool hasItems(String tableId) =>
      (_carts[tableId]?.isNotEmpty ?? false);

  bool hasSentItems(String tableId) =>
      (_sent[tableId]?.isNotEmpty ?? false);

  void setGuests(String tableId, int count) {
    _guestCounts[tableId] = count;
    notifyListeners();
  }

  void addItem(String tableId, CartItem item) {
    _carts.putIfAbsent(tableId, () => <CartItem>[]).add(item);
    notifyListeners();
  }

  void updateItem(String tableId, int index, CartItem newItem) {
    final list = _carts[tableId];
    if (list == null || index < 0 || index >= list.length) return;
    list[index] = newItem;
    notifyListeners();
  }

  void removeItem(String tableId, int index) {
    final list = _carts[tableId];
    if (list == null || index < 0 || index >= list.length) return;
    list.removeAt(index);
    if (list.isEmpty) _carts.remove(tableId);
    notifyListeners();
  }

  /// Promote the current draft to "sent" — called after successfully
  /// handing the order off to the kitchen.
  void markDraftAsSent(String tableId) {
    final draft = _carts[tableId];
    if (draft == null || draft.isEmpty) return;
    _sent.putIfAbsent(tableId, () => <CartItem>[]).addAll(draft);
    _carts.remove(tableId);
    notifyListeners();
  }

  void clearTable(String tableId) {
    final removed = _carts.remove(tableId) != null;
    final removedSent = _sent.remove(tableId) != null;
    final removedGuests = _guestCounts.remove(tableId) != null;
    if (removed || removedSent || removedGuests) notifyListeners();
  }

  double draftSubtotalFor(String tableId) =>
      itemsFor(tableId).fold<double>(0, (s, i) => s + i.totalPrice);

  double sentSubtotalFor(String tableId) =>
      sentItemsFor(tableId).fold<double>(0, (s, i) => s + i.totalPrice);

  double subtotalFor(String tableId) =>
      draftSubtotalFor(tableId) + sentSubtotalFor(tableId);

  int itemCountFor(String tableId) =>
      allItemsFor(tableId).fold<int>(0, (s, i) => s + i.quantity.ceil());
}
