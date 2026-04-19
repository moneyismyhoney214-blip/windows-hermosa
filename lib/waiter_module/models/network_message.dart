import 'dart:convert';
import 'package:uuid/uuid.dart';

/// All message types exchanged over the waiter LAN protocol.
///
/// Three rough groups:
///   1. Presence/roster — `waiter_*`
///   2. Table lifecycle (waiter → cashier viewers) — `table_*`
///   3. Kitchen routing (waiter → KDS/printer) — reuses the existing
///      cashier↔KDS schema from [DisplayAppService] so KDS needs no changes.
enum WireMessageType {
  // Handshake
  hello,
  helloAck,
  heartbeat,

  // Roster / presence
  waiterAnnounce,
  waiterStatus,
  waiterLeave,

  // Chat + call
  waiterCall,
  waiterMessage,
  /// Broadcast acknowledgement — the first waiter to accept a broadcast
  /// call emits this so the other waiters' notification lists flip from
  /// "pending" to "accepted by X".
  waiterCallAccepted,

  // Table lifecycle (waiter broadcasts → cashier listens)
  tableAssign,
  tableRelease,
  tableUpdate,
  tablePaymentStatus,

  // Kitchen routing — carry the same payload shape the cashier uses so
  // KDS can consume without changes.
  newOrder,
  updateCart,
  orderEdit,
  orderCancel,

  // Generic ack
  ack,
  error,
}

extension WireMessageTypeX on WireMessageType {
  String get wire {
    switch (this) {
      case WireMessageType.hello:
        return 'HELLO';
      case WireMessageType.helloAck:
        return 'HELLO_ACK';
      case WireMessageType.heartbeat:
        return 'HEARTBEAT';
      case WireMessageType.waiterAnnounce:
        return 'WAITER_ANNOUNCE';
      case WireMessageType.waiterStatus:
        return 'WAITER_STATUS';
      case WireMessageType.waiterLeave:
        return 'WAITER_LEAVE';
      case WireMessageType.waiterCall:
        return 'WAITER_CALL';
      case WireMessageType.waiterMessage:
        return 'WAITER_MESSAGE';
      case WireMessageType.waiterCallAccepted:
        return 'WAITER_CALL_ACCEPTED';
      case WireMessageType.tableAssign:
        return 'TABLE_ASSIGN';
      case WireMessageType.tableRelease:
        return 'TABLE_RELEASE';
      case WireMessageType.tableUpdate:
        return 'TABLE_UPDATE';
      case WireMessageType.tablePaymentStatus:
        return 'TABLE_PAYMENT_STATUS';
      case WireMessageType.newOrder:
        return 'NEW_ORDER';
      case WireMessageType.updateCart:
        return 'UPDATE_CART';
      case WireMessageType.orderEdit:
        return 'ORDER_EDIT';
      case WireMessageType.orderCancel:
        return 'ORDER_CANCEL';
      case WireMessageType.ack:
        return 'ACK';
      case WireMessageType.error:
        return 'ERROR';
    }
  }

  static WireMessageType? fromWire(String? s) {
    switch (s) {
      case 'HELLO':
        return WireMessageType.hello;
      case 'HELLO_ACK':
        return WireMessageType.helloAck;
      case 'HEARTBEAT':
        return WireMessageType.heartbeat;
      case 'WAITER_ANNOUNCE':
        return WireMessageType.waiterAnnounce;
      case 'WAITER_STATUS':
        return WireMessageType.waiterStatus;
      case 'WAITER_LEAVE':
        return WireMessageType.waiterLeave;
      case 'WAITER_CALL':
        return WireMessageType.waiterCall;
      case 'WAITER_MESSAGE':
        return WireMessageType.waiterMessage;
      case 'WAITER_CALL_ACCEPTED':
        return WireMessageType.waiterCallAccepted;
      case 'TABLE_ASSIGN':
        return WireMessageType.tableAssign;
      case 'TABLE_RELEASE':
        return WireMessageType.tableRelease;
      case 'TABLE_UPDATE':
        return WireMessageType.tableUpdate;
      case 'TABLE_PAYMENT_STATUS':
        return WireMessageType.tablePaymentStatus;
      case 'NEW_ORDER':
        return WireMessageType.newOrder;
      case 'UPDATE_CART':
        return WireMessageType.updateCart;
      case 'ORDER_EDIT':
        return WireMessageType.orderEdit;
      case 'ORDER_CANCEL':
        return WireMessageType.orderCancel;
      case 'ACK':
        return WireMessageType.ack;
      case 'ERROR':
        return WireMessageType.error;
      default:
        return null;
    }
  }
}

/// Protocol version — bump if the envelope structure changes.
const int kWireProtocolVersion = 1;

/// A single wire message on the waiter LAN protocol.
///
/// Envelope shape (JSON):
/// ```
/// {
///   "v": 1,
///   "type": "WAITER_CALL",
///   "id": "<uuid>",
///   "ts": 1713400000000,
///   "sender_id": "<waiter or device id>",
///   "sender_name": "Ahmed",
///   "branch_id": "123",
///   "data": { ... type-specific ... }
/// }
/// ```
class WireMessage {
  final WireMessageType type;
  final String id;
  final int ts;
  final String senderId;
  final String senderName;
  final String branchId;
  final Map<String, dynamic> data;

  WireMessage({
    required this.type,
    required this.senderId,
    required this.senderName,
    required this.branchId,
    Map<String, dynamic>? data,
    String? id,
    int? ts,
  })  : id = id ?? const Uuid().v4(),
        ts = ts ?? DateTime.now().millisecondsSinceEpoch,
        data = data ?? const {};

  Map<String, dynamic> toJson() => {
        'v': kWireProtocolVersion,
        'type': type.wire,
        'id': id,
        'ts': ts,
        'sender_id': senderId,
        'sender_name': senderName,
        'branch_id': branchId,
        'data': data,
      };

  String encode() => jsonEncode(toJson());

  static WireMessage? tryDecode(String raw) {
    try {
      final Map<String, dynamic> j = jsonDecode(raw) as Map<String, dynamic>;
      // Reject messages produced by a future protocol revision — better to
      // drop silently than to misinterpret fields (e.g. an envelope that
      // renamed or restructured `data`). Missing `v` is treated as v1 for
      // backward compat with earlier pre-versioned peers.
      final rawV = j['v'];
      final v = rawV is int ? rawV : int.tryParse(rawV?.toString() ?? '1');
      if (v != null && v > kWireProtocolVersion) return null;

      final t = WireMessageTypeX.fromWire(j['type']?.toString());
      if (t == null) return null;
      return WireMessage(
        type: t,
        id: j['id']?.toString(),
        ts: j['ts'] is int ? j['ts'] as int : null,
        senderId: j['sender_id']?.toString() ?? '',
        senderName: j['sender_name']?.toString() ?? '',
        branchId: j['branch_id']?.toString() ?? '',
        data: (j['data'] is Map<String, dynamic>)
            ? j['data'] as Map<String, dynamic>
            : const {},
      );
    } catch (_) {
      return null;
    }
  }
}
