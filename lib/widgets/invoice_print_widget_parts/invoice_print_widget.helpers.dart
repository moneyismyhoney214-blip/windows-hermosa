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
    if (data!.hasOrderDiscount) return data!.orderDiscountAmount ?? 0;
    // Sum the explicit per-item discounts. Previously this used
    // `itemsSum - totalInclVat` which collapsed to 0 for fully-free
    // orders (both sides == 0) and hid the "إجمالي خصم الأصناف" row
    // — switching to the per-item sum makes the implied discount
    // robust to the backend's pre/post-discount convention quirks.
    return data!.items.fold<double>(
        0.0, (sum, item) => sum + (item.discountAmount ?? 0));
  }

  /// True when the receipt has any discount at all (order-level OR
  /// per-item). Used by the totals widget to decide if a zero-total
  /// receipt should fire the "FREE ORDER" banner — covers IN-824-style
  /// orders that reached zero entirely via per-item free toggles
  /// without an explicit order-level discount/coupon.
  bool get _hasAnyDiscountSource {
    if (data == null) return false;
    if (data!.hasOrderDiscount) return true;
    for (final item in data!.items) {
      if ((item.discountAmount ?? 0) > 0.01) return true;
    }
    return false;
  }
}
