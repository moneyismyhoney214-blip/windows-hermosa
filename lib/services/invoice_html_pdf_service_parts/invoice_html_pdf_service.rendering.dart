// HTML render methods — split from invoice_html_pdf_service.dart for size.
part of '../invoice_html_pdf_service.dart';

extension InvoiceHtmlPdfServiceRendering on InvoiceHtmlPdfService {
  String _renderDocument(
    _PrintInvoiceModel model, {
    required int paperWidthMm,
  }) {
    final b = StringBuffer();

    b.writeln('<!DOCTYPE html>');
    b.writeln('<html lang="ar" dir="rtl">');
    b.writeln('<head>');
    b.writeln('<meta charset="UTF-8"/>');
    b.writeln(
        '<meta name="viewport" content="width=device-width, initial-scale=1.0"/>');
    b.writeln(
        '<link href="https://fonts.googleapis.com/css2?family=Tajawal:wght@400;500;700&display=swap" rel="stylesheet">');
    b.writeln('<style>');
    b.writeln(_buildStyleSheet(paperWidthMm));
    b.writeln('</style>');
    b.writeln('</head>');
    b.writeln('<body>');
    b.writeln('<div class="hidden">');
    b.writeln('<div class="bill bill-container size-5cm">');
    b.writeln(_renderHeader(model));
    b.writeln(_renderBody(model));
    b.writeln(_renderFooter(model));
    b.writeln('</div>');
    b.writeln('</div>');
    b.writeln('</body>');
    b.writeln('</html>');

    return b.toString();
  }

  /// Renders the <header> block — exact replica of PrintInvoice.vue lines 6-188.
  String _renderHeader(_PrintInvoiceModel model) {
    final b = StringBuffer();

    // --- data ---
    final logoUrl = _firstNonEmptyString([
          _pick(model.branch, const ['logo']),
          _pickPath(model.branch, 'seller.logo'),
          _pick(model.seller, const ['logo']),
        ]) ??
        '';
    final sellerName = _firstNonEmptyString([
          _pick(model.branch, const ['seller_name']),
          _pick(model.seller, const ['name', 'seller_name']),
        ]) ??
        '';
    final address = _firstNonEmptyString([
          _pick(model.branch, const ['branch_address', 'address', 'location']),
          _pick(model.seller, const ['address', 'seller_address']),
          _pick(model.invoice, const ['branch_address', 'address']),
        ]) ??
        '';
    final mobile = _firstNonEmptyString([
          _pick(model.branch, const [
            'branch_mobile',
            'branch_phone',
            'mobile',
            'phone',
            'telephone',
            'mobile_number'
          ]),
          _pick(model.seller, const ['mobile', 'phone', 'telephone']),
          _pick(model.invoice, const ['branch_mobile', 'branch_phone', 'mobile']),
        ]) ??
        '';
    final telephone = _firstNonEmptyString([
          _pick(model.branch,
              const ['telephone', 'landline', 'second_mobile', 'phone']),
        ]) ??
        '';
    final taxNumber = _firstNonEmptyString([
          _pick(model.seller, const ['tax_number', 'vat_number']),
          _pick(model.branch, const ['tax_number', 'vat_number']),
          _pick(model.invoice, const ['tax_number', 'vat_number']),
        ]) ??
        '';
    final commercialNumber = _firstNonEmptyString([
          _pick(model.branch, const [
            'commercial_register_number',
            'commercial_register',
            'commercial_number',
            'cr_number'
          ]),
          _pick(model.seller, const [
            'commercial_register_number',
            'commercial_register',
            'commercial_number',
            'cr_number'
          ]),
          _pick(model.invoice, const [
            'commercial_register_number',
            'commercial_register',
            'commercial_number',
            'cr_number'
          ]),
        ]) ??
        '';
    final cashier = _asMap(_pick(model.invoice, const ['cashier']));
    final cashierName = _firstNonEmptyString([
          _pick(cashier, const ['fullname', 'name'])
        ]) ??
        '';
    final parentInvoice =
        _asMap(_pick(model.invoice, const ['parent_invoice']));
    final parentInvoiceNumber = _firstNonEmptyString([
          _pick(parentInvoice, const ['invoice_number'])
        ]) ??
        '';
    final bookingTypeExtra = _asMap(_pick(model.booking, const ['type_extra']));
    final tableName = _firstNonEmptyString([
          _pick(bookingTypeExtra, const ['table_name'])
        ]) ??
        '';
    final carNumber = _firstNonEmptyString([
          _pick(bookingTypeExtra, const ['car_number'])
        ]) ??
        '';
    final originalInvoiceNumber = _firstNonEmptyString([
          _pick(model.invoice, const ['original_invoice_number'])
        ]) ??
        '';

    // --- HTML (mirrors Vue template exactly) ---
    b.writeln('<header>');
    b.writeln('<div class="seller-info">');

    // Logo
    b.writeln('<div class="logo-container flex justify-center mb-4">');
    if (logoUrl.isNotEmpty) {
      b.writeln(
          '<img src="${_escapeHtml(logoUrl)}" alt="" class="w-24 h-24 object-contain"/>');
    }
    b.writeln('</div>');

    // Info
    b.writeln('<div class="info">');
    b.writeln('<p class="title font-bold">${_escapeHtml(sellerName)}</p>');
    b.writeln('<p>${_escapeHtml(address)}</p>');
    if (mobile.isNotEmpty) {
      b.writeln('<p class="mobile">${_escapeHtml(mobile)}</p>');
    }
    if (telephone.isNotEmpty) {
      b.writeln('<p class="mobile">${_escapeHtml(telephone)}</p>');
    }
    b.writeln('</div>');

    // Info-bottom
    b.writeln('<div class="info-bottom">');

    // Order number box
    b.writeln('<div class="flex justify-center my-2">');
    final orderBoxNumber = model.dailyOrderNumber.isNotEmpty
        ? model.dailyOrderNumber
        : model.orderNumber;
    if (model.type.isNotEmpty && orderBoxNumber.isNotEmpty) {
      b.writeln(
          '<div class="border-2 border-black px-4 py-1 text-lg font-bold">Order# ${_escapeHtml(orderBoxNumber)}</div>');
    }
    b.writeln('</div>');

    // Invoice number box
    b.writeln('<div class="flex justify-center my-2">');
    final rawInvoiceNumber = model.invoiceNumber.replaceAll('#', '').trim();
    final invoiceDisplay = rawInvoiceNumber.isNotEmpty &&
            !rawInvoiceNumber.toUpperCase().startsWith('IN-')
        ? 'IN-$rawInvoiceNumber'
        : rawInvoiceNumber;
    b.writeln(
        '<div class="border-2 border-black px-4 py-1 text-lg font-bold">${_escapeHtml(invoiceDisplay)}</div>');
    b.writeln('</div>');

    // Cashier
    if (cashierName.isNotEmpty) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'الكاشير', en: 'Cashier', hi: 'कैशियर', ur: 'کیشیئر', es: 'Cajero', tr: 'Kasiyer')}</p>');
      b.writeln('<p>${_escapeHtml(cashierName)}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'الكاشير', en: 'Cashier', hi: 'कैशियर', ur: 'کیشیئر', es: 'Cajero', tr: 'Kasiyer'))}</p>');
      b.writeln('</div>');
    }

    // Tax number
    b.writeln('<div class="info-bottom-item">');
    b.writeln('<p>${_mainLbl(model.language, ar: 'الرقم الضريبي', en: 'Tax Number', hi: 'कर संख्या', ur: 'ٹیکس نمبر', es: 'Número de Impuesto', tr: 'Vergi Numarası')}</p>');
    b.writeln('<p>${_escapeHtml(taxNumber)}</p>');
    b.writeln(
        '<p>${_escapeHtml(_altLabel(model.language, ar: 'الرقم الضريبي', en: 'Tax Number', hi: 'कर संख्या', ur: 'ٹیکس نمبر', es: 'Número de Impuesto', tr: 'Vergi Numarası'))}</p>');
    b.writeln('</div>');

    // Commercial number
    if (commercialNumber.isNotEmpty) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'رقم السجل التجاري', en: 'Commercial Register Number', hi: 'व्यावसायिक रजिस्टर संख्या', ur: 'تجارتی رجسٹر نمبر', tr: 'Ticari Sicil Numarası', es: 'Número de Registro Comercial')}</p>');
      b.writeln('<p>${_escapeHtml(commercialNumber)}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'رقم السجل التجاري', en: 'Commercial Register Number', hi: 'व्यावसायिक रजिस्टर संख्या', ur: 'تجارتی رجسٹر نمبر', tr: 'Ticari Sicil Numarası', es: 'Número de Registro Comercial'))}</p>');
      b.writeln('</div>');
    }

    // Date
    b.writeln('<div class="info-bottom-item">');
    b.writeln('<p>${_mainLbl(model.language, ar: 'التاريخ', en: 'Date', hi: 'दिनांक', ur: 'تاریخ', es: 'Fecha', tr: 'Tarih')}</p>');
    b.writeln('<p>${_escapeHtml(model.date)}</p>');
    b.writeln(
        '<p>${_escapeHtml(_altLabel(model.language, ar: 'التاريخ', en: 'Date', hi: 'दिनांक', ur: 'تاریخ', es: 'Fecha', tr: 'Tarih'))}</p>');
    b.writeln('</div>');

    // Time
    b.writeln('<div class="info-bottom-item">');
    b.writeln('<p>${_mainLbl(model.language, ar: 'الوقت', en: 'Time', hi: 'समय', ur: 'وقت', es: 'Hora', tr: 'Saat')}</p>');
    b.writeln('<p class="force-ltr">${_escapeHtml(model.time)}</p>');
    b.writeln(
        '<p>${_escapeHtml(_altLabel(model.language, ar: 'الوقت', en: 'Time', hi: 'समय', ur: 'وقت', es: 'Hora', tr: 'Saat'))}</p>');
    b.writeln('</div>');

    // Order number (restaurant only)
    if (model.type.isNotEmpty && model.type.contains('restaurant')) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'رقم الطلب', en: 'Order Number', hi: 'ऑर्डर संख्या', ur: 'آرڈر نمبر', es: 'Número de Pedido', tr: 'Sipariş Numarası')}</p>');
      b.writeln('<p class="force-ltr">${_escapeHtml(_firstNonEmptyString([
                _pick(model.booking, const ['daily_order_number']),
                model.dailyOrderNumber
              ]) ?? '')}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'رقم الطلب', en: 'Order Number', hi: 'ऑर्डर संख्या', ur: 'آرڈر نمبر', es: 'Número de Pedido', tr: 'Sipariş Numarası'))}</p>');
      b.writeln('</div>');
    }

    // Parent invoice
    if (parentInvoiceNumber.isNotEmpty) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'الفاتورة الأب', en: 'Parent Invoice', hi: 'पेरेंट इनवॉइस', ur: 'پیرنٹ انوائس', es: 'Factura Principal', tr: 'Ana Fatura')}</p>');
      b.writeln('<p class="force-ltr">${_escapeHtml(parentInvoiceNumber)}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'الفاتورة الأب', en: 'Parent Invoice', hi: 'पेरेंट इनवॉइस', ur: 'پیرنٹ انوائس', es: 'Factura Principal', tr: 'Ana Fatura'))}</p>');
      b.writeln('</div>');
    }

    // Order type
    if (model.type.isNotEmpty) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'نوع الطلب', en: 'Order Type', hi: 'ऑर्डर प्रकार', ur: 'آرڈر کی قسم', es: 'Tipo de Pedido', tr: 'Sipariş Türü')}</p>');
      b.writeln('<p>${_escapeHtml(_resolveOrderTypeLabel(model.type, model.language.primary))}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'نوع الطلب', en: 'Order Type', hi: 'ऑर्डर प्रकार', ur: 'آرڈر کی قسم', es: 'Tipo de Pedido', tr: 'Sipariş Türü'))}</p>');
      b.writeln('</div>');
    }

    // Table number (restaurant_internal)
    if (model.type == 'restaurant_internal' && tableName.isNotEmpty) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'رقم الطاوله', en: 'Table Number', hi: 'टेबल संख्या', ur: 'ٹیبل نمبر', es: 'Número de Mesa', tr: 'Masa Numarası')}</p>');
      b.writeln('<p>${_escapeHtml(tableName)}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'رقم الطاوله', en: 'Table Number', hi: 'टेबल संख्या', ur: 'ٹیبل نمبر', es: 'Número de Mesa', tr: 'Masa Numarası'))}</p>');
      b.writeln('</div>');
    }

    // Car number (restaurant_parking)
    if (model.type == 'restaurant_parking' && carNumber.isNotEmpty) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'رقم السياره', en: 'Car Number', hi: 'कार संख्या', ur: 'کار نمبر', es: 'Número de Auto', tr: 'Araç Numarası')}</p>');
      b.writeln('<p>${_escapeHtml(carNumber)}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'رقم السياره', en: 'Car Number', hi: 'कार संख्या', ur: 'کار نمبر', es: 'Número de Auto', tr: 'Araç Numarası'))}</p>');
      b.writeln('</div>');
    }

    // Original invoice number (refund)
    if (originalInvoiceNumber.isNotEmpty) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'رقم فاتورة الاسترجاع', en: 'Refund Invoice ID', hi: 'रिफंड इनवॉइस आईडी', ur: 'ریفنڈ انوائس آئی ڈی', es: 'ID de Factura de Reembolso', tr: 'İade Fatura Kimliği')}</p>');
      b.writeln(
          '<p class="force-ltr">${_escapeHtml(originalInvoiceNumber)}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'رقم فاتورة الاسترجاع', en: 'Refund Invoice ID', hi: 'रिफंड इनवॉइस आईडी', ur: 'ریفنڈ انوائس آئی ڈی', es: 'ID de Factura de Reembolso', tr: 'İade Fatura Kimliği'))}</p>');
      b.writeln('</div>');
    }

    // Booking date
    if (model.bookingDate.isNotEmpty) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'تاريخ الحجز', en: 'Booking Date', hi: 'बुकिंग दिनांक', ur: 'بکنگ تاریخ', es: 'Fecha de Reserva', tr: 'Rezervasyon Tarihi')}</p>');
      b.writeln('<p>${_escapeHtml(model.bookingDate)}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'تاريخ الحجز', en: 'Booking Date', hi: 'बुकिंग दिनांक', ur: 'بکنگ تاریخ', es: 'Fecha de Reserva', tr: 'Rezervasyon Tarihi'))}</p>');
      b.writeln('</div>');
    }

    b.writeln('</div>'); // info-bottom
    b.writeln('</div>'); // seller-info
    b.writeln('</header>');

    return b.toString();
  }

  String _renderBody(_PrintInvoiceModel model) {
    final b = StringBuffer();

    b.writeln('<section>');

    b.writeln('<div class="invoice-title">');
    b.writeln('<p>${_escapeHtml(model.title.text)}</p>');
    b.writeln('<p>${_escapeHtml(model.title.textAlt)}</p>');
    b.writeln('</div>');

    b.writeln(_renderClientSection(model));
    b.writeln(_renderCarInfoSection(model));
    b.writeln(_renderItemsSection(model));
    b.writeln(_renderInvoiceDetailsSection(model));

    b.writeln('</section>');

    return b.toString();
  }

  String _renderClientSection(_PrintInvoiceModel model) {
    if (model.client.isEmpty) return '';

    final clientName = _firstNonEmptyString([
          _pick(model.client, const ['name'])
        ]) ??
        '';
    final clientMobile = _firstNonEmptyString([
          _pick(model.client, const ['mobile', 'phone']),
        ]) ??
        '';
    final clientTax = _firstNonEmptyString([
          _pick(model.client, const ['tax_number']),
        ]) ??
        '';
    final clientCommercial = _firstNonEmptyString([
          _pick(model.client, const ['commercial_register']),
        ]) ??
        '';

    final b = StringBuffer();

    b.writeln('<div>');
    b.writeln('<div class="client-info">');
    b.writeln('<div class="client-info-item">');
    b.writeln('<p class="font-bold">${_mainLbl(model.language, ar: 'اسم العميل', en: 'Client Name', hi: 'ग्राहक का नाम', ur: 'کلائنٹ کا نام', es: 'Nombre del Cliente', tr: 'Müşteri Adı')}</p>');
    b.writeln(
      '<p class="font-bold">${_escapeHtml(_altLabel(model.language, ar: 'اسم العميل', en: 'Client Name', hi: 'ग्राहक का नाम', ur: 'کلائنٹ کا نام', es: 'Nombre del Cliente', tr: 'Müşteri Adı'))}</p>',
    );
    b.writeln('<p>${_escapeHtml(clientName)}</p>');
    b.writeln('</div>');

    b.writeln('<div class="client-info-item">');
    b.writeln('<p class="font-bold">${_mainLbl(model.language, ar: 'جوال العميل', en: 'Client Phone', hi: 'ग्राहक फोन', ur: 'کلائنٹ فون', es: 'Teléfono del Cliente', tr: 'Müşteri Telefonu')}</p>');
    b.writeln(
      '<p class="font-bold">${_escapeHtml(_altLabel(model.language, ar: 'جوال العميل', en: 'Client Phone', hi: 'ग्राहक फोन', ur: 'کلائنٹ فون', es: 'Teléfono del Cliente', tr: 'Müşteri Telefonu'))}</p>',
    );
    b.writeln('<p style="direction: ltr">${_escapeHtml(clientMobile)}</p>');
    b.writeln('</div>');
    b.writeln('</div>');

    b.writeln('<div class="client-info mt-2">');

    if (clientTax.isNotEmpty) {
      b.writeln('<div class="client-info-item">');
      b.writeln('<p class="font-bold">${_mainLbl(model.language, ar: 'الرقم الضريبي', en: 'Tax number', hi: 'कर संख्या', ur: 'ٹیکس نمبر', es: 'Número de Impuesto', tr: 'Vergi Numarası')}</p>');
      b.writeln(
        '<p class="font-bold">${_escapeHtml(_altLabel(model.language, ar: 'الرقم الضريبي', en: 'Tax number', hi: 'कर संख्या', ur: 'ٹیکس نمبر', es: 'Número de Impuesto', tr: 'Vergi Numarası'))}</p>',
      );
      b.writeln('<p>${_escapeHtml(clientTax)}</p>');
      b.writeln('</div>');
    }

    if (clientCommercial.isNotEmpty) {
      b.writeln('<div class="client-info-item">');
      b.writeln('<p class="font-bold">${_mainLbl(model.language, ar: 'السجل التجاري', en: 'Commercial register', hi: 'व्यावसायिक रजिस्टर', ur: 'تجارتی رجسٹر', es: 'Registro Comercial', tr: 'Ticari Sicil')}</p>');
      b.writeln(
        '<p class="font-bold">${_escapeHtml(_altLabel(model.language, ar: 'السجل التجاري', en: 'Commercial register', hi: 'व्यावसायिक रजيس्टर', ur: 'تجارتی رجسٹر', es: 'Registro Comercial', tr: 'Ticari Sicil'))}</p>',
      );
      b.writeln(
          '<p style="direction: ltr">${_escapeHtml(clientCommercial)}</p>');
      b.writeln('</div>');
    }

    b.writeln('</div>');
    b.writeln('</div>');

    return b.toString();
  }

  String _renderCarInfoSection(_PrintInvoiceModel model) {
    if (!_isCarCare(model) || model.carInfo.isEmpty) return '';

    final b = StringBuffer();

    b.writeln('<div class="mt-2">');
    b.writeln(
      '<table class="car-info-table w-full border-collapse border border-gray-300 text-xs">',
    );
    b.writeln('<thead><tr>');
    b.writeln(
      '<th colspan="2" class="border border-gray-300 px-2 py-1 bg-gray-50 text-center font-bold text-sm">',
    );
    b.writeln(
        '${_mainLbl(model.language, ar: 'معلومات السيارة', en: 'Car Information', hi: 'कार की जानकारी', ur: 'کار کی معلومات', es: 'Información del Vehículo', tr: 'Araç Bilgileri')} ${_escapeHtml(_altLabel(model.language, ar: 'معلومات السيارة', en: 'Car Information', hi: 'कार की जानकारी', ur: 'کار کی معلومات', es: 'Información del Vehículo', tr: 'Araç Bilgileri'))}');
    b.writeln('</th></tr></thead>');

    b.writeln('<tbody>');
    b.writeln(_carInfoRow(
      model,
      ar: _mainLbl(model.language, ar: 'الماركة', en: 'Brand', hi: 'ब्रांड', ur: 'برانڈ', es: 'Marca', tr: 'Marka'),
      alt: _altLabel(
        model.language,
        ar: 'الماركة',
        hi: 'ब्रांड',
        ur: 'برانڈ',
        tr: 'Marka',
        en: 'Brand',
        es: 'Marca',
      ),
      value: _firstNonEmptyString([
            _pick(model.carInfo, const ['brand'])
          ]) ??
          '',
    ));
    b.writeln(_carInfoRow(
      model,
      ar: _mainLbl(model.language, ar: 'الموديل', en: 'Model', hi: 'मॉडल', ur: 'ماڈل', es: 'Modelo', tr: 'Model'),
      alt: _altLabel(
        model.language,
        ar: 'الموديل',
        hi: 'मॉडल',
        ur: 'ماڈل',
        tr: 'Model',
        en: 'Model',
        es: 'Modelo',
      ),
      value: _firstNonEmptyString([
            _pick(model.carInfo, const ['model'])
          ]) ??
          '',
    ));
    b.writeln(_carInfoRow(
      model,
      ar: _mainLbl(model.language, ar: 'رقم اللوحة', en: 'Plate Number', hi: 'प्लेट नंबर', ur: 'پلیٹ نمبر', es: 'Número de Placa', tr: 'Plaka Numarası'),
      alt: _altLabel(
        model.language,
        ar: 'رقم اللوحة',
        hi: 'प्लेट नंबर',
        ur: 'پلیٹ نمبر',
        tr: 'Plaka Numarası',
        en: 'Plate Number',
        es: 'Número de Placa',
      ),
      value: _firstNonEmptyString([
            _pick(model.carInfo, const ['plate'])
          ]) ??
          '',
    ));

    final year = _firstNonEmptyString([
          _pick(model.carInfo, const ['year'])
        ]) ??
        '';
    if (year.isNotEmpty) {
      b.writeln(_carInfoRow(
        model,
        ar: _mainLbl(model.language, ar: 'السنة', en: 'Year', hi: 'साल', ur: 'سال', es: 'Año', tr: 'Yıl'),
        alt: _altLabel(
          model.language,
          ar: 'السنة',
          hi: 'साल',
          ur: 'سال',
          tr: 'Yıl',
          en: 'Year',
          es: 'Año',
        ),
        value: year,
      ));
    }

    b.writeln('</tbody></table></div>');

    return b.toString();
  }

  String _carInfoRow(
    _PrintInvoiceModel model, {
    required String ar,
    required String alt,
    required String value,
  }) {
    return '''
<tr>
  <td class="border border-gray-300 px-2 py-1 font-bold text-sm">${_escapeHtml(ar)} ${_escapeHtml(alt)}</td>
  <td class="border border-gray-300 px-2 py-1 text-sm">${_escapeHtml(value)}</td>
</tr>
''';
  }

  String _renderItemsSection(_PrintInvoiceModel model) {
    if (model.items.isEmpty) return '';

    final showItemName = _isValidAttribute('item_name', model.fields);
    final showCode = _isValidAttribute('code', model.fields);
    final showExpiry = _isValidAttribute('expiry', model.fields);
    final showService = _isValidAttribute('service_name', model.fields) ||
        _isValidAttribute('meal_name', model.fields);
    final showEmployee = _isValidAttribute('employee_name', model.fields);
    final showQuantity = _isValidAttribute('quantity', model.fields);
    final showDiscount = _isValidAttribute('discount', model.fields);
    final showTotal = _isValidAttribute('total', model.fields);
    final showDate = _isValidAttribute('date', model.fields);
    final showTime = _isValidAttribute('time', model.fields);
    final showOrder =
        _isValidAttribute('order', model.fields) && model.hasOrders;

    final b = StringBuffer();

    b.writeln('<div class="invoice-items">');
    b.writeln('<table>');

    b.writeln('<thead><tr>');
    if (showItemName) b.writeln('<th>${_mainLbl(model.language, ar: 'الصنف', en: 'Item', hi: 'वस्तु', ur: 'آئٹم', es: 'Artículo', tr: 'Ürün')}</th>');
    if (showCode) b.writeln('<th>${_mainLbl(model.language, ar: 'كود الهدية', en: 'Gift Card Code', hi: 'गिफ्ट कार्ड कोड', ur: 'گفٹ کارڈ کوڈ', es: 'Código de Tarjeta Regalo', tr: 'Hediye Kartı Kodu')}</th>');
    if (showExpiry) b.writeln('<th>${_mainLbl(model.language, ar: 'تاريخ الانتهاء', en: 'Expiry Date', hi: 'समाप्ति तिथि', ur: 'ختم ہونے کی تاریخ', es: 'Fecha de Vencimiento', tr: 'Son Kullanma Tarihi')}</th>');
    if (showService) b.writeln('<th>${_mainLbl(model.language, ar: 'الخدمة', en: 'Service', hi: 'सेवा', ur: 'سروس', es: 'Servicio', tr: 'Hizmet')}</th>');
    if (showEmployee) b.writeln('<th>${_mainLbl(model.language, ar: 'الموظف/ة', en: 'Employee', hi: 'कर्मचारी', ur: 'ملازم', es: 'Empleado', tr: 'Çalışan')}</th>');
    if (showQuantity) b.writeln('<th>${_mainLbl(model.language, ar: 'الكمية', en: 'Quantity', hi: 'मात्रा', ur: 'مقدار', es: 'Cantidad', tr: 'Miktar')}</th>');
    if (showDiscount) b.writeln('<th>${_mainLbl(model.language, ar: 'الخصم', en: 'Discount', hi: 'छूट', ur: 'ڈسکاؤنٹ', es: 'Descuento', tr: 'İndirim')}</th>');
    if (showTotal) b.writeln('<th>${_mainLbl(model.language, ar: 'الاجمالي', en: 'Price', hi: 'कुल', ur: 'کل', es: 'Precio', tr: 'Toplam')}</th>');
    if (showDate) b.writeln('<th>${_mainLbl(model.language, ar: 'التاريخ', en: 'Date', hi: 'दिनांक', ur: 'تاریخ', es: 'Fecha', tr: 'Tarih')}</th>');
    if (showTime) b.writeln('<th>${_mainLbl(model.language, ar: 'الوقت', en: 'Time', hi: 'समय', ur: 'وقت', es: 'Hora', tr: 'Saat')}</th>');
    if (showOrder) b.writeln('<th>${_mainLbl(model.language, ar: 'الدور', en: 'Order', hi: 'क्रम', ur: 'آرڈر', es: 'Orden', tr: 'Sıra')}</th>');
    b.writeln('</tr></thead>');

    b.writeln('<thead><tr>');
    if (showItemName) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'الصنف', hi: 'वस्तु', ur: 'آئٹم', tr: 'Ürün', en: 'Item', es: 'Artículo'))}</th>',
      );
    }
    if (showCode) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'كود الهدية', hi: 'गिफ्ट कार्ड कोड', ur: 'گفٹ کارڈ کوڈ', tr: 'Hediye Kartı Kodu', en: 'Gift Card Code', es: 'Código de Tarjeta Regalo'))}</th>',
      );
    }
    if (showExpiry) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'تاريخ الانتهاء', hi: 'समाप्ति तिथि', ur: 'ختم ہونے کی تاریخ', tr: 'Son Kullanma Tarihi', en: 'Expiry Date', es: 'Fecha de Vencimiento'))}</th>',
      );
    }
    if (showService) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'الخدمة', hi: 'सेवा', ur: 'سروس', tr: 'Hizmet', en: 'Service', es: 'Servicio'))}</th>',
      );
    }
    if (showEmployee) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'الموظف/ة', hi: 'कर्मचारी', ur: 'ملازم', tr: 'Çalışan', en: 'Employee', es: 'Empleado'))}</th>',
      );
    }
    if (showQuantity) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'الكمية', hi: 'मात्रा', ur: 'مقدار', tr: 'Miktar', en: 'Quantity', es: 'Cantidad'))}</th>',
      );
    }
    if (showDiscount) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'الخصم', hi: 'छूट', ur: 'ڈسکاؤنٹ', tr: 'İndirim', en: 'Discount', es: 'Descuento'))}</th>',
      );
    }
    if (showTotal) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'الاجمالي', hi: 'कुल', ur: 'کل', tr: 'Toplam', en: 'Price', es: 'Precio'))}</th>',
      );
    }
    if (showDate) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'التاريخ', hi: 'दिनांक', ur: 'تاریخ', tr: 'Tarih', en: 'Date', es: 'Fecha'))}</th>',
      );
    }
    if (showTime) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'الوقت', hi: 'समय', ur: 'وقت', tr: 'Saat', en: 'Time', es: 'Hora'))}</th>',
      );
    }
    if (showOrder) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'الدور', hi: 'क्रम', ur: 'آرڈر', tr: 'Sıra', en: 'Order', es: 'Orden'))}</th>',
      );
    }
    b.writeln('</tr></thead>');

    b.writeln('<tbody>');

    for (var index = 0; index < model.items.length; index++) {
      final item = model.items[index];
      final row = StringBuffer();

      for (final entry in item.entries) {
        final key = entry.key.toString();
        if (!_isValidAttribute(key, model.fields)) continue;
        if ((key == 'order' || key == 'addons') && !model.hasOrders) continue;

        final classes = <String>[];
        if (const ['quantity', 'total', 'order'].contains(key)) {
          classes.add('text-center');
        }
        if (const ['date', 'time', 'order', 'code', 'expiry'].contains(key)) {
          classes.addAll(const ['whitespace-nowrap', 'force-ltr']);
        }

        row.write('<td');
        if (classes.isNotEmpty) {
          row.write(' class="${classes.join(' ')}"');
        }
        row.write('>');

        final addons = _extractItemAddonsForRender(item);
        final combos = _asMapList(item['combos']);
        final canRenderAddons = _isRestaurant(model) &&
            key == 'item_name' &&
            (addons.isNotEmpty || combos.isNotEmpty);

        if (canRenderAddons) {
          row.write('<table class="addons-table">');
          row.write('<tr><td>');
          row.write('<div class="flex justify-between">');
          row.write('<p>${_escapeHtml(_displayValue(entry.value))}</p>');
          row.write('<p>${_escapeHtml(_displayValue(_pick(item, const [
                'meal_price'
              ])))}</p>');
          row.write('</div>');

          for (final combo in combos) {
            final comboQty = _displayValue(_pick(combo, const ['quantity']));
            final comboName = _displayValue(_pick(combo, const ['name']));
            row.write(
              '<p class="addon-size">${_escapeHtml(comboQty)} X ${_escapeHtml(comboName)}</p>',
            );
          }

          row.write('</td></tr>');

          for (final addon in addons) {
            // `attribute` and `option` are language-keyed maps (e.g.
            // `{ar: "نوع الطهي", en: "Cooking type"}`). Resolve them through
            // the invoice language picker so the PDF/HTML invoice matches
            // the cashier's chosen primary/secondary language.
            final attributePrimary = _localizedValue(
                _pick(addon, const ['attribute']), model.language.primary);
            final optionPrimary = _localizedValue(
                _pick(addon, const ['option']), model.language.primary);
            final attributeSecondary = model.language.allowSecondary &&
                    model.language.secondary != model.language.primary
                ? _localizedValue(
                    _pick(addon, const ['attribute']), model.language.secondary)
                : '';
            final optionSecondary = model.language.allowSecondary &&
                    model.language.secondary != model.language.primary
                ? _localizedValue(
                    _pick(addon, const ['option']), model.language.secondary)
                : '';
            final total = _displayValue(_pick(addon, const ['total']));
            final primaryLabel = '$attributePrimary $optionPrimary'.trim();
            final secondaryLabel = '$attributeSecondary $optionSecondary'.trim();
            row.write('<tr>');
            row.write(
                '<td class="addon-item addon-size">${_escapeHtml(primaryLabel)}');
            if (secondaryLabel.isNotEmpty && secondaryLabel != primaryLabel) {
              row.write(
                  '<br><span class="addon-size-alt">${_escapeHtml(secondaryLabel)}</span>');
            }
            row.write('</td>');
            row.write(
                '<td class="addon-size text-center">${_escapeHtml(total)}</td>');
            row.write('</tr>');
          }

          row.write('</table>');
        } else {
          final value = _resolveItemTableValue(key, item, entry.value);
          row.write('<p>${_escapeHtml(value)}</p>');
        }

        row.write('</td>');
      }

      if (row.isNotEmpty) {
        b.writeln('<tr>${row.toString()}</tr>');
      }
    }

    b.writeln('</tbody>');
    b.writeln('</table>');
    b.writeln('</div>');

    return b.toString();
  }

  String _resolveItemTableValue(
    String key,
    Map<String, dynamic> item,
    dynamic fallback,
  ) {
    dynamic value;
    if (key == 'total') {
      value = _pick(item, const ['total', 'total_tax']);
      value ??= 0;
    } else if (key == 'price') {
      value = _pick(item, const ['price', 'total']);
      value ??= fallback;
    } else if (key == 'service_name' || key == 'meal_name') {
      value = _pick(item, const ['meal_name', 'service_name']);
      value ??= fallback;
    } else {
      value = fallback;
    }

    return _displayValue(value);
  }

  String _renderInvoiceDetailsSection(_PrintInvoiceModel model) {
    final invoice = model.invoice;
    final b = StringBuffer();

    b.writeln('<div class="invoice-details">');

    if (_truthy(_pick(invoice, const ['pre_paid']))) {
      b.writeln(_invoiceAmountRow(
        model,
        value: _displayValue(_pick(invoice, const ['pre_paid'])),
        titleAr: _mainLbl(model.language, ar: 'الدفع المسبق', en: 'Pre Paid Amount', hi: 'पूर्व भुगतान राशि', ur: 'پری پیڈ رقم', es: 'Monto Prepagado', tr: 'Ön Ödeme Tutarı'),
        titleAlt: _altLabel(
          model.language,
          ar: 'الدفع المسبق',
          hi: 'पूर्व भुगतान राशि',
          ur: 'پری پیڈ رقم',
          tr: 'Ön Ödeme Tutarı',
          en: 'Pre Paid Amount',
          es: 'Monto Prepagado',
        ),
      ));
    }

    if (_truthy(_pick(invoice, const ['price']))) {
      b.writeln(_invoiceAmountRow(
        model,
        value: model.calculatedPriceBeforeTax,
        titleAr: _mainLbl(model.language, ar: 'الاجمالي قبل الضريبة', en: 'Total Before Tax', hi: 'कर से पहले कुल', ur: 'ٹیکس سے پہلے کل', es: 'Total antes de Impuesto', tr: 'Vergi Öncesi Toplam'),
        titleAlt: _altLabel(
          model.language,
          ar: 'الاجمالي قبل الضريبة',
          hi: 'कर से पहले कुल',
          ur: 'ٹیکس سے پہلے کل',
          tr: 'Vergi Öncesi Toplam',
          en: 'Total Before Tax',
          es: 'Total antes de Impuesto',
        ),
      ));
    }

    if (_truthy(_pick(invoice, const ['discount']))) {
      b.writeln(_invoiceAmountRow(
        model,
        value: _displayValue(_pick(invoice, const ['discount'])),
        titleAr: _mainLbl(model.language, ar: 'قيمة الخصم', en: 'Discount Amount', hi: 'छूट राशि', ur: 'ڈسکاؤنٹ رقم', es: 'Monto de Descuento', tr: 'İndirim Tutarı'),
        titleAlt: _altLabel(
          model.language,
          ar: 'قيمة الخصم',
          hi: 'छूट राशि',
          ur: 'ڈسکاؤنٹ رقم',
          tr: 'İndirim Tutarı',
          en: 'Discount Amount',
          es: 'Monto de Descuento',
        ),
      ));
    }

    if (!_truthy(_pick(invoice, const ['discount'])) &&
        _truthy(_pick(invoice, const ['total_items_discount']))) {
      b.writeln(_invoiceAmountRow(
        model,
        value: _displayValue(_pick(invoice, const ['total_items_discount'])),
        titleAr: _mainLbl(model.language, ar: 'إجمالي خصم الأصناف', en: 'Total Items Discount', hi: 'कुल आइटम छूट', ur: 'کل آئٹم ڈسکاؤنٹ', es: 'Descuento Total de Artículos', tr: 'Toplam Ürün İndirimi'),
        titleAlt: _altLabel(
          model.language,
          ar: 'إجمالي خصم الأصناف',
          hi: 'कुल आइटम छूट',
          ur: 'کل آئٹم ڈسکاؤنٹ',
          tr: 'Toplam Ürün İndirimi',
          en: 'Total Items Discount',
          es: 'Descuento Total de Artículos',
        ),
      ));
    }

    if (_truthy(_pick(invoice, const ['price_after_discount']))) {
      b.writeln(_invoiceAmountRow(
        model,
        value: _displayValue(_pick(invoice, const ['price_after_discount'])),
        titleAr: _mainLbl(model.language, ar: 'الاجمالي بعد الخصم', en: 'Total After Discount', hi: 'छूट के बाद कुल', ur: 'ڈسکاؤنٹ کے بعد کل', es: 'Total después del Descuento', tr: 'İndirim Sonrası Toplam'),
        titleAlt: _altLabel(
          model.language,
          ar: 'الاجمالي بعد الخصم',
          hi: 'छूट के बाद कुल',
          ur: 'ڈسکاؤنٹ کے بعد کل',
          tr: 'İndirim Sonrası Toplam',
          en: 'Total After Discount',
          es: 'Total después del Descuento',
        ),
      ));
    }

    if (_truthy(_pick(invoice, const ['tax']))) {
      b.writeln(_invoiceAmountRow(
        model,
        value: _displayValue(_pick(invoice, const ['tax'])),
        titleAr: _mainLbl(model.language, ar: 'قيمة الضريبة', en: 'Tax Amount', hi: 'कर राशि', ur: 'ٹیکس رقم', es: 'Monto de Impuesto', tr: 'Vergi Tutarı'),
        titleAlt: _altLabel(
          model.language,
          ar: 'قيمة الضريبة',
          hi: 'कर राशि',
          ur: 'ٹیکس رقم',
          tr: 'Vergi Tutarı',
          en: 'Tax Amount',
          es: 'Monto de Impuesto',
        ),
      ));
    }

    if (_truthy(_pick(invoice, const ['total']))) {
      b.writeln(_invoiceAmountRow(
        model,
        value: _displayValue(_pick(invoice, const ['total'])),
        titleAr: _mainLbl(model.language, ar: 'الاجمالي بعد الضريبة', en: 'Total After Tax', hi: 'कर के बाद कुल', ur: 'ٹیکس کے بعد کل', es: 'Total con Impuesto', tr: 'Vergi Sonrası Toplam'),
        titleAlt: _altLabel(
          model.language,
          ar: 'الاجمالي بعد الضريبة',
          hi: 'कर के बाद कुल',
          ur: 'ٹیکس کے بعد کل',
          tr: 'Vergi Sonrası Toplam',
          en: 'Total After Tax',
          es: 'Total con Impuesto',
        ),
      ));
    }

    if (_truthy(model.paymentMethods)) {
      b.writeln(
          '<div class="invoice-details-item flex justify-between items-center">');
      b.writeln('<div class="w-7/12">');
      b.writeln('<p class="price">${_escapeHtml(model.paymentMethods)}</p>');
      b.writeln('</div>');
      b.writeln('<div class="invoice-item-title text-left">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'طرق الدفع', en: 'Payment Methods', hi: 'भुगतान विधियां', ur: 'ادائیگی کے طریقے', es: 'Métodos de Pago', tr: 'Ödeme Yöntemleri')}</p>');
      b.writeln(
        '<p>${_escapeHtml(_altLabel(model.language, ar: 'طرق الدفع', hi: 'भुगतान विधियां', ur: 'ادائیگی کے طریقے', tr: 'Ödeme Yöntemleri', en: 'Payment Methods', es: 'Métodos de Pago'))}</p>',
      );
      b.writeln('</div>');
      b.writeln('</div>');
    }

    b.writeln('</div>');
    return b.toString();
  }

  String _invoiceAmountRow(
    _PrintInvoiceModel model, {
    required dynamic value,
    required String titleAr,
    required String titleAlt,
  }) {
    return '''
<div class="invoice-details-item flex justify-between items-center">
  <div class="flex items-center text-right">
    <div class="currency-area">
      <p>${_escapeHtml(model.currencyAr)}</p>
      <p>${_escapeHtml(model.currencyEn)}</p>
    </div>
    <p class="price">${_escapeHtml(_displayValue(value))}</p>
  </div>
  <div class="invoice-item-title text-left">
    <p>${_escapeHtml(titleAr)}</p>
    <p>${_escapeHtml(titleAlt)}</p>
  </div>
</div>
''';
  }

  String _renderFooter(_PrintInvoiceModel model) {
    final b = StringBuffer();

    b.writeln('<footer class="invoice-details">');
    b.writeln('<div class="flex justify-center">');
    if (model.qrImage.isNotEmpty) {
      b.writeln('<img src="${_escapeHtml(model.qrImage)}"/>');
    }
    b.writeln('</div>');

    b.writeln('<div class="invoice-details-item">');
    b.writeln(
        '<p class="invoice-title" style="border-bottom: 0">سياسة الاسترجاع</p>');
    b.writeln(
      '<div style="white-space: pre-wrap" class="pb-2">${_renderPolicyHtml(model.policy)}</div>',
    );
    b.writeln('</div>');

    b.writeln('<div class="mt-2">');
    b.writeln('<p>${_mainLbl(model.language, ar: 'شكرا لثقتكم بنا', en: 'Thank you for trusting us', hi: 'हम पर विश्वास करने के लिए धन्यवाद', ur: 'ہم پر اعتماد کرنے کا شکریہ', es: 'Gracias por confiar en nosotros', tr: 'Bize güveniniz için teşekkür ederiz')}</p>');
    b.writeln(
      '<p>${_escapeHtml(_altLabel(model.language, ar: 'شكرا لثقتكم بنا', hi: 'हम पर विश्वास करने के लिए धन्यवाद', ur: 'ہم پر اعتماد کرنے کا شکریہ', tr: 'Bize güveniniz için teşekkür ederiz', en: 'Thank you for trusting us', es: 'Gracias por confiar en nosotros'))}</p>',
    );

    b.writeln('<p>${_mainLbl(model.language, ar: 'برنامج هيرموسا المحاسبي المتكامل', en: 'Integrated Accounting Program Hermosa', hi: 'एकीकृत लेखांकन कार्यक्रम हर्मोसा', ur: 'ہرموسا انٹیگریٹڈ اکاؤنٹنگ پروگرام', es: 'Programa de Contabilidad Integrada Hermosa', tr: 'Entegre Muhasebe Programı Hermosa')}</p>');
    b.writeln(
      '<p>${_escapeHtml(_altLabel(model.language, ar: 'برنامج هيرموسا المحاسبي المتكامل', hi: 'एकीकृत लेखांकन कार्यक्रम हर्मोसा', ur: 'ہرموسا انٹیگریٹڈ اکاؤنٹنگ پروگرام', tr: 'Entegre Muhasebe Programı Hermosa', en: 'Integrated Accounting Program Hermosa', es: 'Programa de Contabilidad Integrada Hermosa'))}</p>',
    );

    b.writeln('<p>${_escapeHtml(model.websiteUrl)}</p>');
    b.writeln('</div>');

    b.writeln('</footer>');

    return b.toString();
  }

  String _renderPolicyHtml(String policy) {
    final trimmed = policy.trim();
    if (trimmed.isEmpty) return '';

    final likelyHtml = trimmed.contains('<') && trimmed.contains('>');
    if (likelyHtml) return trimmed;

    return _escapeHtml(trimmed).replaceAll('\n', '<br/>');
  }
}
