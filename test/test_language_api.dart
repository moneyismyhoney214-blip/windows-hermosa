import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/api/base_client.dart';
import 'package:hermosa_pos/services/language_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Language-API Integration', () async {
    print('Testing Language-API Integration');
    print('=' * 60);

    // Mock SharedPreferences
    SharedPreferences.setMockInitialValues({});

    // Initialize translation service
    await translationService.initialize();

    final client = BaseClient();

    print('Scenario 1: Set language to Arabic');
    await translationService.setLanguage('ar');
    var headers = client.getHeadersForTesting();
    print('App Language: ${translationService.currentLocale.languageCode}');
    print('Accept-Language Header: ${headers['Accept-Language']}');

    if (headers['Accept-Language'] == 'ar') {
      print('✅ SUCCESS: Header matches Arabic');
    } else {
      print('❌ FAILURE: Header does not match Arabic');
    }

    print('\nScenario 2: Change language to English');
    await translationService.setLanguage('en');
    headers = client.getHeadersForTesting();
    print('App Language: ${translationService.currentLocale.languageCode}');
    print('Accept-Language Header: ${headers['Accept-Language']}');

    if (headers['Accept-Language'] == 'en') {
      print('✅ SUCCESS: Header matches English');
    } else {
      print('❌ FAILURE: Header does not match English');
    }

    print('\nScenario 3: Change language to Turkish');
    await translationService.setLanguage('tr');
    headers = client.getHeadersForTesting();
    print('App Language: ${translationService.currentLocale.languageCode}');
    print('Accept-Language Header: ${headers['Accept-Language']}');

    if (headers['Accept-Language'] == 'tr') {
      print('✅ SUCCESS: Header matches Turkish');
    } else {
      print('❌ FAILURE: Header does not match Turkish');
    }

    print('=' * 60);
    print('Language-API Integration Test Completed');
  });
}
