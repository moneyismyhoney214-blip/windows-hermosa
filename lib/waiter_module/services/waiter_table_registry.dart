import 'package:flutter/foundation.dart';

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
        );
        break;
      case TableLifecycleKind.paymentPending:
        _byTableId[event.tableId] = (prev ?? _empty(event)).copyWith(
          paymentPending: true,
          paid: false,
          total: event.total,
          itemCount: event.itemCount,
          items: event.items,
        );
        break;
      case TableLifecycleKind.paid:
        _byTableId[event.tableId] = (prev ?? _empty(event)).copyWith(
          paymentPending: false,
          paid: true,
          total: event.total,
        );
        break;
    }
    notifyListeners();
  }

  _TableOwnership _empty(TableLifecycleEvent event) => _TableOwnership(
        waiterId: event.waiterId,
        waiterName: event.waiterName,
        tableNumber: event.tableNumber,
      );

  void clearForWaiter(String waiterId) {
    final removed =
        _byTableId.keys.where((k) => _byTableId[k]?.waiterId == waiterId).toList();
    for (final k in removed) {
      _byTableId.remove(k);
    }
    if (removed.isNotEmpty) notifyListeners();
  }

  /// Drop every ownership record. Used on branch switch / logout so the
  /// next session doesn't inherit the previous shift's table state.
  void clearAll() {
    if (_byTableId.isEmpty) return;
    _byTableId.clear();
    notifyListeners();
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

  const _TableOwnership({
    required this.waiterId,
    required this.waiterName,
    this.tableNumber = '',
    this.guestCount,
    this.total,
    this.itemCount,
    this.items = const [],
    this.paymentPending = false,
    this.paid = false,
  });

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
    );
  }
}

// Silences the unused import of Waiter — reserved for future getters that
// need the full Waiter object.
// ignore: unused_element
Type _waiterRef() => Waiter;
