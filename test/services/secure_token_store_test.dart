import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/security/secure_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests for the JWT secure-storage migration path. The critical
/// invariant: an existing user with a token in SharedPreferences (the
/// pre-Keystore world) must NOT be logged out by the upgrade. The
/// migration step lifts the legacy token, writes it into secure
/// storage, and erases the plaintext copy in a single operation.
///
/// `flutter_secure_storage` exposes a method-channel mock; we stub the
/// channel directly so the tests run on the host (no Android/iOS
/// emulator needed).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final secureStorageMock = <String, String>{};

  setUp(() {
    secureStorageMock.clear();
    // Mock the flutter_secure_storage method channel for unit tests.
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      final key = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return secureStorageMock[key];
        case 'write':
          secureStorageMock[key!] = args['value'] as String;
          return null;
        case 'delete':
          secureStorageMock.remove(key);
          return null;
        case 'deleteAll':
          secureStorageMock.clear();
          return null;
        case 'readAll':
          return Map<String, String>.from(secureStorageMock);
        case 'containsKey':
          return secureStorageMock.containsKey(key);
        default:
          return null;
      }
    });
    SharedPreferences.setMockInitialValues(const {});
  });

  tearDown(() {
    const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('SecureTokenStore.readToken', () {
    test('returns null when nothing is stored anywhere', () async {
      final t = await secureTokenStore.readToken();
      expect(t, isNull);
    });

    test('returns the token from secure storage when present', () async {
      secureStorageMock['auth_token'] = 'jwt-abc';
      final t = await secureTokenStore.readToken();
      expect(t, 'jwt-abc');
    });

    test('migrates a legacy SharedPreferences token to secure storage',
        () async {
      // Simulate a user upgraded from the pre-Keystore build: their
      // token is in plaintext SharedPreferences.
      SharedPreferences.setMockInitialValues({'auth_token': 'legacy-jwt'});

      final t = await secureTokenStore.readToken();

      expect(t, 'legacy-jwt',
          reason: 'migration must surface the legacy token transparently');
      expect(secureStorageMock['auth_token'], 'legacy-jwt',
          reason: 'the token must now live in secure storage');

      // The plaintext copy must be gone.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull,
          reason: 'plaintext copy must be wiped after migration');
    });

    test('secure storage wins when both copies somehow exist', () async {
      secureStorageMock['auth_token'] = 'newer';
      SharedPreferences.setMockInitialValues({'auth_token': 'older'});
      final t = await secureTokenStore.readToken();
      expect(t, 'newer');
    });
  });

  group('SecureTokenStore.writeToken', () {
    test('writes the token and wipes any legacy plaintext copy', () async {
      SharedPreferences.setMockInitialValues({'auth_token': 'legacy'});

      await secureTokenStore.writeToken('fresh-jwt');

      expect(secureStorageMock['auth_token'], 'fresh-jwt');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull);
    });
  });

  group('SecureTokenStore.clearAll', () {
    test('removes token + user from both backends', () async {
      secureStorageMock['auth_token'] = 'jwt';
      secureStorageMock['user_data'] = '{"id":1}';
      SharedPreferences.setMockInitialValues({
        'auth_token': 'legacy-jwt',
        'user_data': '{"id":99}',
      });

      await secureTokenStore.clearAll();

      expect(secureStorageMock['auth_token'], isNull);
      expect(secureStorageMock['user_data'], isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth_token'), isNull);
      expect(prefs.getString('user_data'), isNull);
    });
  });

  group('SecureTokenStore.readUser', () {
    test('migrates legacy user JSON the same way as the token', () async {
      const sample = '{"id":42,"email":"a@b.com"}';
      SharedPreferences.setMockInitialValues({'user_data': sample});

      final u = await secureTokenStore.readUser();
      expect(u, sample);
      expect(secureStorageMock['user_data'], sample);
    });
  });
}
