import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/logger_service.dart';

void main() {
  group('Log.sanitize', () {
    test('redacts JWT-shaped tokens', () {
      const input = 'authorize with '
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dQw4w9WgXcQ';
      final out = Log.sanitize(input);
      expect(out, contains('***JWT***'));
      expect(out, isNot(contains('eyJzdWIiOiIxMjM0NTY3ODkwIn0')));
    });

    test('redacts Authorization: Bearer headers', () {
      const input = 'Authorization: Bearer abc123xyz456';
      final out = Log.sanitize(input);
      expect(out.toLowerCase(), isNot(contains('abc123xyz456')));
    });

    test('redacts 13-19 digit numbers (PAN range)', () {
      // 16-digit PAN
      expect(Log.sanitize('card 4111111111111111 was used'),
          contains('****'));
      // 13-digit PAN (older Visa)
      expect(Log.sanitize('card 4111111111111'),
          contains('****'));
      // 19-digit PAN (upper bound)
      expect(Log.sanitize('card 4111111111111111111'),
          contains('****'));
    });

    test('leaves short numeric ids untouched', () {
      // 6-digit order numbers must not be scrubbed
      final out = Log.sanitize('order 123456 created');
      expect(out, contains('123456'));
    });

    test('redacts e-mail addresses', () {
      final out = Log.sanitize('contact alice@example.com for details');
      expect(out, contains('***@***'));
      expect(out, isNot(contains('alice@example.com')));
    });

    test('returns the empty string unchanged', () {
      expect(Log.sanitize(''), '');
    });

    test('handles strings with no sensitive markers', () {
      const safe = 'order 42 paid in cash by guest';
      expect(Log.sanitize(safe), safe);
    });
  });
}
