import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/controllers/cart_controller.dart';
import 'package:hermosa_pos/controllers/order_totals_calculator.dart';
import 'package:hermosa_pos/models.dart';

/// CartController is the new single-owner of cart state. These tests pin
/// the invariants the rest of the app depends on:
///   * mutations notify listeners exactly once per call
///   * gross / net / grand math matches the receipt the customer sees
///   * order-free wipes the totals regardless of per-item discounts
///   * removing the last item leaves the cart truly empty (no ghost data)
///
/// Anything the controller can't represent (network calls, customer
/// lookups, table reservations) is intentionally out of scope — those
/// stay in screen-level handlers.

CartItem _line({
  String cartId = 'a',
  double price = 10.0,
  double quantity = 1,
  double discount = 0,
  DiscountType discountType = DiscountType.amount,
  bool isFree = false,
}) {
  final p = Product(id: cartId, name: cartId, price: price, category: 'cat');
  return CartItem(
    cartId: cartId,
    product: p,
    quantity: quantity,
    discount: discount,
    discountType: discountType,
    isFree: isFree,
  );
}

void main() {
  group('CartController — line operations', () {
    test('starts empty, gross is zero, listener silent', () {
      final c = CartController();
      var notified = 0;
      c.addListener(() => notified++);

      expect(c.isEmpty, isTrue);
      expect(c.lineCount, 0);
      expect(c.gross, 0);
      expect(notified, 0);
    });

    test('addItem appends, notifies once, and exposes the list as readonly', () {
      final c = CartController();
      var notified = 0;
      c.addListener(() => notified++);

      c.addItem(_line(cartId: 'a'));
      expect(c.lineCount, 1);
      expect(notified, 1);
      expect(
        () => c.items.add(_line(cartId: 'b')),
        throwsUnsupportedError,
        reason: 'items getter must be unmodifiable',
      );
    });

    test('updateQuantity adjusts by delta and notifies', () {
      final c = CartController()..addItem(_line(cartId: 'a', quantity: 2));
      var notified = 0;
      c.addListener(() => notified++);

      final found = c.updateQuantity('a', 3);
      expect(found, isTrue);
      expect(c.items.first.quantity, 5);
      expect(notified, 1);
    });

    test('updateQuantity clamps to minimum 1 — zero or negative becomes 1', () {
      final c = CartController()..addItem(_line(cartId: 'a', quantity: 2));
      c.updateQuantity('a', -10);
      expect(c.items.first.quantity, 1);
    });

    test('updateQuantity on missing cartId is a safe no-op', () {
      final c = CartController()..addItem(_line(cartId: 'a'));
      var notified = 0;
      c.addListener(() => notified++);

      expect(c.updateQuantity('ghost', 1), isFalse);
      expect(notified, 0);
    });

    test('setQuantity overwrites and clamps to minimum 1', () {
      final c = CartController()..addItem(_line(cartId: 'a'));
      c.setQuantity('a', 4.5);
      expect(c.items.first.quantity, 4.5);
      c.setQuantity('a', 0);
      expect(c.items.first.quantity, 1);
    });

    test('removeItem deletes and notifies; missing id is no-op', () {
      final c = CartController()..addItem(_line(cartId: 'a'));
      var notified = 0;
      c.addListener(() => notified++);

      expect(c.removeItem('ghost'), isFalse);
      expect(notified, 0);
      expect(c.removeItem('a'), isTrue);
      expect(c.isEmpty, isTrue);
      expect(notified, 1);
    });

    test('toggleLineFree flips and notifies', () {
      final c = CartController()..addItem(_line(cartId: 'a'));
      var notified = 0;
      c.addListener(() => notified++);

      c.toggleLineFree('a');
      expect(c.items.first.isFree, isTrue);
      c.toggleLineFree('a');
      expect(c.items.first.isFree, isFalse);
      expect(notified, 2);
    });

    test('updateLineDiscount clamps negatives to 0 and overwrites type', () {
      final c = CartController()..addItem(_line(cartId: 'a'));
      c.updateLineDiscount('a', -5, DiscountType.percentage);
      expect(c.items.first.discount, 0);
      expect(c.items.first.discountType, DiscountType.percentage);
    });
  });

  group('CartController — totals math', () {
    test('gross is the sum of CartItem.totalPrice across all lines', () {
      final c = CartController()
        ..addItem(_line(cartId: 'a', price: 10, quantity: 2))
        ..addItem(_line(cartId: 'b', price: 4, quantity: 1));
      expect(c.gross, 24.0);
    });

    test('isOrderFree forces gross to zero', () {
      final c = CartController()
        ..addItem(_line(cartId: 'a', price: 10, quantity: 2))
        ..setOrderFree(true);
      expect(c.gross, 0);
      expect(c.net, 0);
      expect(c.totals.grand, 0);
    });

    test('amount order discount reduces net, clamped to gross', () {
      final c = CartController()
        ..addItem(_line(cartId: 'a', price: 100, quantity: 1))
        ..setOrderDiscount(30, type: DiscountType.amount);
      expect(c.net, 70.0);

      c.setOrderDiscount(9999, type: DiscountType.amount);
      expect(c.net, 0.0, reason: 'over-discount must clamp at gross');
    });

    test('percentage order discount converts before clamping', () {
      final c = CartController()
        ..addItem(_line(cartId: 'a', price: 200, quantity: 1))
        ..setOrderDiscount(25, type: DiscountType.percentage);
      expect(c.net, 150.0);

      c.setOrderDiscount(150, type: DiscountType.percentage);
      expect(c.net, 0.0, reason: 'over-100% must clamp at 100% (=gross)');
    });

    test('grand total uses the injected OrderTotalsCalculator (15% VAT)', () {
      final c = CartController(
        totals: const OrderTotalsCalculator(isTaxEnabled: true, taxRate: 0.15),
      )..addItem(_line(cartId: 'a', price: 100, quantity: 1));
      // gross 100, no discount, tax 15, grand 115.
      expect(c.totals.net, 100);
      expect(c.totals.tax, closeTo(15, 0.001));
      expect(c.totals.grand, closeTo(115, 0.001));
    });
  });

  group('CartController — order-level state', () {
    test('clear empties items + resets discount/promo/free and notifies once',
        () {
      final c = CartController()
        ..addItem(_line(cartId: 'a'))
        ..setOrderDiscount(5)
        ..setOrderFree(true);
      var notified = 0;
      c.addListener(() => notified++);

      c.clear();
      expect(c.isEmpty, isTrue);
      expect(c.orderDiscount, 0);
      expect(c.activePromoCode, isNull);
      expect(c.isOrderFree, isFalse);
      expect(notified, 1);
    });

    test('setOrderDiscount no-ops when value+type unchanged (no notify spam)',
        () {
      final c = CartController()..setOrderDiscount(10);
      var notified = 0;
      c.addListener(() => notified++);

      c.setOrderDiscount(10);
      c.setOrderDiscount(10);
      expect(notified, 0);
    });

    test('clearPromoCode is a no-op when no promo was applied', () {
      final c = CartController();
      var notified = 0;
      c.addListener(() => notified++);

      c.clearPromoCode();
      expect(notified, 0);
    });
  });
}
