import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

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

  const DailyClosingReceiptWidget({
    super.key,
    required this.dateFrom,
    required this.dateTo,
    required this.generatedAt,
    required this.rows,
  });

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
              // Header Rows
              _buildHeaderRow('التاريخ', printDate, 'Date'),
              const SizedBox(height: 8),
              _buildHeaderRow('الوقت', printTime, 'Time'),
              
              const SizedBox(height: 20),
              
              // Title with Dashed Borders
              _buildDashedTitle('إقفالية مبيعات'),
              
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

  Widget _buildHeaderRow(String labelAr, String value, String labelEn) {
    return Row(
      children: [
        Expanded(
          child: Text(labelAr, style: GoogleFonts.cairo(fontSize: 14, color: _secondaryText)),
        ),
        Expanded(
          child: Text(value, 
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: _primaryText)),
        ),
        Expanded(
          child: Text(labelEn, 
            textAlign: TextAlign.left,
            style: GoogleFonts.inter(fontSize: 14, color: _secondaryText)),
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
        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          color: _surfaceColor,
          child: Row(
            children: [
              Expanded(flex: 2, child: _buildTableHeader('طرق الدفع')),
              Expanded(child: Center(child: _buildTableHeader('المبلغ'))),
              Expanded(child: Align(alignment: Alignment.centerLeft, child: _buildTableHeader('العملة'))),
            ],
          ),
        ),
        // Static Rows (From/To)
        _buildDataRow('من', DateFormat('yyyy-MM-dd').format(dateFrom), '-'),
        _buildDataRow('إلى', DateFormat('yyyy-MM-dd').format(dateTo), '-'),
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
    return Column(
      children: [
        Text(
          'شكراً لثقتكم بنا',
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(fontSize: 14, color: _secondaryText),
        ),
        Text(
          'برنامج هيرموسا المحاسبي المتكامل',
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: _primaryText),
        ),
        Text(
          'https://test.hermosaapp.com',
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
