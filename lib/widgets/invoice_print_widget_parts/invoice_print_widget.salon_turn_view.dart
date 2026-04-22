// ignore_for_file: unused_element, unused_element_parameter, dead_code
part of '../invoice_print_widget.dart';

/// Per-service "turn slip" (تذكرة دور) printed in salon mode instead of the
/// restaurant kitchen ticket. Layout mirrors the reference invoice PDF:
/// shop header, bilingual label column, bold `#NO-X` banner, centred client
/// row, service/employee/price rows, and a short courtesy footer.
///
/// The caller injects a single service per ticket via `kitchenData` keyed
/// with:
///   `template: 'salon_turn'`
///   `invoice_number`, `booking_number`, `date_str`, `time_str`,
///   `service_index` (1-based counter)
///   `customer_name`, `service_name`, `employee_name`
///   `price_formatted`, `currency_ar`, `currency_en`
///   `seller_name_ar`, `seller_name_en`, `address_line`, `phones` (List<String>)
extension InvoicePrintWidgetSalonTurnView on InvoicePrintWidget {
  Widget _buildSalonTurnView() {
    final kd = kitchenData ?? const <String, dynamic>{};
    final invoiceNumber = (kd['invoice_number'] ?? '').toString();
    final bookingNumber = (kd['booking_number'] ?? '').toString();
    final dateStr = (kd['date_str'] ?? '').toString();
    final timeStr = (kd['time_str'] ?? '').toString();
    final serviceIndex = (kd['service_index'] as num?)?.toInt() ?? 1;
    final customerName = (kd['customer_name'] ?? '').toString();
    final serviceName = (kd['service_name'] ?? '').toString();
    final employeeName = (kd['employee_name'] ?? '').toString();
    final priceFormatted = (kd['price_formatted'] ?? '').toString();
    final currencyAr = (kd['currency_ar'] ?? 'ر.س').toString();
    final currencyEn = (kd['currency_en'] ?? 'SAR').toString();
    final sellerNameAr = (kd['seller_name_ar'] ?? '').toString();
    final sellerNameEn = (kd['seller_name_en'] ?? '').toString();
    final addressLine = (kd['address_line'] ?? '').toString();
    final phones = (kd['phones'] is List)
        ? List<String>.from((kd['phones'] as List).map((e) => e.toString()))
        : const <String>[];
    final logoUrl = (kd['logo_url'] ?? '').toString();

    const labelStyle =
        TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black);
    const labelEnStyle =
        TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black);
    const valueStyle =
        TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black);

    Widget metaRow(String labelAr, String labelEn, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Text(labelAr,
                  style: labelStyle, textAlign: TextAlign.left),
            ),
            Expanded(
              flex: 4,
              child: Text(value,
                  style: valueStyle, textAlign: TextAlign.center),
            ),
            Expanded(
              flex: 3,
              child: Text(labelEn,
                  style: labelEnStyle, textAlign: TextAlign.right),
            ),
          ],
        ),
      );
    }

    Widget detailRow(String labelAr, String labelEn, String value,
        {Widget? trailing}) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.black)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(labelEn, style: labelEnStyle),
                  Text(labelAr, style: labelStyle),
                ],
              ),
            ),
            Expanded(
              child: Text(value,
                  style: valueStyle, textAlign: TextAlign.center),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Shop header ─────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo — prefer the backend-uploaded seller logo (pulled from
              // the invoice `seller.logo` field); fall back to the bundled
              // splash asset if the URL is empty or unreachable.
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                child: _brandLogoWidget(logoUrl),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (sellerNameAr.isNotEmpty)
                      Text(sellerNameAr,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.black),
                          textAlign: TextAlign.right),
                    if (sellerNameEn.isNotEmpty)
                      Text(sellerNameEn,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black),
                          textAlign: TextAlign.right),
                    if (addressLine.isNotEmpty)
                      Text(addressLine,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black),
                          textAlign: TextAlign.right),
                    for (final p in phones)
                      if (p.trim().isNotEmpty)
                        Text(p,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black),
                            textAlign: TextAlign.right),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── Metadata rows ───────────────────────────────────────────
          if (invoiceNumber.isNotEmpty)
            metaRow('رقم الفاتورة', 'Invoice ID', invoiceNumber),
          if (bookingNumber.isNotEmpty)
            metaRow('رقم الحجز', 'Booking ID', bookingNumber),
          if (dateStr.isNotEmpty) metaRow('التاريخ', 'Date', dateStr),
          if (timeStr.isNotEmpty) metaRow('الوقت', 'Time', timeStr),
          const SizedBox(height: 8),
          // ── Turn banner ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.black, width: 2),
                bottom: BorderSide(color: Colors.black, width: 2),
              ),
            ),
            alignment: Alignment.center,
            child: Text('#NO-$serviceIndex',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: 1.2)),
          ),
          // ── Client (centred) ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.black)),
            ),
            child: Column(
              children: [
                const Text('اسم العميل',
                    style: TextStyle(fontSize: 12, color: Colors.black)),
                const Text('Client Name',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.black)),
                const SizedBox(height: 4),
                Text(customerName,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.black),
                    textAlign: TextAlign.center),
              ],
            ),
          ),
          detailRow('الخدمة', 'Service', serviceName),
          detailRow('الموظف/ة', 'Employee', employeeName),
          detailRow(
            'السعر',
            'Price',
            priceFormatted,
            trailing: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(currencyAr,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black)),
                  Text(currencyEn,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── Footer ──────────────────────────────────────────────────
          const Center(
            child: Text('شكراً لتفضلكم بنا',
                style: TextStyle(fontSize: 12, color: Colors.black)),
          ),
          const Center(
            child: Text('برنامج هيرموسا المحاسبي المتكامل',
                style: TextStyle(fontSize: 11, color: Colors.black)),
          ),
          const Center(
            child: Text('https://test.hermosaapp.com',
                style: TextStyle(fontSize: 11, color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _brandLogoWidget(String logoUrl) {
    // Prefer the backend-uploaded logo so every branch prints its own brand.
    // Fall back to the bundled splash asset when the URL is empty or fails.
    Widget assetFallback() => Image.asset(
          'assets/splash/logo.png',
          width: 54,
          height: 54,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const SizedBox(width: 54, height: 54),
        );
    if (logoUrl.trim().isEmpty) return assetFallback();
    return Image.network(
      logoUrl,
      width: 54,
      height: 54,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => assetFallback(),
    );
  }
}
