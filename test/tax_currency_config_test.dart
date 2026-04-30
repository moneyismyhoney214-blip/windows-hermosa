import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';

void main() {
  group('ApiConstants tax/currency state', () {
    setUp(() {
      ApiConstants.hasTax = true;
      ApiConstants.taxPercentage = 15;
      ApiConstants.taxRate = 0.15;
      ApiConstants.digitsNumber = 2;
      ApiConstants.currency = 'ر.س';
    });

    test('effectiveTaxRate returns rate when hasTax=true', () {
      ApiConstants.hasTax = true;
      ApiConstants.taxRate = 0.15;
      expect(ApiConstants.effectiveTaxRate, 0.15);
    });

    test('effectiveTaxRate is 0 when hasTax=false', () {
      ApiConstants.hasTax = false;
      ApiConstants.taxRate = 0.15;
      expect(ApiConstants.effectiveTaxRate, 0.0);
    });

    test('isTaxActive requires hasTax AND taxPercentage>0', () {
      ApiConstants.hasTax = true;
      ApiConstants.taxPercentage = 15;
      expect(ApiConstants.isTaxActive, isTrue);

      ApiConstants.taxPercentage = 0;
      expect(ApiConstants.isTaxActive, isFalse);

      ApiConstants.taxPercentage = 15;
      ApiConstants.hasTax = false;
      expect(ApiConstants.isTaxActive, isFalse);
    });

    test('getBranchTaxEndpoint builds the documented path', () {
      expect(ApiConstants.getBranchTaxEndpoint(63),
          '/seller/filters/branches/63/getTax');
      expect(ApiConstants.getBranchTaxEndpoint(1),
          '/seller/filters/branches/1/getTax');
    });

    test('currency defaults to Arabic riyal', () {
      expect(ApiConstants.currency, 'ر.س');
    });

    test('taxRate matches taxPercentage/100 by convention', () {
      ApiConstants.taxPercentage = 5;
      ApiConstants.taxRate = 0.05;
      expect(ApiConstants.effectiveTaxRate, 0.05);

      ApiConstants.taxPercentage = 15;
      ApiConstants.taxRate = 0.15;
      expect(ApiConstants.effectiveTaxRate, 0.15);
    });

    test('isTaxActive flips receipt rendering for tax-free branches', () {
      // Simulates a tax-free branch (e.g. Egypt-only, no VAT line on receipt).
      ApiConstants.hasTax = false;
      ApiConstants.taxPercentage = 0;
      ApiConstants.taxRate = 0.0;
      expect(ApiConstants.isTaxActive, isFalse,
          reason: 'tax-free branch must not render the VAT line');
      expect(ApiConstants.effectiveTaxRate, 0.0,
          reason: 'effective rate must collapse to 0 when tax is off');

      // Switching to a tax-enabled branch (re-login, branch change) re-enables it.
      ApiConstants.hasTax = true;
      ApiConstants.taxPercentage = 5;
      ApiConstants.taxRate = 0.05;
      expect(ApiConstants.isTaxActive, isTrue,
          reason: '5% VAT branch must show the VAT line');
      expect(ApiConstants.effectiveTaxRate, 0.05);
    });

    test('roundMoney respects digitsNumber for SAR (2) and BHD (3)', () {
      ApiConstants.digitsNumber = 2;
      expect(ApiConstants.roundMoney(15.301), 15.30);
      expect(ApiConstants.roundMoney(15.306), 15.31);

      ApiConstants.digitsNumber = 3;
      expect(ApiConstants.roundMoney(15.301), 15.301);
      expect(ApiConstants.roundMoney(15.3015), closeTo(15.302, 0.0001));

      // BHD payment scenario from the 422 error: ensure 15.301 stays intact.
      ApiConstants.digitsNumber = 3;
      expect(ApiConstants.formatMoney(15.301), '15.301');
    });

    test('formatMoney pads to digitsNumber decimals', () {
      ApiConstants.digitsNumber = 3;
      expect(ApiConstants.formatMoney(15.0), '15.000');
      expect(ApiConstants.formatMoney(15.3), '15.300');

      ApiConstants.digitsNumber = 2;
      expect(ApiConstants.formatMoney(15.0), '15.00');
    });

    test('currency override sticks across reads', () {
      // Simulates AED branch handover.
      ApiConstants.currency = 'د.إ';
      expect(ApiConstants.currency, 'د.إ');

      ApiConstants.currency = 'EGP';
      expect(ApiConstants.currency, 'EGP');
    });
  });
}
