// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../invoices_screen.dart';

extension InvoicesScreenActions on _InvoicesScreenState {
  Widget _buildInvoiceHeaderIds(Invoice invoice) {
    final invoiceId = _formatInvoiceIdDisplay(_resolveInvoiceId(invoice));
    final dailyOrder =
        _formatOrderNumberDisplay(_resolveDailyOrderNumber(invoice));
    final invoiceLabel =
        invoiceId.isNotEmpty ? '${_tr('فاتورة', 'Invoice')} $invoiceId' : '';
    final orderLabel =
        dailyOrder.isNotEmpty ? '${_tr('طلب', 'Order')} $dailyOrder' : '';

    if (invoiceLabel.isNotEmpty && orderLabel.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            orderLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.appText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            invoiceLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.appTextMuted,
            ),
          ),
        ],
      );
    }

    final singleLabel = orderLabel.isNotEmpty ? orderLabel : invoiceLabel;
    return Text(
      singleLabel.isNotEmpty ? singleLabel : _tr('فاتورة', 'Invoice'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: context.appText,
      ),
    );
  }

  String _formatInvoiceDate(Invoice invoice) {
    final raw = invoice.date.trim().isNotEmpty
        ? invoice.date
        : invoice.createdAt;
    if (raw.isEmpty) return _tr('بدون تاريخ', 'No date');
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final hasTime = raw.contains(':');
    final local = parsed.toLocal();
    final timeLabel = DateFormat('HH:mm').format(local);
    if (!hasTime || timeLabel == '00:00') {
      return DateFormat('yyyy-MM-dd').format(local);
    }
    return timeLabel;
  }

  Color _statusColor(String status) {
    return const Color(0xFF64748B);
  }

  Future<String?> _showWhatsAppMessageDialog({
    required String title,
    required String initialMessage,
  }) async {
    final controller = TextEditingController(text: initialMessage);
    final message = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: _tr('نص الرسالة', 'Message'),
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
            child: Text(_tr('إرسال', 'Send')),
          ),
        ],
      ),
    );
    controller.dispose();
    return message;
  }

  String _normalizeWhatsAppMessage(String message) {
    final trimmed = message.trim();
    final atCount = '@'.allMatches(trimmed).length;
    if (atCount >= 2) return trimmed;

    final needed = 2 - atCount;
    final suffix = List<String>.filled(needed, '@@').join(' ');
    return '$trimmed $suffix'.trim();
  }

  Future<void> _sendWhatsAppForOrder({
    required int orderId,
    required String orderLabel,
  }) async {
    final message = await _showWhatsAppMessageDialog(
      title: _tr('إرسال واتساب للطلب $orderLabel',
          'Send WhatsApp for order $orderLabel'),
      initialMessage: _tr('طلبك جاهز للاستلام', 'Your order is ready'),
    );
    if (message == null || message.isEmpty) return;

    setState(() => _isSendingWhatsApp = true);
    try {
      final normalizedMessage = _normalizeWhatsAppMessage(message);
      await _orderService.sendOrderWhatsApp(
        orderId: orderId.toString(),
        message: normalizedMessage,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr('تم إرسال واتساب للطلب $orderLabel',
                'WhatsApp sent for order $orderLabel'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final userMessage = ErrorHandler.toUserMessage(
        e,
        fallback: _tr('تعذر إرسال واتساب', 'Failed to send WhatsApp'),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userMessage)),
      );
    } finally {
      if (mounted) setState(() => _isSendingWhatsApp = false);
    }
  }

  int? _resolveOrderIdFromInvoice(Invoice invoice) {
    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    final direct = invoice.orderId;
    if (direct != null && direct > 0) return direct;

    final raw = invoice.raw;
    final candidates = [
      raw['order_id'],
      raw['booking_id'],
      raw['order'] is Map ? (raw['order'] as Map)['id'] : null,
      raw['booking'] is Map ? (raw['booking'] as Map)['id'] : null,
    ];
    for (final candidate in candidates) {
      final parsed = parseInt(candidate);
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  int? _extractOrderIdFromPayload(dynamic payload) {
    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    if (payload is Map) {
      final map = payload.map((k, v) => MapEntry(k.toString(), v));
      final directCandidates = [
        map['order_id'],
        map['booking_id'],
        map['orderId'],
        map['bookingId'],
      ];
      for (final candidate in directCandidates) {
        final parsed = parseInt(candidate);
        if (parsed != null && parsed > 0) return parsed;
      }

      final bookingMap = map['booking'];
      if (bookingMap is Map) {
        final parsed = parseInt(bookingMap['id'] ?? bookingMap['order_id']);
        if (parsed != null && parsed > 0) return parsed;
      }

      final orderMap = map['order'];
      if (orderMap is Map) {
        final parsed = parseInt(orderMap['id']);
        if (parsed != null && parsed > 0) return parsed;
      }

      final invoiceMap = map['invoice'];
      if (invoiceMap is Map) {
        final parsed = _extractOrderIdFromPayload(invoiceMap);
        if (parsed != null && parsed > 0) return parsed;
      }

      final dataMap = map['data'];
      if (dataMap is Map) {
        final parsed = _extractOrderIdFromPayload(dataMap);
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    return null;
  }

  bool _isRouteNotFound(ApiException e) {
    final msg = e.message.toLowerCase();
    final user = (e.userMessage ?? '').toLowerCase();
    return msg.contains('route_not_found') ||
        user.contains('الخدمة المطلوبة') ||
        user.contains('غير متاحة');
  }

  Future<int?> _resolveOrderIdForInvoiceAsync(Invoice invoice) async {
    final direct = _resolveOrderIdFromInvoice(invoice);
    if (direct != null && direct > 0) return direct;
    try {
      final details = await _orderService.getInvoice(invoice.id.toString());
      final extracted = _extractOrderIdFromPayload(details);
      if (extracted != null && extracted > 0) return extracted;
    } catch (_) {
      // Continue to helper endpoint
    }
    if (!_invoiceHelperSupported) return null;
    try {
      final helper = await _orderService.getInvoiceHelper(invoice.id.toString());
      final extracted = _extractOrderIdFromPayload(helper);
      if (extracted != null && extracted > 0) return extracted;
    } on ApiException catch (e) {
      if (e.statusCode == 404 && _isRouteNotFound(e)) {
        if (mounted) {
          setState(() => _invoiceHelperSupported = false);
        } else {
          _invoiceHelperSupported = false;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _showUpdateStatusDialogForOrder({
    required int orderId,
    required String orderLabel,
    required String currentStatus,
  }) async {
    int selectedStatus = _normalizeStatusToApiValue(currentStatus);
    // Only delivery-lifecycle statuses + cancel are selectable here.
    final statusOptions = <Map<String, dynamic>>[
      {
        'value': 5,
        'label': _tr('جاهز للتوصيل', 'Ready for delivery'),
        'color': const Color(0xFF16A34A),
      },
      {
        'value': 6,
        'label': _tr('قيد التوصيل', 'On the way'),
        'color': const Color(0xFF0EA5E9),
      },
      {
        'value': 7,
        'label': _tr('مكتمل', 'Completed'),
        'color': const Color(0xFF15803D),
      },
      {
        'value': 8,
        'label': _tr('ملغي', 'Cancelled'),
        'color': const Color(0xFFEF4444),
      },
    ];

    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _tr(
            'تحديث حالة الطلب $orderLabel',
            'Update order status $orderLabel',
          ),
        ),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: statusOptions.map((option) {
                final value = option['value'] as int;
                final color = option['color'] as Color;
                final selected = selectedStatus == value;
                return ChoiceChip(
                  label: Text(option['label'] as String),
                  selected: selected,
                  onSelected: (_) =>
                      setDialogState(() => selectedStatus = value),
                  selectedColor: color.withValues(alpha: 0.18),
                  backgroundColor: const Color(0xFFF8FAFC),
                  labelStyle: TextStyle(
                    color: selected ? color : const Color(0xFF475569),
                    fontWeight: FontWeight.bold,
                  ),
                  side: BorderSide(color: color),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                );
              }).toList(),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(translationService.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              // Extra confirm step when the user picks "Cancelled" —
              // cancellation is destructive and not reversible from here.
              if (selectedStatus == 8) {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (confirmCtx) => AlertDialog(
                    title: Text(_tr('تأكيد إلغاء الطلب', 'Confirm cancel order')),
                    content: Text(_tr(
                      'هل أنت متأكد من إلغاء الطلب $orderLabel؟ لا يمكن التراجع عن هذا الإجراء.',
                      'Are you sure you want to cancel order $orderLabel? This action cannot be undone.',
                    )),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(confirmCtx, false),
                        child: Text(_tr('تراجع', 'Back')),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(confirmCtx, true),
                        child: Text(_tr('نعم، إلغاء الطلب', 'Yes, cancel')),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
              }
              if (!context.mounted) return;
              Navigator.pop(context, selectedStatus);
            },
            child: Text(translationService.t('save')),
          ),
        ],
      ),
    );

    if (result == null) return;

    try {
      await _orderService.updateBookingStatus(
        orderId: orderId.toString(),
        status: result,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('تم تحديث حالة الطلب بنجاح',
              'Order status updated successfully')),
        ),
      );
      _displayAppService.sendOrderStatusUpdateToDisplay(
        orderId: orderId.toString(),
        status: result,
      );
      _loadInvoices(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_tr('تعذر تحديث حالة الطلب: $e',
                'Unable to update order status: $e'))),
      );
    }
  }

  int _normalizeStatusToApiValue(String status) {
    switch (status.toLowerCase()) {
      case '1':
      case 'confirmed':
      case 'pending':
      case 'new':
        return 1;
      case '2':
      case 'started':
      case 'start':
      case 'in_progress':
        return 2;
      case '3':
      case 'ended':
        return 3;
      case '4':
      case 'preparing':
      case 'processing':
        return 4;
      case '5':
      case 'ready':
      case 'ready_for_delivery':
        return 5;
      case '6':
      case 'on_the_way':
      case 'out_for_delivery':
        return 6;
      case '7':
      case 'finished':
      case 'done':
      case 'completed':
        return 7;
      case '8':
      case 'cancelled':
      case 'canceled':
        return 8;
      default:
        return 1;
    }
  }


  Future<void> _showRefundedMealsForInvoice(Invoice invoice) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final refundedMeals = await _orderService.getRefundedMeals(
        invoiceId: invoice.id.toString(),
      );
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading

      if (refundedMeals.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tr(
              'لا توجد مرتجعات لهذه الفاتورة',
              'No refunds for this invoice',
            )),
          ),
        );
        return;
      }

      showDialog(
        context: context,
        builder: (context) => _RefundedMealsDialog(
          title: _tr(
            'مرتجعات الفاتورة #${invoice.id}',
            'Refunds - Invoice #${invoice.id}',
          ),
          refundedMeals: refundedMeals,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading
      final userMessage = ErrorHandler.toUserMessage(
        e,
        fallback: _tr('تعذر جلب المرتجعات', 'Failed to load refunds'),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userMessage)),
      );
    }
  }

  Future<void> _showInvoiceRefundOptions(Invoice invoice) async {
    if (_refundingInvoiceIds.contains(invoice.id)) return;
    // Allow refund for paid or partially-refunded invoices
    if (!_isInvoicePaid(invoice) && !_hasPartialRefund(invoice)) return;
    if (_isInvoiceFullyRefunded(invoice)) return;
    setState(() => _refundingInvoiceIds.add(invoice.id));

    try {
      await showInvoiceRefundDialog(
        context: context,
        invoiceId: invoice.id.toString(),
        invoiceLabel: _formatInvoiceNumber(invoice),
      );
      // Always reload to sync state across cashiers
      await _loadInvoices(reset: true);
    } catch (e) {
      if (!mounted) return;
      final userMessage = ErrorHandler.toUserMessage(
        e,
        fallback: _tr('تعذر تنفيذ الاسترجاع', 'Failed to process refund'),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userMessage)),
      );
    } finally {
      if (mounted) {
        setState(() => _refundingInvoiceIds.remove(invoice.id));
      }
    }
  }

  Future<void> _showBookingDetailsForInvoice(Invoice invoice) async {
    var bookingId = invoice.orderId ?? invoice.raw['booking_id'] ?? invoice.raw['order_id'];
    final orderService = getIt<OrderService>();

    // If no booking_id locally, try to get it from invoice details API
    if (bookingId == null) {
      try {
        final invoiceDetails = await orderService.getInvoice(invoice.id.toString());
        final data = invoiceDetails['data'] is Map
            ? (invoiceDetails['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
            : invoiceDetails;
        final inv = data['invoice'] is Map
            ? (data['invoice'] as Map).map((k, v) => MapEntry(k.toString(), v))
            : data;
        bookingId = inv['booking_id'] ?? inv['order_id'] ?? data['booking_id'] ?? data['order_id'];
      } catch (_) {}
    }

    if (bookingId == null) {
      // Last resort: show InvoiceDetailsDialog instead
      if (!mounted) return;
      _openInvoiceDetails(invoice);
      return;
    }

    try {
      final details = await orderService.getBookingDetails(bookingId.toString());
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => BookingDetailsDialog(bookingData: details),
      );
    } catch (e) {
      if (!mounted) return;
      // Fallback to InvoiceDetailsDialog if booking details fail
      _openInvoiceDetails(invoice);
    }
  }

  Future<bool> _openInvoiceDetails(
    Invoice invoice, {
    bool autoOpenRefund = false,
    bool autoOpenSingleItemRefund = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => InvoiceDetailsDialog(
        invoiceId: invoice.id.toString(),
        autoOpenRefund: autoOpenRefund,
        autoOpenSingleItemRefund: autoOpenSingleItemRefund,
        onPrintReceipt: widget.onPrintReceipt,
      ),
    );
    if (result == true) {
      await _loadInvoices(reset: true);
    }
    return result == true;
  }

}
