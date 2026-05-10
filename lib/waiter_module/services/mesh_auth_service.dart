import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/network_message.dart';

/// Application-layer authentication on the waiter LAN mesh.
///
/// Defense-in-depth on top of the plain WebSocket transport: every
/// outgoing [WireMessage] carries an HMAC-SHA256 over its envelope,
/// keyed by a per-branch shared secret derived from `branchId +
/// sellerId`. Receivers reject any message whose MAC fails so a
/// rogue device on the same WiFi can't inject forged orders,
/// pickup-claims, or table-payment events.
///
/// Threat model — what this DOES protect against:
///   * Random LAN guest forging messages without the app source
///   * Man-in-the-middle injection on the same network
///   * Cross-branch replay (key includes branchId + sellerId)
///
/// What this does NOT protect against:
///   * Attacker with the APK (the application pepper is compile-time)
///   * Replay of the same message inside the dedup window
///   * A compromised legitimate waiter device
///
/// For full E2E confidentiality and authenticity, layer `wss://` on
/// top — but that needs certificate management on private LAN IPs and
/// isn't viable on Sunmi devices without a provisioning pipeline.
class MeshAuthService {
  /// Hardcoded application pepper. Decompiling the APK reveals this;
  /// it raises the bar against opportunistic LAN attackers, not against
  /// a determined adversary with the binary. Bumped on protocol
  /// changes so older builds don't accidentally talk to newer ones
  /// after a key-derivation tweak.
  static const String _pepper =
      'hermosa-mesh-v1-7c5e1f2a8b3d4e6f9a0b1c2d3e4f5a6b';

  Uint8List? _key;
  String? _scope;

  /// Derive (or rotate) the per-branch shared key. Both the cashier
  /// and the waiters call this with the same `branchId + sellerId`,
  /// so they end up with identical keys without ever transmitting
  /// the secret. Idempotent — re-deriving the same scope is a no-op.
  void deriveKey({required String branchId, required String sellerId}) {
    final scope = '$branchId:$sellerId';
    if (scope == _scope && _key != null) return;
    final hmac = Hmac(sha256, utf8.encode(_pepper));
    _key = Uint8List.fromList(
        hmac.convert(utf8.encode('mesh:$scope')).bytes);
    _scope = scope;
    debugPrint('🔐 MeshAuth key derived for branch=$branchId seller=$sellerId');
  }

  /// Drop the key on logout / branch switch so a different user (or
  /// the same user on a different branch) doesn't inherit the
  /// previous shift's MAC capability.
  void clear() {
    _key = null;
    _scope = null;
    debugPrint('🔐 MeshAuth key cleared');
  }

  /// True after [deriveKey] has run. Used by sender/receiver to know
  /// whether to demand signatures or accept unsigned during the boot
  /// window before login completes.
  bool get isReady => _key != null;

  /// Sign a [WireMessage] and return its wire-encoded JSON. The MAC
  /// is appended as a top-level `mac` field so older receivers (or
  /// receivers that haven't hydrated their key yet) can still parse
  /// the message — they'll just skip verification.
  ///
  /// Falls back to unsigned encoding if no key has been derived
  /// (typical during the first few hundred milliseconds of startup,
  /// before login completes). Receivers in the same boot window
  /// also skip verification, so a freshly-launched mesh stays
  /// functional. Once both sides hydrate, every subsequent message
  /// is signed AND verified.
  String signMessage(WireMessage msg) {
    final body = msg.toJson();
    final canonical = jsonEncode(body);
    final key = _key;
    if (key == null) {
      // Pre-hydrate boot window — emit the canonical envelope as-is.
      return canonical;
    }
    final mac =
        Hmac(sha256, key).convert(utf8.encode(canonical)).toString();
    body['mac'] = mac;
    return jsonEncode(body);
  }

  /// Verify a raw incoming JSON string. Returns:
  ///   * `true` if the MAC checks out
  ///   * `true` if no key has been derived yet (pre-hydrate boot
  ///     window — accept everything so the mesh isn't dead before
  ///     login completes)
  ///   * `false` only when a key IS set AND the MAC is missing or
  ///     invalid
  ///
  /// The compare is constant-time to prevent timing oracles.
  bool verifyRaw(String raw) {
    final key = _key;
    if (key == null) {
      // Pre-hydrate: accept everything. Once login completes the
      // window closes; subsequent peers must sign or be dropped.
      return true;
    }
    Map<String, dynamic> parsed;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return false;
      parsed = decoded;
    } catch (_) {
      return false;
    }
    final receivedMac = parsed['mac']?.toString();
    if (receivedMac == null || receivedMac.isEmpty) {
      // Sender claims to be on a peer that hasn't hydrated — reject.
      // We're hydrated, so anything we accept must be signed.
      return false;
    }
    // Reconstruct the canonical body the sender signed by removing
    // the `mac` field. Dart maps preserve insertion order so the
    // re-encoded JSON matches the bytes the sender hashed, provided
    // both sides used the same WireMessage.toJson() ordering.
    final body = Map<String, dynamic>.from(parsed)..remove('mac');
    final canonical = jsonEncode(body);
    final expected =
        Hmac(sha256, key).convert(utf8.encode(canonical)).toString();
    return _constantTimeEquals(expected, receivedMac);
  }

  /// XOR-accumulator compare so a timing side-channel can't reveal
  /// how many leading bytes of the MAC were guessed correctly. Both
  /// sides are SHA-256 hex (64 chars), so length is fixed in
  /// practice — but the length check stays as a defense against
  /// truncated or malformed input.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
