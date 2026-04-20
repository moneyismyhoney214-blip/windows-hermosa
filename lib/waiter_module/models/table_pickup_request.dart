import 'package:uuid/uuid.dart';

/// Uber-style pickup request: the cashier broadcasts one per tap on
/// "استلام", every waiter sees it, the first to accept claims the table,
/// and the remaining waiters see "[Name] استلم الطاولة" instead of an
/// accept button. Semantically distinct from a generic [WaiterMessage]
/// (no free-form text, hard-pinned to a single table, settles with
/// first-wins claim semantics), so it gets its own model.
class TablePickupRequest {
  final String requestId;
  final String cashierId;
  final String cashierName;
  final String tableId;
  final String tableNumber;
  final String? note;
  final DateTime requestedAt;

  // Mutable state — filled in by the pickup store as wire events arrive.
  final String? claimedByWaiterId;
  final String? claimedByWaiterName;
  final DateTime? claimedAt;
  final bool cancelled;

  TablePickupRequest({
    required this.cashierId,
    required this.cashierName,
    required this.tableId,
    required this.tableNumber,
    this.note,
    this.claimedByWaiterId,
    this.claimedByWaiterName,
    this.claimedAt,
    this.cancelled = false,
    String? requestId,
    DateTime? requestedAt,
  })  : requestId = requestId ?? const Uuid().v4(),
        requestedAt = requestedAt ?? DateTime.now();

  bool get isClaimed => claimedByWaiterId != null;
  bool get isPending => !isClaimed && !cancelled;

  TablePickupRequest copyWith({
    String? claimedByWaiterId,
    String? claimedByWaiterName,
    DateTime? claimedAt,
    bool? cancelled,
  }) =>
      TablePickupRequest(
        requestId: requestId,
        cashierId: cashierId,
        cashierName: cashierName,
        tableId: tableId,
        tableNumber: tableNumber,
        note: note,
        requestedAt: requestedAt,
        claimedByWaiterId: claimedByWaiterId ?? this.claimedByWaiterId,
        claimedByWaiterName: claimedByWaiterName ?? this.claimedByWaiterName,
        claimedAt: claimedAt ?? this.claimedAt,
        cancelled: cancelled ?? this.cancelled,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'request_id': requestId,
        'cashier_id': cashierId,
        'cashier_name': cashierName,
        'table_id': tableId,
        'table_number': tableNumber,
        if (note != null && note!.isNotEmpty) 'note': note,
        'requested_at': requestedAt.toIso8601String(),
        if (claimedByWaiterId != null) 'claimed_by_id': claimedByWaiterId,
        if (claimedByWaiterName != null)
          'claimed_by_name': claimedByWaiterName,
        if (claimedAt != null) 'claimed_at': claimedAt!.toIso8601String(),
        if (cancelled) 'cancelled': true,
      };

  factory TablePickupRequest.fromJson(Map<String, dynamic> j) =>
      TablePickupRequest(
        requestId: j['request_id']?.toString(),
        cashierId: j['cashier_id']?.toString() ?? '',
        cashierName: j['cashier_name']?.toString() ?? '',
        tableId: j['table_id']?.toString() ?? '',
        tableNumber: j['table_number']?.toString() ?? '',
        note: j['note']?.toString(),
        requestedAt:
            DateTime.tryParse(j['requested_at']?.toString() ?? ''),
        claimedByWaiterId: j['claimed_by_id']?.toString(),
        claimedByWaiterName: j['claimed_by_name']?.toString(),
        claimedAt:
            DateTime.tryParse(j['claimed_at']?.toString() ?? ''),
        cancelled: j['cancelled'] == true,
      );
}
