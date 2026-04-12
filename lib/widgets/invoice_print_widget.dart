import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hermosa_pos/utils/paper_width_utils.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/receipt_data.dart';
import '../services/api/api_constants.dart';
import 'invoice_html_template.dart';

/// Dashed Divider Widget
class DashedDivider extends StatelessWidget {
  final Color color;
  const DashedDivider({super.key, this.color = Colors.black});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 4.0;
        const dashSpace = 3.0;
        final dashCount = (boxWidth / (dashWidth + dashSpace)).floor();
        return Flex(
          direction: Axis.horizontal,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: dashWidth,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: color),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Invoice Print Widget - Black & White Theme
class InvoicePrintWidget extends StatelessWidget {
  final OrderReceiptData? data;
  final Map<String, dynamic>? kitchenData;
  final bool isTest;
  final int paperWidthMm;
  final String? orderType;
  final String? tableNumber;
  final String? carNumber;
  final String? dailyOrderNumber;
  final String? carBrand;
  final String? carModel;
  final String? carPlateNumber;
  final String? carYear;
  final String? clientName;
  final String? clientPhone;
  final String? clientTaxNumber;
  final String? commercialRegisterNumber;
  final String? returnPolicy;
  final bool useHtmlView;

  const InvoicePrintWidget({
    super.key,
    this.data,
    this.kitchenData,
    this.isTest = false,
    this.paperWidthMm = 58,
    this.orderType,
    this.tableNumber,
    this.carNumber,
    this.dailyOrderNumber,
    this.carBrand,
    this.carModel,
    this.carPlateNumber,
    this.carYear,
    this.clientName,
    this.clientPhone,
    this.clientTaxNumber,
    this.commercialRegisterNumber,
    this.returnPolicy,
    this.useHtmlView = false,
    this.isRtl = true,
    this.isCreditNote = false,
  });

  final bool isRtl;
  final bool isCreditNote;

  double get _receiptWidth => invoiceWidgetWidthForPaper(paperWidthMm);
  double get _summaryLabelWidth => _receiptWidth * 0.52;

  double get _impliedDiscount {
    if (data == null || data!.hasOrderDiscount) return data?.orderDiscountAmount ?? 0;
    final itemsSum = data!.items.fold<double>(0.0, (s, i) => s + i.total);
    return itemsSum > data!.totalExclVat ? itemsSum - data!.totalExclVat : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final receiptWidth = _receiptWidth;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
        key: const ValueKey('invoice-print-root'),
        width: receiptWidth,
        color: Colors.white,
        padding: const EdgeInsets.all(8),
        child: DefaultTextStyle(
          style: GoogleFonts.tajawal(
            color: Colors.black,
            fontSize: isTest ? 18 : 14,
            fontWeight: FontWeight.bold,
            height: 1.4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isTest)
                _buildTestView()
              else if (kitchenData != null)
                _buildKitchenView()
              else if (data != null) ...[
                _buildHeader(),
                _buildInvoiceTitle(),
                if (clientName != null ||
                    clientPhone != null ||
                    clientTaxNumber != null)
                  _buildClientInfo(),
                if ((orderType?.isNotEmpty == true
                            ? orderType
                            : data!.orderType) ==
                        'restaurant_parking' ||
                    (data!.carNumber.isNotEmpty) ||
                    (carNumber != null && carNumber!.isNotEmpty))
                  _buildCarInfo(),
                _buildItems(),
                _buildTotals(),
                _buildFooter(),
              ] else
                const Center(child: Text('لا توجد بيانات للطباعة')),
            ],
          ),
        ),
      ),
    );
  }

  String generateHtmlForPrint() {
    if (data == null) return "<html><body>Test / Kitchen Print</body></html>";
    return InvoiceHtmlTemplate.generateInvoiceHtml(
      data: data!,
      orderType: orderType,
      tableNumber: tableNumber,
      carNumber: carNumber,
      dailyOrderNumber: dailyOrderNumber,
      carBrand: carBrand,
      carModel: carModel,
      carPlateNumber: carPlateNumber,
      carYear: carYear,
      clientName: clientName,
      clientPhone: clientPhone,
      clientTaxNumber: clientTaxNumber,
      commercialRegisterNumber: commercialRegisterNumber,
      returnPolicy: returnPolicy,
      paperWidthMm: paperWidthMm,
    );
  }

  Widget _buildHeader() {
    if (data == null) return const SizedBox.shrink();
    final hasLogo = data!.sellerLogo != null && data!.sellerLogo!.isNotEmpty;
    final resolvedDailyOrderNumber =
        (dailyOrderNumber != null && dailyOrderNumber!.trim().isNotEmpty)
            ? dailyOrderNumber!.trim()
            : (data!.orderNumber != null && data!.orderNumber!.trim().isNotEmpty)
                ? data!.orderNumber!.trim()
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
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Image.network(
                    data!.sellerLogo!,
                    height: 80,
                    width: 80,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox(),
                  ),
                ),
              Text(
                data!.sellerNameAr,
                style: GoogleFonts.tajawal(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black),
                textAlign: TextAlign.center,
              ),
              if (data!.sellerNameEn.isNotEmpty && data!.sellerNameEn != data!.sellerNameAr)
                Text(
                  data!.sellerNameEn,
                  style: GoogleFonts.tajawal(
                      fontSize: 13, color: Colors.black, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 6),
              if (data!.branchAddress != null && data!.branchAddress!.isNotEmpty)
                Text(
                  data!.branchAddress!,
                  style: GoogleFonts.tajawal(fontSize: 12, color: Colors.black, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              if (data!.branchMobile != null && data!.branchMobile!.isNotEmpty)
                Text(
                  data!.branchMobile!,
                  style: GoogleFonts.tajawal(
                      fontSize: 13, color: Colors.black, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const DashedDivider(),
        const SizedBox(height: 12),
        
        // Daily Order Number Boxed
        if (resolvedDailyOrderNumber != null)
          Column(
            children: [
              Text(
                'رقم الطلب اليومي',
                style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: Text(
                  resolvedDailyOrderNumber,
                  style: GoogleFonts.tajawal(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),

        // Invoice Number Boxed
        if (resolvedInvoiceNumber.isNotEmpty)
          Column(
            children: [
              Text(
                'رقم الفاتورة / Invoice No.',
                style: GoogleFonts.tajawal(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: Text(
                  resolvedInvoiceNumber,
                  style: GoogleFonts.tajawal(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),

        const DashedDivider(),
        const SizedBox(height: 8),

        _buildInfoItem(
            'الكاشير',
            'Cashier',
            data!.cashierName?.isNotEmpty == true
                ? data!.cashierName!
                : data!.sellerNameAr),
        _buildInfoItem('الرقم الضريبي', 'VAT Number',
            data!.vatNumber.isNotEmpty ? data!.vatNumber : 'غير متوفر'),
        if (data!.commercialRegisterNumber?.isNotEmpty == true || commercialRegisterNumber?.isNotEmpty == true)
          _buildInfoItem('رقم السجل التجاري', 'CR Number',
              (data!.commercialRegisterNumber?.isNotEmpty == true ? data!.commercialRegisterNumber : commercialRegisterNumber)!),
        _buildInfoItem(
            'التاريخ والوقت',
            'Date & Time',
            data!.issueDateTime,
            isLtr: true),
        if (data?.paymentMethod != null)
          _buildInfoItem('طريقة الدفع', 'Payment Method', data!.paymentMethod),
        
        if ((orderType?.isNotEmpty == true) || (data!.orderType?.isNotEmpty == true))
          _buildInfoItem(
              'نوع الطلب',
              'Order Type',
              _getOrderTypeArabic(orderType?.isNotEmpty == true ? orderType! : data!.orderType!)),
        
        if (tableNumber != null || data!.tableNumber != null)
          _buildInfoItem('رقم الطاولة', 'Table Number', (tableNumber ?? data!.tableNumber)!),

        if ((clientName ?? data!.clientName) != null)
          _buildInfoItem('العميل', 'Customer', (clientName ?? data!.clientName)!),
        
        if ((clientPhone ?? data!.clientPhone) != null)
          _buildInfoItem('جوال العميل', 'Customer Phone', (clientPhone ?? data!.clientPhone)!, isLtr: true),
          
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildNumberBadge({
    required String labelAr,
    required String labelEn,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black, width: 1.5),
          ),
          child: Text(
            value,
            style: GoogleFonts.tajawal(
              fontSize: 14,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  labelAr,
                  style: GoogleFonts.tajawal(fontSize: 14, color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value,
                  style: GoogleFonts.tajawal(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.end,
                  textDirection: isLtr ? TextDirection.ltr : TextDirection.rtl,
                ),
              ),
            ],
          ),
          Text(
            labelEn,
            style: GoogleFonts.tajawal(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const DashedDivider(),
        ],
      ),
    );
  }

  Widget _buildInvoiceTitle() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 2.5),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'فاتورة ضريبية مبسطة',
            style: GoogleFonts.tajawal(
              fontSize: 17, // Slightly larger
              fontWeight: FontWeight.w900,
              color: Colors.black,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            'Simplified Tax Invoice',
            style: GoogleFonts.tajawal(
              fontSize: 11, // Small and sleek
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildClientInfo() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          if (clientName != null)
            _buildInfoItem('اسم العميل', 'Client Name', clientName!),
          if (clientPhone != null)
            _buildInfoItem('جوال العميل', 'Client Phone', clientPhone!,
                isLtr: true),
          if (clientTaxNumber != null)
            _buildInfoItem('الرقم الضريبي', 'Tax number', clientTaxNumber!),
        ],
      ),
    );
  }

  Widget _buildCarInfo([String? overrideCarNumber]) {
    final effectiveCarNumber = overrideCarNumber?.trim().isNotEmpty == true
        ? overrideCarNumber!
        : (data?.carNumber.isNotEmpty == true) ? data!.carNumber : (carNumber ?? '');
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
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
                  'معلومات السيارة',
                  style: GoogleFonts.tajawal(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black),
                  textAlign: TextAlign.center,
                ),
                Text(
                  'Car Information',
                  style:
                      GoogleFonts.tajawal(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          if (effectiveCarNumber.isNotEmpty)
            _buildCarInfoRow('رقم اللوحة / التفاصيل', 'Details', effectiveCarNumber, isLast: true),
        ],
      ),
    );
  }

  Widget _buildCarInfoRow(String labelAr, String labelEn, String value,
      {bool isLast = false}) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 100,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: Colors.black)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(labelAr,
                      style: GoogleFonts.tajawal(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black)),
                  Text(labelEn,
                      style: GoogleFonts.tajawal(
                          fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(value,
                    style:
                        GoogleFonts.tajawal(fontSize: 14, color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        if (!isLast) const DashedDivider(),
      ],
    );
  }

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
                    padding: const EdgeInsets.all(4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الصنف / Item',
                            style: GoogleFonts.tajawal(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, color: Colors.black),
                SizedBox(
                  width: 45,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('كمية',
                            style: GoogleFonts.tajawal(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                        Text('Qty',
                            style: GoogleFonts.tajawal(
                                fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, color: Colors.black),
                SizedBox(
                  width: 60,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('سعر',
                            style: GoogleFonts.tajawal(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                        Text('Price',
                            style: GoogleFonts.tajawal(
                                fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, color: Colors.black),
                SizedBox(
                  width: 70,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text('مجموع',
                            style: GoogleFonts.tajawal(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.black)),
                        Text('Total',
                            style: GoogleFonts.tajawal(
                                fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold)),
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
                              horizontal: 4, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.nameAr,
                                style: GoogleFonts.tajawal(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black),
                              ),
                              if (item.nameEn.isNotEmpty && item.nameEn != item.nameAr)
                                Text(
                                  item.nameEn,
                                  style: GoogleFonts.tajawal(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Container(width: 1, color: Colors.black),
                      SizedBox(
                        width: 45,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          child: Text(
                            item.quantity.toStringAsFixed(0),
                            style: GoogleFonts.tajawal(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.black),
                          ),
                        ),
                      ),
                      Container(width: 1, color: Colors.black),
                      SizedBox(
                        width: 60,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          child: Text(
                            itemPrice.toStringAsFixed(2),
                            style: GoogleFonts.tajawal(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.black),
                          ),
                        ),
                      ),
                      Container(width: 1, color: Colors.black),
                      SizedBox(
                        width: 70,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          child: Text(
                            item.total.toStringAsFixed(2),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
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
              if (hasAddons)
                ...item.addons!.map((addon) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 2),
                      decoration: const BoxDecoration(
                        border:
                            Border(bottom: BorderSide(color: Colors.black38)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '+ ${addon.nameAr}',
                            style: GoogleFonts.tajawal(
                                fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            addon.price.toStringAsFixed(2),
                            style: GoogleFonts.tajawal(
                                fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    )),
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
                        '${item.discountName ?? 'خصم'}${item.discountPercentage != null ? ' (${item.discountPercentage!.toStringAsFixed(0)}%)' : ''}',
                        style: GoogleFonts.tajawal(
                            fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '-${item.discountAmount!.toStringAsFixed(2)}',
                        style: GoogleFonts.tajawal(
                            fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
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

  Widget _buildTotals() {
    if (data == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12, top: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildTotalRow('الاجمالي قبل الضريبة', 'Total Before Tax', data!.totalExclVat),
          // Calculate implied discount
          if (_impliedDiscount > 0.01)
            _buildDiscountRow(
              'اجمالي خصم الأصناف',
              'Total Items Discount',
              _impliedDiscount,
            ),
          _buildTotalRow('قيمة الضريبة', 'Tax Amount', data!.vatAmount),
          const Divider(height: 16, thickness: 2, color: Colors.black),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
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
                      Text('الاجمالي بعد الضريبة',
                          style: GoogleFonts.tajawal(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black)),
                      Text('Total After Tax',
                          style: GoogleFonts.tajawal(
                              fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold)),
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
                          '${(data?.totalInclVat ?? 0.0).toStringAsFixed(2)} ريال',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildTotalRow('المدفوع', 'Paid', data!.totalInclVat),
          _buildTotalRow('المتبقي', 'Remaining', 0.0),
          const DashedDivider(),
          if (data!.payments.isNotEmpty)
            ...data!.payments.map((p) => _buildTotalRow(p.methodLabel, 'Payment', p.amount)),
          if (data!.paymentMethod.isNotEmpty && data!.payments.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _summaryLabelWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('طرق الدفع',
                            style: GoogleFonts.tajawal(
                                fontSize: 14, color: Colors.black, fontWeight: FontWeight.bold)),
                        Text('Payment Methods',
                            style: GoogleFonts.tajawal(
                                fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      data?.paymentMethod ?? '',
                      style: GoogleFonts.tajawal(
                          fontSize: 12,
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(labelAr,
                        style: GoogleFonts.tajawal(
                            fontSize: 14, color: Colors.black, fontWeight: FontWeight.bold)),
                    Text(labelEn,
                        style: GoogleFonts.tajawal(
                            fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold)),
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
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.black),
                      ),
                      const SizedBox(width: 4),
                      Text(ApiConstants.currency,
                          style: GoogleFonts.tajawal(
                              fontSize: 11, color: Colors.black, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const DashedDivider(),
      ],
    );
  }

  Widget _buildDiscountRow(String labelAr, String labelEn, double amount,
      {double? percentage}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
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
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black)),
                        ),
                        if (percentage != null)
                          Text(' (${percentage.toStringAsFixed(0)}%)',
                              style: GoogleFonts.tajawal(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black)),
                      ],
                    ),
                    Text(labelEn,
                        style: GoogleFonts.tajawal(
                            fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold)),
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
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.black),
                      ),
                      const SizedBox(width: 4),
                      Text(ApiConstants.currency,
                          style: GoogleFonts.tajawal(
                              fontSize: 11, color: Colors.black, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const DashedDivider(),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          _buildQrSection(),
          if (returnPolicy != null && returnPolicy!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.only(bottom: 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.black38)),
              ),
              child: Column(
                children: [
                  Text(
                    'سياسة الاسترجاع والاستبدال',
                    style: GoogleFonts.tajawal(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.black),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    returnPolicy!,
                    style: GoogleFonts.tajawal(
                        fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            child: Column(
              children: [
                Text(
                  'شكرا لثقتكم بنا',
                  style: GoogleFonts.tajawal(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.black),
                  textAlign: TextAlign.center,
                ),
                Text(
                  'Thank you for trusting us',
                  style:
                      GoogleFonts.tajawal(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const DashedDivider(),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black38),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'برنامج هيرموسا المحاسبي المتكامل',
                        style: GoogleFonts.tajawal(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.black),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        'Hermosa Integrated Accounting Software',
                        style: GoogleFonts.tajawal(
                            fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'hermosaapp.com',
                        style: GoogleFonts.tajawal(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.black),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrSection() {
    final zatcaImage = data?.zatcaQrImage?.trim() ?? '';
    final rawQr = data?.qrCodeBase64.trim() ?? '';
    Widget? qrWidget;

    // Highest priority: Generate the QR synchronously to avoid screenshot timing issues
    if (rawQr.isNotEmpty && !rawQr.startsWith('http') && !rawQr.startsWith('data:')) {
      try {
        // Decode base64 to ensure it builds correctly for ZATCA format
        final bytes = base64Decode(rawQr);
        final tlvString = String.fromCharCodes(bytes);
        qrWidget = QrImageView(
          data: tlvString,
          version: QrVersions.auto,
          size: 150,
          gapless: true,
          backgroundColor: Colors.white,
        );
      } catch (_) {
        qrWidget = QrImageView(
          data: rawQr,
          version: QrVersions.auto,
          size: 150,
          gapless: true,
          backgroundColor: Colors.white,
        );
      }
    } else if (rawQr.startsWith('data:image')) {
      // Synchronous data image
      try {
        final parts = rawQr.split(',');
        final base64Part = parts.length > 1 ? parts.last : '';
        if (base64Part.isNotEmpty) {
          final bytes = base64Decode(base64Part);
          qrWidget = Image.memory(
            bytes,
            width: 150,
            height: 150,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          );
        }
      } catch (_) {
        qrWidget = null;
      }
    } else if (zatcaImage.isNotEmpty) {
      // Fallback: network image (risks being missed by screenshot if slow)
      qrWidget = Image.network(
        zatcaImage,
        width: 150,
        height: 150,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } else if (rawQr.startsWith('http')) {
      qrWidget = Image.network(
        rawQr,
        width: 150,
        height: 150,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    if (qrWidget == null || qrWidget is SizedBox) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.white,
      padding: const EdgeInsets.all(8),
      child: Center(child: qrWidget),
    );
  }

  String _getOrderTypeArabic(String type) {
    final normalizedType = type.toLowerCase().trim();
    switch (normalizedType) {
      case 'restaurant_internal':
        return 'طلب داخلي';
      case 'restaurant_pickup':
      case 'restaurant_takeaway':
        return 'طلب خارجي';
      case 'restaurant_delivery':
        return 'توصيل';
      case 'restaurant_parking':
      case 'cars':
      case 'car':
        return 'سيارات';
      case 'services':
      case 'service':
        return 'محلي';
      case 'payment':
        return 'دفع نقدي';
      case 'postpaid':
      case 'pay_later':
        return 'دفع لاحقاً';
      case 'card':
        return 'بطاقة';
      case 'stc':
        return 'STC Pay';
      case 'bank_transfer':
        return 'تحويل بنكي';
      case 'wallet':
        return 'محفظة';
      case 'cheque':
        return 'شيك';
      case 'petty_cash':
        return 'بيتي كاش';
      case 'tabby':
        return 'تابي';
      case 'tamara':
        return 'تمارا';
      case 'keeta':
        return 'كيتا';
      case 'my_fatoorah':
        return 'ماي فاتورة';
      case 'jahez':
        return 'جاهز';
      case 'talabat':
        return 'طلبات';
      default:
        return type;
    }
  }

  Widget _buildTestView() {
    return Column(
      children: [
        const Icon(Icons.print, size: 64, color: Colors.black),
        const SizedBox(height: 16),
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
          style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        const DashedDivider(),
        const SizedBox(height: 8),
        Text(
          'التاريخ: ${DateTime.now().toString().split('.').first}',
          style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        Text(
          'عرض الورق: $paperWidthMm ملم',
          style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const DashedDivider(),
        const SizedBox(height: 24),
        Text(
          'اللغة العربية تعمل بنجاح',
          style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        const Text('! @ # \$ % ^ & * ( )'),
        const SizedBox(height: 48),
        const DashedDivider(),
        Text(
          '✂ قُص هنا / CUT HERE ✂',
          style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const DashedDivider(),
        const SizedBox(height: 60), // Extra space for physical cutting
      ],
    );
  }

  Widget _buildMetaRow(String labelAr, String labelEn, String value, {bool isLarge = false}) {
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
                labelAr,
                style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              Text(
                labelEn,
                style: GoogleFonts.tajawal(fontSize: 10, color: Colors.black87, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.tajawal(
                fontSize: isLarge ? 18 : 14,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKitchenView() {
    if (kitchenData == null) return const SizedBox.shrink();

    final orderNumber = kitchenData!['orderNumber'] ?? '';
    final orderTypeRaw = kitchenData!['orderType'] ?? '';
    final items = (kitchenData!['items'] as List? ?? []);
    final note = kitchenData!['note'];
    final createdAt = kitchenData!['createdAt'] as DateTime?;

    final clientNameLocal = kitchenData!['clientName'] ?? clientName;
    final clientPhoneLocal = kitchenData!['clientPhone'] ?? clientPhone;
    final tableNumberLocal = kitchenData!['tableNumber'] ?? tableNumber;
    final carNumberLocal = kitchenData!['carNumber'] ?? carNumber;
    final cashierNameLocal = kitchenData!['cashierName'];
    final printerNameLocal = kitchenData!['printerName'];

    final displayOrderTypeAr = _getOrderTypeArabic(orderTypeRaw);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Column(
          children: [
            Text(
              'طلب مطبخ / Kitchen Ticket',
              style: GoogleFonts.tajawal(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            if (printerNameLocal != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'القسم / Dept: $printerNameLocal',
                  style: GoogleFonts.tajawal(fontSize: 16, color: Colors.black, fontWeight: FontWeight.bold),
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
                      'رقم الطلب',
                      style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      orderNumber.toString().replaceAll('#', ''),
                      style: GoogleFonts.tajawal(fontSize: 56, fontWeight: FontWeight.w900, height: 1.0),
                    ),
                    Text(
                      'ORDER #',
                      style: GoogleFonts.tajawal(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.bold),
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
                          'طاولة',
                          style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          tableNumberLocal.toString(),
                          style: GoogleFonts.tajawal(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, height: 1.0),
                        ),
                        Text(
                          'TABLE',
                          style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
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

        // Metadata Section
        _buildMetaRow('نوع الطلب', 'Order Type', displayOrderTypeAr, isLarge: true),
        if (tableNumberLocal != null)
          _buildMetaRow('رقم الطاولة', 'Table Number', tableNumberLocal.toString(), isLarge: true),
        if (cashierNameLocal != null)
          _buildMetaRow('الكاشير', 'Cashier', cashierNameLocal.toString()),
        if (clientNameLocal != null)
          _buildMetaRow('العميل', 'Customer', clientNameLocal.toString()),
        if (clientPhoneLocal != null)
          _buildMetaRow('الجوال', 'Phone', clientPhoneLocal.toString().trim()),
        if (createdAt != null)
          _buildMetaRow(
            'التاريخ',
            'Date & Time',
            '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}'
          ),
        if (carNumberLocal?.isNotEmpty == true || data?.carNumber.isNotEmpty == true)
          _buildCarInfo(carNumberLocal),

        const SizedBox(height: 16),
        const Divider(thickness: 3, color: Colors.black),
        
        // Items Table Header
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('الصنف', style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold)),
                  Text('Item', style: GoogleFonts.tajawal(fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            SizedBox(
              width: 50,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('الكمية', style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold)),
                  Text('Qty', style: GoogleFonts.tajawal(fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        const Divider(thickness: 1, color: Colors.black54),
        
        // Items List
        ...items.map((item) {
          final rawNameAr = item['nameAr']?.toString() ?? '';
          String nameAr = rawNameAr.isNotEmpty ? rawNameAr : (item['name']?.toString() ?? '');

          final rawNameEn = item['nameEn']?.toString() ?? '';
          String nameEn = rawNameEn.isNotEmpty ? rawNameEn : '';

          if (nameEn.isEmpty && nameAr.contains(' - ')) {
            final parts = nameAr.split(' - ');
            nameAr = parts.first.trim();
            nameEn = parts.last.trim();
          }
          final rawQty = item['quantity'] ?? 1;
          final double parsedQty = double.tryParse(rawQty.toString()) ?? 1.0;
          final qtyStr = parsedQty == parsedQty.toInt() ? parsedQty.toInt().toString() : parsedQty.toString();
          final extras = (item['extras'] as List? ?? []);
          final itemNote = item['notes'];

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
                            style: GoogleFonts.tajawal(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          if (nameEn.isNotEmpty && nameEn != nameAr)
                            Text(
                              nameEn,
                              style: GoogleFonts.tajawal(fontSize: 14, color: Colors.black, fontWeight: FontWeight.bold),
                            ),

                          // Extras
                          if (extras.isNotEmpty)
                            ...extras.map((ex) => Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '+ ${ex['name']}',
                                style: GoogleFonts.tajawal(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            )),
                          
                          // Item specific notes
                          if (itemNote != null && itemNote.toString().isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'ملاحظة: $itemNote',
                                style: GoogleFonts.tajawal(fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Quantity
                    Container(
                      width: 50,
                      alignment: AlignmentDirectional.topEnd,
                      child: Text(
                        qtyStr,
                        style: GoogleFonts.tajawal(fontSize: 26, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
              const DashedDivider(),
            ],
          );
        }),

        // General Booking Note
        if (note != null && note.toString().isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.05),
              border: Border.all(color: Colors.black, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ملاحظة عامة / General Note:',
                  style: GoogleFonts.tajawal(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  note.toString(),
                  style: GoogleFonts.tajawal(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),
      ],
    );
  }
}
