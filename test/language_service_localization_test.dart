import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermosa_pos/services/language_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('Turkish includes cashier and printer option labels', () async {
    await translationService.setLanguage('tr');

    expect(translationService.t('devices'), 'Cihazlar');
    expect(translationService.t('cashier'), 'Kasa');
    expect(translationService.t('printers_management'), 'Yazıcı Yönetimi');
    expect(translationService.t('kds_printers_count'), 'KDS Yazıcıları');
    expect(
      translationService.t('promo_applied', args: {'code': 'ABCD'}),
      'Kupon uygulandı: ABCD',
    );
  });

  test('Unsupported language falls back to Arabic', () async {
    await translationService.setLanguage('xx');

    expect(translationService.t('devices'), 'الأجهزة');
    expect(translationService.t('printers_management'), 'إدارة الطابعات');
  });
}
