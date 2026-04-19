// ignore_for_file: unused_element, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../order_service.dart';

extension OrderServiceInvoiceApis on OrderService {
  /// Refund invoice preview (show only)
  Future<Map<String, dynamic>> showInvoiceRefund(String invoiceId) async {
    final response = await _client.get(ApiConstants.invoiceRefundEndpoint(
      invoiceId,
    ));
    return _rememberResponse('show_invoice_refund', response);
  }

  /// Refund an invoice (backward compatible alias for show endpoint)
  Future<Map<String, dynamic>> refundInvoice(String invoiceId) async {
    return showInvoiceRefund(invoiceId);
  }

  /// Process invoice refund
  /// API: PATCH /seller/refund/branches/{branchId}/invoices/{invoiceId}
  Future<Map<String, dynamic>> processInvoiceRefund({
    required String invoiceId,
    Map<String, dynamic> payload = const {},
  }) async {
    final normalizedPayload = Map<String, dynamic>.from(payload);
    final reason = normalizedPayload['refund_reason']?.toString().trim() ?? '';
    if (reason.isEmpty) {
      normalizedPayload['refund_reason'] = 'طلب العميل';
    }

    final endpoint = ApiConstants.invoiceRefundEndpoint(invoiceId);
    Future<Map<String, dynamic>> submitPatch(
      Map<String, dynamic> patchPayload,
    ) async {
      try {
        final response = await _client.patch(endpoint, patchPayload);
        return _rememberResponse('process_invoice_refund', response);
      } on ApiException catch (e) {
        final lowerMessage = e.message.toLowerCase();
        final expectsMultipart = e.statusCode == 415 ||
            lowerMessage.contains('multipart') ||
            lowerMessage.contains('content type') ||
            lowerMessage.contains('unsupported media');
        if (!expectsMultipart) rethrow;

        final fields = <String, String>{};
        patchPayload.forEach((key, value) {
          if (value == null) return;
          if (value is Map || value is List) {
            fields[key] = jsonEncode(value);
            return;
          }
          fields[key] = value.toString();
        });
        final response = await _client.patchMultipart(endpoint, fields);
        return _rememberResponse('process_invoice_refund', response);
      }
    }

    try {
      return await submitPatch(normalizedPayload);
    } on ApiException catch (e) {
      if (!_isInvoiceRefundContractMismatch(e)) rethrow;
      final compatiblePayload = await _buildInvoiceRefundCompatiblePayload(
        invoiceId: invoiceId,
        originalPayload: normalizedPayload,
      );
      return submitPatch(compatiblePayload);
    }
  }

  /// Get latest credit note number for an invoice
  /// Fetches refunds list and finds the CN matching this invoice
  Future<String?> getLatestCreditNoteNumber(String invoiceId) async {
    try {
      final response = await _client.get(
        '/seller/branches/${ApiConstants.branchId}/refunds',
      );
      final data = response is Map ? response['data'] : response;
      if (data is List) {
        // Refunds are ordered newest first, find one related to this invoice
        for (final refund in data) {
          if (refund is! Map) continue;
          final cnNumber = refund['invoice_number']?.toString() ?? '';
          if (cnNumber.startsWith('#CN') && cnNumber.isNotEmpty) {
            // Fetch refund details to confirm it belongs to this invoice
            final refundId = refund['id']?.toString() ?? '';
            if (refundId.isEmpty) continue;
            try {
              final detail = await _client.get(
                '/seller/branches/${ApiConstants.branchId}/refunds/$refundId',
              );
              final detailData = detail is Map ? (detail['data'] ?? detail) : detail;
              final invoice = detailData is Map ? detailData['invoice'] : null;
              if (invoice is Map) {
                final originalInvoice = invoice['original_invoice_number']?.toString() ?? '';
                if (originalInvoice == '#IN-$invoiceId' || originalInvoice.contains(invoiceId)) {
                  return invoice['invoice_number']?.toString();
                }
              }
            } catch (_) {}
            // If we can't verify, return the first CN (most recent)
            return cnNumber;
          }
        }
      }
    } catch (e) {
      print('⚠️ Failed to get CN number: $e');
    }
    return null;
  }

  /// Update invoice payment methods
  Future<Map<String, dynamic>> updateInvoicePays(
    String invoiceId, {
    required List<Map<String, dynamic>> pays,
    required String date,
  }) async {
    final payload = <String, dynamic>{'pays': pays, 'date': date};
    final response = await _client.patch(
      '/seller/updatePays/branches/${ApiConstants.branchId}/invoices/$invoiceId',
      payload,
    );
    return _rememberResponse('update_invoice_pays', response);
  }

  /// Update invoice employees
  Future<Map<String, dynamic>> updateInvoiceEmployees(
    String invoiceId, {
    required List<int> employeeIds,
  }) async {
    final response = await _client.patch(
      ApiConstants.invoiceEmployeesEndpoint(invoiceId),
      {'employee_ids': employeeIds},
    );
    return _rememberResponse('update_invoice_employees', response);
  }

  /// Update invoice date
  Future<Map<String, dynamic>> updateInvoiceDate({
    required String invoiceId,
    required String date,
  }) async {
    final response = await _client.put(
      '/seller/branches/${ApiConstants.branchId}/invoices/$invoiceId/update-date',
      {'date': date},
    );
    return _rememberResponse('update_invoice_date', response);
  }
}
