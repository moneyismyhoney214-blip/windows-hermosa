import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';
import 'package:hermosa_pos/services/receipt_builder_service.dart';

/// Golden tests for [ReceiptBuilderService] helpers.
///
/// The audit flagged receipts as untested despite being revenue-critical.
/// The service's full `build()` requires a large set of fixtures
/// (OrderReceiptData + caches), but the pure helpers below are the
/// places where most regressions historically originate: payment-method
/// normalization, order-type synonyms, tax-inclusive math, delivery-
/// provider detection, and the printed payment label.
///
/// These tests don't modify any receipt code — they lock in the
/// current behaviour so future refactors can't silently change what
/// the cashier prints.
void main() {
  group('tax-inclusive math', () {
    test('subtotalFromTaxInclusiveTotal: 115 inc 15% → 100', () {
      final sub = ReceiptBuilderService.subtotalFromTaxInclusiveTotal(
        115,
        isTaxEnabled: true,
        taxRate: 0.15,
      );
      expect(sub, closeTo(100, 0.0001));
    });

    test('subtotalFromTaxInclusiveTotal returns the input when tax is off', () {
      expect(
        ReceiptBuilderService.subtotalFromTaxInclusiveTotal(115,
            isTaxEnabled: false, taxRate: 0.15),
        115,
      );
    });

    test('taxFromTaxInclusiveTotal: 115 inc 15% → 15', () {
      expect(
        ReceiptBuilderService.taxFromTaxInclusiveTotal(115,
            isTaxEnabled: true, taxRate: 0.15),
        closeTo(15, 0.0001),
      );
    });

    test('taxFromTaxInclusiveTotal: zero/negative total → 0 tax', () {
      expect(
        ReceiptBuilderService.taxFromTaxInclusiveTotal(0,
            isTaxEnabled: true, taxRate: 0.15),
        0.0,
      );
      expect(
        ReceiptBuilderService.taxFromTaxInclusiveTotal(-10,
            isTaxEnabled: true, taxRate: 0.15),
        0.0,
      );
    });
  });

  group('normalizeOrderTypeValue', () {
    test('empty or "null" string → restaurant_pickup default', () {
      expect(ReceiptBuilderService.normalizeOrderTypeValue(''),
          'restaurant_pickup');
      expect(ReceiptBuilderService.normalizeOrderTypeValue('null'),
          'restaurant_pickup');
    });

    test('pickup synonyms collapse to restaurant_pickup', () {
      for (final v in const [
        'pickup',
        'takeaway',
        'take_away',
        'restaurant_takeaway',
        'restaurant_take_away',
      ]) {
        expect(ReceiptBuilderService.normalizeOrderTypeValue(v),
            'restaurant_pickup',
            reason: '$v should map to restaurant_pickup');
      }
    });

    test('dine-in synonyms collapse to restaurant_internal', () {
      for (final v in const [
        'dine_in',
        'dinein',
        'internal',
        'inside',
        'restaurant_table',
        'table',
      ]) {
        expect(ReceiptBuilderService.normalizeOrderTypeValue(v),
            'restaurant_internal');
      }
    });

    test('delivery synonyms collapse to restaurant_delivery', () {
      for (final v in const [
        'delivery',
        'home_delivery',
        'restaurant_home_delivery',
      ]) {
        expect(ReceiptBuilderService.normalizeOrderTypeValue(v),
            'restaurant_delivery');
      }
    });

    test('parking / drive-through synonyms collapse to restaurant_parking', () {
      for (final v in const [
        'restaurant_parking',
        'parking',
        'drive_through',
        'drive-through',
        'cars',
        'car',
      ]) {
        expect(ReceiptBuilderService.normalizeOrderTypeValue(v),
            'restaurant_parking');
      }
    });

    test('services / service collapse to services', () {
      for (final v in const ['services', 'service', 'restaurant_services']) {
        expect(ReceiptBuilderService.normalizeOrderTypeValue(v), 'services');
      }
    });

    test('unknown input is returned lower-cased unchanged', () {
      expect(ReceiptBuilderService.normalizeOrderTypeValue('SOMETHING_NEW'),
          'something_new');
    });
  });

  group('resolveDeliveryProviderTypeCode', () {
    test('returns null when menu list is inactive', () {
      expect(
        ReceiptBuilderService.resolveDeliveryProviderTypeCode(
          isMenuListActive: false,
          activeMenuListName: 'HungerStation',
          menuListPriceType: 'delivery',
        ),
        isNull,
      );
    });

    test('returns null when the active menu name is empty', () {
      expect(
        ReceiptBuilderService.resolveDeliveryProviderTypeCode(
          isMenuListActive: true,
          activeMenuListName: '',
          menuListPriceType: 'delivery',
        ),
        isNull,
      );
    });

    test('English name "HungerStation" → hungerstation_<suffix>', () {
      expect(
        ReceiptBuilderService.resolveDeliveryProviderTypeCode(
          isMenuListActive: true,
          activeMenuListName: 'HungerStation Menu',
          menuListPriceType: 'delivery',
        ),
        'hungerstation_delivery',
      );
      expect(
        ReceiptBuilderService.resolveDeliveryProviderTypeCode(
          isMenuListActive: true,
          activeMenuListName: 'HungerStation',
          menuListPriceType: 'pickup',
        ),
        'hungerstation_pickup',
      );
    });

    test('Arabic name "هنقر ستيشن" detected as hungerstation', () {
      expect(
        ReceiptBuilderService.resolveDeliveryProviderTypeCode(
          isMenuListActive: true,
          activeMenuListName: 'هنقر ستيشن',
          menuListPriceType: 'delivery',
        ),
        'hungerstation_delivery',
      );
    });

    test('Arabic "طلبات" detected as talabat', () {
      expect(
        ReceiptBuilderService.resolveDeliveryProviderTypeCode(
          isMenuListActive: true,
          activeMenuListName: 'منيو طلبات',
          menuListPriceType: 'delivery',
        ),
        'talabat_delivery',
      );
    });

    test('jahez / gahez / جاهز all map to jahez_<suffix>', () {
      for (final name in const ['Jahez', 'gahez menu', 'منيو جاهز']) {
        expect(
          ReceiptBuilderService.resolveDeliveryProviderTypeCode(
            isMenuListActive: true,
            activeMenuListName: name,
            menuListPriceType: 'pickup',
          ),
          'jahez_pickup',
          reason: 'name=$name should map to jahez_pickup',
        );
      }
    });

    test('unknown provider name → null (caller falls back)', () {
      expect(
        ReceiptBuilderService.resolveDeliveryProviderTypeCode(
          isMenuListActive: true,
          activeMenuListName: 'My Private Menu',
          menuListPriceType: 'delivery',
        ),
        isNull,
      );
    });
  });

  group('normalizePayMethod', () {
    test('null and empty → cash (POS default)', () {
      expect(ReceiptBuilderService.normalizePayMethod(null), 'cash');
      expect(ReceiptBuilderService.normalizePayMethod(''), 'cash');
      expect(ReceiptBuilderService.normalizePayMethod('   '), 'cash');
    });

    test('Arabic substring matches win over compact lookup', () {
      expect(ReceiptBuilderService.normalizePayMethod('بالآجل'), 'pay_later');
      expect(ReceiptBuilderService.normalizePayMethod('مدى'), 'mada');
      expect(ReceiptBuilderService.normalizePayMethod('بطاقة فيزا'), 'card');
      expect(ReceiptBuilderService.normalizePayMethod('نقد'), 'cash');
      expect(ReceiptBuilderService.normalizePayMethod('تابي'), 'tabby');
      expect(ReceiptBuilderService.normalizePayMethod('تمارا'), 'tamara');
      expect(ReceiptBuilderService.normalizePayMethod('شيك'), 'cheque');
      expect(
          ReceiptBuilderService.normalizePayMethod('تحويل بنكي'), 'bank_transfer');
      expect(ReceiptBuilderService.normalizePayMethod('محفظة'), 'wallet');
    });

    test('English / compact synonyms collapse correctly', () {
      const cases = {
        'cash': 'cash',
        'CashPayment': 'cash',
        'petty_cash': 'petty_cash',
        'pay_later': 'pay_later',
        'PostPaid': 'pay_later',
        'deferred': 'pay_later',
        'card': 'card',
        'credit_card': 'card',
        'debit_card': 'card',
        'mada': 'mada',
        'visa': 'visa',
        'mastercard': 'visa',
        'benefit pay': 'benefit',
        'STC Pay': 'stc',
        'bank_transfer': 'bank_transfer',
        'transfer': 'bank_transfer',
        'e-wallet': 'wallet',
        'cheque': 'cheque',
        'check': 'cheque',
        'tabby': 'tabby',
        'taby': 'tabby',
        'tamara': 'tamara',
        'keeta': 'keeta',
        'kita': 'keeta',
        'myfatoorah': 'my_fatoorah',
        'jahez': 'jahez',
        'gahez': 'jahez',
        'talabat': 'talabat',
        'hungerstation': 'hunger_station',
        'hunger': 'hunger_station',
      };
      cases.forEach((input, expected) {
        expect(ReceiptBuilderService.normalizePayMethod(input), expected,
            reason: '"$input" → "$expected"');
      });
    });

    test('unknown values fall back to cash (safe default)', () {
      expect(ReceiptBuilderService.normalizePayMethod('crypto'), 'cash');
      expect(ReceiptBuilderService.normalizePayMethod('xyz'), 'cash');
    });
  });

  group('payMethodArabicLabel', () {
    test('every canonical key has a printable Arabic label', () {
      const canonical = [
        'cash',
        'card',
        'mada',
        'visa',
        'stc',
        'bank_transfer',
        'wallet',
        'cheque',
        'benefit',
        'tabby',
        'tamara',
        'keeta',
        'my_fatoorah',
        'jahez',
        'talabat',
        'hunger_station',
        'petty_cash',
        'pay_later',
      ];
      for (final key in canonical) {
        final label = ReceiptBuilderService.payMethodArabicLabel(key);
        expect(label, isNotEmpty,
            reason: '"$key" must have a printable label');
        expect(label, isNot(key),
            reason: '"$key" should map to a localized label, not the key');
      }
    });

    test('unknown key → input passed through (fallback)', () {
      expect(ReceiptBuilderService.payMethodArabicLabel('custom_xyz'),
          'custom_xyz');
      expect(ReceiptBuilderService.payMethodArabicLabel(''), 'دفع');
    });
  });

  group('buildPaymentMethodLabel', () {
    setUp(() {
      // The label formatter uses ApiConstants.digitsNumber for amount
      // precision. Pin to 2 (Saudi Arabia default) so tests are stable.
      ApiConstants.digitsNumber = 2;
    });

    test('type != "payment" → "دفع لاحق" regardless of pays', () {
      expect(
        ReceiptBuilderService.buildPaymentMethodLabel(
          type: 'deferred',
          pays: const [],
        ),
        'دفع لاحق',
      );
    });

    test('empty pays for a payment-type order → generic "دفع"', () {
      expect(
        ReceiptBuilderService.buildPaymentMethodLabel(
          type: 'payment',
          pays: const [],
        ),
        'دفع',
      );
    });

    test('single payment shows only the label, no amount', () {
      expect(
        ReceiptBuilderService.buildPaymentMethodLabel(
          type: 'payment',
          pays: const [
            {'pay_method': 'cash', 'amount': 50.0}
          ],
        ),
        'نقدي',
      );
    });

    test('split payment shows label and amount for each leg', () {
      final label = ReceiptBuilderService.buildPaymentMethodLabel(
        type: 'payment',
        pays: const [
          {'pay_method': 'cash', 'amount': 30.5},
          {'pay_method': 'مدى', 'amount': 10.0},
        ],
      );
      // Format: "نقدي (30.50) - مدى (10.00)" — exact whitespace + parens
      // matter because the formatted string ends up on the printed receipt.
      expect(label, 'نقدي (30.50) - مدى (10.00)');
    });

    test('split payment falls back gracefully when amount is a string', () {
      final label = ReceiptBuilderService.buildPaymentMethodLabel(
        type: 'payment',
        pays: const [
          {'pay_method': 'cash', 'amount': '12.34'},
          {'pay_method': 'card', 'amount': 'not-a-number'},
        ],
      );
      // First leg parses the string; second leg falls back to 0.00 so
      // the receipt still prints (vs. crashing the print job).
      expect(label, 'نقدي (12.34) - بطاقة (0.00)');
    });
  });
}
