// Dev-reference documentation in code form — not imported by running app; print() is intentional.
// ignore_for_file: avoid_print

import '../services/api/api_constants.dart';
import '../services/display_app_service.dart';

/// Example: How to integrate KDS (Kitchen Display System) in Cashier App
///
/// This shows the complete workflow from cart to payment to kitchen

class KDSIntegrationExample {
  final DisplayAppService _displayAppService;

  KDSIntegrationExample(this._displayAppService);

  /// Workflow 1: Standard Order Flow
  ///
  /// 1. Add items to cart
  /// 2. Update Display (CDS)
  /// 3. Customer pays (NearPay)
  /// 4. Order automatically sent to Kitchen (KDS)
  void standardOrderWorkflow() {
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

    final orderNumber = 'ORD-${DateTime.now().millisecondsSinceEpoch}';
    const subtotal = 71.0;
    const tax = 10.65;
    const total = 81.65;

    _displayAppService.updateCartDisplay(
      items: cartItems,
      subtotal: subtotal,
      tax: tax,
      total: total,
      orderNumber: orderNumber,
      orderType: 'dine_in', // or 'take_away', 'delivery'
      note: 'Extra sauce on the side',
    );

    _displayAppService.setCallbacks(
      onPaymentSuccess: (transactionData) {
        print('Payment successful! Transaction: $transactionData');
        print('Order sent to kitchen automatically!');
        _printReceipt(orderNumber, total);
        _saveOrderToDatabase(orderNumber, cartItems, total);
      },
      onPaymentFailed: (errorMessage) {
        print('Payment failed: $errorMessage');
      },
      onPaymentCancelled: () {
        print('Payment cancelled by customer');
      },
      onOrderReady: ({
        required String orderId,
        required String orderNumber,
        required List<Map<String, dynamic>> items,
        double? total,
        String? note,
      }) {
        print('Order $orderNumber sent to kitchen!');
      },
    );

    _displayAppService.startPayment(
      amount: total,
      orderNumber: orderNumber,
      customerReference: 'Table 5',
    );

    // Real impl: call _displayAppService.notifyPaymentSuccess(...) once NearPay confirms.
  }

  /// Workflow 2: Direct to Kitchen (Skip Payment)
  ///
  /// For orders that pay later or have special payment terms
  void directToKitchenWorkflow() {
    final orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch}';

    _displayAppService.sendOrderToKitchen(
      orderId: orderId,
      orderNumber: '#1028',
      orderType: 'dine_in',
      items: [
        {'name': 'V60 Coffee', 'quantity': 1, 'price': 22.0},
        {'name': 'Croissant', 'quantity': 2, 'price': 15.0},
      ],
      note: 'VIP Customer - Rush order',
      total: 52.0,
    );

    _displayAppService.setMode(DisplayMode.kds);
  }

  /// Workflow 3: Pay First, Then Kitchen
  ///
  /// For takeaway orders where customer pays before preparation
  void payFirstWorkflow() {
    const orderNumber = '#1029';
    const total = 45.0;

    _displayAppService.startPayment(
      amount: total,
      orderNumber: orderNumber,
    );

    _displayAppService.setCallbacks(
      onPaymentSuccess: (transactionData) {
        print('Takeaway payment received!');
        _displayAppService.sendOrderToKitchen(
          orderId: 'ORD-${DateTime.now().millisecondsSinceEpoch}',
          orderNumber: orderNumber,
          orderType: 'take_away',
          items: [
            {'name': 'Iced Americano', 'quantity': 1},
            {'name': 'Muffin', 'quantity': 1},
          ],
          total: total,
        );
        _displayAppService.setMode(DisplayMode.kds);
      },
    );
  }

  /// Workflow 4: Multiple Orders Management
  ///
  /// Handle multiple orders and track their status
  void multipleOrdersWorkflow() {
    _displayAppService.updateCartDisplay(
      items: [
        {'name': 'Latte', 'quantity': 1}
      ],
      subtotal: 18.0,
      tax: 2.7,
      total: 20.7,
      orderNumber: '#1030',
      orderType: 'dine_in',
    );

    _displayAppService.startPayment(
      amount: 20.7,
      orderNumber: '#1030',
    );

    Future.delayed(const Duration(minutes: 2), () {
      _displayAppService.updateCartDisplay(
        items: [
          {'name': 'Espresso', 'quantity': 2}
        ],
        subtotal: 24.0,
        tax: 3.6,
        total: 27.6,
        orderNumber: '#1031',
        orderType: 'take_away',
      );

      _displayAppService.startPayment(
        amount: 27.6,
        orderNumber: '#1031',
      );
    });
  }

  /// Workflow 5: Kitchen Status Updates
  ///
  /// Update KDS status from Cashier (optional)
  void kitchenStatusWorkflow() {
    _displayAppService.markOrderCompleted('order-id-123');
    _displayAppService.markOrderReady('order-id-123');
  }

  /// Helper: Print Receipt
  void _printReceipt(String orderNumber, double total) {
    print('Printing receipt for $orderNumber: ${total.toStringAsFixed(ApiConstants.digitsNumber)} SAR');
  }

  /// Helper: Save to Database
  void _saveOrderToDatabase(
    String orderNumber,
    List<Map<String, dynamic>> items,
    double total,
  ) {
    print('Saving order $orderNumber to database');
  }
}

/// Example usage in a screen:
///
/// ```dart
/// class CheckoutScreen extends StatelessWidget {
///   final DisplayAppService displayAppService;
///
///   void _processPayment() {
///     final kdsExample = KDSIntegrationExample(displayAppService);
///     kdsExample.standardOrderWorkflow();
///   }
/// }
/// ```

/// Complete Integration Example
///
/// Put this in your main_screen.dart or checkout flow:

class CompleteKDSIntegration {
  final DisplayAppService _displayAppService;
  bool _isProcessing = false;

  CompleteKDSIntegration(this._displayAppService);

  /// The complete flow from cart to kitchen
  Future<void> completeCheckoutFlow({
    required List<Map<String, dynamic>> cartItems,
    required double subtotal,
    required double tax,
    required double total,
    required String orderType,
    String? note,
    String? tableNumber,
  }) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final orderNumber = 'ORD-${DateTime.now().millisecondsSinceEpoch}';

      _displayAppService.updateCartDisplay(
        items: cartItems,
        subtotal: subtotal,
        tax: tax,
        total: total,
        orderNumber: orderNumber,
        orderType: orderType,
        note: note,
      );

      _displayAppService.setCallbacks(
        onPaymentSuccess: (transactionData) async {
          print('✅ Payment Success!');
          print('Transaction ID: ${transactionData['transactionId']}');
          print('Amount: ${transactionData['amount']}');
          print('🍳 Order sent to kitchen automatically');
          _displayAppService.clearCart();
          _isProcessing = false;
        },
        onPaymentFailed: (errorMessage) {
          print('❌ Payment Failed: $errorMessage');
          _isProcessing = false;
        },
        onPaymentCancelled: () {
          print('🚫 Payment Cancelled');
          _isProcessing = false;
        },
      );

      _displayAppService.startPayment(
        amount: total,
        orderNumber: orderNumber,
        customerReference: tableNumber,
      );

      // Demo: simulate success after 3s. Real impl calls _processNearPayPayment(total).
      await Future.delayed(const Duration(seconds: 3));

      _displayAppService.notifyPaymentSuccess({
        'transactionId': 'TXN-${DateTime.now().millisecondsSinceEpoch}',
        'amount': total,
        'orderNumber': orderNumber,
        'timestamp': DateTime.now().toIso8601String(),
        'paymentMethod': 'nearpay',
        'status': 'approved',
      });
    } catch (e) {
      print('Error in checkout flow: $e');
      _isProcessing = false;

      _displayAppService.notifyPaymentFailed(e.toString());
    }
  }
}

/// Example: Simple Button Implementation
///
/// ```dart
/// ElevatedButton(
///   onPressed: () {
///     final flow = CompleteKDSIntegration(displayAppService);
///     flow.completeCheckoutFlow(
///       cartItems: [
///         {'name': 'Coffee', 'quantity': 2, 'price': 18.0},
///         {'name': 'Sandwich', 'quantity': 1, 'price': 35.0},
///       ],
///       subtotal: 71.0,
///       tax: 10.65,
///       total: 81.65,
///       orderType: 'dine_in',
///       tableNumber: 'Table 5',
///     );
///   },
///   child: Text('Pay & Send to Kitchen'),
/// )
/// ```
