// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../invoice_details_dialog.dart';

extension InvoiceDetailsDialogStateHelpers on _InvoiceDetailsDialogState {
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

    // Check if ALL items are refunded by comparing quantities
    final meals = data['sales_meals'] ?? data['meals'] ?? data['items'] ?? data['booking_meals'];
    if (meals is List && meals.isNotEmpty) {
      final allRefunded = meals.every((m) {
        if (m is! Map) return false;
        final qty = int.tryParse(m['quantity']?.toString() ?? '0') ?? 0;
        final refundedQty = int.tryParse(m['refunded_quantity']?.toString() ?? m['cancelled_quantity']?.toString() ?? '0') ?? 0;
        final isRefunded = m['is_refunded'] == true || m['is_refunded'] == 1 || m['is_refunded']?.toString() == 'true';
        return isRefunded || (refundedQty >= qty && qty > 0);
      });
      return allRefunded;
    }

    // Fallback to status-based check
    final normalizedStatus = data['status']?.toString().trim().toLowerCase();
    final display = data['status_display']?.toString().trim().toLowerCase() ?? '';
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

}
