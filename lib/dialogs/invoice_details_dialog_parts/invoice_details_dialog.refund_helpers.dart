// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../invoice_details_dialog.dart';

extension InvoiceDetailsDialogRefundHelpers on _InvoiceDetailsDialogState {
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
        title: Text(translationService.t('refund_options_title')),
        content: Text(translationService.t('refund_options_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(translationService.t('cancel')),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'partial'),
            child: Text(translationService.t('refund_items_button')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'full'),
            child: Text(translationService.t('full_refund')),
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
        SnackBar(content: Text(translationService.t('failed_fetch_refund_data', args: {'error': e.toString()}))),
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
          title: Text(translationService.t('invoice_refund_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InputDecorator(
                decoration: InputDecoration(
                  labelText: translationService.t('original_payment_method'),
                  border: const OutlineInputBorder(),
                ),
                child: Text(originalPaymentMethod),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRefundMethod,
                decoration: InputDecoration(
                  labelText: translationService.t('refund_method_label'),
                  border: const OutlineInputBorder(),
                ),
                items: refundMethodOptions.map((method) {
                  switch (method) {
                    case 'cash':
                      return DropdownMenuItem(
                          value: 'cash', child: Text(translationService.t('cash')));
                    case 'card':
                      return DropdownMenuItem(
                          value: 'card', child: Text(translationService.t('card')));
                    default:
                      return DropdownMenuItem(
                          value: 'other', child: Text(translationService.t('refund_other')));
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
                Text(translationService.t('current_status_with_value', args: {'status': refundStatus})),
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
              child: Text(translationService.t('cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, selectedRefundMethod),
              child: Text(translationService.t('execute_refund')),
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

      // Fetch CN number from refunds API
      String? cnNumber;
      try {
        cnNumber = await _orderService.getLatestCreditNoteNumber(widget.invoiceId);
      } catch (_) {}

      // Print credit note (فاتورة دائن)
      debugPrint('🧾 Triggering credit note print for invoice=${widget.invoiceId} cn=$cnNumber');
      await _printCreditNoteForInvoice(widget.invoiceId, creditNoteNumber: cnNumber);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(translationService.t('failed_execute_refund', args: {'error': e.toString()}))),
      );
    } finally {
      if (mounted) setState(() => _isProcessingRefund = false);
    }
  }

}
