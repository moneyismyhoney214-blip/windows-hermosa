import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/printer_role_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tests for [PrinterRoleRegistry] — the printer-role persistence
/// layer. The audit flagged the registry's previous SharedPreferences
/// storage as plaintext-on-disk; the migrated version reads/writes
/// from `flutter_secure_storage` and migrates any legacy plaintext
/// entry on first read.
///
/// `flutter_secure_storage` exposes its native plugin via a method
/// channel; we stub it directly so the tests run on the host without
/// an Android/iOS emulator. Same pattern as
/// `test/services/secure_token_store_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final secureStorageMock = <String, String>{};

  setUp(() {
    secureStorageMock.clear();
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
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
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('initialize() with empty storage leaves the explicit-roles map empty',
      () async {
    final reg = PrinterRoleRegistry();
    await reg.initialize();
    expect(reg.explicitRoles, isEmpty);
  });

  test('setRole + reload survives via secure storage', () async {
    final reg = PrinterRoleRegistry();
    await reg.setRole('device-A', PrinterRole.kds);
    await reg.setRole('device-B', PrinterRole.cashierReceipt);

    expect(reg.explicitRoles['device-A'], PrinterRole.kds);
    expect(reg.explicitRoles['device-B'], PrinterRole.cashierReceipt);

    // The secure-storage blob is a JSON map of id → storageValue.
    expect(secureStorageMock['printer_role_registry_v1'], isNotNull);
    expect(secureStorageMock['printer_role_registry_v1'], contains('"kds"'));

    // Reloading from disk gives back the same map.
    final reg2 = PrinterRoleRegistry();
    await reg2.initialize();
    expect(reg2.explicitRoles['device-A'], PrinterRole.kds);
    expect(reg2.explicitRoles['device-B'], PrinterRole.cashierReceipt);
  });

  test('migrates a legacy SharedPreferences entry to secure storage on '
      'first read', () async {
    // Simulate a device upgraded from the pre-migration build: the
    // role map sits in plaintext SharedPrefs.
    SharedPreferences.setMockInitialValues({
      'printer_role_registry_v1':
          '{"old-device":"kds","another":"cashier_receipt"}',
    });

    final reg = PrinterRoleRegistry();
    await reg.initialize();

    // 1. The roles loaded into memory.
    expect(reg.explicitRoles['old-device'], PrinterRole.kds);
    expect(reg.explicitRoles['another'], PrinterRole.cashierReceipt);

    // 2. The blob was copied into secure storage.
    expect(secureStorageMock['printer_role_registry_v1'], isNotNull);
    expect(secureStorageMock['printer_role_registry_v1'], contains('old-device'));

    // 3. The plaintext SharedPrefs copy was wiped post-migration.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('printer_role_registry_v1'), isNull,
        reason: 'plaintext copy must be removed once the migration succeeds');
  });

  test('clearRole removes a single role and persists', () async {
    final reg = PrinterRoleRegistry();
    await reg.setRole('device-A', PrinterRole.kds);
    await reg.setRole('device-B', PrinterRole.bar);

    await reg.clearRole('device-A');

    expect(reg.explicitRoles.containsKey('device-A'), isFalse);
    expect(reg.explicitRoles['device-B'], PrinterRole.bar);

    // Persisted blob no longer contains device-A.
    expect(secureStorageMock['printer_role_registry_v1'],
        isNot(contains('device-A')));
  });

  test('setRole with empty deviceId is a no-op (and does not throw)',
      () async {
    final reg = PrinterRoleRegistry();
    await reg.setRole('   ', PrinterRole.kitchen);
    expect(reg.explicitRoles, isEmpty);
    // Storage was not touched.
    expect(secureStorageMock['printer_role_registry_v1'], isNull);
  });

  group('PrinterRoleX.fromStorage', () {
    test('canonical values round-trip', () {
      for (final role in PrinterRole.values) {
        expect(PrinterRoleX.fromStorage(role.storageValue), role);
      }
    });

    test('legacy aliases map to cashierReceipt', () {
      expect(PrinterRoleX.fromStorage('cashier'), PrinterRole.cashierReceipt);
      expect(PrinterRoleX.fromStorage('receipt'), PrinterRole.cashierReceipt);
    });

    test('unknown / empty values fall back to general', () {
      expect(PrinterRoleX.fromStorage(null), PrinterRole.general);
      expect(PrinterRoleX.fromStorage(''), PrinterRole.general);
      expect(PrinterRoleX.fromStorage('nonsense'), PrinterRole.general);
    });
  });
}
