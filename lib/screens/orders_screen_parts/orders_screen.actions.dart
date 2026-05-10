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
    // The dialog returns null on cancel and a non-null value (possibly 0 for
    // salon previews that omit prices) when a refund actually happened.
    // Refresh on any non-null return so the displayed total reflects reality.
    if (refundedPreTax == null || !mounted) return;

    // Optimistically subtract the dialog-reported amount so the total drops
    // even if the recompute below fails (network/parse error). The recompute
    // overwrites this with the authoritative value from booking_services.
    if (refundedPreTax > 0) {
      _bookingRefundedAmounts[booking.id] =
          (_bookingRefundedAmounts[booking.id] ?? 0) + refundedPreTax;
    }

    // Pull the booking detail BEFORE _loadData so the remaining-items
    // override is in place by the time the list rebuilds. The list endpoint
    // can lag the detail endpoint and may not even include
    // `booking_services` / `booking_meals` in its rows, so for salons the
    // detail endpoint is the only authoritative source for the post-refund
    // state.
    await _refreshBookingRemainingFromDetail(booking);
    await _loadData();

    // After _loadData, refresh once more in case the list endpoint still
    // returned the frozen totals — the override map is keyed by booking id
    // and survives the rebuild, so the card + invoice flow keep using
    // the up-to-date numbers.
    await _refreshBookingRemainingFromDetail(booking);
    if (mounted) setState(() {});
  }

  /// Lazily refresh `_bookingRemainingPreTaxOverride` for a booking whose
  /// list-side `total_price` is known to be stale (salon `has_cancelled`).
  /// Skips when a refresh is already in flight or when an override is
  /// already cached. Called from build paths, so it must NOT block.
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
          // Restaurant refunds soft-delete via `is_returned`; skip those
          // rows so the override matches the actual outstanding items.
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

      // Reconcile the legacy refunded-amount tracker so the existing
      // grand-total subtraction path also stays in sync if the override
      // ever isn't consulted.
      final originalPreTax = _bookingOriginalTotal(booking);
      if (originalPreTax > 0) {
        _bookingRefundedAmounts[booking.id] =
            (originalPreTax - remainingPreTax).clamp(0.0, originalPreTax);
      }
    } catch (_) {}
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

    // After a refund the backend keeps `total_price` / `grand_total` frozen.
    // Trust the per-booking override populated from booking-detail when it
    // exists — that's the authoritative remaining-items pre-tax sum.
    final override = _bookingRemainingPreTaxOverride[booking.id];
    if (override != null) {
      return override * taxMultiplier;
    }

    // Cancelled bookings (status=8) keep their original `total_price` on
    // the list endpoint even though every booking_service is gone — without
    // this short-circuit the card showed e.g. 700 SAR for a fully cancelled
    // booking. Verified against booking 443600/443602 on a.lamal salon
    // (status=8, total_price=608.7, booking_services=[]). For salon
    // bookings flagged `has_cancelled=true` (partial-or-full cancellation)
    // we trigger a background detail fetch — once it completes the
    // override path above takes over with the real remaining sum.
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
