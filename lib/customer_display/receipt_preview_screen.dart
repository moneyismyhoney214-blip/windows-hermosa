import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Receipt Preview Widget — In-App Invoice Display
///
/// Renders a preview of the invoice/receipt within the Flutter app itself.
/// Inspired by the Vue PrintInvoice.vue template structure:
///  - Seller info (logo, name, address, tax number)
///  - Order details (order number, date, time, type)
///  - Line items (name, qty, price)
///  - Totals (subtotal, tax, discount, total)
///  - Payment method
///
/// Usage:
///   ReceiptPreviewScreen.show(context, data: {...});
class ReceiptPreviewScreen extends StatelessWidget {
  /// Payment/order data to display
  final Map<String, dynamic> receiptData;
  final VoidCallback? onDismiss;

  const ReceiptPreviewScreen({
    super.key,
    required this.receiptData,
    this.onDismiss,
  });

  /// Show as a full-screen dialog
  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> data,
    VoidCallback? onDismiss,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (_) => ReceiptPreviewScreen(
        receiptData: data,
        onDismiss: onDismiss ?? () => Navigator.of(context).pop(),
      ),
    );
  }

  // ─── Data extraction helpers ────────────────────────────────────

  String _firstStr(List<dynamic> values, [String fallback = '']) {
    for (final v in values) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return fallback;
  }

  double _firstNum(List<dynamic> values, [double fallback = 0.0]) {
    for (final v in values) {
      if (v == null) continue;
      if (v is num) return v.toDouble();
      if (v is String) {
        final d = double.tryParse(v.replaceAll(RegExp(r'[^\d.]'), ''));
        if (d != null) return d;
      }
    }
    return fallback;
  }

  String _str(dynamic v, [String fallback = '']) {
    return _firstStr([v], fallback);
  }

  double _num(dynamic v) {
    return _firstNum([v]);
  }

  // Extract nested fields
  Map<String, dynamic> get _branch =>
      (receiptData['branch'] as Map<String, dynamic>?) ?? {};

  Map<String, dynamic> get _seller =>
      (_branch['seller'] as Map<String, dynamic>?) ?? {};

  Map<String, dynamic> get _invoice =>
      (receiptData['invoice'] as Map<String, dynamic>?) ?? {};

  Map<String, dynamic> get _payment =>
      (receiptData['payment'] as Map<String, dynamic>?) ??
      (receiptData['transaction'] as Map<String, dynamic>?) ??
      {};

  List<Map<String, dynamic>> get _items {
    final rawItems = _invoice['items'] ?? receiptData['items'] ?? [];
    if (rawItems is! List) return [];
    return rawItems.map((e) {
      if (e is Map<String, dynamic>) return e;
      if (e is Map) return e.map((k, v) => MapEntry(k.toString(), v));
      return <String, dynamic>{};
    }).toList();
  }

  String get _sellerName => _firstStr([
        _branch['seller_name'],
        _seller['name'],
        receiptData['seller_name']
      ], 'HERMOSA');

  String get _sellerAddress => _firstStr([
        _branch['address'],
        receiptData['address']
      ]);

  String get _taxNumber => _firstStr([
        _seller['tax_number'],
        receiptData['tax_number']
      ]);

  String get _invoiceNumber => _firstStr([
        _invoice['invoice_number'],
        receiptData['invoice_number']
      ]);

  String get _orderNumber => _firstStr([
        receiptData['order_number'],
        receiptData['orderNumber'],
        _invoice['order_number']
      ]);

  String get _date => _firstStr([_invoice['date'], receiptData['date']]);
  String get _time => _firstStr([_invoice['time'], receiptData['time']]);

  String get _orderType => _firstStr([receiptData['type'], receiptData['order_type']]);

  String get _orderTypeLabel {
    switch (_orderType) {
      case 'restaurant_internal':
        return 'محلي';
      case 'restaurant_pickup':
        return 'استلام';
      case 'restaurant_parking':
        return 'سيارات';
      case 'restaurant_delivery':
        return 'توصيل';
      default:
        return _orderType;
    }
  }

  double get _subtotal => _firstNum([_invoice['price'], receiptData['subtotal']]);
  double get _tax => _firstNum([_invoice['tax'], receiptData['tax']]);
  double get _discount => _firstNum([_invoice['discount'], receiptData['discount']]);
  double get _total => _firstNum([_invoice['total'], receiptData['total'], receiptData['amount']]);

  String get _paymentMethod {
    final method = _firstStr([_payment['method'], receiptData['payment_method']]);
    if (method.isEmpty) return 'بطاقة';
    if (method.toLowerCase().contains('cash')) return 'نقد';
    if (method.toLowerCase().contains('card')) return 'بطاقة';
    return method;
  }

  String get _currencyAr => _str(
      (_branch['currency'] as Map?)?.entries
          .firstWhere((e) => e.key == 'ar',
              orElse: () => const MapEntry('ar', 'ر.س'))
          .value,
      'ر.س');

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 700),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              // Close button
              Align(
                alignment: AlignmentDirectional.topEnd,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton(
                    onPressed: onDismiss,
                    icon: const Icon(LucideIcons.x, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF1F5F9),
                      foregroundColor: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),

              // Receipt content
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.rtl,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      children: [
                        _buildSellerHeader(),
                        _buildDivider(),
                        _buildOrderInfo(),
                        _buildDivider(),
                        if (_items.isNotEmpty) ...[
                          _buildItemsTable(),
                          _buildDivider(),
                        ],
                        _buildTotals(),
                        _buildDivider(),
                        _buildPaymentInfo(),
                        const SizedBox(height: 16),
                        _buildFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: List.generate(
          40,
          (_) => Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              height: 1,
              color: const Color(0xFFE2E8F0),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSellerHeader() {
    return Column(
      children: [
        // Logo placeholder
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF5EB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFF58220).withValues(alpha: 0.3),
            ),
          ),
          child: Center(
            child: Text(
              _sellerName.isNotEmpty ? _sellerName[0].toUpperCase() : 'H',
              style: GoogleFonts.tajawal(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: const Color(0xFFF58220),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _sellerName,
          style: GoogleFonts.tajawal(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF0F172A),
          ),
        ),
        if (_sellerAddress.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            _sellerAddress,
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(
              fontSize: 12,
              color: const Color(0xFF64748B),
            ),
          ),
        ],
        if (_taxNumber.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'الرقم الضريبي: $_taxNumber',
            style: GoogleFonts.tajawal(
              fontSize: 11,
              color: const Color(0xFF94A3B8),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOrderInfo() {
    final entries = <MapEntry<String, String>>[];

    if (_invoiceNumber.isNotEmpty) {
      entries.add(MapEntry('رقم الفاتورة', _invoiceNumber));
    }
    if (_orderNumber.isNotEmpty) {
      entries.add(MapEntry('رقم الطلب', _orderNumber));
    }
    if (_date.isNotEmpty) {
      entries.add(MapEntry('التاريخ', _date));
    }
    if (_time.isNotEmpty) {
      entries.add(MapEntry('الوقت', _time));
    }
    if (_orderTypeLabel.isNotEmpty) {
      entries.add(MapEntry('نوع الطلب', _orderTypeLabel));
    }

    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      children: entries.map((e) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                e.key,
                style: GoogleFonts.tajawal(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B),
                ),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  e.value,
                  style: GoogleFonts.tajawal(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildItemsTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'الصنف',
                  style: GoogleFonts.tajawal(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: Center(
                  child: Text(
                    'الكمية',
                    style: GoogleFonts.tajawal(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 70,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    'المبلغ',
                    style: GoogleFonts.tajawal(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Items
        ..._items.map((item) {
          final name = _str(item['item_name']);
          final qty = _str(item['quantity'], '1');
          final total = _num(item['total']);
          final addons = item['addons'];

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        name,
                        style: GoogleFonts.tajawal(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Center(
                        child: Text(
                          qty,
                          style: GoogleFonts.tajawal(
                            fontSize: 13,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 70,
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(
                          total.toStringAsFixed(2),
                          style: GoogleFonts.tajawal(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Addons
                if (addons is List)
                  ...addons.map((addon) {
                    if (addon is! Map) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsetsDirectional.only(start: 16, top: 2),
                      child: Text(
                        '+ ${_str(addon['attribute'])} ${_str(addon['option'])}  ${_str(addon['total'])}',
                        style: GoogleFonts.tajawal(
                          fontSize: 11,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTotals() {
    return Column(
      children: [
        if (_subtotal > 0)
          _totalRow(
            'الإجمالي قبل الضريبة',
            'Total Before Tax',
            _subtotal,
          ),
        if (_discount > 0)
          _totalRow(
            'الخصم',
            'Discount',
            _discount,
            valueColor: const Color(0xFF10B981),
            prefix: '- ',
          ),
        if (_tax > 0)
          _totalRow(
            'الضريبة',
            'Tax',
            _tax,
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF5EB),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الإجمالي',
                    style: GoogleFonts.tajawal(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    'Total',
                    style: GoogleFonts.tajawal(
                      fontSize: 11,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  '${_total.toStringAsFixed(2)} $_currencyAr',
                  style: GoogleFonts.tajawal(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFF58220),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _totalRow(
    String labelAr,
    String labelEn,
    double value, {
    Color valueColor = const Color(0xFF0F172A),
    String prefix = '',
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                labelAr,
                style: GoogleFonts.tajawal(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B),
                ),
              ),
              Text(
                labelEn,
                style: GoogleFonts.tajawal(
                  fontSize: 10,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
          Text(
            '$prefix${value.toStringAsFixed(2)} $_currencyAr',
            style: GoogleFonts.tajawal(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.checkCircle2,
            color: Color(0xFF16A34A),
            size: 24,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تم الدفع بنجاح',
                style: GoogleFonts.tajawal(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF16A34A),
                ),
              ),
              Text(
                'طريقة الدفع: $_paymentMethod',
                style: GoogleFonts.tajawal(
                  fontSize: 12,
                  color: const Color(0xFF15803D),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Text(
          'شكراً لزيارتكم',
          style: GoogleFonts.tajawal(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF0F172A),
          ),
        ),
        Text(
          'Thank you for your visit',
          style: GoogleFonts.tajawal(
            fontSize: 12,
            color: const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }
}
