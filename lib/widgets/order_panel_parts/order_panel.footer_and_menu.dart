// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../order_panel.dart';

extension OrderPanelFooterAndMenu on _OrderPanelState {
  Widget _buildOrderNotes() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: widget.orderNotesController,
        maxLines: 2,
        decoration: InputDecoration(
          hintStyle: const TextStyle(fontSize: 12),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Future<void> _ensureCustomer(VoidCallback onConfirmed) async {
    // In salon mode, customer is ALWAYS required regardless of settings
    final requireCustomer =
        widget.isSalonMode || widget.requireCustomerSelection;

    if (!requireCustomer) {
      onConfirmed();
      return;
    }

    // Enforce explicit customer selection when required.
    if (widget.selectedCustomer != null) {
      onConfirmed();
      return;
    }

    final customer = await showDialog<Customer?>(
      context: context,
      builder: (context) => const CustomerSelectionDialog(),
    );

    if (customer != null) {
      widget.onSelectCustomer(customer);
      // Small delay to let the state update
      Future.delayed(const Duration(milliseconds: 100), onConfirmed);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              _tr('يرجى اختيار عميل للمتابعة', 'Please select a customer')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildFooter(double subtotal, double tax, bool hasItems) {
    // Calculate promo discount if applied
    final promo = widget.appliedPromoCode;
    double promoDiscountAmount = 0.0;
    if (promo != null) {
      final grossTotal = subtotal + tax;
      if (promo.type == DiscountType.percentage) {
        promoDiscountAmount = grossTotal * (promo.discount / 100);
        if (promo.maxDiscount != null &&
            promoDiscountAmount > promo.maxDiscount!) {
          promoDiscountAmount = promo.maxDiscount!;
        }
      } else {
        promoDiscountAmount = promo.discount;
      }
      promoDiscountAmount = promoDiscountAmount.clamp(0.0, subtotal + tax);
    }

    return Container(
      color: context.appSurfaceAlt,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _SummaryRow(
              label: _tr('المجموع الفرعي', 'Subtotal'),
              value: subtotal.toStringAsFixed(2)),
          const SizedBox(height: 8),
          _SummaryRow(
              label: _tr('الضريبة (${(widget.taxRate * 100).toStringAsFixed(0)}%)', 'Tax (${(widget.taxRate * 100).toStringAsFixed(0)}%)'),
              value: tax.toStringAsFixed(2)),
          if (widget.orderDiscount > 0) ...[
            const SizedBox(height: 8),
            _SummaryRow(
                label: _tr('خصم إضافي', 'Additional Discount'),
                value: '- ${widget.orderDiscount.toStringAsFixed(2)}',
                color: Colors.orange),
          ],
          if (promo != null && promoDiscountAmount > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(LucideIcons.badgePercent,
                          size: 14, color: Color(0xFF22C55E)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '${_tr('كوبون', 'Coupon')}: ${promo.code}'
                          ' (${promo.type == DiscountType.percentage ? '${promo.discount.toStringAsFixed(0)}%' : '${promo.discount.toStringAsFixed(2)} ${ApiConstants.currency}'})',
                          style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF22C55E),
                              fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '- ${promoDiscountAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF22C55E),
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Divider(color: context.appBorder),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_tr('الإجمالي', 'Total'),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: context.appText)),
              Text(
                  '${widget.totalAmount.toStringAsFixed(2)} ${ApiConstants.currency}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: context.appText)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              // Menu Button
              _buildMenuButton(),
              const SizedBox(width: 4),
              // Pay Later
              Expanded(
                flex: 2,
                child: _buildActionButton(
                  label: _tr('لاحق', 'Later'),
                  icon: LucideIcons.clock,
                  color: Colors.orange,
                  onPressed: hasItems
                      ? () => _ensureCustomer(widget.onPayLater)
                      : null,
                ),
              ),
              const SizedBox(width: 4),
              // Pay Now
              Expanded(
                flex: 3,
                child: _buildActionButton(
                  label: _tr('دفع', 'Pay'),
                  icon: LucideIcons.checkCircle,
                  color: const Color(0xFF10B981),
                  onPressed: hasItems
                      ? () => _ensureCustomer(() {
                            if (getIt.isRegistered<CashierSoundService>()) {
                              getIt<CashierSoundService>().playButtonSound();
                            }
                            widget.onPay();
                          })
                      : null,
                  showAmount: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton() {
    return PopupMenuButton<String>(
      icon: Container(
        width: 42,
        height: 54,
        decoration: BoxDecoration(
          color: context.appCardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.appBorder),
        ),
        child: Icon(LucideIcons.moreVertical,
            color: context.appTextMuted, size: 20),
      ),
      onSelected: (value) {
        if (value == 'clear') widget.onClear();
        if (value == 'discount') _showOrderDiscountDialog();
        if (value == 'free') widget.onToggleOrderFree();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
            value: 'clear',
            child: Text(_tr('مسح السلة', 'Clear Cart'),
                style: const TextStyle(color: Colors.red))),
        PopupMenuItem(
            value: 'discount',
            child: Text(_tr('خصم على الإجمالي', 'Order Discount'))),
        PopupMenuItem(
            value: 'free',
            child: Text(widget.isOrderFree
                ? _tr('إلغاء المجاني', 'Cancel Free')
                : _tr('الطلب مجاني', 'Free Order'))),
      ],
    );
  }

  void _showOrderDiscountDialog() {
    final controller = TextEditingController(
        text: widget.orderDiscount > 0
            ? widget.orderDiscount.toStringAsFixed(0)
            : '');
    var selectedType = DiscountType.amount;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_tr('خصم على الطلب', 'Order Discount')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Discount type toggle
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setDialogState(() => selectedType = DiscountType.amount),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: selectedType == DiscountType.amount ? const Color(0xFFF58220) : Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _tr('قيمة', 'Amount'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: selectedType == DiscountType.amount ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setDialogState(() => selectedType = DiscountType.percentage),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: selectedType == DiscountType.percentage ? const Color(0xFFF58220) : Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _tr('نسبة %', 'Percentage %'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: selectedType == DiscountType.percentage ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: selectedType == DiscountType.percentage
                      ? _tr('نسبة الخصم %', 'Discount %')
                      : _tr('قيمة الخصم', 'Discount Amount'),
                  suffixText: selectedType == DiscountType.percentage ? '%' : ApiConstants.currency,
                ),
              ),
            ],
          ),
          actions: [
            // Remove discount button
            if (widget.orderDiscount > 0)
              TextButton(
                onPressed: () {
                  widget.onOrderDiscount(0.0, type: DiscountType.amount);
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(_tr('إزالة الخصم', 'Remove Discount')),
              ),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_tr('إلغاء', 'Cancel'))),
            ElevatedButton(
              onPressed: () {
                final value = double.tryParse(controller.text) ?? 0.0;
                widget.onOrderDiscount(value, type: selectedType);
                Navigator.pop(context);
              },
              child: Text(_tr('حفظ', 'Save')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onPressed,
    bool showAmount = false,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        minimumSize: const Size(0, 54),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!showAmount) Icon(icon, size: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              if (showAmount) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(widget.totalAmount.toStringAsFixed(0),
                      style: const TextStyle(fontSize: 11)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
