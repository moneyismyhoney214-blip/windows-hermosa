import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/customer_display/nearpay/nearpay_backend_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Tests for [NearPayBackendService]. Audit flagged NearPay as zero-test
/// coverage despite being on the revenue path; these tests lock down
/// the JWT fetch, purchase-session creation, and session-status read
/// against the contract the SDK expects.
///
/// The service accepts an injectable `http.Client`, so we use
/// `package:http/testing.dart`'s `MockClient` to stub responses with
/// no network I/O.
void main() {
  group('NearPayBackendService.fetchJwtToken', () {
    test('happy path returns the token and parses expiry metadata', () async {
      late http.Request capturedRequest;
      final mock = MockClient((req) async {
        capturedRequest = req;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'token': _validJwt,
              'expires_at': 1747700000,
              'expires_in': 3600,
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final svc = NearPayBackendService(
        baseUrl: 'https://api.example.com',
        authToken: 'seller-token-123',
        branchId: 42,
        client: mock,
      );

      final payload = await svc.fetchJwtToken(terminalTid: 'TID1');

      expect(payload.token, _validJwt);
      expect(payload.expiresAt, 1747700000);
      expect(payload.expiresIn, 3600);

      // Verify the request shape the backend depends on. If any of
      // these change without coordination, real terminals will fail.
      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.url.toString(),
          'https://api.example.com/seller/nearpay/auth/token');
      expect(capturedRequest.headers['authorization'], 'Bearer seller-token-123');
      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body['branch_id'], 42);
      expect(body['terminal_tid'], 'TID1');
    });

    test('non-200 status surfaces the backend message', () async {
      final mock = MockClient((req) async => http.Response(
            jsonEncode({
              'success': false,
              'message': 'الفرع غير مفعّل لخدمة NearPay',
            }),
            403,
          ));
      final svc = NearPayBackendService(
        baseUrl: 'https://api.example.com',
        authToken: 't',
        branchId: 1,
        client: mock,
      );

      expect(
        () => svc.fetchJwtToken(),
        throwsA(predicate(
            (e) => e is Exception && e.toString().contains('NearPay'))),
      );
    });

    test('success:false at 200 status still throws', () async {
      final mock = MockClient((req) async => http.Response(
            jsonEncode({'success': false, 'message': 'unknown error'}),
            200,
          ));
      final svc = NearPayBackendService(
        baseUrl: 'https://api.example.com',
        authToken: 't',
        branchId: 1,
        client: mock,
      );
      expect(svc.fetchJwtToken,
          throwsA(predicate((e) => e.toString().contains('unknown error'))));
    });

    test('malformed JSON body throws a clear FormatException-wrapped error',
        () async {
      final mock = MockClient((req) async => http.Response('not-json', 200));
      final svc = NearPayBackendService(
        baseUrl: 'https://api.example.com',
        authToken: 't',
        branchId: 1,
        client: mock,
      );
      expect(svc.fetchJwtToken,
          throwsA(predicate(
              (e) => e is Exception && e.toString().contains('status'))));
    });

    test('missing token in payload throws', () async {
      final mock = MockClient((req) async => http.Response(
            jsonEncode({
              'success': true,
              'data': {'expires_at': 1},
            }),
            200,
          ));
      final svc = NearPayBackendService(
        baseUrl: 'https://api.example.com',
        authToken: 't',
        branchId: 1,
        client: mock,
      );
      expect(svc.fetchJwtToken,
          throwsA(predicate((e) => e.toString().contains('JWT'))));
    });

    test('network timeout maps to a localised error', () async {
      final mock = MockClient((req) async {
        // The service has a 30s timeout — block forever to trigger it.
        // Use Completer.future so the test doesn't actually wait 30s
        // (the timeout fires inside the service code).
        await Future<void>.delayed(const Duration(seconds: 32));
        return http.Response('{}', 200);
      });
      final svc = NearPayBackendService(
        baseUrl: 'https://api.example.com',
        authToken: 't',
        branchId: 1,
        client: mock,
      );
      expect(
        () => svc.fetchJwtToken(),
        throwsA(predicate((e) => e.toString().contains('انتهت مهلة'))),
      );
    }, timeout: const Timeout(Duration(seconds: 35)));
  });

  group('NearPayBackendService.createPurchaseSession', () {
    test('sends amount-in-halalas and reference id in the body', () async {
      late http.Request capturedRequest;
      final mock = MockClient((req) async {
        capturedRequest = req;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'session_id': 'sess-1',
              'terminal_id': 'term-1',
              'amount': 5000,
              'reference_id': 'INV-001',
              'status': 'new',
              'type': 'purchase',
            }
          }),
          200,
        );
      });

      final svc = NearPayBackendService(
        baseUrl: 'https://api.example.com',
        authToken: 't',
        branchId: 7,
        client: mock,
      );

      final session = await svc.createPurchaseSession(
        amountInHalalas: 5000,
        referenceId: 'INV-001',
      );

      expect(session.sessionId, 'sess-1');
      expect(session.amount, 5000);
      expect(session.referenceId, 'INV-001');
      expect(session.status, 'new');

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body['branch_id'], 7);
      expect(body['amount'], 5000,
          reason: 'amount must be in halalas, never SAR — backend rejects floats');
      expect(body['reference_id'], 'INV-001');
    });

    test('supports nested data.session payload shape', () async {
      // Earlier backend revisions wrapped the session fields under
      // `data.session`. The parser still has to handle both layouts.
      final mock = MockClient((req) async => http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'session': {
                  'session_id': 's',
                  'terminal_id': 't',
                  'amount': 1,
                  'reference_id': 'r',
                  'status': 'new',
                  'type': 'purchase',
                }
              }
            }),
            200,
          ));
      final svc = NearPayBackendService(
        baseUrl: 'https://api.example.com',
        authToken: 't',
        branchId: 1,
        client: mock,
      );
      final session =
          await svc.createPurchaseSession(amountInHalalas: 1, referenceId: 'r');
      expect(session.sessionId, 's');
    });

    test('5xx error is propagated with the backend message', () async {
      final mock = MockClient((req) async => http.Response(
            jsonEncode({'success': false, 'message': 'server overloaded'}),
            503,
          ));
      final svc = NearPayBackendService(
        baseUrl: 'https://api.example.com',
        authToken: 't',
        branchId: 1,
        client: mock,
      );
      expect(
        () => svc.createPurchaseSession(amountInHalalas: 100, referenceId: 'r'),
        throwsA(predicate((e) => e.toString().contains('server overloaded'))),
      );
    });
  });

  group('NearPayBackendService.getSessionStatus', () {
    test('appends terminal_id as a query param when non-empty', () async {
      late http.Request capturedRequest;
      final mock = MockClient((req) async {
        capturedRequest = req;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'session_id': 'sess-1',
              'status': 'completed',
              'transaction_id': 'tx-1',
            }
          }),
          200,
        );
      });

      final svc = NearPayBackendService(
        baseUrl: 'https://api.example.com',
        authToken: 't',
        branchId: 1,
        client: mock,
      );

      final data =
          await svc.getSessionStatus(terminalId: 'term-1', sessionId: 'sess-1');

      expect(capturedRequest.url.queryParameters['terminal_id'], 'term-1');
      expect(capturedRequest.url.path, '/seller/nearpay/session/sess-1');
      expect(data['status'], 'completed');
    });

    test('omits terminal_id query param when empty', () async {
      late http.Request capturedRequest;
      final mock = MockClient((req) async {
        capturedRequest = req;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'session_id': 'x', 'status': 'new'}
          }),
          200,
        );
      });
      final svc = NearPayBackendService(
        baseUrl: 'https://api.example.com',
        authToken: 't',
        branchId: 1,
        client: mock,
      );
      await svc.getSessionStatus(terminalId: '', sessionId: 'x');
      expect(capturedRequest.url.queryParameters.containsKey('terminal_id'),
          isFalse);
    });
  });

  group('baseUrl normalization', () {
    test('trailing slash on baseUrl is stripped', () async {
      late http.Request capturedRequest;
      final mock = MockClient((req) async {
        capturedRequest = req;
        return http.Response(
            jsonEncode({
              'success': true,
              'data': {'token': _validJwt}
            }),
            200);
      });

      final svc = NearPayBackendService(
        baseUrl: 'https://api.example.com/', // trailing slash
        authToken: 't',
        branchId: 1,
        client: mock,
      );
      await svc.fetchJwtToken();
      expect(capturedRequest.url.toString(),
          'https://api.example.com/seller/nearpay/auth/token',
          reason: 'no double slash should appear after normalization');
    });
  });
}

// A syntactically valid (but cryptographically meaningless) JWT used in
// fixtures. Header/payload are base64url-encoded but the signature is
// fake — fetchJwtToken parses but never verifies, so this is fine.
const String _validJwt =
    'eyJhbGciOiJIUzI1NiJ9'
    '.eyJkYXRhIjp7InRlcm1pbmFsX2lkIjoidDEiLCJjbGllbnRfdXVpZCI6InUxIn19'
    '.sig';
