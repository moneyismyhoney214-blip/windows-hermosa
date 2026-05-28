// Pure helpers extracted from `_processPayment` in
// `main_screen.payment.process.dart` as part of the phase-decomposition
// refactor (audit_2026_05_19.md → R7/R8). Everything here is
// side-effect-free and depends only on the shared `models.dart` types so
// it can be unit-tested in isolation — no Flutter, no services, no
// `_MainScreenState`.

import 'dart:core';

import 'package:hermosa_pos/models.dart' show CartItem, DiscountType, PromoCode;

/// Result of parsing a `createBooking` backend response — the values
/// `_processPayment` needs from the booking step before it can proceed
/// to invoice creation, KDS dispatch and printing.
class ParsedBookingResponse {
  /// The booking id (the only required field — null indicates the
  /// backend didn't return one, which is treated as a failure).
  final String? orderId;

  /// Optional `order.id` (booking has a separate `order_id` on some
  /// account configurations).
  final String? backendOrderId;

  /// Optional daily-order-number used in receipt headers.
  final String? backendDailyOrderNumber;

  /// Daily-order-number normalized for display (`#N`), falling back to
  /// `backendOrderId` then `orderId` when the daily counter is missing.
  /// Empty string when [orderId] is null (caller should short-circuit
  /// before reading this).
  final String displayOrderRef;

  /// `booking_products[].id` values for downstream invoice variants.
  final List<Object?> bookingProductIds;

  /// Full `booking_products` rows, normalized to `Map<String, dynamic>`.
  final List<Map<String, dynamic>> bookingProductsData;

  /// Full `booking_meals` (restaurant) + `booking_services` (salon)
  /// rows, normalized to `Map<String, dynamic>`.
  final List<Map<String, dynamic>> bookingMealsData;

  /// The `data` subtree of the original response (so callers can read
  /// `customer_id`, `table`, etc. without re-parsing).
  final Map<String, dynamic>? bookingDataMap;

  /// `bookingDataMap['booking']`, normalized.
  final Map<String, dynamic>? bookingNode;

  /// `bookingDataMap['order']`, normalized.
  final Map<String, dynamic>? orderNode;

  const ParsedBookingResponse({
    required this.orderId,
    required this.backendOrderId,
    required this.backendDailyOrderNumber,
    required this.displayOrderRef,
    required this.bookingProductIds,
    required this.bookingProductsData,
    required this.bookingMealsData,
    required this.bookingDataMap,
    required this.bookingNode,
    required this.orderNode,
  });
}

/// Extract the booking ids + nested data the post-booking phase reads
/// from a `createBooking` response. Pure; safe to unit-test in isolation.
ParsedBookingResponse parseBookingResponse(
  Map<String, dynamic> bookingResponse,
) {
  final bookingDataResponse = bookingResponse['data'];
  final bookingDataMap = asStringKeyMap(bookingDataResponse);
  final bookingNode = asStringKeyMap(bookingDataMap?['booking']);
  final orderNode = asStringKeyMap(bookingDataMap?['order']);

  final orderId = firstNonEmptyText([
    bookingNode?['id'],
    bookingDataMap?['booking_id'],
    bookingDataMap?['id'],
  ]);
  final backendOrderId = firstNonEmptyText(
    [
      orderNode?['id'],
      bookingDataMap?['order_id'],
      bookingNode?['order_id'],
    ],
    allowZero: false,
  );
  final backendDailyOrderNumber = firstNonEmptyText(
    [
      bookingNode?['daily_order_number'],
      orderNode?['order_number'],
      bookingDataMap?['daily_order_number'],
      bookingDataMap?['order_number'],
      bookingNode?['order_number'],
    ],
    allowZero: false,
  );

  final bookingProductIds = <Object?>[];
  final bookingProductsData = <Map<String, dynamic>>[];
  final bookingMealsData = <Map<String, dynamic>>[];

  if (bookingDataResponse is Map) {
    final bookingProducts = bookingDataResponse['booking_products'];
    if (bookingProducts is List) {
      for (final p in bookingProducts) {
        final productMap = asStringKeyMap(p);
        if (productMap != null) {
          bookingProductsData.add(productMap);
          if (productMap['id'] != null) {
            bookingProductIds.add(productMap['id']);
          }
        }
      }
    }

    // Restaurant `booking_meals` and salon `booking_services` both feed
    // the same downstream consumers.
    final bookingMeals = bookingDataResponse['booking_meals'];
    if (bookingMeals is List) {
      for (final m in bookingMeals) {
        final mealMap = asStringKeyMap(m);
        if (mealMap != null) bookingMealsData.add(mealMap);
      }
    }
    final bookingServices = bookingDataResponse['booking_services'];
    if (bookingServices is List) {
      for (final s in bookingServices) {
        final sMap = asStringKeyMap(s);
        if (sMap != null) bookingMealsData.add(sMap);
      }
    }
  }

  final displayOrderRef = orderId == null
      ? ''
      : normalizeDisplayOrderRef(
          firstNonEmptyText(
                [backendDailyOrderNumber, backendOrderId, orderId],
                allowZero: false,
              ) ??
              orderId,
        );

  return ParsedBookingResponse(
    orderId: orderId,
    backendOrderId: backendOrderId,
    backendDailyOrderNumber: backendDailyOrderNumber,
    displayOrderRef: displayOrderRef,
    bookingProductIds: bookingProductIds,
    bookingProductsData: bookingProductsData,
    bookingMealsData: bookingMealsData,
    bookingDataMap: bookingDataMap,
    bookingNode: bookingNode,
    orderNode: orderNode,
  );
}

/// Snapshot of the order-level discount state captured at the moment
/// `_processPayment` starts, so item discounts compute against stable
/// values even if the live state changes mid-flight (e.g. `_clearCart()`
/// resets the order-level discount).
class OrderDiscountSnapshot {
  final double orderDiscount;
  final DiscountType orderDiscountType;
  final bool isOrderFree;
  final PromoCode? promo;
  final double grossOrderTotal;

  const OrderDiscountSnapshot({
    required this.orderDiscount,
    required this.orderDiscountType,
    required this.isOrderFree,
    required this.promo,
    required this.grossOrderTotal,
  });
}

/// Backend API accepts only per-item discount fields, so order-level and
/// promo discounts must be folded into each item's effective percentage.
/// Discounts stack multiplicatively against the remaining un-discounted
/// portion of the line: a 20% item discount followed by a 10% order
/// discount yields `20 + (80 * 10/100) = 28%`, not a flat 30%.
double resolveItemApiDiscount(
  CartItem item,
  OrderDiscountSnapshot snapshot,
) {
  double itemPct = 0;
  if (item.isFree) {
    itemPct = 100;
  } else if (item.discount > 0) {
    if (item.discountType == DiscountType.percentage) {
      itemPct = item.discount.clamp(0, 100).toDouble();
    } else {
      final basePrice = item.product.price +
          item.selectedExtras.fold<double>(0, (s, e) => s + e.price);
      final qty = item.quantity < 1 ? 1.0 : item.quantity;
      final lineTotal = basePrice * qty;
      itemPct = lineTotal > 0
          ? (item.discount / lineTotal * 100).clamp(0, 100).toDouble()
          : 0;
    }
  }

  if (snapshot.isOrderFree) {
    return 100;
  }

  if (snapshot.orderDiscount > 0) {
    double orderPct;
    if (snapshot.orderDiscountType == DiscountType.percentage) {
      orderPct = snapshot.orderDiscount.clamp(0, 100).toDouble();
    } else {
      orderPct = snapshot.grossOrderTotal > 0
          ? (snapshot.orderDiscount / snapshot.grossOrderTotal * 100)
              .clamp(0, 100)
              .toDouble()
          : 0;
    }
    final remainAfterItem = 100 - itemPct;
    itemPct = (itemPct + remainAfterItem * orderPct / 100)
        .clamp(0, 100)
        .toDouble();
  }

  final promo = snapshot.promo;
  if (promo != null) {
    double promoPct;
    if (promo.type == DiscountType.percentage) {
      promoPct = promo.discount.clamp(0, 100).toDouble();
    } else {
      double promoAmount = promo.discount;
      if (promo.maxDiscount != null && promoAmount > promo.maxDiscount!) {
        promoAmount = promo.maxDiscount!;
      }
      promoPct = snapshot.grossOrderTotal > 0
          ? (promoAmount / snapshot.grossOrderTotal * 100)
              .clamp(0, 100)
              .toDouble()
          : 0;
    }
    final remainAfterPrev = 100 - itemPct;
    itemPct = (itemPct + remainAfterPrev * promoPct / 100)
        .clamp(0, 100)
        .toDouble();
  }

  return itemPct;
}

/// Coerces an untyped `Map` into a `Map<String, dynamic>`, returning `null`
/// for non-map inputs.
Map<String, dynamic>? asStringKeyMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return null;
}

/// Returns the first value in [values] whose string form is non-empty and
/// not the literal `"null"`. When [allowZero] is false, strings that parse
/// to integer zero (with an optional leading `#`) are also skipped.
String? firstNonEmptyText(
  List<dynamic> values, {
  bool allowZero = true,
}) {
  for (final value in values) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      continue;
    }
    if (!allowZero) {
      final normalized = text.startsWith('#') ? text.substring(1) : text;
      final parsed = int.tryParse(normalized);
      if (parsed != null && parsed == 0) {
        continue;
      }
    }
    return text;
  }
  return null;
}

/// Prefixes a numeric order reference with `#` for display, leaving
/// already-prefixed or non-numeric values untouched.
String normalizeDisplayOrderRef(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return value;
  if (value.startsWith('#')) return value;
  if (RegExp(r'^\d+$').hasMatch(value)) return '#$value';
  return value;
}

/// Detects backend 422 messages that indicate the promo code has expired,
/// in Arabic or English. Used to drop the promo and retry without it.
bool isExpiredPromoMessage(String message) {
  final normalized = message.trim().toLowerCase();
  if (normalized.isEmpty) return false;
  final hasPromoToken = normalized.contains('برومو') ||
      normalized.contains('promo') ||
      normalized.contains('promocode');
  final hasExpiredToken = normalized.contains('انتهت') ||
      normalized.contains('منتهي') ||
      normalized.contains('صلاحية') ||
      normalized.contains('expire');
  return hasPromoToken && hasExpiredToken;
}

/// Best-effort `int` coercion for backend payloads where numeric fields
/// may arrive as `int`, `num`, or stringly-typed.
int toSafeInt(dynamic value, {int fallback = 1}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

/// Best-effort `double` coercion for backend payloads where numeric
/// fields may arrive as `num` or stringly-typed.
double toSafeDouble(dynamic value, {double fallback = 0.0}) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

/// Copies an untyped pays list (from a backend payload or local cache)
/// into a fresh `List<Map<String, dynamic>>` so callers can mutate it
/// without aliasing the original.
List<Map<String, dynamic>> clonePaysList(dynamic rawPays) {
  if (rawPays is! List) return <Map<String, dynamic>>[];
  return rawPays
      .whereType<Map>()
      .map((entry) => entry.map((k, v) => MapEntry(k.toString(), v)))
      .toList();
}

/// Sums the `amount` field across a normalized pays list, returning a
/// value rounded to [digits] decimals. Negative or non-numeric amounts
/// are skipped — they always come from malformed payloads.
double sumPaysAmounts(
  List<Map<String, dynamic>> pays, {
  int digits = 2,
}) {
  var sum = 0.0;
  for (final pay in pays) {
    final raw = pay['amount'];
    final amount = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '') ?? 0.0;
    if (amount <= 0) continue;
    sum += amount;
  }
  return double.parse(sum.toStringAsFixed(digits));
}

/// Extracts the expected pays total from a backend 422 message of the
/// shape `"... (123.45)"`. Returns null when no `(number)` group exists.
double? extractExpectedPaysTotalFromMessage(String message) {
  final match = RegExp(r'\(([\d.]+)\)').firstMatch(message);
  if (match == null) return null;
  final raw = match.group(1);
  if (raw == null || raw.isEmpty) return null;
  return double.tryParse(raw);
}

/// Recursively walks a booking response looking for any value keyed by
/// `booking_product_id`. Used because the backend nests this id in
/// different shapes across salon vs restaurant responses.
dynamic extractBookingProductId(dynamic node) {
  if (node is Map) {
    if (node['booking_product_id'] != null) {
      return node['booking_product_id'];
    }
    for (final value in node.values) {
      final found = extractBookingProductId(value);
      if (found != null) return found;
    }
  } else if (node is List) {
    for (final item in node) {
      final found = extractBookingProductId(item);
      if (found != null) return found;
    }
  }
  return null;
}

/// Removes the promo-related keys from an in-flight invoice payload
/// (used when the backend rejects the promo and we retry without it).
void stripPromoFieldsFromPayload(Map<String, dynamic> payload) {
  payload.remove('promocode_id');
  payload.remove('promocodeValue');
  payload.remove('promocode_name');
  payload.remove('discount_type');
}

/// Probes a calculate-invoice response (salon or restaurant shape) for
/// the expected total. Returns [fallback] when the response holds no
/// positive total. Salon responses nest the value under `data.invoice.*`;
/// restaurant responses use `data.total`. When [isSalonMode] is true the
/// salon shape is consulted first.
double extractExpectedInvoiceTotal(
  dynamic response,
  double fallback, {
  required bool isSalonMode,
}) {
  if (response is! Map) return fallback;
  final map = response.map((k, v) => MapEntry(k.toString(), v));
  final dataMap = map['data'] is Map ? (map['data'] as Map) : null;
  final invoiceMap = dataMap != null && dataMap['invoice'] is Map
      ? dataMap['invoice'] as Map
      : null;
  final candidates = <dynamic>[
    map['total'],
    map['invoice_total'],
    map['grand_total'],
    if (isSalonMode) ...[
      if (invoiceMap != null) invoiceMap['total'],
      if (invoiceMap != null) invoiceMap['invoice_total'],
      if (invoiceMap != null) invoiceMap['grand_total'],
      if (dataMap != null) dataMap['total'],
      if (dataMap != null) dataMap['invoice_total'],
      if (dataMap != null) dataMap['grand_total'],
      if (dataMap != null) dataMap['total_with_tax'],
    ] else ...[
      if (dataMap != null) dataMap['total'],
      if (dataMap != null) dataMap['invoice_total'],
      if (dataMap != null) dataMap['grand_total'],
      if (dataMap != null) dataMap['total_with_tax'],
      if (invoiceMap != null) invoiceMap['total'],
      if (invoiceMap != null) invoiceMap['invoice_total'],
      if (invoiceMap != null) invoiceMap['grand_total'],
    ],
  ];
  for (final c in candidates) {
    double? value;
    if (c is num) {
      value = c.toDouble();
    } else if (c is String) {
      value = double.tryParse(c);
    }
    if (value != null && value > 0) return value;
  }
  return fallback;
}
