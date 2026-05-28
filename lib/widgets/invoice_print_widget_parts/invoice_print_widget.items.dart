// ignore_for_file: unused_element, unused_element_parameter, dead_code
part of '../invoice_print_widget.dart';

extension InvoicePrintWidgetItems on InvoicePrintWidget {
  Widget _buildItems() {
    if (data == null) return const SizedBox.shrink();
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_ml(ar: 'الصنف', en: 'Item', hi: 'आइटम', ur: 'آئٹم', es: 'Artículo', tr: 'Ürün'),
                            style: GoogleFonts.tajawal(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                        if (_sl(ar: 'الصنف', en: 'Item', hi: 'आइटम', ur: 'آئٹم', es: 'Artículo', tr: 'Ürün').isNotEmpty)
                          Text(_sl(ar: 'الصنف', en: 'Item', hi: 'आइटम', ur: 'آئٹم', es: 'Artículo', tr: 'Ürün'),
                              style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, color: Colors.black),
                SizedBox(
                  width: 55,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(_ml(ar: 'كمية', en: 'Qty', hi: 'मात्रा', ur: 'مقدار', es: 'Cant.', tr: 'Adet'),
                            style: GoogleFonts.tajawal(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                        if (_sl(ar: 'كمية', en: 'Qty', hi: 'मात्रा', ur: 'مقدار', es: 'Cant.', tr: 'Adet').isNotEmpty)
                          Text(_sl(ar: 'كمية', en: 'Qty', hi: 'मात्रा', ur: 'مقدار', es: 'Cant.', tr: 'Adet'),
                              style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, color: Colors.black),
                SizedBox(
                  width: 68,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(_ml(ar: 'سعر', en: 'Price', hi: 'कीमत', ur: 'قیمت', es: 'Precio', tr: 'Fiyat'),
                            style: GoogleFonts.tajawal(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                        if (_sl(ar: 'سعر', en: 'Price', hi: 'कीमत', ur: 'قیمت', es: 'Precio', tr: 'Fiyat').isNotEmpty)
                          Text(_sl(ar: 'سعر', en: 'Price', hi: 'कीमत', ur: 'قیمت', es: 'Precio', tr: 'Fiyat'),
                              style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, color: Colors.black),
                SizedBox(
                  width: 75,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(_ml(ar: 'مجموع', en: 'Total', hi: 'कुल', ur: 'کل', es: 'Total', tr: 'Toplam'),
                            style: GoogleFonts.tajawal(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                        if (_sl(ar: 'مجموع', en: 'Total', hi: 'कुल', ur: 'کل', es: 'Total', tr: 'Toplam').isNotEmpty)
                          Text(_sl(ar: 'مجموع', en: 'Total', hi: 'कुल', ur: 'کل', es: 'Total', tr: 'Toplam'),
                              style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ...data!.items.map((item) {
          // Per-item discount surfaces inline beside the meal name —
          // "(مجاناً)" for free lines and "(خصم 10%)" / "(خصم 5.00 ر.س)"
          // for everything else with a discount. The order-level
          // discount/coupon banner in `_buildTotals` handles whole-bill
          // discounts; per-item chips show in BOTH cases so the
          // customer can see exactly which meal each per-item discount
          // applied to (e.g. a meal manually discounted by the cashier
          // alongside an order-wide coupon).
          final isOrderFullyFree =
              data!.totalInclVat <= 0.001 && _hasAnyDiscountSource;
          // A line is "free" — regardless of how the cashier achieved
          // it — when ANY of the following is true:
          //   * explicit "Free" flag from cashier / backend
          //     (discountName == 'مجاناً')
          //   * 100% discount from the slider or a full coupon
          //     (discountPercentage ≈ 100)
          //   * math fully-discounted line (originalPrice > 0 &&
          //     total ≈ 0 && a discount is present) — catches the
          //     "cashier discounted the full amount in currency"
          //     edge case where neither percentage nor flag is set.
          // The user explicitly asked that all three paths read as
          // "(مجاناً)" rather than splitting "(خصم 100%)" out.
          final isFreeLine = (item.discountName?.trim() == 'مجاناً') ||
              (item.discountPercentage != null &&
                  item.discountPercentage! >= 99.99) ||
              (item.originalPrice != null &&
                  item.originalPrice! > 0 &&
                  item.total <= 0.001 &&
                  item.hasDiscount);
          // Displayed total: 0 for any free line OR when the whole
          // order is free (banner-driven), otherwise the line total
          // straight from the data.
          final displayedItemTotal =
              (isOrderFullyFree || isFreeLine) ? 0.0 : item.total;
          final itemPrice = item.quantity > 0
              ? (displayedItemTotal / item.quantity)
              : displayedItemTotal;
          final hasAddons = item.addons != null && item.addons!.isNotEmpty;
          // Compose the inline discount chip text. Hidden when the
          // whole order is free (the FREE ORDER banner already speaks
          // for every line) or when this line has no discount at all.
          String? discountChip;
          if (!isOrderFullyFree) {
            if (isFreeLine) {
              discountChip =
                  '(${_ml(ar: 'مجاناً', en: 'FREE', hi: 'मुफ्त', ur: 'مفت', es: 'GRATIS', tr: 'ÜCRETSİZ')})';
            } else if (item.hasDiscount) {
              final pct = item.discountPercentage;
              final amount = item.discountAmount ?? 0;
              if (pct != null && pct > 0) {
                discountChip =
                    '(${_ml(ar: 'خصم', en: 'Discount', hi: 'छूट', ur: 'ڈسکاؤنٹ', es: 'Descuento', tr: 'İndirim')} ${pct.toStringAsFixed(0)}%)';
              } else if (amount > 0) {
                final currency = _translateCurrency(ApiConstants.currency);
                discountChip =
                    '(${_ml(ar: 'خصم', en: 'Discount', hi: 'छूट', ur: 'ڈسکاؤنٹ', es: 'Descuento', tr: 'İndirim')} ${amount.toStringAsFixed(ApiConstants.digitsNumber)} $currency)';
              }
            }
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IntrinsicHeight(
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Colors.black),
                      right: BorderSide(color: Colors.black),
                      bottom: BorderSide(color: Colors.black),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: 3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.nameAr,
                                style: GoogleFonts.tajawal(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black),
                              ),
                              if (item.nameEn.isNotEmpty && item.nameEn != item.nameAr)
                                Text(
                                  item.nameEn,
                                  style: GoogleFonts.tajawal(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black),
                                ),
                              // Inline per-item discount chip (e.g.
                              // "(مجاناً)" / "(خصم 10%)" / "(خصم 5.00 ر.س)")
                              // — sits immediately under the meal name so
                              // the customer reads it as a qualifier on
                              // that specific line. Cheaper visual weight
                              // than a separate framed row underneath.
                              if (discountChip != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    discountChip,
                                    style: GoogleFonts.tajawal(
                                        fontSize: 16,
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontStyle: FontStyle.italic),
                                  ),
                                ),
                              // Addons inside the item cell, grouped by name.
                              // Uses primary invoice language for the main
                              // line and the secondary one (when allowed)
                              // for the bilingual line below, mirroring how
                              // the meal itself is rendered above.
                              if (hasAddons)
                                ..._groupedAddons(item.addons!).map((entry) {
                                  final addon = entry.key;
                                  final qty = entry.value;
                                  final primaryName = addon.nameFor(primaryLang);
                                  final secondaryName =
                                      (allowSecondary && secondaryLang != primaryLang)
                                          ? addon.nameFor(secondaryLang)
                                          : '';
                                  // "2x name" reads better on kitchen
                                  // tickets and matches what the customer
                                  // display and receipt printers use.
                                  String format(String n) =>
                                      qty > 1 ? '+ ${qty}x $n' : '+ $n';
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                format(primaryName),
                                                style: GoogleFonts.tajawal(
                                                    fontSize: 17,
                                                    color: Colors.black54,
                                                    fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            Text(
                                              (addon.price * qty)
                                                  .toStringAsFixed(ApiConstants.digitsNumber),
                                              maxLines: 1,
                                              softWrap: false,
                                              overflow: TextOverflow.visible,
                                              style: GoogleFonts.tajawal(
                                                  fontSize: 17,
                                                  color: Colors.black54,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                        if (secondaryName.isNotEmpty &&
                                            secondaryName != primaryName)
                                          Text(
                                            format(secondaryName),
                                            style: GoogleFonts.tajawal(
                                                fontSize: 15,
                                                color: Colors.black54,
                                                fontWeight: FontWeight.bold),
                                          ),
                                      ],
                                    ),
                                  );
                                }),
                            ],
                          ),
                        ),
                      ),
                      Container(width: 1, color: Colors.black),
                      SizedBox(
                        width: 55,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          alignment: Alignment.center,
                          child: Text(
                            item.quantity % 1 == 0 ? item.quantity.toStringAsFixed(0) : item.quantity.toString(),
                            style: GoogleFonts.tajawal(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                color: Colors.black),
                          ),
                        ),
                      ),
                      Container(width: 1, color: Colors.black),
                      SizedBox(
                        width: 68,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 2, vertical: 2),
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: Text(
                              itemPrice.toStringAsFixed(ApiConstants.digitsNumber),
                              maxLines: 1,
                              softWrap: false,
                              style: GoogleFonts.tajawal(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black),
                            ),
                          ),
                        ),
                      ),
                      Container(width: 1, color: Colors.black),
                      SizedBox(
                        width: 75,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 2, vertical: 2),
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.center,
                            child: Text(
                              displayedItemTotal.toStringAsFixed(
                                  ApiConstants.digitsNumber),
                              maxLines: 1,
                              softWrap: false,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}
