import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/screens/main_screen_parts/payment_process_helpers.dart';

void main() {
  group('asStringKeyMap', () {
    test('returns input unchanged when already typed', () {
      final input = <String, dynamic>{'a': 1};
      expect(asStringKeyMap(input), same(input));
    });

    test('coerces a dynamic-keyed map', () {
      final dynamic input = <dynamic, dynamic>{1: 'one', 'b': 2};
      final result = asStringKeyMap(input);
      expect(result, isA<Map<String, dynamic>>());
      expect(result, {'1': 'one', 'b': 2});
    });

    test('returns null for non-map values', () {
      expect(asStringKeyMap(null), isNull);
      expect(asStringKeyMap('not a map'), isNull);
      expect(asStringKeyMap(42), isNull);
      expect(asStringKeyMap([1, 2, 3]), isNull);
    });
  });

  group('firstNonEmptyText', () {
    test('returns first non-empty trimmed string', () {
      expect(firstNonEmptyText(['', '  ', 'foo', 'bar']), 'foo');
    });

    test('skips literal "null" strings (any case)', () {
      expect(firstNonEmptyText(['null', 'NULL', 'Null', 'real']), 'real');
    });

    test('skips actual null values', () {
      expect(firstNonEmptyText([null, null, 'value']), 'value');
    });

    test('returns null when nothing usable is present', () {
      expect(firstNonEmptyText([]), isNull);
      expect(firstNonEmptyText([null, '', '  ']), isNull);
    });

    test('with allowZero=false, skips strings that parse to integer 0', () {
      expect(firstNonEmptyText(['0', '00', '#0', '5'], allowZero: false), '5');
    });

    test('with allowZero=false, non-numeric strings still pass through', () {
      expect(firstNonEmptyText(['0', 'abc'], allowZero: false), 'abc');
    });

    test('with default allowZero=true, "0" is returned', () {
      expect(firstNonEmptyText(['0', '5']), '0');
    });

    test('coerces non-string values via toString', () {
      expect(firstNonEmptyText([42, 'fallback']), '42');
    });
  });

  group('normalizeDisplayOrderRef', () {
    test('prefixes pure-numeric strings with #', () {
      expect(normalizeDisplayOrderRef('123'), '#123');
    });

    test('leaves already-prefixed values untouched', () {
      expect(normalizeDisplayOrderRef('#42'), '#42');
    });

    test('leaves alphanumeric values untouched', () {
      expect(normalizeDisplayOrderRef('ORDER-5'), 'ORDER-5');
    });

    test('trims whitespace before checking', () {
      expect(normalizeDisplayOrderRef('  77  '), '#77');
    });

    test('returns empty string when input is empty', () {
      expect(normalizeDisplayOrderRef(''), '');
      expect(normalizeDisplayOrderRef('   '), '');
    });
  });

  group('isExpiredPromoMessage', () {
    test('detects Arabic expired-promo message', () {
      expect(
        isExpiredPromoMessage('انتهت صلاحية برومو الخصم'),
        isTrue,
      );
    });

    test('detects English expired-promo message', () {
      expect(isExpiredPromoMessage('Promo code has expired'), isTrue);
    });

    test('returns false for empty input', () {
      expect(isExpiredPromoMessage(''), isFalse);
      expect(isExpiredPromoMessage('   '), isFalse);
    });

    test('returns false when only the promo token is present', () {
      expect(isExpiredPromoMessage('Promo code invalid'), isFalse);
    });

    test('returns false when only the expired token is present', () {
      expect(isExpiredPromoMessage('Session expired'), isFalse);
    });
  });

  group('toSafeInt', () {
    test('returns int input verbatim', () {
      expect(toSafeInt(7), 7);
    });

    test('truncates num input', () {
      expect(toSafeInt(7.9), 7);
    });

    test('parses numeric strings', () {
      expect(toSafeInt('42'), 42);
    });

    test('returns fallback for unparseable strings', () {
      expect(toSafeInt('abc', fallback: 99), 99);
    });

    test('returns fallback for null/other types', () {
      expect(toSafeInt(null, fallback: 3), 3);
      expect(toSafeInt(<String, dynamic>{}, fallback: 3), 3);
    });
  });

  group('toSafeDouble', () {
    test('returns double from num input', () {
      expect(toSafeDouble(7), 7.0);
      expect(toSafeDouble(7.5), 7.5);
    });

    test('parses numeric strings', () {
      expect(toSafeDouble('3.14'), 3.14);
    });

    test('returns fallback for unparseable strings', () {
      expect(toSafeDouble('xx', fallback: 1.5), 1.5);
    });

    test('returns fallback for null/other types', () {
      expect(toSafeDouble(null, fallback: -1.0), -1.0);
    });
  });

  group('clonePaysList', () {
    test('returns empty list for non-list input', () {
      expect(clonePaysList(null), isEmpty);
      expect(clonePaysList('not a list'), isEmpty);
    });

    test('coerces dynamic-keyed map entries', () {
      final dynamic raw = [
        <dynamic, dynamic>{'pay_method': 'cash', 'amount': 50},
        <dynamic, dynamic>{1: 'one'},
      ];
      final result = clonePaysList(raw);
      expect(result, hasLength(2));
      expect(result[0], {'pay_method': 'cash', 'amount': 50});
      expect(result[1], {'1': 'one'});
    });

    test('skips non-map entries', () {
      final dynamic raw = [
        {'pay_method': 'cash'},
        'invalid',
        42,
      ];
      expect(clonePaysList(raw), hasLength(1));
    });

    test('produces independent copies', () {
      final src = [
        {'pay_method': 'cash', 'amount': 10},
      ];
      final cloned = clonePaysList(src);
      cloned.first['amount'] = 999;
      expect(src.first['amount'], 10);
    });
  });

  group('sumPaysAmounts', () {
    test('sums positive amounts and rounds to digits', () {
      final pays = <Map<String, dynamic>>[
        {'amount': 10.123},
        {'amount': 20.456},
      ];
      expect(sumPaysAmounts(pays), 30.58);
    });

    test('honours custom digits', () {
      final pays = <Map<String, dynamic>>[
        {'amount': 1.111},
        {'amount': 2.222},
      ];
      expect(sumPaysAmounts(pays, digits: 3), 3.333);
    });

    test('skips non-positive and unparseable amounts', () {
      final pays = <Map<String, dynamic>>[
        {'amount': 10},
        {'amount': 0},
        {'amount': -5},
        {'amount': 'oops'},
      ];
      expect(sumPaysAmounts(pays), 10.0);
    });

    test('accepts stringly-typed amounts', () {
      final pays = <Map<String, dynamic>>[
        {'amount': '12.5'},
        {'amount': '7.25'},
      ];
      expect(sumPaysAmounts(pays), 19.75);
    });

    test('returns 0 for empty input', () {
      expect(sumPaysAmounts(const []), 0.0);
    });
  });

  group('extractExpectedPaysTotalFromMessage', () {
    test('extracts a parenthesized total', () {
      expect(
        extractExpectedPaysTotalFromMessage('Expected total (123.45) was off'),
        123.45,
      );
    });

    test('returns first match when multiple parens present', () {
      expect(
        extractExpectedPaysTotalFromMessage('first (10.0) then (20.0)'),
        10.0,
      );
    });

    test('returns null when no parenthesized number is present', () {
      expect(extractExpectedPaysTotalFromMessage('plain error'), isNull);
    });

    test('returns null on empty body inside parens', () {
      expect(extractExpectedPaysTotalFromMessage('()'), isNull);
    });
  });

  group('extractBookingProductId', () {
    test('finds id at the top level of a map', () {
      expect(
        extractBookingProductId({'booking_product_id': 42}),
        42,
      );
    });

    test('finds id nested deep inside maps and lists', () {
      final node = {
        'data': {
          'items': [
            {'unrelated': 1},
            {
              'inner': {'booking_product_id': 'BP-7'},
            },
          ],
        },
      };
      expect(extractBookingProductId(node), 'BP-7');
    });

    test('returns null when the key is absent', () {
      expect(extractBookingProductId({'foo': 1}), isNull);
      expect(extractBookingProductId([1, 2, {'a': 'b'}]), isNull);
      expect(extractBookingProductId(null), isNull);
      expect(extractBookingProductId('scalar'), isNull);
    });

    test('returns first match in traversal order', () {
      final node = [
        {'booking_product_id': 'first'},
        {'booking_product_id': 'second'},
      ];
      expect(extractBookingProductId(node), 'first');
    });
  });

  group('stripPromoFieldsFromPayload', () {
    test('removes all promo-related keys', () {
      final payload = <String, dynamic>{
        'promocode_id': 'p1',
        'promocodeValue': 'CODE',
        'promocode_name': 'CODE',
        'discount_type': 'percentage',
        'amount': 100,
      };
      stripPromoFieldsFromPayload(payload);
      expect(payload, {'amount': 100});
    });

    test('is a no-op when keys are absent', () {
      final payload = <String, dynamic>{'amount': 50};
      stripPromoFieldsFromPayload(payload);
      expect(payload, {'amount': 50});
    });
  });

  group('parseBookingResponse', () {
    test('extracts ids from nested booking + order nodes', () {
      final result = parseBookingResponse({
        'data': {
          'booking': {
            'id': 'B-1',
            'daily_order_number': 7,
          },
          'order': {
            'id': 99,
            'order_number': 5,
          },
        },
      });
      expect(result.orderId, 'B-1');
      expect(result.backendOrderId, '99');
      expect(result.backendDailyOrderNumber, '7');
      expect(result.displayOrderRef, '#7');
    });

    test('falls back to booking_id and id keys for orderId', () {
      final result = parseBookingResponse({
        'data': {'booking_id': 42},
      });
      expect(result.orderId, '42');
      expect(result.displayOrderRef, '#42');
    });

    test('returns null orderId + empty displayOrderRef when nothing present', () {
      final result = parseBookingResponse({'data': <String, dynamic>{}});
      expect(result.orderId, isNull);
      expect(result.displayOrderRef, '');
    });

    test('extracts booking_products ids + rows', () {
      final result = parseBookingResponse({
        'data': {
          'booking': {'id': 'B-1'},
          'booking_products': [
            {'id': 1, 'name': 'a'},
            {'id': 2, 'name': 'b'},
            {'no_id': true},
          ],
        },
      });
      expect(result.bookingProductIds, [1, 2]);
      expect(result.bookingProductsData, hasLength(3));
    });

    test('merges booking_meals (restaurant) and booking_services (salon)', () {
      final result = parseBookingResponse({
        'data': {
          'booking': {'id': 'B-1'},
          'booking_meals': [
            {'id': 10, 'meal_id': 100},
          ],
          'booking_services': [
            {'id': 20, 'service_id': 200},
          ],
        },
      });
      expect(result.bookingMealsData, hasLength(2));
      expect(result.bookingMealsData[0]['meal_id'], 100);
      expect(result.bookingMealsData[1]['service_id'], 200);
    });

    test('displayOrderRef prefers daily over order id', () {
      final result = parseBookingResponse({
        'data': {
          'booking': {'id': 'B-1', 'daily_order_number': 99},
          'order': {'id': 5},
        },
      });
      expect(result.displayOrderRef, '#99');
    });

    test('displayOrderRef falls through to orderId when daily missing', () {
      final result = parseBookingResponse({
        'data': {
          'booking': {'id': 'B-1'},
        },
      });
      expect(result.displayOrderRef, 'B-1');
    });
  });

  group('extractExpectedInvoiceTotal', () {
    test('reads top-level total field', () {
      final response = {'total': 200};
      expect(
        extractExpectedInvoiceTotal(response, 0.0, isSalonMode: false),
        200.0,
      );
    });

    test('reads restaurant-shaped data.total ahead of invoice.total', () {
      final response = {
        'data': {
          'total': 150,
          'invoice': {'total': 999},
        },
      };
      expect(
        extractExpectedInvoiceTotal(response, 0.0, isSalonMode: false),
        150.0,
      );
    });

    test('reads salon-shaped data.invoice.total ahead of data.total', () {
      final response = {
        'data': {
          'total': 999,
          'invoice': {'total': 175},
        },
      };
      expect(
        extractExpectedInvoiceTotal(response, 0.0, isSalonMode: true),
        175.0,
      );
    });

    test('coerces string totals', () {
      final response = {'data': {'total': '42.50'}};
      expect(
        extractExpectedInvoiceTotal(response, 0.0, isSalonMode: false),
        42.5,
      );
    });

    test('falls back when no positive total present', () {
      final response = {'data': {'total': 0}};
      expect(
        extractExpectedInvoiceTotal(response, 99.0, isSalonMode: false),
        99.0,
      );
    });

    test('falls back when response is not a map', () {
      expect(
        extractExpectedInvoiceTotal('garbage', 17.0, isSalonMode: false),
        17.0,
      );
      expect(
        extractExpectedInvoiceTotal(null, 17.0, isSalonMode: false),
        17.0,
      );
    });
  });
}
