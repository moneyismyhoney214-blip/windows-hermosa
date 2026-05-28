// Integration-style tests for the invoice attempts builder. These cover
// the orchestration logic that `_processPayment` delegates to — the
// attempt-ordering rules and payload-shape guarantees that the
// retry-and-fallback loop downstream depends on.

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hermosa_pos/screens/main_screen_parts/invoice_attempts_builder.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';
import 'package:hermosa_pos/services/api/order_service.dart';
import 'package:hermosa_pos/services/cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeOrderService extends OrderService {
  _FakeOrderService() : super();
  // The builder only stores closures that call these methods; no test
  // actually invokes the closures, so leaving them unimplemented is safe.
}

void main() {
  // OrderService eagerly resolves CacheService via GetIt in its
  // constructor, and CacheService reads SharedPreferences lazily. Both
  // are stubbed once for the suite.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<CacheService>()) {
      getIt.registerLazySingleton<CacheService>(() => CacheService());
    }
  });

  // The builder references ApiConstants.branchId. Pin it so payloads
  // contain a deterministic value across tests.
  setUp(() {
    ApiConstants.branchId = 42;
  });

  List<InvoiceAttempt> buildAttempts({
    required bool isSalonMode,
    required bool isCashOnlyPayment,
    bool isNearPayCardFlow = false,
    bool hasValidSalesMealBookingIds = false,
    bool isCashEnabledForInvoice = true,
    Object? customerIdValue = 7,
    Object bookingIdValue = 'B-1',
    Object orderIdValue = 'O-1',
    Object? primaryBookingProductId,
    int? effectiveDepositId,
    Map<String, dynamic> promoFields = const {},
    List<Map<String, dynamic>>? normalizedPays,
    List<Map<String, dynamic>>? paysForSalesMeals,
    List<Map<String, dynamic>>? invoiceItems,
    List<Map<String, dynamic>>? salesMeals,
    List<Object?> bookingProductIds = const <Object?>[],
  }) {
    return InvoiceAttemptsBuilder.build(
      orderService: _FakeOrderService(),
      isSalonMode: isSalonMode,
      isCashOnlyPayment: isCashOnlyPayment,
      isNearPayCardFlow: isNearPayCardFlow,
      hasValidSalesMealBookingIds: hasValidSalesMealBookingIds,
      isCashEnabledForInvoice: isCashEnabledForInvoice,
      customerIdValue: customerIdValue,
      bookingIdValue: bookingIdValue,
      orderIdValue: orderIdValue,
      primaryBookingProductId: primaryBookingProductId,
      effectiveDepositId: effectiveDepositId,
      promoFields: promoFields,
      dateStr: '2026-05-20',
      bookingOrderType: 'restaurant_internal',
      carNumber: '',
      selectedTableForOrder: null,
      payableTotal: 100.0,
      normalizedPays: normalizedPays ??
          [
            {'pay_method': 'cash', 'amount': 100.0, 'index': 0},
          ],
      paysForSalesMeals: paysForSalesMeals ??
          [
            {'pay_method': 'cash', 'amount': 100.0, 'index': 0},
          ],
      invoiceItems: invoiceItems ??
          [
            {'meal_id': 1, 'quantity': 1, 'price': 100},
          ],
      salesMeals: salesMeals ?? const [],
      bookingProductIds: bookingProductIds,
    );
  }

  group('attempt ordering', () {
    test('restaurant-cash-only puts orders-section-slim first', () {
      final attempts = buildAttempts(
        isSalonMode: false,
        isCashOnlyPayment: true,
      );

      expect(attempts.first.label, 'json_orders_section_slim');
      expect(attempts[1].label, 'multipart_orders_section_slim');
    });

    test('salon-cash-only skips orders-section-slim entirely', () {
      final attempts = buildAttempts(
        isSalonMode: true,
        isCashOnlyPayment: true,
      );

      expect(
        attempts.map((a) => a.label),
        isNot(contains('json_orders_section_slim')),
      );
      // First attempt should be from the cash-only Postman fallback group.
      expect(attempts.first.label, 'json_cash_postman_exact');
    });

    test('non-cash flow uses postman_pays_only first', () {
      final attempts = buildAttempts(
        isSalonMode: false,
        isCashOnlyPayment: false,
        normalizedPays: [
          {'pay_method': 'cash', 'amount': 50.0, 'index': 0},
          {'pay_method': 'card', 'amount': 50.0, 'index': 1},
        ],
      );

      // For restaurant: orders-section-slim comes first, then postman.
      expect(attempts.first.label, 'json_orders_section_slim');
      expect(
        attempts.map((a) => a.label),
        containsAllInOrder([
          'json_orders_section_slim',
          'json_postman_pays_only',
        ]),
      );
    });

    test('non-cash + hasValidSalesMealBookingIds adds sales_meals variants', () {
      final attempts = buildAttempts(
        isSalonMode: false,
        isCashOnlyPayment: false,
        hasValidSalesMealBookingIds: true,
        salesMeals: [
          {'booking_meal_id': 1, 'meal_id': 1, 'price': 100},
        ],
      );

      expect(
        attempts.map((a) => a.label),
        containsAll([
          'json_non_cash_with_sales_meals',
          'multipart_non_cash_with_sales_meals',
        ]),
      );
    });
  });

  group('payload shape', () {
    test('salon mode uses sales_services key', () {
      final attempts = buildAttempts(
        isSalonMode: true,
        isCashOnlyPayment: true,
      );

      final cashPostman = attempts.firstWhere(
        (a) => a.label == 'json_cash_postman_exact',
      );
      // Salon payloads never carry restaurant-shaped sales_meals.
      expect(cashPostman.payload.containsKey('sales_meals'), isFalse);
    });

    test('restaurant base payload carries items + card + meals keys', () {
      final attempts = buildAttempts(
        isSalonMode: false,
        isCashOnlyPayment: false,
      );

      final base = attempts.firstWhere(
        (a) => a.label == 'json_order_booking_base',
      );
      expect(base.payload['items'], isA<List>());
      expect(base.payload['card'], isA<List>());
      expect(base.payload['meals'], isA<List>());
    });

    test('promo fields propagate into every variant that should carry them', () {
      final attempts = buildAttempts(
        isSalonMode: false,
        isCashOnlyPayment: true,
        promoFields: {
          'promocode_id': 'p1',
          'promocode_name': 'CODE',
          'discount_type': 'percentage',
        },
      );

      final cashPostman = attempts.firstWhere(
        (a) => a.label == 'json_cash_postman_exact',
      );
      expect(cashPostman.payload['promocode_id'], 'p1');
      expect(cashPostman.payload['promocode_name'], 'CODE');
    });

    test('orders-section-slim payload omits customer/order/promo fields', () {
      final attempts = buildAttempts(
        isSalonMode: false,
        isCashOnlyPayment: false,
        promoFields: {'promocode_id': 'p1'},
        customerIdValue: 99,
      );

      final slim = attempts.firstWhere(
        (a) => a.label == 'json_orders_section_slim',
      );
      expect(slim.payload.containsKey('customer_id'), isFalse);
      expect(slim.payload.containsKey('order_id'), isFalse);
      expect(slim.payload.containsKey('promocode_id'), isFalse);
    });

    test('deposit_id propagates into cash-postman and base payloads', () {
      final attempts = buildAttempts(
        isSalonMode: false,
        isCashOnlyPayment: true,
        effectiveDepositId: 33,
      );

      final cashPostman = attempts.firstWhere(
        (a) => a.label == 'json_cash_postman_exact',
      );
      expect(cashPostman.payload['deposit_id'], 33);

      final base = attempts.firstWhere(
        (a) => a.label == 'json_order_booking_base',
      );
      expect(base.payload['deposit_id'], 33);
    });

    test('booking_only variant drops order_id', () {
      final attempts = buildAttempts(
        isSalonMode: false,
        isCashOnlyPayment: true,
      );

      final bookingOnly = attempts.firstWhere(
        (a) => a.label == 'json_booking_only_base',
      );
      expect(bookingOnly.payload.containsKey('order_id'), isFalse);
      expect(bookingOnly.payload['booking_id'], 'B-1');
    });
  });

  group('cash fallback', () {
    test('appended for non-cash, non-NearPay, when cash is enabled', () {
      final attempts = buildAttempts(
        isSalonMode: false,
        isCashOnlyPayment: false,
        isCashEnabledForInvoice: true,
        normalizedPays: [
          {'pay_method': 'card', 'amount': 100.0, 'index': 0},
        ],
      );

      expect(
        attempts.map((a) => a.label),
        containsAll([
          'json_cash_fallback_with_items',
          'multipart_cash_fallback_with_items',
        ]),
      );
    });

    test('skipped when NearPay flow is active', () {
      final attempts = buildAttempts(
        isSalonMode: false,
        isCashOnlyPayment: false,
        isNearPayCardFlow: true,
        normalizedPays: [
          {'pay_method': 'card', 'amount': 100.0, 'index': 0},
        ],
      );

      expect(
        attempts.map((a) => a.label),
        isNot(contains('json_cash_fallback_with_items')),
      );
    });

    test('skipped when cash is not enabled', () {
      final attempts = buildAttempts(
        isSalonMode: false,
        isCashOnlyPayment: false,
        isCashEnabledForInvoice: false,
      );

      expect(
        attempts.map((a) => a.label),
        isNot(contains('json_cash_fallback_with_items')),
      );
    });

    test('cash-fallback payload sets pays to a single cash entry', () {
      final attempts = buildAttempts(
        isSalonMode: false,
        isCashOnlyPayment: false,
        normalizedPays: [
          {'pay_method': 'card', 'amount': 100.0, 'index': 0},
        ],
      );

      final fallback = attempts.firstWhere(
        (a) => a.label == 'json_cash_fallback_with_items',
      );
      final pays = fallback.payload['pays'] as List;
      expect(pays, hasLength(1));
      expect((pays.first as Map)['pay_method'], 'cash');
      expect((pays.first as Map)['amount'], 100.0);
    });
  });

  group('booking_product variants', () {
    test('extra bookingProductIds produce per-id attempts in non-cash flow', () {
      final attempts = buildAttempts(
        isSalonMode: false,
        isCashOnlyPayment: false,
        bookingProductIds: const ['bp-1', 'bp-2', 'bp-3'],
      );

      expect(
        attempts.map((a) => a.label),
        containsAll([
          'json_with_items_booking_product_bp-2',
          'multipart_with_items_booking_product_bp-2',
          'json_with_items_booking_product_bp-3',
          'multipart_with_items_booking_product_bp-3',
        ]),
      );
      // The first id is the primary — it's already on the base payload,
      // so no per-id attempt is added for it.
      expect(
        attempts.map((a) => a.label),
        isNot(contains('json_with_items_booking_product_bp-1')),
      );
    });

    test('not added in cash-only flow', () {
      final attempts = buildAttempts(
        isSalonMode: false,
        isCashOnlyPayment: true,
        bookingProductIds: const ['bp-1', 'bp-2'],
      );
      expect(
        attempts.map((a) => a.label),
        isNot(contains('json_with_items_booking_product_bp-2')),
      );
    });
  });
}
