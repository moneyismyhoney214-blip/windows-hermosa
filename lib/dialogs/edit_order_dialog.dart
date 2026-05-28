import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hermosa_pos/dialogs/product_customization_dialog.dart';
import 'package:hermosa_pos/dialogs/salon_service_picker_dialog.dart';
import 'package:hermosa_pos/dialogs/salon_service_selection_dialog.dart';
import 'package:hermosa_pos/models.dart';
import 'package:hermosa_pos/models/booking_invoice.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';
import 'package:hermosa_pos/services/api/base_client.dart';
import 'package:hermosa_pos/services/api/branch_service.dart';
import 'package:hermosa_pos/services/api/error_handler.dart';
import 'package:hermosa_pos/services/api/order_service.dart';
import 'package:hermosa_pos/services/api/product_service.dart';
import 'package:hermosa_pos/services/api/salon_employee_service.dart';
import 'package:hermosa_pos/services/display_app_service.dart';
import 'package:hermosa_pos/services/logger_service.dart';
import 'package:hermosa_pos/widgets/product_card.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../locator.dart';
import '../services/app_themes.dart';
import '../services/language_service.dart';
import '../utils/ui_feedback.dart';

part 'edit_order_dialog_parts/edit_order_dialog.helpers.dart';

/// Describes a single change in an order edit.
/// Types:
///   'add', 'cancel', 'partial_cancel', 'qty_change',
///   'replace_old', 'replace_new',
///   // Salon-only:
///   'employee_change'  — same service, different employee (تحويل)
class OrderChange {
  final String type;
  final String name;
  final int quantity;
  final int? oldQuantity;
  final int? cancelledQuantity;
  final Map<String, String>? localizedNames;
  final List<Extra> extras;
  // Salon-only: populated for `employee_change` so kitchen ticket prints "من <X> إلى <Y>".
  final String? oldEmployeeName;
  final String? newEmployeeName;

  const OrderChange({
    required this.type,
    required this.name,
    required this.quantity,
    this.oldQuantity,
    this.cancelledQuantity,
    this.localizedNames,
    this.extras = const [],
    this.oldEmployeeName,
    this.newEmployeeName,
  });
}

class EditOrderDialog extends StatefulWidget {
  final Booking booking;
  final Map<String, dynamic> bookingData;
  final double taxRate;
  final void Function(
    List<OrderChange> changes,
    String orderNumber, {
    bool isFullCancel,
    String? customerName,
    String? employeeName,
  })? onPrintChanges;

  const EditOrderDialog({
    super.key,
    required this.booking,
    required this.bookingData,
    this.taxRate = 0.0,
    this.onPrintChanges,
  });

  @override
  State<EditOrderDialog> createState() => _EditOrderDialogState();
}

class _EditOrderDialogState extends State<EditOrderDialog> {
  final OrderService _orderService = getIt<OrderService>();
  final List<_EditableOrderItem> _items = [];
  final List<_EditableOrderItem> _originalItems = [];
  bool _saving = false;

  /// Customer name for the salon edit ticket; prefers booking payload over model field.
  String? get _salonCustomerName {
    final data = _asMap(widget.bookingData['data']) ?? widget.bookingData;
    final raw = (data['customer_name'] ??
            data['client_name'] ??
            widget.booking.customerName ??
            '')
        .toString()
        .trim();
    return raw.isEmpty ? null : raw;
  }

  /// Employee names joined with " · "; falls back to original snapshot for full cancellations.
  String? get _salonEmployeeName {
    final names = <String>[];
    final seen = <String>{};
    void addFrom(_EditableOrderItem item) {
      final salon = item.salonData;
      if (salon == null) return;
      final name = (salon['employee_name'] ?? '').toString().trim();
      if (name.isEmpty || !seen.add(name)) return;
      names.add(name);
    }

    for (final item in _items) {
      addFrom(item);
    }
    if (names.isEmpty) {
      for (final item in _originalItems) {
        addFrom(item);
      }
    }
    if (names.isEmpty) return null;
    return names.join(' · ');
  }

  bool get _isSalonBooking {
    final data = _asMap(widget.bookingData['data']) ?? widget.bookingData;
    final bookingServices = data['booking_services'];
    if (bookingServices is List && bookingServices.isNotEmpty) return true;
    final hasMeals = data['booking_meals'] is List &&
        (data['booking_meals'] as List).isNotEmpty;
    if (hasMeals) return false;
    final type = (data['type'] ?? widget.booking.type)
        ?.toString()
        .trim()
        .toLowerCase();
    return type == 'services';
  }

  @override
  void initState() {
    super.initState();
    _seedItems();
  }

  void _seedItems() {
    final data = _asMap(widget.bookingData['data']) ?? widget.bookingData;
    final meals = _extractMeals(data);
    _items.clear();
    _originalItems.clear();
    final taxMul = _salonTaxMultiplier;
    for (final meal in meals) {
      final fresh = _EditableOrderItem.fromMap(meal);
      final original = _EditableOrderItem.fromMap(meal);
      // Attach salon payload so `?create_order` rebuild can re-emit `card[i]` with employee/date/time.
      final isSalonRow =
          meal['service_id'] != null || meal['service_name'] != null;
      if (isSalonRow) {
        final salon = _buildSalonPayloadFromBookingService(meal);
        fresh.salonData = salon;
        original.salonData = salon;
        // Backend stores salon prices pre-tax; gross up for display, save handler divides before POST.
        if (taxMul > 1.0) {
          fresh.unitPrice = fresh.unitPrice * taxMul;
          original.unitPrice = original.unitPrice * taxMul;
        }
      }
      _items.add(fresh);
      _originalItems.add(original);
    }
  }

  /// Tax multiplier for round-tripping pre-tax backend prices to with-tax UI; 1.0 when disabled.
  double get _salonTaxMultiplier {
    if (!_isSalonBooking) return 1.0;
    final branchService = getIt<BranchService>();
    final taxRate =
        branchService.cachedHasTax ? branchService.cachedTaxRate : 0.0;
    return 1.0 + taxRate;
  }

  Map<String, dynamic> _buildSalonPayloadFromBookingService(
    Map<String, dynamic> row,
  ) {
    final emp = row['employee'] is Map
        ? (row['employee'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    final unit = _parseNum(row['unit_price'] ??
        row['modified_unit_price'] ??
        row['price'] ??
        row['total_price'] ??
        row['total']);
    final qtyRaw = row['quantity'];
    final qty = (qtyRaw is num)
        ? qtyRaw.toInt()
        : int.tryParse(qtyRaw?.toString() ?? '') ?? 1;
    return <String, dynamic>{
      'service_id': row['service_id'],
      'item_name': row['service_name'] ?? row['meal_name'] ?? row['name'] ?? '',
      'price': unit * (qty == 0 ? 1 : qty),
      'unitPrice': unit,
      'modified_unit_price': row['modified_unit_price'],
      'quantity': qty == 0 ? 1 : qty,
      'employee_id': row['employee_id'] ?? emp['id'],
      'employee_name': emp['fullname'] ??
          row['employee_fullname'] ??
          row['employee_name'] ??
          '',
      'date': row['date']?.toString() ?? '',
      'time': row['time']?.toString() ?? '',
      'minutes': row['minutes'] ?? 0,
      'session_numbers': row['session_numbers'] ?? 0,
    };
  }

  double _parseNum(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    final cleaned =
        value.toString().replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  List<OrderChange> _detectChanges() {
    final changes = <OrderChange>[];
    final matchedOriginals = <int>{};
    final matchedNew = <int>{};

    // PERF: mealId index makes matching O(n) instead of O(n²).
    final originalByMealId = <Object, List<int>>{};
    for (var i = 0; i < _originalItems.length; i++) {
      originalByMealId
          .putIfAbsent(_originalItems[i].mealId, () => <int>[])
          .add(i);
    }

    for (var n = 0; n < _items.length; n++) {
      final newItem = _items[n];
      int? bestMatch;
      final candidates = originalByMealId[newItem.mealId];
      if (candidates != null) {
        for (final idx in candidates) {
          if (!matchedOriginals.contains(idx)) {
            bestMatch = idx;
            break;
          }
        }
      }

      if (bestMatch != null) {
        final oldItem = _originalItems[bestMatch];
        matchedOriginals.add(bestMatch);
        matchedNew.add(n);

        final oldQty = oldItem.quantity.round();
        final newQty = newItem.quantity.round();

        if (oldQty != newQty) {
          if (newQty < oldQty) {
            changes.add(OrderChange(
              type: 'partial_cancel',
              name: newItem.name,
              quantity: newQty,
              oldQuantity: oldQty,
              cancelledQuantity: oldQty - newQty,
              localizedNames: newItem.localizedNames,
              extras: newItem.extras,
            ));
          } else {
            changes.add(OrderChange(
              type: 'qty_change',
              name: newItem.name,
              quantity: newQty,
              oldQuantity: oldQty,
              localizedNames: newItem.localizedNames,
              extras: newItem.extras,
            ));
          }
        }
      }
    }

    final removed = <_EditableOrderItem>[];
    for (var i = 0; i < _originalItems.length; i++) {
      if (!matchedOriginals.contains(i)) removed.add(_originalItems[i]);
    }
    final added = <_EditableOrderItem>[];
    for (var n = 0; n < _items.length; n++) {
      if (!matchedNew.contains(n)) added.add(_items[n]);
    }

    final pairedRemoved = <int>{};
    final pairedAdded = <int>{};
    for (var r = 0; r < removed.length && r < added.length; r++) {
      pairedRemoved.add(r);
      pairedAdded.add(r);
      changes.add(OrderChange(
        type: 'replace_old',
        name: removed[r].name,
        quantity: removed[r].quantity.round(),
        localizedNames: removed[r].localizedNames,
        extras: removed[r].extras,
      ));
      changes.add(OrderChange(
        type: 'replace_new',
        name: added[r].name,
        quantity: added[r].quantity.round(),
        localizedNames: added[r].localizedNames,
        extras: added[r].extras,
      ));
    }

    for (var r = 0; r < removed.length; r++) {
      if (pairedRemoved.contains(r)) continue;
      changes.add(OrderChange(
        type: 'cancel',
        name: removed[r].name,
        quantity: removed[r].quantity.round(),
        localizedNames: removed[r].localizedNames,
        extras: removed[r].extras,
      ));
    }

    for (var a = 0; a < added.length; a++) {
      if (pairedAdded.contains(a)) continue;
      changes.add(OrderChange(
        type: 'add',
        name: added[a].name,
        quantity: added[a].quantity.round(),
        localizedNames: added[a].localizedNames,
        extras: added[a].extras,
      ));
    }

    return changes;
  }

  /// Salon-aware diff: adds/removes/qty plus `employee_change` (the "تحويل" case).
  List<OrderChange> _detectSalonChanges() {
    final changes = <OrderChange>[];
    final matchedOriginal = <int>{};
    final matchedNew = <int>{};

    String? empNameOf(_EditableOrderItem it) {
      final salon = it.salonData;
      if (salon == null) return null;
      final raw = salon['employee_name']?.toString().trim();
      if (raw != null && raw.isNotEmpty) return raw;
      return null;
    }

    String? empIdOf(_EditableOrderItem it) {
      final salon = it.salonData;
      if (salon == null) return null;
      final raw = salon['employee_id']?.toString().trim();
      return raw == null || raw.isEmpty ? null : raw;
    }

    // New rows have `mealId` starting with `new_` so they never collide with originals.
    final originalByMealId = <String, List<int>>{};
    for (var i = 0; i < _originalItems.length; i++) {
      originalByMealId
          .putIfAbsent(_originalItems[i].mealId, () => <int>[])
          .add(i);
    }

    for (var n = 0; n < _items.length; n++) {
      final newItem = _items[n];
      final candidates = originalByMealId[newItem.mealId];
      if (candidates == null) continue;
      int? matchIdx;
      for (final idx in candidates) {
        if (!matchedOriginal.contains(idx)) {
          matchIdx = idx;
          break;
        }
      }
      if (matchIdx == null) continue;
      matchedOriginal.add(matchIdx);
      matchedNew.add(n);

      final oldItem = _originalItems[matchIdx];
      final oldQty = oldItem.quantity.round();
      final newQty = newItem.quantity.round();

      final oldEmpId = empIdOf(oldItem);
      final newEmpId = empIdOf(newItem);
      if (oldEmpId != null &&
          newEmpId != null &&
          oldEmpId != newEmpId) {
        changes.add(OrderChange(
          type: 'employee_change',
          name: newItem.name,
          quantity: newQty == 0 ? 1 : newQty,
          localizedNames: newItem.localizedNames,
          oldEmployeeName: empNameOf(oldItem),
          newEmployeeName: empNameOf(newItem),
        ));
      }

      if (oldQty != newQty) {
        if (newQty < oldQty) {
          changes.add(OrderChange(
            type: 'partial_cancel',
            name: newItem.name,
            quantity: newQty,
            oldQuantity: oldQty,
            cancelledQuantity: oldQty - newQty,
            localizedNames: newItem.localizedNames,
          ));
        } else {
          changes.add(OrderChange(
            type: 'qty_change',
            name: newItem.name,
            quantity: newQty,
            oldQuantity: oldQty,
            localizedNames: newItem.localizedNames,
          ));
        }
      }
    }

    // Removed services routed via `processBookingRefund` so ticket reads as refund.
    for (var i = 0; i < _originalItems.length; i++) {
      if (matchedOriginal.contains(i)) continue;
      changes.add(OrderChange(
        type: 'cancel',
        name: _originalItems[i].name,
        quantity: _originalItems[i].quantity.round(),
        localizedNames: _originalItems[i].localizedNames,
      ));
    }

    for (var n = 0; n < _items.length; n++) {
      if (matchedNew.contains(n)) continue;
      changes.add(OrderChange(
        type: 'add',
        name: _items[n].name,
        quantity: _items[n].quantity.round(),
        localizedNames: _items[n].localizedNames,
      ));
    }

    return changes;
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  List<Map<String, dynamic>> _extractMeals(Map<String, dynamic> data) {
    List<Map<String, dynamic>> normalizeList(dynamic source) {
      if (source is! List) return const [];
      return source
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }

    const possibleKeys = [
      'meals',
      'booking_meals',
      'booking_products',
      'booking_items',
      'products',
      'services',
      'booking_services',
      'sales_meals',
      'items',
      'invoice_items',
      'order_items',
      'cart',
      'card',
    ];

    String? resolveLocalizedName(dynamic value) {
      if (value == null) return null;
      if (value is Map) {
        final langCode = translationService.currentLanguageCode
            .trim()
            .toLowerCase();
        final useAr =
            langCode.startsWith('ar') || langCode.startsWith('ur');
        final preferred = useAr ? 'ar' : 'en';
        final localized = value[preferred]?.toString().trim();
        if (localized != null && localized.isNotEmpty) return localized;
        for (final v in value.values) {
          final s = v?.toString().trim() ?? '';
          if (s.isNotEmpty) return s;
        }
        return null;
      }
      final s = value.toString().trim();
      if (s.startsWith('{') && s.contains('"ar"')) {
        try {
          final parsed = Map<String, dynamic>.from(
            (const JsonCodec()).decode(s) as Map,
          );
          return resolveLocalizedName(parsed);
        } catch (e) {
          Log.d('EditOrderDialog', 'localized-name JSON decode failed (non-fatal): $e');
        }
      }
      return s.isNotEmpty ? s : null;
    }

    for (final key in possibleKeys) {
      final meals = normalizeList(data[key]);
      if (meals.isNotEmpty) {
        return meals.map((row) {
          final result = Map<String, dynamic>.from(row);
          final mealMap = row['meal'] is Map
              ? (row['meal'] as Map).map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{};
          final serviceMap = row['service'] is Map
              ? (row['service'] as Map).map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{};
          final resolvedName = resolveLocalizedName(row['service_name']) ??
              resolveLocalizedName(row['meal_name']) ??
              resolveLocalizedName(mealMap['name']) ??
              resolveLocalizedName(serviceMap['name']) ??
              resolveLocalizedName(row['name']) ??
              resolveLocalizedName(row['item_name']);
          if (resolvedName != null) result['meal_name'] = resolvedName;
          result['quantity'] ??= 1;
          final resolvedPrice = row['unit_price'] ?? row['price'] ??
              mealMap['price'] ?? mealMap['unit_price'];
          if (resolvedPrice != null) result['unit_price'] = resolvedPrice;
          if (result['total'] == null && resolvedPrice != null) {
            result['total'] = resolvedPrice;
          }
          return result;
        }).toList();
      }
    }

    final nestedCandidates = [
      data['data'],
      data['booking'],
      data['invoice'],
      data['details'],
      data['result'],
    ];
    for (final candidate in nestedCandidates) {
      final nested = _asMap(candidate);
      if (nested == null || identical(nested, data)) continue;
      final extracted = _extractMeals(nested);
      if (extracted.isNotEmpty) return extracted;
    }

    return [];
  }

  String _formatQty(double qty) {
    final rounded = qty.round();
    if ((qty - rounded).abs() < 0.0001) return rounded.toString();
    return qty.toStringAsFixed(ApiConstants.digitsNumber);
  }

  Future<void> _showProductPicker() async {
    final product = await showDialog<Product>(
      context: context,
      builder: (context) => _ProductPickerDialog(taxRate: widget.taxRate),
    );
    if (product == null) return;
    await _addProductWithCustomization(product);
  }

  /// Salon add-service: pick service, fetch employees, run selection dialog, append to `_items`.
  Future<void> _addSalonService() async {
    final service =
        await SalonServicePickerDialog.show(context);
    if (service == null || !mounted) return;

    final serviceIdRaw = service['id'];
    final serviceId = serviceIdRaw is int
        ? serviceIdRaw
        : int.tryParse(serviceIdRaw?.toString() ?? '') ?? 0;
    if (serviceId <= 0) return;

    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ));

    List<Map<String, dynamic>> employees;
    try {
      employees = await getIt<SalonEmployeeService>()
          .getServiceEmployees(serviceId);
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
      employees = const [];
    } finally {
      if (mounted) Navigator.pop(context);
    }

    if (!mounted) return;
    if (employees.isEmpty) {
      UiFeedback.info(context, translationService.t('no_employees_for_service'));
      return;
    }

    // Translate `{value, label}` from endpoint to `{id, name}` for SalonServiceSelectionDialog.
    final mapped = employees
        .map((e) => <String, dynamic>{
              'id': e['value'] ?? e['id'],
              'name': (e['label'] ?? e['name'] ?? '').toString(),
              'is_active': e['is_active'] ?? true,
            })
        .toList();

    // Gross up catalog price for selection dialog only; the dialog's return value is already with-tax.
    final taxMul = _salonTaxMultiplier;
    final pickerService = (taxMul > 1.0 && service['price'] is num)
        ? <String, dynamic>{
            ...service,
            'price': (service['price'] as num).toDouble() * taxMul,
          }
        : service;

    final result = await SalonServiceSelectionDialog.show(
      context,
      serviceData: pickerService,
      employees: mapped,
    );
    if (result == null || !mounted) return;

    setState(() {
      _items.add(_EditableOrderItem.fromSalonResult(result));
    });
  }

  /// Salon edit-existing: persist immediately via `update-booking-data/{id}` to avoid clobbering on rebuild.
  Future<void> _editSalonItem(_EditableOrderItem item) async {
    final salon = item.salonData;
    if (salon == null) return;

    final serviceId = salon['service_id'] is int
        ? salon['service_id'] as int
        : int.tryParse(salon['service_id']?.toString() ?? '') ?? 0;
    if (serviceId <= 0) return;

    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    ));

    Map<String, dynamic>? serviceData;
    List<Map<String, dynamic>> employees;
    try {
      final client = BaseClient();
      final response = await client.get(
        '/seller/branches/${ApiConstants.branchId}/bookings/create?type=services&page=1&per_page=1&search=${Uri.encodeComponent(salon['item_name']?.toString() ?? '')}',
      );
      final data = response is Map ? response['data'] : response;
      if (data is Map && data['collection'] is Map) {
        final list = (data['collection'] as Map)['data'];
        if (list is List) {
          for (final raw in list.whereType<Map>()) {
            final m = raw.map((k, v) => MapEntry(k.toString(), v));
            if (m['id']?.toString() == serviceId.toString()) {
              serviceData = m;
              break;
            }
          }
        }
      }
      employees = await getIt<SalonEmployeeService>()
          .getServiceEmployees(serviceId);
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
      employees = const [];
    } finally {
      if (mounted) Navigator.pop(context);
    }

    if (!mounted) return;
    // Fall back to cached salon payload when catalog search by name misses.
    serviceData ??= <String, dynamic>{
      'id': serviceId,
      'name': salon['item_name'] ?? item.name,
      'price': salon['unitPrice'] ?? item.unitPrice,
      'minutes': salon['minutes'] ?? 0,
      'minutes_format': '',
    };
    if (employees.isEmpty) {
      UiFeedback.info(context, translationService.t('no_employees_for_service'));
      return;
    }

    final mapped = employees
        .map((e) => <String, dynamic>{
              'id': e['value'] ?? e['id'],
              'name': (e['label'] ?? e['name'] ?? '').toString(),
              'is_active': e['is_active'] ?? true,
            })
        .toList();

    final initialDate = DateTime.tryParse(salon['date']?.toString() ?? '');
    TimeOfDay? initialTime;
    final timeStr = salon['time']?.toString() ?? '';
    if (timeStr.contains(':')) {
      final parts = timeStr.split(':');
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1].split(' ').first);
      if (h != null && m != null) initialTime = TimeOfDay(hour: h, minute: m);
    }
    final initialEmpId = salon['employee_id'] is int
        ? salon['employee_id'] as int
        : int.tryParse(salon['employee_id']?.toString() ?? '');

    final result = await SalonServiceSelectionDialog.show(
      context,
      serviceData: serviceData,
      employees: mapped,
      initialEmployeeId: initialEmpId,
      initialDate: initialDate,
      initialTime: initialTime,
      initialQuantity: salon['quantity'] is int
          ? salon['quantity'] as int
          : int.tryParse(salon['quantity']?.toString() ?? '1') ?? 1,
      initialSessionNumbers: salon['session_numbers'] is int
          ? salon['session_numbers'] as int
          : int.tryParse(salon['session_numbers']?.toString() ?? '0') ?? 0,
      // `item.unitPrice` is grossed-up in `_seedItems`; salon['unitPrice'] would show pre-tax.
      initialPrice: item.unitPrice > 0
          ? item.unitPrice
          : _parseNum(salon['unitPrice'] ?? salon['price']) *
              _salonTaxMultiplier,
    );
    if (result == null || !mounted) return;

    // Persist via `update-booking-data/{bookingServiceId}` to preserve the booking_service_id.
    final bookingServiceId = int.tryParse(item.mealId);
    if (bookingServiceId != null && bookingServiceId > 0) {
      try {
        final client = BaseClient();
        await client.postMultipart(
          '/seller/update-booking-data/$bookingServiceId',
          {
            'date': result['date']?.toString() ?? '',
            'employee_id': result['employee_id']?.toString() ?? '',
            'time': result['time']?.toString() ?? '',
            'session_numbers':
                result['session_numbers']?.toString() ?? '0',
            'employee_name':
                result['employee_name']?.toString() ?? '',
          },
        );
        // Invalidate slot cache: old (employee, date) frees, new consumes — both keys are cached.
        try {
          getIt<SalonEmployeeService>().invalidateAvailableTimesCache();
        } catch (e) {
          Log.d('EditOrderDialog', 'invalidate salon slot cache after service update failed (non-fatal): $e');
        }
      } catch (e) {
        if (!mounted) return;
        UiFeedback.info(context, ErrorHandler.toUserMessage(
            e,
            fallback: translationService.t('service_update_failed'),
          ));
        return;
      }
    }

    setState(() {
      item.salonData = Map<String, dynamic>.from(result);
      item.unitPrice = _parseNum(result['unitPrice']);
      item.quantity = (result['quantity'] is num
              ? (result['quantity'] as num).toInt()
              : int.tryParse(result['quantity']?.toString() ?? '1') ?? 1)
          .toDouble();
      item.name = result['item_name']?.toString() ?? item.name;
    });
  }

  Future<void> _addProductWithCustomization(Product product) async {
    if (!mounted) return;
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    ));

    try {
      final productService = getIt<ProductService>();
      final addons = await productService.getMealAddons(product.id);
      if (!mounted) return;
      Navigator.pop(context);

      final activeProduct = Product(
        id: product.id,
        name: product.name,
        price: product.price,
        category: product.category,
        isActive: product.isActive,
        image: product.image,
        extras: addons.isNotEmpty ? addons : product.extras,
      );

      if (activeProduct.extras.isEmpty) {
        _mergeOrAddItem(_EditableOrderItem.fromProduct(activeProduct));
        return;
      }

      unawaited(showDialog(
        context: context,
        builder: (context) => ProductCustomizationDialog(
          product: activeProduct,
          taxRate: widget.taxRate,
          onConfirm: (p, extras, qty, notes) {
            _mergeOrAddItem(_EditableOrderItem.fromProduct(
              p,
              quantity: qty,
              extras: extras,
              notes: notes,
            ));
          },
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _mergeOrAddItem(_EditableOrderItem.fromProduct(product));
    }
  }

  void _mergeOrAddItem(_EditableOrderItem item) {
    for (final existing in _items) {
      if (existing.isSameLine(item)) {
        setState(() {
          existing.quantity += item.quantity;
        });
        return;
      }
    }
    setState(() => _items.add(item));
  }

  Future<void> _saveChanges() async {
    if (_saving) return;

    if (_items.isEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(translationService.t('cancel_order_title')),
          content: Text(translationService.t('cancel_entire_order_q')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(translationService.t('no')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
              ),
              child: Text(translationService.t('yes_cancel_order')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      setState(() => _saving = true);
      try {
        await _orderService.updateBookingStatus(
          orderId: widget.booking.id.toString(),
          status: 8,
        );
        getIt<DisplayAppService>().notifyOrderCancelled(
            orderId: widget.booking.id.toString());
        if (widget.onPrintChanges != null) {
          final cancelChanges = _originalItems.map((item) => OrderChange(
            type: 'cancel',
            name: item.name,
            quantity: item.quantity.round(),
            localizedNames: item.localizedNames,
          )).toList();
          // Salon kitchen ticket header uses daily_order_number ONLY (no booking_number/id fallback).
          final mapped =
              _asMap(widget.bookingData['data']) ?? widget.bookingData;
          final dailyOnly = mapped['daily_order_number']?.toString() ?? '';
          final orderNum = _isSalonBooking
              ? dailyOnly
              : (dailyOnly.isNotEmpty
                  ? dailyOnly
                  : (widget.booking.orderNumber ??
                      widget.booking.id.toString()));
          if (orderNum.isNotEmpty) {
            widget.onPrintChanges!(
              cancelChanges,
              orderNum,
              isFullCancel: true,
              customerName: _isSalonBooking ? _salonCustomerName : null,
              employeeName: _isSalonBooking ? _salonEmployeeName : null,
            );
          }
        }
        if (!mounted) return;
        Navigator.pop(context, true);
      } catch (e) {
        if (!mounted) return;
        UiFeedback.info(context, translationService.t('cancel_order_failed'));
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    setState(() => _saving = true);

    try {
      final data = _asMap(widget.bookingData['data']) ?? widget.bookingData;
      final orderType = data['type']?.toString().trim().isNotEmpty == true
          ? data['type']?.toString()
          : widget.booking.type;
      final notes = data['notes']?.toString() ?? widget.booking.notes ?? '';
      final updatedAt = data['updated_at']?.toString() ??
          data['updatedAt']?.toString() ??
          widget.booking.updatedAt ??
          widget.booking.raw['updated_at']?.toString();

      // Salon save: inline edits already persisted; additions → `?create_order` rebuild (destructive); removals-only → refund endpoint to preserve ids.
      if (_isSalonBooking) {
        // Snapshot diff before mutating backend (refund/create_order resets booking_service ids).
        final salonChanges = _detectSalonChanges();
        final salonOrderNum = data['daily_order_number']?.toString() ?? '';
        final isFullSalonCancel = _items.isEmpty;

        final survivingIds = _items.map((e) => e.mealId).toSet();
        final removedIds = <String>[];
        for (final original in _originalItems) {
          if (!survivingIds.contains(original.mealId)) {
            removedIds.add(original.mealId);
          }
        }
        final hasAdditions = _items.any((it) =>
            it.salonData != null && it.mealId.startsWith('new_'));

        if (hasAdditions) {
          // Rebuild via ?create_order; backend wipes existing booking_services and recreates from payload.
          final fields = <String, String>{'_method': 'PATCH'};
          // Display price is WITH-TAX; divide by multiplier before POST or service double-taxes.
          final taxMul = _salonTaxMultiplier;
          for (var i = 0; i < _items.length; i++) {
            final it = _items[i];
            final salon = it.salonData;
            if (salon == null) continue;
            final qty = it.quantity.round().clamp(1, 9999);
            final unitDisplay = it.unitPrice;
            final unit = taxMul > 1.0 ? unitDisplay / taxMul : unitDisplay;
            fields['card[$i][service_id]'] =
                salon['service_id']?.toString() ?? '';
            fields['card[$i][item_name]'] = it.name;
            fields['card[$i][price]'] = (unit * qty).toString();
            fields['card[$i][unitPrice]'] = unit.toString();
            if (salon['modified_unit_price'] != null) {
              // `modified_unit_price` is pre-tax on backend like `unit_price` — convert back.
              final modDisplay = _parseNum(salon['modified_unit_price']);
              final modPreTax =
                  taxMul > 1.0 ? modDisplay / taxMul : modDisplay;
              fields['card[$i][modified_unit_price]'] = modPreTax.toString();
            }
            fields['card[$i][quantity]'] = qty.toString();
            fields['card[$i][employee_id]'] =
                salon['employee_id']?.toString() ?? '';
            fields['card[$i][employee_name]'] =
                salon['employee_name']?.toString() ?? '';
            fields['card[$i][date]'] = salon['date']?.toString() ?? '';
            fields['card[$i][time]'] = salon['time']?.toString() ?? '';
            fields['card[$i][minutes]'] =
                salon['minutes']?.toString() ?? '0';
            fields['card[$i][session_numbers]'] =
                salon['session_numbers']?.toString() ?? '0';
          }
          try {
            final client = BaseClient();
            await client.postMultipart(
              '/seller/branches/${ApiConstants.branchId}/bookings/${widget.booking.id}?create_order',
              fields,
            );
            // Invalidate slot cache; PATCH may have shifted dates/times/employees.
            try {
              getIt<SalonEmployeeService>().invalidateAvailableTimesCache();
            } catch (e) {
              Log.d('EditOrderDialog', 'invalidate salon slot cache after order update failed (non-fatal): $e');
            }
          } catch (e) {
            if (!mounted) return;
            UiFeedback.info(context, ErrorHandler.toUserMessage(
                e,
                fallback: translationService.t('order_update_failed'),
              ));
            return;
          }
          if (salonChanges.isNotEmpty &&
              widget.onPrintChanges != null &&
              salonOrderNum.isNotEmpty) {
            widget.onPrintChanges!(
              salonChanges,
              salonOrderNum,
              isFullCancel: isFullSalonCancel,
              customerName: _salonCustomerName,
              employeeName: _salonEmployeeName,
            );
          }
          if (!mounted) return;
          Navigator.pop(context, true);
          return;
        }

        if (removedIds.isEmpty) {
          // Edits already persisted inline; still print diff for "تحويل"/qty-change ticket.
          if (salonChanges.isNotEmpty &&
              widget.onPrintChanges != null &&
              salonOrderNum.isNotEmpty) {
            widget.onPrintChanges!(
              salonChanges,
              salonOrderNum,
              isFullCancel: isFullSalonCancel,
              customerName: _salonCustomerName,
              employeeName: _salonEmployeeName,
            );
          }
          if (!mounted) return;
          Navigator.pop(context, true);
          return;
        }

        final parsedIds = removedIds
            .map((id) => int.tryParse(id.trim()))
            .whereType<int>()
            .toList();
        await _orderService.processBookingRefund(
          orderId: widget.booking.id.toString(),
          payload: {'refund': parsedIds},
        );

        if (salonChanges.isNotEmpty &&
            widget.onPrintChanges != null &&
            salonOrderNum.isNotEmpty) {
          widget.onPrintChanges!(
            salonChanges,
            salonOrderNum,
            isFullCancel: isFullSalonCancel,
            customerName: _salonCustomerName,
            employeeName: _salonEmployeeName,
          );
        }

        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      final payloadItems = _items.map((e) => e.toPayload()).toList();

      // Merge type_extra ensuring table_name is present for restaurant_internal.
      Map<String, dynamic>? typeExtra;
      final rawTypeExtra = _asMap(data['type_extra']) ?? widget.booking.typeExtra;
      if (rawTypeExtra != null && rawTypeExtra.isNotEmpty) {
        typeExtra = Map<String, dynamic>.from(rawTypeExtra);
      }
      final normalizedType = (orderType ?? '').trim().toLowerCase();
      if (normalizedType == 'restaurant_internal') {
        typeExtra ??= {};
        typeExtra.putIfAbsent(
          'table_name',
          () => widget.booking.tableName ?? typeExtra!['table_name'] ?? '',
        );
      }

      await _orderService.updateBookingItems(
        orderId: widget.booking.id.toString(),
        orderType: orderType,
        notes: notes,
        items: payloadItems,
        updatedAt: updatedAt,
        typeExtra: typeExtra,
      );
      // Stream the new authoritative items to display/KDS so the kitchen sees
      // adds/removes/quantity edits without waiting on the polling fallback.
      getIt<DisplayAppService>().notifyOrderItemsChanged(
        orderId: widget.booking.id.toString(),
        items: payloadItems,
        orderNumber: widget.booking.orderNumber,
        note: notes,
      );

      final changes = _detectChanges();
      debugPrint('🔄 Order edit: ${changes.length} changes detected (original=${_originalItems.length} items, new=${_items.length} items)');
      for (final c in changes) {
        debugPrint('🔄 Change: type=${c.type} name=${c.name} qty=${c.quantity} oldQty=${c.oldQuantity} cancelledQty=${c.cancelledQuantity}');
      }
      debugPrint('🔄 onPrintChanges callback: ${widget.onPrintChanges != null ? "SET" : "NULL"}');
      if (changes.isNotEmpty && widget.onPrintChanges != null) {
        final orderNum = data['daily_order_number']?.toString() ??
            data['order_number']?.toString() ??
            data['booking_number']?.toString() ??
            widget.booking.orderNumber ??
            widget.booking.id.toString();
        widget.onPrintChanges!(changes, orderNum, isFullCancel: false);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final message = ErrorHandler.toUserMessage(
        e,
        fallback: translationService.t('order_update_failed'),
      );
      UiFeedback.info(context, message);
    } finally {
      if (mounted) setState(() => _saving = false);
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

    final data = _asMap(widget.bookingData['data']) ?? widget.bookingData;
    final orderNumber = (data['order_number'] ??
                data['booking_number'] ??
                data['daily_order_number'])
            ?.toString() ??
        widget.booking.orderNumber ??
        widget.booking.id.toString();

    return PopScope(
      // Block back/swipe/outside-tap when unsaved; uses same diff engine as Save button.
      canPop: !_saving && _detectChanges().isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_saving) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ??
                Theme.of(ctx).colorScheme.surface,
            title: Text(translationService.t('discard_changes_q')),
            content: Text(translationService.t('unsaved_changes_exit')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(translationService.t('keep_editing')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(translationService.t('discard_label')),
              ),
            ],
          ),
        );
        if (confirm == true && context.mounted) {
          Navigator.of(context).pop(false);
        }
      },
      child: Dialog(
      insetPadding: insetPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
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
                          translationService.t(
                            'edit_order_data',
                            args: {'number': orderNumber},
                          ),
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
                          translationService.t('edit_items_then_save'),
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
                    onPressed:
                        _saving ? null : () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            translationService.t('no_items_in_order'),
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _isSalonBooking
                                ? _addSalonService
                                : _showProductPicker,
                            icon: const Icon(LucideIcons.plus, size: 16),
                            label: Text(_isSalonBooking
                                ? translationService.t('add_service_btn')
                                : translationService.t('add_item_btn')),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: _isSalonBooking
                                  ? _addSalonService
                                  : _showProductPicker,
                              icon: const Icon(LucideIcons.plus, size: 16),
                              label: Text(_isSalonBooking
                                  ? translationService.t('add_service_btn')
                                  : translationService.t('add_item_btn')),
                            ),
                          );
                        }
                        final item = _items[index - 1];
                        return _buildEditableItemCard(item);
                      },
                    ),
            ),
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
                      onPressed:
                          _saving ? null : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(translationService.t('cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _saveChanges,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.save, size: 16),
                      label: Text(
                        _saving
                            ? translationService.t('saving_dots')
                            : translationService.t('save_changes_btn'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF58220),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildEditableItemCard(_EditableOrderItem item) {
    final extras = item.extras;
    final isSalonRow = item.salonData != null;
    final salon = item.salonData;
    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isSalonRow && salon != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        [
                          if ((salon['employee_name']?.toString() ?? '')
                              .isNotEmpty)
                            salon['employee_name'],
                          if ((salon['date']?.toString() ?? '').isNotEmpty)
                            salon['date'],
                          if ((salon['time']?.toString() ?? '').isNotEmpty)
                            salon['time'],
                        ].join(' • '),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isSalonRow)
                IconButton(
                  onPressed: () => _editSalonItem(item),
                  icon: const Icon(LucideIcons.pencil, size: 16),
                  color: const Color(0xFFF58220),
                  tooltip: translationService.t('edit_service'),
                ),
              IconButton(
                onPressed: () => setState(() => _items.remove(item)),
                icon: const Icon(LucideIcons.trash2, size: 16),
                color: const Color(0xFFEF4444),
                tooltip: translationService.t('remove_word'),
              ),
            ],
          ),
          if (extras.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: () {
                final grouped = <String, MapEntry<Extra, int>>{};
                for (final e in extras) {
                  if (grouped.containsKey(e.id)) {
                    grouped[e.id] = MapEntry(e, grouped[e.id]!.value + 1);
                  } else {
                    grouped[e.id] = MapEntry(e, 1);
                  }
                }
                return grouped.values.map((entry) {
                  final extra = entry.key;
                  final qty = entry.value;
                  final label = qty > 1 ? '+ ${extra.name} x$qty' : '+ ${extra.name}';
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFD97706),
                      ),
                    ),
                  );
                }).toList();
              }(),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _QtyButton(
                    icon: LucideIcons.minus,
                    onPressed: () {
                      setState(() {
                        item.quantity = (item.quantity - 1).clamp(1, 9999);
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatQty(item.quantity),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 8),
                  _QtyButton(
                    icon: LucideIcons.plus,
                    onPressed: () {
                      setState(() {
                        item.quantity = (item.quantity + 1).clamp(1, 9999);
                      });
                    },
                  ),
                ],
              ),
              const Spacer(),
              Text(
                '${item.totalPrice.toStringAsFixed(ApiConstants.digitsNumber)} ${ApiConstants.currency}',
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
    if (isSalonRow) {
      // Tap anywhere on salon row to open the editor (easier touch target).
      return InkWell(
        onTap: () => _editSalonItem(item),
        borderRadius: BorderRadius.circular(12),
        child: card,
      );
    }
    return card;
  }
}
