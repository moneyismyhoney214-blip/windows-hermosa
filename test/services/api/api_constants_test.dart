import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';

/// Tests for [ApiConstants] — the global per-session config blob.
///
/// Most fields are mutable globals set from the login response; these
/// tests pin down the derived helpers (`effectiveTaxRate`, `isTaxActive`,
/// `roundMoney`, `formatMoney`) so a regression there doesn't quietly
/// break invoice totals or payment payloads (the backend rejects
/// `sum(payments) ≠ invoice.total` at server precision).
void main() {
  // Save and restore the global state around each test so tests in this
  // file don't bleed into others that run in the same process.
  late bool savedHasTax;
  late int savedTaxPercentage;
  late double savedTaxRate;
  late int savedDigits;

  setUp(() {
    savedHasTax = ApiConstants.hasTax;
    savedTaxPercentage = ApiConstants.taxPercentage;
    savedTaxRate = ApiConstants.taxRate;
    savedDigits = ApiConstants.digitsNumber;
  });

  tearDown(() {
    ApiConstants.hasTax = savedHasTax;
    ApiConstants.taxPercentage = savedTaxPercentage;
    ApiConstants.taxRate = savedTaxRate;
    ApiConstants.digitsNumber = savedDigits;
  });

  group('effectiveTaxRate', () {
    test('returns the configured rate when tax is on', () {
      ApiConstants.hasTax = true;
      ApiConstants.taxRate = 0.15;
      expect(ApiConstants.effectiveTaxRate, 0.15);
    });

    test('returns zero when tax is disabled, regardless of taxRate', () {
      ApiConstants.hasTax = false;
      ApiConstants.taxRate = 0.99;
      expect(ApiConstants.effectiveTaxRate, 0.0,
          reason: 'hasTax=false must dominate so arithmetic gates cleanly');
    });
  });

  group('isTaxActive', () {
    test('true only when hasTax AND taxPercentage > 0', () {
      ApiConstants.hasTax = true;
      ApiConstants.taxPercentage = 15;
      expect(ApiConstants.isTaxActive, isTrue);

      ApiConstants.taxPercentage = 0;
      expect(ApiConstants.isTaxActive, isFalse,
          reason: 'zero-percent branches must not show tax UI');

      ApiConstants.taxPercentage = 15;
      ApiConstants.hasTax = false;
      expect(ApiConstants.isTaxActive, isFalse);
    });
  });

  group('roundMoney', () {
    test('rounds to digitsNumber decimals (SA = 2)', () {
      ApiConstants.digitsNumber = 2;
      expect(ApiConstants.roundMoney(10.999), 11.00);
      expect(ApiConstants.roundMoney(10.123), 10.12);
      expect(ApiConstants.roundMoney(10.125), 10.13);
    });

    test('rounds to 3 decimals for KWD-style markets', () {
      ApiConstants.digitsNumber = 3;
      expect(ApiConstants.roundMoney(10.1234), 10.123);
      // 10.1236 has a clearly-resolved 4th decimal so the test isn't
      // sitting on top of a float-representation tie like 10.1235 was.
      expect(ApiConstants.roundMoney(10.1236), 10.124);
    });

    test('clamps digits to a sane range', () {
      // digitsNumber is clamped to 0..6 internally so a garbage config
      // value never trips toStringAsFixed with an out-of-range arg.
      ApiConstants.digitsNumber = 99;
      // Should not throw; result is rounded to 6 decimals.
      expect(ApiConstants.roundMoney(1.1234567), 1.123457);
    });

    test('zero-decimal markets (JPY-style) round to integer', () {
      ApiConstants.digitsNumber = 0;
      expect(ApiConstants.roundMoney(10.6), 11.0);
      expect(ApiConstants.roundMoney(10.4), 10.0);
    });
  });

  group('formatMoney', () {
    test('pads to digitsNumber decimals with trailing zeros', () {
      ApiConstants.digitsNumber = 2;
      expect(ApiConstants.formatMoney(5), '5.00');
      expect(ApiConstants.formatMoney(5.1), '5.10');
      expect(ApiConstants.formatMoney(5.12345), '5.12');
    });

    test('3-decimal markets', () {
      ApiConstants.digitsNumber = 3;
      expect(ApiConstants.formatMoney(5), '5.000');
    });
  });

  group('setAcceptLanguage', () {
    test('normalizes case + whitespace', () {
      ApiConstants.setAcceptLanguage('  EN  ');
      expect(ApiConstants.acceptLanguage, 'en');
    });

    test('empty input falls back to the Arabic default', () {
      ApiConstants.setAcceptLanguage('');
      expect(ApiConstants.acceptLanguage, 'ar');
    });
  });

  group('endpoint string builders', () {
    test('refundedMealsEndpoint emits booking_id when only booking is set', () {
      // ApiConstants.branchId is a global set from login; pin it for the
      // assertion. Restore via tearDown isn't needed — branchId isn't
      // saved/restored above because nothing in this group's other tests
      // depends on it.
      ApiConstants.branchId = 42;
      final url = ApiConstants.refundedMealsEndpoint(bookingId: 'B-1');
      expect(url, contains('/seller/refunded-meals/branches/42'));
      expect(url, contains('booking_id=B-1'));
      expect(url, isNot(contains('invoice_id')));
    });

    test('refundedMealsEndpoint prefers booking over invoice when both set',
        () {
      ApiConstants.branchId = 7;
      final url = ApiConstants.refundedMealsEndpoint(
          bookingId: 'B', invoiceId: 'I');
      expect(url, contains('booking_id=B'),
          reason: 'booking is checked first in the builder');
      expect(url, isNot(contains('invoice_id=I')));
    });

    test('refundedMealsEndpoint emits no query string when both are empty',
        () {
      ApiConstants.branchId = 9;
      final url = ApiConstants.refundedMealsEndpoint();
      expect(url, '/seller/refunded-meals/branches/9');
    });
  });
}
