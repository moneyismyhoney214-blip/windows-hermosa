import 'package:intl/intl.dart';
import 'package:hermosa_pos/utils/paper_width_utils.dart';
import 'package:hermosa_pos/services/printer_language_settings_service.dart';

class DailyClosingReportLine {
  final String label;
  final double amount;

  const DailyClosingReportLine(this.label, this.amount);
}

class DailyClosingReportHtmlTemplate {
  static final _numberFormatter = NumberFormat('0.00', 'en');

  /// Resolve the primary invoice language for every label on the HTML
  /// closing receipt. Pulls from the printer-language settings so an
  /// es/en branch doesn't still get Arabic headers — the previous template
  /// had the labels baked directly into the HTML string.
  static String _pickLang(String code,
      {required String ar,
      required String en,
      String? hi,
      String? ur,
      String? tr,
      String? es}) {
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

  static String _main(
      {required String ar,
      required String en,
      String? hi,
      String? ur,
      String? tr,
      String? es}) {
    final code = printerLanguageSettings.primary.trim().toLowerCase();
    return _pickLang(code,
        ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);
  }

  static String _sec(
      {required String ar,
      required String en,
      String? hi,
      String? ur,
      String? tr,
      String? es}) {
    final primary = printerLanguageSettings.primary.trim().toLowerCase();
    final secondary = printerLanguageSettings.secondary.trim().toLowerCase();
    if (!printerLanguageSettings.allowSecondary) return '';
    if (secondary == primary) return '';
    return _pickLang(secondary,
        ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);
  }

  static String generate({
    required DateTime dateFrom,
    required DateTime dateTo,
    required DateTime generatedAt,
    required List<DailyClosingReportLine> rows,
    int paperWidthMm = 80,
  }) {
    final printDate = DateFormat('yyyy-MM-dd').format(generatedAt);
    final printTime =
        DateFormat('hh:mm a', 'en').format(generatedAt).toLowerCase();

    final primary = printerLanguageSettings.primary.trim().toLowerCase();
    // Arabic and Urdu are the two RTL locales we support; everything else
    // reads left-to-right.
    final isRtl = primary == 'ar' || primary == 'ur';
    return '''
<!DOCTYPE html>
<html lang="$primary" dir="${isRtl ? 'rtl' : 'ltr'}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Sales Closure Receipt</title>
  <style>
    ${_buildStyles(paperWidthMm)}
  </style>
</head>
<body>
  <div class="receipt">
    ${_buildHeader(printDate, printTime)}
    ${_buildTable(dateFrom, dateTo, rows)}
    ${_buildFooter()}
  </div>
</body>
</html>
''';
  }

  // ==========================================
  // HTML Builders
  // ==========================================

  static String _buildHeader(String printDate, String printTime) {
    // Primary label on the left of the row, secondary label on the right.
    // When the cashier only configured a single language the secondary cell
    // collapses to an empty span so the grid stays aligned.
    final datePrimary = _escapeHtml(_main(ar: 'التاريخ', en: 'Date', hi: 'दिनांक', ur: 'تاریخ', es: 'Fecha', tr: 'Tarih'));
    final dateSecondary = _escapeHtml(_sec(ar: 'التاريخ', en: 'Date', hi: 'दिनांक', ur: 'تاریخ', es: 'Fecha', tr: 'Tarih'));
    final timePrimary = _escapeHtml(_main(ar: 'الوقت', en: 'Time', hi: 'समय', ur: 'وقت', es: 'Hora', tr: 'Saat'));
    final timeSecondary = _escapeHtml(_sec(ar: 'الوقت', en: 'Time', hi: 'समय', ur: 'وقت', es: 'Hora', tr: 'Saat'));
    final titlePrimary = _escapeHtml(_main(
        ar: 'إقفالية مبيعات',
        en: 'Sales Closing',
        hi: 'बिक्री समापन',
        ur: 'سیلز کلوزنگ',
        es: 'Cierre de Ventas',
        tr: 'Satış Kapanışı'));
    final titleSecondary = _escapeHtml(_sec(
        ar: 'إقفالية مبيعات',
        en: 'Sales Closing',
        hi: 'बिक्री समापन',
        ur: 'سیلز کلوزنگ',
        es: 'Cierre de Ventas',
        tr: 'Satış Kapanışı'));
    return '''
    <div class="header-row">
      <span>$datePrimary</span>
      <span class="center">$printDate</span>
      <span class="left">$dateSecondary</span>
    </div>
    <div class="header-row">
      <span>$timePrimary</span>
      <span class="center">$printTime</span>
      <span class="left">$timeSecondary</span>
    </div>

    <div class="receipt-title">
      $titlePrimary${titleSecondary.isEmpty || titleSecondary == titlePrimary ? '' : '<br><small>$titleSecondary</small>'}
    </div>
    ''';
  }

  static String _buildTable(
      DateTime dateFrom, DateTime dateTo, List<DailyClosingReportLine> rows) {
    final String rowsHtml = rows.map((line) => '''
      <tr>
        <td class="label-col">${_escapeHtml(line.label)}</td>
        <td class="val-col">${_numberFormatter.format(line.amount)}</td>
        <td class="currency-col">SAR</td>
      </tr>
    ''').join('\n');

    final payMethodsHeader = _escapeHtml(_main(
        ar: 'طرق الدفع',
        en: 'Payment Methods',
        hi: 'भुगतान विधियाँ',
        ur: 'ادائیگی کے طریقے',
        es: 'Métodos de Pago',
        tr: 'Ödeme Yöntemleri'));
    final amountHeader = _escapeHtml(_main(
        ar: 'المبلغ',
        en: 'Amount',
        hi: 'राशि',
        ur: 'رقم',
        es: 'Monto',
        tr: 'Tutar'));
    final currencyHeader = _escapeHtml(_main(
        ar: 'العملة',
        en: 'Currency',
        hi: 'मुद्रा',
        ur: 'کرنسی',
        es: 'Moneda',
        tr: 'Para Birimi'));
    final fromLabel = _escapeHtml(_main(
        ar: 'من',
        en: 'From',
        hi: 'से',
        ur: 'سے',
        es: 'Desde',
        tr: 'Başlangıç'));
    final toLabel = _escapeHtml(_main(
        ar: 'إلى',
        en: 'To',
        hi: 'तक',
        ur: 'تک',
        es: 'Hasta',
        tr: 'Bitiş'));

    return '''
    <table class="receipt-table">
      <thead>
        <tr class="bold-row">
          <th class="label-col">$payMethodsHeader</th>
          <th class="val-col">$amountHeader</th>
          <th class="currency-col">$currencyHeader</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td class="label-col">$fromLabel</td>
          <td class="val-col" dir="ltr">${DateFormat('yyyy-MM-dd').format(dateFrom)}</td>
          <td class="currency-col">-</td>
        </tr>
        <tr>
          <td class="label-col">$toLabel</td>
          <td class="val-col" dir="ltr">${DateFormat('yyyy-MM-dd').format(dateTo)}</td>
          <td class="currency-col">-</td>
        </tr>
        $rowsHtml
      </tbody>
    </table>
    ''';
  }

  static String _buildFooter() {
    final thanks = _escapeHtml(_main(
        ar: 'شكراً لثقتكم بنا',
        en: 'Thank you for your trust',
        hi: 'आपके विश्वास के लिए धन्यवाद',
        ur: 'اعتماد پر شکریہ',
        es: 'Gracias por su confianza',
        tr: 'Güveniniz için teşekkürler'));
    final tagline = _escapeHtml(_main(
        ar: 'برنامج هيرموسا المحاسبي المتكامل',
        en: 'Hermosa Integrated Accounting System',
        hi: 'हर्मोसा एकीकृत लेखा प्रणाली',
        ur: 'ہرموسا مربوط اکاؤنٹنگ سسٹم',
        es: 'Sistema Contable Integral Hermosa',
        tr: 'Hermosa Entegre Muhasebe Sistemi'));
    return '''
    <div class="footer-divider"></div>
    <div class="footer-text">
      $thanks<br>
      <strong>$tagline</strong><br>
      <span dir="ltr">https://portal.hermosaapp.com</span>
    </div>
    ''';
  }

  // ==========================================
  // CSS Styles
  // ==========================================

  static String _buildStyles(int paperWidthMm) {
    final widthMm = normalizePaperWidthMm(paperWidthMm, fallback: 80);
    return '''
    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    }
    body {
      background-color: #f1f5f9;
      display: flex;
      justify-content: center;
      padding: 24px 8px;
      color: #0f172a;
    }
    .receipt {
      background-color: #ffffff;
      width: ${widthMm}mm;
      max-width: ${widthMm}mm;
      padding: 14px 10px;
      border-radius: 8px;
      box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06);
    }
    .header-row {
      display: flex;
      justify-content: space-between;
      font-size: 14px;
      margin-bottom: 8px;
      color: #475569;
    }
    .header-row span {
      flex: 1;
    }
    .header-row .center {
      text-align: center;
      font-weight: 600;
      color: #0f172a;
    }
    .header-row .left {
      text-align: left;
    }
    .receipt-title {
      text-align: center;
      font-size: 20px;
      font-weight: 700;
      border-top: 2px dashed #cbd5e1;
      border-bottom: 2px dashed #cbd5e1;
      padding: 12px 0;
      margin: 20px 0;
      color: #0f172a;
    }
    .receipt-table {
      width: 100%;
      border-collapse: collapse;
      margin-bottom: 20px;
    }
    .receipt-table th,
    .receipt-table td {
      padding: 10px 8px;
      font-size: 14px;
      border-bottom: 1px solid #e2e8f0;
    }
    .receipt-table th {
      background-color: #f8fafc;
      color: #334155;
      font-weight: 700;
      text-align: right;
    }
    .label-col {
      width: 45%;
      text-align: right;
    }
    .val-col {
      width: 35%;
      text-align: center;
      font-weight: 600;
      font-family: monospace;
      font-size: 15px;
    }
    .currency-col {
      width: 20%;
      text-align: left;
      color: #64748b;
      font-size: 12px;
    }
    .footer-divider {
      border-top: 2px dashed #cbd5e1;
      margin: 20px 0;
    }
    .footer-text {
      text-align: center;
      font-size: 14px;
      line-height: 1.8;
      color: #475569;
    }
    .footer-text strong {
      color: #0f172a;
    }
    @media print {
      @page {
        size: ${widthMm}mm auto;
        margin: 0;
      }
      body {
        background-color: #ffffff;
        padding: 0;
      }
      .receipt {
        width: ${widthMm}mm;
        max-width: ${widthMm}mm;
        border-radius: 0;
        box-shadow: none;
      }
    }
    ''';
  }

  // ==========================================
  // Utilities
  // ==========================================

  static String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}
