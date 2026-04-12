import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models.dart';
import '../models/receipt_data.dart';
import '../services/api/api_constants.dart';
import '../services/api/device_service.dart';
import '../services/api/order_service.dart';
import '../services/invoice_html_pdf_service.dart';
import '../services/print_audit_service.dart';
import '../services/printer_role_registry.dart';
import '../services/printer_service.dart';
import '../services/zatca_printer_service.dart';
import '../locator.dart';
import '../widgets/invoice_print_widget.dart';

class InvoiceDetailsDialog extends StatefulWidget {
  final String invoiceId;
  final bool autoOpenRefund;
  final bool autoOpenSingleItemRefund;

  const InvoiceDetailsDialog({
    super.key,
    required this.invoiceId,
    this.autoOpenRefund = false,
    this.autoOpenSingleItemRefund = false,
  });

  @override
  State<InvoiceDetailsDialog> createState() => _InvoiceDetailsDialogState();
}

class _InvoiceDetailsDialogState extends State<InvoiceDetailsDialog> {
  final OrderService _orderService = getIt<OrderService>();
  final PrintAuditService _printAuditService = getIt<PrintAuditService>();
  bool _isLoading = true;
  bool _isSendingWhatsApp = false;
  bool _isProcessingRefund = false;
  bool _isPrintingInvoice = false;
  bool _didAutoOpenRefund = false;
  bool _didAutoOpenSingleItemRefund = false;
  Map<String, dynamic>? _invoiceDetails;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInvoiceDetails();
  }

  Future<void> _sendWhatsAppForInvoice() async {
    if (_invoiceDetails == null) return;
    final payload = _invoiceDetails!['data'] ?? _invoiceDetails!;
    final invoice = payload['invoice'] is Map<String, dynamic>
        ? payload['invoice'] as Map<String, dynamic>
        : payload;

    final orderIdRaw = payload['order_id'] ??
        invoice['order_id'] ??
        payload['booking_id'] ??
        invoice['booking_id'];
    final orderId = orderIdRaw?.toString();
    if (orderId == null || orderId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد رقم طلب مرتبط بهذه الفاتورة')),
      );
      return;
    }

    final controller = TextEditingController(text: 'طلبك جاهز للاستلام');
    final message = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إرسال رسالة واتساب'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'نص الرسالة',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (message == null || message.isEmpty) return;

    setState(() => _isSendingWhatsApp = true);
    try {
      await _orderService.sendOrderWhatsApp(
        orderId: orderId,
        message: message,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إرسال واتساب للطلب #$orderId')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر إرسال الرسالة: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSendingWhatsApp = false);
    }
  }

  Future<void> _loadInvoiceDetails() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      Map<String, dynamic> details;
      try {
        details = await _orderService.getInvoice(widget.invoiceId);
      } catch (e) {
        final errorText = e.toString().toLowerCase();
        final notFound = errorText.contains('route_not_found') ||
            errorText.contains('statuscode: 404') ||
            errorText.contains('status: 404');
        if (!notFound) rethrow;
        details = await _orderService.getInvoiceHelper(widget.invoiceId);
      }
      details = await _mergeRefundedMealsIntoInvoiceDetails(details);



      if (mounted) {
        setState(() {
          _invoiceDetails = details;
          _isLoading = false;
        });
        _maybeAutoOpenRefund();
        _maybeAutoOpenSingleItemRefund();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _mergeRefundedMealsIntoInvoiceDetails(
    Map<String, dynamic> details,
  ) async {
    List<Map<String, dynamic>> refundedMeals;
    try {
      refundedMeals = await _orderService.getRefundedMeals(
        invoiceId: widget.invoiceId,
      );
    } catch (_) {
      return details;
    }

    if (refundedMeals.isEmpty) return details;

    final normalizedDetails = Map<String, dynamic>.from(details);
    final hasWrappedData = _asMap(normalizedDetails['data']) != null;
    final payload = hasWrappedData
        ? Map<String, dynamic>.from(_asMap(normalizedDetails['data'])!)
        : Map<String, dynamic>.from(normalizedDetails);
    final invoice = _asMap(payload['invoice']) != null
        ? Map<String, dynamic>.from(_asMap(payload['invoice'])!)
        : Map<String, dynamic>.from(payload);

    final mergedItems = _orderService.mergeRefundedMealsWithItems(
      _extractItems(invoice, payload),
      refundedMeals,
    );

    if (mergedItems.isNotEmpty) {
      invoice['sales_meals'] = mergedItems;
      invoice['items'] = mergedItems;
      invoice['meals'] = mergedItems;
      payload['sales_meals'] = mergedItems;
      payload['items'] = mergedItems;
      payload['meals'] = mergedItems;
    }

    invoice['refunded_meals'] = refundedMeals;
    payload['refunded_meals'] = refundedMeals;
    if (_asMap(payload['invoice']) != null) {
      payload['invoice'] = invoice;
    }

    if (hasWrappedData) {
      normalizedDetails['data'] = payload;
      return normalizedDetails;
    }
    return payload;
  }

  void _maybeAutoOpenRefund() {
    if (_didAutoOpenRefund || !widget.autoOpenRefund) return;
    _didAutoOpenRefund = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showRefundDialog();
    });
  }

  void _maybeAutoOpenSingleItemRefund() {
    if (_didAutoOpenSingleItemRefund || !widget.autoOpenSingleItemRefund)
      return;
    _didAutoOpenSingleItemRefund = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showSingleItemRefundDialog();
    });
  }

  bool _isInvoicePaidFromDetails() {
    if (_invoiceDetails == null) return false;
    final payload = _asMap(_invoiceDetails!['data']) ?? _invoiceDetails!;
    final data = _asMap(payload['invoice']) ?? payload;

    bool isTruthy(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is num) return value != 0;
      final normalized = value.toString().trim().toLowerCase();
      if (normalized.isEmpty || normalized == 'null') return false;
      return normalized == '1' || normalized == 'true' || normalized == 'yes';
    }

    final normalizedStatus = data['status']?.toString().trim().toLowerCase();
    if (normalizedStatus == 'paid' ||
        normalizedStatus == '2' ||
        normalizedStatus == '7' ||
        normalizedStatus == 'completed') {
      return true;
    }

    final display =
        data['status_display']?.toString().trim().toLowerCase() ?? '';
    if (display.contains('مدفوع') || display.contains('paid')) return true;

    return isTruthy(
      data['is_paid'] ??
          payload['is_paid'] ??
          data['paid'] ??
          payload['paid'] ??
          data['payment_status'] ??
          payload['payment_status'] ??
          data['payment_state'] ??
          payload['payment_state'] ??
          data['pay_status'] ??
          payload['pay_status'] ??
          data['pay_status_id'] ??
          payload['pay_status_id'],
    );
  }

  /// True only when the invoice is completely refunded (status = refunded/4).
  /// A partial refund (has_refund but status ≠ refunded) should NOT block
  /// further refunds.
  bool _isFullyRefundedFromDetails() {
    if (_invoiceDetails == null) return false;
    final payload = _asMap(_invoiceDetails!['data']) ?? _invoiceDetails!;
    final data = _asMap(payload['invoice']) ?? payload;
    final normalizedStatus = data['status']?.toString().trim().toLowerCase();
    final display =
        data['status_display']?.toString().trim().toLowerCase() ?? '';
    if (display.contains('جزئي') || display.contains('partial')) return false;
    if (normalizedStatus == 'refunded') return true;
    if (display == 'مسترجع' || display == 'refunded') return true;
    return false;
  }

  bool _isCancelledFromDetails() {
    if (_invoiceDetails == null) return false;
    final payload = _asMap(_invoiceDetails!['data']) ?? _invoiceDetails!;
    final data = _asMap(payload['invoice']) ?? payload;
    final normalizedStatus = data['status']?.toString().trim().toLowerCase();
    final display =
        data['status_display']?.toString().trim().toLowerCase() ?? '';
    return normalizedStatus == '4' ||
        normalizedStatus == 'cancelled' ||
        normalizedStatus == 'canceled' ||
        display == 'تم الالغاء' ||
        display == 'ملغي';
  }

  bool _hasPartialRefundFromDetails() {
    if (_invoiceDetails == null) return false;
    final payload = _asMap(_invoiceDetails!['data']) ?? _invoiceDetails!;
    final data = _asMap(payload['invoice']) ?? payload;
    bool isTruthy(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is num) return value != 0;
      final s = value.toString().trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes';
    }

    final hasRefundEvidence = isTruthy(
      data['has_refund'] ??
          payload['has_refund'] ??
          data['refund_id'] ??
          payload['refund_id'],
    );

    // Cancelled + no refund evidence = genuine cancel, not partial refund
    if (_isCancelledFromDetails()) {
      return hasRefundEvidence;
    }

    return hasRefundEvidence;
  }

  String _resolvePaymentMethodLabel(
    Map<String, dynamic> data,
    Map<String, dynamic> payload,
  ) {
    String normalizeLabel(String? method) {
      final normalized = method?.trim().toLowerCase() ?? '';
      if (normalized.isEmpty || normalized == 'null') return '';
      switch (normalized) {
        case 'cash':
        case 'نقدي':
        case 'كاش':
          return 'نقدي';
        case 'card':
        case 'mada':
        case 'visa':
        case 'benefit':
        case 'benefit_pay':
        case 'benefit pay':
        case 'بطاقة':
        case 'مدى':
        case 'فيزا':
        case 'ماستر':
        case 'ماستر كارد':
        case 'بينيفت':
        case 'بينيفت باي':
          return 'بطاقة';
        case 'stc':
        case 'stc_pay':
        case 'stc pay':
        case 'اس تي سي':
        case 'اس تي سي باي':
          return 'STC Pay';
        case 'bank_transfer':
        case 'bank':
        case 'bank transfer':
        case 'تحويل بنكي':
        case 'تحويل بنكى':
          return 'تحويل بنكي';
        case 'wallet':
        case 'المحفظة':
        case 'المحفظة الالكترونية':
        case 'المحفظة الإلكترونية':
          return 'محفظة';
        case 'cheque':
        case 'check':
        case 'شيك':
          return 'شيك';
        case 'petty_cash':
        case 'petty cash':
        case 'بيتي كاش':
          return 'بيتي كاش';
        case 'pay_later':
        case 'postpaid':
        case 'deferred':
        case 'pay later':
        case 'الدفع بالآجل':
        case 'الدفع بالاجل':
          return 'الدفع بالآجل';
        case 'tabby':
        case 'تابي':
          return 'تابي';
        case 'tamara':
        case 'تمارا':
          return 'تمارا';
        case 'keeta':
        case 'كيتا':
          return 'كيتا';
        case 'my_fatoorah':
        case 'myfatoorah':
        case 'my fatoorah':
        case 'ماي فاتورة':
        case 'ماي فاتوره':
          return 'ماي فاتورة';
        case 'jahez':
        case 'جاهز':
          return 'جاهز';
        case 'talabat':
        case 'طلبات':
          return 'طلبات';
        default:
          return method?.trim() ?? '';
      }
    }

    final pays = data['pays'] ?? payload['pays'];
    if (pays is List) {
      final labels = <String>{};
      for (final pay in pays.whereType<Map>()) {
        final map = pay.map((k, v) => MapEntry(k.toString(), v));
        final label = normalizeLabel(
          map['pay_method']?.toString() ??
              map['payment_method']?.toString() ??
              map['method']?.toString() ??
              map['name']?.toString(),
        );
        if (label.isNotEmpty) labels.add(label);
      }
      if (labels.isNotEmpty) return labels.join(' + ');
    }

    final direct = normalizeLabel(
      data['payment_methods']?.toString() ??
          data['pay_method']?.toString() ??
          data['payment_method']?.toString() ??
          data['name']?.toString() ??
          payload['payment_methods']?.toString() ??
          payload['pay_method']?.toString() ??
          payload['payment_method']?.toString() ??
          payload['name']?.toString(),
    );
    if (direct.isNotEmpty) return direct;

    final fallback = normalizeLabel(pays?.toString());
    if (fallback.isNotEmpty) return fallback;

    return 'غير محدد';
  }

  List<Map<String, dynamic>> _extractPaysList(
    Map<String, dynamic> data,
    Map<String, dynamic> payload,
  ) {
    final pays = data['pays'] ?? payload['pays'];
    if (pays is! List) return const <Map<String, dynamic>>[];
    return pays
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  String? _dominantPayMethodFromPays(List<Map<String, dynamic>> pays) {
    double bestAmount = -1;
    String? bestMethod;
    for (final pay in pays) {
      final amount = _parsePrice(
        pay['amount'] ?? pay['paid'] ?? pay['value'] ?? pay['total'],
      );
      if (amount <= 0) continue;
      if (amount > bestAmount) {
        bestAmount = amount;
        bestMethod = pay['pay_method']?.toString() ?? pay['method']?.toString();
      }
    }
    return bestMethod;
  }

  String? _mapPayMethodToRefundOption(String? method) {
    final normalized = method?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty || normalized == 'null') return null;
    switch (normalized) {
      case 'cash':
        return 'cash';
      case 'card':
      case 'mada':
      case 'visa':
      case 'benefit':
      case 'benefit_pay':
        return 'card';
      case 'stc':
      case 'stc_pay':
      case 'bank_transfer':
      case 'bank':
      case 'wallet':
      case 'cheque':
      case 'check':
      case 'petty_cash':
      case 'pay_later':
      case 'postpaid':
      case 'deferred':
      case 'tabby':
      case 'tamara':
      case 'keeta':
      case 'my_fatoorah':
      case 'myfatoorah':
      case 'jahez':
      case 'talabat':
      case 'other':
        return 'other';
      default:
        return 'other';
    }
  }

  String _resolveInitialRefundMethod({
    required Map<String, dynamic> data,
    required Map<String, dynamic> payload,
    required List<String> options,
  }) {
    String? candidate;

    final pays = _extractPaysList(data, payload);
    final dominantPayMethod = _dominantPayMethodFromPays(pays);
    candidate = _mapPayMethodToRefundOption(dominantPayMethod);

    if (candidate == null || !options.contains(candidate)) {
      final directMethod = data['pay_method']?.toString() ??
          data['payment_method']?.toString() ??
          payload['pay_method']?.toString() ??
          payload['payment_method']?.toString();
      candidate = _mapPayMethodToRefundOption(directMethod);
    }

    if (candidate != null && options.contains(candidate)) {
      return candidate;
    }

    return options.isNotEmpty ? options.first : 'cash';
  }

  Future<void> _showRefundOptions() async {
    if (_invoiceDetails == null || _isProcessingRefund) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('خيارات الاسترجاع'),
        content: const Text('هل تريد استرجاع الفاتورة كاملة أم عناصر محددة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'partial'),
            child: const Text('استرجاع عناصر'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'full'),
            child: const Text('استرجاع كامل'),
          ),
        ],
      ),
    );
    if (choice == 'full') {
      await _showRefundDialog();
    } else if (choice == 'partial') {
      await _showSingleItemRefundDialog();
    }
  }

  Future<void> _showRefundDialog() async {
    if (_invoiceDetails == null || _isProcessingRefund) return;

    final payload = _asMap(_invoiceDetails!['data']) ?? _invoiceDetails!;
    final data = _asMap(payload['invoice']) ?? payload;

    final refundMethodOptions = const ['cash', 'card', 'other'];
    final originalPaymentMethod = _resolvePaymentMethodLabel(data, payload);

    Map<String, dynamic> preview;
    try {
      preview = await _orderService.showInvoiceRefund(widget.invoiceId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر جلب بيانات الاسترجاع: $e')),
      );
      return;
    }

    final previewPayload = _asMap(preview['data']) ?? _asMap(preview) ?? {};
    final previewInvoice = _asMap(previewPayload['invoice']) ??
        _asMap(previewPayload['data']) ??
        previewPayload;
    final refundStatus = (previewInvoice['refund_status'] ??
            previewInvoice['status_display'] ??
            previewInvoice['status'] ??
            previewPayload['refund_status'])
        ?.toString()
        .trim();
    final refundAmount = _parsePrice(
      previewInvoice['refund_total'] ??
          previewInvoice['refund_amount'] ??
          previewInvoice['amount'] ??
          previewInvoice['total'] ??
          previewPayload['refund_total'] ??
          previewPayload['refund_amount'] ??
          previewPayload['amount'] ??
          previewPayload['total'],
    );

    String selectedRefundMethod = _resolveInitialRefundMethod(
      data: data,
      payload: payload,
      options: refundMethodOptions,
    );

    final refundMethod = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('استرجاع الفاتورة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'طريقة الدفع الأصلية',
                  border: OutlineInputBorder(),
                ),
                child: Text(originalPaymentMethod),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRefundMethod,
                decoration: const InputDecoration(
                  labelText: 'طريقة الاسترجاع (Refund method)',
                  border: OutlineInputBorder(),
                ),
                items: refundMethodOptions.map((method) {
                  switch (method) {
                    case 'cash':
                      return const DropdownMenuItem(
                          value: 'cash', child: Text('نقدي'));
                    case 'card':
                      return const DropdownMenuItem(
                          value: 'card', child: Text('بطاقة'));
                    default:
                      return const DropdownMenuItem(
                          value: 'other', child: Text('أخرى'));
                  }
                }).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() => selectedRefundMethod = value);
                },
              ),
              const SizedBox(height: 12),
              Text(
                'المبلغ المتوقع للاسترجاع: ${refundAmount.toStringAsFixed(2)} ${ApiConstants.currency}',
              ),
              if (refundStatus != null && refundStatus.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('الحالة الحالية: $refundStatus'),
              ],
              const SizedBox(height: 12),
              const Text(
                'سيتم تنفيذ عملية الاسترجاع عبر السيرفر الآن.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, selectedRefundMethod),
              child: const Text('تنفيذ الاسترجاع'),
            ),
          ],
        ),
      ),
    );

    if (refundMethod == null || refundMethod.isEmpty) return;

    setState(() => _isProcessingRefund = true);
    try {
      final result = await _orderService.processInvoiceRefund(
        invoiceId: widget.invoiceId,
        payload: {
          'refund_reason': 'طلب العميل',
          'refund_method': refundMethod,
        },
      );

      if (!mounted) return;
      final serverMessage = result['message']?.toString().trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (serverMessage != null && serverMessage.isNotEmpty)
                ? serverMessage
                : 'تم تنفيذ الاسترجاع بنجاح',
          ),
          backgroundColor: const Color(0xFF10B981),
        ),
      );

      // Print credit note (فاتورة دائن)
      _printCreditNoteForInvoice(widget.invoiceId);

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تنفيذ الاسترجاع: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessingRefund = false);
    }
  }

  Future<void> _printCreditNoteForInvoice(String invoiceId) async {
    try {
      // Fetch invoice details for credit note data
      final invoiceResponse = await _orderService.getInvoice(invoiceId);
      final rawEnvelope = invoiceResponse.map((k, v) => MapEntry(k.toString(), v));
      final envelope = (rawEnvelope['data'] is Map)
          ? (rawEnvelope['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : rawEnvelope;

      final invoice = (envelope['invoice'] is Map)
          ? (envelope['invoice'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : envelope;
      final branch = (envelope['branch'] is Map)
          ? (envelope['branch'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
      final seller = (branch['seller'] is Map)
          ? (branch['seller'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};

      String pick(List<dynamic> candidates) {
        for (final c in candidates) {
          final t = c?.toString().trim();
          if (t != null && t.isNotEmpty && t.toLowerCase() != 'null') return t;
        }
        return '';
      }

      final items = (invoice['items'] as List?)?.map((item) {
        final m = item is Map ? item.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
        final name = m['item_name']?.toString() ?? '';
        String arName = name;
        String enName = name;
        if (name.contains(' - ')) {
          arName = name.split(' - ').first.trim();
          enName = name.split(' - ').last.trim();
        }
        final price = double.tryParse(m['meal_price']?.toString() ?? '') ??
            double.tryParse(m['total']?.toString() ?? '') ?? 0;
        return ReceiptItem(
          nameAr: arName,
          nameEn: enName,
          quantity: double.tryParse(m['quantity']?.toString() ?? '') ?? 1,
          unitPrice: price,
          total: price,
        );
      }).toList() ?? [];

      final totalStr = invoice['total']?.toString() ?? '0';
      final taxStr = invoice['tax']?.toString() ?? '0';
      final grandStr = invoice['grand_total']?.toString() ?? totalStr;
      final totalExcl = double.tryParse(totalStr) ?? 0;
      final tax = double.tryParse(taxStr) ?? 0;
      final grandTotal = double.tryParse(grandStr) ?? (totalExcl + tax);

      // Build credit note receipt — same as normal but with "فاتورة دائن" title
      final receiptData = OrderReceiptData(
        invoiceNumber: pick([invoice['invoice_number']]),
        issueDateTime: pick([invoice['ISO8601'], invoice['date']]),
        sellerNameAr: pick([branch['seller_name']]).split('|').first.trim(),
        sellerNameEn: pick([branch['seller_name']]).contains('|')
            ? pick([branch['seller_name']]).split('|').last.trim()
            : pick([branch['seller_name']]),
        vatNumber: pick([seller['tax_number'], branch['tax_number']]),
        branchName: pick([branch['seller_name']]),
        items: items,
        totalExclVat: totalExcl,
        vatAmount: tax,
        totalInclVat: grandTotal,
        paymentMethod: pick([invoice['payment_methods']]),
        qrCodeBase64: pick([envelope['qr_image'], invoice['qr_image']]),
        branchAddress: pick([branch['address'], branch['district']]),
        branchMobile: pick([branch['mobile']]),
        commercialRegisterNumber: pick([seller['commercial_register']]),
        cashierName: pick([(invoice['cashier'] is Map ? (invoice['cashier'] as Map)['fullname'] : null)]),
        issueDate: pick([invoice['date']]),
        issueTime: pick([invoice['time']]),
      );

      // Print via ESC/POS to cashier printers only
      final devices = await getIt<DeviceService>().getDevices();
      final printers = devices.where(_isPhysicalPrinter).toList(growable: false);
      if (printers.isEmpty) return;

      final cashierPrinters = await _resolvePrintersForRole(
        role: PrinterRole.cashierReceipt,
        printers: printers,
      );
      if (cashierPrinters.isEmpty) return;

      final printerService = getIt<PrinterService>();
      for (final printer in cashierPrinters) {
        try {
          await printerService.printReceipt(
            printer,
            receiptData,
            jobType: 'credit_note',
            isCreditNote: true,
          );
        } catch (e) {
          debugPrint('Credit note ESC/POS print failed: $e');
        }
      }
    } catch (e) {
      debugPrint('Credit note print failed: $e');
    }
  }

  Future<void> _showSingleItemRefundDialog() async {
    if (_invoiceDetails == null || _isProcessingRefund) return;

    final payload = _asMap(_invoiceDetails!['data']) ?? _invoiceDetails!;
    final data = _asMap(payload['invoice']) ?? payload;

    final refundMethodOptions = const ['cash', 'card', 'other'];
    final originalPaymentMethod = _resolvePaymentMethodLabel(data, payload);

    Map<String, dynamic> preview;
    try {
      preview = await _orderService.showInvoiceRefund(widget.invoiceId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر جلب بيانات الاسترجاع: $e')),
      );
      return;
    }

    final previewPayload = _asMap(preview['data']) ?? _asMap(preview) ?? {};
    // DEBUG: print raw API response keys to console
    debugPrint('=== REFUND PREVIEW KEYS: ${preview.keys.toList()}');
    debugPrint('=== REFUND PREVIEW DATA: $preview');
    debugPrint('=== PREVIEW PAYLOAD KEYS: ${previewPayload.keys.toList()}');
    debugPrint('=== INVOICE DATA KEYS: ${data.keys.toList()}');
    debugPrint('=== PAYLOAD KEYS: ${payload.keys.toList()}');
    final candidates = _extractRefundCandidates(data, payload, previewPayload);
    debugPrint('=== CANDIDATES COUNT: ${candidates.length}');
    if (candidates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد عناصر متاحة للاسترجاع')),
      );
      return;
    }

    String selectedRefundMethod = _resolveInitialRefundMethod(
      data: data,
      payload: payload,
      options: refundMethodOptions,
    );
    final selectedItems = <_RefundCandidate>{};

    final selection = await showDialog<_RefundSelection>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('استرجاع عناصر'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'طريقة الدفع الأصلية',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(originalPaymentMethod),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRefundMethod,
                    decoration: const InputDecoration(
                      labelText: 'طريقة الاسترجاع (Refund method)',
                      border: OutlineInputBorder(),
                    ),
                    items: refundMethodOptions.map((method) {
                      switch (method) {
                        case 'cash':
                          return const DropdownMenuItem(
                              value: 'cash', child: Text('نقدي'));
                        case 'card':
                          return const DropdownMenuItem(
                              value: 'card', child: Text('بطاقة'));
                        default:
                          return const DropdownMenuItem(
                              value: 'other', child: Text('أخرى'));
                      }
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => selectedRefundMethod = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'اختر العناصر المراد استرجاعها:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ...candidates.map((candidate) {
                    final isSelected = selectedItems.contains(candidate);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFFF7ED)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFF58220)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: CheckboxListTile(
                        value: isSelected,
                        onChanged: (checked) {
                          setDialogState(() {
                            if (checked == true) {
                              selectedItems.add(candidate);
                            } else {
                              selectedItems.remove(candidate);
                            }
                          });
                        },
                        title: Text(candidate.name),
                        subtitle:
                            Text(_formatRefundCandidateSubtitle(candidate)),
                        activeColor: const Color(0xFFF58220),
                        checkColor: Colors.white,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  if (selectedItems.isNotEmpty)
                    Text(
                      'المبلغ المتوقع للاسترجاع: '
                      '${_formatRefundAmount(selectedItems.fold(0.0, (sum, c) => sum + c.total))} ${ApiConstants.currency}',
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: selectedItems.isEmpty
                  ? null
                  : () => Navigator.pop(
                        context,
                        _RefundSelection(
                          candidates: selectedItems.toList(),
                          method: selectedRefundMethod,
                        ),
                      ),
              child: const Text('تنفيذ الاسترجاع'),
            ),
          ],
        ),
      ),
    );

    if (selection == null) return;

    setState(() => _isProcessingRefund = true);
    try {
      final payload = <String, dynamic>{
        'refund_reason': 'طلب العميل',
        'refund_method': selection.method,
      };
      final mealIds = selection.candidates
          .where((c) => c.type == _RefundCandidateType.meal)
          .map((c) => c.id)
          .toList();
      final productIds = selection.candidates
          .where((c) => c.type == _RefundCandidateType.product)
          .map((c) => c.id)
          .toList();
      final unknownIds = selection.candidates
          .where((c) => c.type == _RefundCandidateType.unknown)
          .map((c) => c.id)
          .toList();
      if (mealIds.isNotEmpty) payload['refund_meals'] = mealIds;
      if (productIds.isNotEmpty) payload['refund_products'] = productIds;
      if (unknownIds.isNotEmpty) payload['refund_items'] = unknownIds;

      final result = await _orderService.processInvoiceRefund(
        invoiceId: widget.invoiceId,
        payload: payload,
      );

      if (!mounted) return;
      final serverMessage = result['message']?.toString().trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (serverMessage != null && serverMessage.isNotEmpty)
                ? serverMessage
                : 'تم تنفيذ الاسترجاع بنجاح',
          ),
          backgroundColor: const Color(0xFF10B981),
        ),
      );

      // Print credit note (فاتورة دائن) with refunded items
      _printCreditNoteWithItems(
        widget.invoiceId,
        selection.candidates,
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر تنفيذ الاسترجاع: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessingRefund = false);
    }
  }

  Future<void> _printCreditNoteWithItems(
    String invoiceId,
    List<_RefundCandidate> refundedItems,
  ) async {
    try {
      final invoiceHtmlPdfService = getIt<InvoiceHtmlPdfService>();
      final refundTotal = refundedItems.fold(0.0, (sum, c) => sum + c.total);

      final itemMaps = refundedItems
          .map((c) => <String, dynamic>{
                'name': c.name,
                'quantity': c.quantity,
                'total': c.total,
                'unit_price': c.quantity > 0 ? c.total / c.quantity : c.total,
              })
          .toList();

      final pdfPath = await invoiceHtmlPdfService.generateCreditNotePdf(
        invoiceId,
        refundedItems: itemMaps,
        refundTotal: refundTotal,
      );

      final pdfFile = File(pdfPath);
      if (!await pdfFile.exists()) return;
      final pdfBytes = await pdfFile.readAsBytes();

      final devices = await getIt<DeviceService>().getDevices();
      final printers =
          devices.where(_isPhysicalPrinter).toList(growable: false);
      if (printers.isEmpty) return;

      final cashierPrinters = await _resolvePrintersForRole(
        role: PrinterRole.cashierReceipt,
        printers: printers,
      );
      final targetPrinters =
          cashierPrinters.isNotEmpty ? cashierPrinters : printers;

      for (final printer in targetPrinters) {
        try {
          await ZatcaPrinterService().printPdfBytes(printer, pdfBytes);
          printAuditService.logAttempt(
            printerIp: printer.connectionType == PrinterConnectionType.bluetooth
                ? (printer.bluetoothAddress ?? 'BT')
                : printer.ip,
            jobType: 'credit_note',
            success: true,
          );
        } catch (e) {
          printAuditService.logAttempt(
            printerIp: printer.connectionType == PrinterConnectionType.bluetooth
                ? (printer.bluetoothAddress ?? 'BT')
                : printer.ip,
            jobType: 'credit_note',
            success: false,
            error: e.toString(),
          );
        }
      }
    } catch (e) {
      debugPrint('Credit note print failed: $e');
    }
  }

  bool _isPhysicalPrinter(DeviceConfig device) {
    final normalized = device.type.trim().toLowerCase();
    if (device.id.startsWith('kitchen:')) return false;
    return normalized == 'printer';
  }

  Future<List<DeviceConfig>> _resolvePrintersForRole({
    required PrinterRole role,
    required List<DeviceConfig> printers,
  }) async {
    final registry = getIt<PrinterRoleRegistry>();
    await registry.initialize();

    final physical = printers.where(_isPhysicalPrinter).toList(growable: false);
    if (physical.isEmpty) return const <DeviceConfig>[];

    final matches = physical
        .where((printer) => registry.resolveRole(printer) == role)
        .toList(growable: false);
    if (matches.isNotEmpty) {
      matches.sort((a, b) => a.name.compareTo(b.name));
      return matches;
    }

    final nonKitchen = physical.where((printer) {
      final resolved = registry.resolveRole(printer);
      return resolved != PrinterRole.kitchen &&
          resolved != PrinterRole.kds &&
          resolved != PrinterRole.bar;
    }).toList(growable: false);
    if (nonKitchen.isNotEmpty) {
      nonKitchen.sort((a, b) => a.name.compareTo(b.name));
      return nonKitchen;
    }

    physical.sort((a, b) => a.name.compareTo(b.name));
    return physical;
  }

  Future<bool> _printReceiptToPrinters({
    required List<DeviceConfig> printers,
    required OrderReceiptData receiptData,
    String? invoiceId,
    required String jobType,
  }) async {
    if (printers.isEmpty) return false;

    final results = await Future.wait(printers.map((printer) async {
      return await _printReceiptToPrinter(
        printer: printer,
        receiptData: receiptData,
        jobType: jobType,
      );
    }));

    return results.any((s) => s);
  }

  Future<bool> _printReceiptToPrinter({
    required DeviceConfig printer,
    required OrderReceiptData receiptData,
    required String jobType,
  }) async {
    try {
      final printerService = getIt<PrinterService>();
      await printerService.printReceipt(
        printer,
        receiptData,
        jobType: jobType,
      );

      _printAuditService.logAttempt(
        printerIp: printer.connectionType == PrinterConnectionType.bluetooth
            ? (printer.bluetoothAddress ?? 'BT')
            : printer.ip,
        jobType: jobType,
        success: true,
      );
      return true;
    } catch (e) {
      _printAuditService.logAttempt(
        printerIp: printer.connectionType == PrinterConnectionType.bluetooth
            ? (printer.bluetoothAddress ?? 'BT')
            : printer.ip,
        jobType: jobType,
        success: false,
        error: e.toString(),
      );
      return false;
    }
  }

  void _showPrintSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _printThisInvoice() async {
    if (_invoiceDetails == null || _isPrintingInvoice) return;

    final payload = _asMap(_invoiceDetails!['data']) ?? _invoiceDetails!;
    final data = _asMap(payload['invoice']) ?? payload;
    final receiptData = _mapToOrderReceiptData(payload, data);

    setState(() => _isPrintingInvoice = true);
    try {
      final devices = await getIt<DeviceService>().getDevices();
      final printers =
          devices.where(_isPhysicalPrinter).toList(growable: false);
      if (printers.isEmpty) {
        _showPrintSnackBar('⚠️ يجب ربط طابعة لطباعة الفواتير', Colors.orange);
        return;
      }

      final cashierPrinters = await _resolvePrintersForRole(
        role: PrinterRole.cashierReceipt,
        printers: printers,
      );

      final success = await _printReceiptToPrinters(
        printers: cashierPrinters,
        receiptData: receiptData,
        invoiceId: widget.invoiceId,
        jobType: 'invoice_details_direct',
      );

      if (success) {
        _showPrintSnackBar('✅ تم إرسال الطباعة بنجاح', Colors.green);
      } else {
        _showPrintSnackBar(
          'تعذر الطباعة — تحقق من اتصال الطابعة',
          Colors.orange,
        );
      }
    } catch (e) {
      _showPrintSnackBar('حدث خطأ: $e', Colors.orange);
    } finally {
      if (mounted) setState(() => _isPrintingInvoice = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat('#,##0.00', 'ar');
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 700;
    final insetPadding = EdgeInsets.symmetric(
      horizontal: isCompact ? 12 : 24,
      vertical: isCompact ? 16 : 24,
    );
    final dialogWidth =
        (size.width - insetPadding.horizontal).clamp(280.0, 700.0).toDouble();
    final dialogHeight =
        (size.height - insetPadding.vertical).clamp(460.0, 760.0).toDouble();
    final canRefund = _invoiceDetails != null &&
        (_isInvoicePaidFromDetails() || _hasPartialRefundFromDetails()) &&
        !_isFullyRefundedFromDetails();

    return Dialog(
      insetPadding: insetPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(isCompact ? 14 : 20),
              decoration: const BoxDecoration(
                color: Color(0xFFF58220),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تفاصيل الفاتورة',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (_invoiceDetails != null)
                          Text(
                            'رقم الفاتورة: #${widget.invoiceId}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildErrorView()
                      : _buildInvoiceContent(formatter),
            ),
            Container(
              padding: EdgeInsets.all(isCompact ? 14 : 20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: isCompact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (canRefund) ...[
                            OutlinedButton.icon(
                              onPressed: _isProcessingRefund
                                  ? null
                                  : _showRefundOptions,
                              icon: _isProcessingRefund
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(LucideIcons.refreshCw, size: 18),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                foregroundColor: const Color(0xFFEF4444),
                                side:
                                    const BorderSide(color: Color(0xFFEF4444)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              label: Text(_isProcessingRefund
                                  ? 'جارٍ الاسترجاع...'
                                  : 'استرجاع'),
                            ),
                            const SizedBox(height: 8),
                          ],
                          OutlinedButton.icon(
                            onPressed:
                                _isPrintingInvoice ? null : _printThisInvoice,
                            icon: _isPrintingInvoice
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(LucideIcons.printer, size: 18),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              foregroundColor: const Color(0xFFF58220),
                              side: const BorderSide(color: Color(0xFFF58220)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            label: Text(_isPrintingInvoice
                                ? 'جارٍ الطباعة...'
                                : 'طباعة الفاتورة'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _isSendingWhatsApp
                                ? null
                                : _sendWhatsAppForInvoice,
                            icon: _isSendingWhatsApp
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(LucideIcons.messageCircle,
                                    size: 18),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              foregroundColor: const Color(0xFF16A34A),
                              side: const BorderSide(color: Color(0xFF16A34A)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            label: Text(_isSendingWhatsApp
                                ? 'جارٍ الإرسال...'
                                : 'إرسال واتساب'),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              backgroundColor: const Color(0xFFF58220),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'إغلاق',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          if (canRefund) ...[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _isProcessingRefund
                                    ? null
                                    : _showRefundOptions,
                                icon: _isProcessingRefund
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(LucideIcons.refreshCw,
                                        size: 18),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                  foregroundColor: const Color(0xFFEF4444),
                                  side: const BorderSide(
                                      color: Color(0xFFEF4444)),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                label: Text(_isProcessingRefund
                                    ? 'جارٍ الاسترجاع...'
                                    : 'استرجاع'),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  _isPrintingInvoice ? null : _printThisInvoice,
                              icon: _isPrintingInvoice
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(LucideIcons.printer, size: 18),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                foregroundColor: const Color(0xFFF58220),
                                side:
                                    const BorderSide(color: Color(0xFFF58220)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              label: Text(_isPrintingInvoice
                                  ? 'جارٍ الطباعة...'
                                  : 'طباعة الفاتورة'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isSendingWhatsApp
                                  ? null
                                  : _sendWhatsAppForInvoice,
                              icon: _isSendingWhatsApp
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(LucideIcons.messageCircle,
                                      size: 18),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                foregroundColor: const Color(0xFF16A34A),
                                side:
                                    const BorderSide(color: Color(0xFF16A34A)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              label: Text(_isSendingWhatsApp
                                  ? 'جارٍ الإرسال...'
                                  : 'إرسال واتساب'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                backgroundColor: const Color(0xFFF58220),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'إغلاق',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(LucideIcons.alertCircle, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text('حدث خطأ: $_error', style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadInvoiceDetails,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceContent(NumberFormat formatter) {
    if (_invoiceDetails == null) {
      return const Center(child: Text('لا توجد بيانات'));
    }

    final payload = _asMap(_invoiceDetails!['data']) ?? _invoiceDetails!;
    final data = _asMap(payload['invoice']) ?? payload;
    
    final receiptData = _mapToOrderReceiptData(payload, data);

    return Container(
      color: const Color(0xFFF1F5F9), // خلفية رمادية فاتحة لبروز "الورقة"
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Ribbon or Indicator for Refunded state
                if (_isFullyRefundedFromDetails())
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                    child: const Text(
                      'مسترجع بالكامل - FULLY REFUNDED',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                else if (_hasPartialRefundFromDetails())
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF59E0B),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                    child: const Text(
                      'استرجاع جزئي - PARTIAL REFUND',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                
                InvoicePrintWidget(
                  data: receiptData,
                  paperWidthMm: 80, // High clarity for preview
                ),
                
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<ReceiptPayment> _resolvePaymentsList(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final paysRaw = data['pays'] ?? payload['pays'];
    final pays = paysRaw is List ? paysRaw : const [];
    final payments = <ReceiptPayment>[];
    for (final pay in pays) {
      final map = _asMap(pay);
      if (map == null) continue;
      final method = (map['pay_method'] ?? map['method'] ?? map['name'])
          ?.toString()
          .trim()
          .toLowerCase();
      final numericAmount = _parsePrice(map['amount'] ?? map['value'] ?? map['paid'] ?? map['total']);
      if (method == null || method.isEmpty) continue;

      String label = 'دفع';
      switch (method) {
        case 'cash':
        case 'نقدي':
        case 'كاش':
          label = 'نقدي';
          break;
        case 'card':
        case 'mada':
        case 'visa':
        case 'benefit':
        case 'benefit_pay':
        case 'بطاقة':
        case 'مدى':
        case 'فيزا':
        case 'ماستر':
        case 'بينيفت':
          label = 'بطاقة';
          break;
        case 'stc':
        case 'stc_pay':
        case 'اس تي سي':
          label = 'STC Pay';
          break;
        case 'bank_transfer':
        case 'bank':
        case 'تحويل بنكي':
          label = 'تحويل بنكي';
          break;
        case 'wallet':
        case 'المحفظة':
          label = 'محفظة';
          break;
        case 'cheque':
        case 'check':
        case 'شيك':
          label = 'شيك';
          break;
        case 'petty_cash':
        case 'بيتي كاش':
          label = 'بيتي كاش';
          break;
        case 'pay_later':
        case 'postpaid':
        case 'deferred':
        case 'الدفع بالآجل':
          label = 'الدفع بالآجل';
          break;
        case 'tabby':
        case 'تابي':
          label = 'تابي';
          break;
        case 'tamara':
        case 'تمارا':
          label = 'تمارا';
          break;
        case 'keeta':
        case 'كيتا':
          label = 'كيتا';
          break;
        case 'my_fatoorah':
        case 'myfatoorah':
        case 'ماي فاتورة':
          label = 'ماي فاتورة';
          break;
        case 'jahez':
        case 'جاهز':
          label = 'جاهز';
          break;
        case 'talabat':
        case 'طلبات':
          label = 'طلبات';
          break;
        default:
          label = method;
      }
      payments.add(ReceiptPayment(methodLabel: label, amount: numericAmount));
    }
    return payments;
  }

  OrderReceiptData _mapToOrderReceiptData(
      Map<String, dynamic> payload, Map<String, dynamic> data) {
    final items = _extractItems(data, payload);
    
    final receiptItems = items.map((item) {
      final meal = _asMap(item['meal']) ?? const <String, dynamic>{};
      
      return ReceiptItem(
        nameAr: item['meal_name']?.toString() ?? item['name']?.toString() ?? meal['name']?.toString() ?? '',
        nameEn: item['meal_name_en']?.toString() ?? meal['name_en']?.toString() ?? '',
        quantity: _parsePrice(item['quantity']),
        unitPrice: _parsePrice(item['unit_price'] ?? item['price']),
        total: _parsePrice(item['total'] ?? item['amount']),
        addons: (item['addons'] as List? ?? []).map((a) {
          final addonMap = _asMap(a)!;
          return ReceiptAddon(
            nameAr: addonMap['name_ar']?.toString() ?? addonMap['name']?.toString() ?? '',
            nameEn: addonMap['name_en']?.toString() ?? '',
            price: _parsePrice(addonMap['price']),
          );
        }).toList(),
        discountAmount: _parsePrice(item['discount_amount'] ?? item['discount']),
        discountPercentage: _parsePrice(item['discount_percentage']),
        discountName: item['discount_name']?.toString(),
      );
    }).toList();

    final issueDateTime = data['date']?.toString() ??
        data['created_at']?.toString() ??
        payload['date']?.toString() ??
        payload['created_at']?.toString() ??
        '';

    return OrderReceiptData(
      invoiceNumber: (data['invoice_number']?.toString() ?? widget.invoiceId).replaceAll('#', '').trim(),
      issueDateTime: issueDateTime,
      sellerNameAr: _extractSellerName(data, payload) ?? 'هيرموسا',
      sellerNameEn: _extractSellerNameEn(data, payload) ?? 'Hermosa',
      vatNumber: _extractVatNumber(data, payload) ?? '',
      branchName: data['branch_name']?.toString() ?? payload['branch_name']?.toString() ?? '',
      items: receiptItems,
      totalExclVat: _parsePrice(data['total'] ?? payload['total']),
      vatAmount: _parsePrice(data['tax'] ?? data['vat'] ?? payload['tax']),
      totalInclVat: _parsePrice(data['grand_total'] ?? data['final_total'] ?? payload['grand_total']),
      paymentMethod: _resolvePaymentMethodLabel(data, payload),
      payments: _resolvePaymentsList(data, payload),
      qrCodeBase64: data['zatca_qr']?.toString() ?? payload['zatca_qr']?.toString() ?? '',
      sellerLogo: _extractLogoUrl(data, payload),
      branchAddress: _extractBranchAddress(data, payload),
      branchMobile: _extractBranchMobile(data, payload),
      cashierName: data['cashier_name']?.toString() ?? payload['cashier_name']?.toString(),
      orderType: data['order_type']?.toString() ?? payload['order_type']?.toString(),
      orderNumber: data['order_number']?.toString() ?? payload['order_number']?.toString() ?? data['booking_id']?.toString(),
      clientName: _extractCustomerName(data, payload),
      clientPhone: _extractCustomerPhone(data, payload),
      tableNumber: _extractTableNumber(data, payload),
      carNumber: data['car_number']?.toString() ?? payload['car_number']?.toString() ?? _asMap(data['type_extra'])?['car_number']?.toString() ?? '',
      commercialRegisterNumber: _extractCommercialRegister(data, payload),
    );
  }

  String? _extractCustomerName(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final direct = node['customer_name']?.toString().trim() ?? 
                    node['client_name']?.toString().trim() ??
                    node['client']?.toString().trim();
      if (direct != null && direct.isNotEmpty && direct != 'null') return direct;
      
      final customer = _asMap(node['customer']) ?? _asMap(node['client']);
      if (customer != null) {
        final name = customer['name']?.toString().trim();
        if (name != null && name.isNotEmpty) return name;
      }
    }
    return null;
  }

  String? _extractCustomerPhone(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final direct = node['customer_phone']?.toString().trim() ?? 
                    node['client_phone']?.toString().trim() ??
                    node['phone']?.toString().trim();
      if (direct != null && direct.isNotEmpty && direct != 'null') return direct;

      final customer = _asMap(node['customer']) ?? _asMap(node['client']);
      if (customer != null) {
        final phone = customer['phone']?.toString().trim() ?? 
                     customer['mobile']?.toString().trim() ??
                     customer['phone_number']?.toString().trim();
        if (phone != null && phone.isNotEmpty) return phone;
      }
    }
    return null;
  }

  String? _extractSellerName(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final branch = _asMap(node['branch']);
      final seller = _asMap(node['seller']) ?? _asMap(branch?['seller']);
      
      final candidates = [
        node['seller_name'],
        node['name'],
        branch?['seller_name'],
        branch?['name'],
        seller?['seller_name'],
        seller?['name'],
      ];
      
      for (final c in candidates) {
        final val = c?.toString().trim();
        if (val != null && val.isNotEmpty && val.toLowerCase() != 'null') return val;
      }
    }
    return null;
  }

  String? _extractSellerNameEn(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final branch = _asMap(node['branch']);
      final seller = _asMap(node['seller']) ?? _asMap(branch?['seller']);
      
      final candidates = [
        node['seller_name_en'],
        node['name_en'],
        branch?['seller_name_en'],
        branch?['name_en'],
        seller?['seller_name_en'],
        seller?['name_en'],
      ];
      
      for (final c in candidates) {
        final val = c?.toString().trim();
        if (val != null && val.isNotEmpty && val.toLowerCase() != 'null') return val;
      }
    }
    return null;
  }

  String? _extractVatNumber(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final branch = _asMap(node['branch']);
      final seller = _asMap(node['seller']) ?? _asMap(branch?['seller']);
      
      final candidates = [
        node['vat_number'],
        node['tax_number'],
        branch?['vat_number'],
        branch?['tax_number'],
        seller?['vat_number'],
        seller?['tax_number'],
      ];
      
      for (final c in candidates) {
        final val = c?.toString().trim();
        if (val != null && val.isNotEmpty && val.toLowerCase() != 'null') return val;
      }
    }
    return null;
  }

  String? _extractLogoUrl(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final branch = _asMap(node['branch']);
      final seller = _asMap(node['seller']) ?? _asMap(branch?['seller']);
      
      final candidates = [
        node['seller_logo'],
        node['logo'],
        branch?['logo'],
        seller?['logo'],
      ];
      
      for (final c in candidates) {
        final val = c?.toString().trim();
        if (val != null && val.isNotEmpty && val.toLowerCase() != 'null') return val;
      }
    }
    return null;
  }

  String? _extractBranchAddress(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final branch = _asMap(node['branch']);
      final seller = _asMap(node['seller']) ?? _asMap(branch?['seller']);
      
      final candidates = [
        node['branch_address'],
        node['address'],
        branch?['address'],
        branch?['location'],
        seller?['address'],
        seller?['seller_address'],
      ];
      
      for (final c in candidates) {
        final val = c?.toString().trim();
        if (val != null && val.isNotEmpty && val.toLowerCase() != 'null') return val;
      }
    }
    return null;
  }

  String? _extractBranchMobile(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final branch = _asMap(node['branch']);
      final seller = _asMap(node['seller']) ?? _asMap(branch?['seller']);
      
      final candidates = [
        node['branch_phone'],
        node['branch_mobile'],
        node['phone'],
        node['mobile'],
        branch?['mobile'],
        branch?['phone'],
        branch?['telephone'],
        branch?['mobile_number'],
        seller?['mobile'],
        seller?['phone'],
        seller?['telephone'],
      ];
      
      for (final c in candidates) {
        final val = c?.toString().trim();
        if (val != null && val.isNotEmpty && val.toLowerCase() != 'null') return val;
      }
    }
    return null;
  }

  String? _extractCommercialRegister(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final branch = _asMap(node['branch']);
      final seller = _asMap(node['seller']) ?? _asMap(branch?['seller']);
      
      final candidates = [
        node['commercial_register'],
        node['commercial_register_number'],
        node['commercial_number'],
        node['cr_number'],
        node['seller_commercial_register'],
        branch?['commercial_register'],
        branch?['commercial_register_number'],
        branch?['commercial_number'],
        branch?['cr_number'],
        seller?['commercial_register'],
        seller?['commercial_register_number'],
        seller?['commercial_number'],
        seller?['cr_number'],
      ];
      
      for (final c in candidates) {
        final val = c?.toString().trim();
        if (val != null && val.isNotEmpty && val.toLowerCase() != 'null') return val;
      }
    }
    return null;
  }

  String? _extractTableNumber(Map<String, dynamic> data, Map<String, dynamic> payload) {
    final nodes = [data, payload];
    for (final node in nodes) {
      final table = node['table_name']?.toString().trim() ?? 
                   node['table_number']?.toString().trim() ??
                   node['table']?.toString().trim();
      if (table != null && table.isNotEmpty && table != 'null') return table;

      final extra = _asMap(node['type_extra']);
      if (extra != null) {
        final t = extra['table_name']?.toString().trim();
        if (t != null && t.isNotEmpty) return t;
      }
      
      final tableObj = _asMap(node['table']);
      if (tableObj != null) {
        final name = tableObj['name']?.toString().trim() ?? tableObj['number']?.toString().trim();
        if (name != null && name.isNotEmpty) return name;
      }
    }
    return null;
  }


  double _parsePrice(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      var cleaned = value.replaceAll(',', '').trim();
      final currency = ApiConstants.currency.trim();
      if (currency.isNotEmpty) {
        cleaned = cleaned.replaceAll(currency, '');
      }
      cleaned = cleaned
          .replaceAll('SAR', '')
          .replaceAll('QAR', '')
          .replaceAll('RS', '')
          .replaceAll('ر.س', '')
          .replaceAll(RegExp(r'[^\d.\-]'), '');
      return double.tryParse(cleaned) ?? 0.0;
    }
    return 0.0;
  }

  String _formatRefundAmount(double value) {
    final safe = value <= 0 ? 0.0 : value;
    return safe.toStringAsFixed(2);
  }

  String _formatRefundCandidateSubtitle(_RefundCandidate candidate) {
    final parts = <String>[];
    if (candidate.quantity > 0) {
      parts.add('الكمية: ${candidate.quantity}');
    }
    if (candidate.total > 0) {
      parts.add(
        'الإجمالي: ${candidate.total.toStringAsFixed(2)} ${ApiConstants.currency}',
      );
    }
    if (parts.isEmpty) {
      parts.add('رقم العنصر: ${candidate.id}');
    }
    return parts.join(' • ');
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  List<Map<String, dynamic>> _extractItems(
    Map<String, dynamic> data,
    Map<String, dynamic> payload,
  ) {
    List<Map<String, dynamic>> normalizeList(dynamic source) {
      if (source is! List) return const [];
      return source
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }

    final possibleKeys = [
      'meals',
      'booking_meals',
      'booking_products',
      'sales_meals',
      'items',
      'invoice_items',
      'products',
      'order_items',
      'card',
      'cart',
    ];
    final nodes = [data, payload];

    for (final node in nodes) {
      for (final key in possibleKeys) {
        final items = normalizeList(node[key]);
        if (items.isNotEmpty) {
          return items.map((row) {
            final meal = _asMap(row['meal']) ?? const <String, dynamic>{};
            return <String, dynamic>{
              ...row,
              if (row['meal_name'] == null &&
                  meal['name']?.toString().isNotEmpty == true)
                'meal_name': meal['name'],
              if (row['quantity'] == null) 'quantity': 1,
              if (row['unit_price'] == null && row['price'] != null)
                'unit_price': row['price'],
              if (row['total'] == null && row['price'] != null)
                'total': row['price'],
            };
          }).toList();
        }
      }
    }

    final nestedCandidates = [
      data['data'],
      data['booking'],
      data['invoice'],
      payload['data'],
      payload['booking'],
      payload['invoice'],
    ];
    for (final candidate in nestedCandidates) {
      final nested = _asMap(candidate);
      if (nested == null) continue;
      final extracted = _extractItems(nested, const <String, dynamic>{});
      if (extracted.isNotEmpty) return extracted;
    }

    return [];
  }

  List<_RefundCandidate> _extractRefundCandidates(
    Map<String, dynamic> data,
    Map<String, dynamic> payload,
    Map<String, dynamic> previewPayload,
  ) {
    final candidates = <_RefundCandidate>[];

    void addCandidate({
      required _RefundCandidateType type,
      required int id,
      required String name,
      required double total,
      required int quantity,
    }) {
      if (id <= 0) return;
      candidates.add(
        _RefundCandidate(
          id: id,
          type: type,
          name: name,
          total: total,
          quantity: quantity,
        ),
      );
    }

    int? parseId(dynamic value) {
      if (value == null) return null;
      final digits = value.toString().replaceAll(RegExp(r'[^0-9]'), '');
      final parsed = int.tryParse(digits);
      return parsed != null && parsed > 0 ? parsed : null;
    }

    String resolveName(Map<String, dynamic> map) {
      final name = map['meal_name'] ??
          map['product_name'] ??
          map['item_name'] ??
          map['name'] ??
          map['title'];
      final text = name?.toString().trim();
      return (text == null || text.isEmpty) ? 'عنصر' : text;
    }

    int resolveQty(Map<String, dynamic> map) {
      final raw = map['quantity'] ?? map['qty'] ?? map['count'];
      final parsed = int.tryParse(raw?.toString() ?? '');
      return parsed ?? 1;
    }

    double resolveTotal(Map<String, dynamic> map) {
      return _parsePrice(
        map['total'] ?? map['amount'] ?? map['price'] ?? map['unit_price'],
      );
    }

    void addFromList(
      dynamic source, {
      required _RefundCandidateType type,
      required List<String> idKeys,
    }) {
      if (source is! List) return;
      for (final row in source.whereType<Map>()) {
        final map = row.map((k, v) => MapEntry(k.toString(), v));
        int? id;
        for (final key in idKeys) {
          id ??= parseId(map[key]);
        }
        id ??= parseId(map['id']);
        if (id == null) continue;
        addCandidate(
          type: type,
          id: id,
          name: resolveName(map),
          total: resolveTotal(map),
          quantity: resolveQty(map),
        );
      }
    }

    addFromList(
      previewPayload['sales_meals'] ?? previewPayload['meals'],
      type: _RefundCandidateType.meal,
      idKeys: const ['sales_meal_id', 'meal_id', 'item_id'],
    );
    addFromList(
      previewPayload['sales_products'] ?? previewPayload['products'],
      type: _RefundCandidateType.product,
      idKeys: const ['sales_product_id', 'product_id', 'item_id'],
    );

    if (candidates.isNotEmpty) {
      return candidates;
    }

    final items = _extractItems(data, payload);
    for (final item in items) {
      final id = parseId(
        item['sales_meal_id'] ??
            item['sales_product_id'] ??
            item['meal_id'] ??
            item['product_id'] ??
            item['item_id'] ??
            item['id'],
      );
      if (id == null) continue;

      final type =
          item['sales_product_id'] != null || item['product_id'] != null
              ? _RefundCandidateType.product
              : item['sales_meal_id'] != null || item['meal_id'] != null
                  ? _RefundCandidateType.meal
                  : _RefundCandidateType.unknown;

      addCandidate(
        type: type,
        id: id,
        name: resolveName(item),
        total: resolveTotal(item),
        quantity: resolveQty(item),
      );
    }

    return candidates;
  }

  }


enum _RefundCandidateType { meal, product, unknown }

class _RefundCandidate {
  final int id;
  final _RefundCandidateType type;
  final String name;
  final double total;
  final int quantity;

  const _RefundCandidate({
    required this.id,
    required this.type,
    required this.name,
    required this.total,
    required this.quantity,
  });
}

class _RefundSelection {
  final List<_RefundCandidate> candidates;
  final String method;

  const _RefundSelection({
    required this.candidates,
    required this.method,
  });
}
