// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../invoice_details_dialog.dart';

extension InvoiceDetailsDialogDataLoading on _InvoiceDetailsDialogState {
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

}
