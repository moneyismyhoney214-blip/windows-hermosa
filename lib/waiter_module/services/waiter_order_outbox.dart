import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../services/offline/connectivity_service.dart';
import '../models/waiter.dart';
import 'waiter_kitchen_bridge.dart';

/// Offline queue for orders the waiter could not push to the KDS because
/// the WebSocket was down. Flushes automatically when connectivity returns.
///
/// Stored as a single JSON array under `waiter_outbox` in SharedPreferences.
/// Small enough for realistic volumes (hundreds of pending orders max) and
/// avoids a new SQLite schema in the core offline DB.
///
/// Failure containment: every entry carries a `_retries` counter that's
/// bumped on each failed flush. Once an entry exceeds [_maxRetries] it's
/// dropped instead of cycled forever — otherwise a single permanently
/// broken order (e.g. a cartItem that references a deleted product) would
/// stall every subsequent reconnect.
class WaiterOrderOutbox {
  static const _kKey = 'waiter_outbox';
  static const int _maxRetries = 10;

  final WaiterKitchenBridge bridge;
  final ConnectivityService connectivity;

  late final VoidCallback _onlineHook = flushIfConnected;
  /// Fires whenever the KDS WebSocket in [WaiterKitchenBridge] flips
  /// state. A KDS reconnect *without* an internet transition needs to
  /// kick the flush too — otherwise queued orders sit there forever
  /// because `connectivity.onOnline` only fires on internet changes.
  late final VoidCallback _kdsHook = flushIfConnected;
  bool _flushing = false;
  bool _kdsListenerAttached = false;

  WaiterOrderOutbox({required this.bridge, required this.connectivity});

  Future<void> initialize() async {
    connectivity.onOnline(_onlineHook);
    try {
      bridge.connectionChanges.addListener(_kdsHook);
      _kdsListenerAttached = true;
    } catch (e) {
      debugPrint('⚠️ Outbox: could not attach to KDS connection: $e');
    }
    // Also try once at startup so queued orders don't wait on a toggle.
    Future.microtask(flushIfConnected);
  }

  Future<void> dispose() async {
    connectivity.removeOnOnline(_onlineHook);
    if (_kdsListenerAttached) {
      try {
        bridge.connectionChanges.removeListener(_kdsHook);
      } catch (_) {}
      _kdsListenerAttached = false;
    }
  }

  Future<int> pendingCount() async {
    final list = await _read();
    return list.length;
  }

  Future<void> enqueue({
    required String orderId,
    required String orderNumber,
    required String tableId,
    required String tableNumber,
    required String waiterId,
    required String waiterName,
    required List<Map<String, dynamic>> items,
    required double total,
    required String branchId,
    String? note,
  }) async {
    final list = await _read();
    list.add({
      'order_id': orderId,
      'order_number': orderNumber,
      'table_id': tableId,
      'table_number': tableNumber,
      'waiter_id': waiterId,
      'waiter_name': waiterName,
      'items': items,
      'total': total,
      'branch_id': branchId,
      if (note != null) 'note': note,
      'queued_at': DateTime.now().toIso8601String(),
      // Stable client-generated dedupe key. The KDS bridge can use this
      // to discard duplicate sends caused by a kill mid-flush (order
      // hit the wire, local SharedPreferences write didn't land → next
      // launch's flush would resend the same row). Same UUID across
      // every retry of the same entry.
      'idempotency_key': const Uuid().v4(),
    });
    await _write(list);
    if (!connectivity.isOffline) {
      unawaited(flushIfConnected());
    }
  }

  Future<void> flushIfConnected() async {
    if (_flushing) return;
    if (!bridge.isConnected) return;
    _flushing = true;
    try {
      final list = await _read();
      if (list.isEmpty) return;
      final remaining = <Map<String, dynamic>>[];
      var aborted = false;
      for (var i = 0; i < list.length; i++) {
        final entry = list[i];
        // Mid-flush guard: if the KDS socket dropped between iterations
        // we'd otherwise hammer every remaining entry with a guaranteed-
        // failure send, all of which would bump their retry counter for
        // nothing. Bail out and keep the rest of the queue intact for
        // the next reconnect — the connection-changes listener will
        // re-trigger flush.
        if (!bridge.isConnected) {
          aborted = true;
          remaining.addAll(list.sublist(i).cast<Map<String, dynamic>>());
          debugPrint(
              '⏸️ Outbox aborted mid-flush at $i/${list.length} — KDS dropped');
          break;
        }
        try {
          final waiter = Waiter(
            id: entry['waiter_id']?.toString() ?? '',
            name: entry['waiter_name']?.toString() ?? '',
            branchId: entry['branch_id']?.toString() ?? '',
          );
          await bridge.sendNewOrder(
            orderId: entry['order_id']?.toString() ?? '',
            orderNumber: entry['order_number']?.toString() ?? '',
            tableNumber: entry['table_number']?.toString() ?? '',
            items: (entry['items'] as List?)
                    ?.map((e) => Map<String, dynamic>.from(e as Map))
                    .toList() ??
                <Map<String, dynamic>>[],
            waiter: waiter,
            total: (entry['total'] as num?)?.toDouble(),
            note: entry['note']?.toString(),
          );
        } catch (e) {
          final retries =
              ((entry['_retries'] as num?)?.toInt() ?? 0) + 1;
          if (retries >= _maxRetries) {
            // Give up on this entry so it doesn't wedge future flushes.
            debugPrint(
                '🗑️ Dropping outbox entry ${entry['order_id']} after $retries retries: $e');
          } else {
            debugPrint(
                '⚠️ Outbox flush failed for ${entry['order_id']} (retry $retries/$_maxRetries): $e');
            remaining.add({...entry, '_retries': retries});
          }
        }
      }
      if (!aborted) {
        // Normal completion — `remaining` only holds the entries that
        // failed mid-iteration (their retry counter was bumped above).
      }
      await _write(remaining);
    } finally {
      _flushing = false;
    }
  }

  Future<List<Map<String, dynamic>>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  Future<void> _write(List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, jsonEncode(list));
  }
}
