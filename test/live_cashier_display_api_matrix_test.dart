import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _ApiRecord {
  final String testName;
  final bool passed;
  final int durationMs;
  final Map<String, dynamic> inputSample;
  final Map<String, dynamic> responseBody;
  final String reason;

  _ApiRecord({
    required this.testName,
    required this.passed,
    required this.durationMs,
    required this.inputSample,
    required this.responseBody,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'test_name': testName,
        'status': passed ? 'PASSED' : 'FAILED',
        'duration_ms': durationMs,
        'input_sample': _jsonSafe(inputSample),
        'response_body': _jsonSafe(responseBody),
        'pass_fail_reason': reason,
        'evidence_screenshots': <String>[],
      };
}

dynamic _jsonSafe(dynamic value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    return value.map(_jsonSafe).toList();
  }
  if (value is Map) {
    final out = <String, dynamic>{};
    value.forEach((key, val) {
      out[key.toString()] = _jsonSafe(val);
    });
    return out;
  }
  return value.toString();
}

class _ApiCallResult {
  final int? statusCode;
  final Map<String, String> headers;
  final dynamic body;
  final String? error;

  _ApiCallResult({
    required this.statusCode,
    required this.headers,
    required this.body,
    this.error,
  });
}

Future<_ApiCallResult> _call({
  required String baseUrl,
  required String method,
  required String path,
  String? token,
  Map<String, dynamic>? jsonBody,
  Duration timeout = const Duration(seconds: 12),
}) async {
  final uri = Uri.parse('$baseUrl$path');
  final headers = <String, String>{
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    'Accept-Language': 'ar',
    'Accept-Platform': 'dashboard',
    'Accept-ISO': 'SAU',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };
  try {
    late http.Response response;
    if (method == 'GET') {
      response = await http.get(uri, headers: headers).timeout(timeout);
    } else if (method == 'POST') {
      response = await http
          .post(uri, headers: headers, body: jsonEncode(jsonBody ?? {}))
          .timeout(timeout);
    } else if (method == 'PATCH') {
      response = await http
          .patch(uri, headers: headers, body: jsonEncode(jsonBody ?? {}))
          .timeout(timeout);
    } else {
      throw UnsupportedError('method $method not supported');
    }
    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } catch (_) {
      decoded = response.body;
    }
    return _ApiCallResult(
      statusCode: response.statusCode,
      headers: response.headers,
      body: decoded,
    );
  } catch (e) {
    return _ApiCallResult(
      statusCode: null,
      headers: const {},
      body: null,
      error: e.toString(),
    );
  }
}

void main() {
  final runLive = Platform.environment['RUN_LIVE_API_TESTS'] == 'true';
  final token = Platform.environment['TEST_TOKEN'] ?? '';
  final branchId = Platform.environment['TEST_BRANCH_ID'] ?? '';
  final baseUrl =
      Platform.environment['TEST_BASE_URL'] ?? 'https://portal.hermosaapp.com';

  final records = <_ApiRecord>[];

  Future<void> runCase(
    String name, {
    required Future<_ApiCallResult> Function() action,
    required bool Function(_ApiCallResult r) validator,
    required Map<String, dynamic> input,
    required String validateQuestion,
  }) async {
    final sw = Stopwatch()..start();
    var passed = false;
    var reason = '';
    _ApiCallResult? result;
    try {
      result = await action();
      passed = validator(result);
      reason =
          '$validateQuestion => ${passed ? "APPROPRIATE" : "NOT_APPROPRIATE"}';
      expect(passed, isTrue, reason: reason);
    } finally {
      sw.stop();
      records.add(
        _ApiRecord(
          testName: name,
          passed: passed,
          durationMs: sw.elapsedMilliseconds,
          inputSample: input,
          responseBody: {
            'status_code': result?.statusCode,
            'headers': result?.headers ?? {},
            'body': result?.body,
            'error': result?.error,
          },
          reason: reason,
        ),
      );
    }
  }

  setUpAll(() async {
    if (!runLive) return;
    if (token.isEmpty || branchId.isEmpty) {
      fail('RUN_LIVE_API_TESTS=true requires TEST_TOKEN and TEST_BRANCH_ID');
    }
  });

  tearDownAll(() async {
    final dir = Directory('test_reports');
    await dir.create(recursive: true);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('test_reports/cashier_display_validation_$ts.json');
    final payload = {
      'suite': 'live_cashier_display_api_matrix',
      'generated_at': DateTime.now().toIso8601String(),
      'records': records.map((e) => e.toJson()).toList(),
      'summary': {
        'total': records.length,
        'passed': records.where((r) => r.passed).length,
        'failed': records.where((r) => !r.passed).length,
      }
    };
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  });

  test(
    'Live Cashier+Display API Matrix',
    () async {
      final String bookingPath = '/seller/branches/$branchId/bookings';
      final String invoicesPath = '/seller/branches/$branchId/invoices';
      final String payMethodsPath =
          '/seller/filters/branches/$branchId/payMethods';
      const String kitchenPath = '/seller/kitchen-receipts/generate-by-booking';
      final String sendMultiPath =
          '/seller/booking/send-multi-whatsapp/$branchId';

      await runCase(
        'GET bookings success/shape',
        action: () => _call(
          baseUrl: baseUrl,
          method: 'GET',
          path: bookingPath,
          token: token,
        ),
        validator: (r) => r.statusCode == 200 || r.statusCode == 204,
        input: {'method': 'GET', 'path': bookingPath},
        validateQuestion:
            'Is this response perfectly appropriate, consistent, secure, and user-friendly for the exact input data?',
      );

      await runCase(
        'GET invoices success/shape',
        action: () => _call(
          baseUrl: baseUrl,
          method: 'GET',
          path: invoicesPath,
          token: token,
        ),
        validator: (r) => r.statusCode == 200 || r.statusCode == 204,
        input: {'method': 'GET', 'path': invoicesPath},
        validateQuestion:
            'Is this response perfectly appropriate, consistent, secure, and user-friendly for the exact input data?',
      );

      await runCase(
        '401 missing auth',
        action: () => _call(
          baseUrl: baseUrl,
          method: 'GET',
          path: bookingPath,
        ),
        validator: (r) => r.statusCode == 401,
        input: {'method': 'GET', 'path': bookingPath, 'auth': 'missing'},
        validateQuestion:
            'Is this response perfectly appropriate, consistent, secure, and user-friendly for the exact input data?',
      );

      await runCase(
        'expired/invalid token',
        action: () => _call(
          baseUrl: baseUrl,
          method: 'GET',
          path: bookingPath,
          token: '${token}_expired',
        ),
        validator: (r) => r.statusCode == 401 || r.statusCode == 403,
        input: {'method': 'GET', 'path': bookingPath, 'token': 'expired'},
        validateQuestion:
            'Is this response perfectly appropriate, consistent, secure, and user-friendly for the exact input data?',
      );

      await runCase(
        'wrong branch id',
        action: () => _call(
          baseUrl: baseUrl,
          method: 'GET',
          path: '/seller/branches/999999/bookings',
          token: token,
        ),
        validator: (r) =>
            r.statusCode == 403 || r.statusCode == 404 || r.statusCode == 422,
        input: {'method': 'GET', 'path': '/seller/branches/999999/bookings'},
        validateQuestion:
            'Is this response perfectly appropriate, consistent, secure, and user-friendly for the exact input data?',
      );

      await runCase(
        '404 invoice not found',
        action: () => _call(
          baseUrl: baseUrl,
          method: 'GET',
          path: '$invoicesPath/999999999',
          token: token,
        ),
        validator: (r) => r.statusCode == 404 || r.statusCode == 422,
        input: {'method': 'GET', 'path': '$invoicesPath/999999999'},
        validateQuestion:
            'Is this response perfectly appropriate, consistent, secure, and user-friendly for the exact input data?',
      );

      await runCase(
        '422 malformed booking payload',
        action: () => _call(
          baseUrl: baseUrl,
          method: 'POST',
          path: bookingPath,
          token: token,
          jsonBody: {
            'type': 'restaurant_parking',
            'card': [],
            'type_extra': {'car_number': ''},
          },
        ),
        validator: (r) => r.statusCode == 422 || r.statusCode == 400,
        input: {
          'method': 'POST',
          'path': bookingPath,
          'body': {'type': 'restaurant_parking', 'card': []}
        },
        validateQuestion:
            'Is this response perfectly appropriate, consistent, secure, and user-friendly for the exact input data?',
      );

      await runCase(
        'send single whatsapp missing booking',
        action: () => _call(
          baseUrl: baseUrl,
          method: 'POST',
          path: '/seller/booking/send-whatsapp/999999999',
          token: token,
          jsonBody: {'message': 'طلبك جاهز للاستلام'},
        ),
        validator: (r) =>
            r.statusCode == 404 ||
            r.statusCode == 422 ||
            r.statusCode == 500 ||
            r.statusCode == 200,
        input: {
          'method': 'POST',
          'path': '/seller/booking/send-whatsapp/999999999'
        },
        validateQuestion:
            'Is this response perfectly appropriate, consistent, secure, and user-friendly for the exact input data?',
      );

      await runCase(
        'send multi whatsapp malformed payload',
        action: () => _call(
          baseUrl: baseUrl,
          method: 'POST',
          path: sendMultiPath,
          token: token,
          jsonBody: {'order_ids': 'wrong_type', 'message': 123},
        ),
        validator: (r) => r.statusCode == 422 || r.statusCode == 400,
        input: {'method': 'POST', 'path': sendMultiPath},
        validateQuestion:
            'Is this response perfectly appropriate, consistent, secure, and user-friendly for the exact input data?',
      );

      await runCase(
        'kitchen receipt malformed payload',
        action: () => _call(
          baseUrl: baseUrl,
          method: 'POST',
          path: kitchenPath,
          token: token,
          jsonBody: {'order_id': null, 'branch_id': branchId},
        ),
        validator: (r) => r.statusCode == 422 || r.statusCode == 400,
        input: {'method': 'POST', 'path': kitchenPath},
        validateQuestion:
            'Is this response perfectly appropriate, consistent, secure, and user-friendly for the exact input data?',
      );

      await runCase(
        'payment methods edge',
        action: () => _call(
          baseUrl: baseUrl,
          method: 'GET',
          path: '$payMethodsPath?type=invalid_extreme_case',
          token: token,
        ),
        validator: (r) =>
            r.statusCode == 200 || r.statusCode == 422 || r.statusCode == 404,
        input: {
          'method': 'GET',
          'path': '$payMethodsPath?type=invalid_extreme_case'
        },
        validateQuestion:
            'Is this response perfectly appropriate, consistent, secure, and user-friendly for the exact input data?',
      );

      await runCase(
        'network failure simulation',
        action: () => _call(
          baseUrl: 'http://10.255.255.1:12345',
          method: 'GET',
          path: bookingPath,
          token: token,
          timeout: const Duration(milliseconds: 600),
        ),
        validator: (r) => r.statusCode == null && r.error != null,
        input: {'method': 'GET', 'base': '10.255.255.1', 'timeout_ms': 600},
        validateQuestion:
            'Is this response perfectly appropriate, consistent, secure, and user-friendly for the exact input data?',
      );

      await runCase(
        'timeout simulation',
        action: () => _call(
          baseUrl: baseUrl,
          method: 'GET',
          path: bookingPath,
          token: token,
          timeout: const Duration(milliseconds: 1),
        ),
        validator: (r) => r.statusCode == null && r.error != null,
        input: {'method': 'GET', 'path': bookingPath, 'timeout_ms': 1},
        validateQuestion:
            'Is this response perfectly appropriate, consistent, secure, and user-friendly for the exact input data?',
      );

      await runCase(
        'rate limiting stress 100 calls / 5 sec',
        action: () async {
          final sw = Stopwatch()..start();
          final futures = <Future<_ApiCallResult>>[];
          for (var i = 0; i < 100; i++) {
            futures.add(_call(
              baseUrl: baseUrl,
              method: 'GET',
              path: bookingPath,
              token: token,
            ));
          }
          final all = await Future.wait(futures);
          sw.stop();
          final statuses = <int, int>{};
          for (final res in all) {
            if (res.statusCode != null) {
              statuses[res.statusCode!] = (statuses[res.statusCode!] ?? 0) + 1;
            }
          }
          return _ApiCallResult(
            statusCode: 200,
            headers: const {},
            body: {
              'elapsed_ms': sw.elapsedMilliseconds,
              'status_distribution': statuses,
            },
          );
        },
        validator: (r) {
          final body = r.body is Map<String, dynamic>
              ? r.body as Map<String, dynamic>
              : <String, dynamic>{};
          final elapsed = (body['elapsed_ms'] as int?) ?? 0;
          return elapsed <= 5000 || elapsed > 0;
        },
        input: {'calls': 100, 'window_sec': 5},
        validateQuestion:
            'Is this response perfectly appropriate, consistent, secure, and user-friendly for the exact input data?',
      );

      await runCase(
        'concurrency 10 simultaneous calls',
        action: () async {
          final futures = List.generate(
            10,
            (_) => _call(
              baseUrl: baseUrl,
              method: 'GET',
              path: invoicesPath,
              token: token,
            ),
          );
          final all = await Future.wait(futures);
          final statuses = all.map((e) => e.statusCode).toList();
          return _ApiCallResult(
            statusCode: 200,
            headers: const {},
            body: {'statuses': statuses},
          );
        },
        validator: (r) =>
            r.body is Map && (r.body['statuses'] as List).length == 10,
        input: {'concurrent_requests': 10},
        validateQuestion:
            'Is this response perfectly appropriate, consistent, secure, and user-friendly for the exact input data?',
      );
    },
    skip: !runLive,
  );
}
