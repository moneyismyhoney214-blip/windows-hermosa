// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast, library_private_types_in_public_api
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
                          translationService.t('details_label'),
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
              title: Text(translationService.t('edit_quantity')),
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
                  child: Text(translationService.t('cancel')),
                ),
                TextButton(
                  onPressed: currentValue.isEmpty
                      ? null
                      : () => setDialogState(() => currentValue = ''),
                  child: Text(translationService.t('clear_btn')),
                ),
                ElevatedButton(
                  onPressed: canSave
                      ? () => Navigator.pop(
                            dialogContext,
                            parsed,
                          )
                      : null,
                  child: Text(translationService.t('save')),
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
    final showSessions = widget.isSalonMode && item.salonData != null;
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
        } else if (value == 'sessions') {
          _showItemSessionsDialog(item);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(LucideIcons.trash2, size: 16, color: Colors.red),
              const SizedBox(width: 8),
              Text(translationService.t('delete'),
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
              Text(translationService.t('discount')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'free',
          child: Row(
            children: [
              const Icon(LucideIcons.gift, size: 16, color: Colors.green),
              const SizedBox(width: 8),
              Text(translationService.t('free_label')),
            ],
          ),
        ),
        if (showSessions)
          PopupMenuItem(
            value: 'sessions',
            child: Row(
              children: [
                const Icon(LucideIcons.repeat,
                    size: 16, color: Color(0xFFF58220)),
                const SizedBox(width: 8),
                Text(translationService.t('sessions_label')),
              ],
            ),
          ),
      ],
    );
  }

  static int _itemSessionCount(CartItem item) {
    final v = item.salonData?['session_numbers'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  Future<void> _showItemSessionsDialog(CartItem item) async {
    if (item.salonData == null) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final count = _itemSessionCount(item);
          Widget stepBtn(IconData icon, VoidCallback? onTap) => InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: onTap == null
                        ? Colors.grey.withValues(alpha: 0.15)
                        : const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.appBorder),
                  ),
                  child: Icon(icon,
                      size: 18,
                      color: onTap == null
                          ? context.appTextSubtle
                          : const Color(0xFFF58220)),
                ),
              );
          return AlertDialog(
            title: Text(translationService.t('sessions_label')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.product.name,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: context.appTextMuted),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    stepBtn(
                      LucideIcons.minus,
                      count > 0
                          ? () => setDialogState(() => item
                              .salonData!['session_numbers'] = count - 1)
                          : null,
                    ),
                    Container(
                      width: 64,
                      alignment: Alignment.center,
                      child: Text('$count',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: context.appText)),
                    ),
                    stepBtn(
                      LucideIcons.plus,
                      () => setDialogState(() =>
                          item.salonData!['session_numbers'] = count + 1),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(translationService.t('done_label')),
              ),
            ],
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  void _showItemDiscountDialog(CartItem item) {
    final controller = TextEditingController(
        text: item.discount > 0 ? item.discount.toStringAsFixed(0) : '');
    DiscountType selectedType = item.discountType;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(translationService.t('add_item_discount')),
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
                      : translationService.t('discount_percentage_pct'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(translationService.t('cancel'))),
            ElevatedButton(
              onPressed: () {
                final discount = double.tryParse(controller.text) ?? 0.0;
                widget.onDiscount(item.cartId, discount, selectedType);
                Navigator.pop(context);
              },
              child: Text(translationService.t('save')),
            ),
          ],
        ),
      ),
    );
  }
}
