// ignore_for_file: unused_element, unused_element_parameter, dead_code
part of '../invoice_print_widget.dart';

extension InvoicePrintWidgetHeader on InvoicePrintWidget {
  Widget _buildHeader() {
    if (data == null) return const SizedBox.shrink();
    final hasLogo = data!.sellerLogo != null && data!.sellerLogo!.isNotEmpty;
    final resolvedDailyOrderNumber =
        (dailyOrderNumber != null && dailyOrderNumber!.trim().isNotEmpty)
            ? dailyOrderNumber!.replaceAll('#', '').trim()
            : (data!.orderNumber != null && data!.orderNumber!.trim().isNotEmpty)
                ? data!.orderNumber!.replaceAll('#', '').trim()
                : null;
    final resolvedInvoiceNumber = data!.invoiceNumber.replaceAll('#', '').trim();

    return Column(
      children: [
        // Centered Header
        Center(
          child: Column(
            children: [
              if (hasLogo)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2.0),
                  child: Image.network(
                    data!.sellerLogo!,
                    height: 52,
                    width: 52,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox(),
                  ),
                ),
              Text(
                data!.sellerNameAr,
                style: GoogleFonts.tajawal(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black),
                textAlign: TextAlign.center,
              ),
              if (data!.sellerNameEn.isNotEmpty && data!.sellerNameEn != data!.sellerNameAr)
                Text(
                  data!.sellerNameEn,
                  style: GoogleFonts.tajawal(
                      fontSize: 19, color: Colors.black, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              if (data!.branchAddress != null && data!.branchAddress!.isNotEmpty)
                Text(
                  data!.branchAddress!,
                  style: GoogleFonts.tajawal(fontSize: 18, color: Colors.black, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              if (data!.branchMobile != null && data!.branchMobile!.isNotEmpty)
                Text(
                  data!.branchMobile!,
                  style: GoogleFonts.tajawal(
                      fontSize: 19, color: Colors.black, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        const DashedDivider(),
        const SizedBox(height: 2),
        
        // Daily Order Number — compact inline row + optional EN secondary line
        if (resolvedDailyOrderNumber != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '${_ml(ar: 'رقم الطلب اليومي', en: 'Daily Order', hi: 'दैनिक ऑर्डर', ur: 'روزانہ آرڈر', es: 'Pedido Diario', tr: 'Günlük Sipariş')}: ',
                  style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '#$resolvedDailyOrderNumber',
                  style: GoogleFonts.tajawal(fontSize: 36, fontWeight: FontWeight.w900, height: 1.0),
                ),
              ],
            ),
          ),
          if (_sl(ar: 'رقم الطلب اليومي', en: 'Daily Order', hi: 'दैनिक ऑर्डर', ur: 'روزانہ آرڈر', es: 'Pedido Diario', tr: 'Günlük Sipariş').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                _sl(ar: 'رقم الطلب اليومي', en: 'Daily Order', hi: 'दैनिक ऑर्डर', ur: 'روزانہ آرڈر', es: 'Pedido Diario', tr: 'Günlük Sipariş'),
                style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
        ],

        // Invoice Number — compact inline row + optional EN secondary line
        if (resolvedInvoiceNumber.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isCreditNote
                      ? '${_ml(ar: 'رقم إشعار الدائن', en: 'Credit Note No.', hi: 'क्रेडिट नोट नं.', ur: 'کریڈٹ نوٹ نمبر', es: 'N° Nota de Crédito', tr: 'Alacak Dekontu No.')}: '
                      : '${_ml(ar: 'رقم الفاتورة', en: 'Invoice No.', hi: 'इनवॉइस नं.', ur: 'انوائس نمبر', es: 'N° Factura', tr: 'Fatura No.')}: ',
                  style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  resolvedInvoiceNumber,
                  style: GoogleFonts.tajawal(fontSize: 24, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          if ((isCreditNote
                  ? _sl(ar: 'رقم إشعار الدائن', en: 'Credit Note No.', hi: 'क्रेडिट नोट नं.', ur: 'کریڈٹ نوٹ نمبر', es: 'N° Nota de Crédito', tr: 'Alacak Dekontu No.')
                  : _sl(ar: 'رقم الفاتورة', en: 'Invoice No.', hi: 'इनवॉइस नं.', ur: 'انوائس نمبر', es: 'N° Factura', tr: 'Fatura No.'))
              .isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                isCreditNote
                    ? _sl(ar: 'رقم إشعار الدائن', en: 'Credit Note No.', hi: 'क्रेडिट नोट नं.', ur: 'کریڈٹ نوٹ نمبر', es: 'N° Nota de Crédito', tr: 'Alacak Dekontu No.')
                    : _sl(ar: 'رقم الفاتورة', en: 'Invoice No.', hi: 'इनवॉइस नं.', ur: 'انوائس نمبر', es: 'N° Factura', tr: 'Fatura No.'),
                style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
        ],

        const DashedDivider(),
        const SizedBox(height: 2),

        _buildInfoItem(
            _ml(ar: 'الكاشير', en: 'Cashier', hi: 'कैशियर', ur: 'کیشیئر', es: 'Cajero', tr: 'Kasiyer'),
            _sl(ar: 'الكاشير', en: 'Cashier', hi: 'कैशियर', ur: 'کیشیئر', es: 'Cajero', tr: 'Kasiyer'),
            data!.cashierName?.isNotEmpty == true
                ? data!.cashierName!
                : (primaryLang != 'ar' && data!.sellerNameEn.isNotEmpty ? data!.sellerNameEn : data!.sellerNameAr)),
        _buildInfoItem(
            _ml(ar: 'الرقم الضريبي', en: 'Tax Number', hi: 'कर संख्या', ur: 'ٹیکس نمبر', es: 'Número de Impuesto', tr: 'Vergi Numarası'),
            _sl(ar: 'الرقم الضريبي', en: 'Tax Number', hi: 'कर संख्या', ur: 'ٹیکس نمبر', es: 'Número de Impuesto', tr: 'Vergi Numarası'),
            data!.vatNumber.isNotEmpty ? data!.vatNumber : _ml(ar: 'غير متوفر', en: 'N/A', hi: 'उपलब्ध नहीं', ur: 'دستیاب نہیں', es: 'No disponible', tr: 'Mevcut değil')),
        if (data!.commercialRegisterNumber?.isNotEmpty == true || commercialRegisterNumber?.isNotEmpty == true)
          _buildInfoItem(
              _ml(ar: 'رقم السجل التجاري', en: 'Commercial Register', hi: 'व्यावसायिक रजिस्टर', ur: 'تجارتی رجسٹر', es: 'Registro Comercial', tr: 'Ticari Sicil'),
              _sl(ar: 'رقم السجل التجاري', en: 'Commercial Register', hi: 'व्यावसायिक रजिस्टर', ur: 'تجارتی رجسٹر', es: 'Registro Comercial', tr: 'Ticari Sicil'),
              (data!.commercialRegisterNumber?.isNotEmpty == true ? data!.commercialRegisterNumber : commercialRegisterNumber)!),
        _buildInfoItem(
            _ml(ar: 'التاريخ والوقت', en: 'Date & Time', hi: 'दिनांक और समय', ur: 'تاریخ اور وقت', es: 'Fecha y Hora', tr: 'Tarih ve Saat'),
            _sl(ar: 'التاريخ والوقت', en: 'Date & Time', hi: 'दिनांक और समय', ur: 'تاریخ اور وقت', es: 'Fecha y Hora', tr: 'Tarih ve Saat'),
            _formatDateTime(data!.issueDateTime),
            isLtr: true),
        if (data?.paymentMethod != null)
          _buildInfoItem(
              _ml(ar: 'طريقة الدفع', en: 'Payment Method', hi: 'भुगतान विधि', ur: 'ادائیگی کا طریقہ', es: 'Método de Pago', tr: 'Ödeme Yöntemi'),
              _sl(ar: 'طريقة الدفع', en: 'Payment Method', hi: 'भुगतान विधि', ur: 'ادائیگی کا طریقہ', es: 'Método de Pago', tr: 'Ödeme Yöntemi'),
              _translatePayMethod(data!.paymentMethod)),

        if ((orderType?.isNotEmpty == true) || (data!.orderType?.isNotEmpty == true))
          _buildInfoItem(
              _ml(ar: 'نوع الطلب', en: 'Order Type', hi: 'ऑर्डर प्रकार', ur: 'آرڈر کی قسم', es: 'Tipo de Pedido', tr: 'Sipariş Türü'),
              _sl(ar: 'نوع الطلب', en: 'Order Type', hi: 'ऑर्डर प्रकार', ur: 'آرڈر کی قسم', es: 'Tipo de Pedido', tr: 'Sipariş Türü'),
              _getOrderTypeArabic(orderType?.isNotEmpty == true ? orderType! : data!.orderType!)),

        if (tableNumber != null || data!.tableNumber != null)
          _buildInfoItem(
              _ml(ar: 'رقم الطاولة', en: 'Table Number', hi: 'टेबल संख्या', ur: 'ٹیبل نمبر', es: 'Número de Mesa', tr: 'Masa Numarası'),
              _sl(ar: 'رقم الطاولة', en: 'Table Number', hi: 'टेबल संख्या', ur: 'ٹیبل نمبر', es: 'Número de Mesa', tr: 'Masa Numarası'),
              (tableNumber ?? data!.tableNumber)!),

        if ((clientName ?? data!.clientName) != null)
          _buildInfoItem(
              _ml(ar: 'العميل', en: 'Customer', hi: 'ग्राहक', ur: 'کسٹمر', es: 'Cliente', tr: 'Müşteri'),
              _sl(ar: 'العميل', en: 'Customer', hi: 'ग्राहक', ur: 'کسٹمر', es: 'Cliente', tr: 'Müşteri'),
              _translateClientName((clientName ?? data!.clientName)!)),

        if ((clientPhone ?? data!.clientPhone) != null)
          _buildInfoItem(
              _ml(ar: 'جوال العميل', en: 'Customer Phone', hi: 'ग्राहक फोन', ur: 'کسٹمر فون', es: 'Teléfono del Cliente', tr: 'Müşteri Telefonu'),
              _sl(ar: 'جوال العميل', en: 'Customer Phone', hi: 'ग्राहक फोन', ur: 'کسٹمر فون', es: 'Teléfono del Cliente', tr: 'Müşteri Telefonu'),
              (clientPhone ?? data!.clientPhone)!, isLtr: true),
          
        const SizedBox(height: 2),
      ],
    );
  }

  Widget _buildNumberBadge({
    required String labelAr,
    required String labelEn,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black, width: 1.5),
          ),
          child: Text(
            value,
            style: GoogleFonts.tajawal(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(String labelAr, String labelEn, String value,
      {bool isLtr = false}) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  labelAr,
                  style: GoogleFonts.tajawal(fontSize: 19, color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value,
                  style: GoogleFonts.tajawal(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.end,
                  textDirection: isLtr ? TextDirection.ltr : TextDirection.rtl,
                ),
              ),
            ],
          ),
          if (labelEn.isNotEmpty)
            Text(
              labelEn,
              style: GoogleFonts.tajawal(fontSize: 14, color: Colors.black, fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }

  Widget _buildInvoiceTitle() {
    return Column(
      children: [
        // Credit Note badge (above the tax invoice box)
        if (isCreditNote)
          Container(
            margin: const EdgeInsets.only(top: 7, bottom: 8),
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                Text(
                  _ml(ar: 'إشعار دائن', en: 'Credit Note', hi: 'क्रेडिट नोट', ur: 'کریڈٹ نوٹ', es: 'Nota de Crédito', tr: 'Alacak Dekontu'),
                  style: GoogleFonts.tajawal(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                if (_sl(ar: 'إشعار دائن', en: 'Credit Note', hi: 'क्रेडिट नोट', ur: 'کریڈٹ نوٹ', es: 'Nota de Crédito', tr: 'Alacak Dekontu').isNotEmpty)
                  Text(
                    _sl(ar: 'إشعار دائن', en: 'Credit Note', hi: 'क्रेडिट नोट', ur: 'کریڈٹ نوٹ', es: 'Nota de Crédito', tr: 'Alacak Dekontu'),
                    style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        Container(
      margin: EdgeInsets.symmetric(vertical: isCreditNote ? 0 : 4),
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 1.5),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _ml(ar: 'فاتورة ضريبية مبسطة', en: 'Simplified Tax Invoice', hi: 'सरलीकृत कर चालान', ur: 'آسان ٹیکس انوائس', es: 'Factura Fiscal Simplificada', tr: 'Basitleştirilmiş Vergi Faturası'),
            style: GoogleFonts.tajawal(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.black,
              letterSpacing: 0.3,
            ),
            textAlign: TextAlign.center,
          ),
          if (_sl(ar: 'فاتورة ضريبية مبسطة', en: 'Simplified Tax Invoice', hi: 'सरलीकृत कर चालान', ur: 'آسان ٹیکس انوائس', es: 'Factura Fiscal Simplificada', tr: 'Basitleştirilmiş Vergi Faturası').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              _sl(ar: 'فاتورة ضريبية مبسطة', en: 'Simplified Tax Invoice', hi: 'सरलीकृत कर चालان', ur: 'آسان ٹیکس انوائس', es: 'Factura Fiscal Simplificada', tr: 'Basitleştirilmiş Vergi Faturası'),
              style: GoogleFonts.tajawal(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    ),
      ],
    );
  }

  Widget _buildClientInfo() {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      child: Column(
        children: [
          if (clientName != null)
            _buildInfoItem(_ml(ar: 'اسم العميل', en: 'Client Name', hi: 'ग्राहक का नाम', ur: 'کلائنٹ کا نام', es: 'Nombre del Cliente', tr: 'Müşteri Adı'), _sl(ar: 'اسم العميل', en: 'Client Name', hi: 'ग्राहक का नाम', ur: 'کلائنٹ کا نام', es: 'Nombre del Cliente', tr: 'Müşteri Adı'), _translateClientName(clientName!)),
          if (clientPhone != null)
            _buildInfoItem(_ml(ar: 'جوال العميل', en: 'Client Phone', hi: 'ग्राहक फोन', ur: 'کلائنٹ فون', es: 'Teléfono del Cliente', tr: 'Müşteri Telefonu'), _sl(ar: 'جوال العميل', en: 'Client Phone', hi: 'ग्राहक फोन', ur: 'کلائنٹ فون', es: 'Teléfono del Cliente', tr: 'Müşteri Telefonu'), clientPhone!,
                isLtr: true),
          if (clientTaxNumber != null)
            _buildInfoItem(_ml(ar: 'الرقم الضريبي', en: 'Tax Number', hi: 'कर संख्या', ur: 'ٹیکس نمبر', es: 'Número de Impuesto', tr: 'Vergi Numarası'), _sl(ar: 'الرقم الضريبي', en: 'Tax Number', hi: 'कर संख्या', ur: 'ٹیکس نمبر', es: 'Número de Impuesto', tr: 'Vergi Numarası'), clientTaxNumber!),
        ],
      ),
    );
  }

  Widget _buildCarInfo([String? overrideCarNumber]) {
    final effectiveCarNumber = overrideCarNumber?.trim().isNotEmpty == true
        ? overrideCarNumber!
        : (data?.carNumber.isNotEmpty == true) ? data!.carNumber : (carNumber ?? '');
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.black)),
            ),
            child: Column(
              children: [
                Text(
                  _ml(ar: 'معلومات السيارة', en: 'Car Info', hi: 'कार की जानकारी', ur: 'گاڑی کی معلومات', es: 'Información del Vehículo', tr: 'Araç Bilgileri'),
                  style: GoogleFonts.tajawal(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          if (effectiveCarNumber.isNotEmpty)
            _buildCarInfoRow(_ml(ar: 'رقم اللوحة / التفاصيل', en: 'Plate No. / Details', hi: 'प्लेट नं. / विवरण', ur: 'پلیٹ نمبر / تفصیلات', es: 'Matrícula / Detalles', tr: 'Plaka No. / Detaylar'), _sl(ar: 'رقم اللوحة / التفاصيل', en: 'Plate No. / Details', hi: 'प्लेट नं. / विवरण', ur: 'پلیٹ نمبر / تفصیلات', es: 'Matrícula / Detalles', tr: 'Plaka No. / Detaylar'), effectiveCarNumber, isLast: true),
        ],
      ),
    );
  }

  Widget _buildCarInfoRow(String labelAr, String labelEn, String value,
      {bool isLast = false}) {
    return Row(
      children: [
        Container(
          width: 95,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: Colors.black)),
          ),
          child: Text(labelAr,
              style: GoogleFonts.tajawal(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.black)),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            child: Text(value,
                style:
                    GoogleFonts.tajawal(fontSize: 17, color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
