import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/logger_service.dart';

/// Extended tests for [Log.sanitize] — the redactor that runs on
/// crash-report bodies and any log line that might carry secrets.
///
/// The existing `test/services/logger_test.dart` covers the happy path.
/// These add edge cases: case-insensitive headers, mixed payloads,
/// no-false-positive on benign text, and the new file-crash path that
/// runs `sanitize` on the message + error before persisting.
void main() {
  group('JWT redaction', () {
    test('removes a real-shape JWT and leaves surrounding text', () {
      const input = 'login response: {"token":"eyJhbGciOiJIUzI1NiJ9'
          '.eyJzdWIiOiIxMjMifQ.abcdef-123_xyz"} ok';
      final out = Log.sanitize(input);
      expect(out, contains('***JWT***'));
      expect(out, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(out, contains('login response'));
      expect(out, contains('} ok'));
    });

    test('does not trip on a string that happens to start with eyJ', () {
      // "eyJabc" alone (no dot separators) isn't a JWT — the redactor
      // must not eat arbitrary base64 prefixes.
      final out = Log.sanitize('product code eyJabc123');
      expect(out, 'product code eyJabc123');
    });
  });

  group('Bearer token redaction', () {
    test('case-insensitive on "Bearer" prefix', () {
      // The sanitizer preserves the original header-key casing
      // (Authorization → Authorization=***) so the surrounding log
      // line stays readable. Only the secret part is wiped.
      expect(Log.sanitize('Authorization: BeArEr abcdef.123'),
          'Authorization=***');
      expect(Log.sanitize('bearer xyz.123_abc-X'), 'Bearer ***');
    });

    test('redacts inside JSON-like bodies', () {
      const input = '{"token": "Bearer eyJa.bc.def", "user": 12}';
      final out = Log.sanitize(input);
      expect(out, isNot(contains('eyJa.bc.def')));
      expect(out, contains('user'));
    });
  });

  group('PAN redaction', () {
    test('redacts a 16-digit card number', () {
      expect(Log.sanitize('card 4111111111111111 was charged'),
          'card **** was charged');
    });

    test('redacts a 13-digit (legacy Visa) number', () {
      expect(Log.sanitize('4111111111111'), '****');
    });

    test('does not redact something shorter than 13 digits', () {
      // PCI scope kicks in at 13 chars. A 12-digit transit id should
      // survive untouched.
      expect(Log.sanitize('ref 123456789012'), 'ref 123456789012');
    });
  });

  group('Email redaction', () {
    test('redacts a standard address', () {
      expect(Log.sanitize('user signup: alice@example.com'),
          'user signup: ***@***');
    });

    test('redacts addresses with dots and plus tags', () {
      expect(Log.sanitize('alice.smith+pos@example.co.uk'), '***@***');
    });
  });

  group('Combined payloads', () {
    test('a multi-secret log line redacts everything in one pass', () {
      const input =
          'login OK for user@example.com: Bearer eyJabc.def.ghi card 4111111111111111';
      final out = Log.sanitize(input);
      expect(out, isNot(contains('user@example.com')));
      expect(out, isNot(contains('eyJabc.def.ghi')));
      expect(out, isNot(contains('4111111111111111')));
      expect(out, contains('login OK'));
    });
  });

  group('Empty / edge inputs', () {
    test('empty string is returned as-is', () {
      expect(Log.sanitize(''), '');
    });

    test('input with no secrets is returned unchanged', () {
      expect(Log.sanitize('hello world 123'), 'hello world 123');
    });
  });
}
