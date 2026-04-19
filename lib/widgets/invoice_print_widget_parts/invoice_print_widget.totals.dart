// ignore_for_file: unused_element, unused_element_parameter, dead_code
part of '../invoice_print_widget.dart';

extension InvoicePrintWidgetTotals on InvoicePrintWidget {
  Widget _buildTotals() {
    if (data == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 3, top: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black),
      ),
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          _buildTotalRow(_ml(ar: 'الاجمالي قبل الضريبة', en: 'Total Before Tax', hi: 'कर से पहले कुल', ur: 'ٹیکس سے پہلے کل', es: 'Total Antes de Impuestos', tr: 'Vergi Öncesi Toplam'), _sl(ar: 'الاجمالي قبل الضريبة', en: 'Total Before Tax', hi: 'कर से पहले कुल', ur: 'ٹیکس سے پہلے کل', es: 'Total Antes de Impuestos', tr: 'Vergi Öncesi Toplam'), data!.totalExclVat),

          // Order discount (promo code / manual / free)
          if (data!.hasOrderDiscount) ...[
            _buildDiscountRow(
              // Build label with discount details
              () {
                final name = data!.orderDiscountName;
                final pct = data!.orderDiscountPercentage;
                if (name != null && name.isNotEmpty && pct != null && pct > 0) {
                  return '$name (${pct.toStringAsFixed(0)}%)';
                } else if (pct != null && pct > 0) {
                  return '${_ml(ar: 'خصم', en: 'Discount', es: 'Descuento', tr: 'İndirim', hi: 'छूट', ur: 'ڈسکاؤنٹ')} (${pct.toStringAsFixed(0)}%)';
                } else if (name != null && name.isNotEmpty) {
                  return name;
                }
                return _ml(ar: 'خصم على الإجمالي', en: 'Order Discount', es: 'Descuento del Pedido', tr: 'Sipariş İndirimi', hi: 'ऑर्डर छूट', ur: 'آرڈر ڈسکاؤنٹ');
              }(),
              '',
              data!.orderDiscountAmount!,
            ),
          ]
          // Implied items discount (only if no explicit order discount)
          else if (_impliedDiscount > 0.01)
            _buildDiscountRow(
              _ml(ar: 'اجمالي خصم الأصناف', en: 'Total Items Discount', hi: 'कुल आइटम छूट', ur: 'کل آئٹمز ڈسکاؤنٹ', es: 'Descuento Total de Artículos', tr: 'Toplam Ürün İndirimi'),
              _sl(ar: 'اجمالي خصم الأصناف', en: 'Total Items Discount', hi: 'कुल आइटम छूट', ur: 'کل آئٹمز ڈسکاؤنٹ', es: 'Descuento Total de Artículos', tr: 'Toplam Ürün İndirimi'),
              _impliedDiscount,
            ),
          _buildTotalRow(_ml(ar: 'قيمة الضريبة', en: 'Tax Amount', hi: 'कर राशि', ur: 'ٹیکس رقم', es: 'Monto del Impuesto', tr: 'Vergi Tutarı'), _sl(ar: 'قيمة الضريبة', en: 'Tax Amount', hi: 'कर राशि', ur: 'ٹیکس رقم', es: 'Monto del Impuesto', tr: 'Vergi Tutarı'), data!.vatAmount),
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
                      Text(_ml(ar: 'الاجمالي بعد الضريبة', en: 'Total After Tax', hi: 'कर के बाद कुल', ur: 'ٹیکس کے بعد کل', es: 'Total Después de Impuestos', tr: 'Vergi Sonrası Toplam'),
                          style: GoogleFonts.tajawal(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Colors.black)),
                      if (_sl(ar: 'الاجمالي بعد الضريبة', en: 'Total After Tax', hi: 'कर के बाद कुल', ur: 'ٹیکس کے بعد کل', es: 'Total Después de Impuestos', tr: 'Vergi Sonrası Toplam').isNotEmpty)
                        Text(_sl(ar: 'الاجمالي بعد الضريبة', en: 'Total After Tax', hi: 'कर के बाद कुल', ur: 'ٹیکس کے بعد کل', es: 'Total Después de Impuestos', tr: 'Vergi Sonrası Toplam'),
                            style: GoogleFonts.tajawal(
                                fontSize: 15,
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
                      '${(data?.totalInclVat ?? 0.0).toStringAsFixed(2)} ${_ml(ar: 'ريال', en: 'SAR', hi: 'SAR', ur: 'SAR', es: 'SAR', tr: 'SAR')}',
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 24,
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
                                fontSize: 19, color: Colors.black, fontWeight: FontWeight.bold)),
                        if (_sl(ar: 'طرق الدفع', en: 'Payment Methods', hi: 'भुगतान के तरीके', ur: 'ادائیگی کے طریقے', es: 'Métodos de Pago', tr: 'Ödeme Yöntemleri').isNotEmpty)
                          Text(_sl(ar: 'طرق الدفع', en: 'Payment Methods', hi: 'भुगतान के तरीके', ur: 'ادائیگی کے طریقے', es: 'Métodos de Pago', tr: 'Ödeme Yöntemleri'),
                              style: GoogleFonts.tajawal(
                                  fontSize: 14, color: Colors.black, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _translatePayMethod(data?.paymentMethod ?? ''),
                      style: GoogleFonts.tajawal(
                          fontSize: 18,
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
                        fontSize: 19, color: Colors.black, fontWeight: FontWeight.bold)),
                if (labelEn.isNotEmpty)
                  Text(labelEn,
                      style: GoogleFonts.tajawal(
                          fontSize: 14, color: Colors.black, fontWeight: FontWeight.bold)),
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
                    amount.toStringAsFixed(2),
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Colors.black),
                  ),
                  const SizedBox(width: 4),
                  Text(_translateCurrency(ApiConstants.currency),
                      style: GoogleFonts.tajawal(
                          fontSize: 16, color: Colors.black, fontWeight: FontWeight.bold)),
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
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: Colors.black)),
                    ),
                    if (percentage != null)
                      Text(' (${percentage.toStringAsFixed(0)}%)',
                          style: GoogleFonts.tajawal(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.black)),
                  ],
                ),
                if (labelEn.isNotEmpty)
                  Text(labelEn,
                      style: GoogleFonts.tajawal(
                          fontSize: 14, color: Colors.black, fontWeight: FontWeight.bold)),
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
                    '-${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Colors.black),
                  ),
                  const SizedBox(width: 4),
                  Text(_translateCurrency(ApiConstants.currency),
                      style: GoogleFonts.tajawal(
                          fontSize: 16, color: Colors.black, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
