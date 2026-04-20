// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../order_panel.dart';

extension OrderPanelCartWidgets on _OrderPanelState {
  Widget _buildOrderTypeSelector() {
    if (widget.typeOptions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.appSurfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: Builder(builder: (context) {
          final filteredOptions = widget.typeOptions.where((t) {
            final val = t['value']?.toString().toLowerCase() ?? '';
            return val.startsWith('restaurant_') ||
                val == 'cars' ||
                val == 'car' ||
                val == 'services' ||
                val == 'service';
          }).toList();

          if (filteredOptions.isEmpty) {
            return const SizedBox.shrink();
          }

          final selectedValue = filteredOptions
                  .any((t) => t['value'] == widget.selectedOrderType)
              ? widget.selectedOrderType
              : filteredOptions.first['value'].toString();

          return DropdownButton<String>(
            value: selectedValue,
            isExpanded: true,
            icon: const Icon(LucideIcons.chevronDown, size: 18),
            items: filteredOptions.map((t) {
              return DropdownMenuItem<String>(
                value: t['value'].toString(),
                child: Text(_orderTypeLabel(t),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              );
            }).toList(),
            onChanged: (v) => widget.onOrderTypeChanged(v!),
          );
        }),
      ),
    );
  }

  Widget _buildCustomerInfo() {
    // Table and customer used to share a single chip — selecting a table hid
    // the customer button entirely. Render them as two separate stacked rows
    // so the cashier can still open the customer picker while a table is set.
    return Column(
      children: [
        if (widget.selectedTable != null) ...[
          _buildTableChip(),
          const SizedBox(height: 8),
        ],
        _buildCustomerChip(),
      ],
    );
  }

  Widget _buildTableChip() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.appSurfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.appPrimary),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFFFFF7ED),
            child: Icon(LucideIcons.layout,
                size: 16, color: Color(0xFFC2410C)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _tr(
                'طاولة ${widget.selectedTable!.number}',
                'Table ${widget.selectedTable!.number}',
              ),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFFC2410C),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 16, color: Colors.red),
            onPressed: widget.onCancelTable,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerChip() {
    return InkWell(
      onTap: () async {
        final customer = await showDialog<Customer?>(
          context: context,
          builder: (context) => const CustomerSelectionDialog(),
        );
        widget.onSelectCustomer(customer);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.appSurfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: widget.selectedCustomer != null
                  ? context.appPrimary
                  : context.appBorder),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: widget.selectedCustomer != null
                  ? const Color(0xFFFFF7ED)
                  : const Color(0xFFE2E8F0),
              child: Icon(LucideIcons.user,
                  size: 16,
                  color: widget.selectedCustomer != null
                      ? const Color(0xFFC2410C)
                      : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                  widget.selectedCustomer?.name ??
                      ((widget.isSalonMode ||
                              widget.requireCustomerSelection)
                          ? _tr('يجب اختيار عميل', 'Customer is required')
                          : _tr(
                              'اختيار العميل (اختياري)',
                              'Select Customer (Optional)',
                            )),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: widget.selectedCustomer != null
                          ? const Color(0xFFC2410C)
                          : ((widget.isSalonMode ||
                                  widget.requireCustomerSelection)
                              ? Colors.red
                              : const Color(0xFF64748B))),
                  overflow: TextOverflow.ellipsis),
            ),
            if (widget.selectedCustomer != null)
              IconButton(
                icon: const Icon(LucideIcons.x, size: 16, color: Colors.red),
                onPressed: () => widget.onSelectCustomer(null),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            else
              const Icon(LucideIcons.chevronLeft,
                  size: 16, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  Widget _buildCouponSection() {
    final hasPromo = widget.appliedPromoCode != null;
    final promoCode = widget.appliedPromoCode;
    String displayText;
    if (hasPromo) {
      final discountText = promoCode!.type == DiscountType.percentage
          ? '${promoCode.discount.toStringAsFixed(0)}%'
          : '${promoCode.discount.toStringAsFixed(2)} ${ApiConstants.currency}';
      displayText = '${promoCode.code} ($discountText)';
    } else {
      displayText = _tr('كود الكوبون - اضغط للبحث', 'Coupon Code - Tap to search');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: widget.onBrowsePromocodes,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: hasPromo
                      ? context.appPrimary.withValues(alpha: 0.12)
                      : context.appSurfaceAlt,
                  border: Border.all(
                    color: hasPromo ? context.appPrimary : context.appBorder,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasPromo ? LucideIcons.badgePercent : LucideIcons.ticket,
                      size: 18,
                      color: hasPromo
                          ? context.appPrimary
                          : context.appTextMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        displayText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              hasPromo ? FontWeight.w600 : FontWeight.normal,
                          color: hasPromo
                              ? context.appPrimary
                              : context.appTextMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!hasPromo)
                      Icon(LucideIcons.search,
                          size: 16, color: context.appTextMuted),
                  ],
                ),
              ),
            ),
          ),
          if (hasPromo) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: widget.onClearPromoCode,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(LucideIcons.x, size: 16, color: Colors.red),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyCart() {
    return Container(
      constraints: const BoxConstraints(minHeight: 200),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: context.appSurfaceAlt,
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.wallet,
                size: 32, color: context.appTextSubtle),
          ),
          const SizedBox(height: 16),
          Text(
              widget.isSalonMode
                  ? _tr('لا توجد خدمات', 'No services')
                  : _tr('لا توجد عناصر', 'No items'),
              style: TextStyle(color: context.appTextMuted, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
              widget.isSalonMode
                  ? _tr('ابدأ بإضافة خدمات للحجز',
                      'Start adding services to booking')
                  : _tr('ابدأ بإضافة منتجات للسلة',
                      'Start adding products to cart'),
              style: TextStyle(color: context.appTextSubtle, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildCartItem(CartItem item) {
    // Salon mode: use dedicated layout with employee + date/time
    if (widget.isSalonMode && item.salonData != null) {
      return _buildSalonCartItem(item);
    }

    return GestureDetector(
      onLongPressStart: (_) => _startLongPress(item.cartId),
      onLongPressEnd: (_) => _cancelLongPress(),
      onLongPressCancel: () => _cancelLongPress(),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.01), blurRadius: 4)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item.product.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF1E293B)),
                  ),
                ),
                Text(
                  item.totalPrice.toStringAsFixed(2),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Color(0xFFF58220)),
                ),
              ],
            ),
            if (item.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_tr('ملاحظة', 'Note')}: ${item.notes}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.orange,
                      fontStyle: FontStyle.italic),
                ),
              ),
            if (item.selectedExtras.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _tr('الإضافات', 'Add-ons'),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: () {
                          // Group identical extras by id and count them
                          final grouped = <String, MapEntry<Extra, int>>{};
                          for (final e in item.selectedExtras) {
                            if (grouped.containsKey(e.id)) {
                              grouped[e.id] = MapEntry(e, grouped[e.id]!.value + 1);
                            } else {
                              grouped[e.id] = MapEntry(e, 1);
                            }
                          }
                          return grouped.values.map((entry) {
                            final e = entry.key;
                            final qty = entry.value;
                            final isRemoval = e.price == 0;
                            final label = qty > 1
                                ? (isRemoval ? '- ${e.name} x$qty' : '+ ${e.name} x$qty')
                                : (isRemoval ? '- ${e.name}' : '+ ${e.name}');
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isRemoval
                                    ? Colors.red[50]
                                    : const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isRemoval
                                      ? Colors.red
                                      : const Color(0xFF1D4ED8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList();
                        }(),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildQuantityControls(item)),
                const SizedBox(width: 4),
                _buildItemMenu(item),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Salon-specific cart item layout showing employee name and date/time.
  Widget _buildSalonCartItem(CartItem item) {
    final salon = item.salonData!;
    final employeeName = salon['employee_name']?.toString() ?? '';
    final date = salon['date']?.toString() ?? '';
    final time = salon['time']?.toString() ?? '';
    final dateTimeDisplay =
        (date.isNotEmpty || time.isNotEmpty) ? '$date  $time'.trim() : '';

    return GestureDetector(
      onLongPressStart: (_) => _startLongPress(item.cartId),
      onLongPressEnd: (_) => _cancelLongPress(),
      onLongPressCancel: () => _cancelLongPress(),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.01), blurRadius: 4)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Service name + price
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item.product.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFF1E293B)),
                  ),
                ),
                Text(
                  item.totalPrice.toStringAsFixed(2),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Color(0xFFF58220)),
                ),
              ],
            ),
            // Employee name
            if (employeeName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(LucideIcons.user,
                        size: 13, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        employeeName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            // Date + time
            if (dateTimeDisplay.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    const Icon(LucideIcons.calendar,
                        size: 13, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Text(
                      dateTimeDisplay,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            if (item.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_tr('ملاحظة', 'Note')}: ${item.notes}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.orange,
                      fontStyle: FontStyle.italic),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildQuantityControls(item)),
                const SizedBox(width: 4),
                _buildItemMenu(item),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
