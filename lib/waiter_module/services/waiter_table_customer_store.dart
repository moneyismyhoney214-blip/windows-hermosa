import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One customer pinned to a table on the waiter device.
@immutable
class TableCustomerLink {
  final String customerId;
  final String customerName;

  const TableCustomerLink({
    required this.customerId,
    required this.customerName,
  });

  Map<String, dynamic> toJson() => {
        'customerId': customerId,
        'customerName': customerName,
      };

  factory TableCustomerLink.fromJson(Map<String, dynamic> json) =>
      TableCustomerLink(
        customerId: json['customerId']?.toString() ?? '',
        customerName: (json['customerName'] as String?)?.trim() ?? '',
      );
}

/// Local (device-only) map of `tableId → customer`. Two write paths:
///   * a waitlisted party is *seated* on a table → auto-bind their customer;
///   * the waiter taps "link customer" on the order screen → manual bind.
///
/// Cleared for a table when it's paid / released so the next party starts
/// fresh. Kept here (not in [WaitlistService]) because a manually-linked
/// table has no waitlist row to hang the id off — and a waitlist seat is
/// already discoverable via `WaitlistService.customerIdForTable`, so this
/// store is purely the "extra" manual links plus a convenience mirror.
class WaiterTableCustomerStore extends ChangeNotifier {
  static const String _storageKey = 'waiter_table_customer_links_v1';

  final Map<String, TableCustomerLink> _links = {};
  bool _initialized = false;
  Future<void>? _initFuture;

  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initFuture ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (v is Map) {
              _links[k.toString()] = TableCustomerLink.fromJson(
                v.map((kk, vv) => MapEntry(kk.toString(), vv)),
              );
            }
          });
        }
      }
    } catch (e, st) {
      developer.log(
        'WaiterTableCustomerStore: failed to load — starting empty',
        error: e,
        stackTrace: st,
      );
      _links.clear();
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode(
        _links.map((k, v) => MapEntry(k, v.toJson())),
      );
      await prefs.setString(_storageKey, payload);
    } catch (e, st) {
      developer.log(
        'WaiterTableCustomerStore: persist failed — in-memory state kept',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// The customer pinned to [tableId], or null when none.
  TableCustomerLink? linkFor(String tableId) => _links[tableId];

  /// Pin [customerId]/[customerName] to [tableId]. No-op when the same
  /// link is already set.
  Future<void> bind({
    required String tableId,
    required String customerId,
    required String customerName,
  }) async {
    final existing = _links[tableId];
    if (existing != null &&
        existing.customerId == customerId &&
        existing.customerName == customerName.trim()) {
      return;
    }
    _links[tableId] = TableCustomerLink(
      customerId: customerId,
      customerName: customerName.trim(),
    );
    notifyListeners();
    await _persist();
  }

  /// Drop the pin for [tableId] (table paid / released / cleared).
  Future<void> clear(String tableId) async {
    if (_links.remove(tableId) == null) return;
    notifyListeners();
    await _persist();
  }

  /// Re-key the pin from [fromTableId] to [toTableId] — used when a seated
  /// party is migrated to a different table so the customer binding follows
  /// the order instead of being stranded on the now-free old table. No-op
  /// when the source has no pin. If the destination already had a pin it's
  /// overwritten (the migrate just made it occupied — it can't have a
  /// different party on it).
  Future<void> moveTable(String fromTableId, String toTableId) async {
    if (fromTableId == toTableId) return;
    final moved = _links.remove(fromTableId);
    if (moved == null) return;
    _links[toTableId] = moved;
    notifyListeners();
    await _persist();
  }
}
