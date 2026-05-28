import 'package:flutter/foundation.dart' show debugPrint, Listenable;

import '../../services/display_app_service.dart';
import '../models/waiter.dart';

/// How long to wait for the KDS to acknowledge a `NEW_ORDER` before treating
/// it as undelivered. "WebSocket connected" ≠ "order processed" — a frozen
/// KDS app can leave the socket up while dropping everything. Matches the
/// cashier's `_waitForKdsAck` window.
const Duration _kAckWait = Duration(seconds: 2);

/// An ORDER_ACK older than this is treated as stale (belongs to a previous
/// connection). Mirrors the cashier's freshness check.
const Duration _kAckFreshness = Duration(seconds: 8);

/// Thin wrapper over [DisplayAppService] that lets the waiter module send
/// orders to the KDS using the *exact same* message format the cashier uses.
///
/// Because the envelope is identical (`NEW_ORDER` / `UPDATE_CART` /
/// `ORDER_CANCEL`), the KDS does not need any changes — it just sees another
/// client on the socket.
class WaiterKitchenBridge {
  final DisplayAppService _display;

  WaiterKitchenBridge(this._display);

  bool get isConnected => _display.isConnected;

  /// Exposes the underlying [DisplayAppService] as a [Listenable] so the
  /// outbox (and anyone else that cares about KDS reachability) can
  /// retry pending work when the socket re-pairs — internet connectivity
  /// alone is not enough because the KDS WebSocket is a separate channel.
  Listenable get connectionChanges => _display;

  /// Send a new order to the KDS.
  ///
  /// [items] must already be in the on-wire shape the cashier uses:
  /// `[{ name, quantity, notes, price, extras: [...] }, ...]`.
  Future<void> sendNewOrder({
    required String orderId,
    required String orderNumber,
    required String tableNumber,
    required List<Map<String, dynamic>> items,
    required Waiter waiter,
    double? total,
    String? note,
    Map<String, dynamic>? invoice,
  }) async {
    final combinedNote = _buildNote(note, tableNumber, waiter);
    try {
      _display.sendOrderToKitchen(
        orderId: orderId,
        orderNumber: orderNumber,
        orderType: 'dine_in',
        items: items,
        note: combinedNote,
        total: total,
        invoice: invoice,
      );
    } catch (e) {
      debugPrint('⚠️ Waiter → KDS NEW_ORDER failed: $e');
      rethrow;
    }
  }

  /// Poll [DisplayAppService] for an `ORDER_ACK` matching [orderId]. Returns
  /// `true` if a fresh ack lands before [timeout]. Callers should fall back to
  /// the offline outbox on `false` — the order may have been dropped by a
  /// frozen/laggy KDS even though the socket was up. Mirrors the cashier's
  /// `_waitForKdsAck` (main_screen.payment.dart).
  Future<bool> awaitOrderAck(
    String orderId, {
    Duration timeout = _kAckWait,
  }) async {
    final target = orderId.trim();
    if (target.isEmpty) return false;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final ackId = _display.lastOrderAckId?.trim();
      final ackAt = _display.lastOrderAckAt;
      if (ackId == target &&
          ackAt != null &&
          DateTime.now().difference(ackAt) <= _kAckFreshness) {
        return true;
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }
    return false;
  }

  /// Push a live cart preview (used while the waiter is still editing).
  /// Equivalent to the cashier's `UPDATE_CART` — the KDS can show it as
  /// "in progress" but won't mark it as prepared.
  void updateCart({
    required String tableNumber,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double tax,
    required double total,
    required Waiter waiter,
  }) {
    _display.updateCartDisplay(
      items: items,
      subtotal: subtotal,
      tax: tax,
      total: total,
      orderNumber: 'T-$tableNumber',
      orderType: 'dine_in',
      note: 'Waiter: ${waiter.name}',
    );
  }

  String _buildNote(String? userNote, String tableNumber, Waiter waiter) {
    final parts = <String>[
      'Table $tableNumber',
      'Waiter: ${waiter.name}',
      if (userNote != null && userNote.trim().isNotEmpty) userNote.trim(),
    ];
    return parts.join(' • ');
  }
}
