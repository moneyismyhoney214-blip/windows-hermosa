// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../order_panel.dart';

extension OrderPanelItemActions on _OrderPanelState {
  Widget _buildQuantityControls(CartItem item) {
    String formatQty(double qty) {
      if (qty % 1 == 0) return qty.toStringAsFixed(0);
      return qty.toString();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 190;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: item.quantity <= 1
                        ? null
                        : () => widget.onUpdateQuantity(item.cartId, -1),
                    child: Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: Icon(
                        LucideIcons.minus,
                        size: 14,
                        color: item.quantity <= 1
                            ? Colors.grey[300]
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                  Container(
                    width: compact ? 40 : 48,
                    alignment: Alignment.center,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _showQuantityInputDialog(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Text(
                          formatQty(item.quantity),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => widget.onUpdateQuantity(item.cartId, 1),
                    child: Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: Icon(
                        LucideIcons.plus,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onShowItemDetails != null) ...[
              SizedBox(width: compact ? 4 : 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => widget.onShowItemDetails!(item),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!compact)
                        Text(
                          _tr('التفاصيل', 'Details'),
                          style: const TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (!compact) const SizedBox(width: 4),
                      Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF59E0B),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          LucideIcons.plus,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _showQuantityInputDialog(CartItem item) async {
    String formatQty(double qty) {
      if (qty % 1 == 0) return qty.toStringAsFixed(0);
      return qty.toString();
    }

    String appendInput(String current, String next) {
      if (next == '.') {
        if (current.contains('.')) return current;
        if (current.isEmpty) return '0.';
        return '$current.';
      }
      if (current == '0') {
        return next == '0' ? current : next;
      }
      return '$current$next';
    }

    double? parseInput(String input) {
      final normalized = input.trim();
      if (normalized.isEmpty) return null;
      return double.tryParse(normalized);
    }

    final initialValue = formatQty(item.quantity);
    final enteredQuantity = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        var currentValue = initialValue;
        const keys = <String>[
          '7',
          '8',
          '9',
          '4',
          '5',
          '6',
          '1',
          '2',
          '3',
          '.',
          '0',
          '⌫',
        ];

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final parsed = parseInput(currentValue);
            final canSave = parsed != null && parsed > 0;
            final shownValue = currentValue.isEmpty ? '0' : currentValue;

            return AlertDialog(
              title: Text(_tr('تعديل الكمية', 'Edit Quantity')),
              content: SizedBox(
                width: 280,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        shownValue,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: keys.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.6,
                      ),
                      itemBuilder: (_, index) {
                        final key = keys[index];
                        final isBackspace = key == '⌫';
                        final isDot = key == '.';

                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            setDialogState(() {
                              if (isBackspace) {
                                if (currentValue.isNotEmpty) {
                                  currentValue = currentValue.substring(
                                    0,
                                    currentValue.length - 1,
                                  );
                                }
                                return;
                              }
                              currentValue = appendInput(currentValue, key);
                            });
                          },
                          child: Ink(
                            decoration: BoxDecoration(
                              color: isBackspace
                                  ? const Color(0xFFFEF2F2)
                                  : (isDot
                                      ? const Color(0xFFFFF7ED)
                                      : const Color(0xFFF8FAFC)),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Center(
                              child: isBackspace
                                  ? const Icon(Icons.backspace_outlined,
                                      size: 18, color: Color(0xFFDC2626))
                                  : (isDot
                                      ? const Text(
                                          '.',
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFFF58220),
                                          ),
                                        )
                                      : Text(
                                          key,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        )),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(_tr('إلغاء', 'Cancel')),
                ),
                TextButton(
                  onPressed: currentValue.isEmpty
                      ? null
                      : () => setDialogState(() => currentValue = ''),
                  child: Text(_tr('مسح', 'Clear')),
                ),
                ElevatedButton(
                  onPressed: canSave
                      ? () => Navigator.pop(
                            dialogContext,
                            parsed,
                          )
                      : null,
                  child: Text(_tr('حفظ', 'Save')),
                ),
              ],
            );
          },
        );
      },
    );

    if (enteredQuantity == null) return;

    final normalizedQuantity = enteredQuantity;
    final delta = normalizedQuantity - item.quantity;
    if (delta.abs() < 0.0001) return;

    widget.onUpdateQuantity(item.cartId, delta);
  }

  Widget _buildItemMenu(CartItem item) {
    return PopupMenuButton<String>(
      icon: const Icon(LucideIcons.moreVertical,
          size: 16, color: Color(0xFF94A3B8)),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onSelected: (value) {
        if (value == 'delete') {
          widget.onRemove(item.cartId);
        } else if (value == 'discount') {
          _showItemDiscountDialog(item);
        } else if (value == 'free') {
          widget.onToggleFree(item.cartId);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(LucideIcons.trash2, size: 16, color: Colors.red),
              const SizedBox(width: 8),
              Text(_tr('حذف', 'Delete'),
                  style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'discount',
          child: Row(
            children: [
              const Icon(LucideIcons.percent, size: 16, color: Colors.orange),
              const SizedBox(width: 8),
              Text(_tr('خصم', 'Discount')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'free',
          child: Row(
            children: [
              const Icon(LucideIcons.gift, size: 16, color: Colors.green),
              const SizedBox(width: 8),
              Text(_tr('مجاني', 'Free')),
            ],
          ),
        ),
      ],
    );
  }

  void _showItemDiscountDialog(CartItem item) {
    final controller = TextEditingController(
        text: item.discount > 0 ? item.discount.toStringAsFixed(0) : '');
    DiscountType selectedType = item.discountType;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(_tr('إضافة خصم للمنتج', 'Add Item Discount')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ToggleButtons(
                isSelected: [
                  selectedType == DiscountType.amount,
                  selectedType == DiscountType.percentage,
                ],
                onPressed: (index) {
                  setState(() {
                    selectedType = index == 0
                        ? DiscountType.amount
                        : DiscountType.percentage;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                children: [
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(translationService.t('discount_type_amount'))),
                  const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('%')),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: selectedType == DiscountType.amount
                      ? _tr(
                          'قيمة الخصم (${ApiConstants.currency})',
                          'Discount Amount (${ApiConstants.currency})',
                        )
                      : _tr('نسبة الخصم (%)', 'Discount Percentage (%)'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_tr('إلغاء', 'Cancel'))),
            ElevatedButton(
              onPressed: () {
                final discount = double.tryParse(controller.text) ?? 0.0;
                widget.onDiscount(item.cartId, discount, selectedType);
                Navigator.pop(context);
              },
              child: Text(_tr('حفظ', 'Save')),
            ),
          ],
        ),
      ),
    );
  }
}
