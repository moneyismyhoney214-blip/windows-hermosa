// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, library_private_types_in_public_api
part of '../orders_screen.dart';

extension OrdersScreenLifecycle on _OrdersScreenState {
  void _onBookingScroll() {
    if (_bookingScrollController.position.pixels >=
            _bookingScrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMoreBookings) {
      _loadMoreData();
    }
  }

  void _onLanguageChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    // 3s cadence keeps salon bookings snappy (they don't fan out through KDS
    // WebSocket, so HTTP is their only refresh signal). Restaurant orders also
    // refresh via DisplayAppService.addOrderStatusListener — see initState.
    // _refreshOrdersRealtime self-guards via _isRealtimeRefreshing, so a slow
    // backend won't queue up overlapping requests.
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_refreshOrdersRealtime());
    });
  }

  Future<void> _refreshOrdersRealtime() async {
    if (!mounted ||
        _isLoading ||
        _isLoadingMore ||
        _isRealtimeRefreshing ||
        _error != null) {
      return;
    }

    _isRealtimeRefreshing = true;
    try {
      _syncSearchQueryFromInput(normalizeController: true);
      final todayDateStr = _todayForApi();
      final orderIdSearch = _orderIdSearchValue;

      Future<Map<String, dynamic>> bookingsFuture;
      if (orderIdSearch.isNotEmpty) {
        bookingsFuture = _loadBookingsForOrderSearch(
          orderIdSearch: orderIdSearch,
          dateFromStr: todayDateStr,
          dateToStr: todayDateStr,
        );
      } else {
        bookingsFuture = _orderService.getBookings(
          page: 1,
          dateFrom: todayDateStr,
          dateTo: todayDateStr,
          search: _searchQueryForApi.isEmpty ? null : _searchQueryForApi,
          status: _selectedStatus == 'all' ? null : _selectedStatus,
        );
      }

      final bookingsResponse = await bookingsFuture;
      _processBookings(bookingsResponse, append: false);
      if (!mounted) return;

      setState(() {
        _selectedBookingIds
            .removeWhere((id) => !_bookings.any((booking) => booking.id == id));
      });
    } catch (_) {
      // Keep UI silent for periodic refresh failures.
    } finally {
      _isRealtimeRefreshing = false;
    }
  }
}
