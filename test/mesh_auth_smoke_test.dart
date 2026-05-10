import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/waiter_module/models/network_message.dart';
import 'package:hermosa_pos/waiter_module/services/mesh_auth_service.dart';

void main() {
  group('MeshAuthService', () {
    test('signed message verifies on the same-key receiver', () {
      final sender = MeshAuthService();
      final receiver = MeshAuthService();
      sender.deriveKey(branchId: '42', sellerId: '81');
      receiver.deriveKey(branchId: '42', sellerId: '81');

      final msg = WireMessage(
        type: WireMessageType.tableUpdate,
        senderId: 'waiter-7',
        senderName: 'Ahmed',
        branchId: '42',
        data: {'table_id': '5', 'guests': 4, 'items': [{'name': 'X', 'qty': 2}]},
      );
      final wire = sender.signMessage(msg);

      expect(receiver.verifyRaw(wire), isTrue,
          reason: 'same-key signed messages must verify');
    });

    test('different-branch keys reject each other', () {
      final sender = MeshAuthService();
      final receiver = MeshAuthService();
      sender.deriveKey(branchId: '42', sellerId: '81');
      receiver.deriveKey(branchId: '99', sellerId: '81');

      final msg = WireMessage(
        type: WireMessageType.newOrder,
        senderId: 'a', senderName: 'A', branchId: '42',
      );
      final wire = sender.signMessage(msg);
      expect(receiver.verifyRaw(wire), isFalse,
          reason: 'cross-branch messages must be rejected');
    });

    test('hydrated receiver rejects unsigned (forged) messages', () {
      final receiver = MeshAuthService();
      receiver.deriveKey(branchId: '42', sellerId: '81');

      final unsigned = WireMessage(
        type: WireMessageType.tablePickupRequest,
        senderId: 'attacker', senderName: 'Eve', branchId: '42',
        data: {'table_id': '5'},
      ).encode();

      expect(receiver.verifyRaw(unsigned), isFalse,
          reason: 'unsigned message to a hydrated receiver must be rejected');
    });

    test('unhydrated receiver accepts everything (boot window)', () {
      final receiver = MeshAuthService();
      // No deriveKey — boot window
      final raw = WireMessage(
        type: WireMessageType.hello,
        senderId: 'a', senderName: 'A', branchId: '42',
      ).encode();
      expect(receiver.verifyRaw(raw), isTrue,
          reason: 'pre-login boot window must accept unsigned');
    });

    test('tampered message fails verification', () {
      final sender = MeshAuthService();
      final receiver = MeshAuthService();
      sender.deriveKey(branchId: '42', sellerId: '81');
      receiver.deriveKey(branchId: '42', sellerId: '81');

      final wire = sender.signMessage(WireMessage(
        type: WireMessageType.tablePaymentStatus,
        senderId: 'a', senderName: 'A', branchId: '42',
        data: {'table_id': '5', 'paid': true, 'total': 100.0},
      ));
      // Tamper: flip "paid" to false but keep the original mac
      final tampered = wire.replaceFirst('"paid":true', '"paid":false');
      expect(receiver.verifyRaw(tampered), isFalse,
          reason: 'tampered message body must invalidate the mac');
    });

    test('clear() forgets the key', () {
      final svc = MeshAuthService();
      svc.deriveKey(branchId: '42', sellerId: '81');
      expect(svc.isReady, isTrue);
      svc.clear();
      expect(svc.isReady, isFalse);
    });
  });
}
