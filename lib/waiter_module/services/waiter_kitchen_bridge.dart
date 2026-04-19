import 'package:flutter/foundation.dart' show debugPrint, Listenable;

import '../../services/display_app_service.dart';
import '../models/waiter.dart';

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
