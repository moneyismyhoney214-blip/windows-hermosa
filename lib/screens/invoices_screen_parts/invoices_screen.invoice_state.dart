// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../invoices_screen.dart';

extension InvoicesScreenInvoiceState on _InvoicesScreenState {
  Future<void> _openInvoicePreview(Invoice invoice) async {
    try {
      Map<String, dynamic> invoiceDetails;
      try {
        invoiceDetails = await _orderService.getInvoice(invoice.id.toString());
      } catch (_) {
        invoiceDetails =
            await _orderService.getInvoiceHelper(invoice.id.toString());
      }

      var receiptData =
          _buildReceiptDataFromInvoiceDetails(invoiceDetails, invoice.id);
      receiptData = await _ensureReceiptLogo(receiptData, invoiceDetails);

      if (!mounted) return;
      await InvoicePreviewHelper.open(
        context: context,
        receiptData: receiptData,
        invoiceId: invoice.id.toString(),
        orderType: receiptData.orderType,
        promptPrinterSelectionOnOpen: false,
        forcePreferredPrinter: true,
        printButtonLabel: 'طباعة',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ErrorHandler.toUserMessage(
              e,
              fallback: _tr(
                'تعذر توليد الفاتورة حالياً.',
                'Unable to generate invoice right now.',
              ),
            ),
          ),
        ),
      );
    }
  }

  /// True only when ALL items have been refunded (status = refunded/4).
  bool _isInvoiceFullyRefunded(Invoice invoice) {
    final normalizedStatus = invoice.status.trim().toLowerCase();
    final display = invoice.statusDisplay.trim().toLowerCase();

    if (display.contains('جزئي') || display.contains('partial')) return false;
    if (normalizedStatus == 'refunded') return true;
    if (display == 'مسترجع' || display == 'refunded') return true;
    return false;
  }

  /// True when the invoice is cancelled (status 4 / "تم الالغاء").
  /// Cancelled invoices should NOT allow refund.
  bool _isInvoiceCancelled(Invoice invoice) {
    final normalizedStatus = invoice.status.trim().toLowerCase();
    final display = invoice.statusDisplay.trim().toLowerCase();
    return normalizedStatus == '4' ||
        normalizedStatus == 'cancelled' ||
        normalizedStatus == 'canceled' ||
        display == 'تم الالغاء' ||
        display == 'ملغي' ||
        display == 'cancelled' ||
        display == 'canceled';
  }

  /// True when some (but not all) items have been refunded.
  bool _hasPartialRefund(Invoice invoice) {
    if (_isInvoiceFullyRefunded(invoice)) return false;

    bool isTruthy(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is num) return value != 0;
      final s = value.toString().trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes';
    }

    final raw = invoice.raw;
    final hasRefundEvidence = isTruthy(
      raw['has_refund'] ?? raw['refund_id'] ?? raw['refund_status'],
    );

    // Status 4 / "تم الالغاء": only treat as partial refund if there is
    // concrete evidence a refund happened (has_refund, refund_id, etc.).
    // Otherwise it is a genuine cancellation — no refund allowed.
    if (_isInvoiceCancelled(invoice)) {
      return hasRefundEvidence;
    }

    if (hasRefundEvidence) return true;

    final display = invoice.statusDisplay.trim().toLowerCase();
    if (display.contains('جزئي') || display.contains('partial')) return true;

    final normalizedStatus = invoice.status.trim().toLowerCase();
    if (normalizedStatus == 'partially_refunded' ||
        normalizedStatus == 'partial_refund') return true;

    return false;
  }

  bool _isInvoicePaid(Invoice invoice) {
    bool isTruthy(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is num) return value != 0;
      final normalized = value.toString().trim().toLowerCase();
      if (normalized.isEmpty || normalized == 'null') return false;
      return normalized == '1' || normalized == 'true' || normalized == 'yes';
    }

    final normalizedStatus = invoice.status.trim().toLowerCase();
    if (normalizedStatus == 'paid' ||
        normalizedStatus == '2' ||
        normalizedStatus == '7' ||
        normalizedStatus == 'completed') {
      return true;
    }

    final display = invoice.statusDisplay.trim().toLowerCase();
    if (display.contains('مدفوع') || display.contains('paid')) return true;

    final raw = invoice.raw;
    return isTruthy(
      raw['is_paid'] ??
          raw['paid'] ??
          raw['payment_status'] ??
          raw['payment_state'] ??
          raw['pay_status'] ??
          raw['pay_status_id'],
    );
  }

  String _formatInvoiceNumber(Invoice invoice) {
    final raw = invoice.invoiceNumber.trim();
    if (raw.isEmpty || raw == '0') {
      return '#${invoice.id}';
    }
    return raw.startsWith('#') ? raw : '#$raw';
  }

  String _formatInvoiceIdDisplay(String? rawValue) {
    final raw = rawValue?.trim() ?? '';
    if (raw.isEmpty || raw == '0') return '';
    final clean = raw.replaceAll('#', '').trim();
    if (clean.isEmpty || clean == '0') return '';
    if (_hasLetters(clean)) return clean;
    return '#$clean';
  }

  String _formatOrderNumberDisplay(String? rawValue) {
    final raw = rawValue?.trim() ?? '';
    if (raw.isEmpty || raw == '0') return '';
    final clean = raw.replaceAll('#', '').trim();
    if (clean.isEmpty || clean == '0') return '';
    return '#$clean';
  }

  String? _resolveInvoiceId(Invoice invoice) {
    return _firstNonEmptyText(
      [
        invoice.invoiceNumber,
        invoice.raw['invoice_number'],
        invoice.raw['invoice_id'],
        invoice.raw['id'],
        invoice.id,
      ],
      allowZero: false,
    );
  }

  String? _resolveDailyOrderNumber(Invoice invoice) {
    final raw = invoice.raw;
    final orderMap =
        raw['order'] is Map ? Map<String, dynamic>.from(raw['order']) : null;
    final bookingMap =
        raw['booking'] is Map ? Map<String, dynamic>.from(raw['booking']) : null;
    return _firstNonEmptyText(
      [
        raw['daily_order_number'],
        orderMap?['daily_order_number'],
        bookingMap?['daily_order_number'],
        raw['order_number'],
        orderMap?['order_number'],
        bookingMap?['order_number'],
        raw['booking_number'],
        bookingMap?['booking_number'],
      ],
      allowZero: false,
    );
  }

  bool _matchesSearchQuery(String? candidate, String query) {
    if (candidate == null || candidate.trim().isEmpty) return false;
    final normalizedCandidate = _normalizeSearchToken(candidate);
    final normalizedQuery = _normalizeSearchToken(query);
    if (normalizedQuery.isEmpty) return false;
    return normalizedCandidate.contains(normalizedQuery);
  }

  bool _invoiceMatchesSearch(Invoice invoice, String query) {
    final invoiceId = _resolveInvoiceId(invoice);
    final dailyOrder = _resolveDailyOrderNumber(invoice);
    final candidates = [
      invoiceId,
      dailyOrder,
      invoice.id.toString(),
      invoice.raw['invoice_number']?.toString(),
      invoice.raw['invoice_id']?.toString(),
      invoice.raw['order_number']?.toString(),
      invoice.raw['daily_order_number']?.toString(),
    ];
    return candidates.any((value) => _matchesSearchQuery(value, query));
  }

}
