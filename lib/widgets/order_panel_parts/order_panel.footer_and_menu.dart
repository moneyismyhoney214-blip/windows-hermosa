// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast, library_private_types_in_public_api
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
          fillColor: context.appSurfaceAlt,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Future<void> _ensureCustomer(VoidCallback onConfirmed) async {
    // Salon mode forces customer selection regardless of settings.
    final requireCustomer =
        widget.isSalonMode || widget.requireCustomerSelection;

    if (!requireCustomer) {
      onConfirmed();
      return;
    }

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
      Future.delayed(const Duration(milliseconds: 100), onConfirmed);
    } else {
      if (!mounted) return;
      UiFeedback.error(context, translationService.t('please_select_customer_to_continue'));
    }
  }

  Widget _buildFooter(double subtotal, double tax, bool hasItems) {
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
              label: translationService.t('subtotal'),
              value: subtotal.toStringAsFixed(ApiConstants.digitsNumber)),
          if (ApiConstants.isTaxActive) ...[
            const SizedBox(height: 8),
            _SummaryRow(
                label: translationService.t(
                    'tax_pct_n',
                    args: {'pct': ApiConstants.taxPercentage}),
                value: tax.toStringAsFixed(ApiConstants.digitsNumber)),
          ],
          if (widget.orderDiscount > 0) ...[
            const SizedBox(height: 8),
            _SummaryRow(
                label: translationService.t('additional_discount_label'),
                value: '- ${widget.orderDiscount.toStringAsFixed(ApiConstants.digitsNumber)}',
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
                          '${translationService.t('coupon_label_v2')}: ${promo.code}'
                          ' (${promo.type == DiscountType.percentage ? '${promo.discount.toStringAsFixed(0)}%' : '${promo.discount.toStringAsFixed(ApiConstants.digitsNumber)} ${ApiConstants.currency}'})',
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
                  '- ${promoDiscountAmount.toStringAsFixed(ApiConstants.digitsNumber)}',
                  style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF22C55E),
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
          if (widget.isSalonMode && widget.onSelectDeposit != null) ...[
            const SizedBox(height: 8),
            _buildDepositRow(cartSubtotal: subtotal),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Divider(color: context.appBorder),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(translationService.t('total'),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: context.appText)),
              Text(
                  '${widget.totalAmount.toStringAsFixed(ApiConstants.digitsNumber)} ${ApiConstants.currency}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: context.appText)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildMenuButton(),
              const SizedBox(width: 4),
              Expanded(
                flex: 2,
                child: _buildActionButton(
                  label: translationService.t('later_word'),
                  icon: LucideIcons.clock,
                  color: Colors.orange,
                  onPressed: hasItems
                      ? () => _ensureCustomer(widget.onPayLater)
                      : null,
                ),
              ),
              if (widget.onAddBooking != null) ...[
                const SizedBox(width: 4),
                // Add Booking — salon-only; routes to "الحجوزات" tab.
                Expanded(
                  flex: 2,
                  child: _buildActionButton(
                    label: translationService.t('add_booking_btn'),
                    icon: LucideIcons.calendarCheck,
                    color: const Color(0xFF6366F1),
                    onPressed: hasItems
                        ? () => _ensureCustomer(widget.onAddBooking!)
                        : null,
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Expanded(
                flex: 3,
                child: _buildActionButton(
                  label: translationService.t('pay_label'),
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
        if (value == 'sessions') _showSessionsDialog();
      },
      itemBuilder: (context) => [
        PopupMenuItem(
            value: 'clear',
            child: Text(translationService.t('clear_cart_btn'),
                style: const TextStyle(color: Colors.red))),
        PopupMenuItem(
            value: 'discount',
            child: Text(translationService.t('order_discount_label'))),
        PopupMenuItem(
            value: 'free',
            child: Text(widget.isOrderFree
                ? translationService.t('cancel_free')
                : translationService.t('free_order_label'))),
        if (widget.isSalonMode)
          PopupMenuItem(
              value: 'sessions',
              child: Text(translationService.t('change_sessions_btn'))),
      ],
    );
  }

  static int _sessionCountOf(CartItem item) {
    final v = item.salonData?['session_numbers'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  Future<void> _showSessionsDialog() async {
    final salonItems =
        widget.cart.where((c) => c.salonData != null).toList();
    if (salonItems.isEmpty) {
      UiFeedback.info(context, translationService.t('no_salon_services_in_cart'));
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Widget stepBtn(IconData icon, VoidCallback? onTap) => InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: onTap == null
                        ? Colors.grey.withValues(alpha: 0.15)
                        : const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.appBorder),
                  ),
                  child: Icon(icon,
                      size: 16,
                      color: onTap == null
                          ? context.appTextSubtle
                          : const Color(0xFFF58220)),
                ),
              );

          return AlertDialog(
            title: Text(translationService.t('sessions_per_service')),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: salonItems.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (_, i) {
                  final item = salonItems[i];
                  final count = _sessionCountOf(item);
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.product.name,
                          style: TextStyle(
                              fontSize: 14, color: context.appText),
                        ),
                      ),
                      stepBtn(
                        LucideIcons.minus,
                        count > 0
                            ? () => setDialogState(() => item
                                .salonData!['session_numbers'] = count - 1)
                            : null,
                      ),
                      Container(
                        width: 38,
                        alignment: Alignment.center,
                        child: Text('$count',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: context.appText)),
                      ),
                      stepBtn(
                        LucideIcons.plus,
                        () => setDialogState(() =>
                            item.salonData!['session_numbers'] = count + 1),
                      ),
                    ],
                  );
                },
              ),
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
          title: Text(translationService.t('order_discount_label')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                          translationService.t('amount_label'),
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
                          translationService.t('percentage_pct'),
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
                      ? translationService.t('discount_pct')
                      : translationService.t('discount_amount_label'),
                  suffixText: selectedType == DiscountType.percentage ? '%' : ApiConstants.currency,
                ),
              ),
            ],
          ),
          actions: [
            if (widget.orderDiscount > 0)
              TextButton(
                onPressed: () {
                  widget.onOrderDiscount(0.0, type: DiscountType.amount);
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(translationService.t('remove_discount_btn')),
              ),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(translationService.t('cancel'))),
            ElevatedButton(
              onPressed: () {
                final value = double.tryParse(controller.text) ?? 0.0;
                widget.onOrderDiscount(value, type: selectedType);
                Navigator.pop(context);
              },
              child: Text(translationService.t('save')),
            ),
          ],
        ),
      ),
    );
  }

  /// Server rule (from observed 422 response): the deposit's prepaid amount
  /// must not exceed the invoice total. We approximate `invoice total ≈
  /// subtotal` (pre-tax, since deposit.price is also pre-tax) — this is a safe
  /// underestimate that blocks the most common rejection case client-side.
  bool _depositExceedsCart(Map<String, dynamic> deposit, double cartSubtotal) {
    if (cartSubtotal <= 0) return true;
    final price = _parseDepositPrice(deposit['price']);
    return price > cartSubtotal + 0.01;
  }

  Widget _buildDepositRow({required double cartSubtotal}) {
    final deposits = widget.availableDeposits;
    final selectedId = widget.selectedDepositId;
    final selected = selectedId == null
        ? null
        : deposits.firstWhere(
            (d) => _parseDepositIdLocal(d['value']) == selectedId,
            orElse: () => const {},
          );
    final hasSelection = selected != null && selected.isNotEmpty;
    final selectedExceedsCart =
        hasSelection && _depositExceedsCart(selected, cartSubtotal);
    final noDepositsAvailable = deposits.isEmpty;
    final customerSelected = widget.selectedCustomer != null;

    if (!customerSelected) {
      return Row(
        children: [
          Icon(LucideIcons.wallet,
              size: 14, color: context.appTextMuted.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              translationService.t('select_customer_to_view_deposits'),
              style: TextStyle(
                  fontSize: 12,
                  color: context.appTextMuted.withValues(alpha: 0.7)),
            ),
          ),
        ],
      );
    }

    if (noDepositsAvailable && !hasSelection) {
      return Row(
        children: [
          Icon(LucideIcons.wallet, size: 14, color: context.appTextMuted),
          const SizedBox(width: 6),
          Text(
            translationService.t('no_deposits_for_customer'),
            style: TextStyle(fontSize: 12, color: context.appTextMuted),
          ),
        ],
      );
    }

    final depositAmount =
        hasSelection ? _parseDepositPrice(selected['price']) : 0.0;
    final depositLabel = hasSelection
        ? (selected['label']?.toString() ?? '#$selectedId')
        : '';

    final accentColor = selectedExceedsCart
        ? const Color(0xFFEF4444)
        : const Color(0xFF22C55E);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _showDepositPicker(cartSubtotal: cartSubtotal),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        selectedExceedsCart
                            ? LucideIcons.alertTriangle
                            : LucideIcons.wallet,
                        size: 14,
                        color: hasSelection ? accentColor : context.appTextMuted,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          hasSelection
                              ? '${translationService.t('deposit_label')}: $depositLabel'
                              : translationService.t(
                                  'use_deposit_n',
                                  args: {'count': deposits.length},
                                ),
                          style: TextStyle(
                            fontSize: 13,
                            color: hasSelection ? accentColor : context.appText,
                            fontWeight: hasSelection
                                ? FontWeight.w500
                                : FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasSelection) ...[
                  Text(
                    '- ${depositAmount.toStringAsFixed(ApiConstants.digitsNumber)}',
                    style: TextStyle(
                        fontSize: 13,
                        color: accentColor,
                        fontWeight: FontWeight.w600),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    iconSize: 16,
                    icon: const Icon(LucideIcons.x),
                    color: context.appTextMuted,
                    tooltip: translationService.t('remove_deposit_btn'),
                    onPressed: () => widget.onSelectDeposit?.call(null),
                  ),
                ] else
                  Icon(LucideIcons.chevronLeft,
                      size: 16, color: context.appTextMuted),
              ],
            ),
          ),
        ),
        if (selectedExceedsCart)
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 20, left: 20),
            child: Text(
              translationService.t('deposit_exceeds_msg'),
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFFEF4444)),
            ),
          ),
      ],
    );
  }

  Future<void> _showDepositPicker({required double cartSubtotal}) async {
    final deposits = widget.availableDeposits;
    if (deposits.isEmpty) return;
    final selectedId = widget.selectedDepositId;

    await showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                translationService.t('apply_a_deposit_label'),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: context.appText),
              ),
              const SizedBox(height: 4),
              Text(
                translationService.t('deposit_exceeds_invoice_msg'),
                style: TextStyle(
                    fontSize: 11, color: context.appTextMuted),
              ),
              const SizedBox(height: 12),
              for (final d in deposits)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Builder(builder: (_) {
                    final id = _parseDepositIdLocal(d['value']);
                    final isSelected = id != null && id == selectedId;
                    final price = _parseDepositPrice(d['price']);
                    final label = d['label']?.toString() ?? '#$id';
                    final exceedsCart = _depositExceedsCart(d, cartSubtotal);
                    final disabled = id == null || exceedsCart;
                    final baseColor = isSelected
                        ? const Color(0xFF22C55E)
                        : context.appBorder;
                    return Opacity(
                      opacity: disabled && !isSelected ? 0.55 : 1.0,
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: baseColor),
                        ),
                        leading: Icon(
                          exceedsCart
                              ? LucideIcons.alertTriangle
                              : LucideIcons.wallet,
                          color: exceedsCart
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF22C55E),
                        ),
                        title: Text(label),
                        subtitle: Text(
                          exceedsCart
                              ? translationService.t(
                                  'amount_exceeds_invoice_n',
                                  args: {
                                    'amount': price.toStringAsFixed(
                                        ApiConstants.digitsNumber),
                                  },
                                )
                              : '${translationService.t('amount_label')}: ${price.toStringAsFixed(ApiConstants.digitsNumber)} ${ApiConstants.currency}',
                          style: TextStyle(
                            color: exceedsCart
                                ? const Color(0xFFEF4444)
                                : null,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(LucideIcons.check,
                                color: Color(0xFF22C55E))
                            : null,
                        onTap: disabled
                            ? null
                            : () {
                                widget.onSelectDeposit?.call(id);
                                Navigator.pop(ctx);
                              },
                      ),
                    );
                  }),
                ),
              if (selectedId != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    widget.onSelectDeposit?.call(null);
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(LucideIcons.x, size: 16),
                  label: Text(translationService.t('remove_deposit_btn')),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static int? _parseDepositIdLocal(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double _parseDepositPrice(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
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
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      maxLines: 1,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
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
