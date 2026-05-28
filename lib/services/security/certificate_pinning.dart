import 'dart:io';

import 'package:crypto/crypto.dart';

import '../logger_service.dart';

/// TLS-pinning hook for `dart:io` HttpClient and `package:http` IOClient.
///
/// **Operating modes**
///
/// 1. **Disabled** — `pinnedSha256Hashes` is empty for a host. We just
///    log the first cert we see so devs can capture a fingerprint to
///    paste back into [pinnedSha256Hashes]. This was the only mode the
///    framework supported before; pins were dead config that never
///    actually checked anything because `checkAccepted` had no caller.
/// 2. **Detect-only** (default when pins ARE configured) — every TLS
///    handshake's leaf cert is hashed and compared against the pin
///    set. Mismatches are logged at error level and surfaced via the
///    crash reporter, but the request is allowed through. Lets ops
///    deploy pins gradually without bricking devices if the pin is
///    stale or wrong.
/// 3. **Enforce** — set `--dart-define=CERT_PINNING_ENFORCE=true` at
///    build time. Mismatches throw `HandshakeException` and the
///    request fails closed. Use this for hardened production builds
///    after at least one release in detect-only mode has confirmed
///    the pins are accurate across your fleet.
///
/// **Wiring** — [PinningHttpClient] (in `pinning_http_client.dart`)
/// wraps `package:http`'s IOClient and calls [checkAccepted] on every
/// response. [BaseClient._initClient] installs that wrapper, so every
/// API call routes through the pinning check without per-call changes.
///
/// **Let's Encrypt caveat** — `portal.hermosaapp.com` is served with
/// an LE cert that rotates every ~90 days. Pinning the LEAF SHA-256
/// means the pin goes stale at each renewal. We populate the current
/// leaf below for visibility, but the *durable* pin is the certificate
/// presented by your origin behind LE. If the server isn't behind a
/// long-lived cert, prefer detect-only mode and refresh the leaf pin
/// in a CI step before each release (see `scripts/refresh-cert-pins.sh`).
class CertificatePinning {
  CertificatePinning._();

  /// Master kill-switch from build-time env. Set
  /// `--dart-define=CERT_PINNING_ENFORCE=true` for hardened builds.
  /// Anything else (default included) keeps detect-only behaviour.
  static const bool _enforce = bool.fromEnvironment(
    'CERT_PINNING_ENFORCE',
    defaultValue: false,
  );

  /// Map of `host → set of accepted leaf-cert SHA-256 hashes`.
  ///
  /// Format: lowercase hex, no separators, 64 chars (output of
  /// `openssl x509 -in cert.pem -outform DER | sha256sum`).
  ///
  /// Captured 2026-05-19. Refresh before each release — LE rotates.
  static final Map<String, Set<String>> pinnedSha256Hashes = <String, Set<String>>{
    'portal.hermosaapp.com': <String>{
      // Current production leaf (LE R12, expires ~90 days from 2026-05-19).
      // The same cert covers `api.hermosaapp.com` as a SAN, so direct
      // calls there (if any) keep validating too — but the active host is
      // portal, hence the single map entry.
      '6c4182c67054c0764c50f68342ac1fd9b591bbe61bbbbc27dbe43ed9d7e13380',
    },
  };

  /// True iff pinning is enabled at runtime (i.e. the build was
  /// compiled with `--dart-define=CERT_PINNING_ENFORCE=true`). When
  /// false, mismatches are logged but never throw.
  static bool get enforce => _enforce;

  /// Hosts we've already logged a fingerprint for, so we only echo
  /// each host's hash once per process. Pure diagnostic.
  static final Set<String> _firstSeenLogged = <String>{};

  /// `HttpClient.badCertificateCallback` returns `false` to keep the
  /// default rejection in place — we never override system trust.
  /// Logs the rejected fingerprint so devs can diagnose pin failures
  /// vs. genuine MITM attempts.
  static bool onBadCertificate(X509Certificate cert, String host, int port) {
    final fingerprint = _sha256Hex(cert.der);
    Log.w(
      'cert-pin',
      'bad cert for $host:$port (sha256/$fingerprint) — refusing handshake',
    );
    return false;
  }

  /// Inspect an accepted handshake's leaf certificate against the pin
  /// list. Behaviour depends on [enforce] and whether pins are set
  /// for the host (see class docstring).
  ///
  /// Called by [PinningHttpClient.send] after each response so every
  /// HTTPS call routes through here automatically.
  static void checkAccepted(X509Certificate cert, String host, int port) {
    final fingerprint = _sha256Hex(cert.der);
    final pins = pinnedSha256Hashes[host];

    if (pins == null || pins.isEmpty) {
      // Disabled mode — record the fingerprint once so devs can pin.
      if (_firstSeenLogged.add(host)) {
        Log.i('cert-pin',
            'saw $host → sha256/$fingerprint '
            '(add to CertificatePinning.pinnedSha256Hashes to enable pinning)');
      }
      return;
    }

    if (pins.contains(fingerprint)) {
      return; // pin matched, all good
    }

    final msg = 'pin mismatch for $host: presented sha256/$fingerprint, '
        'expected one of ${pins.length} pinned hash(es)';
    if (_enforce) {
      Log.e('cert-pin', '$msg — REFUSING (enforce mode)');
      throw HandshakeException(
        'TLS certificate pin mismatch for $host '
        '(sha256/$fingerprint not in pin list)',
      );
    } else {
      Log.e('cert-pin', '$msg — allowing (detect-only mode; set '
          'CERT_PINNING_ENFORCE=true to fail closed)');
    }
  }

  /// Install [onBadCertificate] on a raw `dart:io` HttpClient.
  /// Per-response leaf inspection is done by [PinningHttpClient], not
  /// here — `dart:io` doesn't expose an "accepted handshake" callback.
  static void attach(HttpClient client) {
    client.badCertificateCallback = onBadCertificate;
  }

  static String _sha256Hex(List<int> bytes) {
    return sha256.convert(bytes).toString().toLowerCase();
  }
}
