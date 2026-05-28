import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:lucide_icons/lucide_icons.dart';

import '../locator.dart';
import '../services/api/api_constants.dart';
import '../services/api/base_client.dart';
import '../services/app_themes.dart';
import '../services/cache_service.dart';
import '../services/language_service.dart';

/// Salon Appointments Calendar Screen.
///
/// Displays a daily timeline/list of appointments fetched from
/// `GET /seller/branches/{branchId}/calculated/reports/appointments`.
/// The response format is not yet finalised, so parsing is deliberately
/// flexible: it handles flat lists, grouped-by-employee maps, and falls back
/// to showing raw JSON when the shape is unexpected.
class AppointmentsScreen extends StatefulWidget {
  final VoidCallback onBack;

  const AppointmentsScreen({super.key, required this.onBack});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  final BaseClient _client = BaseClient();
  final CacheService _cache = getIt<CacheService>();
  final NumberFormat _amountFormatter = NumberFormat('#,##0.##');

  DateTime _selectedDate = DateTime.now();
  String? _selectedEmployeeId;
  bool _isLoading = true;
  String? _error;

  /// Parsed flat list of appointment maps (may come from various shapes).
  List<Map<String, dynamic>> _appointments = [];

  /// Employee options extracted from response (id -> name).
  Map<String, String> _employeeOptions = {};

  @override
  void initState() {
    super.initState();
    translationService.addListener(_onLanguageChanged);
    _loadAppointments();
  }

  @override
  void dispose() {
    translationService.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  // Cache key for (date, employee) filter pair; paints last-seen response while refreshing.
  String get _appointmentsCacheKey {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final emp =
        (_selectedEmployeeId == null || _selectedEmployeeId!.isEmpty)
            ? 'all'
            : _selectedEmployeeId!;
    return 'salon_appointments_${dateStr}_$emp';
  }

  Future<void> _loadAppointments() async {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    String endpoint =
        '${ApiConstants.salonAppointmentsCalendarEndpoint}?date_from=$dateStr&date_to=$dateStr';
    if (_selectedEmployeeId != null && _selectedEmployeeId!.isNotEmpty) {
      endpoint += '&employee_id=$_selectedEmployeeId';
    }

    // Paint cached response immediately while fresh request is in flight.
    Map<String, dynamic>? cached;
    try {
      final raw = await _cache.get(_appointmentsCacheKey);
      if (raw is Map) {
        cached = Map<String, dynamic>.from(raw);
      }
    } catch (_) {
      cached = null;
    }
    if (!mounted) return;

    if (cached != null) {
      _parseResponse(cached);
      setState(() {
        _isLoading = false;
        _error = null;
      });
    } else {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final response = await _client.get(endpoint);
      if (!mounted) return;

      final Map<String, dynamic> responseMap =
          response is Map<String, dynamic> ? response : {'data': response};

      _parseResponse(responseMap);

      // 6h expiry: past a typical shift but short enough to bound staleness.
      unawaited(_cache.set(
        _appointmentsCacheKey,
        responseMap,
        expiry: const Duration(hours: 6),
      ));

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Keep cached list visible; only show error when screen is empty.
        if (_appointments.isEmpty) {
          _error = e.toString();
        }
        _isLoading = false;
      });
    }
  }

  /// API returns a list of employees with nested `appointments` (or sometimes flat).
  void _parseResponse(Map<String, dynamic> response) {
    _appointments = [];
    _employeeOptions = {};

    final dynamic data = response['data'];

    if (data is List) {
      final hasNested = data.isNotEmpty &&
          data.first is Map &&
          (data.first as Map).containsKey('appointments');

      if (hasNested) {
        for (final emp in data) {
          if (emp is! Map) continue;
          final empId = (emp['id'] ?? '').toString();
          final empName = (emp['name'] ?? '').toString();
          final empAvatar = (emp['avatar'] ?? '').toString();
          if (empId.isNotEmpty) _employeeOptions[empId] = empName;

          final appts = emp['appointments'];
          if (appts is List) {
            for (final appt in appts) {
              if (appt is! Map) continue;
              final flat = Map<String, dynamic>.from(appt);
              flat['_employee_id'] = empId;
              flat['_employee_name'] = empName;
              flat['_employee_avatar'] = empAvatar;
              _appointments.add(flat);
            }
          }
        }
      } else {
        _appointments =
            data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } else if (data is Map) {
      final mapData = Map<String, dynamic>.from(data);
      if (mapData.containsKey('appointments')) {
        final appts = mapData['appointments'];
        if (appts is List) {
          _appointments =
              appts.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }
    }

    // Client-side date filter (API may not filter).
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    _appointments = _appointments.where((a) {
      final start = (a['start'] ?? '').toString();
      if (start.isEmpty) return true;
      return start.startsWith(dateStr);
    }).toList();

    if (_selectedEmployeeId != null && _selectedEmployeeId!.isNotEmpty) {
      _appointments = _appointments
          .where((a) => (a['_employee_id'] ?? '').toString() == _selectedEmployeeId)
          .toList();
    }

    _appointments.sort((a, b) {
      final timeA = (a['start'] ?? '').toString();
      final timeB = (b['start'] ?? '').toString();
      return timeA.compareTo(timeB);
    });
  }

  String _field(Map<String, dynamic> appt, List<String> keys,
      [String fallback = '-']) {
    for (final key in keys) {
      final value = appt[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return fallback;
  }

  String _customerName(Map<String, dynamic> a) =>
      _field(a, ['customer_name', 'customer', 'client_name', 'client']);

  String _serviceName(Map<String, dynamic> a) =>
      _field(a, ['service_name', 'service', 'meal_name', 'product_name', 'name']);

  String _employeeName(Map<String, dynamic> a) => _field(a, [
        '_employee_name',
        'employee_name',
        'employee',
        'staff_name',
        'staff',
      ]);

  String _timeDisplay(Map<String, dynamic> a) {
    final start = (a['start'] ?? a['start_time'] ?? a['time'] ?? '').toString();
    if (start.isEmpty) return '-';
    try {
      final dt = DateTime.parse(start);
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return start;
    }
  }

  /// Normalize status to string key; API numeric codes: 1=confirmed, 2=in_progress, 3/7=completed, 4=cancelled.
  String _status(Map<String, dynamic> a) {
    final raw = a['status'] ?? a['appointment_status'] ?? a['state'] ?? 'unknown';
    if (raw is int) {
      switch (raw) {
        case 1: return 'confirmed';
        case 2: return 'in_progress';
        case 3: return 'completed';
        case 4: return 'cancelled';
        case 5: return 'no_show';
        case 7: return 'completed';
        default: return 'unknown';
      }
    }
    return raw.toString().toLowerCase();
  }

  String _totalPrice(Map<String, dynamic> a) {
    final raw = a['total_price'] ??
        a['total'] ??
        a['price'] ??
        a['amount'] ??
        a['grand_total'];
    if (raw == null) return '-';
    final num? parsed = num.tryParse(raw.toString());
    if (parsed == null) return raw.toString();
    return '${_amountFormatter.format(parsed)} ${ApiConstants.currency}';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
      case 'approved':
      case 'booked':
        return const Color(0xFF2196F3);
      case 'in_progress':
      case 'in-progress':
      case 'started':
      case 'ongoing':
        return const Color(0xFFFF9800);
      case 'completed':
      case 'done':
      case 'finished':
        return const Color(0xFF4CAF50);
      case 'cancelled':
      case 'canceled':
      case 'rejected':
      case 'no_show':
      case 'no-show':
        return const Color(0xFFF44336);
      case 'pending':
      case 'waiting':
        return const Color(0xFF9C27B0);
      default:
        return const Color(0xFF607D8B);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'confirmed':
      case 'approved':
      case 'booked':
        return translationService.t('confirmed');
      case 'in_progress':
      case 'in-progress':
      case 'started':
      case 'ongoing':
        return translationService.t('in_progress');
      case 'completed':
      case 'done':
      case 'finished':
        return translationService.t('completed');
      case 'cancelled':
      case 'canceled':
      case 'rejected':
        return translationService.t('cancelled');
      case 'no_show':
      case 'no-show':
        return translationService.t('no_show');
      case 'pending':
      case 'waiting':
        return translationService.t('pending');
      default:
        return status;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'confirmed':
      case 'approved':
      case 'booked':
        return LucideIcons.calendarCheck;
      case 'in_progress':
      case 'in-progress':
      case 'started':
      case 'ongoing':
        return LucideIcons.clock;
      case 'completed':
      case 'done':
      case 'finished':
        return LucideIcons.checkCircle;
      case 'cancelled':
      case 'canceled':
      case 'rejected':
        return LucideIcons.xCircle;
      case 'no_show':
      case 'no-show':
        return LucideIcons.userX;
      case 'pending':
      case 'waiting':
        return LucideIcons.hourglass;
      default:
        return LucideIcons.helpCircle;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: translationService.currentLocale,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFF58220),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1E293B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      unawaited(_loadAppointments());
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 1100;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      // Full-screen (no parent AppBar) — own safe-area handling.
      body: SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              _buildHeader(isCompact),
              _buildFilterBar(isCompact),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFF58220),
                        ),
                      )
                    : _error != null
                        ? _buildErrorView()
                        : _appointments.isEmpty
                            ? _buildEmptyView()
                            : _buildAppointmentsList(isCompact),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isCompact) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 24,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: isCompact
          ? Row(
              children: [
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(LucideIcons.chevronRight),
                  color: const Color(0xFFF58220),
                ),
                Expanded(
                  child: Text(
                    translationService.t('salon_appointments'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: context.appText,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _loadAppointments,
                  icon: const Icon(LucideIcons.refreshCw),
                  color: const Color(0xFFF58220),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: widget.onBack,
                  icon: const Icon(LucideIcons.chevronRight, size: 28),
                  label: Text(
                    translationService.t('back'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFF58220),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
                Text(
                  translationService.t('salon_appointments'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: context.appText,
                  ),
                ),
                _HeaderActionBtn(
                  icon: LucideIcons.refreshCw,
                  label: translationService.t('refresh'),
                  onTap: _loadAppointments,
                ),
              ],
            ),
    );
  }

  Widget _buildFilterBar(bool isCompact) {
    final dateLabel = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 24,
        vertical: 10,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: context.appSurfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.calendar, size: 18, color: Color(0xFFF58220)),
                  const SizedBox(width: 8),
                  Text(
                    isToday
                        ? translationService.t('today_with_date', args: {'date': dateLabel})
                        : dateLabel,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.appText,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(LucideIcons.chevronDown, size: 16, color: Color(0xFF94A3B8)),
                ],
              ),
            ),
          ),

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SmallIconBtn(
                icon: LucideIcons.chevronRight,
                tooltip: translationService.t('previous_day'),
                onTap: () {
                  setState(() => _selectedDate =
                      _selectedDate.subtract(const Duration(days: 1)));
                  _loadAppointments();
                },
              ),
              const SizedBox(width: 4),
              _SmallIconBtn(
                icon: LucideIcons.chevronLeft,
                tooltip: translationService.t('next_day'),
                onTap: () {
                  setState(() => _selectedDate =
                      _selectedDate.add(const Duration(days: 1)));
                  _loadAppointments();
                },
              ),
            ],
          ),

          if (!isToday)
            TextButton.icon(
              onPressed: () {
                setState(() => _selectedDate = DateTime.now());
                _loadAppointments();
              },
              icon: const Icon(LucideIcons.calendarCheck, size: 16),
              label: Text(translationService.t('today')),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFF58220),
                textStyle: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),

          if (_employeeOptions.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: context.appSurfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedEmployeeId,
                  hint: Text(
                    translationService.t('all_employees'),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  items: [
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text(translationService.t('all_employees')),
                    ),
                    ..._employeeOptions.entries.map(
                      (e) => DropdownMenuItem<String>(
                        value: e.key,
                        child: Text(e.value),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedEmployeeId = value);
                    _loadAppointments();
                  },
                ),
              ),
            ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF58220).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              translationService.t('appointments_count', args: {'count': _appointments.length}),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFF58220),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.alertCircle, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            translationService.t('error'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _error!,
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadAppointments,
            icon: const Icon(LucideIcons.refreshCw),
            label: Text(translationService.t('retry')),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF58220),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.calendarOff, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            translationService.t('no_appointments'),
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            translationService.t('no_appointments_this_day'),
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentsList(bool isCompact) {
    return RefreshIndicator(
      color: const Color(0xFFF58220),
      onRefresh: _loadAppointments,
      child: ListView.builder(
        padding: EdgeInsets.all(isCompact ? 12 : 20),
        itemCount: _appointments.length,
        itemBuilder: (context, index) {
          final appt = _appointments[index];
          return _buildAppointmentCard(appt, isCompact);
        },
      ),
    );
  }

  Widget _buildAppointmentCard(Map<String, dynamic> appt, bool isCompact) {
    final status = _status(appt);
    final color = _statusColor(status);
    final time = _timeDisplay(appt);
    final customer = _customerName(appt);
    final service = _serviceName(appt);
    final employee = _employeeName(appt);
    final price = _totalPrice(appt);
    final statusText = _statusLabel(status);
    final statusIcn = _statusIcon(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          right: BorderSide(color: color, width: 4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showAppointmentDetails(appt),
          child: Padding(
            padding: EdgeInsets.all(isCompact ? 12 : 16),
            child: isCompact
                ? _buildCompactCard(
                    time: time,
                    customer: customer,
                    service: service,
                    employee: employee,
                    price: price,
                    statusText: statusText,
                    statusIcn: statusIcn,
                    color: color,
                  )
                : _buildWideCard(
                    time: time,
                    customer: customer,
                    service: service,
                    employee: employee,
                    price: price,
                    statusText: statusText,
                    statusIcn: statusIcn,
                    color: color,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactCard({
    required String time,
    required String customer,
    required String service,
    required String employee,
    required String price,
    required String statusText,
    required IconData statusIcn,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(LucideIcons.clock, size: 16, color: Color(0xFF64748B)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                time,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.appText,
                ),
              ),
            ),
            _StatusChip(label: statusText, icon: statusIcn, color: color),
          ],
        ),
        const SizedBox(height: 10),
        _InfoRow(
          icon: LucideIcons.user,
          label: translationService.t('customer'),
          value: customer,
        ),
        const SizedBox(height: 6),
        _InfoRow(
          icon: LucideIcons.scissors,
          label: translationService.t('service'),
          value: service,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _InfoRow(
                icon: LucideIcons.userCheck,
                label: translationService.t('employee'),
                value: employee,
              ),
            ),
            Text(
              price,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFFF58220),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWideCard({
    required String time,
    required String customer,
    required String service,
    required String employee,
    required String price,
    required String statusText,
    required IconData statusIcn,
    required Color color,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.clock, size: 16, color: Color(0xFF64748B)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      time,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.appText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _StatusChip(label: statusText, icon: statusIcn, color: color),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(
                icon: LucideIcons.user,
                label: translationService.t('customer'),
                value: customer,
              ),
              const SizedBox(height: 4),
              _InfoRow(
                icon: LucideIcons.scissors,
                label: translationService.t('service'),
                value: service,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _InfoRow(
            icon: LucideIcons.userCheck,
            label: translationService.t('employee'),
            value: employee,
          ),
        ),
        const SizedBox(width: 16),
        Text(
          price,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF58220),
          ),
        ),
      ],
    );
  }

  void _showAppointmentDetails(Map<String, dynamic> appt) {
    final status = _status(appt);
    final color = _statusColor(status);

    showDialog(
      context: context,
      builder: (ctx) {
        final entries = appt.entries.toList();
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(_statusIcon(status), color: color, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    translationService.t('appointment_details'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${translationService.t('status')}: ${_statusLabel(status)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${translationService.t('time')}: ${_timeDisplay(appt)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...entries.map((e) {
                      final key = e.key;
                      final value = e.value?.toString() ?? '';
                      if (key.startsWith('_')) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 140,
                              child: Text(
                                key,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                value.isEmpty ? '-' : value,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  translationService.t('ok'),
                  style: const TextStyle(color: Color(0xFFF58220)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HeaderActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const btnColor = Color(0xFFF58220);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: btnColor, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: btnColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _SmallIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: context.appSurfaceAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF64748B)),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w500,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.appTextMuted,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
