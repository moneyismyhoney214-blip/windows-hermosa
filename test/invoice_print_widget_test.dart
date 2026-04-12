import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/models/receipt_data.dart';
import 'package:hermosa_pos/widgets/invoice_print_widget.dart';

OrderReceiptData _sampleReceiptData() {
  return OrderReceiptData(
    invoiceNumber: 'INV-1001',
    issueDateTime: '2026-04-06 16:02:00',
    sellerNameAr: 'مطعم تجريبي',
    sellerNameEn: 'Demo Restaurant',
    vatNumber: '300012345600003',
    branchName: 'الفرع الرئيسي',
    items: <ReceiptItem>[
      ReceiptItem(
        nameAr: 'وجبة تجريبية',
        nameEn: 'Demo Meal',
        quantity: 1,
        unitPrice: 25.22,
        total: 25.22,
      ),
    ],
    totalExclVat: 21.93,
    vatAmount: 3.29,
    totalInclVat: 25.22,
    paymentMethod: 'نقدي',
    qrCodeBase64: '',
  );
}

void main() {
  Future<void> pumpReceipt(
    WidgetTester tester, {
    required int paperWidthMm,
  }) async {
    tester.view.physicalSize = const Size(1600, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: InvoicePrintWidget(
                data: _sampleReceiptData(),
                paperWidthMm: paperWidthMm,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('InvoicePrintWidget uses 58mm width', (
    WidgetTester tester,
  ) async {
    await pumpReceipt(tester, paperWidthMm: 58);

    final root = find.byKey(const ValueKey('invoice-print-root'));
    expect(root, findsOneWidget);
    expect(tester.getSize(root).width, closeTo(302.0, 0.01));
  });

  testWidgets('InvoicePrintWidget uses 80mm width', (
    WidgetTester tester,
  ) async {
    await pumpReceipt(tester, paperWidthMm: 80);

    final root = find.byKey(const ValueKey('invoice-print-root'));
    expect(root, findsOneWidget);
    expect(tester.getSize(root).width, closeTo(420.0, 0.01));
  });

  testWidgets('InvoicePrintWidget uses 88mm width', (
    WidgetTester tester,
  ) async {
    await pumpReceipt(tester, paperWidthMm: 88);

    final root = find.byKey(const ValueKey('invoice-print-root'));
    expect(root, findsOneWidget);
    expect(tester.getSize(root).width, closeTo(462.0, 0.01));
  });
}
