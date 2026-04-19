import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../services/api/api_constants.dart';
import '../services/api/base_client.dart';
import '../services/api/salon_employee_service.dart';
import '../services/api/filter_service.dart';
import '../services/language_service.dart';
import '../locator.dart';
import '../services/app_themes.dart';

class CreateDepositDialog extends StatefulWidget {
  const CreateDepositDialog({super.key});

  @override
  State<CreateDepositDialog> createState() => _CreateDepositDialogState();
}

class _CreateDepositDialogState extends State<CreateDepositDialog> {
  final SalonEmployeeService _salonService = getIt<SalonEmployeeService>();
  final FilterService _filterService = getIt<FilterService>();
  final NumberFormat _amountFormatter = NumberFormat('#,##0.##');

  // Form data
  Map<String, dynamic>? _selectedCustomer;
  final List<_SelectedService> _selectedServices = [];
  final TextEditingController _notesController = TextEditingController();
  DateTime _bookingDate = DateTime.now();
  TimeOfDay _bookingTime = TimeOfDay.now();

  // Payment data
  List<Map<String, dynamic>> _payMethods = [];
  String? _selectedPayMethodKey;
  final TextEditingController _payAmountController = TextEditingController();

  // Customer search
  List<Map<String, dynamic>> _customers = [];
  final TextEditingController _customerSearchController =
      TextEditingController();
  Timer? _customerSearchDebounce;
  bool _isLoadingCustomers = false;

  bool _isLoadingPayMethods = false;
  bool _isCreating = false;
  String? _error;

  String get _langCode =>
      translationService.currentLanguageCode.trim().toLowerCase();
  bool get _useArabicUi =>
      _langCode.startsWith('ar') || _langCode.startsWith('ur');
  String _tr(String ar, String en) => _useArabicUi ? ar : en;

  static const double _taxRate = 0.15;

  // Computed totals
  double get _subtotal {
    double sum = 0;
    for (final s in _selectedServices) {
      sum += s.price * s.quantity;
    }
    return sum;
  }

  double get _tax => _subtotal * _taxRate;
  double get _total => _subtotal + _tax;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _loadPayMethods();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _customerSearchController.dispose();
    _payAmountController.dispose();
    _customerSearchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadCustomers({String? search}) async {
    setState(() => _isLoadingCustomers = true);
    try {
      final response = await _filterService.getCustomers(search: search);
      final data = response['data'];
      if (data is List && mounted) {
        setState(() {
          _customers = data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _isLoadingCustomers = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingCustomers = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCustomers = false);
    }
  }

  Future<void> _loadPayMethods() async {
    setState(() => _isLoadingPayMethods = true);
    try {
      final response = await _filterService.getPaymentMethods();
      final data = response['data'];
      if (data is List && mounted) {
        final methods = data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        setState(() {
          _payMethods = methods;
          _isLoadingPayMethods = false;
          if (methods.isNotEmpty) {
            _selectedPayMethodKey =
                methods.first['value']?.toString() ??
                    methods.first['id']?.toString() ??
                    '';
          }
        });
      } else {
        if (mounted) setState(() => _isLoadingPayMethods = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingPayMethods = false);
    }
  }

  void _onCustomerSearch(String value) {
    _customerSearchDebounce?.cancel();
    _customerSearchDebounce = Timer(const Duration(milliseconds: 400), () {
      _loadCustomers(search: value.isEmpty ? null : value);
    });
  }

  Future<void> _pickBookingDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _bookingDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _bookingDate = picked);
    }
  }

  Future<void> _pickBookingTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _bookingTime,
    );
    if (picked != null && mounted) {
      setState(() => _bookingTime = picked);
    }
  }

  void _openServicePicker() async {
    final result = await showDialog<_SelectedService>(
      context: context,
      builder: (ctx) => _ServicePickerDialog(tr: _tr),
    );
    if (result != null && mounted) {
      setState(() {
        // Check if already exists, bump quantity if so
        final existing = _selectedServices.indexWhere(
            (s) => s.id == result.id);
        if (existing >= 0) {
          _selectedServices[existing].quantity += 1;
        } else {
          _selectedServices.add(result);
        }
      });
      // Auto-fill payment amount to total
      _payAmountController.text = _total.toStringAsFixed(2);
    }
  }

  Future<void> _createDeposit() async {
    // Validation
    if (_selectedCustomer == null) {
      setState(() =>
          _error = _tr('يرجى اختيار العميل', 'Please select a customer'));
      return;
    }
    if (_selectedServices.isEmpty) {
      setState(() =>
          _error = _tr('يرجى اختيار خدمة واحدة على الأقل', 'Please select at least one service'));
      return;
    }
    if (_subtotal <= 0) {
      setState(
          () => _error = _tr('الإجمالي يجب أن يكون أكبر من صفر', 'Total must be greater than zero'));
      return;
    }

    setState(() {
      _isCreating = true;
      _error = null;
    });

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final bookingDateStr = DateFormat('yyyy-MM-dd').format(_bookingDate);
      final bookingTimeStr =
          '${_bookingTime.hour.toString().padLeft(2, '0')}:${_bookingTime.minute.toString().padLeft(2, '0')}';

      final fields = <String, String>{
        'customer_id':
            (_selectedCustomer!['value'] ?? _selectedCustomer!['id'] ?? '')
                .toString(),
        'price': _subtotal.toStringAsFixed(2),
        'total': _total.toStringAsFixed(2),
        'date': dateStr,
        'booking_date': bookingDateStr,
        'booking_time': bookingTimeStr,
        'notes': _notesController.text,
      };

      // Add services[] array
      int serviceIndex = 0;
      for (final service in _selectedServices) {
        for (int q = 0; q < service.quantity; q++) {
          fields['services[$serviceIndex]'] = service.id;
          serviceIndex++;
        }
      }

      // Add pays - send ALL methods, even with 0 amount
      final payAmount =
          double.tryParse(_payAmountController.text) ?? 0.0;
      int payIndex = 0;
      for (final method in _payMethods) {
        final key =
            method['value']?.toString() ?? method['id']?.toString() ?? '';
        final label = method['label']?.toString() ?? key;
        final isSelected = key == _selectedPayMethodKey;
        final amount = isSelected ? payAmount : 0.0;

        fields['pays[$payIndex][name]'] = label;
        fields['pays[$payIndex][pay_method]'] = key;
        fields['pays[$payIndex][amount]'] = amount.toStringAsFixed(2);
        fields['pays[$payIndex][index]'] = payIndex.toString();
        payIndex++;
      }

      await _salonService.createDeposit(fields);

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCreating = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 700;
    final insetPadding = EdgeInsets.symmetric(
      horizontal: isCompact ? 12 : 24,
      vertical: isCompact ? 16 : 24,
    );
    final dialogWidth =
        (size.width - insetPadding.horizontal).clamp(280.0, 760.0).toDouble();
    final dialogHeight =
        (size.height - insetPadding.vertical).clamp(420.0, 820.0).toDouble();

    return Dialog(
      insetPadding: insetPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            // ── Header ──
            Container(
              padding: EdgeInsets.all(isCompact ? 16 : 24),
              decoration: const BoxDecoration(
                color: Color(0xFFF58220),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tr('إنشاء عربون', 'Create Deposit'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isCompact ? 18 : 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _tr('اختر الخدمات وأكمل البيانات',
                              'Select services and fill in details'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isCreating
                        ? null
                        : () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // ── Body ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Error message
                    if (_error != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: Text(
                          _error!,
                          style:
                              TextStyle(color: Colors.red[700], fontSize: 12),
                        ),
                      ),

                    // ── 1. Customer Selector ──
                    _buildSectionLabel(
                        _tr('العميل', 'Customer'), LucideIcons.user),
                    const SizedBox(height: 8),
                    _buildCustomerSelector(),
                    const SizedBox(height: 16),

                    // ── 2. Selected Services List ──
                    _buildSectionLabel(
                        _tr('الخدمات', 'Services'), LucideIcons.scissors),
                    const SizedBox(height: 8),
                    if (_selectedServices.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: context.appBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: context.appBorder),
                        ),
                        child: Center(
                          child: Text(
                            _tr('لم يتم اختيار خدمات بعد',
                                'No services selected yet'),
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 13),
                          ),
                        ),
                      )
                    else
                      ...List.generate(_selectedServices.length, (index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildEditableServiceCard(
                              _selectedServices[index]),
                        );
                      }),
                    const SizedBox(height: 8),

                    // ── 3. Add Service Button ──
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openServicePicker,
                        icon: const Icon(LucideIcons.plus, size: 16),
                        label: Text(_tr('إضافة خدمة', 'Add Service')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF58220),
                          side: const BorderSide(color: Color(0xFFF58220)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── 4. Auto-calculated Totals ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.appBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.appBorder),
                      ),
                      child: Column(
                        children: [
                          _buildTotalRow(
                            _tr('المجموع', 'Subtotal'),
                            '${_amountFormatter.format(_subtotal)} ${ApiConstants.currency}',
                          ),
                          const SizedBox(height: 6),
                          _buildTotalRow(
                            _tr('الضريبة (15%)', 'Tax (15%)'),
                            '${_amountFormatter.format(_tax)} ${ApiConstants.currency}',
                          ),
                          const Divider(height: 16),
                          _buildTotalRow(
                            _tr('الإجمالي', 'Total'),
                            '${_amountFormatter.format(_total)} ${ApiConstants.currency}',
                            isBold: true,
                            color: const Color(0xFFF58220),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── 5. Booking Date & Time ──
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionLabel(
                                  _tr('تاريخ الحجز', 'Booking Date'),
                                  LucideIcons.calendarDays),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: _pickBookingDate,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: context.appCardBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: context.appBorder),
                                  ),
                                  child: Text(
                                    DateFormat('yyyy-MM-dd')
                                        .format(_bookingDate),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSectionLabel(
                                  _tr('وقت الحجز', 'Booking Time'),
                                  LucideIcons.clock),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: _pickBookingTime,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: context.appCardBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: context.appBorder),
                                  ),
                                  child: Text(
                                    '${_bookingTime.hour.toString().padLeft(2, '0')}:${_bookingTime.minute.toString().padLeft(2, '0')}',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── 6. Notes ──
                    _buildSectionLabel(
                        _tr('ملاحظات', 'Notes'), LucideIcons.fileText),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notesController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: _tr('أدخل ملاحظاتك', 'Enter notes'),
                        hintStyle:
                            TextStyle(color: Colors.grey[400], fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xFFF58220)),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── 7. Payment Method ──
                    _buildSectionLabel(
                        _tr('طريقة الدفع', 'Payment Method'),
                        LucideIcons.creditCard),
                    const SizedBox(height: 8),
                    _buildPaymentMethodSection(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // ── Footer ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.appBg,
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isCreating
                          ? null
                          : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(_tr('إلغاء', 'Cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isCreating ? null : _createDeposit,
                      icon: _isCreating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.check, size: 16),
                      label: Text(
                        _isCreating
                            ? _tr('جارٍ الإنشاء...', 'Creating...')
                            : _tr('إنشاء عربون', 'Create Deposit'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF58220),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section label ──
  Widget _buildSectionLabel(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF64748B)),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF475569),
          ),
        ),
      ],
    );
  }

  // ── Customer selector ──
  Widget _buildCustomerSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search field
        TextField(
          controller: _customerSearchController,
          onChanged: _onCustomerSearch,
          decoration: InputDecoration(
            hintText: _tr('ابحث عن عميل...', 'Search customer...'),
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
            prefixIcon: const Icon(Icons.search, size: 18),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFF58220)),
            ),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
          ),
        ),
        const SizedBox(height: 6),
        // Customer dropdown list
        Container(
          constraints: const BoxConstraints(maxHeight: 120),
          decoration: BoxDecoration(
            border: Border.all(color: context.appBorder),
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
          ),
          child: _isLoadingCustomers
              ? const Center(
                  child: Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ))
              : _customers.isEmpty
                  ? Center(
                      child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _tr('لا يوجد عملاء', 'No customers'),
                        style:
                            TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _customers.length,
                      padding: EdgeInsets.zero,
                      itemBuilder: (ctx, idx) {
                        final c = _customers[idx];
                        final name = c['label']?.toString() ??
                            c['name']?.toString() ??
                            '';
                        final id = c['value'] ?? c['id'];
                        final isSelected =
                            _selectedCustomer?['value'] == id ||
                                _selectedCustomer?['id'] == id;
                        return InkWell(
                          onTap: () => setState(() => _selectedCustomer = c),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFF58220)
                                      .withValues(alpha: 0.08)
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? LucideIcons.checkCircle
                                      : LucideIcons.circle,
                                  size: 16,
                                  color: isSelected
                                      ? const Color(0xFFF58220)
                                      : Colors.grey[400],
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: context.appText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
        // Selected customer badge
        if (_selectedCustomer != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.checkCircle,
                      size: 14, color: Color(0xFF22C55E)),
                  const SizedBox(width: 6),
                  Text(
                    _selectedCustomer!['label']?.toString() ??
                        _selectedCustomer!['name']?.toString() ??
                        '',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF22C55E),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Editable service card (like _buildEditableItemCard) ──
  Widget _buildEditableServiceCard(_SelectedService service) {
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
          // Service name + delete button
          Row(
            children: [
              Expanded(
                child: Text(
                  service.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedServices.remove(service);
                  });
                  _payAmountController.text = _total.toStringAsFixed(2);
                },
                icon: const Icon(LucideIcons.trash2, size: 16),
                color: const Color(0xFFEF4444),
                tooltip: _tr('حذف', 'Remove'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Quantity +/- and price
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _QtyButton(
                    icon: LucideIcons.minus,
                    onPressed: () {
                      setState(() {
                        service.quantity =
                            (service.quantity - 1).clamp(1, 9999);
                      });
                      _payAmountController.text =
                          _total.toStringAsFixed(2);
                    },
                  ),
                  const SizedBox(width: 8),
                  Text(
                    service.quantity.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  _QtyButton(
                    icon: LucideIcons.plus,
                    onPressed: () {
                      setState(() {
                        service.quantity =
                            (service.quantity + 1).clamp(1, 9999);
                      });
                      _payAmountController.text =
                          _total.toStringAsFixed(2);
                    },
                  ),
                ],
              ),
              const Spacer(),
              Text(
                '${_amountFormatter.format(service.price * service.quantity)} ${ApiConstants.currency}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFF58220),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Totals row ──
  Widget _buildTotalRow(String label, String value,
      {bool isBold = false, Color? color}) {
    return Row(
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
    );
  }

  // ── Payment method section (chips + amount) ──
  Widget _buildPaymentMethodSection() {
    if (_isLoadingPayMethods) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    if (_payMethods.isEmpty) {
      return Text(
        _tr('لا توجد طرق دفع', 'No payment methods'),
        style: TextStyle(color: Colors.grey[400], fontSize: 12),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Payment method chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _payMethods.map((method) {
            final key =
                method['value']?.toString() ?? method['id']?.toString() ?? '';
            final label = method['label']?.toString() ?? key;
            final isSelected = _selectedPayMethodKey == key;

            return ChoiceChip(
              selected: isSelected,
              label: Text(label),
              onSelected: (_) {
                setState(() => _selectedPayMethodKey = key);
              },
              selectedColor: const Color(0xFFF58220).withValues(alpha: 0.18),
              backgroundColor: const Color(0xFFF8FAFC),
              labelStyle: TextStyle(
                color: isSelected
                    ? const Color(0xFFF58220)
                    : const Color(0xFF475569),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              side: BorderSide(
                color: isSelected
                    ? const Color(0xFFF58220)
                    : const Color(0xFFE2E8F0),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        // Amount field
        TextField(
          controller: _payAmountController,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText:
                '${_tr('المبلغ', 'Amount')} (${ApiConstants.currency})',
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFF58220)),
            ),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            prefixIcon: const Icon(LucideIcons.banknote,
                size: 16, color: Color(0xFF94A3B8)),
          ),
        ),
      ],
    );
  }
}

// ── Quantity Button (same as edit_order_dialog) ──
class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _QtyButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: context.appSurfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: context.appBorder),
        ),
        child: Icon(icon, size: 14, color: const Color(0xFF0F172A)),
      ),
    );
  }
}

// ── Selected Service model ──
class _SelectedService {
  final String id;
  final String name;
  final double price;
  int quantity;

  _SelectedService({
    required this.id,
    required this.name,
    required this.price,
    int quantity = 1,
  }) : quantity = quantity;
}

// ── Service Picker Dialog (like _ProductPickerDialog) ──
class _ServicePickerDialog extends StatefulWidget {
  final String Function(String ar, String en) tr;

  const _ServicePickerDialog({required this.tr});

  @override
  State<_ServicePickerDialog> createState() => _ServicePickerDialogState();
}

class _ServicePickerDialogState extends State<_ServicePickerDialog> {
  final SalonEmployeeService _salonService = getIt<SalonEmployeeService>();
  final BaseClient _client = BaseClient();
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _amountFormatter = NumberFormat('#,##0.##');

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _services = [];
  String _selectedCategory = 'all';
  bool _isLoadingServices = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadServices();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final response =
          await _client.get(ApiConstants.serviceCategoriesEndpoint);
      final data =
          response is Map<String, dynamic> ? response['data'] : response;
      if (data is List && mounted) {
        setState(() {
          _categories = data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
      }
    } catch (_) {
      // Categories are optional; ignore errors
    }
  }

  Future<void> _loadServices() async {
    setState(() => _isLoadingServices = true);
    try {
      final services = await _salonService.getAllServices();
      if (mounted) {
        setState(() {
          _services = services;
          _isLoadingServices = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingServices = false);
    }
  }

  List<Map<String, dynamic>> get _filteredServices {
    var list = _services;

    // Filter by category
    if (_selectedCategory != 'all') {
      list = list.where((s) {
        final catId = s['category_id']?.toString() ?? '';
        return catId == _selectedCategory;
      }).toList();
    }

    // Filter by search
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list
          .where(
              (s) => (s['label']?.toString() ?? '').toLowerCase().contains(query))
          .toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 700;
    final dialogWidth = isCompact ? size.width * 0.92 : size.width * 0.7;
    final dialogHeight = isCompact ? size.height * 0.82 : size.height * 0.75;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.tr('اختيار خدمة', 'Select a Service'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: widget.tr('ابحث عن خدمة', 'Search services'),
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Category chips
            if (_categories.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _categories.length + 1,
                  itemBuilder: (context, index) {
                    final isAll = index == 0;
                    final category = isAll ? null : _categories[index - 1];
                    final label = isAll
                        ? widget.tr('الكل', 'All')
                        : category?['label']?.toString() ??
                            category?['name']?.toString() ??
                            '';
                    final value = isAll
                        ? 'all'
                        : category?['value']?.toString() ??
                            category?['id']?.toString() ??
                            '';
                    final selected = _selectedCategory == value;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: selected,
                        label: Text(label),
                        onSelected: (_) {
                          setState(() => _selectedCategory = value);
                        },
                        selectedColor:
                            const Color(0xFFF58220).withValues(alpha: 0.18),
                        labelStyle: TextStyle(
                          color: selected
                              ? const Color(0xFFF58220)
                              : const Color(0xFF475569),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        side: BorderSide(
                          color: selected
                              ? const Color(0xFFF58220)
                              : const Color(0xFFE2E8F0),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),

            // Services list
            Expanded(
              child: _isLoadingServices
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredServices.isEmpty
                      ? Center(
                          child: Text(
                            widget.tr('لا توجد خدمات', 'No services found'),
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredServices.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, color: Color(0xFFE2E8F0)),
                          itemBuilder: (context, index) {
                            final service = _filteredServices[index];
                            final label =
                                service['label']?.toString() ?? '';
                            final price = double.tryParse(
                                    service['price']?.toString() ?? '') ??
                                0.0;
                            final serviceId =
                                (service['value'] ?? service['id'] ?? '')
                                    .toString();

                            return InkWell(
                              onTap: () {
                                Navigator.pop(
                                  context,
                                  _SelectedService(
                                    id: serviceId,
                                    name: label,
                                    price: price,
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 4),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF58220)
                                            .withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        LucideIcons.scissors,
                                        size: 16,
                                        color: Color(0xFFF58220),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${_amountFormatter.format(price)} ${ApiConstants.currency}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFF58220),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
