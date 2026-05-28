import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/utils/ui_feedback.dart';

/// Widget tests for `UiFeedback` — the central snackbar/dialog helper
/// that hundreds of call-sites delegate to. These tests pin the contract
/// (mounted-checks, return values, destructive-style switch) so future
/// edits can't quietly break the dialogs.
void main() {
  group('UiFeedback.confirm', () {
    testWidgets('returns true when the user taps the confirm button',
        (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await UiFeedback.confirm(
                  context,
                  title: 'Delete?',
                  message: 'This cannot be undone.',
                  confirmLabel: 'Yes',
                  cancelLabel: 'No',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Delete?'), findsOneWidget);
      expect(find.text('This cannot be undone.'), findsOneWidget);

      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('returns false when the user taps the cancel button',
        (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await UiFeedback.confirm(
                  context,
                  title: 'Delete?',
                  message: 'Sure?',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('returns false when the dialog is dismissed by tap-outside',
        (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await UiFeedback.confirm(
                  context,
                  title: 'X',
                  message: 'Y',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Tap on the barrier (top-left, well outside the dialog).
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(result, isFalse,
          reason: 'null cancel must coerce to false per the contract');
    });

    testWidgets('destructive: styles the confirm button red',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => UiFeedback.confirm(
                context,
                title: 'Delete?',
                message: 'Y',
                confirmLabel: 'Delete',
                destructive: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final btn = tester.widget<TextButton>(
        find.ancestor(of: find.text('Delete'), matching: find.byType(TextButton)),
      );
      final fg = btn.style?.foregroundColor?.resolve({});
      expect(fg, isNotNull);
      // Red shade family — exact shade comes from Colors.red.shade700.
      expect(fg!.r, greaterThan(0.5));
      expect(fg.g, lessThan(0.5));
    });
  });

  group('UiFeedback.error / success / warning / info', () {
    testWidgets('error shows a snackbar with the message', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => UiFeedback.error(context, 'boom'),
              child: const Text('go'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('go'));
      await tester.pump(); // snackbar animation start
      expect(find.text('boom'), findsOneWidget);
    });

    testWidgets('success shows a snackbar with the message', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => UiFeedback.success(context, 'done'),
              child: const Text('go'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.text('done'), findsOneWidget);
    });

    testWidgets('hideCurrentSnackBar is called before each new one',
        (tester) async {
      // Quick fire two snackbars; only the second should remain.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                ElevatedButton(
                  onPressed: () => UiFeedback.error(context, 'first'),
                  child: const Text('a'),
                ),
                ElevatedButton(
                  onPressed: () => UiFeedback.success(context, 'second'),
                  child: const Text('b'),
                ),
              ],
            ),
          ),
        ),
      ));

      await tester.tap(find.text('a'));
      await tester.pump();
      await tester.tap(find.text('b'));
      await tester.pump();

      expect(find.text('first'), findsNothing);
      expect(find.text('second'), findsOneWidget);
    });
  });
}
