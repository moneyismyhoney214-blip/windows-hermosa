import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:hermosa_pos/models.dart';
import 'package:hermosa_pos/models/booking_invoice.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';
import 'package:hermosa_pos/services/api/error_handler.dart';
import 'package:hermosa_pos/services/api/order_service.dart';
import 'package:hermosa_pos/services/api/product_service.dart';
import 'package:hermosa_pos/dialogs/product_customization_dialog.dart';
import 'package:hermosa_pos/widgets/product_card.dart';
import '../locator.dart';
import '../services/language_service.dart';
import '../services/app_themes.dart';

/// Describes a single change in an order edit.
/// Types: 'add', 'cancel', 'partial_cancel', 'qty_change', 'replace_old', 'replace_new'
class OrderChange {
  final String type;
  final String name;
  final int quantity;
  final int? oldQuantity;
  final int? cancelledQuantity;
  final Map<String, String>? localizedNames;
  final List<Extra> extras;

  const OrderChange({
    required this.type,
    required this.name,
    required this.quantity,
    this.oldQuantity,
    this.cancelledQuantity,
    this.localizedNames,
    this.extras = const [],
  });
}

class EditOrderDialog extends StatefulWidget {
  final Booking booking;
  final Map<String, dynamic> bookingData;
  final double taxRate;
  final void Function(List<OrderChange> changes, String orderNumber, {bool isFullCancel})? onPrintChanges;

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
    for (final meal in meals) {
      _items.add(_EditableOrderItem.fromMap(meal));
      _originalItems.add(_EditableOrderItem.fromMap(meal));
    }
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
          final resolvedName = _resolveLocalizedName(row['meal_name']) ??
              _resolveLocalizedName(mealMap['name']) ??
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
    return qty.toStringAsFixed(2);
  }

  Future<void> _showProductPicker() async {
    final product = await showDialog<Product>(
      context: context,
      builder: (context) => _ProductPickerDialog(taxRate: widget.taxRate),
    );
    if (product == null) return;
    await _addProductWithCustomization(product);
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
          final orderNum = (_asMap(widget.bookingData['data']) ?? widget.bookingData)['daily_order_number']?.toString() ??
              widget.booking.orderNumber ?? widget.booking.id.toString();
          widget.onPrintChanges!(cancelChanges, orderNum, isFullCancel: true);
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

    return Dialog(
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
                            onPressed: _showProductPicker,
                            icon: const Icon(LucideIcons.plus, size: 16),
                            label: Text(_tr('إضافة صنف', 'Add Item')),
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
                              onPressed: _showProductPicker,
                              icon: const Icon(LucideIcons.plus, size: 16),
                              label: Text(_tr('إضافة صنف', 'Add Item')),
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
    );
  }

  Widget _buildEditableItemCard(_EditableOrderItem item) {
    final extras = item.extras;
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
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                '${item.totalPrice.toStringAsFixed(2)} ${ApiConstants.currency}',
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
        child: Icon(icon, size: 14, color: const Color(0xFF0F172A)),
      ),
    );
  }
}

class _EditableOrderItem {
  final String mealId;
  final String name;
  double quantity;
  final double unitPrice;
  final List<Extra> extras;
  final String notes;
  final Map<String, String>? localizedNames;

  _EditableOrderItem({
    required this.mealId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.extras,
    required this.notes,
    this.localizedNames,
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

    final name = pickText([
          map['meal_name'],
          map['item_name'],
          map['name'],
          map['title'],
          mealMap['name'],
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
                  fillColor: const Color(0xFFF8FAFC),
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
