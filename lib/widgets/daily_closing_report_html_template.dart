import 'package:intl/intl.dart';
import 'package:hermosa_pos/utils/paper_width_utils.dart';

class DailyClosingReportLine {
  final String label;
  final double amount;

  const DailyClosingReportLine(this.label, this.amount);
}

class DailyClosingReportHtmlTemplate {
  static final _numberFormatter = NumberFormat('0.00', 'en');

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

    return '''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
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
    return '''
    <div class="header-row">
      <span>التاريخ</span>
      <span class="center">$printDate</span>
      <span class="left" dir="ltr">Date</span>
    </div>
    <div class="header-row">
      <span>الوقت</span>
      <span class="center">$printTime</span>
      <span class="left" dir="ltr">Time</span>
    </div>

    <div class="receipt-title">
      إقفالية مبيعات
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

    return '''
    <table class="receipt-table">
      <thead>
        <tr class="bold-row">
          <th class="label-col">طرق الدفع</th>
          <th class="val-col">المبلغ</th>
          <th class="currency-col">العملة</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td class="label-col">من</td>
          <td class="val-col" dir="ltr">${DateFormat('yyyy-MM-dd').format(dateFrom)}</td>
          <td class="currency-col">-</td>
        </tr>
        <tr>
          <td class="label-col">إلى</td>
          <td class="val-col" dir="ltr">${DateFormat('yyyy-MM-dd').format(dateTo)}</td>
          <td class="currency-col">-</td>
        </tr>
        $rowsHtml
      </tbody>
    </table>
    ''';
  }

  static String _buildFooter() {
    return '''
    <div class="footer-divider"></div>
    <div class="footer-text">
      شكراً لثقتكم بنا<br>
      <strong>برنامج هيرموسا المحاسبي المتكامل</strong><br>
      <span dir="ltr">https://test.hermosaapp.com</span>
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
