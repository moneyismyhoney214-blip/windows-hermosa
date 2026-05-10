// ignore_for_file: unused_element, unused_element_parameter, dead_code, unused_local_variable
part of '../invoice_print_widget.dart';

/// Per-service "turn slip" (تذكرة دور) printed in salon mode instead of the
/// restaurant kitchen ticket. Layout: shop header, optional bilingual label
/// column, bold daily-order-number banner, centred client row,
/// service/employee/price rows, and a short courtesy footer.
///
/// All printed labels honour the printer's language pair via `_ml`/`_sl`,
/// so a user configured for `tr/es` (or any other locale combo from
/// `printerLanguageSettings`) gets the slip in their language — secondary
/// labels are dropped when `allowSecondary` is off or the two languages
/// match.
///
/// The caller injects a single service per ticket via `kitchenData` keyed
/// with:
///   `template: 'salon_turn'`
///   `invoice_number`, `booking_number`, `date_str`, `time_str`,
///   `service_index` (1-based counter), `daily_order_number` (banner text)
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
    // Banner shows the daily_order_number ONLY (per spec). The booking_id
    // is intentionally NOT shown here even when it's available — staff
    // identifies clients by the loud daily counter, not the long internal
    // booking id. Falls back to the per-cart service index when the
    // backend hasn't issued a daily number yet.
    final dailyOrderNumber = (kd['daily_order_number'] ?? '').toString().trim();
    final String bannerText;
    if (dailyOrderNumber.isNotEmpty) {
      final stripped = dailyOrderNumber.startsWith('#')
          ? dailyOrderNumber.substring(1)
          : dailyOrderNumber;
      bannerText = '#$stripped';
    } else {
      bannerText = '#NO-$serviceIndex';
    }
    final customerName = (kd['customer_name'] ?? '').toString();
    final serviceName = (kd['service_name'] ?? '').toString();
    final employeeName = (kd['employee_name'] ?? '').toString();
    final priceFormatted = (kd['price_formatted'] ?? '').toString();
    final notesText = (kd['notes'] ?? '').toString().trim();
    // Falls back to the active branch's currency when the kitchen payload
    // omits a currency hint (e.g. legacy payloads from older waiter clients).
    final currencyAr =
        (kd['currency_ar'] ?? ApiConstants.currency).toString();
    final currencyEn =
        (kd['currency_en'] ?? ApiConstants.currency).toString();
    final sellerNameAr = (kd['seller_name_ar'] ?? '').toString();
    final sellerNameEn = (kd['seller_name_en'] ?? '').toString();
    final addressLine = (kd['address_line'] ?? '').toString();
    final phones = (kd['phones'] is List)
        ? List<String>.from((kd['phones'] as List).map((e) => e.toString()))
        : const <String>[];
    final logoUrl = (kd['logo_url'] ?? '').toString();

    // Resolve the shop-name + currency lines for the configured printer
    // language pair. The seller payload only carries `_ar` and `_en`
    // variants today, so anything that isn't ar maps to the en string;
    // when the user picks a non-en/non-ar pair, both lines share the en
    // text (better than blanking the header).
    String pickSeller(String lang) {
      switch (lang) {
        case 'ar':
          return sellerNameAr.isNotEmpty ? sellerNameAr : sellerNameEn;
        default:
          return sellerNameEn.isNotEmpty ? sellerNameEn : sellerNameAr;
      }
    }

    String pickCurrency(String lang) {
      return lang == 'ar' ? currencyAr : currencyEn;
    }

    final sellerPrimary = pickSeller(primaryLang);
    final sellerSecondary = (allowSecondary && secondaryLang != primaryLang)
        ? pickSeller(secondaryLang)
        : '';
    final currencyPrimary = pickCurrency(primaryLang);
    final currencySecondary = (allowSecondary && secondaryLang != primaryLang)
        ? pickCurrency(secondaryLang)
        : '';

    // Localised labels — every string the slip prints honours the printer
    // language pair the user configured (ar/en/es/tr/hi/ur). `_ml` returns
    // the primary label; `_sl` returns the secondary label or '' when the
    // user disabled secondary or the two languages match.
    final lblInvoiceP = _ml(
        ar: 'رقم الفاتورة', en: 'Invoice ID',
        es: 'N° Factura', tr: 'Fatura No',
        hi: 'चालान संख्या', ur: 'انوائس نمبر');
    final lblInvoiceS = _sl(
        ar: 'رقم الفاتورة', en: 'Invoice ID',
        es: 'N° Factura', tr: 'Fatura No',
        hi: 'चालान संख्या', ur: 'انوائس نمبر');
    final lblBookingP = _ml(
        ar: 'رقم الحجز', en: 'Booking ID',
        es: 'N° Reserva', tr: 'Rezervasyon No',
        hi: 'बुकिंग संख्या', ur: 'بکنگ نمبر');
    final lblBookingS = _sl(
        ar: 'رقم الحجز', en: 'Booking ID',
        es: 'N° Reserva', tr: 'Rezervasyon No',
        hi: 'बुकिंग संख्या', ur: 'بکنگ نمبر');
    final lblDateP = _ml(
        ar: 'التاريخ', en: 'Date',
        es: 'Fecha', tr: 'Tarih', hi: 'दिनांक', ur: 'تاریخ');
    final lblDateS = _sl(
        ar: 'التاريخ', en: 'Date',
        es: 'Fecha', tr: 'Tarih', hi: 'दिनांक', ur: 'تاریخ');
    final lblTimeP = _ml(
        ar: 'الوقت', en: 'Time',
        es: 'Hora', tr: 'Saat', hi: 'समय', ur: 'وقت');
    final lblTimeS = _sl(
        ar: 'الوقت', en: 'Time',
        es: 'Hora', tr: 'Saat', hi: 'समय', ur: 'وقت');
    final lblClientP = _ml(
        ar: 'اسم العميل', en: 'Client Name',
        es: 'Nombre del Cliente', tr: 'Müşteri Adı',
        hi: 'ग्राहक का नाम', ur: 'کسٹمر کا نام');
    final lblClientS = _sl(
        ar: 'اسم العميل', en: 'Client Name',
        es: 'Nombre del Cliente', tr: 'Müşteri Adı',
        hi: 'ग्राहक का नाम', ur: 'کسٹمر کا نام');
    final lblServiceP = _ml(
        ar: 'الخدمة', en: 'Service',
        es: 'Servicio', tr: 'Hizmet',
        hi: 'सेवा', ur: 'سروس');
    final lblServiceS = _sl(
        ar: 'الخدمة', en: 'Service',
        es: 'Servicio', tr: 'Hizmet',
        hi: 'सेवा', ur: 'سروس');
    final lblEmployeeP = _ml(
        ar: 'الموظف/ة', en: 'Employee',
        es: 'Empleado/a', tr: 'Çalışan',
        hi: 'कर्मचारी', ur: 'ملازم');
    final lblEmployeeS = _sl(
        ar: 'الموظف/ة', en: 'Employee',
        es: 'Empleado/a', tr: 'Çalışan',
        hi: 'कर्मचारी', ur: 'ملازم');
    final lblPriceP = _ml(
        ar: 'السعر', en: 'Price',
        es: 'Precio', tr: 'Fiyat',
        hi: 'मूल्य', ur: 'قیمت');
    final lblPriceS = _sl(
        ar: 'السعر', en: 'Price',
        es: 'Precio', tr: 'Fiyat',
        hi: 'मूल्य', ur: 'قیمت');
    final lblNotesP = _ml(
        ar: 'ملاحظات', en: 'Notes',
        es: 'Notas', tr: 'Notlar',
        hi: 'टिप्पणियाँ', ur: 'نوٹس');
    final lblNotesS = _sl(
        ar: 'ملاحظات', en: 'Notes',
        es: 'Notas', tr: 'Notlar',
        hi: 'टिप्पणियाँ', ur: 'نوٹس');
    final lblThanksP = _ml(
        ar: 'شكراً لتفضلكم بنا', en: 'Thank you for visiting us',
        es: 'Gracias por visitarnos',
        tr: 'Bizi tercih ettiğiniz için teşekkürler',
        hi: 'हमारे यहाँ आने के लिए धन्यवाद',
        ur: 'ہمیں منتخب کرنے کا شکریہ');

    // Tuned to the kitchen-ticket scale: section labels at 22–24, values at
    // 28, banner number at 96 (mirrors `_buildKitchenView`'s order-number
    // banner). Tighter than the previous pass — readable from the counter
    // without bloating the slip into an extra-long roll.
    final labelStyle = GoogleFonts.tajawal(
        fontSize: 20, fontWeight: FontWeight.w600, color: Colors.black);
    final labelEnStyle = GoogleFonts.tajawal(
        fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black);
    final valueStyle = GoogleFonts.tajawal(
        fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black);

    // metaRow: 3-col when both labels exist (primary | value | secondary),
    // 2-col (label | value) when secondary is empty so the layout stays
    // balanced for single-language printer setups.
    Widget metaRow(String labelPrimary, String labelSecondary, String value) {
      if (labelSecondary.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 4,
                child: Text(labelPrimary,
                    style: labelEnStyle, textAlign: TextAlign.start),
              ),
              Expanded(
                flex: 6,
                child: Text(value,
                    style: valueStyle, textAlign: TextAlign.center),
              ),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: Text(labelPrimary,
                  style: labelEnStyle, textAlign: TextAlign.start),
            ),
            Expanded(
              flex: 4,
              child: Text(value,
                  style: valueStyle, textAlign: TextAlign.center),
            ),
            Expanded(
              flex: 3,
              child: Text(labelSecondary,
                  style: labelStyle, textAlign: TextAlign.end),
            ),
          ],
        ),
      );
    }

    Widget detailRow(String labelPrimary, String labelSecondary, String value,
        {Widget? trailing}) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.black54)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(labelPrimary, style: labelEnStyle),
                  if (labelSecondary.isNotEmpty)
                    Text(labelSecondary, style: labelStyle),
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
                width: 80,
                height: 80,
                alignment: Alignment.center,
                child: _brandLogoWidget(logoUrl),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (sellerPrimary.isNotEmpty)
                      Text(sellerPrimary,
                          style: GoogleFonts.tajawal(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.black),
                          textAlign: TextAlign.right),
                    if (sellerSecondary.isNotEmpty &&
                        sellerSecondary != sellerPrimary)
                      Text(sellerSecondary,
                          style: GoogleFonts.tajawal(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.black),
                          textAlign: TextAlign.right),
                    if (addressLine.isNotEmpty)
                      Text(addressLine,
                          style: GoogleFonts.tajawal(
                              fontSize: 18, color: Colors.black),
                          textAlign: TextAlign.right),
                    for (final p in phones)
                      if (p.trim().isNotEmpty)
                        Text(p,
                            style: GoogleFonts.tajawal(
                                fontSize: 18, color: Colors.black),
                            textAlign: TextAlign.right),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── Metadata rows ───────────────────────────────────────────
          // Booking-ID and Invoice-ID meta rows are intentionally
          // suppressed — the salon turn slip is identified by
          // `daily_order_number` (the banner below), not by the long
          // internal ids. Keeping them here would double-print the same
          // identifier in two formats.
          if (dateStr.isNotEmpty) metaRow(lblDateP, lblDateS, dateStr),
          if (timeStr.isNotEmpty) metaRow(lblTimeP, lblTimeS, timeStr),
          const SizedBox(height: 8),
          // ── Turn banner ─────────────────────────────────────────────
          // Mirrors the kitchen ticket's order-number banner (96 w900) so
          // the dor # is the loudest element on the slip.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.black, width: 2),
                bottom: BorderSide(color: Colors.black, width: 2),
              ),
            ),
            alignment: Alignment.center,
            child: Text(bannerText,
                style: GoogleFonts.tajawal(
                    fontSize: 96,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                    height: 1.0,
                    letterSpacing: 1.5)),
          ),
          // ── Client (centred) ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.black)),
            ),
            child: Column(
              children: [
                Text(lblClientP,
                    style: GoogleFonts.tajawal(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black)),
                if (lblClientS.isNotEmpty)
                  Text(lblClientS,
                      style: GoogleFonts.tajawal(
                          fontSize: 20, color: Colors.black)),
                const SizedBox(height: 4),
                Text(customerName,
                    style: GoogleFonts.tajawal(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.black),
                    textAlign: TextAlign.center),
              ],
            ),
          ),
          detailRow(lblServiceP, lblServiceS, serviceName),
          detailRow(lblEmployeeP, lblEmployeeS, employeeName),
          if (notesText.isNotEmpty) detailRow(lblNotesP, lblNotesS, notesText),
          detailRow(
            lblPriceP,
            lblPriceS,
            priceFormatted,
            trailing: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(currencyPrimary,
                      style: GoogleFonts.tajawal(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black)),
                  if (currencySecondary.isNotEmpty &&
                      currencySecondary != currencyPrimary)
                    Text(currencySecondary,
                        style: GoogleFonts.tajawal(
                            fontSize: 18, color: Colors.black)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── Footer ──────────────────────────────────────────────────
          Center(
            child: Text(lblThanksP,
                style: GoogleFonts.tajawal(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.black),
                textAlign: TextAlign.center),
          ),
          Center(
            child: Text('برنامج هيرموسا المحاسبي المتكامل',
                style: GoogleFonts.tajawal(
                    fontSize: 16, color: Colors.black)),
          ),
          Center(
            child: Text('https://test.hermosaapp.com',
                style: GoogleFonts.tajawal(
                    fontSize: 14, color: Colors.black)),
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
          width: 80,
          height: 80,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const SizedBox(width: 80, height: 80),
        );
    if (logoUrl.trim().isEmpty) return assetFallback();
    return Image.network(
      logoUrl,
      width: 80,
      height: 80,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => assetFallback(),
    );
  }
}
