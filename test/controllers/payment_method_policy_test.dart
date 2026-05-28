import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/controllers/payment_method_policy.dart';

void main() {
  group('PaymentMethodPolicy.isMethodEnabledForInvoice', () {
    test('returns true when the method is explicitly enabled', () {
      final ok = PaymentMethodPolicy.isMethodEnabledForInvoice(
        normalizedMethod: 'cash',
        enabledPayMethods: const {'cash': true},
        isProfileNearPayEnabled: false,
        isCdsEnabled: false,
      );
      expect(ok, isTrue);
    });

    test('returns false when the method is explicitly disabled', () {
      final ok = PaymentMethodPolicy.isMethodEnabledForInvoice(
        normalizedMethod: 'cash',
        enabledPayMethods: const {'cash': false},
        isProfileNearPayEnabled: false,
        isCdsEnabled: false,
      );
      expect(ok, isFalse);
    });

    test('"card" is enabled when any branded variant is enabled', () {
      final ok = PaymentMethodPolicy.isMethodEnabledForInvoice(
        normalizedMethod: 'card',
        enabledPayMethods: const {'mada': true},
        isProfileNearPayEnabled: false,
        isCdsEnabled: false,
      );
      expect(ok, isTrue);
    });

    test('"card" is suppressed when NearPay is on but CDS is off', () {
      // The only NearPay surface is the customer display; without CDS
      // there is nowhere to render the card prompt.
      final ok = PaymentMethodPolicy.isMethodEnabledForInvoice(
        normalizedMethod: 'card',
        enabledPayMethods: const {'card': true, 'mada': true},
        isProfileNearPayEnabled: true,
        isCdsEnabled: false,
      );
      expect(ok, isFalse);
    });

    test('"card" is allowed when NearPay is on AND CDS is on', () {
      final ok = PaymentMethodPolicy.isMethodEnabledForInvoice(
        normalizedMethod: 'card',
        enabledPayMethods: const {'card': true},
        isProfileNearPayEnabled: true,
        isCdsEnabled: true,
      );
      expect(ok, isTrue);
    });
  });

  group('PaymentMethodPolicy.hasAnyEnabledPayMethod', () {
    test('returns false when no supported method is enabled', () {
      final has = PaymentMethodPolicy.hasAnyEnabledPayMethod(
        enabledPayMethods: const {'cash': false, 'card': false},
        isProfileNearPayEnabled: false,
        isCdsEnabled: false,
      );
      expect(has, isFalse);
    });

    test('returns true when cash is enabled', () {
      final has = PaymentMethodPolicy.hasAnyEnabledPayMethod(
        enabledPayMethods: const {'cash': true},
        isProfileNearPayEnabled: false,
        isCdsEnabled: false,
      );
      expect(has, isTrue);
    });

    test('ignores unknown methods even when truthy', () {
      final has = PaymentMethodPolicy.hasAnyEnabledPayMethod(
        enabledPayMethods: const {'bitcoin': true},
        isProfileNearPayEnabled: false,
        isCdsEnabled: false,
      );
      expect(has, isFalse);
    });

    test('skips card-likes when NearPay is on but CDS is off', () {
      final has = PaymentMethodPolicy.hasAnyEnabledPayMethod(
        enabledPayMethods: const {
          'card': true,
          'mada': true,
          'visa': true,
          'benefit': true,
        },
        isProfileNearPayEnabled: true,
        isCdsEnabled: false,
      );
      expect(has, isFalse);
    });

    test('counts non-card methods when card-likes are suppressed', () {
      final has = PaymentMethodPolicy.hasAnyEnabledPayMethod(
        enabledPayMethods: const {
          'card': true, // suppressed
          'cash': true, // remains usable
        },
        isProfileNearPayEnabled: true,
        isCdsEnabled: false,
      );
      expect(has, isTrue);
    });
  });

  group('PaymentMethodPolicy.effectiveForTender', () {
    test('forces pay_later off regardless of input', () {
      final out = PaymentMethodPolicy.effectiveForTender(
          const {'cash': true, 'pay_later': true});
      expect(out['pay_later'], isFalse);
      expect(out['cash'], isTrue);
    });

    test('does not mutate the input map', () {
      final input = <String, bool>{'cash': true, 'pay_later': true};
      PaymentMethodPolicy.effectiveForTender(input);
      expect(input['pay_later'], isTrue,
          reason: 'callers may share the live map; the helper must copy');
    });
  });
}
