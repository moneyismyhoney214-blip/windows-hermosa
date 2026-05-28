import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/waiter_module/models/network_message.dart';
import 'package:hermosa_pos/waiter_module/services/mesh_auth_service.dart';

/// Tests for [MeshAuthService] — application-layer auth on the waiter
/// LAN mesh. The HMAC is derived from a per-branch+seller scope plus a
/// build-time pepper; getting any of that wrong silently drops every
/// signed message from peers and looks like "the mesh is dead".
///
/// The pepper is `--dart-define`-injected. In test (no env var) it
/// falls back to a known dev value, which is fine for verifying that
/// signed messages round-trip — production builds get a real value
/// stamped in by Codemagic.
void main() {
  WireMessage makeMessage() {
    // The auth tests don't care about message semantics — they only
    // care that the same bytes hash the same way on both sides. Pin
    // every field so toJson() is deterministic across signing peers.
    return WireMessage(
      type: WireMessageType.heartbeat,
      senderId: 'unit-test',
      senderName: 'Unit Test',
      branchId: '5',
      id: 'test-1',
      ts: DateTime.utc(2026, 5, 19).millisecondsSinceEpoch,
      data: const {'hello': 'world'},
    );
  }

  group('deriveKey + isReady', () {
    test('isReady starts false; flips true after deriveKey', () {
      final svc = MeshAuthService();
      expect(svc.isReady, isFalse);

      svc.deriveKey(branchId: '7', sellerId: '1');
      expect(svc.isReady, isTrue);
    });

    test('clear() drops the key and isReady reverts to false', () {
      final svc = MeshAuthService();
      svc.deriveKey(branchId: '7', sellerId: '1');
      svc.clear();
      expect(svc.isReady, isFalse);
    });

    test('re-deriving the same scope is idempotent', () {
      final svc = MeshAuthService();
      svc.deriveKey(branchId: '7', sellerId: '1');
      // Sign a message, then re-derive the same scope — signature for
      // identical input must remain identical, proving the key didn't
      // rotate underneath us.
      final msg = makeMessage();
      final first = svc.signMessage(msg);
      svc.deriveKey(branchId: '7', sellerId: '1');
      final second = svc.signMessage(msg);
      expect(first, second);
    });
  });

  group('signMessage', () {
    test('attaches a mac field once a key is derived', () {
      final svc = MeshAuthService();
      svc.deriveKey(branchId: '7', sellerId: '1');
      final raw = svc.signMessage(makeMessage());
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['mac'], isA<String>());
      // SHA-256 hex is 64 chars.
      expect((decoded['mac'] as String).length, 64);
    });

    test('emits unsigned envelope when no key has been derived '
        '(pre-hydrate boot window)', () {
      final svc = MeshAuthService();
      final raw = svc.signMessage(makeMessage());
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded.containsKey('mac'), isFalse);
    });
  });

  group('verifyRaw', () {
    test('accepts anything in the pre-hydrate boot window', () {
      final svc = MeshAuthService();
      expect(svc.verifyRaw('{"anything": true}'), isTrue,
          reason: 'pre-hydrate must accept so login can complete');
    });

    test('round-trips a signed message after both sides derive the same scope',
        () {
      final sender = MeshAuthService();
      final receiver = MeshAuthService();
      sender.deriveKey(branchId: '5', sellerId: '2');
      receiver.deriveKey(branchId: '5', sellerId: '2');

      final wire = sender.signMessage(makeMessage());
      expect(receiver.verifyRaw(wire), isTrue);
    });

    test('rejects messages from a peer on a different branch', () {
      final sender = MeshAuthService();
      final receiver = MeshAuthService();
      sender.deriveKey(branchId: '5', sellerId: '2');
      receiver.deriveKey(branchId: '99', sellerId: '2');

      final wire = sender.signMessage(makeMessage());
      expect(receiver.verifyRaw(wire), isFalse,
          reason: 'cross-branch replay protection is the whole point');
    });

    test('rejects messages from a peer on a different seller', () {
      final sender = MeshAuthService();
      final receiver = MeshAuthService();
      sender.deriveKey(branchId: '5', sellerId: '2');
      receiver.deriveKey(branchId: '5', sellerId: '99');

      final wire = sender.signMessage(makeMessage());
      expect(receiver.verifyRaw(wire), isFalse);
    });

    test('rejects unsigned messages once key is set', () {
      final svc = MeshAuthService();
      svc.deriveKey(branchId: '5', sellerId: '2');
      // No mac field — once we've hydrated, anything unsigned is hostile.
      expect(svc.verifyRaw('{"some": "payload"}'), isFalse);
    });

    test('rejects messages with a tampered body', () {
      final sender = MeshAuthService();
      final receiver = MeshAuthService();
      sender.deriveKey(branchId: '5', sellerId: '2');
      receiver.deriveKey(branchId: '5', sellerId: '2');

      final wire = sender.signMessage(makeMessage());
      // Flip a byte in the canonical body to invalidate the MAC.
      final tampered = wire.replaceFirst('"hello":"world"',
          '"hello":"WORLD"');
      expect(receiver.verifyRaw(tampered), isFalse);
    });

    test('rejects malformed JSON gracefully (returns false, never throws)',
        () {
      final svc = MeshAuthService();
      svc.deriveKey(branchId: '5', sellerId: '2');
      expect(svc.verifyRaw('not json'), isFalse);
      expect(svc.verifyRaw('"a string, not an object"'), isFalse);
      expect(svc.verifyRaw(''), isFalse);
    });
  });
}
