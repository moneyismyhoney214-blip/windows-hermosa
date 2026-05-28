import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/security/certificate_pinning.dart';

/// Minimal X509Certificate stand-in for hash-callback tests. We only
/// need the `der` accessor — everything else can throw if touched
/// because the production code never reads them.
class _StubCertificate implements X509Certificate {
  _StubCertificate(this.der);

  @override
  final Uint8List der;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used in tests');
}

void main() {
  setUp(() {
    // Each test starts with no pins configured and the
    // "seen-host-this-process" set drained.
    CertificatePinning.pinnedSha256Hashes.clear();
  });

  group('CertificatePinning.checkAccepted — pinning disabled', () {
    test('does not throw when no pins are configured', () {
      final cert = _StubCertificate(Uint8List.fromList([1, 2, 3, 4]));
      expect(
        () => CertificatePinning.checkAccepted(cert, 'api.example.com', 443),
        returnsNormally,
      );
    });
  });

  group('CertificatePinning.checkAccepted — pinning enabled', () {
    test('passes when the leaf cert hash is on the pin list', () {
      // sha256 of [1,2,3,4] is
      //   9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a
      const knownGoodHash =
          '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a';
      CertificatePinning.pinnedSha256Hashes['api.example.com'] = {
        knownGoodHash,
      };
      final cert = _StubCertificate(Uint8List.fromList([1, 2, 3, 4]));
      expect(
        () => CertificatePinning.checkAccepted(cert, 'api.example.com', 443),
        returnsNormally,
      );
    });

    test('detect-only mode logs but does not throw on mismatch', () {
      // Default build → CERT_PINNING_ENFORCE=false. A mismatch must
      // route through the logger / crash reporter but allow the
      // request to complete, so a stale pin can't brick the cashier
      // before ops gets a chance to ship a fix.
      CertificatePinning.pinnedSha256Hashes['api.example.com'] = {
        'an-unrelated-fingerprint-1234567890abcdef1234567890abcdef12345678',
      };
      final cert = _StubCertificate(Uint8List.fromList([1, 2, 3, 4]));
      expect(CertificatePinning.enforce, isFalse,
          reason: 'default builds must run detect-only');
      expect(
        () => CertificatePinning.checkAccepted(cert, 'api.example.com', 443),
        returnsNormally,
      );
    });

    // Enforce-mode behaviour (throws HandshakeException on mismatch)
    // is gated on the compile-time const `--dart-define=CERT_PINNING_ENFORCE=true`
    // and therefore can't be flipped at runtime from a unit test.
    // Enforce-mode coverage is exercised in integration_test/
    // hardened_build_test.dart instead, where the test binary is
    // compiled with the dart-define set.

    test('different host means different pin set', () {
      CertificatePinning.pinnedSha256Hashes['api.example.com'] = {
        'pin-for-api',
      };
      final cert = _StubCertificate(Uint8List.fromList([1, 2, 3, 4]));
      // Pinning is only enforced for the configured host. A handshake
      // to a different host whose pin list is empty falls back to the
      // OS trust store and is allowed through.
      expect(
        () => CertificatePinning.checkAccepted(cert, 'other.example.com', 443),
        returnsNormally,
      );
    });
  });

  group('CertificatePinning.onBadCertificate', () {
    test('always returns false (never overrides the bad-cert rejection)', () {
      final cert = _StubCertificate(Uint8List.fromList([1, 2, 3, 4]));
      expect(
        CertificatePinning.onBadCertificate(cert, 'api.example.com', 443),
        isFalse,
        reason: 'overriding a bad cert is the exact bug pinning prevents',
      );
    });
  });
}
