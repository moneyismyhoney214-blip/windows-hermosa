// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../invoice_details_dialog.dart';

extension InvoiceDetailsDialogActions on _InvoiceDetailsDialogState {
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
        SnackBar(content: Text(translationService.t('no_order_linked_invoice'))),
      );
      return;
    }

    final controller = TextEditingController(text: 'طلبك جاهز للاستلام');
    final message = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(translationService.t('send_whatsapp_title')),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: translationService.t('message_text'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(translationService.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(translationService.t('send')),
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
        SnackBar(content: Text(translationService.t('whatsapp_sent_order_hash', args: {'id': orderId.toString()}))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(translationService.t('failed_send_message', args: {'error': e.toString()}))),
      );
    } finally {
      if (mounted) setState(() => _isSendingWhatsApp = false);
    }
  }

}
