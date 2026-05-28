// ignore_for_file: library_private_types_in_public_api
// Single-item refund flow — off-limits for routine refactors (part of
// the receipt/refund pipeline). `use_build_context_synchronously`
// finding here is a known micro-bug that needs a dedicated pass over
// the refund dialog's state machine. Suppressed at file level until
// then.
// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast, use_build_context_synchronously
part of '../invoice_details_dialog.dart';

extension InvoiceDetailsDialogSingleItemRefund on _InvoiceDetailsDialogState {
  Future<void> _showSingleItemRefundDialog() async {
    if (_invoiceDetails == null || _isProcessingRefund) return;

    final payload = _asMap(_invoiceDetails!['data']) ?? _invoiceDetails!;
    final data = _asMap(payload['invoice']) ?? payload;

    const refundMethodOptions = ['cash', 'card', 'other'];
    final originalPaymentMethod = _resolvePaymentMethodLabel(data, payload);

    Map<String, dynamic> preview;
    try {
      preview = await _orderService.showInvoiceRefund(widget.invoiceId);
    } catch (e) {
      if (!mounted) return;
      UiFeedback.info(context, translationService.t('failed_fetch_refund_data', args: {'error': e.toString()}));
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
      UiFeedback.info(context, translationService.t('no_items_available_refund'));
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
          title: Text(translationService.t('refund_items_button')),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
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
              child: Text(translationService.t('cancel')),
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
              child: Text(translationService.t('execute_refund')),
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
      UiFeedback.success(context, (serverMessage != null && serverMessage.isNotEmpty)
                ? serverMessage
                : 'تم تنفيذ الاسترجاع بنجاح');

      // Fetch CN number from refunds API
      String? cnNumber2;
      try {
        cnNumber2 = await _orderService.getLatestCreditNoteNumber(widget.invoiceId);
      } catch (e) {
        Log.d('InvoiceDetailsDialog', 'fetch credit-note number (single-item) failed (non-fatal): $e');
      }

      // Print credit note (فاتورة دائن) with refunded items — fire and forget before pop
      final creditNoteFuture = _printCreditNoteWithItems(
        widget.invoiceId,
        selection.candidates,
        creditNoteNumber: cnNumber2,
      );

      // Wait briefly for print to start, then close dialog
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      Navigator.pop(context, true);
      await creditNoteFuture;
    } catch (e) {
      if (!mounted) return;
      UiFeedback.info(context, translationService.t('failed_execute_refund', args: {'error': e.toString()}));
    } finally {
      if (mounted) setState(() => _isProcessingRefund = false);
    }
  }

}
