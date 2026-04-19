import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

/// Comprehensive API Testing Suite for Hermosa POS System
/// Tests all API endpoints and validates responses

class ApiTestResult {
  final String endpoint;
  final bool success;
  final int? statusCode;
  final String? error;
  final dynamic response;
  final Duration responseTime;

  ApiTestResult({
    required this.endpoint,
    required this.success,
    this.statusCode,
    this.error,
    this.response,
    required this.responseTime,
  });

  @override
  String toString() {
    final status = success ? '✅ PASS' : '❌ FAIL';
    final code = statusCode != null ? '($statusCode)' : '';
    final time = '${responseTime.inMilliseconds}ms';
    return '$status $endpoint $code - ${error ?? 'OK'} [$time]';
  }
}

class ApiTestingSuite {
  static const String baseUrl = 'https://portal.hermosaapp.com';
  static const Duration timeout = Duration(seconds: 10);

  final List<ApiTestResult> results = [];
  String? authToken;

  // Test configuration
  static const int testBranchId = 87;
  static const int testSellerId = 1;

  Future<void> runAllTests() async {
    print('🚀 Starting Comprehensive API Testing Suite\n');
    print('=' * 80);

    final stopwatch = Stopwatch()..start();

    // Phase 1: Authentication Tests
    await _testAuthentication();

    // Phase 2: Product Tests
    await _testProducts();

    // Phase 3: Category Tests
    await _testCategories();

    // Phase 4: Order Tests
    await _testOrders();

    // Phase 5: Table Tests
    await _testTables();

    // Phase 6: Customer Tests
    await _testCustomers();

    // Phase 7: Report Tests
    await _testReports();

    // Phase 8: Payment Method Tests
    await _testPaymentMethods();

    stopwatch.stop();

    // Print results
    _printResults(stopwatch.elapsed);
  }

  Future<void> _testAuthentication() async {
    print('\n📡 PHASE 1: AUTHENTICATION TESTS');
    print('-' * 80);

    // Test 1.1: Health check (no auth required)
    await _testEndpoint(
      'Health Check',
      '/seller/login',
      method: 'POST',
      body: {'email': 'test@test.com', 'password': 'test'},
      expectAuth: false,
    );
  }

  Future<void> _testProducts() async {
    print('\n📦 PHASE 2: PRODUCT TESTS');
    print('-' * 80);

    // Test 2.1: Get products
    await _testEndpoint(
      'GET Products',
      '/seller/branches/$testBranchId/meals',
    );

    // Test 2.2: Get products with pagination
    await _testEndpoint(
      'GET Products (Paginated)',
      '/seller/branches/$testBranchId/meals?page=1',
    );

    // Test 2.3: Get product details
    await _testEndpoint(
      'GET Product Details',
      '/seller/branches/$testBranchId/meals/1',
    );
  }

  Future<void> _testCategories() async {
    print('\n📂 PHASE 3: CATEGORY TESTS');
    print('-' * 80);

    // Test 3.1: Get meal categories
    await _testEndpoint(
      'GET Categories',
      '/seller/filters/resource/branches/$testBranchId/categories?scope=types&type=meals&all=false',
    );

    // Test 3.2: Get main categories
    await _testEndpoint(
      'GET Main Categories',
      '/seller/main-categories',
    );
  }

  Future<void> _testOrders() async {
    print('\n📋 PHASE 4: ORDER TESTS');
    print('-' * 80);

    // Test 4.1: Get bookings
    await _testEndpoint(
      'GET Bookings',
      '/seller/branches/$testBranchId/bookings',
    );

    // Test 4.2: Get booking metadata
    await _testEndpoint(
      'GET Booking Metadata',
      '/seller/branches/$testBranchId/bookings/create',
    );

    // Test 4.3: Get invoices
    await _testEndpoint(
      'GET Invoices',
      '/seller/branches/$testBranchId/invoices',
    );
  }

  Future<void> _testTables() async {
    print('\n🪑 PHASE 5: TABLE TESTS');
    print('-' * 80);

    // Test 5.1: Get restaurant tables
    await _testEndpoint(
      'GET Tables',
      '/seller/branches/$testBranchId/restaurantTables',
    );
  }

  Future<void> _testCustomers() async {
    print('\n👥 PHASE 6: CUSTOMER TESTS');
    print('-' * 80);

    // Test 6.1: Get customers
    await _testEndpoint(
      'GET Customers',
      '/seller/sellers/$testSellerId/customers',
    );
  }

  Future<void> _testReports() async {
    print('\n📊 PHASE 7: REPORT TESTS');
    print('-' * 80);

    // Test 7.1: Get sales reports
    await _testEndpoint(
      'GET Sales Reports',
      '/seller/branches/$testBranchId/salesReports',
    );

    // Test 7.2: Get tax declaration report
    await _testEndpoint(
      'GET Tax Declaration',
      '/seller/branches/$testBranchId/taxDeclarationReport',
    );
  }

  Future<void> _testPaymentMethods() async {
    print('\n💳 PHASE 8: PAYMENT METHOD TESTS');
    print('-' * 80);

    // Test 8.1: Get payment methods
    await _testEndpoint(
      'GET Payment Methods',
      '/seller/filters/branches/$testBranchId/payMethods',
    );
  }

  Future<void> _testEndpoint(
    String testName,
    String endpoint, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool expectAuth = true,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      late final http.Response response;

      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Accept-Language': 'ar|en',
        'Accept-Platform': ';',
        'Accept-ISO': 'SAU|BHR',
      };

      if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers).timeout(timeout);
          break;
        case 'POST':
          response = await http
              .post(
                uri,
                headers: headers,
                body: jsonEncode(body),
              )
              .timeout(timeout);
          break;
        case 'PUT':
          response = await http
              .put(
                uri,
                headers: headers,
                body: jsonEncode(body),
              )
              .timeout(timeout);
          break;
        default:
          throw Exception('Unsupported method: $method');
      }

      stopwatch.stop();

      final isSuccess = response.statusCode >= 200 && response.statusCode < 300;
      final result = ApiTestResult(
        endpoint: '$method $endpoint',
        success: isSuccess,
        statusCode: response.statusCode,
        response: isSuccess ? _parseResponse(response.body) : null,
        responseTime: stopwatch.elapsed,
        error: isSuccess ? null : _extractError(response.body),
      );

      results.add(result);
      print(result);
    } on SocketException catch (e) {
      stopwatch.stop();
      final result = ApiTestResult(
        endpoint: '$method $endpoint',
        success: false,
        statusCode: null,
        error: 'Network error: ${e.message}',
        responseTime: stopwatch.elapsed,
      );
      results.add(result);
      print(result);
    } on TimeoutException catch (_) {
      stopwatch.stop();
      final result = ApiTestResult(
        endpoint: '$method $endpoint',
        success: false,
        statusCode: null,
        error: 'Request timeout after ${timeout.inSeconds}s',
        responseTime: stopwatch.elapsed,
      );
      results.add(result);
      print(result);
    } catch (e) {
      stopwatch.stop();
      final result = ApiTestResult(
        endpoint: '$method $endpoint',
        success: false,
        statusCode: null,
        error: 'Exception: $e',
        responseTime: stopwatch.elapsed,
      );
      results.add(result);
      print(result);
    }
  }

  dynamic _parseResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded.containsKey('data')) {
        final data = decoded['data'];
        if (data is List) {
          return 'List[${data.length} items]';
        } else if (data is Map) {
          return 'Map{${data.keys.take(5).join(', ')}}';
        }
        return data.runtimeType.toString();
      }
      return decoded.runtimeType.toString();
    } catch (_) {
      return 'Raw response';
    }
  }

  String? _extractError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        if (decoded.containsKey('message')) {
          return decoded['message'];
        } else if (decoded.containsKey('error')) {
          return decoded['error'];
        }
      }
      return 'Status error';
    } catch (_) {
      return 'Parse error';
    }
  }

  void _printResults(Duration totalTime) {
    print('\n');
    print('=' * 80);
    print('📊 API TEST RESULTS SUMMARY');
    print('=' * 80);

    final passed = results.where((r) => r.success).length;
    final failed = results.where((r) => !r.success).length;
    final total = results.length;
    final avgTime = results.isEmpty
        ? 0
        : results
                .map((r) => r.responseTime.inMilliseconds)
                .reduce((a, b) => a + b) /
            total;

    print('');
    print('📈 Statistics:');
    print(
        '  ✅ Passed: $passed/$total (${(passed / total * 100).toStringAsFixed(1)}%)');
    print('  ❌ Failed: $failed/$total');
    print(
        '  ⏱️  Total Time: ${totalTime.inSeconds}.${totalTime.inMilliseconds % 1000}s');
    print('  ⏱️  Average Response Time: ${avgTime.toStringAsFixed(0)}ms');
    print('');

    if (failed > 0) {
      print('❌ FAILED TESTS:');
      print('-' * 80);
      for (final result in results.where((r) => !r.success)) {
        print('  • ${result.endpoint}');
        print('    Error: ${result.error}');
        print('');
      }
    }

    print('=' * 80);
    if (failed == 0) {
      print('🎉 ALL API TESTS PASSED!');
    } else {
      print('⚠️  SOME API TESTS FAILED - Review errors above');
    }
    print('=' * 80);
  }
}

// Live API smoke suite.
// Disabled by default to keep CI deterministic.
void main() {
  final runLive = Platform.environment['RUN_LIVE_API_TESTS'] == 'true';

  test(
    'Live API smoke suite',
    () async {
      final tester = ApiTestingSuite();
      await tester.runAllTests();
    },
    skip: !runLive,
  );
}
