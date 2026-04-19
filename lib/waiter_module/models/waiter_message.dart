import 'package:uuid/uuid.dart';

/// Sentinel for broadcast requests — any waiter on the LAN may claim a
/// message addressed to this id. Sent by the cashier (or by a waiter
/// asking for help) when they don't want to pin the call to one person.
const String kBroadcastWaiterId = '*';

/// A call / notification exchanged on the waiter LAN.
///
/// A message with `toWaiterId == kBroadcastWaiterId` is a **broadcast**:
/// every waiter sees it, the first to tap "accept" claims it, and the
/// rest watch the acceptance state roll in.
///
/// Direct 1-to-1 messages keep the old semantics (used by the call-bell
/// flow when the cashier wants a specific waiter).
class WaiterMessage {
  final String id;
  final String fromWaiterId;
  final String fromWaiterName;
  final String toWaiterId;
  final String? toWaiterName;
  final String? tableId;
  final String? tableNumber;
  final String text;
  final bool isCall;
  final DateTime sentAt;
  final bool read;

  /// Set when a waiter claims a broadcast. Null while the broadcast is
  /// still pending. `acceptedByWaiterName` is populated for the UI to
  /// show "قبله {name}" without another roster lookup.
  final String? acceptedByWaiterId;
  final String? acceptedByWaiterName;
  final DateTime? acceptedAt;

  WaiterMessage({
    required this.fromWaiterId,
    required this.fromWaiterName,
    required this.toWaiterId,
    required this.text,
    this.toWaiterName,
    this.tableId,
    this.tableNumber,
    this.isCall = false,
    this.read = false,
    this.acceptedByWaiterId,
    this.acceptedByWaiterName,
    this.acceptedAt,
    String? id,
    DateTime? sentAt,
  })  : id = id ?? const Uuid().v4(),
        sentAt = sentAt ?? DateTime.now();

  bool get isBroadcast => toWaiterId == kBroadcastWaiterId;
  bool get isAccepted => acceptedByWaiterId != null;

  WaiterMessage copyWith({
    bool? read,
    String? acceptedByWaiterId,
    String? acceptedByWaiterName,
    DateTime? acceptedAt,
  }) =>
      WaiterMessage(
        id: id,
        fromWaiterId: fromWaiterId,
        fromWaiterName: fromWaiterName,
        toWaiterId: toWaiterId,
        toWaiterName: toWaiterName,
        tableId: tableId,
        tableNumber: tableNumber,
        text: text,
        isCall: isCall,
        sentAt: sentAt,
        read: read ?? this.read,
        acceptedByWaiterId: acceptedByWaiterId ?? this.acceptedByWaiterId,
        acceptedByWaiterName: acceptedByWaiterName ?? this.acceptedByWaiterName,
        acceptedAt: acceptedAt ?? this.acceptedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'from_waiter_id': fromWaiterId,
        'from_waiter_name': fromWaiterName,
        'to_waiter_id': toWaiterId,
        if (toWaiterName != null) 'to_waiter_name': toWaiterName,
        if (tableId != null) 'table_id': tableId,
        if (tableNumber != null) 'table_number': tableNumber,
        'text': text,
        'is_call': isCall,
        'sent_at': sentAt.toIso8601String(),
        'read': read,
        if (acceptedByWaiterId != null) 'accepted_by_id': acceptedByWaiterId,
        if (acceptedByWaiterName != null)
          'accepted_by_name': acceptedByWaiterName,
        if (acceptedAt != null) 'accepted_at': acceptedAt!.toIso8601String(),
      };

  factory WaiterMessage.fromJson(Map<String, dynamic> json) => WaiterMessage(
        id: json['id']?.toString(),
        fromWaiterId: json['from_waiter_id']?.toString() ?? '',
        fromWaiterName: json['from_waiter_name']?.toString() ?? '',
        toWaiterId: json['to_waiter_id']?.toString() ?? '',
        toWaiterName: json['to_waiter_name']?.toString(),
        tableId: json['table_id']?.toString(),
        tableNumber: json['table_number']?.toString(),
        text: json['text']?.toString() ?? '',
        isCall: json['is_call'] == true,
        read: json['read'] == true,
        sentAt: DateTime.tryParse(json['sent_at']?.toString() ?? ''),
        acceptedByWaiterId: json['accepted_by_id']?.toString(),
        acceptedByWaiterName: json['accepted_by_name']?.toString(),
        acceptedAt:
            DateTime.tryParse(json['accepted_at']?.toString() ?? ''),
      );
}
