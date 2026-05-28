// Prioritised invoice-creation attempts for `_processPayment`. Each variant exists to satisfy a payload shape some account has 422'd on; append new variants with a comment for the failure mode they unlock.

import 'package:hermosa_pos/models.dart' show TableItem;
import 'package:hermosa_pos/services/api/api_constants.dart';
import 'package:hermosa_pos/services/api/order_service.dart';

class InvoiceAttempt {
  final String label;
  final Future<Map<String, dynamic>> Function() run;
  final Map<String, dynamic> payload;

  const InvoiceAttempt({
    required this.label,
    required this.run,
    required this.payload,
  });
}

class InvoiceAttemptsBuilder {
  // Named args keep the call-site declarative (vs. ~20 positional params).
  static List<InvoiceAttempt> build({
    required OrderService orderService,
    required bool isSalonMode,
    required bool isCashOnlyPayment,
    required bool isNearPayCardFlow,
    required bool hasValidSalesMealBookingIds,
    required bool isCashEnabledForInvoice,
    required Object? customerIdValue,
    required Object bookingIdValue,
    required Object orderIdValue,
    required Object? primaryBookingProductId,
    required int? effectiveDepositId,
    required Map<String, dynamic> promoFields,
    required String dateStr,
    required String bookingOrderType,
    required String carNumber,
    required TableItem? selectedTableForOrder,
    required double payableTotal,
    required List<Map<String, dynamic>> normalizedPays,
    required List<Map<String, dynamic>> paysForSalesMeals,
    required List<Map<String, dynamic>> invoiceItems,
    required List<Map<String, dynamic>> salesMeals,
    required List<Object?> bookingProductIds,
  }) {
    final depositField = effectiveDepositId != null
        ? <String, dynamic>{'deposit_id': effectiveDepositId}
        : <String, dynamic>{};

    final invoiceDataBase = <String, dynamic>{
      if (customerIdValue != null) 'customer_id': customerIdValue,
      'branch_id': ApiConstants.branchId,
      'order_id': orderIdValue,
      'booking_id': bookingIdValue,
      if (primaryBookingProductId != null && !isSalonMode)
        'booking_product_id': primaryBookingProductId,
      if (effectiveDepositId != null) 'deposit_id': effectiveDepositId,
      ...promoFields,
      'cash_back': 0,
      'date': dateStr,
      'pays': normalizedPays,
      if (isSalonMode)
        'sales_services': invoiceItems
      else ...{
        'items': invoiceItems,
        'card': invoiceItems,
        'meals': invoiceItems,
        if (hasValidSalesMealBookingIds) 'sales_meals': salesMeals,
      },
    };
    final invoiceDataBookingOnly =
        Map<String, dynamic>.from(invoiceDataBase)..remove('order_id');

    final invoiceDataCashPostman = <String, dynamic>{
      if (customerIdValue != null) 'customer_id': customerIdValue,
      'branch_id': ApiConstants.branchId,
      'booking_id': bookingIdValue,
      'date': dateStr,
      'pays': normalizedPays,
      ...promoFields,
      ...depositField,
    };

    // Shape from the known-good orders-section flow (see orders_screen.data.dart); tried first on restaurant.
    final invoiceDataOrdersSectionSlim = <String, dynamic>{
      'branch_id': ApiConstants.branchId,
      'booking_id': bookingIdValue,
      'date': dateStr,
      'cash_back': 0,
      'pays': normalizedPays,
      if (!isSalonMode && hasValidSalesMealBookingIds)
        'sales_meals': salesMeals,
    };

    final invoiceDataCashWithSalesMeals = <String, dynamic>{
      if (customerIdValue != null) 'customer_id': customerIdValue,
      'branch_id': ApiConstants.branchId,
      'booking_id': bookingIdValue,
      'date': dateStr,
      'pays': paysForSalesMeals,
      ...promoFields,
      ...depositField,
      if (isSalonMode)
        'sales_services': invoiceItems
      else ...{
        if (hasValidSalesMealBookingIds) 'sales_meals': salesMeals,
        if (!hasValidSalesMealBookingIds) 'items': invoiceItems,
      },
    };

    final invoiceDataPostmanPaysOnly = <String, dynamic>{
      if (customerIdValue != null) 'customer_id': customerIdValue,
      'branch_id': ApiConstants.branchId,
      'booking_id': bookingIdValue,
      'date': dateStr,
      'pays': normalizedPays,
      ...promoFields,
      ...depositField,
    };

    final invoiceDataBackendExact = <String, dynamic>{
      if (customerIdValue != null) 'customer_id': customerIdValue,
      'branch_id': ApiConstants.branchId,
      'booking_id': bookingIdValue,
      'date': dateStr,
      'pays': paysForSalesMeals,
      ...depositField,
      if (isSalonMode)
        'sales_services': invoiceItems
      else if (hasValidSalesMealBookingIds)
        'sales_meals': salesMeals,
    };

    final invoiceDataWithItems = <String, dynamic>{
      ...invoiceDataBase,
      // Some accounts require items payload even with order_id.
      'items': invoiceItems,
      'card': invoiceItems,
      'meals': invoiceItems,
      if (hasValidSalesMealBookingIds) 'sales_meals': salesMeals,
    };
    final invoiceDataWithItemsBookingOnly =
        Map<String, dynamic>.from(invoiceDataWithItems)..remove('order_id');

    final invoiceDataLegacyCard = <String, dynamic>{
      if (customerIdValue != null) 'customer_id': customerIdValue,
      'branch_id': ApiConstants.branchId,
      'date': dateStr,
      'card': invoiceItems,
      'pays': normalizedPays,
      ...promoFields,
      'type': bookingOrderType,
      'type_extra': {
        'car_number': carNumber.isEmpty ? null : carNumber,
        'table_name': selectedTableForOrder?.number,
        'latitude': null,
        'longitude': null,
      },
    };

    final attempts = <InvoiceAttempt>[];

    // Restaurant: known-good slim payload first; fall through on reject.
    if (!isSalonMode) {
      attempts.add(InvoiceAttempt(
        label: 'json_orders_section_slim',
        run: () => orderService.createInvoice(invoiceDataOrdersSectionSlim),
        payload: invoiceDataOrdersSectionSlim,
      ));
      attempts.add(InvoiceAttempt(
        label: 'multipart_orders_section_slim',
        run: () =>
            orderService.createInvoiceMultipart(invoiceDataOrdersSectionSlim),
        payload: invoiceDataOrdersSectionSlim,
      ));
    }

    if (isCashOnlyPayment) {
      if (hasValidSalesMealBookingIds) {
        attempts.addAll([
          InvoiceAttempt(
            label: 'json_cash_with_sales_meals',
            run: () => orderService.createInvoice(invoiceDataCashWithSalesMeals),
            payload: invoiceDataCashWithSalesMeals,
          ),
          InvoiceAttempt(
            label: 'multipart_backend_exact',
            run: () => orderService.createInvoiceMultipart(invoiceDataBackendExact),
            payload: invoiceDataBackendExact,
          ),
          InvoiceAttempt(
            label: 'multipart_cash_with_sales_meals',
            run: () =>
                orderService.createInvoiceMultipart(invoiceDataCashWithSalesMeals),
            payload: invoiceDataCashWithSalesMeals,
          ),
        ]);
      }
      // Cashier-cash flow stays closest to Postman contract as fallback.
      attempts.addAll([
        InvoiceAttempt(
          label: 'json_cash_postman_exact',
          run: () => orderService.createInvoice(invoiceDataCashPostman),
          payload: invoiceDataCashPostman,
        ),
        InvoiceAttempt(
          label: 'multipart_cash_postman_exact',
          run: () => orderService.createInvoiceMultipart(invoiceDataCashPostman),
          payload: invoiceDataCashPostman,
        ),
        InvoiceAttempt(
          label: 'json_postman_pays_only',
          run: () => orderService.createInvoice(invoiceDataPostmanPaysOnly),
          payload: invoiceDataPostmanPaysOnly,
        ),
        InvoiceAttempt(
          label: 'json_booking_only_base',
          run: () => orderService.createInvoice(invoiceDataBookingOnly),
          payload: invoiceDataBookingOnly,
        ),
        InvoiceAttempt(
          label: 'json_order_booking_base',
          run: () => orderService.createInvoice(invoiceDataBase),
          payload: invoiceDataBase,
        ),
      ]);
    } else {
      if (hasValidSalesMealBookingIds) {
        attempts.addAll([
          InvoiceAttempt(
            label: 'json_non_cash_with_sales_meals',
            run: () => orderService.createInvoice(invoiceDataCashWithSalesMeals),
            payload: invoiceDataCashWithSalesMeals,
          ),
          InvoiceAttempt(
            label: 'multipart_non_cash_with_sales_meals',
            run: () =>
                orderService.createInvoiceMultipart(invoiceDataCashWithSalesMeals),
            payload: invoiceDataCashWithSalesMeals,
          ),
        ]);
      }
      attempts.addAll([
        InvoiceAttempt(
          label: 'json_postman_pays_only',
          run: () => orderService.createInvoice(invoiceDataPostmanPaysOnly),
          payload: invoiceDataPostmanPaysOnly,
        ),
        InvoiceAttempt(
          label: 'multipart_postman_pays_only',
          run: () => orderService.createInvoiceMultipart(invoiceDataPostmanPaysOnly),
          payload: invoiceDataPostmanPaysOnly,
        ),
        InvoiceAttempt(
          label: 'json_order_booking_base',
          run: () => orderService.createInvoice(invoiceDataBase),
          payload: invoiceDataBase,
        ),
        InvoiceAttempt(
          label: 'json_booking_only_base',
          run: () => orderService.createInvoice(invoiceDataBookingOnly),
          payload: invoiceDataBookingOnly,
        ),
        InvoiceAttempt(
          label: 'json_order_booking_with_items',
          run: () => orderService.createInvoice(invoiceDataWithItems),
          payload: invoiceDataWithItems,
        ),
        InvoiceAttempt(
          label: 'json_booking_only_with_items',
          run: () => orderService.createInvoice(invoiceDataWithItemsBookingOnly),
          payload: invoiceDataWithItemsBookingOnly,
        ),
        InvoiceAttempt(
          label: 'multipart_order_booking_with_items',
          run: () => orderService.createInvoiceMultipart(invoiceDataWithItems),
          payload: invoiceDataWithItems,
        ),
        InvoiceAttempt(
          label: 'multipart_booking_only_with_items',
          run: () =>
              orderService.createInvoiceMultipart(invoiceDataWithItemsBookingOnly),
          payload: invoiceDataWithItemsBookingOnly,
        ),
        InvoiceAttempt(
          label: 'json_legacy_card_payload',
          run: () => orderService.createInvoice(invoiceDataLegacyCard),
          payload: invoiceDataLegacyCard,
        ),
        InvoiceAttempt(
          label: 'multipart_legacy_card_payload',
          run: () => orderService.createInvoiceMultipart(invoiceDataLegacyCard),
          payload: invoiceDataLegacyCard,
        ),
      ]);
    }

    if (!isCashOnlyPayment && bookingProductIds.length > 1) {
      for (final bookingProductId in bookingProductIds.skip(1)) {
        final withSpecificBookingProduct =
            Map<String, dynamic>.from(invoiceDataWithItems)
              ..['booking_product_id'] = bookingProductId;
        attempts.add(InvoiceAttempt(
          label: 'json_with_items_booking_product_$bookingProductId',
          run: () => orderService.createInvoice(withSpecificBookingProduct),
          payload: withSpecificBookingProduct,
        ));
        attempts.add(InvoiceAttempt(
          label: 'multipart_with_items_booking_product_$bookingProductId',
          run: () =>
              orderService.createInvoiceMultipart(withSpecificBookingProduct),
          payload: withSpecificBookingProduct,
        ));
      }
    }

    if (!isNearPayCardFlow && !isCashOnlyPayment && isCashEnabledForInvoice) {
      final fallbackInvoiceData = <String, dynamic>{
        ...invoiceDataWithItems,
        'pays': [
          {
            'name': 'دفع نقدي',
            'pay_method': 'cash',
            'amount': payableTotal,
            'index': 0,
          },
        ],
      };
      attempts.add(InvoiceAttempt(
        label: 'json_cash_fallback_with_items',
        run: () => orderService.createInvoice(fallbackInvoiceData),
        payload: fallbackInvoiceData,
      ));

      final fallbackInvoiceDataBookingOnly = <String, dynamic>{
        ...invoiceDataWithItemsBookingOnly,
        'pays': [
          {
            'name': 'دفع نقدي',
            'pay_method': 'cash',
            'amount': payableTotal,
            'index': 0,
          },
        ],
      };
      attempts.add(InvoiceAttempt(
        label: 'multipart_cash_fallback_with_items',
        run: () =>
            orderService.createInvoiceMultipart(fallbackInvoiceDataBookingOnly),
        payload: fallbackInvoiceDataBookingOnly,
      ));
    }

    return attempts;
  }
}
