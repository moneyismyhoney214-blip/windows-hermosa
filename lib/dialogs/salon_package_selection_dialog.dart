import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../services/language_service.dart';
import '../services/api/salon_employee_service.dart';
import '../locator.dart';
import '../services/app_themes.dart';

/// Dialog for selecting employee, date, and time for EACH service inside a
/// salon package before adding it to the booking cart.
///
/// Returns a [List<Map<String, dynamic>>] where each element is a cart-item map
/// matching the booking-create payload shape (one per service in the package).
/// Returns `null` if the user cancelled.
class SalonPackageSelectionDialog extends StatefulWidget {
  /// The package data map as returned by `bookings/create?type=packageServices`.
  final Map<String, dynamic> packageData;

  /// List of all employee option maps.
  final List<Map<String, dynamic>> employees;

  /// Maps service ID -> list of employees who can perform that service.
  final Map<int, List<Map<String, dynamic>>> serviceEmployeeMap;

  const SalonPackageSelectionDialog({
    super.key,
    required this.packageData,
    required this.employees,
    required this.serviceEmployeeMap,
  });

  /// Convenience launcher.
  static Future<List<Map<String, dynamic>>?> show(
    BuildContext context, {
    required Map<String, dynamic> packageData,
    required List<Map<String, dynamic>> employees,
    required Map<int, List<Map<String, dynamic>>> serviceEmployeeMap,
  }) {
    return showDialog<List<Map<String, dynamic>>>(
      context: context,
      barrierDismissible: true,
      builder: (_) => SalonPackageSelectionDialog(
        packageData: packageData,
        employees: employees,
        serviceEmployeeMap: serviceEmployeeMap,
      ),
    );
  }

  @override
  State<SalonPackageSelectionDialog> createState() =>
      _SalonPackageSelectionDialogState();
}

class _SalonPackageSelectionDialogState
    extends State<SalonPackageSelectionDialog> {
  // ───────── brand palette ─────────
  static const _brand = Color(0xFFF58220);
  static const _brandLight = Color(0xFFFFF7ED);

  // ───────── parsed package fields ─────────
  late final int _packageId;
  late final String _packageName;
  late final double _packagePrice;
  late final String _minutesFormat;
  late final List<Map<String, dynamic>> _services;

  // ───────── per-service state ─────────
  // Indexed by position in _services list.
  late List<Map<String, dynamic>?> _selectedEmployees;
  late List<DateTime> _selectedDates;
  late List<TimeOfDay> _selectedTimes;
  late List<List<Map<String, dynamic>>> _availableTimes; // per-service
  late List<String?> _selectedTimeSlots; // per-service
  late List<bool> _isLoadingTimes; // per-service

  bool get _useArabicUi {
    final code = translationService.currentLanguageCode.trim().toLowerCase();
    return code.startsWith('ar') || code.startsWith('ur');
  }

  String _tr(String ar, String en) => _useArabicUi ? ar : en;

  // ───────── lifecycle ─────────
  @override
  void initState() {
    super.initState();
    final p = widget.packageData;
    _packageId = _parseInt(p['id']);
    _packageName = (p['name'] ?? '').toString();
    _packagePrice = _parseDouble(p['price']);
    _minutesFormat = (p['minutes_format'] ?? '').toString();

    // Parse services list
    final rawServices = p['services'];
    _services = <Map<String, dynamic>>[];
    if (rawServices is List) {
      for (final s in rawServices) {
        if (s is Map<String, dynamic>) {
          _services.add(s);
        }
      }
    }

    // Initialize per-service state
    final now = DateTime.now();
    final roundedTime = _roundToNext5(TimeOfDay.now());
    _selectedEmployees = List.filled(_services.length, null);
    _selectedDates = List.generate(_services.length, (_) => now);
    _selectedTimes = List.generate(_services.length, (_) => roundedTime);

    _availableTimes = List.generate(_services.length, (_) => []);
    _selectedTimeSlots = List.filled(_services.length, null);
    _isLoadingTimes = List.filled(_services.length, false);

    // Pre-select first available employee for each service
    for (var i = 0; i < _services.length; i++) {
      final serviceId = _parseInt(_services[i]['id']);
      final serviceEmployees = widget.serviceEmployeeMap[serviceId];
      final employees =
          (serviceEmployees != null && serviceEmployees.isNotEmpty)
              ? serviceEmployees
              : widget.employees;
      if (employees.isNotEmpty) {
        _selectedEmployees[i] = employees.first;
        _fetchAvailableTimes(i);
      }
    }
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
      var cleaned = v.replaceAll(RegExp(r'[^\d.\-]'), '');
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

  List<Map<String, dynamic>> _employeesForService(int index) {
    final serviceId = _parseInt(_services[index]['id']);
    final serviceEmployees = widget.serviceEmployeeMap[serviceId];
    if (serviceEmployees != null && serviceEmployees.isNotEmpty) {
      return serviceEmployees;
    }
    return widget.employees;
  }

  // ───────── actions ─────────
  Future<void> _fetchAvailableTimes(int index) async {
    final emp = _selectedEmployees[index];
    if (emp == null) return;
    final empId = emp['id'] is int
        ? emp['id'] as int
        : int.tryParse(emp['id']?.toString() ?? '') ?? 0;
    final serviceId = _parseInt(_services[index]['id']);
    if (empId <= 0 || serviceId <= 0) return;

    setState(() {
      _isLoadingTimes[index] = true;
      _availableTimes[index] = [];
      _selectedTimeSlots[index] = null;
    });
    try {
      final salonService = getIt<SalonEmployeeService>();
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDates[index]);
      final times = await salonService.getAvailableTimes(
        employeeId: empId,
        serviceId: serviceId,
        date: dateStr,
      );
      if (mounted) {
        setState(() {
          _availableTimes[index] = times;
          _isLoadingTimes[index] = false;
          if (times.isNotEmpty) {
            _selectedTimeSlots[index] = times.first['value']?.toString();
            _syncTimeFromSlot(index);
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingTimes[index] = false);
    }
  }

  void _syncTimeFromSlot(int index) {
    final slot = _selectedTimeSlots[index];
    if (slot == null) return;
    final parts = slot.split(':');
    if (parts.length >= 2) {
      _selectedTimes[index] = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 0,
        minute: int.tryParse(parts[1]) ?? 0,
      );
    }
  }

  Future<void> _pickDate(int index) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDates[index],
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
      setState(() => _selectedDates[index] = picked);
      _fetchAvailableTimes(index);
    }
  }

  Future<void> _pickTime(int index) async {
    if (_availableTimes[index].isNotEmpty) return; // use dropdown instead
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTimes[index],
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
            textDirection:
                _useArabicUi ? ui.TextDirection.rtl : ui.TextDirection.ltr,
            child: child!,
          ),
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedTimes[index] = picked);
    }
  }

  void _onConfirm() {
    // Validate that all services have an employee selected
    for (var i = 0; i < _services.length; i++) {
      if (_selectedEmployees[i] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tr(
              'يرجى اختيار الموظف لجميع الخدمات',
              'Please select an employee for all services',
            )),
            backgroundColor: Colors.red.shade600,
          ),
        );
        return;
      }
    }

    final List<Map<String, dynamic>> results = [];
    for (var i = 0; i < _services.length; i++) {
      final service = _services[i];
      final serviceId = _parseInt(service['id']);
      final serviceName = (service['name'] ?? '').toString();
      final minutes = _parseInt(service['minutes']);
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDates[i]);
      final timeStr =
          '${_selectedTimes[i].hour.toString().padLeft(2, '0')}:${_selectedTimes[i].minute.toString().padLeft(2, '0')}';

      results.add({
        'package_service_id': _packageId,
        'item_name': '$serviceName ($_packageName)',
        'service_id': serviceId,
        'minutes': minutes,
        'employee_name':
            _selectedEmployees[i]!['name']?.toString() ?? '',
        'employee_id': _parseInt(_selectedEmployees[i]!['id']),
        'date': dateStr,
        'time': timeStr,
        'session_numbers': 1,
        'quantity': 1,
        'price': _packagePrice,
        'unitPrice': _packagePrice,
        'modified_unit_price': null,
        'type': 'packageServices',
      });
    }

    Navigator.pop(context, results);
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
            Expanded(child: _body()),
            _footer(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────── HEADER ───────────────────────
  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
              child: Icon(LucideIcons.package2, size: 16, color: _brand),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _packageName,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    _infoBadge(
                      icon: LucideIcons.banknote,
                      label:
                          '${_packagePrice.toStringAsFixed(2)} ${_tr('ر.س', 'SAR')}',
                    ),
                    if (_minutesFormat.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _infoBadge(
                        icon: LucideIcons.clock,
                        label: _minutesFormat,
                      ),
                    ],
                    const SizedBox(width: 8),
                    _infoBadge(
                      icon: LucideIcons.layers,
                      label: '${_services.length} ${_tr('خدمات', 'services')}',
                    ),
                  ],
                ),
              ],
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

  Widget _infoBadge({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _brandLight,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _brand),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: _brand),
          ),
        ],
      ),
    );
  }

  // ─────────────────────── BODY ───────────────────────
  Widget _body() {
    if (_services.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.packageOpen, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              _tr('لا توجد خدمات في هذه الباقة', 'No services in this package'),
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: _services.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) => _serviceCard(index),
    );
  }

  Widget _serviceCard(int index) {
    final service = _services[index];
    final serviceName = (service['name'] ?? '').toString();
    final minutes = _parseInt(service['minutes']);
    final servicePrice = _parseDouble(service['price']);
    final employees = _employeesForService(index);
    final dateText = DateFormat('yyyy-MM-dd').format(_selectedDates[index]);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Service header
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _brandLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _brand),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      serviceName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (minutes > 0) ...[
                          Icon(LucideIcons.clock,
                              size: 13, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            '$minutes ${_tr('دقيقة', 'min')}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                          const SizedBox(width: 12),
                        ],
                        if (servicePrice > 0) ...[
                          Icon(LucideIcons.banknote,
                              size: 13, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            '${servicePrice.toStringAsFixed(2)} ${_tr('ر.س', 'SAR')}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Employee dropdown
          Text(
            _tr('الموظف', 'Employee'),
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF555555)),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<Map<String, dynamic>>(
                value: _selectedEmployees[index],
                isExpanded: true,
                hint: Text(
                  _tr('اختر الموظف', 'Select employee'),
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),
                icon: const Icon(LucideIcons.chevronDown, size: 18),
                items: employees.map((emp) {
                  return DropdownMenuItem<Map<String, dynamic>>(
                    value: emp,
                    child: Text(
                      emp['name']?.toString() ?? '',
                      style: const TextStyle(fontSize: 14),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedEmployees[index] = value);
                  _fetchAvailableTimes(index);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Date picker
          Text(
            _tr('التاريخ', 'Date'),
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF555555)),
          ),
          const SizedBox(height: 6),
          _pickerTile(
            icon: LucideIcons.calendar,
            label: dateText,
            onTap: () => _pickDate(index),
          ),
          const SizedBox(height: 12),

          // Time: available slots dropdown or manual picker
          Text(
            _tr('الوقت المتاح', 'Available Time'),
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF555555)),
          ),
          const SizedBox(height: 6),
          _buildTimeSelector(index),
        ],
      ),
    );
  }

  Widget _buildTimeSelector(int index) {
    if (_isLoadingTimes[index]) {
      return Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: const Center(
          child: SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _brand)),
        ),
      );
    }

    if (_availableTimes[index].isNotEmpty) {
      return Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedTimeSlots[index],
            isExpanded: true,
            icon: const Icon(LucideIcons.clock, size: 18, color: _brand),
            hint: Text(_tr('اختر الوقت', 'Select time'),
              style: TextStyle(color: Colors.grey[400], fontSize: 14)),
            items: _availableTimes[index].map((t) {
              final val = t['value']?.toString() ?? '';
              final lbl = t['label']?.toString() ?? val;
              return DropdownMenuItem<String>(value: val, child: Text(lbl, style: const TextStyle(fontSize: 14)));
            }).toList(),
            onChanged: (val) {
              setState(() {
                _selectedTimeSlots[index] = val;
                _syncTimeFromSlot(index);
              });
            },
          ),
        ),
      );
    }

    // Fallback: manual time picker
    final timeText =
        '${_selectedTimes[index].hour.toString().padLeft(2, '0')}:${_selectedTimes[index].minute.toString().padLeft(2, '0')}';
    return _pickerTile(
      icon: LucideIcons.clock,
      label: timeText,
      onTap: () => _pickTime(index),
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
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: _brand),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(LucideIcons.chevronDown, size: 14, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  // ─────────────────────── FOOTER ───────────────────────
  Widget _footer() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Total summary
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _tr('سعر الباقة', 'Package Price'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${_packagePrice.toStringAsFixed(2)} ${_tr('ر.س', 'SAR')}',
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
