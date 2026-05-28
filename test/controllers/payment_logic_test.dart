import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/controllers/payment_logic.dart';

void main() {
  group('PaymentLogic.isCashOnlyPayment', () {
    test('returns false when no payments are present', () {
      expect(PaymentLogic.isCashOnlyPayment(const []), isFalse);
    });

    test('returns false when every amount is zero or negative', () {
      final pays = <Map<String, dynamic>>[
        {'pay_method': 'cash', 'amount': 0},
        {'pay_method': 'cash', 'amount': -5},
      ];
      expect(PaymentLogic.isCashOnlyPayment(pays), isFalse);
    });

    test('returns true when the only positive payment is cash', () {
      final pays = <Map<String, dynamic>>[
        {'pay_method': 'cash', 'amount': 100},
      ];
      expect(PaymentLogic.isCashOnlyPayment(pays), isTrue);
    });

    test('returns true when split-cash payments total positive', () {
      final pays = <Map<String, dynamic>>[
        {'pay_method': 'cash', 'amount': 40},
        {'pay_method': 'cash', 'amount': 60},
      ];
      expect(PaymentLogic.isCashOnlyPayment(pays), isTrue);
    });

    test('returns false when one of the positive payments is card', () {
      final pays = <Map<String, dynamic>>[
        {'pay_method': 'cash', 'amount': 40},
        {'pay_method': 'card', 'amount': 60},
      ];
      expect(PaymentLogic.isCashOnlyPayment(pays), isFalse);
    });

    test('treats string amounts the same as numeric amounts', () {
      final pays = <Map<String, dynamic>>[
        {'pay_method': 'cash', 'amount': '50.00'},
      ];
      expect(PaymentLogic.isCashOnlyPayment(pays), isTrue);
    });

    test('ignores zero-amount entries when computing the mix', () {
      // A zero-amount card line should NOT contaminate the result.
      final pays = <Map<String, dynamic>>[
        {'pay_method': 'cash', 'amount': 100},
        {'pay_method': 'card', 'amount': 0},
      ];
      expect(PaymentLogic.isCashOnlyPayment(pays), isTrue);
    });

    test('non-numeric amounts default to 0 and are skipped', () {
      final pays = <Map<String, dynamic>>[
        {'pay_method': 'cash', 'amount': 'NaN'},
        {'pay_method': 'cash', 'amount': 25},
      ];
      expect(PaymentLogic.isCashOnlyPayment(pays), isTrue);
    });
  });

  group('PaymentLogic.sumPayments', () {
    test('returns 0 for an empty list', () {
      expect(PaymentLogic.sumPayments(const []), 0.0);
    });

    test('sums positive amounts, ignoring negatives and non-numerics', () {
      final pays = <Map<String, dynamic>>[
        {'pay_method': 'cash', 'amount': 10},
        {'pay_method': 'cash', 'amount': '20.5'},
        {'pay_method': 'cash', 'amount': -5},
        {'pay_method': 'cash', 'amount': 'NaN'},
      ];
      expect(PaymentLogic.sumPayments(pays), closeTo(30.5, 1e-9));
    });
  });

  group('PaymentLogic.applyOrderDiscounts', () {
    test('returns gross when there are no discounts', () {
      final net = PaymentLogic.applyOrderDiscounts(
        grossOrderTotal: 100,
        manualDiscount: 0,
        promoDiscount: 0,
        isOrderFree: false,
      );
      expect(net, 100);
    });

    test('subtracts both manual and promo additively', () {
      final net = PaymentLogic.applyOrderDiscounts(
        grossOrderTotal: 100,
        manualDiscount: 10,
        promoDiscount: 15,
        isOrderFree: false,
      );
      expect(net, 75);
    });

    test('clamps to zero — discounts cannot make the order negative', () {
      final net = PaymentLogic.applyOrderDiscounts(
        grossOrderTotal: 50,
        manualDiscount: 30,
        promoDiscount: 40,
        isOrderFree: false,
      );
      expect(net, 0);
    });

    test('isOrderFree wins even when discounts are zero', () {
      final net = PaymentLogic.applyOrderDiscounts(
        grossOrderTotal: 100,
        manualDiscount: 0,
        promoDiscount: 0,
        isOrderFree: true,
      );
      expect(net, 0);
    });
  });

  group('PaymentLogic.normalizePayMethod', () {
    test('returns a non-empty canonical token for known aliases', () {
      // We don't pin the exact result (ReceiptBuilderService owns the
      // alias table) — just that the helper is wired up and stable.
      expect(PaymentLogic.normalizePayMethod('CASH'), isNotEmpty);
      expect(PaymentLogic.normalizePayMethod(null), isNotEmpty);
    });
  });
}
