// Private support classes used by InvoiceHtmlPdfService.
// Split out of invoice_html_pdf_service.dart for size; remain in the same library via `part of`.
part of '../invoice_html_pdf_service.dart';

/// Reconciled totals for a single invoice. Produced by
/// [InvoiceHtmlPdfService._resolveInvoiceTotals] so the WhatsApp PDF
/// path always feeds [OrderReceiptData] non-zero, internally consistent
/// values regardless of which invoice route the backend used.
class _InvoiceTotals {
  final double totalExclVat;
  final double vatAmount;
  final double totalInclVat;

  const _InvoiceTotals({
    required this.totalExclVat,
    required this.vatAmount,
    required this.totalInclVat,
  });
}

class _PrintInvoiceModel {
  final Map<String, dynamic> envelope;
  final Map<String, dynamic> invoice;
  final Map<String, dynamic> branch;
  final Map<String, dynamic> seller;
  final Map<String, dynamic> booking;
  final Map<String, dynamic> client;
  final Map<String, dynamic> carInfo;
  final _InvoiceLanguage language;
  final List<Map<String, dynamic>> items;
  final List<String> fields;
  final String type;
  final String module;
  final String kind;
  final _InvoiceTitle title;
  final String orderNumber;
  final String dailyOrderNumber;
  final String bookingDate;
  final String date;
  final String time;
  final String invoiceNumber;
  final String currencyAr;
  final String currencyEn;
  final String paymentMethods;
  final String policy;
  final String qrImage;
  final bool hasOrders;
  final double calculatedPriceBeforeTax;
  final String websiteUrl;

  _PrintInvoiceModel({
    required this.envelope,
    required this.invoice,
    required this.branch,
    required this.seller,
    required this.booking,
    required this.client,
    required this.carInfo,
    required this.language,
    required this.items,
    required this.fields,
    required this.type,
    required this.module,
    required this.kind,
    required this.title,
    required this.orderNumber,
    required this.dailyOrderNumber,
    required this.bookingDate,
    required this.date,
    required this.time,
    required this.invoiceNumber,
    required this.currencyAr,
    required this.currencyEn,
    required this.paymentMethods,
    required this.policy,
    required this.qrImage,
    required this.hasOrders,
    required this.calculatedPriceBeforeTax,
    required this.websiteUrl,
  });
}

class _InvoiceLanguage {
  final String primary;
  final String secondary;
  final bool allowSecondary;

  const _InvoiceLanguage({
    required this.primary,
    required this.secondary,
    required this.allowSecondary,
  });

  bool get showHindi =>
      primary == 'hi' || (allowSecondary && secondary == 'hi');

  bool get showUrdu => primary == 'ur' || (allowSecondary && secondary == 'ur');

  bool get showTurkish =>
      primary == 'tr' || (allowSecondary && secondary == 'tr');

  bool get showSpanish =>
      primary == 'es' || (allowSecondary && secondary == 'es');

  /// Resolve a label for a given language code.
  String _resolve(
    String code, {
    required String ar,
    required String en,
    String? hi,
    String? ur,
    String? tr,
    String? es,
  }) {
    switch (code) {
      case 'ar':
        return ar;
      case 'hi':
        return hi ?? en;
      case 'ur':
        return ur ?? en;
      case 'tr':
        return tr ?? en;
      case 'es':
        return es ?? en;
      case 'en':
      default:
        return en;
    }
  }

  /// The main (primary) label for the invoice.
  String mainLabel({
    required String ar,
    required String en,
    String? hi,
    String? ur,
    String? tr,
    String? es,
  }) =>
      _resolve(primary, ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);

  /// The secondary label shown below the primary. Empty if not allowed.
  String secLabel({
    required String ar,
    required String en,
    String? hi,
    String? ur,
    String? tr,
    String? es,
  }) {
    if (!allowSecondary) return '';
    if (secondary == primary) return '';
    return _resolve(secondary, ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);
  }
}

class _InvoiceTitle {
  final String text;
  final String textAlt;

  const _InvoiceTitle({
    required this.text,
    required this.textAlt,
  });
}
