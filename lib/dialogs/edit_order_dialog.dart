import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:hermosa_pos/models.dart';
import 'package:hermosa_pos/models/booking_invoice.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';
import 'package:hermosa_pos/services/api/base_client.dart';
import 'package:hermosa_pos/services/api/branch_service.dart';
import 'package:hermosa_pos/services/api/error_handler.dart';
import 'package:hermosa_pos/services/api/order_service.dart';
import 'package:hermosa_pos/services/api/product_service.dart';
import 'package:hermosa_pos/services/api/salon_employee_service.dart';
import 'package:hermosa_pos/dialogs/product_customization_dialog.dart';
import 'package:hermosa_pos/dialogs/salon_service_picker_dialog.dart';
import 'package:hermosa_pos/dialogs/salon_service_selection_dialog.dart';
import 'package:hermosa_pos/widgets/product_card.dart';
import '../locator.dart';
import '../services/language_service.dart';
import '../services/app_themes.dart';

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
  // Salon-only: populated for `employee_change` so the kitchen ticket can
  // print "من <X> إلى <Y>". Null for restaurant rows.
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

  bool get _useArabicUi {
    final code = translationService.currentLanguageCode.trim().toLowerCase();
    return code.startsWith('ar') || code.startsWith('ur');
  }

  String _tr(String ar, String en) => _useArabicUi ? ar : en;

  /// Salon bookings carry `booking_services` while restaurants carry
  /// `booking_meals`. The product picker pulls the branch's restaurant
  /// menu (categories like صوصات / تكة دجاج), which is meaningless for a
  /// salon and lets users build payloads the salon backend can't accept.
  /// Hide the "+ Add Item" button when the booking is salon — the dialog
  /// then only supports removing services, which the save-handler routes
  /// through `processBookingRefund`.
  /// Customer name for the salon edit ticket. Pulls from the booking
  /// payload first (carries the freshest client name when a clerk just
  /// edited it on the booking screen) and falls back to the model field.
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

  /// Employee name(s) for the salon edit ticket. A salon booking can hold
  /// services across multiple employees — we join distinct names with " · "
  /// so the staff sees every person whose schedule the change touches.
  /// Falls back to the original snapshot when the live `_items` list is
  /// empty (e.g. a full cancellation).
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
      // Attach the raw salon payload so a rebuild via `?create_order` can
      // re-emit `card[i]` rows that retain the existing employee/date/time.
      // Restaurant rows pass through with `salonData == null`.
      final isSalonRow =
          meal['service_id'] != null || meal['service_name'] != null;
      if (isSalonRow) {
        final salon = _buildSalonPayloadFromBookingService(meal);
        fresh.salonData = salon;
        original.salonData = salon;
        // Backend stores salon prices pre-tax (e.g. 260.87 for a 300 SAR
        // service at 15% VAT). The cashier expects to see and edit the
        // tax-included price, so gross up for display. The save handler
        // divides by the same multiplier before posting back to
        // `?create_order`, so the round-trip stays correct.
        if (taxMul > 1.0) {
          fresh.unitPrice = fresh.unitPrice * taxMul;
          original.unitPrice = original.unitPrice * taxMul;
        }
      }
      _items.add(fresh);
      _originalItems.add(original);
    }
  }

  /// Tax multiplier used by salon edit/add to round-trip between the
  /// pre-tax prices the backend stores and the with-tax prices the cashier
  /// sees in the edit dialog. Returns 1.0 when the branch has tax disabled.
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

    // PERF: build a mealId → [original indices] index so matching is O(n)
    // instead of the previous O(n²) nested scan. With 50+ items this cuts
    // the ~2500-comparison hot path down to one linear pass on save.
    final originalByMealId = <Object, List<int>>{};
    for (var i = 0; i < _originalItems.length; i++) {
      originalByMealId
          .putIfAbsent(_originalItems[i].mealId, () => <int>[])
          .add(i);
    }

    // Step 1: Match items by mealId — detect quantity changes
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
            // Partial cancel — quantity decreased
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
            // Quantity increased
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

    // Step 2: Collect unmatched (removed & added)
    final removed = <_EditableOrderItem>[];
    for (var i = 0; i < _originalItems.length; i++) {
      if (!matchedOriginals.contains(i)) removed.add(_originalItems[i]);
    }
    final added = <_EditableOrderItem>[];
    for (var n = 0; n < _items.length; n++) {
      if (!matchedNew.contains(n)) added.add(_items[n]);
    }

    // Step 3: Pair removed+added as replacements
    final pairedRemoved = <int>{};
    final pairedAdded = <int>{};
    for (var r = 0; r < removed.length && r < added.length; r++) {
      pairedRemoved.add(r);
      pairedAdded.add(r);
      // Old item cancelled
      changes.add(OrderChange(
        type: 'replace_old',
        name: removed[r].name,
        quantity: removed[r].quantity.round(),
        localizedNames: removed[r].localizedNames,
        extras: removed[r].extras,
      ));
      // New item replaces it
      changes.add(OrderChange(
        type: 'replace_new',
        name: added[r].name,
        quantity: added[r].quantity.round(),
        localizedNames: added[r].localizedNames,
        extras: added[r].extras,
      ));
    }

    // Step 4: Remaining removed = fully cancelled
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

    // Step 5: Remaining added = new additions
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

  /// Salon-aware diff. Mirrors `_detectChanges` for adds / removes / qty
  /// changes, plus a new `employee_change` row when the service kept its
  /// id but had its assigned employee swapped (the "تحويل" case the
  /// cashier asked for). The kitchen-ticket printer renders these as
  /// "من <X> إلى <Y>".
  ///
  /// Inline employee edits committed via `update-booking-data/{id}` only
  /// mutate `_items[i].salonData`; `_originalItems[i].salonData` keeps the
  /// pre-edit snapshot, so the comparison here picks up the swap even
  /// though the network call already happened.
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

    // Index originals by mealId (booking_service_id). New rows have
    // `mealId` starting with `new_` so they never collide.
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

    // Removed (refunded) services — full cancellations from the dialog's
    // perspective. The salon save flow routes these through
    // `processBookingRefund`, so the printed ticket reads as a refund.
    for (var i = 0; i < _originalItems.length; i++) {
      if (matchedOriginal.contains(i)) continue;
      changes.add(OrderChange(
        type: 'cancel',
        name: _originalItems[i].name,
        quantity: _originalItems[i].quantity.round(),
        localizedNames: _originalItems[i].localizedNames,
      ));
    }

    // Newly added services.
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

    String? _resolveLocalizedName(dynamic value) {
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
      var s = value.toString().trim();
      // Handle JSON-encoded name strings like '{"ar":"...","en":"..."}'
      if (s.startsWith('{') && s.contains('"ar"')) {
        try {
          final parsed = Map<String, dynamic>.from(
            (const JsonCodec()).decode(s) as Map,
          );
          return _resolveLocalizedName(parsed);
        } catch (_) {}
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
          final resolvedName = _resolveLocalizedName(row['service_name']) ??
              _resolveLocalizedName(row['meal_name']) ??
              _resolveLocalizedName(mealMap['name']) ??
              _resolveLocalizedName(serviceMap['name']) ??
              _resolveLocalizedName(row['name']) ??
              _resolveLocalizedName(row['item_name']);
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

  /// Salon add-service flow: pick a service from the catalog, fetch the
  /// employees that can perform it, then run the existing employee/date/time
  /// dialog. The accepted result is appended to `_items` carrying its full
  /// salon payload so the save handler can emit it back as a `card[i]` row.
  Future<void> _addSalonService() async {
    final service =
        await SalonServicePickerDialog.show(context);
    if (service == null || !mounted) return;

    final serviceIdRaw = service['id'];
    final serviceId = serviceIdRaw is int
        ? serviceIdRaw
        : int.tryParse(serviceIdRaw?.toString() ?? '') ?? 0;
    if (serviceId <= 0) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    List<Map<String, dynamic>> employees;
    try {
      employees = await getIt<SalonEmployeeService>()
          .getServiceEmployees(serviceId);
    } catch (_) {
      employees = const [];
    } finally {
      if (mounted) Navigator.pop(context);
    }

    if (!mounted) return;
    if (employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr(
          'لا يوجد موظفون متاحون لهذه الخدمة',
          'No employees available for this service',
        )),
      ));
      return;
    }

    // SalonServiceSelectionDialog expects employees as `{id, name}`; the
    // service-employees endpoint returns `{value, label}` — translate.
    final mapped = employees
        .map((e) => <String, dynamic>{
              'id': e['value'] ?? e['id'],
              'name': (e['label'] ?? e['name'] ?? '').toString(),
              'is_active': e['is_active'] ?? true,
            })
        .toList();

    // The catalog price stored on `service['price']` is pre-tax. Gross it
    // up BEFORE seeding the selection dialog so the cashier sees the
    // with-tax amount in the price input — consistent with how existing
    // rows are rendered. We do NOT gross up the dialog's *return* value
    // because the user already typed/confirmed a with-tax number in that
    // input; doubling the multiplication produced 350 → 402.50 on a
    // freshly added مكياج خطوبة (the bug from the screenshot).
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

  /// Salon edit-existing flow: tap on a service row to change its employee /
  /// date / time. Persists immediately via `update-booking-data/{id}` so the
  /// surgical edit doesn't get clobbered by a later `?create_order` rebuild.
  Future<void> _editSalonItem(_EditableOrderItem item) async {
    final salon = item.salonData;
    if (salon == null) return;

    final serviceId = salon['service_id'] is int
        ? salon['service_id'] as int
        : int.tryParse(salon['service_id']?.toString() ?? '') ?? 0;
    if (serviceId <= 0) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

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
    } catch (_) {
      employees = const [];
    } finally {
      if (mounted) Navigator.pop(context);
    }

    if (!mounted) return;
    // Fall back to the cached salon payload when the catalog lookup misses
    // (search by name can be flaky across paginated branches).
    serviceData ??= <String, dynamic>{
      'id': serviceId,
      'name': salon['item_name'] ?? item.name,
      'price': salon['unitPrice'] ?? item.unitPrice,
      'minutes': salon['minutes'] ?? 0,
      'minutes_format': '',
    };
    if (employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_tr(
          'لا يوجد موظفون متاحون لهذه الخدمة',
          'No employees available for this service',
        )),
      ));
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
      // `item.unitPrice` is already the with-tax display price (grossed up
      // in `_seedItems`). Falling back to `salon['unitPrice']` would show
      // the raw pre-tax number (260 instead of 300) — exactly the bug the
      // user reported.
      initialPrice: item.unitPrice > 0
          ? item.unitPrice
          : _parseNum(salon['unitPrice'] ?? salon['price']) *
              _salonTaxMultiplier,
    );
    if (result == null || !mounted) return;

    // Persist surgically. `update-booking-data/{bookingServiceId}` updates
    // employee/date/time in place — preserves the booking_service_id, so a
    // subsequent refund / receipt referencing it stays correct.
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
        // Editing employee / date / time mutates the slot graph in two
        // places at once: the old (employee, date) tuple frees the slot,
        // the new (employee, date) tuple consumes one. Both keys are
        // cached for 2 minutes, so without a clear here the next picker
        // open will show the old time as still booked AND the new time
        // as still free — the very symptom the user reported.
        try {
          getIt<SalonEmployeeService>().invalidateAvailableTimesCache();
        } catch (_) {}
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ErrorHandler.toUserMessage(
            e,
            fallback: _tr('فشل تعديل الخدمة', 'Failed to update service'),
          )),
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

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

      showDialog(
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
      );
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

    // If all items removed, cancel the order instead
    if (_items.isEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_tr('إلغاء الطلب', 'Cancel Order')),
          content: Text(_tr(
            'لا يوجد عناصر في الطلب. هل تريد إلغاء الطلب بالكامل؟',
            'No items in order. Cancel the entire order?',
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_tr('لا', 'No')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
              ),
              child: Text(_tr('نعم، إلغاء الطلب', 'Yes, Cancel Order')),
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
        // Print cancellation ticket for all original items
        if (widget.onPrintChanges != null) {
          final cancelChanges = _originalItems.map((item) => OrderChange(
            type: 'cancel',
            name: item.name,
            quantity: item.quantity.round(),
            localizedNames: item.localizedNames,
          )).toList();
          // Salon kitchen ticket header is the daily_order_number ONLY —
          // booking_number / id fallbacks are the restaurant convention
          // and don't apply to the salon edit ticket.
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_tr('فشل إلغاء الطلب', 'Failed to cancel order'))),
        );
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

      // Salon save flow:
      //   - Edits to existing services (employee/date/time) were already
      //     committed inline through `update-booking-data/{id}` in
      //     `_editSalonItem`, so no extra work is needed here for those.
      //   - If new services were added, we have to rebuild the booking via
      //     POST `?create_order` with a full `card[]` (the endpoint replaces
      //     all booking_services — confirmed against the salon backend).
      //     This is destructive of booking_service_ids, so we only do it
      //     when there is at least one new row.
      //   - When the only change is removals, we route through the refund
      //     endpoint instead — that preserves audit history (refund_id) and
      //     keeps the surviving rows' ids intact.
      if (_isSalonBooking) {
        // Snapshot the diff BEFORE we mutate the backend — the refund /
        // create_order calls below reset booking_service ids and would
        // make a post-save diff unreliable.
        final salonChanges = _detectSalonChanges();
        // Salon kitchen ticket header uses ONLY daily_order_number per the
        // user's spec — booking_number / id fallbacks are intentionally
        // dropped here so the printout is consistent across edits.
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
          // Rebuild via ?create_order. Send all surviving + new rows as
          // card[i]. The backend wipes existing booking_services and
          // recreates fresh rows from the payload.
          final fields = <String, String>{'_method': 'PATCH'};
          // `_items[i].unitPrice` is the WITH-TAX display price the cashier
          // sees. Backend stores prices pre-tax, so divide by the tax
          // multiplier before posting to `?create_order` — otherwise the
          // service is double-taxed (300 displayed → 300 sent → 300 × 1.15
          // shown back as 345 next time the dialog opens).
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
              // `modified_unit_price` follows the same pre-tax convention
              // as `unit_price` on the backend — convert back from display.
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
            // Salon items in this PATCH-like POST may have shifted dates,
            // times, or employees. Drop the slot cache so the next booking
            // picker re-queries the backend instead of re-offering slots
            // that are now stale.
            try {
              getIt<SalonEmployeeService>().invalidateAvailableTimesCache();
            } catch (_) {}
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(ErrorHandler.toUserMessage(
                e,
                fallback: _tr('فشل تعديل الطلب', 'Unable to update order'),
              )),
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
          // Edits were already persisted inline (e.g. employee swap via
          // update-booking-data) — print the diff so the cashier still
          // gets the "تحويل" / qty-change ticket even when no items moved.
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

      // Build type_extra: merge data['type_extra'] with booking.typeExtra,
      // ensuring table_name is present for restaurant_internal orders.
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

      // Detect changes and trigger print
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
        fallback: _tr('تعذر تحديث الطلب', 'Unable to update order'),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
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
      // Block accidental swipe-back / system-back / outside-tap when the
      // user has unsaved changes — without this, a misclick on the
      // overlay or a hardware back-press silently throws away their
      // edits with no chance to recover. We compute "has changes" via
      // the same diff engine the Save button uses, so a no-op edit
      // (open/close without touching anything) still pops cleanly.
      canPop: !_saving && _detectChanges().isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_saving) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(ctx).dialogTheme.backgroundColor ??
                Theme.of(ctx).colorScheme.surface,
            title: Text(_tr('تجاهل التعديلات؟', 'Discard changes?')),
            content: Text(_tr(
              'لديك تعديلات غير محفوظة. هل تريد الخروج بدون حفظ؟',
              'You have unsaved changes. Exit without saving?',
            )),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(_tr('استمرار التعديل', 'Keep editing')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(_tr('تجاهل', 'Discard')),
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
                          _tr('عدّل الأصناف ثم احفظ التغييرات',
                              'Edit items then save changes'),
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
                                ? _tr('إضافة خدمة', 'Add Service')
                                : _tr('إضافة صنف', 'Add Item')),
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
                                  ? _tr('إضافة خدمة', 'Add Service')
                                  : _tr('إضافة صنف', 'Add Item')),
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
                      child: Text(_tr('إلغاء', 'Cancel')),
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
                            ? _tr('جارٍ الحفظ...', 'Saving...')
                            : _tr('حفظ التعديلات', 'Save Changes'),
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
                  tooltip: _tr('تعديل الخدمة', 'Edit service'),
                ),
              IconButton(
                onPressed: () => setState(() => _items.remove(item)),
                icon: const Icon(LucideIcons.trash2, size: 16),
                color: const Color(0xFFEF4444),
                tooltip: _tr('حذف', 'Remove'),
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
      // Tapping anywhere on a salon row opens the same employee/date/time
      // editor as the pencil button — easier hit target on touch screens.
      return InkWell(
        onTap: () => _editSalonItem(item),
        borderRadius: BorderRadius.circular(12),
        child: card,
      );
    }
    return card;
  }
}

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
        child: Icon(icon, size: 14, color: context.appText),
      ),
    );
  }
}

class _EditableOrderItem {
  final String mealId;
  String name;
  double quantity;
  double unitPrice;
  final List<Extra> extras;
  final String notes;
  final Map<String, String>? localizedNames;

  /// Salon-only payload mirroring the booking-create `card[i]` shape.
  /// Set when the row represents a salon `booking_service` (existing or
  /// freshly added through SalonServiceSelectionDialog). Restaurant rows
  /// leave this null.
  Map<String, dynamic>? salonData;

  _EditableOrderItem({
    required this.mealId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.extras,
    required this.notes,
    this.localizedNames,
    this.salonData,
  });

  double get totalPrice {
    final extrasTotal = extras.fold<double>(0.0, (sum, e) => sum + e.price);
    return (unitPrice + extrasTotal) * quantity;
  }

  bool isSameLine(_EditableOrderItem other) {
    if (mealId != other.mealId) return false;
    if (notes.trim() != other.notes.trim()) return false;
    final a = extras.map((e) => e.id).toList()..sort();
    final b = other.extras.map((e) => e.id).toList()..sort();
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Map<String, dynamic> toPayload() {
    return {
      'meal_id': mealId,
      'meal_name': name,
      'item_name': name,
      'quantity': quantity.round().clamp(1, 9999),
      'price': unitPrice,
      'unit_price': unitPrice,
      if (notes.isNotEmpty) 'note': notes,
      if (extras.isNotEmpty)
        'addons': extras
            .map((e) => int.tryParse(e.id.toString().trim()))
            .whereType<int>()
            .toList(),
    };
  }

  static _EditableOrderItem fromProduct(
    Product product, {
    double quantity = 1,
    List<Extra> extras = const [],
    String notes = '',
  }) {
    return _EditableOrderItem(
      mealId: product.id,
      name: product.name,
      quantity: quantity,
      unitPrice: product.price,
      extras: extras,
      notes: notes,
      localizedNames: product.localizedNames.isNotEmpty ? product.localizedNames : null,
    );
  }

  /// Build an editable row from a freshly-picked salon service. The dialog
  /// returns a payload identical in shape to the salon `card[i]` row, so we
  /// stash it on `salonData` for the save handler to re-emit verbatim.
  static _EditableOrderItem fromSalonResult(Map<String, dynamic> result) {
    final unit = result['unitPrice'] is num
        ? (result['unitPrice'] as num).toDouble()
        : double.tryParse(result['unitPrice']?.toString() ?? '') ?? 0.0;
    final qty = result['quantity'] is num
        ? (result['quantity'] as num).toInt()
        : int.tryParse(result['quantity']?.toString() ?? '') ?? 1;
    return _EditableOrderItem(
      // Negative synthetic id keeps the new row distinguishable from any
      // existing booking_service_id (always positive). The save handler
      // emits a plain card[i] for these without a `booking_service_id`.
      mealId:
          'new_${DateTime.now().microsecondsSinceEpoch}_${result['service_id']}',
      name: result['item_name']?.toString() ?? '',
      quantity: qty.toDouble(),
      unitPrice: unit,
      extras: const [],
      notes: '',
      salonData: Map<String, dynamic>.from(result),
    );
  }

  static _EditableOrderItem fromMap(Map<String, dynamic> map) {
    final langCode = translationService.currentLanguageCode
        .trim()
        .toLowerCase();
    final useAr = langCode.startsWith('ar') || langCode.startsWith('ur');
    final preferredLang = useAr ? 'ar' : 'en';

    String? resolveLocalized(dynamic value) {
      if (value == null) return null;
      if (value is Map) {
        final localized = value[preferredLang]?.toString().trim();
        if (localized != null && localized.isNotEmpty) return localized;
        for (final v in value.values) {
          final s = v?.toString().trim() ?? '';
          if (s.isNotEmpty) return s;
        }
        return null;
      }
      var s = value.toString().trim();
      if (s.startsWith('{') && s.contains('"ar"')) {
        try {
          final parsed = Map<String, dynamic>.from(jsonDecode(s) as Map);
          return resolveLocalized(parsed);
        } catch (_) {}
      }
      return s.isNotEmpty ? s : null;
    }

    String? pickText(List<dynamic> values) {
      for (final value in values) {
        final text = resolveLocalized(value);
        if (text != null && text.isNotEmpty) return text;
      }
      return null;
    }

    String mealId = pickText([
          map['meal_id'],
          map['product_id'],
          map['item_id'],
          map['id'],
          map['meal'] is Map ? (map['meal'] as Map)['id'] : null,
        ]) ??
        '';
    if (mealId.isEmpty) {
      mealId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    final mealMap = map['meal'] is Map
        ? (map['meal'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};
    final serviceMap = map['service'] is Map
        ? (map['service'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : <String, dynamic>{};

    // Salon rows expose `service_name`; restaurant rows use `meal_name`.
    // Without `service_name` first, salon services rendered as the literal
    // "Item" fallback in the edit-order dialog list.
    final name = pickText([
          map['service_name'],
          map['meal_name'],
          map['item_name'],
          map['name'],
          map['title'],
          mealMap['name'],
          serviceMap['name'],
        ]) ??
        'Item';

    double parseNum(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is Map) return 0.0;
      final cleaned =
          value.toString().replaceAll(',', '').replaceAll(RegExp(r'[^\d.\-]'), '');
      return double.tryParse(cleaned) ?? 0.0;
    }

    final quantity = parseNum(map['quantity']).clamp(1, 9999).toDouble();
    var unitPrice =
        parseNum(map['unit_price'] ?? map['unitPrice'] ?? map['price']);
    if (unitPrice == 0 && mealMap.isNotEmpty) {
      unitPrice = parseNum(mealMap['price'] ?? mealMap['unit_price']);
    }

    final extras = <Extra>[];
    final extrasRaw = map['extras'] ??
        map['addons'] ??
        map['add_ons'] ??
        map['options'] ??
        map['modifiers'] ??
        map['operations'];
    if (extrasRaw is List) {
      for (final entry in extrasRaw) {
        if (entry is Map) {
          extras.add(Extra.fromJson(
              entry.map((k, v) => MapEntry(k.toString(), v))));
        } else if (entry != null) {
          extras.add(Extra(id: entry.toString(), name: entry.toString(), price: 0));
        }
      }
    } else if (extrasRaw is Map) {
      final nested = extrasRaw['operations'] ?? extrasRaw['items'];
      if (nested is List) {
        for (final entry in nested) {
          if (entry is Map) {
            extras.add(Extra.fromJson(
                entry.map((k, v) => MapEntry(k.toString(), v))));
          }
        }
      }
    }

    // Extract localizedNames from meal_name_translations
    final Map<String, String>? locNames;
    final mt = map['meal_name_translations'];
    if (mt is Map) {
      locNames = {};
      for (final e in mt.entries) {
        final v = e.value?.toString().trim() ?? '';
        if (v.isNotEmpty) locNames[e.key.toString()] = v;
      }
    } else {
      locNames = null;
    }

    return _EditableOrderItem(
      mealId: mealId,
      name: name,
      quantity: quantity,
      unitPrice: unitPrice,
      extras: extras,
      notes: map['note']?.toString() ?? map['notes']?.toString() ?? '',
      localizedNames: locNames,
    );
  }
}

class _ProductPickerDialog extends StatefulWidget {
  final double taxRate;
  const _ProductPickerDialog({this.taxRate = 0.0});

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  final ProductService _productService = getIt<ProductService>();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  String? get _salonPlaceholderLogo {
    if (ApiConstants.branchModule != 'salons') return null;
    final cached = getIt<BranchService>().cachedBranchReceiptInfo;
    if (cached == null) return null;
    String url = (cached['branch_logo_url']?.toString() ?? '').trim();
    if (url.isEmpty) {
      final branch = cached['branch'];
      if (branch is Map) {
        for (final key in const ['logo', 'image']) {
          final v = branch[key]?.toString().trim() ?? '';
          if (v.isNotEmpty && v.toLowerCase() != 'null') {
            url = v;
            break;
          }
        }
      }
    }
    if (url.isEmpty) return null;
    if (url.startsWith('/')) url = '${ApiConstants.baseUrl}$url';
    return url;
  }

  List<CategoryModel> _categories = [];
  List<Product> _products = [];
  String _selectedCategory = 'all';
  bool _isLoading = false;
  bool _isLastPage = false;
  int _page = 1;

  bool get _useArabicUi {
    final code = translationService.currentLanguageCode.trim().toLowerCase();
    return code.startsWith('ar') || code.startsWith('ur');
  }

  String _tr(String ar, String en) => _useArabicUi ? ar : en;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadProducts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 180 &&
        !_isLoading &&
        !_isLastPage) {
      _loadMore();
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _productService.getMealCategories();
      if (!mounted) return;
      setState(() => _categories = categories);
    } catch (_) {
      // Ignore.
    }
  }

  Future<void> _loadProducts({bool reset = true}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    if (reset) {
      _page = 1;
      _isLastPage = false;
    }

    try {
      final products = await _productService.getProducts(
        categoryId: _selectedCategory,
        page: _page,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _products = products;
        } else {
          _products.addAll(products);
        }
        _isLastPage = products.length < 10;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLastPage || _isLoading) return;
    setState(() => _page += 1);
    await _loadProducts(reset: false);
  }

  List<Product> get _filteredProducts {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _products;
    return _products
        .where((p) => p.name.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 700;
    final dialogWidth = isCompact ? size.width * 0.92 : size.width * 0.8;
    final dialogHeight = isCompact ? size.height * 0.82 : size.height * 0.78;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _tr('اختر صنفاً', 'Select an item'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _tr('ابحث عن صنف', 'Search items'),
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: context.appSurfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_categories.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _categories.length + 1,
                  itemBuilder: (context, index) {
                    final isAll = index == 0;
                    final category =
                        isAll ? null : _categories[index - 1];
                    final label = isAll
                        ? _tr('الكل', 'All')
                        : category?.name ?? '';
                    final value = isAll ? 'all' : category!.id;
                    final selected = _selectedCategory == value;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        selected: selected,
                        label: Text(label),
                        onSelected: (_) {
                          setState(() => _selectedCategory = value);
                          _loadProducts(reset: true);
                        },
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _filteredProducts.isEmpty && !_isLoading
                  ? Center(
                      child: Text(
                        translationService.t('no_products'),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isCompact ? 2 : 4,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: isCompact ? 0.72 : 0.78,
                      ),
                      itemCount: _filteredProducts.length +
                          (_isLoading || !_isLastPage ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _filteredProducts.length) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final product = _filteredProducts[index];
                        return ProductCard(
                          product: product,
                          taxRate: widget.taxRate,
                          priceIsTaxInclusive:
                              ApiConstants.branchModule == 'salons',
                          placeholderImageUrl: _salonPlaceholderLogo,
                          onTap: () => Navigator.pop(context, product),
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
