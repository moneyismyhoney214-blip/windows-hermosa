import 'package:flutter_html_to_pdf_plus/flutter_html_to_pdf_plus.dart';
import 'package:hermosa_pos/utils/paper_width_utils.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class KitchenHtmlPdfService {
  /// Generates a lean kitchen ticket HTML — items, quantity, and notes only.
  /// No business info, no prices, no client/tax details.
  String generateKitchenHtml({
    required String orderNumber,
    required String orderType,
    required List<Map<String, dynamic>> items,
    String? note,
    String? invoiceNumber,
    DateTime? createdAt,
    Map<String, dynamic>? templateMeta,
    int paperWidthMm = 80,
  }) {
    final widthMm = normalizePaperWidthMm(paperWidthMm, fallback: 80);
    final b = StringBuffer();
    final now = createdAt ?? DateTime.now();
    final time = DateFormat('HH:mm').format(now);

    // Only need table name from templateMeta — everything else stripped for kitchen
    final tableName = (templateMeta?['table_name'] as String? ?? '').trim();

    b.writeln('<!DOCTYPE html>');
    b.writeln('<html lang="ar" dir="rtl">');
    b.writeln('<head>');
    b.writeln('  <meta charset="UTF-8">');
    b.writeln('  <title>Kitchen Ticket</title>');
    b.writeln('  <style>');
    b.writeln('    * { box-sizing: border-box; }');
    b.writeln(
        '    body { font-family: sans-serif; margin: 0; padding: 0; background: white; }');
    b.writeln(
        '    .ticket { width: ${widthMm}mm; margin: 0 auto; padding: 8px; color: #000; }');
    // ── header ──
    b.writeln(
        '    .header { text-align: center; border-bottom: 3px solid #000; padding-bottom: 6px; margin-bottom: 6px; }');
    b.writeln(
        '    .order-num { font-size: 32px; font-weight: bold; letter-spacing: 1px; }');
    b.writeln(
        '    .meta-table { width: 100%; font-size: 16px; margin-top: 4px; border-collapse: collapse; }');
    b.writeln('    .meta-table td { font-weight: bold; padding: 0; }');
    // ── general order note — shown prominently just below header ──
    b.writeln(
        '    .order-note { background: #000; color: #fff; padding: 5px 8px; font-size: 18px; font-weight: bold; margin-bottom: 8px; border-radius: 2px; white-space: pre-wrap; word-wrap: break-word; }');
    b.writeln(
        '    .order-note-label { font-size: 13px; font-weight: normal; opacity: 0.75; display: block; margin-bottom: 2px; }');
    // ── items table ──
    b.writeln('    table { width: 100%; border-collapse: collapse; }');
    b.writeln(
        '    thead th { font-size: 18px; font-weight: bold; border-bottom: 2px solid #000; padding: 4px; text-align: right; }');
    b.writeln('    thead th.qty-col { text-align: center; width: 20%; }');
    b.writeln(
        '    tbody td { padding: 6px 4px; border-bottom: 1px dashed #000; vertical-align: top; }');
    b.writeln(
        '    tbody td.qty-cell { text-align: center; font-size: 22px; font-weight: bold; vertical-align: middle; }');
    b.writeln(
        '    .item-name { font-size: 20px; font-weight: bold; line-height: 1.3; }');
    b.writeln(
        '    .addon { font-size: 15px; color: #000; padding-right: 6px; line-height: 1.4; }');
    b.writeln(
        '    .item-note { font-size: 15px; color: #000; font-weight: bold; padding-right: 6px; margin-top: 2px; white-space: pre-wrap; }');
    b.writeln('  </style>');
    b.writeln('</head>');
    b.writeln('<body>');
    b.writeln('<div class="ticket" dir="rtl">');

    // ── header: order number + type + table + time ──
    b.writeln('  <div class="header">');
    b.writeln('    <div class="order-num">${_escapeHtml(orderNumber)}</div>');
    b.writeln('    <table class="meta-table">');
    b.writeln('      <tr>');
    b.writeln(
        '        <td style="text-align:right;">${_escapeHtml(_translateOrderType(orderType))}</td>');
    if (tableName.isNotEmpty) {
      b.writeln(
          '        <td style="text-align:center;">🍽 ${_escapeHtml(tableName)}</td>');
    }
    b.writeln('        <td style="text-align:left; direction:ltr;">$time</td>');
    b.writeln('      </tr>');
    b.writeln('    </table>');
    if (invoiceNumber != null && invoiceNumber.isNotEmpty) {
      b.writeln(
          '    <div style="font-size:14px; margin-top:3px; color:#000;">${_escapeHtml(invoiceNumber)}</div>');
    }
    b.writeln('  </div>');

    // ── general order note — prominent black banner ──
    final trimmedNote = note?.trim() ?? '';
    if (trimmedNote.isNotEmpty) {
      b.writeln('  <div class="order-note">');
      b.writeln(
          '    <span class="order-note-label">ملاحظة الطلب / Order Note</span>');
      b.writeln('    ${_escapeHtml(trimmedNote)}');
      b.writeln('  </div>');
    }

    // ── items table: name + qty only (no price) ──
    b.writeln('  <table>');
    b.writeln('    <thead><tr>');
    b.writeln('      <th style="text-align:right;">الصنف / Item</th>');
    b.writeln('      <th class="qty-col" width="20%">الكمية</th>');
    b.writeln('    </tr></thead>');
    b.writeln('    <tbody>');

    for (final item in items) {
      final name = (item['name'] ?? item['meal_name'] ?? 'صنف').toString();
      final qty = (item['quantity'] ?? '1').toString();

      b.writeln('    <tr>');
      b.writeln('      <td>');
      b.writeln('        <div class="item-name">${_escapeHtml(name)}</div>');

      // extras / addons
      final addons = item['extras'] ?? item['addons'];
      if (addons is List) {
        for (final addon in addons) {
          final addonName = (addon is Map)
              ? (addon['name'] ?? addon['option'] ?? '').toString()
              : addon.toString();
          if (addonName.trim().isNotEmpty) {
            b.writeln(
                '        <div class="addon">+ ${_escapeHtml(addonName.trim())}</div>');
          }
        }
      }

      // per-item note — bold, dark
      final itemNote = (item['notes'] ?? '').toString().trim();
      if (itemNote.isNotEmpty) {
        b.writeln(
            '        <div class="item-note">⚠ ${_escapeHtml(itemNote)}</div>');
      }

      b.writeln('      </td>');
      b.writeln('      <td class="qty-cell">$qty</td>');
      b.writeln('    </tr>');
    }

    b.writeln('    </tbody>');
    b.writeln('  </table>');
    b.writeln('</div>');
    b.writeln('</body>');
    b.writeln('</html>');

    return b.toString();
  }

  String _translateOrderType(String type) {
    switch (type.toLowerCase()) {
      case 'restaurant_internal':
        return 'Dine-in (داخل المطعم)';
      case 'restaurant_pickup':
        return 'Takeaway (سفري)';
      case 'restaurant_delivery':
        return 'Delivery (توصيل)';
      case 'restaurant_parking':
        return 'Car (سيارة)';
      default:
        return type;
    }
  }

  String _escapeHtml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  Future<String> generatePdfPath(String html, String orderId) async {
    final outputDir = await getTemporaryDirectory();
    final fileName = 'kds_${orderId}_${DateTime.now().millisecondsSinceEpoch}';

    final file = await FlutterHtmlToPdf.convertFromHtmlContent(
      content: html,
      configuration: PrintPdfConfiguration(
        targetDirectory: outputDir.path,
        targetName: fileName,
      ),
    );
    return file.path;
  }
}
