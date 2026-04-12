import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/models.dart';

void main() {
  group('PromoCode.fromJson parsing', () {
    test('parses fixed discount payload from Postman contract', () {
      final promo = PromoCode.fromJson({
        'id': 55,
        'code': 'WELCOME50',
        'discount_type': 'fixed',
        'discount_value': 50,
      });

      expect(promo.id, '55');
      expect(promo.code, 'WELCOME50');
      expect(promo.discount, 50.0);
      expect(promo.type, DiscountType.amount);
    });

    test('parses localized code map and percentage discount', () {
      final promo = PromoCode.fromJson({
        'promocode_id': '99',
        'promocode_name': {'ar': 'SUMMER2025', 'en': 'SUMMER2025'},
        'discountType': 'percentage',
        'discount_value': '20',
      });

      expect(promo.id, '99');
      expect(promo.code, 'SUMMER2025');
      expect(promo.discount, 20.0);
      expect(promo.type, DiscountType.percentage);
    });

    test('accepts fallback promocodeValue with percent token', () {
      final promo = PromoCode.fromJson({
        'id': '12',
        'promocodeValue': 'VIP10',
        'type': '%',
        'value': '10',
      });

      expect(promo.id, '12');
      expect(promo.code, 'VIP10');
      expect(promo.discount, 10.0);
      expect(promo.type, DiscountType.percentage);
    });
  });
}
