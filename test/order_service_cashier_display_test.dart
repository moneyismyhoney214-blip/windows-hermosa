import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';
import 'package:hermosa_pos/services/api/base_client.dart';
import 'package:hermosa_pos/services/api/order_service.dart';
import 'package:hermosa_pos/services/cache_service.dart';

void main() {
  late BaseClient client;
  late OrderService service;

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    final sl = GetIt.instance;
    sl.allowReassignment = true;
    if (!sl.isRegistered<CacheService>()) {
      sl.registerLazySingleton<CacheService>(() => CacheService());
    }
  });

  setUp(() {
    ApiConstants.branchId = 65;
    client = BaseClient();
    client.setToken('test-token');
    service = OrderService();
  });

  test('createDriveThroughBooking sends correct payload and endpoint',
      () async {
    late Uri capturedUri;
    late Map<String, dynamic> capturedBody;
    late String authHeader;

    client.setClientForTesting(
      MockClient((request) async {
        capturedUri = request.url;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        authHeader = request.headers['authorization'] ?? '';
        return http.Response(
            jsonEncode({
              'data': {'id': 123}
            }),
            200);
      }),
    );

    await service.createDriveThroughBooking(
      customerId: 126787,
      card: const [
        {
          'item_name': 'وجبة',
          'meal_id': 560,
          'price': 80.0,
          'unitPrice': 80.0,
          'quantity': 1,
          'addons': [],
        }
      ],
      carNumber: 'ABC-1234',
      tableName: null,
      latitude: null,
      longitude: null,
    );

    expect(
      capturedUri.path,
      '/seller/branches/65/bookings',
    );
    expect(authHeader, 'Bearer test-token');
    expect(capturedBody['type'], 'restaurant_parking');
    expect(capturedBody['customer_id'], 126787);
    expect(capturedBody['type_extra']['car_number'], 'ABC-1234');
    expect(capturedBody['card'], isA<List>());
  });

  test('createBooking retries delivery payload with fallback coordinates',
      () async {
    var requestCount = 0;
    final capturedBodies = <Map<String, dynamic>>[];

    client.setClientForTesting(
      MockClient((request) async {
        requestCount += 1;
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        capturedBodies.add(payload);

        if (requestCount == 1) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'status': 422,
                'message':
                    'الحقل type extra.latitude مطلوب في حال ما إذا كان النوع يساوي restaurant_delivery.',
                'errors': [],
              }),
            ),
            422,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        return http.Response(
          jsonEncode({
            'status': 200,
            'data': {'id': 901},
          }),
          200,
        );
      }),
    );

    final response = await service.createBooking({
      'type': 'restaurant_delivery',
      'date': '2026-02-24',
      'customer_id': 126787,
      'card': const [
        {
          'item_name': 'قهوة عربية',
          'meal_id': 533,
          'price': 15.0,
          'unitPrice': 15.0,
          'quantity': 1,
          'addons': [],
        },
      ],
      'type_extra': {
        'car_number': null,
        'table_name': null,
        'latitude': null,
        'longitude': null,
      },
    });

    expect(requestCount, 2);
    expect(capturedBodies.first['type_extra']['latitude'], isNull);
    expect(capturedBodies.first['type_extra']['longitude'], isNull);
    expect(capturedBodies.last['type_extra']['latitude'], '0');
    expect(capturedBodies.last['type_extra']['longitude'], '0');
    expect((response['data'] as Map)['id'], 901);
  });

  test('createBooking retries with null-safe payload on unhandled null match',
      () async {
    var requestCount = 0;
    final capturedBodies = <Map<String, dynamic>>[];

    client.setClientForTesting(
      MockClient((request) async {
        requestCount += 1;
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        capturedBodies.add(payload);

        if (requestCount == 1) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'status': 500,
                'message': 'Unhandled match case NULL',
              }),
            ),
            500,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        return http.Response(
          jsonEncode({
            'status': 200,
            'data': {'id': 902},
          }),
          200,
        );
      }),
    );

    final response = await service.createBooking({
      'type': 'restaurant_pickup',
      'date': '2026-02-25',
      'customer_id': 126787,
      'card': const [
        {
          'item_name': 'شاي',
          'meal_id': 533,
          'price': 10.0,
          'unitPrice': 10.0,
          'quantity': 1,
          'addons': [],
        },
      ],
      'type_extra': {
        'car_number': null,
        'table_name': null,
        'latitude': null,
        'longitude': null,
      },
    });

    expect(requestCount, 2);
    expect(capturedBodies.first['type_extra']['car_number'], isNull);
    expect(capturedBodies.last['type_extra']['car_number'], '');
    expect(capturedBodies.last['type_extra']['table_name'], '');
    expect(capturedBodies.last['type_extra']['latitude'], '');
    expect(capturedBodies.last['type_extra']['longitude'], '');
    expect((response['data'] as Map)['id'], 902);
  });

  test(
      'updateBookingStatus retries with alternate request format when status field is rejected',
      () async {
    final methods = <String>[];
    final bodies = <String>[];

    client.setClientForTesting(
      MockClient((request) async {
        methods.add(request.method);
        bodies.add(request.body);

        if (request.method == 'PUT') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'status': 422,
                'message': 'The status field is required.',
                'errors': {
                  'status': ['The status field is required.'],
                },
              }),
            ),
            422,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        return http.Response(
          jsonEncode({
            'status': 200,
            'data': {'updated': true},
          }),
          200,
        );
      }),
    );

    final response = await service.updateBookingStatus(
      orderId: '415794',
      status: 2,
    );

    expect((response['data'] as Map)['updated'], true);
    expect(methods, ['PUT', 'PATCH']);
    expect(jsonDecode(bodies[0])['status'], '2');
    expect(jsonDecode(bodies[1])['status'], '2');
  });

  test('updateBookingStatus does not retry non-retryable validation errors',
      () async {
    final methods = <String>[];

    client.setClientForTesting(
      MockClient((request) async {
        methods.add(request.method);
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'status': 422,
              'message': 'The selected status is invalid.',
              'errors': {
                'status': ['The selected status is invalid.'],
              },
            }),
          ),
          422,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await expectLater(
      service.updateBookingStatus(orderId: '415794', status: 9),
      throwsA(
        isA<ApiException>().having((e) => e.statusCode, 'statusCode', 422),
      ),
    );
    expect(methods, ['PUT']);
  });

  test('sendOrderWhatsApp posts expected booking message body', () async {
    late Uri capturedUri;
    late Map<String, dynamic> capturedBody;

    client.setClientForTesting(
      MockClient((request) async {
        capturedUri = request.url;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('', 200);
      }),
    );

    await service.sendOrderWhatsApp(
      orderId: '258469',
      message: 'طلبك جاهز للاستلام',
    );

    expect(capturedUri.path, '/seller/booking/send-whatsapp/258469');
    expect(capturedBody, {'message': 'طلبك جاهز للاستلام'});
  });

  test('sendMultiOrdersWhatsApp posts expected order ids and message body',
      () async {
    late Uri capturedUri;
    late Map<String, dynamic> capturedBody;

    client.setClientForTesting(
      MockClient((request) async {
        capturedUri = request.url;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('', 200);
      }),
    );

    await service.sendMultiOrdersWhatsApp(
      orderIds: const [258469, 258470, 258471],
      message: 'طلباتكم جاهزة',
    );

    expect(capturedUri.path, '/seller/booking/send-multi-whatsapp/65');
    expect(capturedBody['order_ids'], [258469, 258470, 258471]);
    expect(capturedBody.containsKey('booking_ids'), isFalse);
    expect(capturedBody['message'], 'طلباتكم جاهزة');
  });

  test('showBookingRefund hits booking refund show endpoint', () async {
    late Uri capturedUri;
    late String capturedMethod;

    client.setClientForTesting(
      MockClient((request) async {
        capturedUri = request.url;
        capturedMethod = request.method;
        return http.Response(
            jsonEncode({
              'status': 200,
              'data': {'id': 258469}
            }),
            200);
      }),
    );

    await service.showBookingRefund('258469');

    expect(capturedMethod, 'GET');
    expect(capturedUri.path, '/seller/refund/branches/65/bookings/258469');
  });

  test('processBookingRefund hits booking refund process endpoint', () async {
    late Uri capturedUri;
    late String capturedMethod;
    late Map<String, dynamic> capturedBody;

    client.setClientForTesting(
      MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/seller/refund/branches/65/bookings/258469') {
          return http.Response(
            jsonEncode({
              'status': 200,
              'data': {
                'collection': [
                  {'id': 1}
                ]
              }
            }),
            200,
          );
        }
        capturedUri = request.url;
        capturedMethod = request.method;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({
              'status': 200,
              'data': {'refunded': true}
            }),
            200);
      }),
    );

    await service.processBookingRefund(
      orderId: '258469',
      payload: const {'reason': 'customer_request'},
    );

    expect(capturedMethod, 'PATCH');
    expect(capturedUri.path, '/seller/refund/branches/65/bookings/258469');
    expect(capturedBody['reason'], 'customer_request');
    expect(capturedBody['refund_reason'], 'طلب العميل');
    expect(capturedBody['refund'], [1]);
  });

  test('refundInvoice keeps invoice refund endpoint contract', () async {
    late Uri capturedUri;
    late String capturedMethod;

    client.setClientForTesting(
      MockClient((request) async {
        capturedUri = request.url;
        capturedMethod = request.method;
        return http.Response(
            jsonEncode({
              'status': 200,
              'data': {'id': 408465}
            }),
            200);
      }),
    );

    await service.refundInvoice('408465');

    expect(capturedMethod, 'GET');
    expect(capturedUri.path, '/seller/refund/branches/65/invoices/408465');
  });

  test('processInvoiceRefund hits invoice refund process endpoint', () async {
    late Uri capturedUri;
    late String capturedMethod;
    late Map<String, dynamic> capturedBody;

    client.setClientForTesting(
      MockClient((request) async {
        capturedUri = request.url;
        capturedMethod = request.method;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({
              'status': 200,
              'data': {'ok': true}
            }),
            200);
      }),
    );

    await service.processInvoiceRefund(
      invoiceId: '408465',
      payload: const {
        'refund_items': [
          {'item_id': 1, 'quantity': 1}
        ],
      },
    );

    expect(capturedMethod, 'PATCH');
    expect(capturedUri.path, '/seller/refund/branches/65/invoices/408465');
    expect(capturedBody['refund_reason'], 'طلب العميل');
    expect(capturedBody['refund_items'], [
      {'item_id': 1, 'quantity': 1}
    ]);
  });

  test(
      'processInvoiceRefund retries with compatible payload on backend contract mismatch',
      () async {
    final patchBodies = <Map<String, dynamic>>[];
    var refundShowCalls = 0;

    client.setClientForTesting(
      MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path == '/seller/refund/branches/65/invoices/408465') {
          refundShowCalls += 1;
          return http.Response(
            jsonEncode({
              'status': 200,
              'data': {
                'sales_meals': [
                  {
                    'sales_meal_id': 181696,
                    'total': 40.0,
                  }
                ],
                'sales_products': [],
              }
            }),
            200,
          );
        }

        if (request.method == 'PATCH' &&
            request.url.path == '/seller/refund/branches/65/invoices/408465') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          patchBodies.add(body);

          if (patchBodies.length == 1) {
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'status': 422,
                  'message': 'الحقل التاريخ مطلوب. (و 1 حقل إضافي)',
                  'errors': {
                    'date': ['الحقل التاريخ مطلوب.'],
                    'pays': ['الحقل المدفوعات مطلوب.'],
                  },
                }),
              ),
              422,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }

          return http.Response(
            jsonEncode({
              'status': 200,
              'data': {'ok': true}
            }),
            200,
          );
        }

        return http.Response(
          jsonEncode({'status': 404, 'message': 'unexpected path'}),
          404,
        );
      }),
    );

    final response = await service.processInvoiceRefund(
      invoiceId: '408465',
      payload: const {
        'refund_items': [
          {'item_id': 181696, 'quantity': 1}
        ],
      },
    );

    expect(response['data'], isA<Map>());
    expect(patchBodies.length, 2);
    expect(refundShowCalls, 1);

    final firstBody = patchBodies.first;
    expect(firstBody['refund_items'], [
      {'item_id': 181696, 'quantity': 1}
    ]);

    final secondBody = patchBodies[1];
    expect(secondBody.containsKey('refund_items'), isFalse);
    expect(secondBody['refund_meals'], [181696]);
    expect(secondBody['date'], isA<String>());
    expect(secondBody['pays'], isA<List>());
    final normalizedPays = secondBody['pays'] as List;
    expect(normalizedPays, isNotEmpty);
    final firstPay = normalizedPays.first as Map<String, dynamic>;
    expect(firstPay['pay_method'], 'cash');
    expect((firstPay['amount'] as num).toDouble(), closeTo(40.0, 0.001));
  });

  test('updateInvoiceEmployees uses employees endpoint payload', () async {
    late Uri capturedUri;
    late String capturedMethod;
    late Map<String, dynamic> capturedBody;

    client.setClientForTesting(
      MockClient((request) async {
        capturedUri = request.url;
        capturedMethod = request.method;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({
              'status': 200,
              'data': {'ok': true}
            }),
            200);
      }),
    );

    await service.updateInvoiceEmployees(
      '408465',
      employeeIds: const [1, 2, 3],
    );

    expect(capturedMethod, 'PATCH');
    expect(capturedUri.path, '/seller/employees/branches/65/invoices/408465');
    expect(capturedBody, {
      'employee_ids': [1, 2, 3]
    });
  });

  test('getInvoicePdfWithWhatsApp calls pdf/1 endpoint', () async {
    late Uri capturedUri;
    late String capturedMethod;

    client.setClientForTesting(
      MockClient((request) async {
        capturedUri = request.url;
        capturedMethod = request.method;
        return http.Response(
            jsonEncode({
              'status': 200,
              'pdf_url': '/seller/branches/65/invoices/408465/pdf/1'
            }),
            200);
      }),
    );

    await service.getInvoicePdfWithWhatsApp('408465');

    expect(capturedMethod, 'GET');
    expect(capturedUri.path, '/seller/branches/65/invoices/408465/pdf/1');
  });

  test('sendInvoiceWhatsApp posts invoice_id and branch_id', () async {
    late Uri capturedUri;
    late String capturedMethod;
    late Map<String, dynamic> capturedBody;

    client.setClientForTesting(
      MockClient((request) async {
        capturedUri = request.url;
        capturedMethod = request.method;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({'status': 200, 'message': 'sent'}), 200);
      }),
    );

    await service.sendInvoiceWhatsApp(invoiceId: '408465');

    expect(capturedMethod, 'POST');
    expect(capturedUri.path, '/seller/invoices/send-whatsapp');
    expect(capturedBody['invoice_id'], 408465);
    expect(capturedBody['branch_id'], 65);
  });

  test('createInvoice sends order_id with booking_id compatibility', () async {
    late Map<String, dynamic> capturedBody;

    client.setClientForTesting(
      MockClient((request) async {
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({
              'data': {'id': 5001}
            }),
            200);
      }),
    );

    await service.createInvoice({
      'customer_id': 126787,
      'order_id': 258470,
      'date': '2026-02-20',
      'pays': const [
        {'name': 'دفع نقدي', 'pay_method': 'cash', 'amount': 73.6, 'index': 0}
      ],
      'items': const [
        {'meal_id': 560, 'quantity': 1, 'price': 73.6, 'addons': []}
      ],
    });

    expect(capturedBody['order_id'], 258470);
    expect(capturedBody['booking_id'], 258470);
  });

  test('updateBookingPrintCount posts to print-count endpoint', () async {
    late Uri capturedUri;
    late Map<String, dynamic> capturedBody;

    client.setClientForTesting(
      MockClient((request) async {
        capturedUri = request.url;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({
              'data': {'ok': true}
            }),
            200);
      }),
    );

    await service.updateBookingPrintCount('258469');

    expect(capturedUri.path, '/seller/booking-update-print-count/258469');
    expect(capturedBody, isEmpty);
  });

  test('generateKitchenReceiptByBooking posts expected body and endpoint',
      () async {
    late Uri capturedUri;
    late Map<String, dynamic> capturedBody;

    client.setClientForTesting(
      MockClient((request) async {
        capturedUri = request.url;
        capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({
              'data': {'receipt': 'ok'}
            }),
            200);
      }),
    );

    await service.generateKitchenReceiptByBooking(
      bookingId: '258469',
      kitchenId: 1,
    );

    expect(capturedUri.path, '/seller/kitchen-receipts/generate-by-booking');
    expect(capturedBody['booking_id'], 258469);
    expect(capturedBody['kitchen_id'], 1);
  });
}
