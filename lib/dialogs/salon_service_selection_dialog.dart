import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/language_service.dart';
import '../services/api/salon_employee_service.dart';
import '../locator.dart';
import '../services/app_themes.dart';

/// Dialog for selecting employee, date, time, and quantity when adding a salon
/// service to a booking cart.
///
/// Returns a [Map<String, dynamic>] matching the booking-create payload:
/// ```json
/// {
///   "package_service_id": null,
///   "item_name": "...",
///   "service_id": 1623,
///   "minutes": 75,
///   "employee_name": "...",
///   "employee_id": 111,
///   "date": "2026-03-01",
///   "time": "15:05",
///   "session_numbers": 0,
///   "quantity": 1,
///   "price": 700.01,
///   "unitPrice": 700.01,
///   "modified_unit_price": null
/// }
/// ```
class SalonServiceSelectionDialog extends StatefulWidget {
  /// The service data map as returned by `bookings/create?type=services`.
  final Map<String, dynamic> serviceData;

  /// List of employee option maps, each with at least `id` and `name`.
  /// Example: `[{"id": 111, "name": "ليلى المهدي"}, ...]`
  final List<Map<String, dynamic>> employees;

  const SalonServiceSelectionDialog({
    super.key,
    required this.serviceData,
    required this.employees,
  });

  /// Convenience launcher. Shows the dialog and returns the booking-item map
  /// or `null` if the user cancelled.
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required Map<String, dynamic> serviceData,
    required List<Map<String, dynamic>> employees,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (_) => SalonServiceSelectionDialog(
        serviceData: serviceData,
        employees: employees,
      ),
    );
  }

  @override
  State<SalonServiceSelectionDialog> createState() =>
      _SalonServiceSelectionDialogState();
}

class _SalonServiceSelectionDialogState
    extends State<SalonServiceSelectionDialog> {
  // ───────── brand palette (matches existing dialogs) ─────────
  static const _brand = Color(0xFFF58220);
  static const _brandLight = Color(0xFFFFF7ED);

  // ───────── state ─────────
  Map<String, dynamic>? _selectedEmployee;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  int _quantity = 1;
  late TextEditingController _priceController;
  bool _priceEdited = false;

  // Parsed service fields
  late final int _serviceId;
  late final String _serviceName;
  late final double _originalPrice;
  late final int _minutes;
  late final String _minutesFormat;
  late final String? _image;
  late final List<dynamic> _addonsGroups;
  late final List<dynamic> _addons;

  // Available times from API
  List<Map<String, dynamic>> _availableTimes = [];
  String? _selectedTimeSlot;
  bool _isLoadingTimes = false;

  // Addon selection: addonId -> quantity
  final Map<String, int> _selectedAddonQuantities = {};

  bool get _useArabicUi {
    final code = translationService.currentLanguageCode.trim().toLowerCase();
    return code.startsWith('ar') || code.startsWith('ur');
  }

  String _tr(String ar, String en) => _useArabicUi ? ar : en;

  // ───────── lifecycle ─────────
  @override
  void initState() {
    super.initState();
    final s = widget.serviceData;
    _serviceId = _parseInt(s['id']);
    _serviceName = (s['name'] ?? '').toString();
    _originalPrice = _parseDouble(s['price']);
    _minutes = _parseInt(s['minutes']);
    _minutesFormat = (s['minutes_format'] ?? '$_minutes min').toString();
    _image = s['image']?.toString();
    _addonsGroups = (s['addons_groups'] is List) ? s['addons_groups'] as List : [];
    _addons = (s['addons'] is List) ? s['addons'] as List : [];

    _selectedDate = DateTime.now();
    _selectedTime = _roundToNext5(TimeOfDay.now());
    _priceController =
        TextEditingController(text: _originalPrice.toStringAsFixed(2));

    // Pre-select first employee if available
    if (widget.employees.isNotEmpty) {
      _selectedEmployee = widget.employees.first;
      _fetchAvailableTimes();
    }
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  // ───────── helpers ─────────
  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  static double _parseDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) {
      // Strip currency symbols/arabic text, keep numbers and dots
      var cleaned = v.replaceAll(RegExp(r'[^\d.\-]'), '');
      // Handle multiple dots (e.g. "700.01 ر.س" → "700.01." after strip)
      final dotIndex = cleaned.indexOf('.');
      if (dotIndex >= 0) {
        cleaned = cleaned.substring(0, dotIndex + 1) +
            cleaned.substring(dotIndex + 1).replaceAll('.', '');
      }
      return double.tryParse(cleaned) ?? 0.0;
    }
    return 0.0;
  }

  TimeOfDay _roundToNext5(TimeOfDay t) {
    var m = t.minute;
    final remainder = m % 5;
    if (remainder != 0) m += (5 - remainder);
    if (m >= 60) {
      return TimeOfDay(hour: (t.hour + 1) % 24, minute: 0);
    }
    return TimeOfDay(hour: t.hour, minute: m);
  }

  double get _currentPrice {
    final text = _priceController.text.trim();
    return double.tryParse(text) ?? _originalPrice;
  }

  double? get _modifiedUnitPrice {
    if (!_priceEdited) return null;
    final edited = _currentPrice;
    if ((edited - _originalPrice).abs() < 0.001) return null;
    return edited;
  }

  double get _totalPrice => _currentPrice * _quantity + _addonsTotal;

  double get _addonsTotal {
    double total = 0;
    for (final entry in _selectedAddonQuantities.entries) {
      final addon = _findAddonById(entry.key);
      if (addon != null) {
        total += _parseDouble(addon['price']) * entry.value * _quantity;
      }
    }
    return total;
  }

  Map<String, dynamic>? _findAddonById(String id) {
    for (final addon in _addons) {
      if (addon is Map<String, dynamic> && addon['id']?.toString() == id) {
        return addon;
      }
    }
    for (final group in _addonsGroups) {
      if (group is Map<String, dynamic>) {
        final items = group['addons'] ?? group['items'] ?? group['options'];
        if (items is List) {
          for (final addon in items) {
            if (addon is Map<String, dynamic> &&
                addon['id']?.toString() == id) {
              return addon;
            }
          }
        }
      }
    }
    return null;
  }

  List<Map<String, dynamic>> get _allAddons {
    final merged = <String, Map<String, dynamic>>{};
    for (final addon in _addons) {
      if (addon is Map<String, dynamic>) {
        final id = addon['id']?.toString() ?? '';
        if (id.isNotEmpty) merged[id] = addon;
      }
    }
    for (final group in _addonsGroups) {
      if (group is Map<String, dynamic>) {
        final items = group['addons'] ?? group['items'] ?? group['options'];
        if (items is List) {
          for (final addon in items) {
            if (addon is Map<String, dynamic>) {
              final id = addon['id']?.toString() ?? '';
              if (id.isNotEmpty) merged[id] = addon;
            }
          }
        }
      }
    }
    return merged.values.toList();
  }

  // ───────── addon selection ─────────
  void _toggleAddon(String id) {
    setState(() {
      if (_selectedAddonQuantities.containsKey(id)) {
        _selectedAddonQuantities.remove(id);
      } else {
        _selectedAddonQuantities[id] = 1;
      }
    });
  }

  void _changeAddonQty(String id, int delta) {
    setState(() {
      final current = _selectedAddonQuantities[id];
      if (current == null) {
        if (delta > 0) _selectedAddonQuantities[id] = 1;
        return;
      }
      final next = current + delta;
      if (next <= 0) {
        _selectedAddonQuantities.remove(id);
      } else {
        _selectedAddonQuantities[id] = next;
      }
    });
  }

  // ───────── actions ─────────
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: _useArabicUi ? const Locale('ar') : const Locale('en'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _brand,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _fetchAvailableTimes();
    }
  }

  Future<void> _fetchAvailableTimes() async {
    final empId = _selectedEmployee?['id'];
    if (empId == null) return;
    setState(() {
      _isLoadingTimes = true;
      _availableTimes = [];
      _selectedTimeSlot = null;
    });
    try {
      final salonService = getIt<SalonEmployeeService>();
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final times = await salonService.getAvailableTimes(
        employeeId: empId is int ? empId : int.tryParse(empId.toString()) ?? 0,
        serviceId: _serviceId,
        date: dateStr,
      );
      if (mounted) {
        setState(() {
          _availableTimes = times;
          _isLoadingTimes = false;
          // Auto-select first available time
          if (times.isNotEmpty) {
            _selectedTimeSlot = times.first['value']?.toString();
            _syncTimeFromSlot();
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingTimes = false);
    }
  }

  void _syncTimeFromSlot() {
    if (_selectedTimeSlot == null) return;
    final parts = _selectedTimeSlot!.split(':');
    if (parts.length >= 2) {
      _selectedTime = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 0,
        minute: int.tryParse(parts[1]) ?? 0,
      );
    }
  }

  Future<void> _pickTime() async {
    // If available times loaded, don't open native picker - use dropdown instead
    if (_availableTimes.isNotEmpty) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _brand,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: Directionality(
            textDirection: _useArabicUi ? ui.TextDirection.rtl : ui.TextDirection.ltr,
            child: child!,
          ),
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  void _onConfirm() {
    if (_selectedEmployee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('يرجى اختيار الموظف', 'Please select an employee')),
          backgroundColor: Colors.red.shade600,
        ),
      );
      return;
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final timeStr =
        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

    final result = <String, dynamic>{
      'package_service_id': null,
      'item_name': _serviceName,
      'service_id': _serviceId,
      'minutes': _minutes,
      'employee_name': _selectedEmployee!['name']?.toString() ?? '',
      'employee_id': _parseInt(_selectedEmployee!['id']),
      'date': dateStr,
      'time': timeStr,
      'session_numbers': 0,
      'quantity': _quantity,
      'price': _currentPrice * _quantity,
      'unitPrice': _currentPrice,
      'modified_unit_price': _modifiedUnitPrice,
    };

    // Attach selected addons if any
    if (_selectedAddonQuantities.isNotEmpty) {
      final selectedAddons = <Map<String, dynamic>>[];
      for (final entry in _selectedAddonQuantities.entries) {
        final addon = _findAddonById(entry.key);
        if (addon != null) {
          for (var i = 0; i < entry.value; i++) {
            selectedAddons.add({
              'id': addon['id'],
              'name': addon['name'],
              'price': _parseDouble(addon['price']),
            });
          }
        }
      }
      result['addons'] = selectedAddons;
    }

    Navigator.pop(context, result);
  }

  // ══════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final isWide = screen.width >= 700;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isWide ? 24 : 8,
        vertical: isWide ? 16 : 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: isWide
            ? (screen.width * 0.85).clamp(700.0, 1200.0)
            : screen.width,
        height: (screen.height * 0.92).clamp(500.0, double.infinity),
        color: const Color(0xFFF4F4F4),
        child: Column(
          children: [
            _header(),
            Expanded(
              child: isWide ? _wideBody() : _narrowBody(),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────── HEADER ───────────────────────
  Widget _header() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: Colors.white,
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade400),
            ),
            child: const Center(
              child: Icon(LucideIcons.scissors, size: 16, color: _brand),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _serviceName,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(LucideIcons.x, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── WIDE BODY (tablet) ───────────────────────
  Widget _wideBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 40, child: _leftColumn()),
        const VerticalDivider(
            width: 1, thickness: 1, color: Color(0xFFE0E0E0)),
        Expanded(flex: 60, child: _rightColumn()),
      ],
    );
  }

  // ─────────────────────── NARROW BODY (phone) ───────────────────────
  Widget _narrowBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _serviceInfoCard(),
          const SizedBox(height: 14),
          _employeeDropdown(),
          const SizedBox(height: 14),
          _dateTimeRow(),
          const SizedBox(height: 14),
          _quantityRow(),
          const SizedBox(height: 14),
          _priceField(),
          const SizedBox(height: 14),
          ..._addonWidgets(),
        ],
      ),
    );
  }

  // ─────────────────────── LEFT COLUMN ───────────────────────
  Widget _leftColumn() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _serviceInfoCard(),
          const SizedBox(height: 18),
          Text(
            _tr('الموظف', 'Employee'),
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333)),
          ),
          const SizedBox(height: 8),
          _employeeDropdown(),
          const SizedBox(height: 18),
          Text(
            _tr('التاريخ والوقت', 'Date & Time'),
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333)),
          ),
          const SizedBox(height: 8),
          _dateTimeRow(),
          const SizedBox(height: 18),
          _quantityRow(),
          const SizedBox(height: 18),
          Text(
            _tr('السعر', 'Price'),
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333)),
          ),
          const SizedBox(height: 8),
          _priceField(),
        ],
      ),
    );
  }

  // ─────────────────────── RIGHT COLUMN ───────────────────────
  Widget _rightColumn() {
    final addons = _addonWidgets();
    if (addons.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.packageOpen, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              _tr('لا توجد إضافات', 'No add-ons available'),
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: addons,
      ),
    );
  }

  // ═══════════════════ COMPONENTS ═══════════════════

  // ── Service info card with image, name, price, duration ──
  Widget _serviceInfoCard() {
    final img = _image;
    final hasImg = img != null && img.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Image / initials
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _brandLight,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasImg
                ? CachedNetworkImage(
                    imageUrl: img,
                    fit: BoxFit.cover,
                    memCacheWidth: 200,
                    fadeInDuration: const Duration(milliseconds: 120),
                    placeholder: (_, __) => _imgPlaceholder(),
                    errorWidget: (_, __, ___) => _imgPlaceholder(),
                  )
                : _imgPlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _serviceName,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _infoBadge(
                      icon: LucideIcons.banknote,
                      label: '${_originalPrice.toStringAsFixed(2)} ${_tr('ر.س', 'SAR')}',
                    ),
                    const SizedBox(width: 8),
                    _infoBadge(
                      icon: LucideIcons.clock,
                      label: _minutesFormat,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imgPlaceholder() {
    final initials = _serviceName.length >= 2
        ? _serviceName.substring(0, 2).toUpperCase()
        : _serviceName.toUpperCase();
    return Center(
      child: Text(
        initials,
        style: const TextStyle(
            fontSize: 24, fontWeight: FontWeight.bold, color: _brand),
      ),
    );
  }

  Widget _infoBadge({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _brandLight,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _brand),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: _brand),
          ),
        ],
      ),
    );
  }

  // ── Employee dropdown ──
  Widget _employeeDropdown() {
    return Container(
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Map<String, dynamic>>(
          value: _selectedEmployee,
          isExpanded: true,
          hint: Text(
            _tr('اختر الموظف', 'Select employee'),
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          icon: const Icon(LucideIcons.chevronDown, size: 18),
          items: widget.employees.map((emp) {
            return DropdownMenuItem<Map<String, dynamic>>(
              value: emp,
              child: Text(
                emp['name']?.toString() ?? '',
                style: const TextStyle(fontSize: 14),
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() => _selectedEmployee = value);
            _fetchAvailableTimes();
          },
        ),
      ),
    );
  }

  // ── Date and Time pickers row ──
  Widget _dateTimeRow() {
    final dateText = DateFormat('yyyy-MM-dd').format(_selectedDate);

    return Column(
      children: [
        // Date picker
        _pickerTile(
          icon: LucideIcons.calendar,
          label: dateText,
          onTap: _pickDate,
        ),
        const SizedBox(height: 10),
        // Time: dropdown of available slots (or manual picker fallback)
        _buildTimeSelector(),
      ],
    );
  }

  Widget _buildTimeSelector() {
    if (_isLoadingTimes) {
      return Container(
        height: 48,
        decoration: BoxDecoration(
          color: context.appCardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.appBorder),
        ),
        child: const Center(
          child: SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: _brand),
          ),
        ),
      );
    }

    if (_availableTimes.isNotEmpty) {
      return Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: context.appCardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.appBorder),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedTimeSlot,
            isExpanded: true,
            icon: const Icon(LucideIcons.clock, size: 18, color: _brand),
            hint: Text(
              _tr('اختر الوقت', 'Select time'),
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            ),
            items: _availableTimes.map((t) {
              final val = t['value']?.toString() ?? '';
              final label = t['label']?.toString() ?? val;
              return DropdownMenuItem<String>(
                value: val,
                child: Text(label, style: const TextStyle(fontSize: 14)),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                _selectedTimeSlot = val;
                _syncTimeFromSlot();
              });
            },
          ),
        ),
      );
    }

    // Fallback: manual time picker
    final timeText =
        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';
    return _pickerTile(
      icon: LucideIcons.clock,
      label: timeText,
      onTap: _pickTime,
    );
  }

  Widget _pickerTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: context.appCardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: _brand),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(LucideIcons.chevronDown, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  // ── Quantity row (matches product_customization_dialog style) ──
  Widget _quantityRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _circleBtn(
          LucideIcons.minus,
          () => setState(() => _quantity = _quantity > 1 ? _quantity - 1 : 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Text(
            '$_quantity',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        _circleBtn(
          LucideIcons.plus,
          () => setState(() => _quantity += 1),
        ),
      ],
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(color: _brand, shape: BoxShape.circle),
        child: Icon(icon, size: 22, color: Colors.white),
      ),
    );
  }

  // ── Price field (editable) ──
  Widget _priceField() {
    return TextField(
      controller: _priceController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      onChanged: (_) {
        setState(() => _priceEdited = true);
      },
      decoration: InputDecoration(
        prefixIcon: const Icon(LucideIcons.banknote, size: 18, color: _brand),
        suffixText: _tr('ر.س', 'SAR'),
        suffixStyle: TextStyle(fontSize: 13, color: Colors.grey[500]),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _brand),
        ),
      ),
    );
  }

  // ── Addon sections ──
  List<Widget> _addonWidgets() {
    final allAddons = _allAddons;
    if (allAddons.isEmpty) return [];

    final widgets = <Widget>[];
    widgets.add(Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        _tr('الإضافات', 'Add-ons'),
        style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF333333)),
      ),
    ));

    // If we have grouped addons, show by group
    if (_addonsGroups.isNotEmpty) {
      for (final group in _addonsGroups) {
        if (group is! Map<String, dynamic>) continue;
        final groupName = (group['name'] ?? group['title'] ?? '').toString();
        final items =
            group['addons'] ?? group['items'] ?? group['options'] ?? [];
        if (items is! List || items.isEmpty) continue;

        if (groupName.isNotEmpty &&
            groupName.trim().toLowerCase() != 'global') {
          widgets.add(Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(
              groupName,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700]),
            ),
          ));
        }

        final addonMaps = items
            .whereType<Map<String, dynamic>>()
            .where((a) => a['id'] != null)
            .toList();
        widgets.add(_addonsGrid(addonMaps));
        widgets.add(const SizedBox(height: 10));
      }
    }

    // Flat addons list (not in groups)
    if (_addons.isNotEmpty) {
      final flatAddons = _addons
          .whereType<Map<String, dynamic>>()
          .where((a) => a['id'] != null)
          .toList();
      if (flatAddons.isNotEmpty) {
        widgets.add(_addonsGrid(flatAddons));
        widgets.add(const SizedBox(height: 10));
      }
    }

    return widgets;
  }

  Widget _addonsGrid(List<Map<String, dynamic>> addons) {
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 480
          ? 3
          : box.maxWidth >= 300
              ? 2
              : 1;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          childAspectRatio: 0.88,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: addons.length,
        itemBuilder: (_, i) {
          final addon = addons[i];
          final id = addon['id']?.toString() ?? '';
          // PERF: RepaintBoundary + stable ValueKey per addon card. Parent
          // setState on any addon change still rebuilds the grid, but each
          // card becomes its own repaint region so unrelated cards are not
          // repainted on every toggle. Framework compares keys to reuse
          // element slots, eliminating layout/paint for untouched cards.
          return RepaintBoundary(
            key: ValueKey('addon_$id'),
            child: _addonCard(addon),
          );
        },
      );
    });
  }

  Widget _addonCard(Map<String, dynamic> addon) {
    final id = addon['id']?.toString() ?? '';
    final name = (addon['name'] ?? '').toString();
    final price = _parseDouble(addon['price']);
    final selected = _selectedAddonQuantities.containsKey(id);
    final qty = _selectedAddonQuantities[id] ?? 1;

    return InkWell(
      onTap: () => _toggleAddon(id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: context.appCardBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? _brand : Colors.grey[300]!,
            width: selected ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          children: [
            // Image area
            Expanded(
              flex: 6,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFFFF3E0)
                      : const Color(0xFFEEEEEE),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(7)),
                ),
                child: Center(
                  child: Text(
                    name.length >= 2
                        ? name.substring(0, 2).toUpperCase()
                        : name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: selected ? _brand : Colors.grey[400],
                    ),
                  ),
                ),
              ),
            ),
            // Text area
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      price.toStringAsFixed(2),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: selected ? _brand : Colors.grey[600],
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _tinyBtn(LucideIcons.minus, const Color(0xFFEF5350),
                              () => _changeAddonQty(id, -1)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text('$qty',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                          _tinyBtn(LucideIcons.plus, _brand,
                              () => _changeAddonQty(id, 1)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tinyBtn(IconData icon, Color bg, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, size: 13, color: Colors.white),
      ),
    );
  }

  // ─────────────────────── FOOTER ───────────────────────
  Widget _footer() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Total summary
          if (_addonsTotal > 0 || _quantity > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _tr('الإجمالي', 'Total'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${_totalPrice.toStringAsFixed(2)} ${_tr('ر.س', 'SAR')}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _brand),
                  ),
                ],
              ),
            ),
          // Add button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: _brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: Text(
                _tr('إضافة للحجز', 'Add to Booking'),
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
