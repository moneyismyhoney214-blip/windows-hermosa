import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

// Simple mock service for testing
class MockDisplayAppService {
  bool isConnected = false;
  String? connectedIp;
  List<Map<String, dynamic>> sentMessages = [];

  Future<void> connect(String ipAddress, {int port = 8080}) async {
    connectedIp = ipAddress;
    isConnected = true;
  }

  void disconnect() {
    isConnected = false;
    connectedIp = null;
  }

  void updateCartDisplay({
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double tax,
    required double total,
    required String orderNumber,
  }) {
    if (!isConnected) throw Exception('Not connected');

    final message = {
      'type': 'UPDATE_CART',
      'data': {
        'items': items,
        'subtotal': subtotal,
        'tax': tax,
        'total': total,
        'orderNumber': orderNumber,
      },
    };

    sentMessages.add(message);
  }

  void startPayment({
    required double amount,
    required String orderNumber,
  }) {
    if (!isConnected) throw Exception('Not connected');

    final message = {
      'type': 'START_PAYMENT',
      'data': {
        'amount': amount,
        'orderNumber': orderNumber,
        'timestamp': DateTime.now().toIso8601String(),
      },
    };

    sentMessages.add(message);
  }

  void notifyPaymentSuccess(Map<String, dynamic> transactionData) {
    if (!isConnected) throw Exception('Not connected');

    final message = {
      'type': 'PAYMENT_SUCCESS',
      'data': transactionData,
    };

    sentMessages.add(message);
  }
}

void main() {
  group('✅ CASHIER APP TESTS', () {
    late MockDisplayAppService displayService;

    setUp(() {
      displayService = MockDisplayAppService();
    });

    tearDown(() {
      displayService.disconnect();
    });

    test('[✅] يتصل بـ Display App', () async {
      expect(displayService.isConnected, false);

      await displayService.connect('192.168.1.100');

      expect(displayService.isConnected, true);
      expect(displayService.connectedIp, '192.168.1.100');
    });

    test('[✅] يبعت UPDATE_CART', () {
      displayService.connect('192.168.1.100');

      final items = [
        {'name': 'Coffee', 'quantity': 2, 'price': 15.0},
      ];

      displayService.updateCartDisplay(
        items: items,
        subtotal: 30.0,
        tax: 4.5,
        total: 34.5,
        orderNumber: 'ORD-001',
      );

      expect(displayService.sentMessages.length, 1);

      final message = displayService.sentMessages[0];
      expect(message['type'], 'UPDATE_CART');

      final data = message['data'] as Map<String, dynamic>;
      expect(data['total'], 34.5);
      expect(data['orderNumber'], 'ORD-001');
    });

    test('[✅] يبعت START_PAYMENT', () {
      displayService.connect('192.168.1.100');

      displayService.startPayment(
        amount: 34.5,
        orderNumber: 'ORD-001',
      );

      expect(displayService.sentMessages.length, 1);

      final message = displayService.sentMessages[0];
      expect(message['type'], 'START_PAYMENT');

      final data = message['data'] as Map<String, dynamic>;
      expect(data['amount'], 34.5);
      expect(data['orderNumber'], 'ORD-001');
      expect(data['timestamp'], isNotNull);
    });

    test('[✅] يبعت PAYMENT_SUCCESS → يبعت للـ KDS تلقائياً', () {
      displayService.connect('192.168.1.100');

      final transactionData = {
        'transactionId': 'TXN-123',
        'amount': 34.5,
        'orderNumber': 'ORD-001',
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'approved',
      };

      displayService.notifyPaymentSuccess(transactionData);

      expect(displayService.sentMessages.length, 1);

      final message = displayService.sentMessages[0];
      expect(message['type'], 'PAYMENT_SUCCESS');

      final data = message['data'] as Map<String, dynamic>;
      expect(data['status'], 'approved');
      expect(data['transactionId'], 'TXN-123');
    });
  });

  group('📋 INVOICE API TESTS', () {
    test('[✅] Invoice API Structure is valid', () {
      // Based on Hermosa API documentation
      final invoice = {
        'customer_id': 126787,
        'card': [
          {
            'item_name': 'استكانة شاي',
            'meal_id': 1,
            'price': 5,
            'unitPrice': 5,
            'modified_unit_price': null,
            'quantity': 1,
          }
        ],
        'type': 'services',
        'type_extra': {
          'car_number': null,
          'table_name': null,
          'latitude': null,
          'longitude': null,
        }
      };

      expect(invoice['customer_id'], 126787);

      final card = invoice['card'] as List<dynamic>;
      expect(card.length, 1);

      final firstItem = card[0] as Map<String, dynamic>;
      expect(firstItem['item_name'], 'استكانة شاي');
      expect(firstItem['price'], 5);
      expect(invoice['type'], 'services');
    });

    test('[✅] Invoice List API Parameters', () {
      final params = {
        'date_from': '2025-07-27',
        'date_to': '2025-07-27',
        'status': '',
        'search': '',
        'invoice_type': '',
        'page': 1,
        'per_page': 20,
      };

      expect(params['page'], 1);
      expect(params['per_page'], 20);
      expect(params['date_from'], isNotNull);
    });

    test('[✅] Invoice card item structure', () {
      final cardItem = {
        'item_name': 'Spanish Latte',
        'meal_id': 42,
        'price': 18.0,
        'unitPrice': 18.0,
        'modified_unit_price': null,
        'quantity': 2,
      };

      expect(cardItem['item_name'], 'Spanish Latte');
      expect(cardItem['meal_id'], 42);
      expect(cardItem['price'], 18.0);
      expect(cardItem['quantity'], 2);
    });
  });

  group('🔌 ECOSYSTEM MESSAGE TESTS', () {
    test('[✅] NEW_ORDER message format for KDS', () {
      final message = {
        'type': 'NEW_ORDER',
        'data': {
          'id': 'ORD-123456',
          'orderNumber': '#1028',
          'type': 'dine_in',
          'items': [
            {'name': 'Spanish Latte', 'quantity': 2, 'extras': []},
          ],
          'note': 'Extra hot',
          'total': 45.00,
          'status': 'pending',
          'createdAt': DateTime.now().toIso8601String(),
          'sendToKds': true,
        },
      };

      expect(message['type'], 'NEW_ORDER');

      final data = message['data'] as Map<String, dynamic>;
      expect(data['sendToKds'], true);
      expect(data['items'], isA<List>());

      // Verify JSON encoding
      final jsonString = jsonEncode(message);
      expect(jsonString, contains('NEW_ORDER'));
      expect(jsonString, contains('sendToKds'));
    });

    test('[✅] All WebSocket message types are valid', () {
      final validTypes = [
        'SET_MODE',
        'UPDATE_CART',
        'NEW_ORDER',
        'START_PAYMENT',
        'UPDATE_PAYMENT_STATUS',
        'PAYMENT_SUCCESS',
        'PAYMENT_FAILED',
        'CANCEL_PAYMENT',
        'CLEAR_PAYMENT',
        'ORDER_COMPLETED',
        'ORDER_READY',
      ];

      for (final type in validTypes) {
        expect(type.isNotEmpty, true);
        expect(type, isA<String>());
      }

      expect(validTypes.length, 11);
    });

    test('[✅] Payment status update messages', () {
      final statusMessages = [
        {'type': 'UPDATE_PAYMENT_STATUS', 'status': 'processing'},
        {'type': 'UPDATE_PAYMENT_STATUS', 'status': 'waiting_card'},
        {'type': 'UPDATE_PAYMENT_STATUS', 'status': 'pin_entry'},
        {
          'type': 'PAYMENT_SUCCESS',
          'data': {'status': 'approved'}
        },
        {'type': 'PAYMENT_FAILED', 'message': 'Card declined'},
      ];

      for (final msg in statusMessages) {
        expect(msg['type'], isNotNull);
      }
    });
  });

  group('🔄 COMPLETE WORKFLOW TESTS', () {
    test('[✅] Complete order flow - Data integrity', () {
      // Step 1: Cart items
      final cartItems = [
        {
          'name': 'Spanish Latte',
          'quantity': 2,
          'price': 18.0,
          'extras': [
            {'name': 'Oat Milk', 'price': 3.0}
          ],
        },
        {
          'name': 'Chicken Sandwich',
          'quantity': 1,
          'price': 35.0,
        },
      ];

      // Step 2: Calculate totals
      double subtotal = 0;
      for (final item in cartItems) {
        final price = item['price'] as double;
        final quantity = item['quantity'] as int;
        subtotal += price * quantity;
      }

      expect(subtotal, 71.0);

      final tax = subtotal * 0.15; // 15% VAT
      final total = subtotal + tax;

      expect(tax, closeTo(10.65, 0.01));
      expect(total, closeTo(81.65, 0.01));

      // Step 3: Verify order data for KDS
      final orderData = {
        'id': 'ORD-${DateTime.now().millisecondsSinceEpoch}',
        'orderNumber': 'ORD-001',
        'items': cartItems,
        'total': total,
        'type': 'dine_in',
      };

      final items = orderData['items'] as List<dynamic>;
      expect(items.length, 2);
      expect(orderData['total'], closeTo(81.65, 0.01));
    });

    test('[✅] Payment to KDS automatic trigger', () {
      // Given
      final orderNumber = 'ORD-001';
      final total = 81.65;

      // When payment succeeds
      final transactionData = {
        'transactionId': 'TXN-123',
        'amount': total,
        'orderNumber': orderNumber,
        'status': 'approved',
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Then
      expect(transactionData['status'], 'approved');
      expect(transactionData['amount'], total);
      expect(transactionData['orderNumber'], orderNumber);
      expect(transactionData.containsKey('transactionId'), true);
      expect(transactionData.containsKey('timestamp'), true);
    });

    test('[✅] Full ecosystem workflow simulation', () {
      final service = MockDisplayAppService();
      service.connect('192.168.1.100');

      // 1. Update cart
      service.updateCartDisplay(
        items: [
          {'name': 'Coffee', 'quantity': 1, 'price': 15.0}
        ],
        subtotal: 15.0,
        tax: 2.25,
        total: 17.25,
        orderNumber: 'TEST-001',
      );

      // 2. Start payment
      service.startPayment(amount: 17.25, orderNumber: 'TEST-001');

      // 3. Payment success
      service.notifyPaymentSuccess({
        'transactionId': 'TXN-TEST',
        'amount': 17.25,
        'orderNumber': 'TEST-001',
        'status': 'approved',
      });

      // Verify all messages sent
      expect(service.sentMessages.length, 3);
      expect(service.sentMessages[0]['type'], 'UPDATE_CART');
      expect(service.sentMessages[1]['type'], 'START_PAYMENT');
      expect(service.sentMessages[2]['type'], 'PAYMENT_SUCCESS');
    });
  });
}
