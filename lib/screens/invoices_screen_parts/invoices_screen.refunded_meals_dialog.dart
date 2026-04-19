// ignore_for_file: unused_element
part of '../invoices_screen.dart';

class _RefundedMealsDialog extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> refundedMeals;

  const _RefundedMealsDialog({
    required this.title,
    required this.refundedMeals,
  });

  bool get _useArabicUi {
    final code = translationService.currentLanguageCode.trim().toLowerCase();
    return code.startsWith('ar') || code.startsWith('ur');
  }

  String _tr(String ar, String en) => _useArabicUi ? ar : en;

  double _parsePrice(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '')) ?? 0;
  }

  bool _isTruthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 700;

    double totalRefunded = 0;
    for (final meal in refundedMeals) {
      totalRefunded += _parsePrice(meal['total'] ?? meal['price']);
    }

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 40,
        vertical: isCompact ? 24 : 40,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Color(0xFFDC2626),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.refreshCw,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
        color: context.appCardBg.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${refundedMeals.length} ${_tr('صنف', 'items')}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Items list
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: refundedMeals.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 20, color: Color(0xFFE2E8F0)),
                itemBuilder: (context, index) {
                  final meal = refundedMeals[index];
                  return _buildMealRow(meal);
                },
              ),
            ),

            // Total
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                border:
                    Border(top: BorderSide(color: Colors.grey.shade200)),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _tr('إجمالي المرتجعات', 'Total Refunded'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                      Text(
                        '${totalRefunded.toStringAsFixed(2)} ${ApiConstants.currency}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        _tr('إغلاق', 'Close'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
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

  Widget _buildMealRow(Map<String, dynamic> meal) {
    final name = meal['meal_name']?.toString() ??
        meal['name']?.toString() ??
        _tr('صنف غير معروف', 'Unknown item');
    final quantity = int.tryParse(meal['quantity']?.toString() ?? '1') ?? 1;
    final total = _parsePrice(meal['total'] ?? meal['price']);
    final discount = _parsePrice(meal['discount']);
    final tax = _parsePrice(meal['tax']);
    final isInvoiced = _isTruthy(meal['is_invoiced']);
    final invoiceId = meal['invoice_id'];
    final addons = meal['addons'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'x$quantity',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFEF4444),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                  decoration: TextDecoration.lineThrough,
                ),
              ),
            ),
            Text(
              '${total.toStringAsFixed(2)} ${ApiConstants.currency}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFFEF4444),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(width: 42),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
        if (discount > 0 || tax > 0) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 42),
            child: Text(
              [
                if (discount > 0)
                  '${_tr('خصم', 'Discount')}: ${discount.toStringAsFixed(2)}',
                if (tax > 0)
                  '${_tr('ضريبة', 'Tax')}: ${tax.toStringAsFixed(2)}',
              ].join(' | '),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        ],
        if (addons is List && addons.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 42),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: addons.map((addon) {
                final text = addon is Map
                    ? [addon['attribute'], addon['option']]
                        .where((e) => e != null && e.toString().trim().isNotEmpty)
                        .join(' - ')
                    : addon.toString();
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '+ $text',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFFD97706),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}
