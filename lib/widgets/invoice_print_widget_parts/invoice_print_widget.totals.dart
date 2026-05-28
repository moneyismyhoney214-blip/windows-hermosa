// ignore_for_file: unused_element, unused_element_parameter, dead_code
part of '../invoice_print_widget.dart';

extension InvoicePrintWidgetTotals on InvoicePrintWidget {
  Widget _buildTotals() {
    if (data == null) return const SizedBox.shrink();
    // The entire order is free when the grand total is zero AND there's an
    // order-level discount/coupon explaining why. We use both signals so a
    // zero-priced sample order (no items / all-zero menu) doesn't trigger
    // the FREE ORDER banner spuriously.
    // FREE ORDER fires when the grand total is zero AND any discount
    // brought it there — covers order-level coupons AND the
    // "everything-per-item-free" case (e.g. backend invoice IN-824
    // where the discount lives entirely in the items, with no
    // explicit order-level coupon).
    final isOrderFullyFree =
        data!.totalInclVat <= 0.001 && _hasAnyDiscountSource;
    // The DISCOUNT banner is reserved for an ORDER-level discount/coupon
    // (i.e. the cashier discounted the whole bill). Per-item discounts
    // do NOT trigger the banner — those are surfaced inline beside the
    // item itself in `_buildItemsSection`, which keeps the banner from
    // shouting when only a single meal happens to be free or discounted.
    final hasOrderLevelDiscount =
        data!.hasOrderDiscount && (data!.orderDiscountAmount ?? 0) > 0;
    final hasDiscountBanner = !isOrderFullyFree && hasOrderLevelDiscount;
    final discountAmountForBanner =
        hasDiscountBanner ? (data!.orderDiscountAmount ?? 0) : 0.0;
    final discountPctForBanner =
        hasDiscountBanner ? data!.orderDiscountPercentage : null;
    final discountNameForBanner =
        hasDiscountBanner ? data!.orderDiscountName : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 3, top: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black),
      ),
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          // Prominent "FREE ORDER" banner — sits above the rest of the
          // totals so a cashier scanning the receipt sees it before the
          // line-by-line breakdown. Uses a double-bordered box so it
          // reads as a stamp, not just another row.
          if (isOrderFullyFree) ...[
            // FREE ORDER banner — plain receipt-style frame (no fill).
            // Thermal printers struggle with large solid backgrounds, and
            // the user explicitly asked for the discount/free banners to
            // be "أبيض و أسود عادي" — same monochrome treatment as the
            // rest of the receipt.
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black, width: 2),
              ),
              child: Column(
                children: [
                  Text(
                    _ml(ar: 'طلب مجاني', en: 'FREE ORDER', hi: 'मुफ्त ऑर्डर', ur: 'مفت آرڈر', es: 'PEDIDO GRATIS', tr: 'ÜCRETSİZ SİPARİŞ'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.tajawal(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        letterSpacing: 1.2),
                  ),
                  if (_sl(ar: 'طلب مجاني', en: 'FREE ORDER', hi: 'मुफ्त ऑर्डर', ur: 'مفت آرڈر', es: 'PEDIDO GRATIS', tr: 'ÜCRETSİZ SİPARİŞ').isNotEmpty)
                    Text(
                      _sl(ar: 'طلب مجاني', en: 'FREE ORDER', hi: 'मुफ्त ऑर्डर', ur: 'مفت آرڈر', es: 'PEDIDO GRATIS', tr: 'ÜCRETSİZ SİPARİŞ'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tajawal(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          letterSpacing: 1.0),
                    ),
                  if ((data!.orderDiscountName?.trim().isNotEmpty ?? false) &&
                      data!.orderDiscountName!.trim() != 'طلب مجاني' &&
                      data!.orderDiscountName!.trim() != 'Free Order')
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        data!.orderDiscountName!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.tajawal(
                            fontSize: 13,
                            color: Colors.black87,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (hasDiscountBanner) ...[
            // DISCOUNT banner for ORDER-level discounts/coupons only.
            // Per-item discounts surface inline beside their items in
            // `_buildItemsSection`. Receipt-monochrome styling — black
            // border on white, no fill — to match the user's "أبيض و
            // أسود عادي" requirement and to print cleanly on thermal
            // paper.
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black, width: 2),
              ),
              child: Column(
                children: [
                  Text(
                    () {
                      final amount = discountAmountForBanner
                          .toStringAsFixed(ApiConstants.digitsNumber);
                      final currency =
                          _translateCurrency(ApiConstants.currency);
                      final pct = discountPctForBanner;
                      final hasPct = pct != null && pct > 0;
                      final label = _ml(
                          ar: 'خصم',
                          en: 'DISCOUNT',
                          hi: 'छूट',
                          ur: 'ڈسکاؤنٹ',
                          es: 'DESCUENTO',
                          tr: 'İNDİRİM');
                      if (hasPct) {
                        return '$label  $amount $currency  (${pct.toStringAsFixed(0)}%)';
                      }
                      return '$label  $amount $currency';
                    }(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.tajawal(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                        letterSpacing: 0.8),
                  ),
                  if (_sl(ar: 'خصم', en: 'DISCOUNT', hi: 'छूट', ur: 'ڈسکاؤنٹ', es: 'DESCUENTO', tr: 'İNDİRİM').isNotEmpty)
                    Text(
                      () {
                        final amount = discountAmountForBanner
                            .toStringAsFixed(ApiConstants.digitsNumber);
                        final currency =
                            _translateCurrency(ApiConstants.currency);
                        final pct = discountPctForBanner;
                        final hasPct = pct != null && pct > 0;
                        final label = _sl(
                            ar: 'خصم',
                            en: 'DISCOUNT',
                            hi: 'छूट',
                            ur: 'ڈسکاؤنٹ',
                            es: 'DESCUENTO',
                            tr: 'İNDİRİM');
                        if (hasPct) {
                          return '$label  $amount $currency  (${pct.toStringAsFixed(0)}%)';
                        }
                        return '$label  $amount $currency';
                      }(),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tajawal(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                          letterSpacing: 0.5),
                    ),
                  if ((discountNameForBanner?.trim().isNotEmpty ?? false) &&
                      discountNameForBanner!.trim() != 'خصم' &&
                      discountNameForBanner.trim() != 'Discount')
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        discountNameForBanner,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.tajawal(
                            fontSize: 13,
                            color: Colors.black87,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
          ],
          // Free orders collapse the rest of the totals to a single
          // grand-total row (which already prints "0") — the banner
          // above is the canonical "this is free" statement, so the
          // per-line subtotal/discount/tax breakdown becomes noise.
          if (!isOrderFullyFree) ...[
            // Pre-tax subtotal — only shown for tax-enabled branches. Tax-free
            // branches collapse the receipt to a single grand total line.
            if (ApiConstants.isTaxActive)
              _buildTotalRow(_ml(ar: 'الاجمالي قبل الضريبة', en: 'Total Before Tax', hi: 'कर से पहले कुल', ur: 'ٹیکس سے پہلے کل', es: 'Total Antes de Impuestos', tr: 'Vergi Öncesi Toplam'), _sl(ar: 'الاجمالي قبل الضريبة', en: 'Total Before Tax', hi: 'कर से पहले कुल', ur: 'ٹیکس سے پہلے کل', es: 'Total Antes de Impuestos', tr: 'Vergi Öncesi Toplam'), data!.totalExclVat)
            else
              _buildTotalRow(_ml(ar: 'الإجمالي', en: 'Subtotal', hi: 'उप-योग', ur: 'ذیلی کل', es: 'Subtotal', tr: 'Ara Toplam'), _sl(ar: 'الإجمالي', en: 'Subtotal', hi: 'उप-योग', ur: 'ذیلی کل', es: 'Subtotal', tr: 'Ara Toplam'), data!.totalExclVat),
            // When no order-level discount fires the banner, surface the
            // per-item discount aggregate on its own totals line so the
            // customer can still see the sum at a glance.
            if (!hasDiscountBanner && _impliedDiscount > 0.01)
              _buildDiscountRow(
                _ml(ar: 'اجمالي خصم الأصناف', en: 'Total Items Discount', hi: 'कुल आइटम छूट', ur: 'کل آئٹمز ڈسکاؤنٹ', es: 'Descuento Total de Artículos', tr: 'Toplam Ürün İndirimi'),
                _sl(ar: 'اجمالي خصم الأصناف', en: 'Total Items Discount', hi: 'कुल आइटम छूट', ur: 'کل آئٹمز ڈسکاؤنٹ', es: 'Descuento Total de Artículos', tr: 'Toplam Ürün İndirimi'),
                _impliedDiscount,
              ),
            if (ApiConstants.isTaxActive)
              _buildTotalRow(_ml(ar: 'قيمة الضريبة (${ApiConstants.taxPercentage}%)', en: 'Tax Amount (${ApiConstants.taxPercentage}%)', hi: 'कर राशि (${ApiConstants.taxPercentage}%)', ur: 'ٹیکس رقم (${ApiConstants.taxPercentage}%)', es: 'Monto del Impuesto (${ApiConstants.taxPercentage}%)', tr: 'Vergi Tutarı (${ApiConstants.taxPercentage}%)'), _sl(ar: 'قيمة الضريبة (${ApiConstants.taxPercentage}%)', en: 'Tax Amount (${ApiConstants.taxPercentage}%)', hi: 'कर राशि (${ApiConstants.taxPercentage}%)', ur: 'ٹیکس رقم (${ApiConstants.taxPercentage}%)', es: 'Monto del Impuesto (${ApiConstants.taxPercentage}%)', tr: 'Vergi Tutarı (${ApiConstants.taxPercentage}%)'), data!.vatAmount),
          ],
          const Divider(height: 8, thickness: 1, color: Colors.black),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Colors.black, width: 2)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Grand total label — "after tax" when VAT is on, plain
                      // "Total" when the branch has no tax line on the receipt.
                      Text(
                          ApiConstants.isTaxActive
                              ? _ml(ar: 'الاجمالي بعد الضريبة', en: 'Total After Tax', hi: 'कर के बाद कुल', ur: 'ٹیکس کے بعد کل', es: 'Total Después de Impuestos', tr: 'Vergi Sonrası Toplam')
                              : _ml(ar: 'الإجمالي', en: 'Total', hi: 'कुल', ur: 'کل', es: 'Total', tr: 'Toplam'),
                          style: GoogleFonts.tajawal(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Colors.black)),
                      if ((ApiConstants.isTaxActive
                              ? _sl(ar: 'الاجمالي بعد الضريبة', en: 'Total After Tax', hi: 'कर के बाद कुल', ur: 'ٹیکس کے بعد کل', es: 'Total Después de Impuestos', tr: 'Vergi Sonrası Toplam')
                              : _sl(ar: 'الإجمالي', en: 'Total', hi: 'कुल', ur: 'کل', es: 'Total', tr: 'Toplam'))
                          .isNotEmpty)
                        Text(
                            ApiConstants.isTaxActive
                                ? _sl(ar: 'الاجمالي بعد الضريبة', en: 'Total After Tax', hi: 'कर के बाद कुल', ur: 'ٹیکس کے بعد کل', es: 'Total Después de Impuestos', tr: 'Vergi Sonrası Toplam')
                                : _sl(ar: 'الإجمالي', en: 'Total', hi: 'कुल', ur: 'کل', es: 'Total', tr: 'Toplam'),
                            style: GoogleFonts.tajawal(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${(data?.totalInclVat ?? 0.0).toStringAsFixed(ApiConstants.digitsNumber)} ${_translateCurrency(ApiConstants.currency)}',
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.black),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildTotalRow(_ml(ar: 'المدفوع', en: 'Paid', hi: 'भुगतान किया', ur: 'ادا شدہ', es: 'Pagado', tr: 'Ödenen'), _sl(ar: 'المدفوع', en: 'Paid', hi: 'भुगतान किया', ur: 'ادا شدہ', es: 'Pagado', tr: 'Ödenen'), data!.totalInclVat),
          _buildTotalRow(_ml(ar: 'المتبقي', en: 'Remaining', hi: 'शेष', ur: 'بقایا', es: 'Restante', tr: 'Kalan'), _sl(ar: 'المتبقي', en: 'Remaining', hi: 'शेष', ur: 'بقایا', es: 'Restante', tr: 'Kalan'), 0.0),
          const DashedDivider(),
          if (data!.payments.isNotEmpty)
            ...data!.payments.map((p) => _buildTotalRow(_translatePayMethod(p.methodLabel), '', p.amount)),
          if (data!.paymentMethod.isNotEmpty && data!.payments.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _summaryLabelWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_ml(ar: 'طرق الدفع', en: 'Payment Methods', hi: 'भुगतान के तरीके', ur: 'ادائیگی کے طریقے', es: 'Métodos de Pago', tr: 'Ödeme Yöntemleri'),
                            style: GoogleFonts.tajawal(
                                fontSize: 21, color: Colors.black, fontWeight: FontWeight.bold)),
                        if (_sl(ar: 'طرق الدفع', en: 'Payment Methods', hi: 'भुगतान के तरीके', ur: 'ادائیگی کے طریقے', es: 'Métodos de Pago', tr: 'Ödeme Yöntemleri').isNotEmpty)
                          Text(_sl(ar: 'طرق الدفع', en: 'Payment Methods', hi: 'भुगतान के तरीके', ur: 'ادائیگی کے طریقے', es: 'Métodos de Pago', tr: 'Ödeme Yöntemleri'),
                              style: GoogleFonts.tajawal(
                                  fontSize: 16, color: Colors.black, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _translatePayMethod(data?.paymentMethod ?? ''),
                      style: GoogleFonts.tajawal(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black),
                      textAlign: TextAlign.left,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String labelAr, String labelEn, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(labelAr,
                    style: GoogleFonts.tajawal(
                        fontSize: 21, color: Colors.black, fontWeight: FontWeight.bold)),
                if (labelEn.isNotEmpty)
                  Text(labelEn,
                      style: GoogleFonts.tajawal(
                          fontSize: 16, color: Colors.black, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    amount.toStringAsFixed(ApiConstants.digitsNumber),
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: Colors.black),
                  ),
                  const SizedBox(width: 4),
                  Text(_translateCurrency(ApiConstants.currency),
                      style: GoogleFonts.tajawal(
                          fontSize: 18, color: Colors.black, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountRow(String labelAr, String labelEn, double amount,
      {double? percentage}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(labelAr,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.tajawal(
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                              color: Colors.black)),
                    ),
                    if (percentage != null)
                      Text(' (${percentage.toStringAsFixed(0)}%)',
                          style: GoogleFonts.tajawal(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: Colors.black)),
                  ],
                ),
                if (labelEn.isNotEmpty)
                  Text(labelEn,
                      style: GoogleFonts.tajawal(
                          fontSize: 16, color: Colors.black, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '-${amount.toStringAsFixed(ApiConstants.digitsNumber)}',
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: Colors.black),
                  ),
                  const SizedBox(width: 4),
                  Text(_translateCurrency(ApiConstants.currency),
                      style: GoogleFonts.tajawal(
                          fontSize: 18, color: Colors.black, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
