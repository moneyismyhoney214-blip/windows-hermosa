// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../orders_screen.dart';

extension OrdersScreenProcessing on _OrdersScreenState {
  void _processBookings(dynamic response, {required bool append}) {
    if (response is Map<String, dynamic>) {
      _bookingsRawResponse = response;
    }
    final list = _extractListResponse(response);
    List<Booking> newItems = (list is List)
        ? list
            .whereType<Map>()
            .map((e) => Booking.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : [];

    // Ensure order-number search works even if backend search behavior varies.
    if (_isOrderNumberSearch && _searchQueryForApi.isNotEmpty) {
      final digits = _searchQueryForApi;
      newItems = newItems.where((booking) {
        final orderId = booking.orderId?.toString() ?? '';
        final id = booking.id.toString();
        final orderNumber =
            (booking.orderNumber ?? '').replaceAll(RegExp(r'[^0-9]'), '');
        final bookingNumber =
            (booking.bookingNumber ?? '').replaceAll(RegExp(r'[^0-9]'), '');

        // Exact match for order search to avoid collisions with booking IDs.
        return orderId == digits ||
            id == digits ||
            orderNumber == digits ||
            bookingNumber == digits;
      }).toList();
    }

    final totalCount = _extractTotalCount(response);

    // Salon-only: when we've already learned (via SalonInvoiceCreatedEvent
    // or the cross-ref scan) that a booking is invoiced, force its
    // status/status_display to the "انتهي" state so the list paint never
    // briefly shows "حجز مؤكد" while the backend lags ~1s before
    // propagating status=3 in the LIST response. This kills the
    // "card flips to انتهي a second later" flicker.
    if (ApiConstants.branchModule == 'salons' &&
        _bookingIdsWithInvoice.isNotEmpty) {
      for (final booking in newItems) {
        if (_bookingIdsWithInvoice.contains(booking.id)) {
          booking.raw['status'] = 3;
          booking.raw['status_display'] = 'انتهي';
          booking.raw['has_invoice'] = true;
        }
      }
    }

    // Salon-only: enforce strict separation between Bookings, Pending
    // Invoices and Posted Invoices. The /bookings endpoint returns:
    //   - real appointments (`book_appointment=true`) → Bookings tab
    //   - pay-later orders awaiting invoice (`book_appointment=false`,
    //     status=1) → Pending Invoices tab (this screen)
    //   - finalised orders (status=3 "انتهي" or status=7 "مكتمل", with
    //     `invoice_id` set on the detail endpoint) → Posted Invoices tab
    // Without this filter the same customer (e.g. مريم المازني) shows up
    // in both the Bookings tab AND the Pending Invoices tab, and stays in
    // Pending after the cashier clicks "Create Invoice".
    if (ApiConstants.branchModule == 'salons') {
      newItems = newItems.where((booking) {
        if (booking.raw['book_appointment'] == true) return false;
        if (_bookingHasInvoice(booking)) return false;
        if (_bookingIdsWithInvoice.contains(booking.id)) return false;
        if (_isBookingPaid(booking)) return false;
        return true;
      }).toList();
    }

    if (mounted) {
      setState(() {
        if (append) {
          _bookings.addAll(newItems);
        } else {
          _bookings = newItems;
        }

        final visibleCount = _bookings.length;

        if (totalCount != null) {
          _hasMoreBookings = visibleCount < totalCount;
        } else {
          _hasMoreBookings = newItems.length >= 20;
        }
      });
    }
  }

  int? _extractTotalCount(dynamic response) {
    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    Map<String, dynamic>? asMap(dynamic value) {
      if (value is Map<String, dynamic>) return value;
      if (value is Map) {
        return value.map((k, v) => MapEntry(k.toString(), v));
      }
      return null;
    }

    final root = asMap(response);
    if (root == null) return null;

    final rootKeys = ['total', 'count', 'records_total', 'recordsTotal'];
    for (final key in rootKeys) {
      final parsed = parseInt(root[key]);
      if (parsed != null && parsed >= 0) return parsed;
    }

    final data = asMap(root['data']);
    if (data != null) {
      for (final key in rootKeys) {
        final parsed = parseInt(data[key]);
        if (parsed != null && parsed >= 0) return parsed;
      }
    }

    final pagination = asMap(root['pagination']) ?? asMap(data?['pagination']);
    if (pagination != null) {
      final parsed = parseInt(pagination['total']);
      if (parsed != null && parsed >= 0) return parsed;
    }

    final meta = asMap(root['meta']) ?? asMap(data?['meta']);
    if (meta != null) {
      final parsed = parseInt(meta['total']);
      if (parsed != null && parsed >= 0) return parsed;
    }

    return null;
  }
}
