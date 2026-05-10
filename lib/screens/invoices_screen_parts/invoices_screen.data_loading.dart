// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../invoices_screen.dart';

extension InvoicesScreenDataLoading on _InvoicesScreenState {
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_isLoading && !_isLoadingMore && mounted) {
        _loadInvoices(reset: true);
      }
    });
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || _isLoading) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadInvoices(reset: false);
    }
  }

  Future<void> _loadInvoices({required bool reset}) async {
    final todayDate = _todayForApi();
    final shouldReset = reset || _activeDate != todayDate;
    if (_activeDate != todayDate) {
      _activeDate = todayDate;
    }

    final isSalonMode = ApiConstants.branchModule == 'salons';

    // PERF (salon-only): on a fresh load, paint the cached page-1 response
    // immediately so the user doesn't stare at a 10-second spinner waiting
    // for the slow `/seller/branches/{id}/invoices` round-trip. Restaurant
    // module keeps the original "spinner-first" UX so its flow is untouched.
    Map<String, dynamic>? salonCached;
    // One-shot bypass: if main_screen just created an invoice, the cached
    // page would render WITHOUT it for the few seconds the API takes —
    // confusing for the user. Skip the cache once and go straight to the
    // API (which will include the new invoice).
    final skipSalonCache = isSalonMode && _skipSalonCacheOnNextLoad;
    if (skipSalonCache) {
      _skipSalonCacheOnNextLoad = false;
    }
    if (shouldReset && isSalonMode && !skipSalonCache) {
      try {
        salonCached = await _orderService.getCachedInvoices(
          dateFrom: _activeDate,
          dateTo: _activeDate,
        );
      } catch (_) {
        salonCached = null;
      }
    }

    if (shouldReset) {
      setState(() {
        _error = null;
        _page = 1;
        _hasMore = true;
        if (salonCached != null) {
          // Cache hit — show stale list now, refresh proceeds below.
          _isLoading = false;
        } else {
          _isLoading = true;
        }
      });
      if (salonCached != null) {
        final cachedInvoices = _invoicesFromResponse(salonCached);
        if (mounted && cachedInvoices.isNotEmpty) {
          setState(() {
            _invoices = cachedInvoices;
            _hasMore = _resolveHasMore(salonCached!, cachedInvoices.length);
          });
        }
      }
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      final response = await _orderService.getInvoices(
        dateFrom: _activeDate,
        dateTo: _activeDate,
        search: _resolveApiSearchQuery(),
        page: _page,
        perPage: _perPage,
      );

      final nextInvoices = _invoicesFromResponse(response);
      final hasMore = _resolveHasMore(response, nextInvoices.length);

      if (!mounted) return;
      setState(() {
        if (shouldReset) {
          _invoices = nextInvoices;
        } else {
          _invoices = [..._invoices, ...nextInvoices];
        }
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = hasMore;
        if (_hasMore) _page += 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        // Preserve any cached/optimistic data we already painted — only
        // surface the error when we have nothing to show.
        if (_invoices.isEmpty) {
          _error = e.toString();
        }
      });
    }
  }

  List<Invoice> _invoicesFromResponse(dynamic response) {
    final list = _extractListResponse(response);
    if (list is! List) return const <Invoice>[];
    return list
        .whereType<Map>()
        .map((e) => Invoice.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  dynamic _extractListResponse(dynamic response) {
    if (response is List) return response;
    if (response is Map) {
      final direct = response['data'];
      if (direct is List) return direct;
      if (direct is Map && direct['data'] is List) {
        return direct['data'];
      }
    }
    return const [];
  }

  bool _resolveHasMore(dynamic response, int fetchedCount) {
    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value.toString());
    }

    if (response is Map) {
      final meta = response['meta'] is Map ? response['meta'] as Map : null;
      if (meta != null) {
        final current = parseInt(meta['current_page']);
        final last = parseInt(meta['last_page']);
        if (current != null && last != null) {
          return current < last;
        }
      }
      final data = response['data'];
      if (data is Map) {
        final meta = data['meta'] is Map ? data['meta'] as Map : null;
        if (meta != null) {
          final current = parseInt(meta['current_page']);
          final last = parseInt(meta['last_page']);
          if (current != null && last != null) {
            return current < last;
          }
        }
      }
    }

    return fetchedCount >= _perPage;
  }

}
