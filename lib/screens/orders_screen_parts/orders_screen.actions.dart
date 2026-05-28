// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, library_private_types_in_public_api
part of '../orders_screen.dart';

extension OrdersScreenActions on _OrdersScreenState {
  /// Mirror Orders-screen booking mutation to the waiter mesh; no-op for non-table bookings.
  void _mirrorBookingTableState(Booking booking, {required bool reserved}) {
    final tableId = booking.tableId;
    if (tableId == null) return;
    try {
      getIt<CashierMeshBootstrap>().broadcastCashierTableState(
        tableId: tableId.toString(),
        tableNumber: booking.tableName ?? '',
        reserved: reserved,
        bookingId: reserved ? booking.id.toString() : null,
      );
    } catch (e) {
      Log.d('OrdersScreenActions', 'broadcast table state to mesh failed (non-fatal): $e');
    }
  }

  Future<void> _cancelBooking(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(translationService.t('cancel_booking_title')),
        content: Text(translationService.t('confirm_cancel_this_booking_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(translationService.t('no')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: Text(translationService.t('yes_cancel')),
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

      if (widget.onPrintOrderChanges != null) {
        try {
          final details = await _orderService.getBookingDetails(booking.id.toString());
          final detailData = details['data'] is Map
              ? (details['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
              : details;
          final bookingNode = detailData['booking'] is Map
              ? (detailData['booking'] as Map).map((k, v) => MapEntry(k.toString(), v))
              : detailData;

          final mealsList = (bookingNode['booking_services'] ??
                  bookingNode['booking_meals'] ??
                  bookingNode['meals'] ??
                  bookingNode['items'] ??
                  detailData['booking_services'] ??
                  detailData['booking_meals']) as List?;
          if (mealsList != null && mealsList.isNotEmpty) {
            final cancelChanges = mealsList.map((meal) {
              final m = meal is Map ? meal.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};
              final name = m['service_name']?.toString() ??
                  m['meal_name']?.toString() ??
                  m['name']?.toString() ??
                  m['item_name']?.toString() ??
                  '';
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

      // Free the table on every device immediately.
      _mirrorBookingTableState(booking, reserved: false);

      if (!mounted) return;
      UiFeedback.info(context, translationService.t('booking_cancelled_msg'));
      unawaited(_loadData());
    } catch (e) {
      if (!mounted) return;
      UiFeedback.info(context, translationService.t('cancel_booking_failed'));
    }
  }

  Future<void> _showBookingRefundDialog(Booking booking) async {
    final refundedPreTax = await showBookingRefundDialog(
      context: context,
      bookingId: booking.id.toString(),
      bookingLabel: _bookingReference(booking),
    );
    // Null = cancel; any non-null = refund happened (may be 0 for salon previews).
    if (refundedPreTax == null || !mounted) return;

    // Optimistic subtraction; recompute below overwrites with authoritative value.
    if (refundedPreTax > 0) {
      _bookingRefundedAmounts[booking.id] =
          (_bookingRefundedAmounts[booking.id] ?? 0) + refundedPreTax;
    }

    // Pull detail BEFORE _loadData so override is set before rebuild.
    await _refreshBookingRemainingFromDetail(booking);
    await _loadData();

    // Refresh again post-list in case list returned frozen totals.
    await _refreshBookingRemainingFromDetail(booking);
    if (mounted) setState(() {});
  }

  /// Lazy refresh of override map for stale salon list rows. Non-blocking; idempotent.
  void _scheduleBookingDetailRefresh(Booking booking) {
    if (_bookingRemainingPreTaxOverride.containsKey(booking.id)) return;
    if (_bookingDetailRefreshInFlight.contains(booking.id)) return;
    _bookingDetailRefreshInFlight.add(booking.id);
    Future.microtask(() async {
      try {
        await _refreshBookingRemainingFromDetail(booking);
        if (mounted) setState(() {});
      } finally {
        _bookingDetailRefreshInFlight.remove(booking.id);
      }
    });
  }

  Future<void> _refreshBookingRemainingFromDetail(Booking booking) async {
    try {
      final detail =
          await _orderService.getBookingDetails(booking.id.toString());
      final detailData = detail['data'];
      Map<String, dynamic>? detailMap;
      if (detailData is Map<String, dynamic>) {
        detailMap = detailData;
      } else if (detailData is Map) {
        detailMap = detailData.map((k, v) => MapEntry(k.toString(), v));
      }
      if (detailMap == null) return;

      final freshRows = <Map<String, dynamic>>[];
      for (final key in const [
        'booking_services',
        'booking_meals',
        'booking_products',
      ]) {
        final rows = detailMap[key];
        if (rows is! List) continue;
        for (final row in rows.whereType<Map>()) {
          // Skip soft-deleted (is_returned) rows so override matches outstanding items.
          final isReturned = row['is_returned'];
          if (isReturned == true ||
              isReturned == 1 ||
              isReturned == '1' ||
              isReturned == 'true') {
            continue;
          }
          freshRows.add(row.map((k, v) => MapEntry(k.toString(), v)));
        }
      }

      double remainingPreTax = 0;
      for (final row in freshRows) {
        remainingPreTax += _parseNum(row['total_price'] ??
            row['total'] ??
            row['price'] ??
            row['unit_price']);
      }

      if (freshRows.isNotEmpty) {
        _bookingItemsOverride[booking.id] = freshRows;
      } else {
        _bookingItemsOverride.remove(booking.id);
      }
      _bookingRemainingPreTaxOverride[booking.id] = remainingPreTax;

      // Keep legacy refunded-amount tracker in sync as a fallback path.
      final originalPreTax = _bookingOriginalTotal(booking);
      if (originalPreTax > 0) {
        _bookingRefundedAmounts[booking.id] =
            (originalPreTax - remainingPreTax).clamp(0.0, originalPreTax);
      }
    } catch (e) {
      Log.d('OrdersScreenActions', 'reconcile booking refunded amount failed (non-fatal): $e');
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
    if (raw.isEmpty) return translationService.t('no_date_label');
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('yyyy-MM-dd HH:mm').format(parsed);
  }

  double _bookingGrandTotal(Booking booking) {
    final raw = booking.raw;
    // Use branch tax rate (not hardcoded 15%) so untaxed branches display raw amount.
    final branchService = getIt<BranchService>();
    final taxRate = branchService.cachedHasTax ? branchService.cachedTaxRate : 0.0;
    final taxMultiplier = 1.0 + taxRate;

    // Backend keeps totals frozen post-refund; override (from detail) is authoritative.
    final override = _bookingRemainingPreTaxOverride[booking.id];
    if (override != null) {
      return override * taxMultiplier;
    }

    // Cancelled bookings (status=8) keep original total_price on list even with empty booking_services.
    final isSalon = ApiConstants.branchModule == 'salons';
    final statusStr = booking.status.trim().toLowerCase();
    final isCancelled = statusStr == '8' ||
        statusStr == 'cancelled' ||
        statusStr == 'canceled';
    if (isSalon && isCancelled) return 0.0;
    if (isSalon && raw['has_cancelled'] == true) {
      _scheduleBookingDetailRefresh(booking);
    }

    double base;
    // Priority: grand_total → total+tax → sum(meals)*taxMultiplier → total*taxMultiplier.
    final gt = double.tryParse(raw['grand_total']?.toString() ?? '');
    if (gt != null && gt > 0) {
      base = gt;
    } else if (booking.tax > 0) {
      base = booking.total + booking.tax;
    } else if (booking.meals.isNotEmpty) {
      double sum = 0;
      for (final meal in booking.meals) {
        sum += meal.total > 0 ? meal.total : (meal.unitPrice * meal.quantity);
      }
      base = sum > 0 ? sum * taxMultiplier : booking.total;
    } else if (booking.total > 0) {
      base = booking.total * taxMultiplier;
    } else {
      base = booking.total;
    }
    // Subtract locally tracked refunds (pre-tax → gross up by same rate).
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
        return translationService.t('confirmed_booking_label');
      case '2':
      case 'started':
        return translationService.t('started_label');
      case '3':
        return translationService.t('ended_label');
      case '4':
      case 'preparing':
      case 'processing':
        return translationService.t('preparing_status');
      case '5':
      case 'ready':
      case 'ready_for_delivery':
        return translationService.t('ready_for_delivery');
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
