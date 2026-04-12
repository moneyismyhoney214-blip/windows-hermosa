import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/Splash/splash_screen.dart';

void main() {
  testWidgets('SplashScreen should not overflow on small screens', (WidgetTester tester) async {
    // Set a very small screen size that previously caused overflow
    // The error report mentioned 329 pixels width
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(isAuthenticated: false),
      ),
    );

    // No overflow should occur
    expect(tester.takeException(), isNull);
    
    // Check if the "HERMOSA" text is present (it's split into individual characters)
    expect(find.text('H'), findsOneWidget);
    expect(find.text('E'), findsOneWidget);
    expect(find.text('R'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.text('O'), findsOneWidget);
    expect(find.text('S'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
  });
}
