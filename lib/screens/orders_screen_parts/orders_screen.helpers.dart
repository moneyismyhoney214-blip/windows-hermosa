// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
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
    // Priority 1: Use orderNumber if available (daily_order_number from API)
    final orderNumber = booking.orderNumber?.trim();
    if (orderNumber != null && orderNumber.isNotEmpty && orderNumber != '0') {
      return orderNumber.startsWith('#') ? orderNumber : '#$orderNumber';
    }
    // Priority 2: Use orderId if available
    if (orderId != null && orderId > 0) {
      return '#$orderId';
    }
    // Priority 3: Use bookingNumber if available (but strip BOK- prefix)
    final bookingNumber = booking.bookingNumber?.trim();
    if (bookingNumber != null &&
        bookingNumber.isNotEmpty &&
        bookingNumber != '0') {
      // Remove BOK- prefix if present to show cleaner number
      final cleaned = bookingNumber.replaceAll(
          RegExp(r'#?BOK-?', caseSensitive: false), '');
      return cleaned.startsWith('#') ? cleaned : '#$cleaned';
    }
    // Fallback: Use booking.id
    // Note: Backend should provide daily_order_number in /bookings endpoint
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
    return hasInvoiceFlag || hasInvoiceId || hasBookingInvoiceId;
  }

  bool _isBookingCancelled(Booking booking) {
    final normalized = booking.status.trim().toLowerCase();
    return normalized == '8' ||
        normalized == 'cancelled' ||
        normalized == 'canceled';
  }

  bool _canCreateInvoiceForBooking(Booking booking) {
    if (_isBookingCancelled(booking)) return false;
    if (booking.isPaid) return false;
    if (_bookingHasInvoice(booking)) return false;
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
}
