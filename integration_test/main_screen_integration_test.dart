import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/material.dart';
import 'package:hermosa_pos/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Main Screen Core Journey -', () {
    testWidgets('Add items to cart, connect display, and trigger payment', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // 1. Ensure we are on Main Screen / Login successfully (mocked auth via DI if needed)
      expect(find.text('Spanish Latte'), findsWidgets);

      // 2. Add an item to cart
      await tester.tap(find.text('Spanish Latte').first);
      await tester.pumpAndSettle();

      // 3. Verify cart total updated
      expect(find.text('18.00'), findsOneWidget); 
      
      // 4. Open Display Connection Dialog
      await tester.tap(find.byIcon(Icons.monitor));
      await tester.pumpAndSettle();
      
      // 5. Input Mock IP and connect
      await tester.enterText(find.byType(TextField).first, '127.0.0.1');
      await tester.tap(find.text('Connect to CDS'));
      await tester.pumpAndSettle();

      // 6. Trigger Pay with Card
      await tester.tap(find.text('Pay with Card'));
      await tester.pump(); // Fast frame
      
      // 7. Verify we show UI waiting for display response
      expect(find.text('Waiting for customer to tap card...'), findsOneWidget);
    });
  });
}
