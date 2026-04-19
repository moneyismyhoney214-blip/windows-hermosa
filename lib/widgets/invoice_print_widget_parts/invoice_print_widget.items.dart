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
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                        if (_sl(ar: 'الصنف', en: 'Item', hi: 'आइटम', ur: 'آئٹم', es: 'Artículo', tr: 'Ürün').isNotEmpty)
                          Text(_sl(ar: 'الصنف', en: 'Item', hi: 'आइटम', ur: 'آئٹم', es: 'Artículo', tr: 'Ürün'),
                              style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
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
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                        if (_sl(ar: 'كمية', en: 'Qty', hi: 'मात्रा', ur: 'مقدار', es: 'Cant.', tr: 'Adet').isNotEmpty)
                          Text(_sl(ar: 'كمية', en: 'Qty', hi: 'मात्रा', ur: 'مقدار', es: 'Cant.', tr: 'Adet'),
                              style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
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
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                        if (_sl(ar: 'سعر', en: 'Price', hi: 'कीमत', ur: 'قیمت', es: 'Precio', tr: 'Fiyat').isNotEmpty)
                          Text(_sl(ar: 'سعر', en: 'Price', hi: 'कीमत', ur: 'قیمت', es: 'Precio', tr: 'Fiyat'),
                              style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
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
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                        if (_sl(ar: 'مجموع', en: 'Total', hi: 'कुल', ur: 'کل', es: 'Total', tr: 'Toplam').isNotEmpty)
                          Text(_sl(ar: 'مجموع', en: 'Total', hi: 'कुल', ur: 'کل', es: 'Total', tr: 'Toplam'),
                              style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ...data!.items.map((item) {
          final itemPrice =
              item.quantity > 0 ? (item.total / item.quantity) : item.total;
          final hasAddons = item.addons != null && item.addons!.isNotEmpty;
          final hasDiscount = item.hasDiscount;
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
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black),
                              ),
                              if (item.nameEn.isNotEmpty && item.nameEn != item.nameAr)
                                Text(
                                  item.nameEn,
                                  style: GoogleFonts.tajawal(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black),
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
                                                    fontSize: 15,
                                                    color: Colors.black54,
                                                    fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            Text(
                                              (addon.price * qty)
                                                  .toStringAsFixed(2),
                                              style: GoogleFonts.tajawal(
                                                  fontSize: 15,
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
                                                fontSize: 13,
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
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: Colors.black),
                          ),
                        ),
                      ),
                      Container(width: 1, color: Colors.black),
                      SizedBox(
                        width: 68,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          alignment: Alignment.center,
                          child: Text(
                            itemPrice.toStringAsFixed(2),
                            style: GoogleFonts.tajawal(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black),
                          ),
                        ),
                      ),
                      Container(width: 1, color: Colors.black),
                      SizedBox(
                        width: 75,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          alignment: Alignment.center,
                          child: Text(
                            item.total.toStringAsFixed(2),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (hasDiscount)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.black38)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${item.discountName ?? _ml(ar: 'خصم', en: 'Discount', hi: 'छूट', ur: 'ڈسکاؤنٹ', es: 'Descuento', tr: 'İndirim')}${item.discountPercentage != null ? ' (${item.discountPercentage!.toStringAsFixed(0)}%)' : ''}',
                        style: GoogleFonts.tajawal(
                            fontSize: 18, color: Colors.black, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '-${item.discountAmount!.toStringAsFixed(2)}',
                        style: GoogleFonts.tajawal(
                            fontSize: 18, color: Colors.black, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}
