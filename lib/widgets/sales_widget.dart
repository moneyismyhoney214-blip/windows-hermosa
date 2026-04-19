import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../services/printer_language_settings_service.dart';

// تعريف موديل البيانات داخل الملف ليكون مكتفياً بذاته أو انقله لملف منفصل
class DailyClosingReportLine {
  final String label;
  final double amount;

  const DailyClosingReportLine(this.label, this.amount);
}

class DailyClosingReceiptWidget extends StatelessWidget {
  final DateTime dateFrom;
  final DateTime dateTo;
  final DateTime generatedAt;
  final List<DailyClosingReportLine> rows;

  /// Printer-language overrides. When null the widget resolves them from
  /// the global `printerLanguageSettings` singleton so the closing receipt
  /// follows the same locale as the rest of the invoices/tickets.
  final String? primaryLang;
  final String? secondaryLang;
  final bool? allowSecondary;

  const DailyClosingReceiptWidget({
    super.key,
    required this.dateFrom,
    required this.dateTo,
    required this.generatedAt,
    required this.rows,
    this.primaryLang,
    this.secondaryLang,
    this.allowSecondary,
  });

  String get _effectivePrimary =>
      (primaryLang ?? printerLanguageSettings.primary).trim().toLowerCase();
  String get _effectiveSecondary =>
      (secondaryLang ?? printerLanguageSettings.secondary)
          .trim()
          .toLowerCase();
  bool get _effectiveAllowSecondary =>
      allowSecondary ?? printerLanguageSettings.allowSecondary;

  String _pickLang(String code,
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

  String _main(
          {required String ar,
          required String en,
          String? hi,
          String? ur,
          String? tr,
          String? es}) =>
      _pickLang(_effectivePrimary,
          ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);

  String _sec(
      {required String ar,
      required String en,
      String? hi,
      String? ur,
      String? tr,
      String? es}) {
    if (!_effectiveAllowSecondary) return '';
    if (_effectiveSecondary == _effectivePrimary) return '';
    return _pickLang(_effectiveSecondary,
        ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);
  }

  // الألوان المعتمدة من قالب الـ HTML
  static const Color _primaryText = Color(0xFF0F172A);
  static const Color _secondaryText = Color(0xFF475569);
  static const Color _dividerColor = Color(0xFFCBD5E1);
  static const Color _surfaceColor = Color(0xFFF8FAFC);
  static const Color _bgColor = Color(0xFFF1F5F9);

  @override
  Widget build(BuildContext context) {
    final printDate = DateFormat('yyyy-MM-dd').format(generatedAt);
    final printTime = DateFormat('hh:mm a').format(generatedAt).toLowerCase();

    return Container(
      width: 400,
      color: _bgColor,
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 6,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Rows — primary + optional secondary label so the
              // closing receipt respects the same invoice-language setting
              // as the cashier/kitchen prints.
              _buildHeaderRow(
                _main(ar: 'التاريخ', en: 'Date', hi: 'दिनांक', ur: 'تاریخ', es: 'Fecha', tr: 'Tarih'),
                printDate,
                _sec(ar: 'التاريخ', en: 'Date', hi: 'दिनांक', ur: 'تاریخ', es: 'Fecha', tr: 'Tarih'),
              ),
              const SizedBox(height: 8),
              _buildHeaderRow(
                _main(ar: 'الوقت', en: 'Time', hi: 'समय', ur: 'وقت', es: 'Hora', tr: 'Saat'),
                printTime,
                _sec(ar: 'الوقت', en: 'Time', hi: 'समय', ur: 'وقت', es: 'Hora', tr: 'Saat'),
              ),

              const SizedBox(height: 20),

              // Title with Dashed Borders
              _buildDashedTitle(_main(ar: 'إقفالية مبيعات', en: 'Sales Closing', hi: 'बिक्री समापन', ur: 'سیلز کلوزنگ', es: 'Cierre de Ventas', tr: 'Satış Kapanışı')),
              
              const SizedBox(height: 20),
              
              // Table Section
              _buildTable(),
              
              const SizedBox(height: 20),
              
              // Footer Section
              const _DashedDivider(color: _dividerColor),
              const SizedBox(height: 20),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  /// Header row: primary-language label | value | optional secondary label.
  /// The secondary column stays empty when the cashier hasn't enabled a
  /// second language (keeps the row balanced without a dangling EN header).
  Widget _buildHeaderRow(String labelPrimary, String value, String labelSecondary) {
    return Row(
      children: [
        Expanded(
          child: Text(labelPrimary, style: GoogleFonts.cairo(fontSize: 14, color: _secondaryText)),
        ),
        Expanded(
          child: Text(value,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: _primaryText)),
        ),
        Expanded(
          child: Text(
            labelSecondary,
            textAlign: TextAlign.left,
            style: GoogleFonts.inter(fontSize: 14, color: _secondaryText),
          ),
        ),
      ],
    );
  }

  Widget _buildDashedTitle(String title) {
    return Column(
      children: [
        const _DashedDivider(color: _dividerColor, height: 2),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _primaryText,
            ),
          ),
        ),
        const _DashedDivider(color: _dividerColor, height: 2),
      ],
    );
  }

  Widget _buildTable() {
    return Column(
      children: [
        // Table Header — primary invoice language.
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          color: _surfaceColor,
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildTableHeader(_main(
                    ar: 'طرق الدفع',
                    en: 'Payment Methods',
                    hi: 'भुगतान विधियाँ',
                    ur: 'ادائیگی کے طریقے',
                    es: 'Métodos de Pago',
                    tr: 'Ödeme Yöntemleri')),
              ),
              Expanded(
                child: Center(
                  child: _buildTableHeader(_main(
                      ar: 'المبلغ',
                      en: 'Amount',
                      hi: 'राशि',
                      ur: 'رقم',
                      es: 'Monto',
                      tr: 'Tutar')),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _buildTableHeader(_main(
                      ar: 'العملة',
                      en: 'Currency',
                      hi: 'मुद्रा',
                      ur: 'کرنسی',
                      es: 'Moneda',
                      tr: 'Para Birimi')),
                ),
              ),
            ],
          ),
        ),
        // Static Rows (From/To) — still bilingual when the secondary
        // language differs from the primary.
        _buildDataRow(
          _main(ar: 'من', en: 'From', hi: 'से', ur: 'سے', es: 'Desde', tr: 'Başlangıç'),
          DateFormat('yyyy-MM-dd').format(dateFrom),
          '-',
        ),
        _buildDataRow(
          _main(ar: 'إلى', en: 'To', hi: 'तक', ur: 'تک', es: 'Hasta', tr: 'Bitiş'),
          DateFormat('yyyy-MM-dd').format(dateTo),
          '-',
        ),
        // Dynamic Rows
        ...rows.map((row) => _buildDataRow(row.label, row.amount.toStringAsFixed(2), 'SAR')),
      ],
    );
  }

  Widget _buildTableHeader(String text) {
    return Text(text, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 14, color: const Color(0xFF334155)));
  }

  Widget _buildDataRow(String label, String value, String currency) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(label, style: GoogleFonts.cairo(fontSize: 14))),
          Expanded(child: Center(child: Text(value, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)))),
          Expanded(child: Align(alignment: Alignment.centerLeft, child: Text(currency, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))))),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final thanks = _main(
      ar: 'شكراً لثقتكم بنا',
      en: 'Thank you for your trust',
      hi: 'आपके विश्वास के लिए धन्यवाद',
      ur: 'اعتماد پر شکریہ',
      es: 'Gracias por su confianza',
      tr: 'Güveniniz için teşekkürler',
    );
    final tagline = _main(
      ar: 'برنامج هيرموسا المحاسبي المتكامل',
      en: 'Hermosa Integrated Accounting System',
      hi: 'हर्मोसा एकीकृत लेखा प्रणाली',
      ur: 'ہرموسا مربوط اکاؤنٹنگ سسٹم',
      es: 'Sistema Contable Integral Hermosa',
      tr: 'Hermosa Entegre Muhasebe Sistemi',
    );
    return Column(
      children: [
        Text(
          thanks,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(fontSize: 14, color: _secondaryText),
        ),
        Text(
          tagline,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: _primaryText),
        ),
        Text(
          'https://portal.hermosaapp.com',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 12, color: _secondaryText),
        ),
      ],
    );
  }
}

// Widget لعمل الخط المتقطع
class _DashedDivider extends StatelessWidget {
  final Color color;
  final double height;

  const _DashedDivider({required this.color, this.height = 1});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final boxWidth = constraints.constrainWidth();
      const dashWidth = 5.0;
      final dashCount = (boxWidth / (2 * dashWidth)).floor();
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(dashCount, (_) {
          return SizedBox(width: dashWidth, height: height, child: DecoratedBox(decoration: BoxDecoration(color: color)));
        }),
      );
    });
  }
}
