/// Compile-time security configuration.
///
/// IMPORTANT: anything in this file ships in the APK / IPA in plaintext.
/// Treat every value here as **public to anyone who unzips the build**.
/// Move anything more sensitive (per-merchant tokens, signing keys,
/// payment-terminal credentials) into [SecureTokenStore] or fetch from
/// the backend at runtime instead.
///
/// History: the previous version of this file held four NearPay-tier
/// terminal credentials (`nearPayClientUuid`, `nearPayTerminalId`,
/// `nearPayGoogleCloudProjectNumber`, `nearPayPrivateKeyFileName`) as
/// `static const`. Those constants were never read anywhere in lib/ —
/// they were dead identifiers that nonetheless leaked terminal pairing
/// material to anyone with `unzip`. They were removed entirely; the
/// actual NearPay flow loads its developer certificate at runtime from
/// `assets/certs/`, which is a separate but still-followed-up item.
class SecurityConfig {
  SecurityConfig._();

  /// HMAC handshake secret for the cashier ↔ customer-display WebSocket
  /// channel. Both engines are bundled into the same APK so this value is
  /// shared by construction; the threat model assumes the attacker who
  /// extracts this string already has the rest of the binary.
  ///
  /// Future: derive per-install from a Keystore-resident master so a
  /// breached APK doesn't compromise every deployment uniformly.
  static const String wsSharedSecret = 'hermosa_pos_secure_ws_key_2024';
}
