import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api/api_constants.dart';
import '../services/api/base_client.dart';
import '../services/api/branch_service.dart';
import '../services/api/salon_employee_service.dart';
import '../services/language_service.dart';
import '../services/app_themes.dart';
import '../locator.dart';

/// Composer for creating a salon booking — supports both flows captured in
/// the salon dashboard HAR:
///
/// * **حجز موعد (Book Appointment)** —
///   `POST /seller/branches/{id}/bookings?book_appointment&create_order`
///   Creates a confirmed appointment with date/time + employee. The list
///   screen auto-prints the kitchen receipt right after.
///
/// * **دفع لاحقاً (Pay Later)** —
///   `POST /seller/branches/{id}/bookings?create_order`
///   Same payload but without the `book_appointment` flag, so the backend
///   files it as a pay-later order rather than an appointment.
///
/// Both share the same multipart body shape:
/// ```
/// customer_id=...
/// card[0][service_id]=...
/// card[0][item_name]=...
/// card[0][employee_id]=...
/// card[0][employee_name]=...
/// card[0][minutes]=...
/// card[0][quantity]=1
/// card[0][price]=...
/// card[0][unitPrice]=...
/// card[0][date]=YYYY-MM-DD
/// card[0][time]=HH:mm
/// card[0][session_numbers]=0
/// type=
/// type_extra[car_number]=
/// type_extra[table_name]=
/// type_extra[latitude]=
/// type_extra[longitude]=
/// ```
class CreateBookingDialog extends StatefulWidget {
  const CreateBookingDialog({super.key});

  @override
  State<CreateBookingDialog> createState() => _CreateBookingDialogState();
}

class _CreateBookingDialogState extends State<CreateBookingDialog> {
  final BaseClient _client = BaseClient();
  final NumberFormat _amountFormatter = NumberFormat('#,##0.##');

  // ── Catalog state (services + flags) ─────────────────────────────────
  bool _isLoadingServices = true;
  String? _servicesError;
  List<Map<String, dynamic>> _services = [];
  bool _payLaterAllowed = true;
  bool _customerRequired = true;
  bool _posTimeSelection = true;
  bool _posEmployeeSelection = true;

  // ── Customers ────────────────────────────────────────────────────────
  bool _isLoadingCustomers = false;
  List<Map<String, dynamic>> _customers = [];
  Map<String, dynamic>? _selectedCustomer;
  final TextEditingController _customerSearchController =
      TextEditingController();
  Timer? _customerSearchDebounce;

  // ── Selected services (cart) ─────────────────────────────────────────
  final List<_BookingLine> _lines = [];

  // ── Submit state ─────────────────────────────────────────────────────
  bool _isSubmitting = false;
  String? _submitError;

  // Branch logo — used as fallback thumbnail when a service has no image.
  // Populated lazily from the cached branch-receipt info (same source the
  // home screen / service-selection dialog already reads from), so the
  // first paint reuses what's already in memory.
  String? _branchLogoUrl;

  String get _langCode =>
      translationService.currentLanguageCode.trim().toLowerCase();
  bool get _useArabicUi =>
      _langCode.startsWith('ar') || _langCode.startsWith('ur');
  String _tr(String ar, String en) => _useArabicUi ? ar : en;

  @override
  void initState() {
    super.initState();
    _loadCreateForm();
    _loadCustomers();
    _loadBranchLogo();
  }

  Future<void> _loadBranchLogo() async {
    try {
      final branchService = getIt<BranchService>();
      String url = '';
      final cached = branchService.cachedBranchReceiptInfo;
      if (cached != null) {
        // Top-level `branch_logo_url` is sourced from `/seller/branches`
        // which always returns the logo, while the nested `branch.logo`
        // depends on `/seller/get_branches/{id}` which 500s on some
        // accounts. Prefer the reliable top-level value.
        final topLevel = cached['branch_logo_url']?.toString().trim() ?? '';
        if (topLevel.isNotEmpty && topLevel.toLowerCase() != 'null') {
          url = topLevel;
        } else {
          final branch = cached['branch'];
          if (branch is Map) {
            url = (branch['logo'] ??
                    branch['image'] ??
                    (branch['seller'] is Map
                        ? branch['seller']['logo']
                        : null) ??
                    (branch['original_seller'] is Map
                        ? branch['original_seller']['logo']
                        : null) ??
                    '')
                .toString();
          }
        }
      }
      if (url.isEmpty) {
        url = await branchService.getBranchLogoUrl(ApiConstants.branchId);
      }
      if (url.isEmpty) return;
      if (url.startsWith('/')) url = 'https://portal.hermosaapp.com$url';
      if (!mounted) return;
      setState(() => _branchLogoUrl = url);
    } catch (_) {
      // Soft fail — fallback icon will show instead.
    }
  }

  @override
  void dispose() {
    _customerSearchController.dispose();
    _customerSearchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadCreateForm() async {
    setState(() {
      _isLoadingServices = true;
      _servicesError = null;
    });
    try {
      // GET /seller/branches/{id}/bookings/create?type=services&...
      final endpoint = '${ApiConstants.bookingCreateMetadataEndpoint}'
          '?type=services&is_favourite=0&category_id=&is_home=0&is_delivery=0&page=1&search=';
      final response = await _client.get(endpoint);

      List<Map<String, dynamic>> items = [];
      bool payLater = true;
      bool customerRequired = true;
      bool posTime = true;
      bool posEmployee = true;

      if (response is Map<String, dynamic>) {
        final dataRaw = response['data'];
        if (dataRaw is Map) {
          final data = Map<String, dynamic>.from(dataRaw);
          payLater = data['pay_later'] == true;
          customerRequired = data['customer_required'] == true;
          posTime = data['pos_time_selection'] == true;
          posEmployee = data['pos_employee_selection'] == true;

          final coll = data['collection'];
          dynamic collData;
          if (coll is Map) {
            collData = coll['data'];
          } else if (data['data'] is List) {
            collData = data['data'];
          }
          if (collData is List) {
            items = collData
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _services = items;
        _payLaterAllowed = payLater;
        _customerRequired = customerRequired;
        _posTimeSelection = posTime;
        _posEmployeeSelection = posEmployee;
        _isLoadingServices = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _servicesError = e.toString();
        _isLoadingServices = false;
      });
    }
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
      final dataRaw = response is Map<String, dynamic> ? response['data'] : null;
      final list = dataRaw is List
          ? dataRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _customers = list;
        _isLoadingCustomers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingCustomers = false);
    }
  }

  void _onCustomerSearchChanged(String value) {
    _customerSearchDebounce?.cancel();
    _customerSearchDebounce = Timer(const Duration(milliseconds: 350), () {
      _loadCustomers(search: value.trim());
    });
  }

  // ── Service / line helpers ───────────────────────────────────────────
  // The salon API returns service prices as `"350.00 ر.س"` — and the Arabic
  // currency suffix `ر.س` contains a literal dot. A naïve "strip non-digits
  // except dots" leaves `"350.00."` which `double.tryParse` rejects, so we
  // keep only the first dot and drop any subsequent ones.
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

  void _addService(Map<String, dynamic> service) async {
    final line = _BookingLine(
      serviceId: service['id']?.toString() ?? '',
      serviceName: service['name']?.toString() ?? '',
      price: _parseAmount(service['price']),
      minutes: int.tryParse(service['minutes']?.toString() ?? '') ?? 0,
      date: DateTime.now(),
      time: TimeOfDay.now(),
    );
    setState(() => _lines.add(line));

    if (_posEmployeeSelection) {
      // Auto-load eligible employees so the user only has to pick one. The
      // backend endpoint `/seller/bookings/branches/{id}/services/{sid}`
      // returns the employees who can perform this service plus available
      // time slots — see HAR line 4686.
      await _loadEmployeesForLine(line);
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadEmployeesForLine(_BookingLine line) async {
    try {
      final endpoint =
          ApiConstants.salonServiceEmployeesEndpoint(int.parse(line.serviceId));
      final response = await _client.get(endpoint);
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
      line.eligibleEmployees = employees;
    } catch (_) {
      // Soft fail — user can still type/pick later, or the booking can be
      // created without employee assignment if the branch doesn't require
      // pos_employee_selection.
    }
  }

  Future<void> _loadEmployeeSlotsForLine(_BookingLine line) async {
    final empId = line.employeeId;
    if (empId == null) return;
    try {
      // The backend rejects GET on this route with 405 — only PATCH/PUT
      // are accepted. Sending {date, service_id} as the JSON body returns
      // the same slot list and correctly omits any time the employee is
      // already booked at, so the cashier can't double-book a 19:30
      // slot for two different customers.
      final endpoint =
          ApiConstants.salonEmployeeAvailableTimesEndpoint(int.parse(empId));
      final dateStr = DateFormat('yyyy-MM-dd').format(line.date);
      final response = await _client.patch(endpoint, {
        'date': dateStr,
        'service_id': int.tryParse(line.serviceId) ?? line.serviceId,
      });
      List<Map<String, dynamic>> slots = [];
      if (response is Map<String, dynamic>) {
        final data = response['data'];
        if (data is List) {
          slots = data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
      line.availableSlots = slots;
    } catch (_) {
      line.availableSlots = [];
    }
  }

  double get _subtotal {
    double sum = 0;
    for (final l in _lines) {
      sum += l.price * l.quantity;
    }
    return sum;
  }

  bool get _canSubmit {
    if (_lines.isEmpty) return false;
    if (_customerRequired && _selectedCustomer == null) return false;
    return true;
  }

  Future<void> _submit({required bool bookAppointment}) async {
    if (!_canSubmit || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final fields = <String, String>{};
      final customerId = _selectedCustomer?['value']?.toString() ?? '';
      fields['customer_id'] = customerId;

      for (var i = 0; i < _lines.length; i++) {
        final l = _lines[i];
        final p = 'card[$i]';
        fields['$p[package_service_id]'] = '';
        fields['$p[item_name]'] = l.serviceName;
        fields['$p[service_id]'] = l.serviceId;
        fields['$p[minutes]'] = l.minutes.toString();
        fields['$p[employee_name]'] = l.employeeName ?? '';
        fields['$p[employee_id]'] = l.employeeId ?? '';
        fields['$p[date]'] = DateFormat('yyyy-MM-dd').format(l.date);
        // HAR always sends a time, even for pay-later (default to "now"
        // when the user didn't pick one). Backend rejects empty time on
        // the appointment flow.
        fields['$p[time]'] = _formatTime(l.time ?? TimeOfDay.now());
        fields['$p[session_numbers]'] = '0';
        fields['$p[quantity]'] = l.quantity.toString();
        fields['$p[price]'] = _moneyString(l.price);
        fields['$p[unitPrice]'] = _moneyString(l.price);
        fields['$p[modified_unit_price]'] = '';
      }

      // Type fields are sent empty in the HAR for in-store services. We
      // mirror that exactly so the backend doesn't infer a delivery / car
      // / table flow.
      fields['type'] = '';
      fields['type_extra[car_number]'] = '';
      fields['type_extra[table_name]'] = '';
      fields['type_extra[latitude]'] = '';
      fields['type_extra[longitude]'] = '';

      final query = bookAppointment
          ? '?book_appointment&create_order'
          : '?create_order';
      final endpoint = '${ApiConstants.bookingsEndpoint}$query';

      final response = await _client.postMultipart(endpoint, fields);

      // The slot-availability cache is keyed on (employee, service, date)
      // and the slot we just consumed is still in there. Drop it now so
      // the next booking attempt re-queries the backend instead of
      // re-offering the time we just took.
      try {
        getIt<SalonEmployeeService>().invalidateAvailableTimesCache();
      } catch (_) {}

      if (!mounted) return;
      final data = response is Map<String, dynamic> ? response['data'] : null;
      String? bookingId;
      if (data is Map) {
        bookingId =
            (data['id'] ?? data['booking_id'] ?? data['booking']?['id'])
                ?.toString();
      } else if (data is num) {
        bookingId = data.toString();
      }

      Navigator.of(context).pop({
        'id': bookingId ?? '',
        'book_appointment': bookAppointment,
        'data': data,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = e.toString();
        _isSubmitting = false;
      });
    }
  }

  String _moneyString(double v) {
    // Backend example sends "25" / "115" — plain integer when whole, else
    // up to digits_number decimals.
    if (v == v.roundToDouble()) {
      return v.toStringAsFixed(0);
    }
    return v.toStringAsFixed(ApiConstants.digitsNumber.clamp(0, 4));
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // ── UI ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 900;
    final dialogWidth = isCompact ? size.width * 0.95 : size.width * 0.85;
    final dialogHeight = size.height * 0.9;

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
              child: _isLoadingServices
                  ? const Center(child: CircularProgressIndicator())
                  : _servicesError != null
                      ? _buildLoadError()
                      : isCompact
                          ? _buildCompactBody()
                          : _buildWideBody(),
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
          const Icon(LucideIcons.calendarPlus,
              color: Color(0xFFF58220), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _tr('إنشاء حجز جديد', 'New Booking'),
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

  Widget _buildLoadError() {
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
              _servicesError ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appText),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadCreateForm,
              child: Text(_tr('إعادة المحاولة', 'Retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 5, child: _buildServiceCatalog()),
        VerticalDivider(width: 1, color: context.appBorder),
        Expanded(flex: 4, child: _buildCart()),
      ],
    );
  }

  Widget _buildCompactBody() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: _tr('الخدمات', 'Services')),
              Tab(text: _tr('السلة (${_lines.length})', 'Cart (${_lines.length})')),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [_buildServiceCatalog(), _buildCart()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCatalog() {
    if (_services.isEmpty) {
      return Center(
        child: Text(
          _tr('لا توجد خدمات متاحة', 'No services available'),
          style: TextStyle(color: context.appText.withValues(alpha: 0.7)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _services.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s = _services[i];
        final price = _parseAmount(s['price']);
        final imgUrl = s['image']?.toString() ?? '';
        return Material(
          color: context.appCardBg,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => _addService(s),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.appBorder),
              ),
              child: Row(
                children: [
                  _buildServiceThumbnail(imgUrl),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s['name']?.toString() ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: context.appText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s['minutes_format']?.toString() ?? '',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_amountFormatter.format(price)} ${ApiConstants.currency}',
                    style: const TextStyle(
                      color: Color(0xFFF58220),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(LucideIcons.plus,
                      size: 18, color: Color(0xFFF58220)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Renders a 44×44 thumbnail for a service. Order of preference:
  /// 1. The service's own `image` field.
  /// 2. The branch logo loaded from cached receipt info.
  /// 3. A small scissors badge in the salon brand palette.
  Widget _buildServiceThumbnail(String serviceImageUrl) {
    Widget content;
    if (serviceImageUrl.isNotEmpty) {
      content = CachedNetworkImage(
        imageUrl: serviceImageUrl,
        fit: BoxFit.cover,
        memCacheWidth: 100,
        placeholder: (_, __) => _branchLogoOrIcon(),
        errorWidget: (_, __, ___) => _branchLogoOrIcon(),
      );
    } else {
      content = _branchLogoOrIcon();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 44, height: 44, child: content),
    );
  }

  Widget _branchLogoOrIcon() {
    final logo = _branchLogoUrl;
    if (logo != null && logo.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: logo,
        fit: BoxFit.contain,
        memCacheWidth: 100,
        placeholder: (_, __) => _scissorsBadge(),
        errorWidget: (_, __, ___) => _scissorsBadge(),
      );
    }
    return _scissorsBadge();
  }

  Widget _scissorsBadge() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFF7ED),
        shape: BoxShape.circle,
      ),
      child: const Icon(LucideIcons.scissors,
          size: 22, color: Color(0xFFF58220)),
    );
  }

  Widget _buildCart() {
    return Column(
      children: [
        _buildCustomerSection(),
        const Divider(height: 1),
        Expanded(
          child: _lines.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _tr('أضف خدمة من القائمة',
                          'Add a service from the catalog'),
                      style: TextStyle(color: context.appText.withValues(alpha: 0.6)),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _lines.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _buildLineCard(_lines[i], i),
                ),
        ),
      ],
    );
  }

  Widget _buildCustomerSection() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _tr('العميل', 'Customer'),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: context.appText,
            ),
          ),
          const SizedBox(height: 8),
          if (_selectedCustomer != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF58220).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF58220)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.user,
                      size: 16, color: Color(0xFFF58220)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedCustomer!['label']?.toString() ?? '',
                      style: TextStyle(color: context.appText),
                    ),
                  ),
                  IconButton(
                    onPressed: () =>
                        setState(() => _selectedCustomer = null),
                    icon: const Icon(LucideIcons.x, size: 16),
                  ),
                ],
              ),
            )
          else
            TextField(
              controller: _customerSearchController,
              onChanged: _onCustomerSearchChanged,
              decoration: InputDecoration(
                hintText: _tr('ابحث عن عميل...', 'Search customer...'),
                isDense: true,
                prefixIcon: const Icon(LucideIcons.search, size: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          if (_selectedCustomer == null && _customers.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                border: Border.all(color: context.appBorder),
                borderRadius: BorderRadius.circular(8),
              ),
              child: _isLoadingCustomers
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
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
                          onTap: () => setState(() {
                            _selectedCustomer = c;
                            _customers = [];
                            _customerSearchController.clear();
                          }),
                        );
                      },
                    ),
            ),
          if (_customerRequired && _selectedCustomer == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _tr('* اختيار العميل مطلوب', '* Customer is required'),
                style: const TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLineCard(_BookingLine line, int index) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  line.serviceName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: context.appText,
                  ),
                ),
              ),
              Text(
                '${_amountFormatter.format(line.price * line.quantity)} ${ApiConstants.currency}',
                style: const TextStyle(
                  color: Color(0xFFF58220),
                  fontWeight: FontWeight.w800,
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _lines.removeAt(index)),
                icon: const Icon(LucideIcons.trash2,
                    size: 16, color: Color(0xFFEF4444)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_posEmployeeSelection)
            _buildEmployeeDropdown(line)
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _tr('بدون اختيار موظف', 'No employee assignment'),
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _buildDateField(line)),
              const SizedBox(width: 8),
              if (_posTimeSelection)
                Expanded(child: _buildTimeField(line)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                _tr('الكمية', 'Qty'),
                style: TextStyle(
                  fontSize: 12,
                  color: context.appText.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: line.quantity > 1
                    ? () => setState(() => line.quantity -= 1)
                    : null,
                icon: const Icon(LucideIcons.minus, size: 14),
                visualDensity: VisualDensity.compact,
              ),
              Text(
                '${line.quantity}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              IconButton(
                onPressed: () => setState(() => line.quantity += 1),
                icon: const Icon(LucideIcons.plus, size: 14),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeDropdown(_BookingLine line) {
    final emps = line.eligibleEmployees;
    if (emps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          _tr('جاري تحميل الموظفين...', 'Loading employees...'),
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: line.employeeId,
      isDense: true,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _tr('الموظف', 'Employee'),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: emps.map((e) {
        final id = (e['id'] ?? e['value'])?.toString() ?? '';
        final name = (e['fullname'] ?? e['name'] ?? e['label'])?.toString() ?? '';
        return DropdownMenuItem(value: id, child: Text(name));
      }).toList(),
      onChanged: (val) async {
        if (val == null) return;
        final picked = emps.firstWhere(
          (e) => (e['id'] ?? e['value'])?.toString() == val,
          orElse: () => {},
        );
        setState(() {
          line.employeeId = val;
          line.employeeName =
              (picked['fullname'] ?? picked['name'] ?? picked['label'])
                      ?.toString() ??
                  '';
          line.availableSlots = [];
          line.time = null;
        });
        await _loadEmployeeSlotsForLine(line);
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildDateField(_BookingLine line) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: line.date,
          firstDate: DateTime.now().subtract(const Duration(days: 1)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) {
          setState(() {
            line.date = picked;
            line.availableSlots = [];
            line.time = null;
          });
          await _loadEmployeeSlotsForLine(line);
          if (mounted) setState(() {});
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: _tr('التاريخ', 'Date'),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          DateFormat('yyyy-MM-dd').format(line.date),
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildTimeField(_BookingLine line) {
    final slots = line.availableSlots;
    if (slots.isNotEmpty) {
      // Backend gave us time slots — present them as a dropdown so the user
      // doesn't pick a time the employee can't work.
      return DropdownButtonFormField<String>(
        initialValue: line.time != null ? _formatTime(line.time!) : null,
        isDense: true,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: _tr('الوقت', 'Time'),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        items: slots.map((slot) {
          final value = slot['value']?.toString() ?? '';
          final label = slot['label']?.toString() ?? value;
          return DropdownMenuItem(value: value, child: Text(label));
        }).toList(),
        onChanged: (val) {
          if (val == null) return;
          final parts = val.split(':');
          if (parts.length == 2) {
            setState(() {
              line.time = TimeOfDay(
                hour: int.tryParse(parts[0]) ?? 0,
                minute: int.tryParse(parts[1]) ?? 0,
              );
            });
          }
        },
      );
    }

    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: line.time ?? TimeOfDay.now(),
        );
        if (picked != null) setState(() => line.time = picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: _tr('الوقت', 'Time'),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          line.time != null ? _formatTime(line.time!) : '--:--',
          style: const TextStyle(fontSize: 13),
        ),
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
              Text(
                _tr('الإجمالي:', 'Total:'),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: context.appText,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_amountFormatter.format(_subtotal)} ${ApiConstants.currency}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Color(0xFFF58220),
                ),
              ),
              const Spacer(),
              if (_payLaterAllowed)
                OutlinedButton.icon(
                  onPressed: _canSubmit && !_isSubmitting
                      ? () => _submit(bookAppointment: false)
                      : null,
                  icon: const Icon(LucideIcons.clock, size: 16),
                  label: Text(_tr('دفع لاحقاً', 'Pay Later')),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _canSubmit && !_isSubmitting
                    ? () => _submit(bookAppointment: true)
                    : null,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(LucideIcons.calendarCheck, size: 16),
                label: Text(_tr('حجز موعد', 'Book Appointment')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF58220),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BookingLine {
  final String serviceId;
  final String serviceName;
  final double price;
  final int minutes;
  int quantity;
  String? employeeId;
  String? employeeName;
  DateTime date;
  TimeOfDay? time;
  List<Map<String, dynamic>> eligibleEmployees;
  List<Map<String, dynamic>> availableSlots;

  _BookingLine({
    required this.serviceId,
    required this.serviceName,
    required this.price,
    required this.minutes,
    required this.date,
    this.time,
  })  : quantity = 1,
        eligibleEmployees = [],
        availableSlots = [];
}
