// ignore_for_file: avoid_dynamic_calls
//
// JSON wire-boundary / message-dispatch layer — dynamic accesses here are
// known and accepted pending the typed-model refactor planned in
// audit_2026_05_19.md (split models.dart, introduce concrete DTOs).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';
import 'package:hermosa_pos/services/api/base_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Tests for [BaseClient] — the single HTTP entry point. The audit
/// flagged this as untested. We use [BaseClient.setClientForTesting]
/// to inject a `MockClient` from `package:http/testing.dart` so no
/// network I/O happens.
///
/// BaseClient is a singleton, which means state bleeds between tests
/// if we're not careful. setUp/tearDown reset the token and headers
/// to known values.
void main() {
  late BaseClient client;

  setUp(() {
    client = BaseClient();
    client.clearToken();
  });

  tearDown(() {
    client.clearToken();
    // Re-init real client so subsequent tests aren't stuck with the
    // last test's MockClient.
    client.setClientForTesting(http.Client());
  });

  group('headers', () {
    test('default headers include Accept-Language from ApiConstants', () {
      ApiConstants.setAcceptLanguage('en');
      final h = client.getHeadersForTesting();
      expect(h['Accept-Language'], 'en');
      expect(h['Content-Type'], 'application/json');
      expect(h['Accept'], 'application/json');
    });

    test('Authorization header appears once a token is set', () {
      expect(client.getHeadersForTesting().containsKey('Authorization'),
          isFalse);
      client.setToken('abc.def.ghi');
      expect(client.getHeadersForTesting()['Authorization'],
          'Bearer abc.def.ghi');
    });

    test('clearToken removes the Authorization header', () {
      client.setToken('xyz');
      client.clearToken();
      expect(client.getHeadersForTesting().containsKey('Authorization'),
          isFalse);
    });
  });

  group('get', () {
    test('decodes JSON body on 2xx', () async {
      client.setClientForTesting(MockClient((req) async {
        return http.Response(jsonEncode({'ok': true, 'n': 1}), 200);
      }));

      final result = await client.get('/seller/profile');
      expect(result, isA<Map>());
      expect(result['ok'], isTrue);
      expect(result['n'], 1);
    });

    test('attaches token + accepts the response', () async {
      client.setToken('tok-1');
      late http.Request captured;
      client.setClientForTesting(MockClient((req) async {
        captured = req;
        return http.Response('{}', 200);
      }));

      await client.get('/x');
      expect(captured.headers['Authorization'], 'Bearer tok-1');
      expect(captured.headers['Accept'], 'application/json');
    });

    test('absolute URL is honored over the base URL', () async {
      late http.Request captured;
      client.setClientForTesting(MockClient((req) async {
        captured = req;
        return http.Response('{}', 200);
      }));

      await client.get('https://other.example.com/path');
      expect(captured.url.toString(), 'https://other.example.com/path');
    });

    test('relative path is prefixed with ApiConstants.baseUrl', () async {
      late http.Request captured;
      client.setClientForTesting(MockClient((req) async {
        captured = req;
        return http.Response('{}', 200);
      }));

      await client.get('/seller/profile');
      expect(captured.url.host, 'portal.hermosaapp.com');
      expect(captured.url.path, '/seller/profile');
    });

    test('customBaseUrl override goes to that host', () async {
      late http.Request captured;
      client.setClientForTesting(MockClient((req) async {
        captured = req;
        return http.Response('{}', 200);
      }));

      await client.get('/x', customBaseUrl: 'https://staging.example.com');
      expect(captured.url.host, 'staging.example.com');
    });

    test('per-call headers override defaults', () async {
      late http.Request captured;
      client.setClientForTesting(MockClient((req) async {
        captured = req;
        return http.Response('{}', 200);
      }));

      await client.get('/x', headers: {'Accept-Language': 'fr'});
      expect(captured.headers['Accept-Language'], 'fr');
    });
  });

  group('post', () {
    test('sends JSON-encoded body', () async {
      late http.Request captured;
      client.setClientForTesting(MockClient((req) async {
        captured = req;
        return http.Response('{}', 200);
      }));

      await client.post('/x', {'a': 1, 'b': 'two'});
      expect(captured.method, 'POST');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['a'], 1);
      expect(body['b'], 'two');
    });
  });

  group('error handling', () {
    test('non-2xx throws ApiException with the status code', () async {
      client.setClientForTesting(MockClient((req) async {
        return http.Response(jsonEncode({'message': 'forbidden'}), 403);
      }));

      try {
        await client.get('/x');
        fail('expected ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, 403);
      }
    });

    test('401 throws UnauthorizedException and invokes onUnauthorized',
        () async {
      var called = 0;
      BaseClient.onUnauthorized = () async => called++;

      client.setClientForTesting(MockClient((req) async {
        return http.Response(jsonEncode({'message': 'token expired'}), 401);
      }));

      try {
        await client.get('/x');
        fail('expected UnauthorizedException');
      } on UnauthorizedException catch (e) {
        expect(e.statusCode, 401);
      }
      expect(called, 1,
          reason: 'onUnauthorized must fire so the app routes to login');

      BaseClient.onUnauthorized = null;
    });

    test('skipGlobalAuth=true suppresses the onUnauthorized callback',
        () async {
      var called = 0;
      BaseClient.onUnauthorized = () async => called++;

      client.setClientForTesting(MockClient((req) async {
        return http.Response('{}', 401);
      }));

      try {
        await client.get('/x', skipGlobalAuth: true);
      } on UnauthorizedException {
        // Expected — the exception still bubbles up, but the global
        // logout side-effect must not fire (used by public-content
        // endpoints like legal_page_screen).
      }
      expect(called, 0);
      BaseClient.onUnauthorized = null;
    });

    test('5xx surfaces as ApiException, not silently swallowed', () async {
      client.setClientForTesting(MockClient((req) async {
        return http.Response('upstream down', 502);
      }));

      try {
        await client.get('/x');
        fail('expected ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, 502);
      }
    });

    test('non-JSON 2xx body throws ApiException (not a silent parse failure)',
        () async {
      client.setClientForTesting(MockClient((req) async {
        return http.Response('definitely not json', 200);
      }));

      expect(() => client.get('/x'), throwsA(isA<ApiException>()));
    });
  });
}
