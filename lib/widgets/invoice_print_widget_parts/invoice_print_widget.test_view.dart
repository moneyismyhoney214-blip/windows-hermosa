// ignore_for_file: unused_element, unused_element_parameter, dead_code
part of '../invoice_print_widget.dart';

extension InvoicePrintWidgetTestView on InvoicePrintWidget {
  Widget _buildTestView() {
    return Column(
      children: [
        const Icon(Icons.print, size: 64, color: Colors.black),
        const SizedBox(height: 6),
        Text(
          'اختبار الطباعة',
          style: GoogleFonts.tajawal(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          'Test Print',
          style: GoogleFonts.tajawal(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        const DashedDivider(),
        const SizedBox(height: 8),
        Text(
          'التاريخ: ${DateTime.now().toString().split('.').first}',
          style: GoogleFonts.tajawal(fontSize: 30, fontWeight: FontWeight.bold),
        ),
        Text(
          'عرض الورق: $paperWidthMm ملم',
          style: GoogleFonts.tajawal(fontSize: 30, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const DashedDivider(),
        const SizedBox(height: 24),
        Text(
          'اللغة العربية تعمل بنجاح',
          style: GoogleFonts.tajawal(fontSize: 30, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        const Text('! @ # \$ % ^ & * ( )'),
        const SizedBox(height: 48),
        const DashedDivider(),
        Text(
          '✂ قُص هنا / CUT HERE ✂',
          style: GoogleFonts.tajawal(fontSize: 34, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const DashedDivider(),
        const SizedBox(height: 60), // Extra space for physical cutting
      ],
    );
  }

  /// Row used inside kitchen change-tickets (Qty Change / Partial Cancel)
  /// to show old/new/cancelled quantities. Accepts already-resolved primary
  /// and secondary labels — the caller is responsible for picking them via
  /// `_ml` / `_sl` so every invoice language (ar/en/es/tr/hi/ur) is supported,
  /// not just Arabic + English.
  Widget _buildChangeDetailRow(String labelPrimary, String labelSecondary, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                labelPrimary,
                style: GoogleFonts.tajawal(fontSize: 34, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              if (labelSecondary.isNotEmpty && labelSecondary != labelPrimary)
                Text(
                  labelSecondary,
                  style: GoogleFonts.tajawal(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.black54),
                ),
            ],
          ),
          Text(
            value,
            style: GoogleFonts.tajawal(fontSize: 40, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  /// Kitchen metadata row (order type / table / customer / phone / date).
  /// Takes pre-resolved primary + secondary labels so every supported
  /// invoice language renders correctly — not just Arabic + English.
  Widget _buildMetaRow(String labelPrimary, String labelSecondary, String value, {bool isLarge = false}) {
    // Use start/end alignment so it adapts to Directionality (RTL/LTR)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                labelPrimary,
                style: GoogleFonts.tajawal(fontSize: 34, fontWeight: FontWeight.bold),
              ),
              if (labelSecondary.isNotEmpty && labelSecondary != labelPrimary)
                Text(
                  labelSecondary,
                  style: GoogleFonts.tajawal(fontSize: 30, color: Colors.black87, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.tajawal(
                fontSize: isLarge ? 34 : 28,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
