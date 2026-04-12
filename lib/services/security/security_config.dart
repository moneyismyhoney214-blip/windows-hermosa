/// Temporary security configuration wrapper.
///
/// NOTE: This keeps secrets centralized until backend secure distribution
/// is available. Do not log these values.
class SecurityConfig {
  SecurityConfig._();

  static const String wsSharedSecret = 'hermosa_pos_secure_ws_key_2024';

  static const String nearPayClientUuid =
      '55df27ff-0b1c-430f-a137-3d8dd96d4af0';
  static const String nearPayTerminalId = '0211868700118687';
  static const String nearPayGoogleCloudProjectNumber = '764962961378';
  static const String nearPayPrivateKeyFileName =
      '1770817497953-private-key.pem';
}
