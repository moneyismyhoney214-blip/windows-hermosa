import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hermosa_pos/dialogs/improved_display_connection_dialog.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Display Connection Dialog Tests', () {
    testWidgets('Dialog should open and show mode selection buttons', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => ImprovedDisplayConnectionDialog(
                        onConnect: (ip, port, mode) {},
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify dialog is open
      expect(find.text('شاشات العرض'), findsOneWidget);
      expect(find.text('إضافة يدوي'), findsOneWidget);

      // Tap "Add Device" button
      await tester.tap(find.text('إضافة يدوي'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify mode selection buttons exist
      expect(find.text('شاشة العملاء\nCDS'), findsOneWidget);
      expect(find.text('شاشة المطبخ\nKDS'), findsOneWidget);
      expect(find.text('إلغاء'), findsOneWidget);
    });

    testWidgets('Mode selection should update UI immediately', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => ImprovedDisplayConnectionDialog(
                        onConnect: (ip, port, mode) {},
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pump(const Duration(milliseconds: 300));

      // Open add device dialog
      await tester.tap(find.text('إضافة يدوي'));
      await tester.pump(const Duration(milliseconds: 300));

      // Enter IP
      await tester.enterText(
        find.byType(TextField).at(1),
        '192.168.1.100',
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Select CDS mode
      await tester.tap(find.text('شاشة العملاء\nCDS'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify selection is highlighted
      expect(find.text('شاشة العملاء\nCDS'), findsOneWidget);

      // Connect button should exist
      expect(find.widgetWithText(ElevatedButton, 'اتصال'), findsOneWidget);
    });

    testWidgets('Connection button should be disabled without mode selection', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => ImprovedDisplayConnectionDialog(
                        onConnect: (ip, port, mode) {},
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pump(const Duration(milliseconds: 300));

      // Open add device dialog
      await tester.tap(find.text('إضافة يدوي'));
      await tester.pump(const Duration(milliseconds: 300));

      // Enter IP only
      await tester.enterText(
        find.byType(TextField).at(1),
        '192.168.1.100',
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Find connect button - should be disabled
      final connectButton = find.widgetWithText(ElevatedButton, 'اتصال');
      expect(connectButton, findsOneWidget);

      // The button should be disabled (onPressed is null)
      final button = tester.widget<ElevatedButton>(connectButton);
      expect(button.onPressed, isNull);
    });

    testWidgets('Complete connection flow - CDS mode', (
      WidgetTester tester,
    ) async {
      String? capturedIp;
      int? capturedPort;
      String? capturedMode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => ImprovedDisplayConnectionDialog(
                        onConnect: (ip, port, mode) {
                          capturedIp = ip;
                          capturedPort = port;
                          capturedMode = mode;
                        },
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pump(const Duration(milliseconds: 300));

      // Open add device dialog
      await tester.tap(find.text('إضافة يدوي'));
      await tester.pump(const Duration(milliseconds: 300));

      // Enter IP
      await tester.enterText(
        find.byType(TextField).at(1),
        '192.168.1.100',
      );

      // Enter device name
      await tester.enterText(
        find.byType(TextField).first,
        'Test Device',
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Select CDS mode
      await tester.tap(find.text('شاشة العملاء\nCDS'));
      await tester.pump(const Duration(milliseconds: 300));

      // Tap connect
      await tester.tap(find.widgetWithText(ElevatedButton, 'اتصال'));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify connection parameters
      expect(capturedIp, equals('192.168.1.100'));
      expect(capturedPort, equals(8080));
      expect(capturedMode, equals('cds'));
    });

    testWidgets('Complete connection flow - KDS mode', (
      WidgetTester tester,
    ) async {
      String? capturedIp;
      String? capturedMode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => ImprovedDisplayConnectionDialog(
                        onConnect: (ip, port, mode) {
                          capturedIp = ip;
                          capturedMode = mode;
                        },
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pump(const Duration(milliseconds: 300));

      // Open add device dialog
      await tester.tap(find.text('إضافة يدوي'));
      await tester.pump(const Duration(milliseconds: 300));

      // Enter IP
      await tester.enterText(
        find.byType(TextField).at(1),
        '192.168.1.50',
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Select KDS mode
      await tester.tap(find.text('شاشة المطبخ\nKDS'));
      await tester.pump(const Duration(milliseconds: 300));

      // Tap connect
      await tester.tap(find.widgetWithText(ElevatedButton, 'اتصال'));
      await tester.pumpAndSettle();

      // Verify connection parameters
      expect(capturedIp, equals('192.168.1.50'));
      expect(capturedMode, equals('kds'));
    });

    testWidgets('Cancel button should close dialog without connecting', (
      WidgetTester tester,
    ) async {
      bool connected = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => ImprovedDisplayConnectionDialog(
                        onConnect: (ip, port, mode) {
                          connected = true;
                        },
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Open add device dialog
      await tester.tap(find.text('إضافة يدوي'));
      await tester.pumpAndSettle();

      // Tap cancel
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      // Verify we're back to main dialog
      expect(find.text('شاشات العرض'), findsOneWidget);

      // Verify no connection was made
      expect(connected, isFalse);
    });
  });
}
