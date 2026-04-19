/// Table-lifecycle events that the waiter broadcasts so the cashier (and
/// other waiters) can mirror table state without owning it.
///
/// The waiter is the sole authoritative controller — the cashier is a viewer.
enum TableLifecycleKind {
  assigned,   // A waiter took the table (status → occupied)
  released,   // Table cleared / order closed (status → available)
  updated,    // Order edited mid-service
  paymentPending, // Guests will pay later
  paid,       // Payment received (cashier may also update; see PAY flow)
}

extension TableLifecycleKindX on TableLifecycleKind {
  String get wire {
    switch (this) {
      case TableLifecycleKind.assigned:
        return 'assigned';
      case TableLifecycleKind.released:
        return 'released';
      case TableLifecycleKind.updated:
        return 'updated';
      case TableLifecycleKind.paymentPending:
        return 'payment_pending';
      case TableLifecycleKind.paid:
        return 'paid';
    }
  }

  static TableLifecycleKind? fromWire(String? s) {
    switch (s) {
      case 'assigned':
        return TableLifecycleKind.assigned;
      case 'released':
        return TableLifecycleKind.released;
      case 'updated':
        return TableLifecycleKind.updated;
      case 'payment_pending':
        return TableLifecycleKind.paymentPending;
      case 'paid':
        return TableLifecycleKind.paid;
    }
    return null;
  }
}

/// Compact per-item snapshot broadcast with [TableLifecycleEvent] so the
/// cashier's "Details" dialog can show exactly what the table ordered
/// without having to query the backend.
class TableItemSnapshot {
  final String name;
  final double quantity;
  final double unitPrice;
  final String? note;
  final String? mealId;
  final String? categoryId;

  TableItemSnapshot({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    this.note,
    this.mealId,
    this.categoryId,
  });

  double get lineTotal => quantity * unitPrice;

  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'unit_price': unitPrice,
        if (note != null && note!.isNotEmpty) 'note': note,
        if (mealId != null) 'meal_id': mealId,
        if (categoryId != null) 'category_id': categoryId,
      };

  factory TableItemSnapshot.fromJson(Map<String, dynamic> j) =>
      TableItemSnapshot(
        name: j['name']?.toString() ?? '',
        quantity: (j['quantity'] is num)
            ? (j['quantity'] as num).toDouble()
            : double.tryParse(j['quantity']?.toString() ?? '') ?? 1.0,
        unitPrice: (j['unit_price'] is num)
            ? (j['unit_price'] as num).toDouble()
            : double.tryParse(j['unit_price']?.toString() ?? '') ?? 0.0,
        note: j['note']?.toString(),
        mealId: j['meal_id']?.toString(),
        categoryId: j['category_id']?.toString(),
      );
}

class TableLifecycleEvent {
  final TableLifecycleKind kind;
  final String tableId;
  final String tableNumber;
  final String waiterId;
  final String waiterName;
  final int? guestCount;
  final double? total;
  final int? itemCount;
  final String? orderId;
  final String? note;
  final List<TableItemSnapshot>? items;

  TableLifecycleEvent({
    required this.kind,
    required this.tableId,
    required this.tableNumber,
    required this.waiterId,
    required this.waiterName,
    this.guestCount,
    this.total,
    this.itemCount,
    this.orderId,
    this.note,
    this.items,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind.wire,
        'table_id': tableId,
        'table_number': tableNumber,
        'waiter_id': waiterId,
        'waiter_name': waiterName,
        if (guestCount != null) 'guest_count': guestCount,
        if (total != null) 'total': total,
        if (itemCount != null) 'item_count': itemCount,
        if (orderId != null) 'order_id': orderId,
        if (note != null) 'note': note,
        if (items != null)
          'items': items!.map((e) => e.toJson()).toList(growable: false),
      };

  factory TableLifecycleEvent.fromJson(Map<String, dynamic> json) =>
      TableLifecycleEvent(
        kind: TableLifecycleKindX.fromWire(json['kind']?.toString()) ??
            TableLifecycleKind.updated,
        tableId: json['table_id']?.toString() ?? '',
        tableNumber: json['table_number']?.toString() ?? '',
        waiterId: json['waiter_id']?.toString() ?? '',
        waiterName: json['waiter_name']?.toString() ?? '',
        guestCount: (json['guest_count'] is num)
            ? (json['guest_count'] as num).toInt()
            : int.tryParse(json['guest_count']?.toString() ?? ''),
        total: (json['total'] is num)
            ? (json['total'] as num).toDouble()
            : double.tryParse(json['total']?.toString() ?? ''),
        itemCount: (json['item_count'] is num)
            ? (json['item_count'] as num).toInt()
            : int.tryParse(json['item_count']?.toString() ?? ''),
        orderId: json['order_id']?.toString(),
        note: json['note']?.toString(),
        items: (json['items'] is List)
            ? (json['items'] as List)
                .whereType<Map>()
                .map((e) => TableItemSnapshot.fromJson(
                    e.map((k, v) => MapEntry(k.toString(), v))))
                .toList()
            : null,
      );
}
