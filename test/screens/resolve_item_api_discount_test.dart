import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/models.dart';
import 'package:hermosa_pos/screens/main_screen_parts/payment_process_helpers.dart';

Product _product({double price = 100}) => Product(
      id: '1',
      name: 'Test',
      price: price,
      category: 'cat',
    );

CartItem _item({
  double quantity = 1,
  double discount = 0,
  DiscountType discountType = DiscountType.amount,
  bool isFree = false,
  double price = 100,
}) =>
    CartItem(
      cartId: 'c1',
      product: _product(price: price),
      quantity: quantity,
      discount: discount,
      discountType: discountType,
      isFree: isFree,
    );

OrderDiscountSnapshot _snap({
  double orderDiscount = 0,
  DiscountType orderDiscountType = DiscountType.amount,
  bool isOrderFree = false,
  PromoCode? promo,
  double grossOrderTotal = 100,
}) =>
    OrderDiscountSnapshot(
      orderDiscount: orderDiscount,
      orderDiscountType: orderDiscountType,
      isOrderFree: isOrderFree,
      promo: promo,
      grossOrderTotal: grossOrderTotal,
    );

void main() {
  group('resolveItemApiDiscount', () {
    test('no discount → 0%', () {
      expect(resolveItemApiDiscount(_item(), _snap()), 0);
    });

    test('isFree item → 100%', () {
      expect(resolveItemApiDiscount(_item(isFree: true), _snap()), 100);
    });

    test('item percentage discount returns the percentage clamped to [0,100]', () {
      expect(
        resolveItemApiDiscount(
          _item(discount: 25, discountType: DiscountType.percentage),
          _snap(),
        ),
        25,
      );
      expect(
        resolveItemApiDiscount(
          _item(discount: 150, discountType: DiscountType.percentage),
          _snap(),
        ),
        100,
      );
    });

    test('item amount discount converts to percentage against line total', () {
      // 50% of a 100-price single-quantity item = 50.
      expect(
        resolveItemApiDiscount(
          _item(discount: 50, discountType: DiscountType.amount),
          _snap(),
        ),
        50,
      );
    });

    test('item amount discount with quantity > 1 splits across line total', () {
      // discount=25 on price=100, qty=2 → line=200, pct=12.5.
      expect(
        resolveItemApiDiscount(
          _item(quantity: 2, discount: 25, discountType: DiscountType.amount),
          _snap(),
        ),
        12.5,
      );
    });

    test('isOrderFree short-circuits to 100% regardless of item discount', () {
      expect(
        resolveItemApiDiscount(
          _item(discount: 25, discountType: DiscountType.percentage),
          _snap(isOrderFree: true),
        ),
        100,
      );
    });

    test('item + order discount stack multiplicatively against remaining', () {
      // 20% item + 10% order → 20 + (80 * 10/100) = 28%.
      expect(
        resolveItemApiDiscount(
          _item(discount: 20, discountType: DiscountType.percentage),
          _snap(orderDiscount: 10, orderDiscountType: DiscountType.percentage),
        ),
        28,
      );
    });

    test('order amount discount converts via grossOrderTotal', () {
      // 50 order-discount on 200-gross → 25% order. Item has 0%.
      expect(
        resolveItemApiDiscount(
          _item(),
          _snap(orderDiscount: 50, grossOrderTotal: 200),
        ),
        25,
      );
    });

    test('promo percentage stacks after item + order', () {
      // Item 20%, no order, promo 50% → 20 + (80 * 50/100) = 60.
      const promo = PromoCode(
        id: 'p1',
        code: 'P',
        discount: 50,
        type: DiscountType.percentage,
        isActive: true,
      );
      expect(
        resolveItemApiDiscount(
          _item(discount: 20, discountType: DiscountType.percentage),
          _snap(promo: promo),
        ),
        60,
      );
    });

    test('promo amount uses maxDiscount cap and grossOrderTotal', () {
      // Promo amount=80, cap=40, gross=200 → effective promo=40 → 20%.
      const promo = PromoCode(
        id: 'p1',
        code: 'P',
        discount: 80,
        type: DiscountType.amount,
        maxDiscount: 40,
        isActive: true,
      );
      expect(
        resolveItemApiDiscount(
          _item(),
          _snap(promo: promo, grossOrderTotal: 200),
        ),
        20,
      );
    });

    test('zero gross with order amount discount yields 0% (avoids div-by-zero)', () {
      expect(
        resolveItemApiDiscount(
          _item(),
          _snap(orderDiscount: 50, grossOrderTotal: 0),
        ),
        0,
      );
    });

    test('three-layer stack (item + order + promo) caps at 100', () {
      const promo = PromoCode(
        id: 'p1',
        code: 'P',
        discount: 100,
        type: DiscountType.percentage,
        isActive: true,
      );
      // Item 50%, order 50% (=> 75% after stack), promo 100% (=> 100% cap).
      expect(
        resolveItemApiDiscount(
          _item(discount: 50, discountType: DiscountType.percentage),
          _snap(
            orderDiscount: 50,
            orderDiscountType: DiscountType.percentage,
            promo: promo,
          ),
        ),
        100,
      );
    });
  });
}
