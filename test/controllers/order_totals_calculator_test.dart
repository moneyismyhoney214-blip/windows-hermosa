import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/controllers/order_totals_calculator.dart';

void main() {
  group('OrderTotalsCalculator.taxAmountFromSubtotal', () {
    test('returns 0 when tax is disabled', () {
      const calc = OrderTotalsCalculator(isTaxEnabled: false, taxRate: 0.15);
      expect(calc.taxAmountFromSubtotal(100), 0.0);
    });

    test('returns 0 for zero or negative subtotal', () {
      const calc = OrderTotalsCalculator(isTaxEnabled: true, taxRate: 0.15);
      expect(calc.taxAmountFromSubtotal(0), 0.0);
      expect(calc.taxAmountFromSubtotal(-10), 0.0);
    });

    test('multiplies subtotal by the rate', () {
      const calc = OrderTotalsCalculator(isTaxEnabled: true, taxRate: 0.15);
      expect(calc.taxAmountFromSubtotal(200), closeTo(30.0, 1e-9));
    });

    test('returns 0 when rate is zero', () {
      const calc = OrderTotalsCalculator(isTaxEnabled: true, taxRate: 0.0);
      expect(calc.taxAmountFromSubtotal(100), 0.0);
    });
  });

  group('OrderTotalsCalculator.composeGrandTotal', () {
    test('with no tax and no discounts returns gross-equal grand', () {
      const calc = OrderTotalsCalculator.noTax();
      final t = calc.composeGrandTotal(gross: 100);
      expect(t.net, 100);
      expect(t.tax, 0);
      expect(t.grand, 100);
    });

    test('15% tax on net 200 yields grand 230', () {
      const calc = OrderTotalsCalculator(isTaxEnabled: true, taxRate: 0.15);
      final t = calc.composeGrandTotal(gross: 200);
      expect(t.net, 200);
      expect(t.tax, closeTo(30, 1e-9));
      expect(t.grand, closeTo(230, 1e-9));
    });

    test('discounts subtract from gross before tax is applied', () {
      const calc = OrderTotalsCalculator(isTaxEnabled: true, taxRate: 0.15);
      final t = calc.composeGrandTotal(
        gross: 200,
        manualDiscount: 10,
        promoDiscount: 40,
      );
      expect(t.net, 150);
      expect(t.tax, closeTo(22.5, 1e-9));
      expect(t.grand, closeTo(172.5, 1e-9));
    });

    test('discounts cannot push the net below zero', () {
      const calc = OrderTotalsCalculator(isTaxEnabled: true, taxRate: 0.15);
      final t = calc.composeGrandTotal(
        gross: 50,
        manualDiscount: 100,
        promoDiscount: 0,
      );
      expect(t.net, 0);
      expect(t.tax, 0);
      expect(t.grand, 0);
    });

    test('isOrderFree returns an all-zero bundle', () {
      const calc = OrderTotalsCalculator(isTaxEnabled: true, taxRate: 0.15);
      final t = calc.composeGrandTotal(
        gross: 200,
        manualDiscount: 0,
        isOrderFree: true,
      );
      expect(t, const GrandTotal(net: 0, tax: 0, grand: 0));
    });
  });

  group('OrderTotalsCalculator immutability', () {
    test('noTax constructor produces the documented state', () {
      const calc = OrderTotalsCalculator.noTax();
      expect(calc.isTaxEnabled, isFalse);
      expect(calc.taxRate, 0.0);
    });

    test('GrandTotal equality compares all three fields', () {
      const a = GrandTotal(net: 100, tax: 15, grand: 115);
      const b = GrandTotal(net: 100, tax: 15, grand: 115);
      const c = GrandTotal(net: 100, tax: 15, grand: 116);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
