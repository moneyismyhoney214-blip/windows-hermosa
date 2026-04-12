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
    // Step 1: Build cart items
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
    final subtotal = 71.0;
    final tax = 10.65;
    final total = 81.65;

    // Step 2: Update Display App (CDS)
    _displayAppService.updateCartDisplay(
      items: cartItems,
      subtotal: subtotal,
      tax: tax,
      total: total,
      orderNumber: orderNumber,
      orderType: 'dine_in', // or 'take_away', 'delivery'
      note: 'Extra sauce on the side',
    );

    // Step 3: Setup payment callbacks
    _displayAppService.setCallbacks(
      onPaymentSuccess: (transactionData) {
        // Payment successful!
        // Order is automatically sent to KDS by the service
        print('Payment successful! Transaction: $transactionData');
        print('Order sent to kitchen automatically!');

        // Optional: Print receipt
        _printReceipt(orderNumber, total);

        // Optional: Save to database
        _saveOrderToDatabase(orderNumber, cartItems, total);
      },
      onPaymentFailed: (errorMessage) {
        // Payment failed
        print('Payment failed: $errorMessage');
        // Show error to cashier
        // Stay on cart screen for retry
      },
      onPaymentCancelled: () {
        // Customer cancelled
        print('Payment cancelled by customer');
        // Return to cart
      },
      onOrderReady: ({
        required String orderId,
        required String orderNumber,
        required List<Map<String, dynamic>> items,
        double? total,
        String? note,
      }) {
        // This is called when order is sent to KDS
        print('Order $orderNumber sent to kitchen!');
      },
    );

    // Step 4: Start payment (shows "Tap to Pay" on CDS)
    _displayAppService.startPayment(
      amount: total,
      orderNumber: orderNumber,
      customerReference: 'Table 5', // or customer name/number
    );

    // Step 5: Process payment with NearPay SDK
    // (This would be done via NearPay SDK in real implementation)
    // When payment succeeds, call:
    // _displayAppService.notifyPaymentSuccess(transactionData);
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

    // Switch Display to KDS mode
    _displayAppService.setMode(DisplayMode.kds);
  }

  /// Workflow 3: Pay First, Then Kitchen
  ///
  /// For takeaway orders where customer pays before preparation
  void payFirstWorkflow() {
    final orderNumber = '#1029';
    final total = 45.0;

    // 1. Start payment
    _displayAppService.startPayment(
      amount: total,
      orderNumber: orderNumber,
    );

    // 2. Setup callback for success
    _displayAppService.setCallbacks(
      onPaymentSuccess: (transactionData) {
        print('Takeaway payment received!');

        // Now send to kitchen for preparation
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

        // Switch Display to show KDS
        _displayAppService.setMode(DisplayMode.kds);
      },
    );
  }

  /// Workflow 4: Multiple Orders Management
  ///
  /// Handle multiple orders and track their status
  void multipleOrdersWorkflow() {
    // Order 1
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

    // When paid, automatically goes to KDS
    _displayAppService.startPayment(
      amount: 20.7,
      orderNumber: '#1030',
    );

    // Later... Order 2
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
    // Mark an order as completed from Cashier side
    _displayAppService.markOrderCompleted('order-id-123');

    // Or mark as ready
    _displayAppService.markOrderReady('order-id-123');
  }

  /// Helper: Print Receipt
  void _printReceipt(String orderNumber, double total) {
    // Implement receipt printing
    print('Printing receipt for $orderNumber: ${total.toStringAsFixed(2)} SAR');
  }

  /// Helper: Save to Database
  void _saveOrderToDatabase(
    String orderNumber,
    List<Map<String, dynamic>> items,
    double total,
  ) {
    // Implement database save
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
      // 1. Generate order number
      final orderNumber = 'ORD-${DateTime.now().millisecondsSinceEpoch}';

      // 2. Show cart on CDS
      _displayAppService.updateCartDisplay(
        items: cartItems,
        subtotal: subtotal,
        tax: tax,
        total: total,
        orderNumber: orderNumber,
        orderType: orderType,
        note: note,
      );

      // 3. Set up callbacks
      _displayAppService.setCallbacks(
        onPaymentSuccess: (transactionData) async {
          // SUCCESS! Payment received
          print('✅ Payment Success!');
          print('Transaction ID: ${transactionData['transactionId']}');
          print('Amount: ${transactionData['amount']}');

          // Order automatically sent to KDS!
          print('🍳 Order sent to kitchen automatically');

          // Clear cart after successful payment
          _displayAppService.clearCart();

          // Reset state
          _isProcessing = false;

          // Show success to cashier
          // (Show snackbar, dialog, etc.)
        },
        onPaymentFailed: (errorMessage) {
          // FAILED
          print('❌ Payment Failed: $errorMessage');
          _isProcessing = false;

          // Show error to cashier
          // Allow retry
        },
        onPaymentCancelled: () {
          // CANCELLED
          print('🚫 Payment Cancelled');
          _isProcessing = false;

          // Return to cart screen
        },
      );

      // 4. Start payment on CDS (shows "Tap to Pay" screen)
      _displayAppService.startPayment(
        amount: total,
        orderNumber: orderNumber,
        customerReference: tableNumber,
      );

      // 5. Now process with NearPay SDK
      // (This is where you integrate with NearPay)
      // await _processNearPayPayment(total);

      // For demo: simulate success after 3 seconds
      await Future.delayed(const Duration(seconds: 3));

      // 6. Notify success (this triggers KDS automatically)
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
