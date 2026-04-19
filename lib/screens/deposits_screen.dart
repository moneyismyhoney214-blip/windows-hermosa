import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api/api_constants.dart';
import '../services/api/salon_employee_service.dart';
import '../services/language_service.dart';
import '../services/app_themes.dart';
import '../dialogs/create_deposit_dialog.dart';
import '../locator.dart';

class DepositsScreen extends StatefulWidget {
  final VoidCallback onBack;

  const DepositsScreen({super.key, required this.onBack});

  @override
  State<DepositsScreen> createState() => _DepositsScreenState();
}

class _DepositsScreenState extends State<DepositsScreen> {
  final SalonEmployeeService _salonService = getIt<SalonEmployeeService>();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _amountFormatter = NumberFormat('#,##0.##');

  List<Map<String, dynamic>> _deposits = [];
  Timer? _autoRefreshTimer;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _page = 1;
  static const int _perPage = 20;

  String _searchQuery = '';

  String get _langCode =>
      translationService.currentLanguageCode.trim().toLowerCase();
  bool get _useArabicUi =>
      _langCode.startsWith('ar') || _langCode.startsWith('ur');
  String _tr(String ar, String nonArabic) => _useArabicUi ? ar : nonArabic;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadDeposits(reset: true);
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_isLoading && !_isLoadingMore && mounted) {
        _loadDeposits(reset: true);
      }
    });
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || _isLoading) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadDeposits(reset: false);
    }
  }

  Future<void> _loadDeposits({required bool reset}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      final response = await _salonService.getDeposits(
        page: _page,
        perPage: _perPage,
      );

      final rawList = response['data'];
      List<Map<String, dynamic>> deposits = [];
      if (rawList is List) {
        deposits = rawList
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }

      // Resolve pagination
      final meta = response['meta'];
      final lastPage = (meta is Map ? meta['last_page'] : null) as int? ??
          response['last_page'] as int? ??
          1;
      final hasMore = _page < lastPage;

      if (!mounted) return;
      setState(() {
        if (reset) {
          _deposits = deposits;
        } else {
          _deposits = [..._deposits, ...deposits];
        }
        _isLoading = false;
        _isLoadingMore = false;
        _hasMore = hasMore;
        if (_hasMore) _page += 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Color _statusColor(dynamic status) {
    final s = int.tryParse(status?.toString() ?? '') ?? 0;
    if (s == 2) return const Color(0xFF22C55E); // used - green
    return const Color(0xFFF97316); // pending (1) or default - orange
  }

  String _statusLabel(dynamic status) {
    final s = int.tryParse(status?.toString() ?? '') ?? 0;
    if (s == 2) return _tr('تم الاستخدام', 'Used');
    return _tr('قيد الانتظار', 'Pending');
  }

  String _safeStr(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  /// Parse amount from API which may include currency symbols (e.g. "805.00 ر.س")
  double _parseAmount(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    var cleaned = value.toString().replaceAll(RegExp(r'[^\d.\-]'), '');
    final dotIndex = cleaned.indexOf('.');
    if (dotIndex >= 0) {
      cleaned = cleaned.substring(0, dotIndex + 1) +
          cleaned.substring(dotIndex + 1).replaceAll('.', '');
    }
    return double.tryParse(cleaned) ?? 0.0;
  }

  String _normalizeSearchToken(String value) {
    return value
        .toLowerCase()
        .replaceAll('#', '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
  }

  bool _depositMatchesSearch(Map<String, dynamic> deposit, String query) {
    final normalized = _normalizeSearchToken(query);
    if (normalized.isEmpty) return true;

    // Search by invoice number
    final invoiceNumber = _safeStr(deposit['invoice_number']);
    if (_normalizeSearchToken(invoiceNumber).contains(normalized)) return true;

    // Search by ID
    final id = _safeStr(deposit['id']);
    if (_normalizeSearchToken(id).contains(normalized)) return true;

    // Search by customer name
    final customerName = _safeStr(
        deposit['customer']?['name'] ?? deposit['customer_name'] ?? '');
    if (customerName.toLowerCase().contains(query.toLowerCase())) return true;

    return false;
  }

  void _openCreateDepositDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const CreateDepositDialog(),
    );
    if (result == true) {
      _loadDeposits(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorView()
                    : _buildDepositsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 900;
    final searchWidth = (width * 0.25).clamp(180.0, 280.0).toDouble();

    final searchField = TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value.trim()),
      onSubmitted: (_) => _loadDeposits(reset: true),
      decoration: InputDecoration(
        hintText: _tr(
          'بحث برقم العربون أو اسم العميل',
          'Search by deposit number or customer name',
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        prefixIcon: const Icon(Icons.search, size: 18),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                  _loadDeposits(reset: true);
                },
                icon: const Icon(Icons.clear, size: 18),
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );

    final headerContent = isCompact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(LucideIcons.chevronRight, size: 24),
                    color: const Color(0xFFF58220),
                  ),
                  Expanded(
                    child: Text(
                      _tr('العرابين', 'Deposits'),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _loadDeposits(reset: true),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _openCreateDepositDialog,
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: Text(_tr('إنشاء عربون', 'Create Deposit')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF58220),
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          )
        : Row(
            children: [
              TextButton.icon(
                onPressed: widget.onBack,
                icon: const Icon(LucideIcons.chevronRight, size: 28),
                label: Text(
                  _tr('رجوع', 'Back'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFF58220),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const Spacer(),
              Text(
                _tr('العرابين', 'Deposits'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              SizedBox(width: searchWidth, child: searchField),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _loadDeposits(reset: true),
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _openCreateDepositDialog,
                icon: const Icon(LucideIcons.plus, size: 16),
                label: Text(_tr('إنشاء عربون', 'Create Deposit')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF58220),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: context.appCardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: headerContent,
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.alertCircle, size: 40, color: Colors.red.shade400),
          const SizedBox(height: 8),
          Text(
            _tr('تعذر تحميل العرابين', 'Unable to load deposits'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _loadDeposits(reset: true),
            icon: const Icon(Icons.refresh),
            label: Text(_tr('إعادة المحاولة', 'Retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildDepositsList() {
    final query = _searchQuery.trim();
    final displayItems = query.isEmpty
        ? _deposits
        : _deposits
            .where((item) => _depositMatchesSearch(item, query))
            .toList();

    if (displayItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.wallet, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(
              _tr('لا توجد عرابين', 'No deposits found'),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadDeposits(reset: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: displayItems.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= displayItems.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: _isLoadingMore
                    ? const CircularProgressIndicator()
                    : const SizedBox.shrink(),
              ),
            );
          }

          return _buildDepositCard(displayItems[index]);
        },
      ),
    );
  }

  Widget _buildDepositCard(Map<String, dynamic> deposit) {
    final invoiceNumber = _safeStr(deposit['invoice_number']);
    final customerName = _safeStr(
        deposit['user']?['name'] ?? deposit['customer']?['name'] ?? deposit['customer_name'] ?? '');
    final total = _parseAmount(deposit['total']);
    final status = deposit['status'];
    final bookingDate = _safeStr(deposit['booking_date']);
    final bookingTime = _safeStr(deposit['booking_time']);
    final notes = _safeStr(deposit['notes']);
    final createdAt = _safeStr(deposit['created_at']);
    final statusColor = _statusColor(status);
    final statusText = _statusLabel(status);

    final displayNumber = invoiceNumber.isNotEmpty
        ? '#DP-$invoiceNumber'
        : '#DP-${deposit['id'] ?? ''}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.appBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: invoice number + status badge
          Row(
            children: [
              Expanded(
                child: Text(
                  displayNumber,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Date
          if (createdAt.isNotEmpty)
            Text(
              _formatDate(createdAt),
              style: TextStyle(color: Colors.grey.shade600),
            ),

          // Customer name
          if (customerName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(LucideIcons.user, size: 16, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              ],
            ),
          ],

          const Divider(height: 24),

          // Total amount - LARGE, BOLD, ORANGE
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _tr('الإجمالي', 'Total'),
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_amountFormatter.format(total)} ${ApiConstants.currency}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF58220),
                ),
              ),
            ],
          ),

          // Booking date/time
          if (bookingDate.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(LucideIcons.calendarDays,
                    size: 15, color: Color(0xFF94A3B8)),
                const SizedBox(width: 6),
                Text(
                  bookingDate,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
                if (bookingTime.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  const Icon(LucideIcons.clock,
                      size: 15, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 4),
                  Text(
                    bookingTime,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ],
            ),
          ],

          // Notes
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.fileText,
                    size: 15, color: Color(0xFF94A3B8)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    notes,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          // Action buttons
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _showDepositDetails(deposit),
                icon: const Icon(LucideIcons.fileText, size: 16),
                label: Text(_tr('عرض التفاصيل', 'View Details')),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF2563EB),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) return '';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    final timeLabel = DateFormat('HH:mm').format(local);
    if (timeLabel == '00:00') {
      return DateFormat('yyyy-MM-dd').format(local);
    }
    return '${DateFormat('yyyy-MM-dd').format(local)} $timeLabel';
  }

  Future<void> _showDepositDetails(Map<String, dynamic> deposit) async {
    final depositId = deposit['id'];
    if (depositId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final details =
          await _salonService.getDepositDetails(int.parse(depositId.toString()));
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading

      final data = details['data'] is Map
          ? Map<String, dynamic>.from(details['data'] as Map)
          : details;

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => _DepositDetailsDialog(
          deposit: data,
          tr: _tr,
          amountFormatter: _amountFormatter,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr(
            'تعذر جلب تفاصيل العربون',
            'Failed to load deposit details',
          )),
        ),
      );
    }
  }
}

// ── Deposit Details Dialog ──────────────────────────────────────────────

class _DepositDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> deposit;
  final String Function(String ar, String en) tr;
  final NumberFormat amountFormatter;

  const _DepositDetailsDialog({
    required this.deposit,
    required this.tr,
    required this.amountFormatter,
  });

  String _safeStr(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  static double _parseAmountStatic(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    var cleaned = value.toString().replaceAll(RegExp(r'[^\d.\-]'), '');
    final dotIndex = cleaned.indexOf('.');
    if (dotIndex >= 0) {
      cleaned = cleaned.substring(0, dotIndex + 1) +
          cleaned.substring(dotIndex + 1).replaceAll('.', '');
    }
    return double.tryParse(cleaned) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 700;

    final invoiceNumber = _safeStr(deposit['invoice_number']);
    final customerName = _safeStr(
        deposit['user']?['name'] ?? deposit['customer']?['name'] ?? deposit['customer_name'] ?? '');
    final price = _parseAmountStatic(deposit['price']);
    final total = _parseAmountStatic(deposit['total']);
    final tax = total - price;
    final bookingDate = _safeStr(deposit['booking_date']);
    final bookingTime = _safeStr(deposit['booking_time']);
    final notes = _safeStr(deposit['notes']);
    final createdAt = _safeStr(deposit['created_at']);

    // Extract services
    final services = deposit['services'] is List
        ? (deposit['services'] as List)
        : deposit['meals'] is List
            ? (deposit['meals'] as List)
            : [];

    // Extract payments
    final pays = deposit['pays'] is List
        ? (deposit['pays'] as List)
        : [];

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 40,
        vertical: isCompact ? 24 : 40,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFF58220),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.wallet,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      invoiceNumber.isNotEmpty
                          ? '${tr('عربون', 'Deposit')} #DP-$invoiceNumber'
                          : '${tr('عربون', 'Deposit')} #DP-${deposit['id'] ?? ''}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Customer
                    if (customerName.isNotEmpty)
                      _buildInfoRow(
                          LucideIcons.user, tr('العميل', 'Customer'), customerName),

                    // Created at
                    if (createdAt.isNotEmpty)
                      _buildInfoRow(
                          LucideIcons.calendar, tr('التاريخ', 'Date'), createdAt),

                    // Booking date/time
                    if (bookingDate.isNotEmpty)
                      _buildInfoRow(
                        LucideIcons.calendarDays,
                        tr('تاريخ الحجز', 'Booking Date'),
                        bookingTime.isNotEmpty
                            ? '$bookingDate - $bookingTime'
                            : bookingDate,
                      ),

                    // Services
                    if (services.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        tr('الخدمات', 'Services'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...services.map((s) {
                        final name = s is Map
                            ? (s['meal_name'] ?? s['name'] ?? '-').toString()
                            : s.toString();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(LucideIcons.scissors,
                                  size: 14, color: Color(0xFF94A3B8)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],

                    const Divider(height: 24),

                    // Price breakdown
                    _buildAmountRow(tr('السعر قبل الضريبة', 'Subtotal'),
                        '${amountFormatter.format(price)} ${ApiConstants.currency}'),
                    if (tax > 0)
                      _buildAmountRow(tr('الضريبة', 'Tax'),
                          '${amountFormatter.format(tax)} ${ApiConstants.currency}'),
                    const SizedBox(height: 4),
                    _buildAmountRow(
                      tr('الإجمالي', 'Total'),
                      '${amountFormatter.format(total)} ${ApiConstants.currency}',
                      isBold: true,
                      color: const Color(0xFFF58220),
                    ),

                    // Payments
                    if (pays.isNotEmpty) ...[
                      const Divider(height: 24),
                      Text(
                        tr('المدفوعات', 'Payments'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...pays.map((p) {
                        if (p is! Map) return const SizedBox.shrink();
                        final methodName =
                            (p['name'] ?? p['pay_method'] ?? '-').toString();
                        final amount = double.tryParse(
                                p['amount']?.toString() ?? '0') ??
                            0;
                        if (amount <= 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                methodName,
                                style: const TextStyle(
                                    fontSize: 13, color: Color(0xFF475569)),
                              ),
                              Text(
                                '${amountFormatter.format(amount)} ${ApiConstants.currency}',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B)),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],

                    // Notes
                    if (notes.isNotEmpty) ...[
                      const Divider(height: 24),
                      _buildInfoRow(
                          LucideIcons.fileText, tr('ملاحظات', 'Notes'), notes),
                    ],
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF58220),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    tr('إغلاق', 'Close'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAmountRow(String label, String value,
      {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color ?? const Color(0xFF475569),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 15 : 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ?? const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }
}
