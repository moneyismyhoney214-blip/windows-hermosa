import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../dialogs/booking_details_dialog.dart';
import '../dialogs/create_booking_dialog.dart';
import '../services/api/api_constants.dart';
import '../services/api/base_client.dart';
import '../services/app_themes.dart';
import '../services/language_service.dart';
import '../services/logger_service.dart';
import '../utils/ui_feedback.dart';

/// Salon Bookings management screen.
///
/// Mirrors the `/seller/branches/{id}/bookings` flow captured in the salon
/// dashboard HAR: a paginated list filtered by status + date range with
/// a "create booking" entry point that opens the appointment / pay-later
/// composer ([CreateBookingDialog]).
class BookingsScreen extends StatefulWidget {
  final VoidCallback onBack;

  /// Optional hook fired after a successful booking creation so the host
  /// (main_screen) can dispatch salon turn tickets. Null disables the
  /// auto-print and the screen falls back to a passive snackbar.
  final Future<void> Function(String orderId, Map<String, dynamic> bookingData)?
      onPrintSalonTurnTicket;

  const BookingsScreen({
    super.key,
    required this.onBack,
    this.onPrintSalonTurnTicket,
  });

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  final BaseClient _client = BaseClient();
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _amountFormatter = NumberFormat('#,##0.##');

  List<Map<String, dynamic>> _bookings = [];
  bool _isLoading = true;
  String? _error;

  // Filters mirror the HAR query string minus status (client-side `book_appointment:true` filter).
  DateTime _dateFrom = DateTime.now();
  DateTime _dateTo = DateTime.now();
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    translationService.addListener(_onLanguageChanged);
    _loadBookings();
  }

  @override
  void dispose() {
    translationService.removeListener(_onLanguageChanged);
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadBookings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final fromStr = DateFormat('yyyy-MM-dd').format(_dateFrom);
      final toStr = DateFormat('yyyy-MM-dd').format(_dateTo);
      final search = Uri.encodeQueryComponent(_searchQuery);
      final endpoint = '${ApiConstants.bookingsEndpoint}'
          '?platform=&date_from=$fromStr&date_to=$toStr'
          '&search=$search';

      final response = await _client.get(endpoint);
      final raw = response is Map<String, dynamic> ? response['data'] : null;
      // Keep only real appointments; pay-later orders live in the pending-invoices tab.
      final list = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .where((e) => e['book_appointment'] == true)
              .toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _bookings = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _searchQuery = value.trim());
      _loadBookings();
    });
  }

  Future<void> _pickDateRange() async {
    final initial = DateTimeRange(start: _dateFrom, end: _dateTo);
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _dateFrom = picked.start;
        _dateTo = picked.end;
      });
      unawaited(_loadBookings());
    }
  }

  Future<void> _openBookingDetails(Map<String, dynamic> booking) async {
    final id = booking['id']?.toString();
    if (id == null || id.isEmpty) return;

    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ));

    Map<String, dynamic>? full;
    String? err;
    try {
      final response = await _client.get(ApiConstants.bookingDetailsEndpoint(id));
      if (response is Map<String, dynamic>) {
        final data = response['data'];
        if (data is Map) {
          full = Map<String, dynamic>.from(data);
        }
      }
    } catch (e) {
      err = e.toString();
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (err != null || full == null) {
      UiFeedback.info(context, err ?? translationService.t('booking_details_load_failed'));
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => BookingDetailsDialog(bookingData: full!),
    );
  }

  Future<void> _openCreateBooking() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CreateBookingDialog(),
    );

    if (!mounted || result == null) return;
    final createdId = result['id']?.toString();
    final isAppointment = result['book_appointment'] == true;
    if (createdId != null && createdId.isNotEmpty) {
      _showSuccessSnack(createdId, isAppointment: isAppointment);

      // Print salon turn slips for both appointment + pay-later (alerts floor staff to the booking).
      final cb = widget.onPrintSalonTurnTicket;
      final responseData = result['data'];
      if (cb != null && responseData is Map) {
        final bookingMap = Map<String, dynamic>.from(responseData);
        // Re-fetch detail when booking_services is absent inline (slip needs per-service rows).
        Future<void> doPrint() async {
          Map<String, dynamic> printable = bookingMap;
          if (printable['booking_services'] is! List) {
            try {
              final response = await _client
                  .get(ApiConstants.bookingDetailsEndpoint(createdId));
              if (response is Map<String, dynamic>) {
                final inner = response['data'];
                if (inner is Map) {
                  printable = Map<String, dynamic>.from(inner);
                }
              }
            } catch (e) {
              Log.d('BookingsScreen', 'fetch booking details for print failed (non-fatal): $e');
            }
          }
          try {
            await cb(createdId, printable);
          } catch (e) {
            Log.d('BookingsScreen', 'post-booking-create print callback failed (non-fatal): $e');
          }
        }

        unawaited(doPrint());
      }
    }
    unawaited(_loadBookings());
  }

  void _showSuccessSnack(String id, {required bool isAppointment}) {
    final msg = isAppointment
        ? translationService.t('booking_created_n', args: {'id': id})
        : translationService.t('pay_later_order_created_n', args: {'id': id});
    UiFeedback.success(context, msg);
  }

  String _bookingDisplayNumber(Map<String, dynamic> booking) {
    final raw = (booking['booking_number'] ?? booking['id'])?.toString() ?? '';
    return raw.startsWith('#') ? raw.substring(1) : raw;
  }

  String _safe(dynamic v) {
    if (v == null) return '';
    return v.toString();
  }

  // Strip currency suffix and keep only first dot — Arabic "ر.س" contains a literal dot that breaks double.tryParse.
  double _parseAmount(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    var cleaned = v.toString().replaceAll(RegExp(r'[^\d.\-]'), '');
    final dotIndex = cleaned.indexOf('.');
    if (dotIndex >= 0) {
      cleaned = cleaned.substring(0, dotIndex + 1) +
          cleaned.substring(dotIndex + 1).replaceAll('.', '');
    }
    return double.tryParse(cleaned) ?? 0.0;
  }

  Color _statusColor(int status, bool cancelled) {
    if (cancelled) return const Color(0xFFEF4444);
    switch (status) {
      case 1:
        return const Color(0xFFF97316); // confirmed - orange
      case 2:
        return const Color(0xFF22C55E); // completed - green
      case 3:
        return const Color(0xFF6B7280); // archived - grey
      default:
        return const Color(0xFF3B82F6);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildFiltersBar(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildErrorView()
                      : _buildList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: context.appCardBg,
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onBack,
            icon: const Icon(LucideIcons.chevronRight, size: 24),
            color: const Color(0xFFF58220),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              translationService.t('bookings'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: context.appText,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _openCreateBooking,
            icon: const Icon(LucideIcons.plus, size: 18),
            label: Text(translationService.t('new_booking')),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF58220),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isLoading ? null : _loadBookings,
            icon: const Icon(LucideIcons.refreshCw, size: 20),
            tooltip: translationService.t('refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: context.appBg,
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(LucideIcons.calendar, size: 16),
            label: Text(
              '${DateFormat('yyyy-MM-dd').format(_dateFrom)} → '
              '${DateFormat('yyyy-MM-dd').format(_dateTo)}',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: translationService.t('search'),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                prefixIcon: const Icon(LucideIcons.search, size: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.alertCircle,
                color: Color(0xFFEF4444), size: 48),
            const SizedBox(height: 12),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appText),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadBookings,
              child: Text(translationService.t('retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.calendarX,
                size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            Text(
              translationService.t('no_bookings'),
              style: TextStyle(
                color: context.appText.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBookings,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _bookings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildBookingCard(_bookings[i]),
      ),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final number = _bookingDisplayNumber(booking);
    final customer = booking['customer'];
    final customerName = (customer is Map ? customer['name'] : null)?.toString() ?? '';
    final statusValue = int.tryParse(booking['status']?.toString() ?? '') ?? 0;
    final statusLabel = _safe(booking['status_display']).trim();
    final cancelled = booking['has_cancelled'] == true;
    final bookAppointment = booking['book_appointment'] == true;
    final typeText = _safe(booking['type_text']);
    final createdAt = _safe(booking['created_at']);
    final total = _parseAmount(booking['total_price']);
    final color = _statusColor(statusValue, cancelled);

    return Material(
      color: context.appCardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _openBookingDetails(booking),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.appBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      bookAppointment
                          ? LucideIcons.calendarCheck
                          : LucideIcons.clock,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#$number',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: context.appText,
                          ),
                        ),
                        if (customerName.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              customerName,
                              style: TextStyle(
                                color: context.appText.withValues(alpha: 0.75),
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_amountFormatter.format(total)} ${ApiConstants.currency}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: context.appText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          cancelled
                              ? translationService.t('cancelled')
                              : (statusLabel.isNotEmpty
                                  ? statusLabel
                                  : translationService.t('confirmed')),
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (typeText.isNotEmpty) ...[
                    const Icon(LucideIcons.tag,
                        size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Text(
                      typeText,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (bookAppointment) ...[
                    const Icon(LucideIcons.calendarCheck,
                        size: 14, color: Color(0xFF22C55E)),
                    const SizedBox(width: 4),
                    Text(
                      translationService.t('appointment'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF22C55E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ] else ...[
                    const Icon(LucideIcons.clock,
                        size: 14, color: Color(0xFFF97316)),
                    const SizedBox(width: 4),
                    Text(
                      translationService.t('pay_later'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFF97316),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      createdAt,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
