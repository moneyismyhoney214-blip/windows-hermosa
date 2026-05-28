// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, library_private_types_in_public_api
part of '../orders_screen.dart';

extension OrdersScreenHelpers on _OrdersScreenState {
  String get _langCode =>
      translationService.currentLanguageCode.trim().toLowerCase();
  bool get _useArabicUi =>
      _langCode.startsWith('ar') || _langCode.startsWith('ur');
  String _tr(String ar, String nonArabic) => _useArabicUi ? ar : nonArabic;

  bool get _isOrderNumberSearch =>
      RegExp(r'^#?\d+$').hasMatch(_searchQuery.trim());

  String get _orderIdSearchValue {
    if (!_isOrderNumberSearch) return '';
    return _normalizeDigits(_searchQuery.trim().replaceAll('#', ''));
  }

  String get _searchQueryForApi {
    final query = _normalizeDigits(_searchQuery.trim());
    if (query.isEmpty) return '';
    if (_isOrderNumberSearch) {
      return query.replaceAll('#', '');
    }
    return query;
  }

  String _normalizeDigits(String value) {
    if (value.isEmpty) return value;
    const easternArabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const arabicIndic = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    var normalized = value;
    for (var i = 0; i < 10; i++) {
      normalized = normalized.replaceAll(easternArabic[i], '$i');
      normalized = normalized.replaceAll(arabicIndic[i], '$i');
    }
    return normalized;
  }

  String _digitsOnly(String value) =>
      _normalizeDigits(value).replaceAll(RegExp(r'[^0-9]'), '').trim();

  String _bookingReference(Booking booking) {
    final orderId = booking.orderId;
    // Priority: orderNumber → orderId → bookingNumber (strip BOK-) → booking.id.
    final orderNumber = booking.orderNumber?.trim();
    if (orderNumber != null && orderNumber.isNotEmpty && orderNumber != '0') {
      return orderNumber.startsWith('#') ? orderNumber : '#$orderNumber';
    }
    if (orderId != null && orderId > 0) {
      return '#$orderId';
    }
    final bookingNumber = booking.bookingNumber?.trim();
    if (bookingNumber != null &&
        bookingNumber.isNotEmpty &&
        bookingNumber != '0') {
      final cleaned = bookingNumber.replaceAll(
          RegExp(r'#?BOK-?', caseSensitive: false), '');
      return cleaned.startsWith('#') ? cleaned : '#$cleaned';
    }
    return '#${booking.id}';
  }

  bool _bookingHasInvoice(Booking booking) {
    final raw = booking.raw;
    bool hasValue(dynamic value) {
      final text = value?.toString().trim().toLowerCase() ?? '';
      return text.isNotEmpty && text != 'null' && text != '0';
    }

    final hasInvoiceFlag = raw['has_invoice'] == true ||
        raw['has_invoice'] == 1 ||
        raw['has_invoice'] == '1';
    final hasInvoiceId =
        hasValue(raw['invoice_id']) || hasValue(raw['invoice_number']);
    final hasBookingInvoiceId =
        hasValue(raw['invoice'] is Map ? (raw['invoice'] as Map)['id'] : null);

    // Salon bookings-list lacks invoice signals; status=3/"انتهي"/"finished" is the only immediate marker.
    if (ApiConstants.branchModule == 'salons') {
      final statusValue = raw['status'];
      final statusInt = statusValue is int
          ? statusValue
          : int.tryParse(statusValue?.toString() ?? '');
      if (statusInt == 3) return true;
      final display = raw['status_display']?.toString().trim() ?? '';
      if (display.contains('انتهي') ||
          display.toLowerCase().contains('finished') ||
          display.toLowerCase().contains('done')) {
        return true;
      }
    }

    return hasInvoiceFlag || hasInvoiceId || hasBookingInvoiceId;
  }

  /// Salon pay-now stays at status=1; detect paid via pays/paid/status_display.
  bool _isBookingPaid(Booking booking) {
    if (booking.isPaid) return true;
    final raw = booking.raw;

    bool truthy(dynamic value) {
      if (value == true) return true;
      if (value is num) return value != 0;
      final text = value?.toString().trim().toLowerCase() ?? '';
      if (text.isEmpty || text == 'null' || text == 'false' || text == '0') {
        return false;
      }
      return true;
    }

    if (truthy(raw['is_paid']) || truthy(raw['paid_at'])) return true;

    final paidValue = raw['paid'];
    if (paidValue is num && paidValue > 0) return true;
    if (paidValue is String) {
      final parsed = double.tryParse(paidValue.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (parsed != null && parsed > 0) return true;
    }

    final pays = raw['pays'];
    if (pays is List && pays.isNotEmpty) return true;
    if (pays is String && pays.trim().isNotEmpty) return true;

    final paymentMethods = raw['payment_methods'];
    if (paymentMethods is String && paymentMethods.trim().isNotEmpty) {
      return true;
    }

    // Salon list rows expose status_display "تم الدفع"/"Paid" alongside status=1.
    final display = raw['status_display']?.toString().trim() ?? '';
    if (display.isNotEmpty) {
      final lower = display.toLowerCase();
      if (lower.contains('paid') ||
          lower.contains('settled') ||
          display.contains('تم الدفع') ||
          display.contains('مدفوع')) {
        return true;
      }
    }

    return false;
  }

  bool _isBookingCancelled(Booking booking) {
    final normalized = booking.status.trim().toLowerCase();
    return normalized == '8' ||
        normalized == 'cancelled' ||
        normalized == 'canceled';
  }

  bool _canCreateInvoiceForBooking(Booking booking) {
    if (_isBookingCancelled(booking)) return false;
    if (_isBookingPaid(booking)) return false;
    if (_bookingHasInvoice(booking)) return false;
    // Cross-reference scan masks salon pay-now bookings with missing list signals.
    if (_bookingIdsWithInvoice.contains(booking.id)) return false;
    // Guard against fully-refunded bookings still at status=1 (would 422 on create).
    final remaining = _bookingRemainingPreTaxOverride[booking.id];
    if (remaining != null && remaining <= 0) return false;
    final overrideItems = _bookingItemsOverride[booking.id];
    if (overrideItems != null && overrideItems.isEmpty) return false;
    return true;
  }

  bool _matchesOrderSearch(Booking booking, String digits) {
    final orderId = booking.orderId?.toString() ?? '';
    final bookingId = booking.id.toString();
    final orderNumberDigits = _digitsOnly(booking.orderNumber ?? '');
    final bookingNumberDigits = _digitsOnly(booking.bookingNumber ?? '');

    return orderId == digits ||
        bookingId == digits ||
        orderNumberDigits == digits ||
        bookingNumberDigits == digits;
  }

  List<Booking> _bookingsFromResponse(dynamic response) {
    final list = _extractListResponse(response);
    if (list is! List) return const <Booking>[];
    return list
        .whereType<Map>()
        .map((e) => Booking.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Map<String, dynamic> _buildSearchResponseFromMatches(List<Booking> matches) {
    return <String, dynamic>{
      'status': 200,
      'message': 'order_id_local_search',
      'data': matches.map((booking) => booking.raw).toList(),
      'meta': {'total': matches.length},
    };
  }

  String _todayForApi() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  void _syncSearchQueryFromInput({bool normalizeController = false}) {
    final raw = _normalizeDigits(_searchController.text.trim());
    if (raw.isEmpty) {
      _searchQuery = '';
      return;
    }

    final compact = raw.replaceAll(' ', '');
    final isOrderInput = RegExp(r'^#?\d+$').hasMatch(compact);
    if (!isOrderInput) {
      _searchQuery = raw;
      return;
    }

    final normalized = '#${compact.replaceAll('#', '')}';
    _searchQuery = normalized;

    if (normalizeController && _searchController.text.trim() != normalized) {
      _searchController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }
  }

  /// Cache key for persistent invoice→booking map; keyed by branch + day.
  String _salonInvoiceLinkCacheKey(String dateStr) =>
      'salon_invoice_booking_link_${ApiConstants.branchId}_$dateStr';

  /// Hydrate `_bookingIdsWithInvoice` from disk so buttons hide on first paint.
  Future<void> _hydrateSalonInvoiceLinkFromCache(String dateStr) async {
    try {
      final cached = await _cache.get(_salonInvoiceLinkCacheKey(dateStr));
      if (cached is! Map) return;
      final discovered = <int>{};
      cached.forEach((_, value) {
        final parsed = value is int
            ? value
            : int.tryParse(value?.toString() ?? '');
        if (parsed != null && parsed > 0) discovered.add(parsed);
      });
      if (discovered.isEmpty || !mounted) return;
      setState(() {
        _bookingIdsWithInvoice.addAll(discovered);
        // Drop already-invoiced bookings — they belong in Posted Invoices, not Pending.
        _bookings.removeWhere(
            (booking) => _bookingIdsWithInvoice.contains(booking.id));
      });
    } catch (e) {
      Log.d('OrdersScreenHelpers', 'scan-for-existing-invoices failed (non-fatal): $e');
    }
  }

  /// Salon-only invoice→booking cross-reference: cache → invoice list → parallel detail
  /// fetches (booking_id lives only on invoice detail). Progressive setState; persists merged map.
  Future<void> _kickOffSalonInvoiceCrossRef(String todayDateStr) async {
    if (_invoiceCrossRefInFlight) return;
    _invoiceCrossRefInFlight = true;
    try {
      // Step 1: load persisted map { invoiceId: bookingId, ... }.
      final cacheKey = _salonInvoiceLinkCacheKey(todayDateStr);
      final cachedRaw = await _cache.get(cacheKey);
      final invoiceToBooking = <int, int>{};
      if (cachedRaw is Map) {
        cachedRaw.forEach((k, v) {
          final invId = int.tryParse(k.toString());
          final bookingId =
              v is int ? v : int.tryParse(v?.toString() ?? '');
          if (invId != null &&
              invId > 0 &&
              bookingId != null &&
              bookingId > 0) {
            invoiceToBooking[invId] = bookingId;
          }
        });
      }

      // Step 2: collect today's invoice IDs.
      final invoiceIds = <int>{};
      const maxPages = 2;
      for (var page = 1; page <= maxPages; page++) {
        Map<String, dynamic> response;
        try {
          response = await _orderService.getInvoices(
            page: page,
            perPage: 50,
            dateFrom: todayDateStr,
            dateTo: todayDateStr,
          );
        } catch (e) {
          Log.d('catch', 'non-fatal: $e');
          break;
        }
        final list = _extractListResponse(response);
        if (list is! List || list.isEmpty) break;
        for (final entry in list.whereType<Map>()) {
          final m = entry.map((k, v) => MapEntry(k.toString(), v));
          final invoiceIdRaw = m['id'];
          final invoiceId = invoiceIdRaw is int
              ? invoiceIdRaw
              : int.tryParse(invoiceIdRaw?.toString() ?? '');
          if (invoiceId != null && invoiceId > 0) {
            invoiceIds.add(invoiceId);
          }
        }
        if (list.length < 50) break;
      }

      // Step 3: fetch details for unmapped invoices only.
      final pending = invoiceIds
          .where((id) => !invoiceToBooking.containsKey(id))
          .toList(growable: false);
      // Concurrency of 6 is comfortable with the backend rate limiter.
      const maxConcurrent = 6;
      var changedThisRun = false;
      for (var i = 0; i < pending.length; i += maxConcurrent) {
        final batch = pending.skip(i).take(maxConcurrent).toList();
        final results = await Future.wait<MapEntry<int, int>?>(
          batch.map((invoiceId) async {
            try {
              final detail =
                  await _orderService.getInvoice(invoiceId.toString());
              final data = detail['data'];
              final dataMap = data is Map
                  ? data.map((k, v) => MapEntry(k.toString(), v))
                  : <String, dynamic>{};
              // Salon detail nests booking_id at the envelope top level.
              final raw = dataMap['booking_id'] ??
                  (dataMap['booking'] is Map
                      ? (dataMap['booking'] as Map)['id']
                      : null);
              if (raw == null) return null;
              final bookingId =
                  raw is int ? raw : int.tryParse(raw.toString());
              if (bookingId == null || bookingId <= 0) return null;
              return MapEntry(invoiceId, bookingId);
            } catch (e) {
              Log.d('catch', 'non-fatal: $e');
              return null;
            }
          }),
          eagerError: false,
        );
        final discoveredThisBatch = <int>{};
        for (final entry in results) {
          if (entry == null) continue;
          invoiceToBooking[entry.key] = entry.value;
          discoveredThisBatch.add(entry.value);
        }
        if (discoveredThisBatch.isNotEmpty && mounted) {
          setState(() {
            _bookingIdsWithInvoice.addAll(discoveredThisBatch);
            _bookings.removeWhere(
                (booking) => discoveredThisBatch.contains(booking.id));
          });
          changedThisRun = true;
        }
      }

      // Step 4: merge cached entries (handles late hydration race).
      if (mounted && invoiceToBooking.isNotEmpty) {
        final allIds = invoiceToBooking.values.toSet();
        if (!_bookingIdsWithInvoice.containsAll(allIds)) {
          setState(() {
            _bookingIdsWithInvoice.addAll(allIds);
            _bookings.removeWhere(
                (booking) => _bookingIdsWithInvoice.contains(booking.id));
          });
        }
      }

      // Step 5: persist merged map with 6h expiry.
      if (changedThisRun || (cachedRaw == null && invoiceToBooking.isNotEmpty)) {
        await _cache.set(
          cacheKey,
          invoiceToBooking
              .map((k, v) => MapEntry(k.toString(), v)),
          expiry: const Duration(hours: 6),
        );
      }
    } finally {
      _invoiceCrossRefInFlight = false;
    }
  }

  /// Match backend's "booking_id already used" 422 strictly (avoid false positives).
  bool _isBookingAlreadyInvoiced422(Object error) {
    final text = error.toString();
    final lower = text.toLowerCase();
    if (!lower.contains('422')) return false;
    return text.contains('قيمة الحقل رقم الحجز مُستخدمة من قبل') ||
        text.contains('booking_id') &&
            (lower.contains('already used') ||
                lower.contains('already taken') ||
                lower.contains('used before'));
  }
}
