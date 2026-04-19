// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../orders_screen.dart';

extension OrdersScreenActions on _OrdersScreenState {
  Future<void> _cancelBooking(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('إلغاء الحجز', 'Cancel Booking')),
        content: Text(_tr(
          'هل أنت متأكد من إلغاء هذا الحجز؟',
          'Are you sure you want to cancel this booking?',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_tr('لا', 'No')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: Text(_tr('نعم، إلغاء', 'Yes, Cancel')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _orderService.updateBookingStatus(
        orderId: booking.id.toString(),
        status: 8,
      );

      // Print cancellation ticket to kitchen
      if (widget.onPrintOrderChanges != null) {
        try {
          final details = await _orderService.getBookingDetails(booking.id.toString());
          final detailData = details['data'] is Map
              ? (details['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
              : details;
          final bookingNode = detailData['booking'] is Map
              ? (detailData['booking'] as Map).map((k, v) => MapEntry(k.toString(), v))
              : detailData;

          final mealsList = (bookingNode['booking_meals'] ?? bookingNode['meals'] ?? bookingNode['items'] ?? detailData['booking_meals']) as List?;
          if (mealsList != null && mealsList.isNotEmpty) {
            final cancelChanges = mealsList.map((meal) {
              final m = meal is Map ? meal.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
              final name = m['meal_name']?.toString() ?? m['name']?.toString() ?? m['item_name']?.toString() ?? '';
              final qty = int.tryParse(m['quantity']?.toString() ?? '1') ?? 1;
              return OrderChange(type: 'cancel', name: name, quantity: qty);
            }).toList();
            final orderNum = booking.orderNumber ?? booking.bookingNumberRaw ?? booking.id.toString();
            widget.onPrintOrderChanges!(cancelChanges, orderNum, isFullCancel: true);
          }
        } catch (e) {
          debugPrint('⚠️ Could not print cancellation ticket: $e');
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('تم إلغاء الحجز', 'Booking cancelled'))),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('فشل إلغاء الحجز', 'Failed to cancel booking'))),
      );
    }
  }

  Future<void> _showBookingRefundDialog(Booking booking) async {
    final refundedPreTax = await showBookingRefundDialog(
      context: context,
      bookingId: booking.id.toString(),
      bookingLabel: _bookingReference(booking),
    );
    if (refundedPreTax != null && refundedPreTax > 0 && mounted) {
      _bookingRefundedAmounts[booking.id] =
          (_bookingRefundedAmounts[booking.id] ?? 0) + refundedPreTax;
      await _loadData();
      // Also recalculate from refund preview (remaining items) for accuracy
      try {
        final preview = await _orderService.showBookingRefund(booking.id.toString());
        final collection = (preview['data'] is Map
            ? (preview['data'] as Map)['collection']
            : null) as List?;
        if (collection != null) {
          double remainingPreTax = 0;
          for (final item in collection) {
            if (item is Map) {
              remainingPreTax += _parseNum(item['price']);
            }
          }
          // Override local tracking with accurate server data
          final originalPreTax = _bookingOriginalTotal(booking);
          if (originalPreTax > 0) {
            _bookingRefundedAmounts[booking.id] = originalPreTax - remainingPreTax;
          }
          if (mounted) setState(() {});
        }
      } catch (_) {}
    }
  }

  double _bookingOriginalTotal(Booking booking) {
    if (booking.meals.isNotEmpty) {
      double sum = 0;
      for (final meal in booking.meals) {
        sum += meal.total > 0 ? meal.total : (meal.unitPrice * meal.quantity);
      }
      return sum;
    }
    return booking.total;
  }

  String _formatBookingDate(Booking booking) {
    final raw =
        booking.date.trim().isNotEmpty ? booking.date : booking.createdAt;
    if (raw.isEmpty) return _tr('بدون تاريخ', 'No date');
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('yyyy-MM-dd HH:mm').format(parsed);
  }

  double _bookingGrandTotal(Booking booking) {
    final raw = booking.raw;
    // Resolve the branch's real tax rate at call time. Previously this
    // function hardcoded `* 1.15`, which baked a 15% VAT onto every pay-later
    // total even for branches that have tax disabled — so a 6 SAR order
    // showed as 6.90 in the Orders list. Reading from BranchService keeps
    // taxed branches working (15%, 5%, custom rates) and makes untaxed
    // branches display the raw amount.
    final branchService = getIt<BranchService>();
    final taxRate = branchService.cachedHasTax ? branchService.cachedTaxRate : 0.0;
    final taxMultiplier = 1.0 + taxRate;

    double base;
    // 1. Try grand_total directly from API (already includes any tax).
    final gt = double.tryParse(raw['grand_total']?.toString() ?? '');
    if (gt != null && gt > 0) {
      base = gt;
    } else if (booking.tax > 0) {
      // 2. Backend returned an explicit tax amount — trust it.
      base = booking.total + booking.tax;
    } else if (booking.meals.isNotEmpty) {
      // 3. Sum meals and optionally gross up by the configured tax rate.
      double sum = 0;
      for (final meal in booking.meals) {
        sum += meal.total > 0 ? meal.total : (meal.unitPrice * meal.quantity);
      }
      base = sum > 0 ? sum * taxMultiplier : booking.total;
    } else if (booking.total > 0) {
      // 4. Fallback: gross up booking.total by the configured tax rate.
      base = booking.total * taxMultiplier;
    } else {
      base = booking.total;
    }
    // Subtract locally tracked refund amounts (pre-tax → gross up by the
    // same configured rate).
    final refundedPreTax = _bookingRefundedAmounts[booking.id];
    if (refundedPreTax != null && refundedPreTax > 0) {
      base = (base - refundedPreTax * taxMultiplier).clamp(0.0, double.infinity);
    }
    return base;
  }

  String _resolveOrderStatusLabel(Booking booking) {
    final orderNode = booking.raw['order'] is Map
        ? (booking.raw['order'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : null;
    final bookingNode = booking.raw['booking'] is Map
        ? (booking.raw['booking'] as Map)
            .map((k, v) => MapEntry(k.toString(), v))
        : null;
    final apiStatusCandidates = <String>[
      booking.raw['status_display']?.toString().trim() ?? '',
      orderNode?['status_display']?.toString().trim() ?? '',
      bookingNode?['status_display']?.toString().trim() ?? '',
    ].where((value) => value.isNotEmpty);
    if (apiStatusCandidates.isNotEmpty) {
      return apiStatusCandidates.first;
    }
    switch (booking.status.toLowerCase()) {
      case '1':
      case 'confirmed':
      case 'new':
      case 'pending':
        return _tr('حجز مؤكد', 'Confirmed');
      case '2':
      case 'started':
        return _tr('بدأ', 'Started');
      case '3':
        return _tr('انتهي', 'Ended');
      case '4':
      case 'preparing':
      case 'processing':
        return translationService.t('preparing_status');
      case '5':
      case 'ready':
      case 'ready_for_delivery':
        return _tr('جاهز للتوصيل', 'Ready for delivery');
      case '6':
      case 'on_the_way':
      case 'out_for_delivery':
        return translationService.t('on_the_way');
      case '7':
      case 'finished':
      case 'done':
      case 'completed':
        return translationService.t('completed_status');
      case '8':
      case 'cancelled':
      case 'canceled':
        return translationService.t('cancelled_status');
      default:
        return booking.status;
    }
  }

  Color _resolveOrderStatusColor(Booking booking) {
    final display =
        booking.raw['status_display']?.toString().toLowerCase() ?? '';
    if (display.contains('ملغي') || display.contains('cancel')) {
      return const Color(0xFFEF4444);
    }
    switch (booking.status.toLowerCase()) {
      case '1':
      case 'pending':
      case 'confirmed':
        return const Color(0xFFF59E0B);
      case '2':
      case 'started':
        return const Color(0xFF3B82F6);
      case '3':
        return const Color(0xFF22C55E);
      case '4':
      case 'preparing':
      case 'processing':
        return const Color(0xFF3B82F6);
      case '5':
      case 'ready':
      case 'ready_for_delivery':
        return const Color(0xFF16A34A);
      case '6':
      case 'on_the_way':
      case 'out_for_delivery':
        return const Color(0xFF0EA5E9);
      case '7':
      case 'finished':
      case 'done':
      case 'completed':
        return const Color(0xFF15803D);
      case '8':
      case 'cancelled':
      case 'canceled':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF64748B);
    }
  }
}
