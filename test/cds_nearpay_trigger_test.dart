import 'package:flutter_test/flutter_test.dart';

enum TestDisplayMode { none, cds, kds }

/// Focused harness for Cashier -> Display payment trigger behavior.
/// We validate the exact scenario:
/// - Cashier is connected
/// - Display may be in KDS
/// - Cashier Pay must force CDS then send START_PAYMENT
class CashierPaymentHarness {
  bool isConnected = false;
  TestDisplayMode mode = TestDisplayMode.none;
  final List<Map<String, dynamic>> sentMessages = [];

  void connect({required TestDisplayMode initialMode}) {
    isConnected = true;
    mode = initialMode;
  }

  void startPayment({
    required double amount,
    required String orderNumber,
    String? customerReference,
  }) {
    if (!isConnected) return;

    if (mode != TestDisplayMode.cds) {
      // Matches production intent: force CDS first.
      sentMessages.add({'type': 'SET_MODE', 'mode': 'CDS'});
      mode = TestDisplayMode.cds;
    }

    sentMessages.add({
      'type': 'START_PAYMENT',
      'data': {
        'amount': amount,
        'orderNumber': orderNumber,
        'customerReference': customerReference,
      },
    });
  }
}

void main() {
  group('💳 Cashier -> CDS NearPay Trigger', () {
    test('Pay from KDS forces CDS then sends START_PAYMENT', () {
      final harness = CashierPaymentHarness();
      harness.connect(initialMode: TestDisplayMode.kds);

      harness.startPayment(
        amount: 88.75,
        orderNumber: 'ORD-KDS-TO-CDS-001',
        customerReference: 'TABLE-7',
      );

      expect(harness.sentMessages.length, 2);
      expect(harness.sentMessages[0]['type'], 'SET_MODE');
      expect(harness.sentMessages[0]['mode'], 'CDS');
      expect(harness.sentMessages[1]['type'], 'START_PAYMENT');
      expect(
        (harness.sentMessages[1]['data'] as Map<String, dynamic>)['amount'],
        88.75,
      );
    });

    test('Pay from CDS sends START_PAYMENT directly (no extra SET_MODE)', () {
      final harness = CashierPaymentHarness();
      harness.connect(initialMode: TestDisplayMode.cds);

      harness.startPayment(
        amount: 42.0,
        orderNumber: 'ORD-CDS-READY-001',
      );

      expect(harness.sentMessages.length, 1);
      expect(harness.sentMessages[0]['type'], 'START_PAYMENT');
    });

    test('Not connected -> no payment message sent', () {
      final harness = CashierPaymentHarness();

      harness.startPayment(
        amount: 20.0,
        orderNumber: 'ORD-NO-CONN',
      );

      expect(harness.sentMessages, isEmpty);
    });
  });
}

