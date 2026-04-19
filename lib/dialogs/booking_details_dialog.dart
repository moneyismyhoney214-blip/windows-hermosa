import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';
import 'package:hermosa_pos/services/api/branch_service.dart';
import 'package:hermosa_pos/locator.dart';
import '../services/language_service.dart';
import '../services/app_themes.dart';

class BookingDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> bookingData;
  final VoidCallback? onEditOrder;

  const BookingDetailsDialog({
    super.key,
    required this.bookingData,
    this.onEditOrder,
  });

  bool get _useArabicUi {
    final code = translationService.currentLanguageCode.trim().toLowerCase();
    return code.startsWith('ar') || code.startsWith('ur');
  }

  String _tr(String ar, String en) => _useArabicUi ? ar : en;

  bool _isTruthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value.toString().trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
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
        (size.width - insetPadding.horizontal).clamp(280.0, 680.0).toDouble();
    final dialogHeight =
        (size.height - insetPadding.vertical).clamp(420.0, 760.0).toDouble();

    final data = _asMap(bookingData['data']) ?? bookingData;

    // Extract booking information
    final orderId = data['id']?.toString() ?? '';
    final rawOrderNumber = (data['order_number'] ??
                data['booking_number'] ??
                data['daily_order_number'] ??
                data['id'])
            ?.toString() ??
        '';

    final status = data['status']?.toString() ?? 'pending';

    // Determine if this is a pay-later order
    final isPayLater = !_isTruthy(data['is_paid']) &&
        !_isTruthy(data['paid']) &&
        data['invoice_id'] == null &&
        data['invoice_number'] == null;

    // Check if fully refunded (has refunded_meals and status indicates refund)
    final isRefunded = status == 'refunded' ||
        status == '4' ||
        _isTruthy(data['is_refunded']) ||
        _isTruthy(data['refunded']);

    // Show invoice number for non-pay-later orders, booking number for pay-later
    final bookingNum = data['booking_number']?.toString().trim() ?? '';
    final dailyNum = data['daily_order_number']?.toString().trim() ?? '';
    final String displayNumber;
    if (isPayLater && !isRefunded) {
      if (bookingNum.isNotEmpty) {
        // API returns e.g. "#BOK-442816" — use it as-is (strip leading #)
        displayNumber = bookingNum.startsWith('#') ? bookingNum.substring(1) : bookingNum;
      } else if (dailyNum.isNotEmpty) {
        displayNumber = 'bok-$dailyNum';
      } else {
        displayNumber = 'bok-$orderId';
      }
    } else {
      final invoiceNum = data['invoice_number']?.toString().trim();
      if (invoiceNum != null && invoiceNum.isNotEmpty) {
        displayNumber = invoiceNum.startsWith('#')
            ? invoiceNum.substring(1)
            : invoiceNum;
      } else if (bookingNum.isNotEmpty) {
        displayNumber = bookingNum.startsWith('#') ? bookingNum.substring(1) : bookingNum;
      } else {
        displayNumber = rawOrderNumber.isNotEmpty ? 'in-$rawOrderNumber' : 'in-$orderId';
      }
    }
    final date = data['date']?.toString() ??
        data['created_at']?.toString() ??
        data['updated_at']?.toString() ??
        'N/A';

    // Extract meals/items first so we can compute totals from them if needed
    final meals = _extractMeals(data);
    final refundedMeals = _extractRefundedMeals(data);

    // Compute totals from items if API returns 0 (e.g. after full refund)
    var total = _parsePrice(
      data['total'] ?? data['total_price'] ?? data['invoice_total'],
    );
    var tax = _parsePrice(
      data['tax'] ??
          data['vat'] ??
          data['tax_value'] ??
          data['tax_amount'] ??
          data['value_tax'],
    );
    final discount = _parsePrice(
      data['discount'] ?? data['discount_value'] ?? data['total_discount'],
    );
    var grandTotal = _parsePrice(
      data['grand_total'] ??
          data['final_total'] ??
          data['invoice_total'] ??
          data['total'] ??
          data['total_price'],
    );

    // Calculate refunded amount from separate refunded_meals list
    double refundedTotal = 0;
    for (final refund in refundedMeals) {
      refundedTotal += _parsePrice(refund['total'] ?? refund['price'] ?? refund['unit_price']);
    }

    // Also count refunded items that were merged into meals list
    double mergedRefundTotal = 0;
    double activeMealsTotal = 0;
    for (final meal in meals) {
      final isRefunded = _isTruthy(meal['is_refunded']) ||
          _isTruthy(meal['is_cancelled']) ||
          meal['status'] == 'refunded' ||
          meal['status'] == 'cancelled';
      final price = _parsePrice(meal['total'] ?? meal['price'] ?? meal['unit_price']);
      if (isRefunded) {
        mergedRefundTotal += price;
      } else {
        activeMealsTotal += price;
      }
    }

    // Use the larger of the two refund totals (avoid double-counting)
    final effectiveRefundTotal = refundedTotal > mergedRefundTotal
        ? refundedTotal
        : mergedRefundTotal;

    // Resolve the active branch's tax configuration once — the old code
    // baked in 15% VAT even when the branch was tax-free, so a 6 SAR order
    // appeared as 6.90 in the orders list.
    final branchService = getIt<BranchService>();
    final resolvedTaxRate =
        branchService.cachedHasTax ? branchService.cachedTaxRate : 0.0;
    final taxMultiplier = 1.0 + resolvedTaxRate;

    // Recalculate from items when totals are missing or tax is 0.
    // API 'price' field is the PRE-TAX line total (confirmed from HAR:
    // app sends price=26 with tax, API returns price=22.61 without tax).
    if ((grandTotal == 0 || tax == 0) && (meals.isNotEmpty || refundedMeals.isNotEmpty)) {
      final originalPreTax = activeMealsTotal + effectiveRefundTotal;
      if (originalPreTax > 0) {
        total = originalPreTax;
        tax = originalPreTax * resolvedTaxRate;
        grandTotal = originalPreTax + tax;
      }
    }

    // Subtract refunded amount from totals to show actual remaining amount.
    // effectiveRefundTotal is also pre-tax (from same API price field).
    if (effectiveRefundTotal > 0 && grandTotal > 0) {
      final refundWithTax = effectiveRefundTotal * taxMultiplier;
      grandTotal = (grandTotal - refundWithTax).clamp(0.0, double.infinity);
      total = taxMultiplier > 0 ? grandTotal / taxMultiplier : grandTotal;
      tax = grandTotal - total;
    }

    // Extract customer info
    final customerName = _extractCustomerName(data);
    // Extract table info
    final tableName = data['table_name']?.toString() ??
        data['table']?.toString() ??
        _asMap(data['type_extra'])?['table_name']?.toString();

    return Dialog(
      insetPadding: insetPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.all(isCompact ? 16 : 24),
              decoration: const BoxDecoration(
                color: Color(0xFFF58220),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              translationService.t('order_details'),
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
                              '#$displayNumber',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _getStatusColor(status)),
                        ),
                        child: Text(
                          _getStatusText(status),
                          style: TextStyle(
                            color: _getStatusColor(status),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildInfoChip(LucideIcons.calendar, date),
                      _buildInfoChip(LucideIcons.user, customerName),
                      if (tableName != null) ...[
                        _buildInfoChip(LucideIcons.layout,
                            '${translationService.t('table')} $tableName'),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Meals List + Refunded Meals
            Expanded(
              child: meals.isEmpty && refundedMeals.isEmpty
                  ? Center(
                      child: Text(
                        translationService.t('no_items_in_order'),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        ...meals.asMap().entries.map((entry) {
                          return Column(
                            children: [
                              _buildMealItem(entry.value),
                              if (entry.key < meals.length - 1) const Divider(),
                            ],
                          );
                        }),
                        if (refundedMeals.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _buildRefundedMealsSection(refundedMeals),
                        ],
                      ],
                    ),
            ),

            // Summary
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.appBg,
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Column(
                children: [
                  _buildSummaryRow(translationService.t('subtotal'), total),
                  const SizedBox(height: 8),
                  _buildSummaryRow(
                      translationService
                          .t('tax_with_rate', args: {'rate': '15'}),
                      tax),
                  if (discount > 0) ...[
                    const SizedBox(height: 8),
                    _buildSummaryRow(
                        translationService.t('discount'), -discount,
                        isDiscount: true),
                  ],
                  if (effectiveRefundTotal > 0) ...[
                    const SizedBox(height: 8),
                    _buildSummaryRow(
                        _tr('المسترجع', 'Refunded'), -effectiveRefundTotal,
                        isDiscount: true),
                  ],
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(),
                  ),
                  _buildSummaryRow(translationService.t('total'), grandTotal,
                      isTotal: true),
                  const SizedBox(height: 16),
                  if (onEditOrder != null) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          onEditOrder?.call();
                        },
                        icon: const Icon(LucideIcons.edit3, size: 18),
                        label: Text(_tr('تعديل الطلب', 'Edit Order')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF2563EB),
                          side: const BorderSide(color: Color(0xFF2563EB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF58220),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        translationService.t('close'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
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

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.8)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _resolveLocalizedName(dynamic value) {
    if (value == null) return '';
    if (value is Map) {
      final langCode = _useArabicUi ? 'ar' : 'en';
      final localized = value[langCode]?.toString().trim();
      if (localized != null && localized.isNotEmpty) return localized;
      for (final v in value.values) {
        final s = v?.toString().trim() ?? '';
        if (s.isNotEmpty) return s;
      }
      return '';
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
    return s;
  }

  Widget _buildMealItem(Map<String, dynamic> meal) {
    final rawName = meal['service_name'] ?? meal['meal_name'] ?? meal['name'] ?? meal['item_name'];
    final name = _resolveLocalizedName(rawName).isNotEmpty
        ? _resolveLocalizedName(rawName)
        : translationService.t('unknown_item');
    final quantity = int.tryParse(meal['quantity']?.toString() ?? '1') ?? 1;
    final unitPrice = _parsePrice(meal['unit_price'] ?? meal['price']);
    final totalPrice = _parsePrice(meal['total'] ?? meal['price']);
    final extras = _extractMealExtras(meal);
    final rawStatus = meal['status']?.toString().trim().toLowerCase() ?? '';
    final isCancelled = rawStatus == 'cancelled' ||
        rawStatus == 'canceled' ||
        rawStatus == '3' ||
        _isTruthy(meal['is_cancelled']) ||
        _isTruthy(meal['cancel_status']) ||
        _isTruthy(meal['cancelled']);
    final isRefunded = rawStatus == 'refunded' ||
        rawStatus == '4' ||
        _isTruthy(meal['is_refunded']) ||
        (meal['refund_id'] != null &&
            meal['refund_id'].toString().trim().isNotEmpty &&
            meal['refund_id'].toString().trim() != '0' &&
            meal['refund_id'].toString().trim() != 'null');
    final hasInvoicedFlag = meal.containsKey('is_invoiced');
    final badgeLabel = isCancelled
        ? (hasInvoicedFlag && !_isTruthy(meal['is_invoiced'])
            ? _tr('ملغي قبل الفوترة', 'Cancelled before invoice')
            : _tr('ملغي', 'Cancelled'))
        : isRefunded
            ? _tr('مسترجع', 'Refunded')
            : null;
    final quantityColor = isCancelled
        ? const Color(0xFF94A3B8)
        : isRefunded
            ? const Color(0xFFEF4444)
            : const Color(0xFFF58220);
    final quantityBackground = isCancelled
        ? const Color(0xFFF1F5F9)
        : isRefunded
            ? const Color(0xFFFEF2F2)
            : const Color(0xFFFFF7ED);
    final titleColor =
        isCancelled ? const Color(0xFF94A3B8) : const Color(0xFF0F172A);
    final amountColor = isCancelled
        ? const Color(0xFF94A3B8)
        : isRefunded
            ? const Color(0xFFEF4444)
            : const Color(0xFFF58220);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: quantityBackground,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'x$quantity',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: quantityColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: titleColor,
                              decoration: isCancelled
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                            ),
                          ),
                          if (badgeLabel != null) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isCancelled
                                    ? const Color(0xFFF1F5F9)
                                    : const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isCancelled
                                      ? const Color(0xFFCBD5E1)
                                      : const Color(0xFFFCA5A5),
                                ),
                              ),
                              child: Text(
                                badgeLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isCancelled
                                      ? const Color(0xFF64748B)
                                      : const Color(0xFFDC2626),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${totalPrice.toStringAsFixed(2)} ${ApiConstants.currency}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: amountColor,
                ),
              ),
            ],
          ),
          if (extras.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 40),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: () {
                  // Group duplicate extras and show count
                  final grouped = <String, int>{};
                  for (final extra in extras) {
                    final name = extra['name']?.toString() ?? '';
                    if (name.isNotEmpty) {
                      grouped[name] = (grouped[name] ?? 0) + 1;
                    }
                  }
                  return grouped.entries.map((entry) {
                    final label = entry.value > 1
                        ? '+ ${entry.key} x${entry.value}'
                        : '+ ${entry.key}';
                    return Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(4),
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
            ),
          ],
          if (unitPrice > 0 && quantity > 1) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 40),
              child: Text(
                '${unitPrice.toStringAsFixed(2)} ${ApiConstants.currency} / ${translationService.t('per_unit')}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _mergeRefundedMealsWithItems(
    List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> refundedMeals,
  ) {
    if (refundedMeals.isEmpty) return items;

    String normalizeId(dynamic value) =>
        value?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';

    Set<String> signaturesFor(Map<String, dynamic> item) {
      final signatures = <String>{};

      void add(String prefix, dynamic value) {
        final normalized = normalizeId(value);
        if (normalized.isNotEmpty) {
          signatures.add('$prefix:$normalized');
        }
      }

      add('sales_meal', item['sales_meal_id']);
      add('booking_meal', item['booking_meal_id']);
      add('item', item['item_id']);
      add('id', item['id']);
      add('meal', item['meal_id']);

      // Only use name-based matching when no ID signatures exist.
      // This prevents re-added items from being merged with refunded items
      // that share the same name but have different IDs.
      if (signatures.isEmpty) {
        final name =
            (item['meal_name'] ?? item['name'] ?? item['item_name'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
        if (name.isNotEmpty) {
          signatures.add(
            'name:$name|qty:${item['quantity'] ?? 1}|total:${_parsePrice(item['total'] ?? item['price']).toStringAsFixed(2)}',
          );
        }
      }

      return signatures;
    }

    Map<String, dynamic> normalizeRefund(Map<String, dynamic> meal) {
      final normalized = Map<String, dynamic>.from(meal);
      final isInvoiced = _isTruthy(normalized['is_invoiced']);
      normalized['meal_name'] = normalized['meal_name'] ??
          normalized['name'] ??
          normalized['item_name'] ??
          translationService.t('unknown_item');
      normalized['quantity'] = int.tryParse(
            normalized['quantity']?.toString() ?? '',
          ) ??
          1;
      normalized['unit_price'] ??= normalized['price'];
      normalized['total'] ??=
          _parsePrice(normalized['price']) * (normalized['quantity'] as int);
      normalized['status'] = isInvoiced ? 'refunded' : 'cancelled';
      if (isInvoiced) {
        normalized['is_refunded'] = true;
        normalized['sales_meal_id'] ??= normalized['id'];
      } else {
        normalized['is_cancelled'] = true;
        normalized['booking_meal_id'] ??= normalized['id'];
      }
      return normalized;
    }

    final merged = items
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: true);
    final signatureIndex = <String, int>{};

    void indexRow(int index, Map<String, dynamic> item) {
      for (final signature in signaturesFor(item)) {
        signatureIndex.putIfAbsent(signature, () => index);
      }
    }

    for (var i = 0; i < merged.length; i++) {
      indexRow(i, merged[i]);
    }

    for (final rawRefund in refundedMeals) {
      final refund = normalizeRefund(rawRefund);
      int? matchedIndex;
      for (final signature in signaturesFor(refund)) {
        final existingIndex = signatureIndex[signature];
        if (existingIndex != null) {
          matchedIndex = existingIndex;
          break;
        }
      }

      if (matchedIndex != null) {
        final existing = merged[matchedIndex];
        // If the existing item is ACTIVE (not refunded/cancelled),
        // do NOT overwrite it. Add refund as separate row instead.
        final existingRefunded = _isTruthy(existing['is_refunded']) ||
            _isTruthy(existing['is_cancelled']) ||
            existing['status'] == 'refunded' ||
            existing['status'] == 'cancelled';

        if (!existingRefunded) {
          merged.add(refund);
          indexRow(merged.length - 1, refund);
          continue;
        }

        merged[matchedIndex] = Map<String, dynamic>.from(existing)
          ..addAll(refund);
        indexRow(matchedIndex, merged[matchedIndex]);
        continue;
      }

      merged.add(refund);
      indexRow(merged.length - 1, refund);
    }

    return merged;
  }

  Widget _buildSummaryRow(String label, double value,
      {bool isTotal = false, bool isDiscount = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            color: isDiscount ? Colors.orange : const Color(0xFF64748B),
          ),
        ),
        Text(
          isDiscount
              ? '- ${value.abs().toStringAsFixed(2)} ${ApiConstants.currency}'
              : '${value.toStringAsFixed(2)} ${ApiConstants.currency}',
          style: TextStyle(
            fontSize: isTotal ? 18 : 14,
            fontWeight: FontWeight.bold,
            color: isTotal
                ? const Color(0xFF1E293B)
                : isDiscount
                    ? Colors.orange
                    : const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case '1':
      case 'pending':
      case 'new':
        return Colors.orange;
      case '2':
      case 'started':
      case 'confirmed':
      case 'in_progress':
        return Colors.blue;
      case '3':
        return Colors.green;
      case '4':
      case 'preparing':
      case 'processing':
        return Colors.blue;
      case '5':
      case 'ready':
      case 'ready_for_delivery':
        return Colors.green;
      case '6':
      case 'on_the_way':
      case 'out_for_delivery':
        return Colors.blue;
      case '7':
      case 'completed':
      case 'finished':
      case 'done':
      case 'paid':
        return Colors.green;
      case '8':
      case 'cancelled':
      case 'canceled':
        return Colors.red;
      case 'later':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case '1':
      case 'pending':
      case 'new':
        return translationService.t('pending');
      case '2':
      case 'started':
      case 'confirmed':
      case 'in_progress':
        return translationService.t('processing');
      case '3':
        return translationService.t('completed');
      case '4':
      case 'preparing':
      case 'processing':
        return translationService.t('processing');
      case '5':
      case 'ready':
      case 'ready_for_delivery':
        return translationService.t('ready');
      case '6':
      case 'on_the_way':
      case 'out_for_delivery':
        return translationService.t('on_the_way');
      case '7':
      case 'completed':
      case 'finished':
      case 'done':
      case 'paid':
        return translationService.t('completed');
      case '8':
      case 'cancelled':
      case 'canceled':
        return translationService.t('cancelled');
      case 'later':
        return translationService.t('pay_later_status');
      default:
        return status;
    }
  }

  double _parsePrice(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      var cleaned = value.replaceAll(',', '').trim();
      final currency = ApiConstants.currency.trim();
      if (currency.isNotEmpty) {
        cleaned = cleaned.replaceAll(currency, '');
      }
      cleaned = cleaned
          .replaceAll('SAR', '')
          .replaceAll('QAR', '')
          .replaceAll('RS', '')
          .replaceAll('ر.س', '')
          .replaceAll(RegExp(r'[^\d.\-]'), '');
      return double.tryParse(cleaned) ?? 0.0;
    }
    return 0.0;
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  String _extractCustomerName(Map<String, dynamic> data) {
    // Try all possible locations for customer name
    final candidates = <dynamic>[
      data['customer_name'],
      data['client_name'],
      _asMap(data['customer'])?['name'],
      _asMap(data['customer'])?['fullname'],
      _asMap(data['client'])?['name'],
      _asMap(data['user'])?['name'],
      _asMap(data['user'])?['fullname'],
      // Nested booking structure
      _asMap(data['booking'])?['customer_name'],
      _asMap(_asMap(data['booking'])?['customer'])?['name'],
      _asMap(_asMap(data['booking'])?['user'])?['name'],
      // Direct string fields
      data['client'],
    ];

    for (final c in candidates) {
      if (c is String) {
        final trimmed = c.trim();
        if (trimmed.isNotEmpty && trimmed != 'null') return trimmed;
      }
    }

    return translationService.t('general_customer');
  }

  List<Map<String, dynamic>> _extractRefundedMeals(Map<String, dynamic> data) {
    final raw = data['refunded_meals'];
    if (raw is! List || raw.isEmpty) return const [];
    return raw
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Widget _buildRefundedMealsSection(List<Map<String, dynamic>> refundedMeals) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.refreshCw,
                  size: 16, color: Color(0xFFDC2626)),
              const SizedBox(width: 8),
              Text(
                _tr('المرتجعات', 'Refunded Items'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFDC2626),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${refundedMeals.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFFFCA5A5), height: 20),
          ...refundedMeals.map((meal) => _buildRefundedMealRow(meal)),
        ],
      ),
    );
  }

  Widget _buildRefundedMealRow(Map<String, dynamic> meal) {
    final name = meal['meal_name']?.toString() ??
        meal['name']?.toString() ??
        _tr('صنف غير معروف', 'Unknown item');
    final quantity = int.tryParse(meal['quantity']?.toString() ?? '1') ?? 1;
    final total = _parsePrice(meal['total'] ?? meal['price']);
    final isInvoiced = _isTruthy(meal['is_invoiced']);
    final addons = meal['addons'];
    final invoiceId = meal['invoice_id'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'x$quantity',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFEF4444),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF991B1B),
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isInvoiced
                            ? const Color(0xFFFEE2E2)
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isInvoiced
                            ? (invoiceId != null
                                ? _tr('مسترجع - فاتورة #$invoiceId',
                                    'Refunded - Invoice #$invoiceId')
                                : _tr('مسترجع', 'Refunded'))
                            : _tr('ملغي قبل الفوترة', 'Cancelled before invoice'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isInvoiced
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${total.toStringAsFixed(2)} ${ApiConstants.currency}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFEF4444),
                ),
              ),
            ],
          ),
          if (addons is List && addons.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 32),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: () {
                  // Group duplicate addons and show count
                  final grouped = <String, int>{};
                  for (final addon in addons) {
                    final addonText = addon is Map
                        ? (addon['name']?.toString() ??
                            addon['attribute']?.toString() ??
                            addon['option']?.toString() ??
                            '')
                        : addon.toString();
                    if (addonText.isNotEmpty) {
                      grouped[addonText] = (grouped[addonText] ?? 0) + 1;
                    }
                  }
                  return grouped.entries.map((entry) {
                    final label = entry.value > 1
                        ? '+ ${entry.key} x${entry.value}'
                        : '+ ${entry.key}';
                    return Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFFD97706),
                        ),
                      ),
                    );
                  }).toList();
                }(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _extractMeals(Map<String, dynamic> data) {
    List<Map<String, dynamic>> normalizeList(dynamic source) {
      if (source is! List) return const [];
      return source
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }

    // Try different possible field names for meals
    final possibleKeys = [
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

    // Build price lookup from booking_meals
    final priceLookup = <String, Map<String, dynamic>>{};
    for (final key in ['booking_meals', 'meals', 'items']) {
      final raw = data[key];
      if (raw is! List) continue;
      for (final item in raw) {
        if (item is! Map) continue;
        final row = item.map((k, v) => MapEntry(k.toString(), v));
        final id = (row['id'] ?? row['meal_id'])?.toString();
        if (id != null && id.isNotEmpty) priceLookup[id] = row;
      }
    }

    for (final key in possibleKeys) {
      final meals = normalizeList(data[key]);
      if (meals.isNotEmpty) {
        final normalizedMeals = meals.map((row) {
          final mealMap = row['meal'] is Map
              ? (row['meal'] as Map).map((k, v) => MapEntry(k.toString(), v))
              : <String, dynamic>{};
          String? resolveName(dynamic nameValue) {
            if (nameValue == null) return null;
            if (nameValue is Map) {
              final langCode = _useArabicUi ? 'ar' : 'en';
              final localized = nameValue[langCode]?.toString().trim();
              if (localized != null && localized.isNotEmpty) return localized;
              for (final v in nameValue.values) {
                final s = v?.toString().trim() ?? '';
                if (s.isNotEmpty) return s;
              }
              return null;
            }
            var s = nameValue.toString().trim();
            if (s.startsWith('{') && s.contains('"ar"')) {
              try {
                final parsed = Map<String, dynamic>.from(jsonDecode(s) as Map);
                return resolveName(parsed);
              } catch (_) {}
            }
            return s.isNotEmpty ? s : null;
          }

          final mealName = resolveName(row['service_name']) ??
              resolveName(row['meal_name']) ??
              resolveName(mealMap['name']) ??
              resolveName(row['name']) ??
              resolveName(row['item_name']);

          final result = Map<String, dynamic>.from(row);
          if (mealName != null) result['meal_name'] = mealName;
          result['quantity'] ??= 1;
          if (result['unit_price'] == null && row['price'] != null) {
            result['unit_price'] = row['price'];
          }
          if (result['total'] == null && row['price'] != null) {
            result['total'] = row['price'];
          }
          // Enrich with price from priceLookup if still missing
          if (result['price'] == null && result['unit_price'] == null) {
            final mealId = (result['meal_id'] ?? result['id'])?.toString();
            if (mealId != null && priceLookup.containsKey(mealId)) {
              final src = priceLookup[mealId]!;
              result['price'] ??= src['price'];
              result['unit_price'] ??= src['unit_price'] ?? src['price'];
              result['total'] ??= src['total'] ?? src['price'];
            }
            // Also try nested meal object
            if (result['price'] == null && mealMap.isNotEmpty) {
              result['price'] ??= mealMap['price'];
              result['unit_price'] ??= mealMap['unit_price'] ?? mealMap['price'];
              result['total'] ??= mealMap['price'];
            }
          }
          return result;
        }).toList();
        final refundedMeals = normalizeList(data['refunded_meals']);
        return _mergeRefundedMealsWithItems(normalizedMeals, refundedMeals);
      }
    }

    // Some APIs wrap line items inside nested nodes.
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

    return _mergeRefundedMealsWithItems(
      const <Map<String, dynamic>>[],
      normalizeList(data['refunded_meals']),
    );
  }

  List<Map<String, dynamic>> _extractMealExtras(Map<String, dynamic> meal) {
    // Try different possible field names for extras
    final possibleKeys = [
      'extras',
      'add_ons',
      'addons',
      'options',
      'modifiers',
      'cooking_type',
      'meal_attributes',
      'operations',
    ];

    for (final key in possibleKeys) {
      final extras = meal[key];
      if (extras is List) {
        return extras.where((item) => item != null).map((item) {
          if (item is Map) {
            final normalized = item.map((k, v) => MapEntry(k.toString(), v));
            final label = normalized['name'] ??
                normalized['title'] ??
                normalized['label'] ??
                [
                  normalized['attribute'],
                  normalized['option'],
                ].whereType<Object>().map((e) => e.toString()).join(' - ');
            return {
              ...normalized,
              'name': label.toString().trim().isEmpty
                  ? translationService.t('unknown_item')
                  : label,
            };
          }
          return <String, dynamic>{'name': item.toString()};
        }).toList();
      }
      if (extras is Map) {
        final nested = extras['operations'] ?? extras['items'];
        if (nested is List) {
          return nested
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList();
        }
      }
    }

    return [];
  }
}
