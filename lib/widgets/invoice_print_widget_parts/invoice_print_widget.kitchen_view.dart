// ignore_for_file: unused_element, unused_element_parameter, dead_code
part of '../invoice_print_widget.dart';

extension InvoicePrintWidgetKitchenView on InvoicePrintWidget {
  Widget _buildKitchenView() {
    if (kitchenData == null) return const SizedBox.shrink();

    final orderNumber = kitchenData!['orderNumber'] ?? '';
    final orderTypeRaw = kitchenData!['orderType'] ?? '';
    final items = (kitchenData!['items'] as List? ?? []);
    final note = kitchenData!['note'];
    final createdAt = kitchenData!['createdAt'] as DateTime?;

    // Kitchen-specific invoice language (falls back to widget defaults).
    // The item name resolver uses these to pick from meal_name_translations.
    final String kitchenPrimaryLang =
        (kitchenData!['primaryLang']?.toString().trim().isNotEmpty == true)
            ? kitchenData!['primaryLang'].toString().trim().toLowerCase()
            : primaryLang;
    final String kitchenSecondaryLang =
        (kitchenData!['secondaryLang']?.toString().trim().isNotEmpty == true)
            ? kitchenData!['secondaryLang'].toString().trim().toLowerCase()
            : secondaryLang;
    final bool kitchenAllowSecondary =
        kitchenData!['allowSecondary'] is bool
            ? kitchenData!['allowSecondary'] as bool
            : allowSecondary;

    final clientNameLocal = kitchenData!['clientName'] ?? clientName;
    final clientPhoneLocal = kitchenData!['clientPhone'] ?? clientPhone;
    final tableNumberLocal = kitchenData!['tableNumber'] ?? tableNumber;
    final carNumberLocal = kitchenData!['carNumber'] ?? carNumber;
    final printerNameLocal = kitchenData!['printerName'];

    final displayOrderTypeAr = _getOrderTypeArabic(orderTypeRaw);

    // Every label below goes through `_ml` (primary invoice language) and
    // `_sl` (secondary — empty string when `allowSecondary` is off or the
    // two languages match), so the ticket respects the cashier's setting
    // whether that's ar/en, es/en, tr/es, or any other combo.
    final titlePrimary = _ml(ar: 'طلب مطبخ', en: 'Kitchen Ticket', hi: 'रसोई टिकट', ur: 'کچن ٹکٹ', es: 'Ticket de Cocina', tr: 'Mutfak Fişi');
    final titleSecondary = _sl(ar: 'طلب مطبخ', en: 'Kitchen Ticket', hi: 'रसोई टिकट', ur: 'کچن ٹکٹ', es: 'Ticket de Cocina', tr: 'Mutfak Fişi');
    final deptPrimary = _ml(ar: 'القسم', en: 'Dept', hi: 'विभाग', ur: 'شعبہ', es: 'Sección', tr: 'Bölüm');
    final deptSecondary = _sl(ar: 'القسم', en: 'Dept', hi: 'विभाग', ur: 'شعبہ', es: 'Sección', tr: 'Bölüm');
    final orderNumberPrimary = _ml(ar: 'رقم الطلب', en: 'Order #', hi: 'ऑर्डर #', ur: 'آرڈر #', es: 'N° Pedido', tr: 'Sipariş #');
    final orderNumberSecondary = _sl(ar: 'رقم الطلب', en: 'Order #', hi: 'ऑर्डर #', ur: 'آرڈر #', es: 'N° Pedido', tr: 'Sipariş #');
    final tableLabelPrimary = _ml(ar: 'طاولة', en: 'Table', hi: 'मेज़', ur: 'میز', es: 'Mesa', tr: 'Masa');
    final tableLabelSecondary = _sl(ar: 'طاولة', en: 'Table', hi: 'मेज़', ur: 'میز', es: 'Mesa', tr: 'Masa');
    final itemHeaderPrimary = _ml(ar: 'الصنف', en: 'Item', hi: 'आइटम', ur: 'آئٹم', es: 'Artículo', tr: 'Ürün');
    final itemHeaderSecondary = _sl(ar: 'الصنف', en: 'Item', hi: 'आइटम', ur: 'آئٹم', es: 'Artículo', tr: 'Ürün');
    final qtyHeaderPrimary = _ml(ar: 'الكمية', en: 'Qty', hi: 'मात्रा', ur: 'مقدار', es: 'Cant.', tr: 'Adet');
    final qtyHeaderSecondary = _sl(ar: 'الكمية', en: 'Qty', hi: 'मात्रा', ur: 'مقدار', es: 'Cant.', tr: 'Adet');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Column(
          children: [
            Text(
              titlePrimary,
              style: GoogleFonts.tajawal(fontSize: 46, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            if (titleSecondary.isNotEmpty && titleSecondary != titlePrimary)
              Text(
                titleSecondary,
                style: GoogleFonts.tajawal(fontSize: 34, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            if (printerNameLocal != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  (deptSecondary.isNotEmpty && deptSecondary != deptPrimary)
                      ? '$deptPrimary / $deptSecondary: $printerNameLocal'
                      : '$deptPrimary: $printerNameLocal',
                  style: GoogleFonts.tajawal(fontSize: 30, color: Colors.black, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        const DashedDivider(),

        // Large Order Number and Table Number Row
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text(
                      orderNumberPrimary,
                      style: GoogleFonts.tajawal(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      orderNumber.toString().replaceAll('#', ''),
                      style: GoogleFonts.tajawal(fontSize: 96, fontWeight: FontWeight.w900, height: 1.0),
                    ),
                    if (orderNumberSecondary.isNotEmpty && orderNumberSecondary != orderNumberPrimary)
                      Text(
                        orderNumberSecondary,
                        style: GoogleFonts.tajawal(fontSize: 26, color: Colors.black87, fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
              ),
              if (tableNumberLocal != null)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      children: [
                        Text(
                          tableLabelPrimary,
                          style: GoogleFonts.tajawal(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          tableNumberLocal.toString(),
                          style: GoogleFonts.tajawal(fontSize: 84, fontWeight: FontWeight.w900, color: Colors.white, height: 1.0),
                        ),
                        if (tableLabelSecondary.isNotEmpty && tableLabelSecondary != tableLabelPrimary)
                          Text(
                            tableLabelSecondary,
                            style: GoogleFonts.tajawal(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const DashedDivider(),
        const SizedBox(height: 12),

        // Metadata Section — each row resolved via _ml/_sl so every configured
        // invoice-language pair renders correctly.
        _buildMetaRow(
          _ml(ar: 'نوع الطلب', en: 'Order Type', hi: 'ऑर्डर प्रकार', ur: 'آرڈر کی قسم', es: 'Tipo de Pedido', tr: 'Sipariş Türü'),
          _sl(ar: 'نوع الطلب', en: 'Order Type', hi: 'ऑर्डर प्रकार', ur: 'آرڈر کی قسم', es: 'Tipo de Pedido', tr: 'Sipariş Türü'),
          displayOrderTypeAr,
          isLarge: true,
        ),
        if (tableNumberLocal != null)
          _buildMetaRow(
            _ml(ar: 'رقم الطاولة', en: 'Table Number', hi: 'मेज़ संख्या', ur: 'میز نمبر', es: 'Número de Mesa', tr: 'Masa Numarası'),
            _sl(ar: 'رقم الطاولة', en: 'Table Number', hi: 'मेज़ संख्या', ur: 'میز نمبر', es: 'Número de Mesa', tr: 'Masa Numarası'),
            tableNumberLocal.toString(),
            isLarge: true,
          ),
        if (clientNameLocal != null)
          _buildMetaRow(
            _ml(ar: 'العميل', en: 'Customer', hi: 'ग्राहक', ur: 'کسٹمر', es: 'Cliente', tr: 'Müşteri'),
            _sl(ar: 'العميل', en: 'Customer', hi: 'ग्राहक', ur: 'کسٹمر', es: 'Cliente', tr: 'Müşteri'),
            clientNameLocal.toString(),
          ),
        if (clientPhoneLocal != null)
          _buildMetaRow(
            _ml(ar: 'الجوال', en: 'Phone', hi: 'फ़ोन', ur: 'فون', es: 'Teléfono', tr: 'Telefon'),
            _sl(ar: 'الجوال', en: 'Phone', hi: 'फ़ोन', ur: 'فون', es: 'Teléfono', tr: 'Telefon'),
            clientPhoneLocal.toString().trim(),
          ),
        if (createdAt != null)
          _buildMetaRow(
            _ml(ar: 'التاريخ', en: 'Date & Time', hi: 'दिनांक और समय', ur: 'تاریخ اور وقت', es: 'Fecha y Hora', tr: 'Tarih ve Saat'),
            _sl(ar: 'التاريخ', en: 'Date & Time', hi: 'दिनांक और समय', ur: 'تاریخ اور وقت', es: 'Fecha y Hora', tr: 'Tarih ve Saat'),
            '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
          ),
        if (carNumberLocal?.isNotEmpty == true || data?.carNumber.isNotEmpty == true)
          _buildCarInfo(carNumberLocal),

        const SizedBox(height: 16),
        const Divider(thickness: 3, color: Colors.black),

        // Items Table Header — primary + optional secondary language.
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(itemHeaderPrimary, style: GoogleFonts.tajawal(fontSize: 26, fontWeight: FontWeight.bold)),
                  if (itemHeaderSecondary.isNotEmpty && itemHeaderSecondary != itemHeaderPrimary)
                    Text(itemHeaderSecondary, style: GoogleFonts.tajawal(fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            SizedBox(
              width: 90,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(qtyHeaderPrimary, style: GoogleFonts.tajawal(fontSize: 26, fontWeight: FontWeight.bold)),
                  if (qtyHeaderSecondary.isNotEmpty && qtyHeaderSecondary != qtyHeaderPrimary)
                    Text(qtyHeaderSecondary, style: GoogleFonts.tajawal(fontSize: 22, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        const Divider(thickness: 1, color: Colors.black54),
        
        // Items List
        ...items.map((item) {
          // Primary name = invoice primary language; secondary = secondary
          // language (if allowed and different). Reads `meal_name_translations`
          // / `localizedNames` first and falls back to nameAr/nameEn/name.
          String nameAr = _resolveKitchenItemName(item as Map, lang: kitchenPrimaryLang);
          String nameEn = kitchenAllowSecondary && kitchenSecondaryLang != kitchenPrimaryLang
              ? _resolveKitchenItemName(item, lang: kitchenSecondaryLang)
              : '';

          if (nameEn.isEmpty && nameAr.contains(' - ')) {
            final parts = nameAr.split(' - ');
            nameAr = parts.first.trim();
            nameEn = parts.last.trim();
          }
          final rawQty = item['quantity'] ?? 1;
          final double parsedQty = double.tryParse(rawQty.toString()) ?? 1.0;
          final qtyStr = parsedQty == parsedQty.toInt() ? parsedQty.toInt().toString() : parsedQty.toString();
          final extras = (item['extras'] as List? ?? []);
          final addonsTranslations = item['addons_translations'] as List? ?? const [];
          final itemNote = item['notes'];

          String? pickTranslation(dynamic source, String lang) {
            if (source is! Map) return null;
            final opt = source['option'];
            if (opt is Map) {
              final v = opt[lang]?.toString().trim();
              if (v != null && v.isNotEmpty) return v;
            }
            final attr = source['attribute'];
            if (attr is Map) {
              final v = attr[lang]?.toString().trim();
              if (v != null && v.isNotEmpty) return v;
            }
            return null;
          }

          // Resolve the primary/secondary label for an addon at [idx]. Prefers
          // per-extra `translations` (embedded when normalizing API add-ons),
          // then falls back to the parent item's `addons_translations` list
          // (index-matched), then the raw `name` string.
          ({String primary, String secondary}) addonNamesFor(int idx, dynamic ex) {
            String? primaryName;
            if (ex is Map) {
              primaryName = pickTranslation(ex['translations'], kitchenPrimaryLang);
            }
            if (primaryName == null && idx < addonsTranslations.length) {
              primaryName = pickTranslation(addonsTranslations[idx], kitchenPrimaryLang);
            }
            primaryName ??= (ex is Map ? ex['name']?.toString() : ex?.toString()) ?? '';

            String secondaryName = '';
            if (kitchenAllowSecondary && kitchenSecondaryLang != kitchenPrimaryLang) {
              String? s;
              if (ex is Map) {
                s = pickTranslation(ex['translations'], kitchenSecondaryLang);
              }
              if (s == null && idx < addonsTranslations.length) {
                s = pickTranslation(addonsTranslations[idx], kitchenSecondaryLang);
              }
              if (s != null && s.isNotEmpty && s != primaryName) {
                secondaryName = s;
              }
            }
            return (primary: primaryName, secondary: secondaryName);
          }

          // Group identical addons so "3x سيخ" prints once with a count prefix
          // instead of three back-to-back identical lines. Dedupe key is the
          // addon's id when available, otherwise its primary-language name —
          // the same bucket the cart/kitchen payload uses when totalling.
          final groupedExtras = <String, ({String primary, String secondary, int count})>{};
          final groupedOrder = <String>[];
          for (var i = 0; i < extras.length; i++) {
            final ex = extras[i];
            final names = addonNamesFor(i, ex);
            String key;
            if (ex is Map) {
              final id = ex['id']?.toString().trim() ?? '';
              key = id.isNotEmpty ? 'id:$id' : 'name:${names.primary}';
            } else {
              key = 'name:${names.primary}';
            }
            final existing = groupedExtras[key];
            if (existing == null) {
              groupedExtras[key] = (
                primary: names.primary,
                secondary: names.secondary,
                count: 1,
              );
              groupedOrder.add(key);
            } else {
              groupedExtras[key] = (
                primary: existing.primary,
                secondary: existing.secondary,
                count: existing.count + 1,
              );
            }
          }

          String addonLabel(({String primary, String secondary, int count}) g) {
            final prefix = g.count > 1 ? '+ ${g.count}x ' : '+ ';
            if (g.secondary.isNotEmpty && g.secondary != g.primary) {
              return '$prefix${g.primary} / ${g.secondary}';
            }
            return '$prefix${g.primary}';
          }

          // Change-ticket support: Add / Cancelled / Partial Cancel / Qty Change
          final tag = item['tag']?.toString();
          // `tagPrimary` is the primary-language label already resolved by the
          // cashier-side builder. Older payloads used `tagAr` (Arabic-only
          // field name) — still honored for backwards compatibility.
          final tagPrimary =
              (item['tagPrimary'] ?? item['tagAr'])?.toString();
          final tagSecondary = item['tagSecondary']?.toString();
          final tagColor = item['tagColor']?.toString();
          final isCancelled = item['cancelled'] == true;
          final oldQuantity = item['oldQuantity'];
          final cancelledQuantity = item['cancelledQuantity'];

          Color resolveTagColor() {
            if (tagColor == 'green') return const Color(0xFF16A34A);
            if (tagColor == 'black') return Colors.black;
            if (tagColor == 'orange') return const Color(0xFFF59E0B);
            return const Color(0xFFF59E0B);
          }

          if (tag != null) {
            // Change ticket layout (edit order): badge + item + per-tag details.
            // Prefer the cashier-resolved `tagSecondary`; fall back to the raw
            // English `tag` so the badge still shows two lines when only the
            // primary was localized.
            final tagPrimaryText = tagPrimary ?? tag;
            final tagSecondaryText = (tagSecondary != null &&
                    tagSecondary.isNotEmpty &&
                    tagSecondary != tagPrimaryText)
                ? tagSecondary
                : ((tagPrimary != null && tag != tagPrimary) ? tag : '');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: resolveTagColor(),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Text(
                        tagPrimaryText,
                        style: GoogleFonts.tajawal(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      if (tagSecondaryText.isNotEmpty)
                        Text(
                          tagSecondaryText,
                          style: GoogleFonts.tajawal(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.85)),
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    nameAr,
                    style: GoogleFonts.tajawal(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      decoration: isCancelled ? TextDecoration.lineThrough : null,
                      color: isCancelled ? Colors.grey[600] : Colors.black,
                    ),
                  ),
                ),
                if (nameEn.isNotEmpty && nameEn != nameAr)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      nameEn,
                      style: GoogleFonts.tajawal(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        decoration: isCancelled ? TextDecoration.lineThrough : null,
                        color: isCancelled ? Colors.grey[600] : Colors.black,
                      ),
                    ),
                  ),

                // Extras — also shown on change tickets so the kitchen
                // knows the full spec of an added / modified item.
                if (groupedOrder.isNotEmpty)
                  ...groupedOrder.map((k) => Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                        child: Text(
                          addonLabel(groupedExtras[k]!),
                          style: GoogleFonts.tajawal(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            decoration:
                                isCancelled ? TextDecoration.lineThrough : null,
                            color: isCancelled ? Colors.grey[600] : Colors.black,
                          ),
                        ),
                      )),

                // Fully cancelled item → ✗
                if (isCancelled && cancelledQuantity == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '✗',
                      style: GoogleFonts.tajawal(fontSize: 46, fontWeight: FontWeight.w900, color: Colors.red),
                    ),
                  ),

                // Partial cancel: show original / cancelled / remaining
                if (cancelledQuantity != null) ...[
                  const SizedBox(height: 4),
                  _buildChangeDetailRow(
                    _ml(ar: 'الكمية الأصلية', en: 'Original Qty', hi: 'मूल मात्रा', ur: 'اصل مقدار', es: 'Cantidad Original', tr: 'Orijinal Miktar'),
                    _sl(ar: 'الكمية الأصلية', en: 'Original Qty', hi: 'मूल मात्रा', ur: 'اصل مقدار', es: 'Cantidad Original', tr: 'Orijinal Miktar'),
                    '$oldQuantity',
                  ),
                  _buildChangeDetailRow(
                    _ml(ar: 'الكمية الملغاة', en: 'Cancelled', hi: 'रद्द की गई', ur: 'منسوخ', es: 'Cancelada', tr: 'İptal Edildi'),
                    _sl(ar: 'الكمية الملغاة', en: 'Cancelled', hi: 'रद्द की गई', ur: 'منسوخ', es: 'Cancelada', tr: 'İptal Edildi'),
                    '$cancelledQuantity  ✗',
                  ),
                  const DashedDivider(),
                  _buildChangeDetailRow(
                    _ml(ar: 'الكمية المطلوبة الآن', en: 'Remaining', hi: 'शेष', ur: 'باقی', es: 'Restante', tr: 'Kalan'),
                    _sl(ar: 'الكمية المطلوبة الآن', en: 'Remaining', hi: 'शेष', ur: 'باقی', es: 'Restante', tr: 'Kalan'),
                    '$qtyStr  ✓',
                  ),
                ],

                // Quantity change (no partial cancel): old → new
                if (tag == 'Qty Change' && cancelledQuantity == null) ...[
                  const SizedBox(height: 4),
                  _buildChangeDetailRow(
                    _ml(ar: 'الكمية السابقة', en: 'Previous Qty', hi: 'पिछली मात्रा', ur: 'پچھلی مقدار', es: 'Cantidad Anterior', tr: 'Önceki Miktar'),
                    _sl(ar: 'الكمية السابقة', en: 'Previous Qty', hi: 'पिछली मात्रा', ur: 'پچھلی مقدار', es: 'Cantidad Anterior', tr: 'Önceki Miktar'),
                    '$oldQuantity',
                  ),
                  _buildChangeDetailRow(
                    _ml(ar: 'الكمية الجديدة', en: 'New Qty', hi: 'नई मात्रा', ur: 'نئی مقدار', es: 'Cantidad Nueva', tr: 'Yeni Miktar'),
                    _sl(ar: 'الكمية الجديدة', en: 'New Qty', hi: 'नई मात्रा', ur: 'نئی مقدار', es: 'Cantidad Nueva', tr: 'Yeni Miktar'),
                    qtyStr,
                  ),
                ],

                // Add / new item: show ✓ qty
                if ((tag == 'Add' || tag == 'New') && cancelledQuantity == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '✓  $qtyStr',
                      style: GoogleFonts.tajawal(fontSize: 42, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A)),
                    ),
                  ),

                const SizedBox(height: 8),
                const DashedDivider(),
              ],
            );
          }

          // Regular (non-tagged) kitchen item layout
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Item Name
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nameAr,
                            style: GoogleFonts.tajawal(fontSize: 32, fontWeight: FontWeight.bold),
                          ),
                          if (nameEn.isNotEmpty && nameEn != nameAr)
                            Text(
                              nameEn,
                              style: GoogleFonts.tajawal(fontSize: 24, color: Colors.black, fontWeight: FontWeight.bold),
                            ),

                          // Extras
                          if (groupedOrder.isNotEmpty)
                            ...groupedOrder.map((k) => Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                addonLabel(groupedExtras[k]!),
                                style: GoogleFonts.tajawal(fontSize: 30, fontWeight: FontWeight.bold),
                              ),
                            )),

                          // Item specific notes — "Note" label follows the
                          // invoice language (ar/en/es/tr/hi/ur).
                          if (itemNote != null && itemNote.toString().isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${_ml(ar: 'ملاحظة', en: 'Note', hi: 'नोट', ur: 'نوٹ', es: 'Nota', tr: 'Not')}: $itemNote',
                                style: GoogleFonts.tajawal(fontSize: 28, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Quantity
                    Container(
                      width: 90,
                      alignment: AlignmentDirectional.topEnd,
                      child: Text(
                        qtyStr,
                        style: GoogleFonts.tajawal(fontSize: 48, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
              const DashedDivider(),
            ],
          );
        }),

        // General Booking Note — header localized per invoice language.
        if (note != null && note.toString().isNotEmpty) ...[
          const SizedBox(height: 20),
          Builder(builder: (_) {
            final notePrimary = _ml(ar: 'ملاحظة عامة', en: 'General Note', hi: 'सामान्य नोट', ur: 'عمومی نوٹ', es: 'Nota General', tr: 'Genel Not');
            final noteSecondary = _sl(ar: 'ملاحظة عامة', en: 'General Note', hi: 'सामान्य नोट', ur: 'عمومی نوٹ', es: 'Nota General', tr: 'Genel Not');
            final header = (noteSecondary.isNotEmpty && noteSecondary != notePrimary)
                ? '$notePrimary / $noteSecondary:'
                : '$notePrimary:';
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.05),
                border: Border.all(color: Colors.black, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    header,
                    style: GoogleFonts.tajawal(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    note.toString(),
                    style: GoogleFonts.tajawal(fontSize: 34, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          }),
        ],

        const SizedBox(height: 16),
      ],
    );
  }

  /// Pick an item's name for the given language code. Reads
  /// `meal_name_translations` (preferred) or `localizedNames`, then falls
  /// back to `nameAr` / `nameEn` / `name`.
  String _resolveKitchenItemName(Map item, {required String lang}) {
    final translations = item['meal_name_translations'] ??
        item['localizedNames'] ??
        item['localized_names'];
    if (translations is Map) {
      final primary = translations[lang];
      if (primary is String && primary.trim().isNotEmpty) return primary.trim();
      final en = translations['en'];
      if (lang != 'en' && en is String && en.trim().isNotEmpty) return en.trim();
      final ar = translations['ar'];
      if (lang != 'ar' && ar is String && ar.trim().isNotEmpty) return ar.trim();
    }
    if (lang == 'en') {
      final e = item['nameEn']?.toString();
      if (e != null && e.trim().isNotEmpty) return e.trim();
    }
    final a = item['nameAr']?.toString();
    if (a != null && a.trim().isNotEmpty) return a.trim();
    final e = item['nameEn']?.toString();
    if (e != null && e.trim().isNotEmpty) return e.trim();
    return item['name']?.toString() ?? '';
  }
}
