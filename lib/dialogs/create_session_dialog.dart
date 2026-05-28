import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../locator.dart';
import '../services/api/api_constants.dart';
import '../services/api/base_client.dart';
import '../services/api/error_handler.dart';
import '../services/api/salon_employee_service.dart';
import '../services/app_themes.dart';
import '../services/language_service.dart';
import '../services/logger_service.dart';
import '../utils/ui_feedback.dart';

/// Wizard for creating a booking session (تذكرة مراجعة).
///
/// Mirrors the salon dashboard flow captured in the HAR:
/// 1. Pick a customer (`/seller/filters/branches/{id}/allCustomers`)
/// 2. Pick a booking the customer owns
///    (`/seller/filters/branches/{id}/allBookingSessions?customer_id=…`)
/// 3. Pick the service inside that booking
///    (`/seller/services/branches/{id}/bookings/{booking_id}`)
/// 4. Pick the employee (`/seller/bookings/branches/{id}/services/{sid}`)
///    and a date+time slot
///    (`/seller/bookings/branches/{id}/employees/{eid}?date=…`)
/// 5. POST `/seller/branches/{id}/bookingSessions` (multipart)
class CreateSessionDialog extends StatefulWidget {
  const CreateSessionDialog({super.key});

  @override
  State<CreateSessionDialog> createState() => _CreateSessionDialogState();
}

class _CreateSessionDialogState extends State<CreateSessionDialog> {
  final BaseClient _client = BaseClient();

  bool _isLoadingCustomers = false;
  List<Map<String, dynamic>> _customers = [];
  Map<String, dynamic>? _selectedCustomer;
  final TextEditingController _customerSearch = TextEditingController();
  Timer? _customerDebounce;

  bool _isLoadingBookings = false;
  List<Map<String, dynamic>> _bookings = [];
  Map<String, dynamic>? _selectedBooking;

  bool _isLoadingServices = false;
  List<Map<String, dynamic>> _services = [];
  Map<String, dynamic>? _selectedService;

  bool _isLoadingEmployees = false;
  List<Map<String, dynamic>> _employees = [];
  Map<String, dynamic>? _selectedEmployee;

  bool _isLoadingSlots = false;
  List<Map<String, dynamic>> _slots = [];
  String? _selectedSlot;

  DateTime _date = DateTime.now();

  bool _isSubmitting = false;
  String? _submitError;


  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _customerSearch.dispose();
    _customerDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadCustomers({String? search}) async {
    setState(() => _isLoadingCustomers = true);
    try {
      final branchId = ApiConstants.branchId;
      final query = (search == null || search.isEmpty)
          ? ''
          : '&search=${Uri.encodeQueryComponent(search)}';
      final endpoint =
          '/seller/filters/branches/$branchId/allCustomers?id=$query';
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
        _customers = list;
        _isLoadingCustomers = false;
      });
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
      if (mounted) setState(() => _isLoadingCustomers = false);
    }
  }

  void _onCustomerSearch(String value) {
    _customerDebounce?.cancel();
    _customerDebounce = Timer(const Duration(milliseconds: 350), () {
      _loadCustomers(search: value.trim());
    });
  }

  Future<void> _loadBookingsForCustomer(int customerId) async {
    setState(() {
      _isLoadingBookings = true;
      _bookings = [];
      _selectedBooking = null;
    });
    try {
      final endpoint =
          '${ApiConstants.allBookingSessionsFilterEndpoint}?customer_id=$customerId';
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
        _bookings = list;
        _isLoadingBookings = false;
      });
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
      if (mounted) setState(() => _isLoadingBookings = false);
    }
  }

  Future<void> _loadServicesForBooking(int bookingId) async {
    setState(() {
      _isLoadingServices = true;
      _services = [];
      _selectedService = null;
    });
    try {
      final response = await _client
          .get(ApiConstants.bookingSessionServicesEndpoint(bookingId));
      final raw = response is Map<String, dynamic> ? response['data'] : null;
      final list = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _services = list;
        _isLoadingServices = false;
      });
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
      if (mounted) setState(() => _isLoadingServices = false);
    }
  }

  Future<void> _loadEmployeesForService(int serviceId) async {
    setState(() {
      _isLoadingEmployees = true;
      _employees = [];
      _selectedEmployee = null;
      _slots = [];
      _selectedSlot = null;
    });
    try {
      final response = await _client
          .get(ApiConstants.salonServiceEmployeesEndpoint(serviceId));
      List<Map<String, dynamic>> employees = [];
      if (response is Map<String, dynamic>) {
        final data = response['data'];
        if (data is Map) {
          final emps = data['employees'];
          if (emps is List) {
            employees = emps
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        } else if (data is List) {
          employees = data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _isLoadingEmployees = false;
      });
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
      if (mounted) setState(() => _isLoadingEmployees = false);
    }
  }

  Future<void> _loadSlots() async {
    final empId = (_selectedEmployee?['id'] ??
            _selectedEmployee?['value'])
        ?.toString();
    if (empId == null) return;
    setState(() {
      _isLoadingSlots = true;
      _slots = [];
      _selectedSlot = null;
    });
    try {
      // Backend wants PATCH with `{date, service_id}` body — GET silently 405s and shows every slot as available.
      final empIdNum = int.tryParse(empId) ?? 0;
      final endpoint =
          ApiConstants.salonEmployeeAvailableTimesEndpoint(empIdNum);
      final dateStr = DateFormat('yyyy-MM-dd').format(_date);
      final body = <String, dynamic>{'date': dateStr};
      final serviceId =
          int.tryParse(_selectedService?['value']?.toString() ?? '');
      if (serviceId != null) body['service_id'] = serviceId;

      final response = await _client.patch(endpoint, body);
      final raw = response is Map<String, dynamic> ? response['data'] : null;
      final list = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _slots = list;
        _isLoadingSlots = false;
      });
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
      if (mounted) setState(() => _isLoadingSlots = false);
    }
  }

  bool get _canSubmit =>
      _selectedCustomer != null &&
      _selectedBooking != null &&
      _selectedService != null &&
      _selectedEmployee != null &&
      _selectedSlot != null &&
      !_isSubmitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      final fields = <String, String>{
        'customer_id': _selectedCustomer?['value']?.toString() ?? '',
        'booking_id': _selectedBooking?['value']?.toString() ?? '',
        'service_id': _selectedService?['value']?.toString() ?? '',
        'employee_id':
            (_selectedEmployee?['id'] ?? _selectedEmployee?['value'])
                    ?.toString() ??
                '',
        'date': DateFormat('yyyy-MM-dd').format(_date),
        'time': _selectedSlot ?? '',
      };
      final response = await _client
          .postMultipart(ApiConstants.bookingSessionsEndpoint, fields);
      // Drop slot cache so a follow-up session can't re-offer the consumed time.
      try {
        getIt<SalonEmployeeService>().invalidateAvailableTimesCache();
      } catch (e) {
        Log.d('CreateSessionDialog', 'invalidate salon slot cache after create failed (non-fatal): $e');
      }
      if (!mounted) return;
      String? id;
      if (response is Map<String, dynamic>) {
        final data = response['data'];
        if (data is Map) {
          final invoice = data['invoice'];
          if (invoice is Map) id = invoice['id']?.toString();
          id ??= data['id']?.toString();
        }
      }
      Navigator.of(context).pop({'id': id ?? '', 'data': response});
    } catch (e) {
      if (!mounted) return;
      // ErrorHandler.toUserMessage surfaces the backend's userMessage (e.g. Arabic max-sessions line).
      final friendly = ErrorHandler.toUserMessage(
        e,
        fallback: translationService.t('session_create_failed'),
      );
      setState(() {
        _submitError = friendly;
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 700;
    final dialogWidth = (size.width * (isCompact ? 0.95 : 0.7))
        .clamp(320.0, 720.0)
        .toDouble();
    final dialogHeight = (size.height * 0.9).clamp(420.0, 820.0).toDouble();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCustomerStep(),
                    if (_selectedCustomer != null) ...[
                      const SizedBox(height: 16),
                      _buildBookingStep(),
                    ],
                    if (_selectedBooking != null) ...[
                      const SizedBox(height: 16),
                      _buildServiceStep(),
                    ],
                    if (_selectedService != null) ...[
                      const SizedBox(height: 16),
                      _buildEmployeeStep(),
                    ],
                    if (_selectedEmployee != null) ...[
                      const SizedBox(height: 16),
                      _buildDateAndSlotStep(),
                    ],
                  ],
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      decoration: BoxDecoration(
        color: context.appCardBg,
        border: Border(bottom: BorderSide(color: context.appBorder)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.ticket,
              color: Color(0xFFF58220), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              translationService.t('new_review_ticket'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: context.appText,
              ),
            ),
          ),
          IconButton(
            onPressed: _isSubmitting ? null : () => Navigator.pop(context),
            icon: const Icon(LucideIcons.x),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerStep() {
    return _stepCard(
      title: translationService.t('step_1_customer'),
      child: Column(
        children: [
          if (_selectedCustomer != null)
            _selectedTile(
              label: _selectedCustomer!['label']?.toString() ?? '',
              onClear: () => setState(() {
                _selectedCustomer = null;
                _bookings = [];
                _selectedBooking = null;
                _services = [];
                _selectedService = null;
                _employees = [];
                _selectedEmployee = null;
                _slots = [];
                _selectedSlot = null;
              }),
            )
          else ...[
            TextField(
              controller: _customerSearch,
              onChanged: _onCustomerSearch,
              decoration: InputDecoration(
                hintText: translationService.t('search_customer_dots'),
                isDense: true,
                prefixIcon: const Icon(LucideIcons.search, size: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            _isLoadingCustomers
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.appBorder),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _customers.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              translationService.t('no_customers'),
                              style: TextStyle(
                                color: context.appText.withValues(alpha: 0.6),
                              ),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _customers.length.clamp(0, 30),
                            itemBuilder: (_, i) {
                              final c = _customers[i];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  c['label']?.toString() ?? '',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                onTap: () {
                                  setState(() => _selectedCustomer = c);
                                  final id = int.tryParse(
                                      c['value']?.toString() ?? '');
                                  if (id != null) _loadBookingsForCustomer(id);
                                },
                              );
                            },
                          ),
                  ),
          ],
        ],
      ),
    );
  }

  Widget _buildBookingStep() {
    return _stepCard(
      title: translationService.t('step_2_booking'),
      child: _isLoadingBookings
          ? const Center(child: CircularProgressIndicator())
          : _bookings.isEmpty
              ? Text(
                  translationService.t('no_bookings_for_customer'),
                  style: TextStyle(
                      color: context.appText.withValues(alpha: 0.6)),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _bookings.map((b) {
                    final selected = _selectedBooking?['value'] == b['value'];
                    return ChoiceChip(
                      label: Text(b['label']?.toString() ?? ''),
                      selected: selected,
                      onSelected: (s) {
                        if (!s) return;
                        setState(() => _selectedBooking = b);
                        final id =
                            int.tryParse(b['value']?.toString() ?? '');
                        if (id != null) _loadServicesForBooking(id);
                      },
                      selectedColor: const Color(0xFFF58220),
                      labelStyle: TextStyle(
                        color:
                            selected ? Colors.white : context.appText,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList(),
                ),
    );
  }

  /// Backend embeds the remaining-session count inside the service label
  /// (e.g. `"مكياج فرنسي (3 جلسات.)"`). The schema doesn't carry a
  /// dedicated field for it, so we parse the parens. Returns `null` when
  /// the count can't be extracted, in which case we let the user proceed
  /// (and the backend will still validate).
  int? _remainingSessionsFromLabel(String label) {
    final match = RegExp(r'\((\d+)').firstMatch(label);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  Widget _buildServiceStep() {
    return _stepCard(
      title: translationService.t('step_3_service'),
      child: _isLoadingServices
          ? const Center(child: CircularProgressIndicator())
          : _services.isEmpty
              ? Text(
                  translationService.t('no_services_in_booking'),
                  style: TextStyle(
                      color: context.appText.withValues(alpha: 0.6)),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _services.map((s) {
                    final label = s['label']?.toString() ?? '';
                    final remaining = _remainingSessionsFromLabel(label);
                    // 0 جلسات متبقية: نمنع الاختيار لأن الـ backend يرفض الإنشاء بـ 422.
                    final exhausted = remaining == 0;
                    final selected =
                        _selectedService?['value'] == s['value'];
                    final chipBg = exhausted
                        ? Colors.grey.shade300
                        : (selected
                            ? const Color(0xFFF58220)
                            : context.appCardBg);
                    final chipFg = exhausted
                        ? Colors.grey.shade700
                        : (selected ? Colors.white : context.appText);
                    return InkWell(
                      onTap: exhausted
                          ? () {
                              UiFeedback.warning(context, translationService.t('no_sessions_remaining'));
                            }
                          : () {
                              setState(() => _selectedService = s);
                              final id = int.tryParse(
                                  s['value']?.toString() ?? '');
                              if (id != null) _loadEmployeesForService(id);
                            },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: chipBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: exhausted
                                ? Colors.grey.shade400
                                : (selected
                                    ? const Color(0xFFF58220)
                                    : context.appBorder),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (exhausted) ...[
                              Icon(
                                LucideIcons.ban,
                                size: 14,
                                color: chipFg,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: chipFg,
                                  fontWeight: FontWeight.w600,
                                  decoration: exhausted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
    );
  }

  Widget _buildEmployeeStep() {
    return _stepCard(
      title: translationService.t('step_4_employee'),
      child: _isLoadingEmployees
          ? const Center(child: CircularProgressIndicator())
          : _employees.isEmpty
              ? Text(
                  translationService.t('no_available_employees'),
                  style: TextStyle(
                      color: context.appText.withValues(alpha: 0.6)),
                )
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _employees.map((e) {
                    final id =
                        (e['id'] ?? e['value'])?.toString();
                    final selectedId = (_selectedEmployee?['id'] ??
                            _selectedEmployee?['value'])
                        ?.toString();
                    final selected = id != null && id == selectedId;
                    final name = (e['fullname'] ??
                            e['name'] ??
                            e['label'])
                        ?.toString() ??
                        '';
                    return ChoiceChip(
                      label: Text(name),
                      selected: selected,
                      onSelected: (val) {
                        if (!val) return;
                        setState(() => _selectedEmployee = e);
                        _loadSlots();
                      },
                      selectedColor: const Color(0xFFF58220),
                      labelStyle: TextStyle(
                        color:
                            selected ? Colors.white : context.appText,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }).toList(),
                ),
    );
  }

  Widget _buildDateAndSlotStep() {
    return _stepCard(
      title: translationService.t('step_5_date_time'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) {
                setState(() => _date = picked);
                unawaited(_loadSlots());
              }
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: translationService.t('date'),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                DateFormat('yyyy-MM-dd').format(_date),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_isLoadingSlots)
            const Center(child: CircularProgressIndicator())
          else if (_slots.isEmpty)
            Text(
              translationService.t('no_available_time_slots'),
              style: TextStyle(color: context.appText.withValues(alpha: 0.6)),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _slots.map((slot) {
                final value = slot['value']?.toString() ?? '';
                final label = slot['label']?.toString() ?? value;
                final selected = _selectedSlot == value;
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (s) {
                    if (s) setState(() => _selectedSlot = value);
                  },
                  selectedColor: const Color(0xFFF58220),
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : context.appText,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _stepCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: context.appText,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _selectedTile({required String label, required VoidCallback onClear}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF58220).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF58220)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.checkCircle,
              size: 16, color: Color(0xFFF58220)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: context.appText),
            ),
          ),
          IconButton(
            onPressed: onClear,
            icon: const Icon(LucideIcons.x, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appCardBg,
        border: Border(top: BorderSide(color: context.appBorder)),
      ),
      child: Column(
        children: [
          if (_submitError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _submitError!,
                style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12),
              ),
            ),
          Row(
            children: [
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _canSubmit ? _submit : null,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(LucideIcons.check, size: 16),
                label: Text(translationService.t('create_ticket')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF58220),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
