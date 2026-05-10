// Live integration test: hits the real Hermosa portal API to verify the
// login → taxObject extraction → getTax refresh pipeline matches what
// `AuthService._applyTaxObject` and `BranchService._applyTaxToApiConstants`
// expect.
//
// Run with:
//   flutter test test/tax_api_live_test.dart
//
// Skip when offline — the network guard inside [setUpAll] downgrades the
// suite to a no-op rather than failing CI.

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:hermosa_pos/services/api/api_constants.dart';

const _baseUrl = 'https:// portal.hermosaapp.com';
const _email = 'tikanah200@gmail.com';
const _password = '123456';

Map<String, String> _headers([String? token]) => {
      'Accept': 'application/json',
      'Accept-Language': 'ar',
      'Accept-Platform': 'dashboard',
      'Accept-ISO': 'SAU',
      if (token != null) 'Authorization': 'Bearer $token',
    };

Future<Map<String, dynamic>> _login() async {
  final uri = Uri.parse('$_baseUrl/seller/login');
  final req = http.MultipartRequest('POST', uri)
    ..headers.addAll(_headers())
    ..fields['email'] = _email
    ..fields['password'] = _password
    ..fields['remember_me'] = '0';
  final streamed = await req.send().timeout(const Duration(seconds: 15));
  final res = await http.Response.fromStream(streamed);
  expect(res.statusCode, 200, reason: 'login HTTP code');
  return jsonDecode(res.body) as Map<String, dynamic>;
}

Future<Map<String, dynamic>> _fetchTax(int branchId, String token) async {
  final uri =
      Uri.parse('$_baseUrl/seller/filters/branches/$branchId/getTax');
  final res = await http
      .get(uri, headers: _headers(token))
      .timeout(const Duration(seconds: 15));
  expect(res.statusCode, 200, reason: 'getTax HTTP code');
  return jsonDecode(res.body) as Map<String, dynamic>;
}

// Replicates `AuthService._applyTaxObject` — keeps this test independent of
// the real service (which depends on Flutter binding for SharedPreferences).
void _applyTaxObject(Map raw) {
  final tax = raw.map((k, v) => MapEntry(k.toString(), v));
  final hasTaxRaw = tax['has_tax'] ?? tax['hasTax'];
  if (hasTaxRaw is bool) {
    ApiConstants.hasTax = hasTaxRaw;
  } else if (hasTaxRaw is num) {
    ApiConstants.hasTax = hasTaxRaw != 0;
  }
  final pctRaw = tax['tax_percentage'] ?? tax['taxPercentage'];
  if (pctRaw is num) {
    final pct = pctRaw.toDouble();
    final percent = pct > 1.0 ? pct : pct * 100.0;
    ApiConstants.taxPercentage = percent.round();
    ApiConstants.taxRate = (percent / 100.0).clamp(0.0, 1.0).toDouble();
  }
  final digits = tax['digits_number'] ?? tax['digitsNumber'];
  if (digits is num) ApiConstants.digitsNumber = digits.toInt();
  final currency = tax['currency']?.toString().trim();
  if (currency != null && currency.isNotEmpty) {
    ApiConstants.currency = currency;
  }
}

void main() {
  late bool networkAvailable;

  setUpAll(() async {
    try {
      final ping = await http
          .get(Uri.parse('$_baseUrl/seller/login'), headers: _headers())
          .timeout(const Duration(seconds: 5));
      networkAvailable = ping.statusCode > 0;
    } catch (_) {
      networkAvailable = false;
    }
    if (!networkAvailable) {
      // ignore: avoid_print
      print('⚠️ Network unavailable — skipping live API tests');
    }
  });

  setUp(() {
    // Reset to factory defaults so each test is order-independent.
    ApiConstants.hasTax = true;
    ApiConstants.taxPercentage = 15;
    ApiConstants.taxRate = 0.15;
    ApiConstants.digitsNumber = 2;
    ApiConstants.currency = 'ر.س';
  });

  test('login returns taxObject in the documented shape', () async {
    if (!networkAvailable) return;

    final body = await _login();
    expect(body['status'], 200);
    final data = body['data'] as Map;
    expect(data['token'], isA<String>());
    final branches = data['branches'] as List;
    expect(branches, isNotEmpty);

    final branch = branches.first as Map;
    expect(branch['id'], isA<num>());
    expect(branch['name'], isA<String>());

    final taxObject = branch['taxObject'] as Map;
    expect(taxObject.containsKey('has_tax'), isTrue);
    expect(taxObject.containsKey('tax_percentage'), isTrue);
    expect(taxObject.containsKey('digits_number'), isTrue);
    expect(taxObject.containsKey('currency'), isTrue);
  });

  test('AuthService._applyTaxObject correctly maps login taxObject',
      () async {
    if (!networkAvailable) return;

    final body = await _login();
    final branch = (body['data']['branches'] as List).first as Map;
    final taxObject = branch['taxObject'] as Map;
    _applyTaxObject(taxObject);

    // Cross-check against the live payload (BH branch on  portal.hermosaapp.com
    // returns 10% / د.ب, KSA branch on portal returns 15% / ر.س — the test
    // adapts to whichever environment the URL points at).
    final expectedHasTax = taxObject['has_tax'] == true;
    final expectedPct = (taxObject['tax_percentage'] as num).toInt();
    final expectedDigits = (taxObject['digits_number'] as num).toInt();
    final expectedCurrency = taxObject['currency'].toString();

    expect(ApiConstants.hasTax, expectedHasTax);
    expect(ApiConstants.taxPercentage, expectedPct);
    expect(ApiConstants.taxRate, closeTo(expectedPct / 100.0, 0.0001));
    expect(ApiConstants.digitsNumber, expectedDigits);
    expect(ApiConstants.currency, expectedCurrency);
    expect(
      ApiConstants.effectiveTaxRate,
      expectedHasTax ? closeTo(expectedPct / 100.0, 0.0001) : 0.0,
    );
    expect(ApiConstants.isTaxActive, expectedHasTax && expectedPct > 0);
  });

  test('getTax endpoint returns identical config to login taxObject',
      () async {
    if (!networkAvailable) return;

    final loginBody = await _login();
    final token = loginBody['data']['token'] as String;
    final branch = (loginBody['data']['branches'] as List).first as Map;
    final branchId = (branch['id'] as num).toInt();
    final loginTax = branch['taxObject'] as Map;

    final taxBody = await _fetchTax(branchId, token);
    expect(taxBody['status'], 200);
    final taxData = taxBody['data'] as Map;

    expect(taxData['has_tax'], loginTax['has_tax']);
    expect(taxData['tax_percentage'], loginTax['tax_percentage']);
    expect(taxData['digits_number'], loginTax['digits_number']);
    expect(taxData['currency'], loginTax['currency']);
  });

  test('full flow: login → getTax → ApiConstants reflects authoritative data',
      () async {
    if (!networkAvailable) return;

    // Simulate cold app startup with stale prefs values.
    ApiConstants.hasTax = false;
    ApiConstants.taxPercentage = 0;
    ApiConstants.taxRate = 0.0;
    ApiConstants.currency = 'XXX';

    final loginBody = await _login();
    final token = loginBody['data']['token'] as String;
    final branch = (loginBody['data']['branches'] as List).first as Map;
    final branchId = (branch['id'] as num).toInt();
    final loginTax = branch['taxObject'] as Map;

    // Step 1: apply taxObject from login
    _applyTaxObject(loginTax);
    expect(ApiConstants.hasTax, loginTax['has_tax'] == true,
        reason: 'login taxObject should hydrate hasTax');

    // Step 2: refresh via getTax (server is authoritative)
    final taxBody = await _fetchTax(branchId, token);
    final getTaxData = taxBody['data'] as Map;
    _applyTaxObject(getTaxData);

    // Final state matches whatever the live API returned (BH or KSA).
    expect(ApiConstants.hasTax, getTaxData['has_tax'] == true);
    expect(
      ApiConstants.taxPercentage,
      (getTaxData['tax_percentage'] as num).toInt(),
    );
    expect(
      ApiConstants.taxRate,
      closeTo((getTaxData['tax_percentage'] as num).toDouble() / 100.0, 0.0001),
    );
    expect(ApiConstants.currency, getTaxData['currency']);
  });

  test('unauthenticated getTax returns 401', () async {
    if (!networkAvailable) return;

    final uri = Uri.parse('$_baseUrl/seller/filters/branches/63/getTax');
    final res = await http
        .get(uri, headers: _headers())
        .timeout(const Duration(seconds: 10));
    expect(res.statusCode, 401);
    final body = jsonDecode(res.body) as Map;
    expect(body['status'], 401);
    expect(body['message'], 'UNAUTHENTICATED');
  });
}
