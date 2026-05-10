import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api/api_constants.dart';
import '../services/api/base_client.dart';
import '../services/language_service.dart';
import '../services/app_themes.dart';
import '../dialogs/create_session_dialog.dart';
import '../dialogs/session_details_dialog.dart';

/// Salon Review Tickets (تذاكر المراجعة) screen.
///
/// Each row is a *session* — one visit against a booked service — fetched
/// from `GET /seller/branches/{id}/bookingSessions`. The screen mirrors the
/// salon dashboard: status filter, search, and a "create" entry point that
/// walks the cashier through customer → booking → service → employee →
/// date → time, ending in `POST /seller/branches/{id}/bookingSessions`.
class ReviewTicketsScreen extends StatefulWidget {
  final VoidCallback onBack;

  /// Optional hook fired after a successful session creation. The host
  /// (main_screen) uses it to dispatch the session ticket to every salon
  /// turn-ticket printer so the floor staff knows the customer just
  /// arrived for a paid-package visit.
  final Future<void> Function(String orderId, Map<String, dynamic> bookingData)?
      onPrintSalonTurnTicket;

  const ReviewTicketsScreen({
    super.key,
    required this.onBack,
    this.onPrintSalonTurnTicket,
  });

  @override
  State<ReviewTicketsScreen> createState() => _ReviewTicketsScreenState();
}

class _ReviewTicketsScreenState extends State<ReviewTicketsScreen> {
  final BaseClient _client = BaseClient();
  final TextEditingController _searchController = TextEditingController();

  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  String? _error;

  // Status filter — backend uses 1 = pending, 2 = completed.
  int? _statusFilter; // null = all
  String _searchQuery = '';
  Timer? _searchDebounce;

  String get _langCode =>
      translationService.currentLanguageCode.trim().toLowerCase();
  bool get _useArabicUi =>
      _langCode.startsWith('ar') || _langCode.startsWith('ur');
  String _tr(String ar, String en) => _useArabicUi ? ar : en;

  @override
  void initState() {
    super.initState();
    translationService.addListener(_onLanguageChanged);
    _loadSessions();
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

  Future<void> _loadSessions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final params = <String>[];
      if (_statusFilter != null) params.add('status=$_statusFilter');
      if (_searchQuery.isNotEmpty) {
        params.add('search=${Uri.encodeQueryComponent(_searchQuery)}');
      }
      final endpoint = params.isEmpty
          ? ApiConstants.bookingSessionsEndpoint
          : '${ApiConstants.bookingSessionsEndpoint}?${params.join('&')}';

      final response = await _client.get(endpoint);
      final raw = response is Map<String, dynamic> ? response['data'] : null;
      final list = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _sessions = list;
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
      _loadSessions();
    });
  }

  Future<void> _openSessionDetails(Map<String, dynamic> session) async {
    final id = int.tryParse(session['id']?.toString() ?? '');
    if (id == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    Map<String, dynamic>? full;
    String? err;
    try {
      final response = await _client
          .get(ApiConstants.bookingSessionDetailsEndpoint(id));
      if (response is Map<String, dynamic>) {
        final data = response['data'];
        if (data is Map) full = Map<String, dynamic>.from(data);
      }
    } catch (e) {
      err = e.toString();
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (err != null || full == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(err ??
                _tr('فشل تحميل تفاصيل التذكرة',
                    'Failed to load session details'))),
      );
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => SessionDetailsDialog(sessionData: full!),
    );
  }

  Future<void> _openCreateDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CreateSessionDialog(),
    );
    if (!mounted || result == null) return;
    final id = result['id']?.toString();
    if (id != null && id.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('تم إنشاء التذكرة #$id', 'Session #$id created')),
          backgroundColor: const Color(0xFF22C55E),
        ),
      );

      // Print the session to every salon turn-ticket printer. The session
      // response wraps the visit in `data.invoice.{items, client, ...}`,
      // which is a different shape from `booking.booking_services`. We
      // remap it into the booking-compatible structure the host's print
      // helper consumes so we can reuse the same dispatch logic — same
      // printer-role policy, same header rendering.
      final cb = widget.onPrintSalonTurnTicket;
      final raw = result['data'];
      if (cb != null && raw is Map) {
        final outer = raw is Map<String, dynamic>
            ? raw
            : Map<String, dynamic>.from(raw);
        final outerData =
            outer['data'] is Map ? outer['data'] as Map : outer;
        final invoice = outerData['invoice'];
        if (invoice is Map) {
          final items = invoice['items'];
          final List<Map<String, dynamic>> bookingServices = [];
          if (items is List) {
            for (final it in items) {
              if (it is! Map) continue;
              final m = Map<String, dynamic>.from(it);
              bookingServices.add({
                'service_name': m['item_name'] ?? '',
                'employee': {'fullname': m['employee_name'] ?? ''},
                'employee_id': m['employee_id'],
                'date': m['date'] ?? '',
                'time': m['time'] ?? '',
                'price': 0, // session ticket carries no per-line price
              });
            }
          }
          final synthetic = <String, dynamic>{
            'id': invoice['id'] ?? id,
            'booking_number': invoice['invoice_number'] ?? '#SEN-$id',
            'user': invoice['client'],
            'booking_services': bookingServices,
            'branch': outerData['branch'],
          };
          unawaited(() async {
            try {
              await cb(id, synthetic);
            } catch (_) {}
          }());
        }
      }
    }
    _loadSessions();
  }

  Color _statusColor(int status) {
    switch (status) {
      case 2:
        return const Color(0xFF22C55E); // completed (انتهى)
      case 3:
        return const Color(0xFFEF4444); // cancelled (تم الإلغاء)
      case 1:
      default:
        return const Color(0xFFF97316); // pending (قيد الانتظار)
    }
  }

  String _statusFallbackLabel(int status) {
    switch (status) {
      case 2:
        return _tr('انتهى', 'Completed');
      case 3:
        return _tr('تم الإلغاء', 'Cancelled');
      case 1:
      default:
        return _tr('قيد الانتظار', 'Pending');
    }
  }

  /// Updates the status of a session via
  /// `POST /seller/branches/{id}/bookingSessions/{sessionId}` with
  /// multipart `_method=PATCH&status=N` (Laravel method spoofing — same
  /// pattern the dashboard captured in the HAR). Refreshes the list on
  /// success and surfaces the backend's friendly message on failure.
  ///
  /// [target] semantics:
  ///   * 1 → reopen (return to قيد الانتظار)
  ///   * 2 → mark complete (انتهى)
  ///   * 3 → cancel (تم الإلغاء)
  Future<void> _changeSessionStatus(
    Map<String, dynamic> session,
    int target,
  ) async {
    final id = int.tryParse(session['id']?.toString() ?? '');
    if (id == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _client.postMultipart(
        ApiConstants.bookingSessionDetailsEndpoint(id),
        {
          '_method': 'PATCH',
          'status': target.toString(),
        },
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('تم تعديل الحالة بنجاح', 'Status updated')),
          backgroundColor: const Color(0xFF22C55E),
        ),
      );
      _loadSessions();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr('فشل تعديل الحالة: $e', 'Failed to update status: $e'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _displayNumber(Map<String, dynamic> s) {
    final raw = (s['session_number'] ?? s['id'])?.toString() ?? '';
    return raw.startsWith('#') ? raw.substring(1) : raw;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildFilters(),
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
              _tr('تذاكر المراجعة', 'Review Tickets'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: context.appText,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _openCreateDialog,
            icon: const Icon(LucideIcons.plus, size: 18),
            label: Text(_tr('تذكرة جديدة', 'New Ticket')),
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
            onPressed: _isLoading ? null : _loadSessions,
            icon: const Icon(LucideIcons.refreshCw, size: 20),
            tooltip: _tr('تحديث', 'Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: context.appBg,
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _statusChip(null, _tr('الكل', 'All')),
          _statusChip(1, _tr('قيد الانتظار', 'Pending')),
          _statusChip(2, _tr('انتهى', 'Completed')),
          _statusChip(3, _tr('ملغية', 'Cancelled')),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: _tr('بحث', 'Search'),
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

  Widget _statusChip(int? value, String label) {
    final selected = _statusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (s) {
        if (!s) return;
        setState(() => _statusFilter = value);
        _loadSessions();
      },
      selectedColor: const Color(0xFFF58220),
      labelStyle: TextStyle(
        color: selected ? Colors.white : context.appText,
        fontWeight: FontWeight.w600,
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
              onPressed: _loadSessions,
              child: Text(_tr('إعادة المحاولة', 'Retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.fileText,
                size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            Text(
              _tr('لا توجد تذاكر مراجعة', 'No review tickets'),
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
      onRefresh: _loadSessions,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _sessions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildSessionCard(_sessions[i]),
      ),
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> s) {
    final number = _displayNumber(s);
    final status = int.tryParse(s['status']?.toString() ?? '') ?? 1;
    final statusLabel = s['status_display']?.toString().trim() ?? '';
    final color = _statusColor(status);
    final serviceName = s['service_name']?.toString() ?? '';
    final customerName = s['customer_name']?.toString() ?? '';
    final date = s['date']?.toString() ?? '';
    final time = s['time']?.toString() ?? '';
    final bookingId = s['booking_id']?.toString() ?? '';

    return Material(
      color: context.appCardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _openSessionDetails(s),
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
                    child: Icon(LucideIcons.ticket, color: color),
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
                                color: context.appText
                                    .withValues(alpha: 0.75),
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
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
                      statusLabel.isEmpty
                          ? _statusFallbackLabel(status)
                          : statusLabel,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  // Status-change popup menu — what's offered depends on
                  // the row's current state. Pending → can complete or
                  // cancel; completed/cancelled → can only reopen.
                  PopupMenuButton<int>(
                    tooltip: _tr('تغيير الحالة', 'Change status'),
                    icon: const Icon(LucideIcons.moreVertical, size: 18),
                    onSelected: (target) =>
                        _changeSessionStatus(s, target),
                    itemBuilder: (_) {
                      final items = <PopupMenuEntry<int>>[];
                      if (status != 2) {
                        items.add(PopupMenuItem(
                          value: 2,
                          child: Row(
                            children: [
                              const Icon(LucideIcons.checkCircle,
                                  size: 16, color: Color(0xFF22C55E)),
                              const SizedBox(width: 8),
                              Text(_tr('تم الانتهاء', 'Mark complete')),
                            ],
                          ),
                        ));
                      }
                      if (status != 3) {
                        items.add(PopupMenuItem(
                          value: 3,
                          child: Row(
                            children: [
                              const Icon(LucideIcons.xCircle,
                                  size: 16, color: Color(0xFFEF4444)),
                              const SizedBox(width: 8),
                              Text(_tr('إلغاء', 'Cancel')),
                            ],
                          ),
                        ));
                      }
                      if (status != 1) {
                        items.add(PopupMenuItem(
                          value: 1,
                          child: Row(
                            children: [
                              const Icon(LucideIcons.rotateCcw,
                                  size: 16, color: Color(0xFFF97316)),
                              const SizedBox(width: 8),
                              Text(_tr('إعادة فتح', 'Reopen')),
                            ],
                          ),
                        ));
                      }
                      return items;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (serviceName.isNotEmpty)
                Row(
                  children: [
                    const Icon(LucideIcons.scissors,
                        size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        serviceName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (date.isNotEmpty) ...[
                    const Icon(LucideIcons.calendar,
                        size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Text(
                      date,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (time.isNotEmpty) ...[
                    const Icon(LucideIcons.clock,
                        size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (bookingId.isNotEmpty)
                    Text(
                      _tr('حجز #', 'BOK #') + bookingId,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF94A3B8),
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
