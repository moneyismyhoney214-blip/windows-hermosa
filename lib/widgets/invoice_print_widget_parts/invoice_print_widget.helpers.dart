// ignore_for_file: unused_element, unused_element_parameter, dead_code
part of '../invoice_print_widget.dart';

extension InvoicePrintWidgetHelpers on InvoicePrintWidget {
  double get _receiptWidth => invoiceWidgetWidthForPaper(paperWidthMm);
  double get _summaryLabelWidth => _receiptWidth * 0.52;

  /// Resolve a label for a language code.
  static String _r(String code, {required String ar, required String en, String? hi, String? ur, String? tr, String? es}) {
    switch (code) {
      case 'hi': return hi ?? en;
      case 'ur': return ur ?? en;
      case 'tr': return tr ?? en;
      case 'es': return es ?? en;
      case 'en': return en;
      case 'ar': default: return ar;
    }
  }
  /// Primary label.
  String _ml({required String ar, required String en, String? hi, String? ur, String? tr, String? es}) =>
      _r(primaryLang, ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);
  /// Secondary label.
  String _sl({required String ar, required String en, String? hi, String? ur, String? tr, String? es}) {
    if (!allowSecondary || secondaryLang == primaryLang) return '';
    return _r(secondaryLang, ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);
  }

  double get _impliedDiscount {
    if (data == null) return 0;
    // If there's an explicit order discount, use it
    if (data!.hasOrderDiscount) return data!.orderDiscountAmount ?? 0;
    // Compare items sum with totalInclVat (both tax-inclusive) to avoid false discounts
    final itemsSum = data!.items.fold<double>(0.0, (s, i) => s + i.total);
    final totalWithTax = data!.totalInclVat;
    return itemsSum > totalWithTax && (itemsSum - totalWithTax) > 0.01
        ? itemsSum - totalWithTax
        : 0.0;
  }
}
