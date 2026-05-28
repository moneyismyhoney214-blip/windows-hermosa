// ignore_for_file: invalid_use_of_protected_member
//
// setState is protected on State<T>; extension methods aren't inferred as in-subclass.
part of '../waiter_order_screen.dart';

// Widget-builder + cart-sheet helpers extracted as an extension on _WaiterOrderScreenState.

extension _WaiterOrderScreenBuilders on _WaiterOrderScreenState {
  Widget _sectionHeader(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      color: context.appSurfaceAlt,
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// Renders extras like `+ Cheese   + Extra sauce` under the meal name.
  String? _extrasLine(CartItem item) => item.selectedExtras.isEmpty
      ? null
      : item.selectedExtras.map((e) => '+ ${e.name}').join('   ');

  Widget _sentRow(BuildContext context, CartItem item) {
    final extrasLine = _extrasLine(item);
    return ListTile(
      dense: true,
      isThreeLine: extrasLine != null,
      leading: Icon(LucideIcons.check,
          size: 16, color: context.appSuccess.withValues(alpha: 0.8)),
      title: Text(
        item.product.name,
        style: TextStyle(color: context.appText),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${item.quantity.toStringAsFixed(item.quantity == item.quantity.toInt() ? 0 : 1)} × ${_displayPrice(item.product.price).toStringAsFixed(ApiConstants.digitsNumber)}${item.notes.isNotEmpty ? "  •  ${item.notes}" : ""}',
            style: TextStyle(color: context.appTextMuted, fontSize: 11),
          ),
          if (extrasLine != null)
            Text(
              extrasLine,
              style: TextStyle(color: context.appPrimary, fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: Text(
        _displayPrice(item.totalPrice).toStringAsFixed(ApiConstants.digitsNumber),
        style: TextStyle(
          color: context.appTextMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _draftRow(BuildContext context, CartItem item, int i) {
    final extrasLine = _extrasLine(item);
    return ListTile(
      dense: true,
      isThreeLine: extrasLine != null,
      title: Text(
        item.product.name,
        style: TextStyle(color: context.appText),
      ),
      subtitle: GestureDetector(
        onTap: () => _editItemNotes(i, item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.notes.isEmpty
                  ? '${item.quantity.toStringAsFixed(item.quantity == item.quantity.toInt() ? 0 : 1)} × ${_displayPrice(item.product.price).toStringAsFixed(ApiConstants.digitsNumber)}'
                  : '${item.quantity.toStringAsFixed(0)} × ${_displayPrice(item.product.price).toStringAsFixed(ApiConstants.digitsNumber)}  •  ${item.notes}',
              style: TextStyle(
                color: item.notes.isEmpty
                    ? context.appTextMuted
                    : context.appPrimary,
                fontSize: 11,
              ),
            ),
            if (extrasLine != null)
              Text(
                extrasLine,
                style: TextStyle(color: context.appPrimary, fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            iconSize: 22,
            constraints: const BoxConstraints(
              minWidth: WaiterSizes.minTapTarget,
              minHeight: WaiterSizes.minTapTarget,
            ),
            tooltip: translationService.t('waiter_item_note'),
            onPressed: () => _editItemNotes(i, item),
            icon: Icon(LucideIcons.stickyNote,
                color: item.notes.isEmpty
                    ? context.appTextMuted
                    : context.appPrimary),
          ),
          IconButton(
            iconSize: 22,
            constraints: const BoxConstraints(
              minWidth: WaiterSizes.minTapTarget,
              minHeight: WaiterSizes.minTapTarget,
            ),
            onPressed: () {
              final newQty = item.quantity - 1;
              if (newQty <= 0) {
                _cart.removeItem(widget.table.id, i);
              } else {
                _cart.updateItem(
                  widget.table.id,
                  i,
                  CartItem(
                    cartId: item.cartId,
                    product: item.product,
                    quantity: newQty,
                    selectedExtras: item.selectedExtras,
                    discount: item.discount,
                    discountType: item.discountType,
                    isFree: item.isFree,
                    notes: item.notes,
                  ),
                );
              }
              _broadcastUpdate();
            },
            icon: const Icon(LucideIcons.minus),
          ),
          Text('${item.quantity.toInt()}',
              style: TextStyle(color: context.appText)),
          IconButton(
            iconSize: 22,
            constraints: const BoxConstraints(
              minWidth: WaiterSizes.minTapTarget,
              minHeight: WaiterSizes.minTapTarget,
            ),
            onPressed: () {
              _cart.updateItem(
                widget.table.id,
                i,
                CartItem(
                  cartId: item.cartId,
                  product: item.product,
                  quantity: item.quantity + 1,
                  selectedExtras: item.selectedExtras,
                  discount: item.discount,
                  discountType: item.discountType,
                  isFree: item.isFree,
                  notes: item.notes,
                ),
              );
              _broadcastUpdate();
            },
            icon: const Icon(LucideIcons.plus),
          ),
          IconButton(
            iconSize: 22,
            constraints: const BoxConstraints(
              minWidth: WaiterSizes.minTapTarget,
              minHeight: WaiterSizes.minTapTarget,
            ),
            onPressed: () {
              _cart.removeItem(widget.table.id, i);
              _broadcastUpdate();
            },
            icon: Icon(LucideIcons.trash2, color: context.appDanger),
          ),
        ],
      ),
    );
  }

  Future<void> _editItemNotes(int index, CartItem item) async {
    final ctrl = TextEditingController(text: item.notes);
    String? result;
    try {
      result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.appSurface,
          title: Text(translationService.t('waiter_item_note')),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: translationService.t('waiter_item_note_hint'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(translationService.t('waiter_cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: Text(translationService.t('waiter_save')),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
    if (result == null) return;
    _cart.updateItem(
      widget.table.id,
      index,
      CartItem(
        cartId: item.cartId,
        product: item.product,
        quantity: item.quantity,
        selectedExtras: item.selectedExtras,
        discount: item.discount,
        discountType: item.discountType,
        isFree: item.isFree,
        notes: result,
      ),
    );
    _broadcastUpdate();
  }

  Future<void> _printBill() async {
    if (_abortIfExternallyChanged()) return;
    if (!_canSubmit) return;
    if (!await _ensureCustomerLinked()) return;
    if (!mounted) return;
    // Refresh pay methods + tax config from branch settings before tender dialog.
    await _billing.refreshPayMethods();
    // Sync NearPay flag + SDK bootstrap with profile before card methods are offered.
    unawaited(_billing.hydrateNearPayConfig());
    if (!mounted) return;
    final me = widget.controller.session.self;
    if (me == null) return;
    final subtotal = _cart.subtotalFor(widget.table.id);
    // Apply VAT up-front; backend computes tax-inclusive totals and would otherwise
    // mismatch pays and create a cancelled draft invoice.
    final total = _billing.applyTax(subtotal);
    final allItems = _cart.allItemsFor(widget.table.id);
    if (allItems.isEmpty) return;

    // Announce payment-pending so cashier immediately sees "awaiting payment".
    widget.controller.broadcastTableEvent(TableLifecycleEvent(
      kind: TableLifecycleKind.paymentPending,
      tableId: widget.table.id,
      tableNumber: widget.table.number,
      waiterId: me.id,
      waiterName: me.name,
      guestCount: _guests,
      total: total,
      itemCount: _cart.itemCountFor(widget.table.id),
      items: _snapshotItems(),
    ));

    final selectedPays = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => PaymentTenderDialog(
        total: total,
        enabledMethods: _billing.enabledPaymentMethods(),
        onConfirm: () {},
        onConfirmWithPays: (pays) => Navigator.of(context).pop(pays),
      ),
    );
    if (selectedPays == null || selectedPays.isEmpty) {
      // Waiter backed out — revert to "open bill" state.
      widget.controller.broadcastTableEvent(TableLifecycleEvent(
        kind: TableLifecycleKind.updated,
        tableId: widget.table.id,
        tableNumber: widget.table.number,
        waiterId: me.id,
        waiterName: me.name,
        guestCount: _guests,
        total: total,
        itemCount: _cart.itemCountFor(widget.table.id),
        items: _snapshotItems(),
      ));
      return;
    }

    // Reuse pay-later booking when un-invoiced — once round 1 is paid the booking
    // is locked (1 invoice per booking) so a new round must get a fresh booking.
    // Priority: registry.bookingIdFor (if un-paid) → cart.pendingBookingIdFor (retry).
    final priorRoundInvoiced = _registry.paidFor(widget.table.id);
    final existingBookingId = priorRoundInvoiced
        ? _cart.pendingBookingIdFor(widget.table.id)
        : (_registry.bookingIdFor(widget.table.id) ??
            _cart.pendingBookingIdFor(widget.table.id));

    // PATCH new drafts onto existing booking so the invoice includes them.
    if (existingBookingId != null && _cart.hasItems(widget.table.id)) {
      try {
        await _billing.updateBookingItems(
          bookingId: existingBookingId,
          table: widget.table,
          items: allItems,
          guests: _guests,
        );
        // Supplemental kitchen ticket for newly-added drafts.
        try {
          await _dispatchToKds(
              me: me, orderId: existingBookingId, isEdit: true);
        } catch (e) {
          debugPrint('⚠️ KDS dispatch failed (non-fatal): $e');
        }
        _cart.markDraftAsSent(widget.table.id);
      } catch (e) {
        unawaited(WaiterHaptics.warn());
        if (!mounted) return;
        UiFeedback.info(context, '${translationService.t('waiter_bill_failed')}: $e');
        return;
      }
    }

    await _runBillFlow(
      pays: selectedPays,
      total: total,
      allItems: allItems,
      existingBookingId: existingBookingId,
    );
  }

  Future<void> _runBillFlow({
    required List<Map<String, dynamic>> pays,
    required double total,
    required List<CartItem> allItems,
    String? existingBookingId,
  }) async {
    if (_abortIfExternallyChanged()) return;
    // Single-flight — second tap during in-flight processBill would duplicate booking/invoice.
    if (_sending) return;
    final me = widget.controller.session.self;
    if (me == null) return;
    setState(() => _sending = true);

    // No blocking spinner — backend is fast. Success-path side effects run regardless
    // of mount state so backing out mid-flow doesn't leave the table at "بانتظار الدفع".
    // (See docs/WAITER_MODULE_QA_FINDINGS.md B-1.) Only success sheet/snackbar/pop check mounted.
    final result = await _billing.processBill(
      table: widget.table,
      items: allItems,
      guests: _guests,
      waiterName: me.name,
      pays: pays,
      existingBookingId: existingBookingId,
      customerId: _linkedCustomerId(),
    );

    if (!result.success) {
      // Keep cart for retry; persist partial bookingId so retry doesn't double-book.
      final persistedBookingId = result.bookingId ?? existingBookingId;
      if (persistedBookingId != null) {
        _cart.setPendingBookingId(widget.table.id, persistedBookingId);
      }
      if (mounted) setState(() => _sending = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.appDanger,
          duration: const Duration(seconds: 3),
          content: Text(
            '${translationService.t('waiter_bill_failed')}: ${result.errorMessage ?? ''}',
            style: const TextStyle(color: Colors.white),
          ),
          action: SnackBarAction(
            textColor: Colors.white,
            label: translationService.t('waiter_retry'),
            onPressed: () => _runBillFlow(
              pays: pays,
              total: total,
              allItems: allItems,
              existingBookingId: persistedBookingId,
            ),
          ),
        ),
      );
      return;
    }

    // Success — clear retry bookingId so next action doesn't reuse a now-paid id.
    _cart.clearPendingBookingId(widget.table.id);

    // Settle waitlist party that held this table (stayed `notified` until commit).
    unawaited(_settleWaitlistHoldOnCommit());

    final payLater = result.paymentMethod == 'pay_later';

    // Build canonical receipt data ONCE — preview + print share it (single bilingual fetch).
    final receiptData = await _printDispatcher.buildCashierReceiptData(
      invoiceId: payLater ? null : result.invoiceId,
      invoiceNumber: result.invoiceNumber,
      dailyOrderNumber: result.dailyOrderNumber,
      items: allItems,
      totalInclVat: total,
      vatRate: _billing.taxRate,
      tableNumber: widget.table.number,
      waiterName: me.name,
      pays: pays,
    );

    // Physical prints — fire BEFORE success sheet so printer is humming on display.
    if (!payLater && result.invoiceId != null) {
      // Pay-now uses prebuilt receipt data to avoid refetching the invoice.
      unawaited(_printDispatcher.printPrebuiltCashierReceipt(receiptData));
      final bookingIdForKitchen =
          result.bookingId ?? existingBookingId ?? '';
      if (bookingIdForKitchen.isNotEmpty && allItems.isNotEmpty) {
        // daily_order_number > invoice_number > #bookingId.
        final orderNumber = result.dailyOrderNumber?.isNotEmpty == true
            ? result.dailyOrderNumber!
            : (result.invoiceNumber?.isNotEmpty == true
                ? result.invoiceNumber!
                : '#$bookingIdForKitchen');
        // Pay-now KDS dispatch is inconsistent across paths — always paper-print.
        const kdsHasIt = false;
        unawaited(
          _printDispatcher.printKitchenTicket(
            bookingId: bookingIdForKitchen,
            orderNumber: orderNumber,
            items: allItems,
            tableNumber: widget.table.number,
            waiterName: me.name,
            invoiceNumber: result.invoiceNumber,
            kdsAlreadyDispatched: kdsHasIt,
          ),
        );
      }
    }
    widget.controller.broadcastTableEvent(TableLifecycleEvent(
      kind: payLater
          ? TableLifecycleKind.paymentPending
          : TableLifecycleKind.paid,
      tableId: widget.table.id,
      tableNumber: widget.table.number,
      waiterId: me.id,
      waiterName: me.name,
      guestCount: _guests,
      total: total,
      itemCount: _cart.itemCountFor(widget.table.id),
      items: _snapshotItems(),
      orderId: result.bookingId,
    ));

    if (!mounted) {
      // Pay-now pop mid-flight: clear cart so re-opening doesn't resurface paid items.
      if (!payLater) _cart.clearTable(widget.table.id);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        backgroundColor: context.appSuccess,
        content: Text(
          payLater
              ? translationService.t('waiter_bill_pending')
              : translationService.t('waiter_bill_done'),
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );

    if (!payLater) {
      // Paid-but-seated: keep screen open for next round; clear cart only.
      _cart.clearTable(widget.table.id);
    }
    if (mounted) setState(() => _sending = false);
    if (_externallyChanged && mounted) Navigator.of(context).pop();
  }

  void _openCartSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scroll) => AnimatedBuilder(
          animation: _cart,
          builder: (_, __) => _buildCart(
            context,
            _cart.itemsFor(widget.table.id),
            scrollController: scroll,
          ),
        ),
      ),
    );
  }

  Widget _buildPicker(BuildContext context) {
    if (_loadingCategories) {
      return Center(
        child: CircularProgressIndicator(color: context.appPrimary),
      );
    }
    final bp = context.waiterBreakpoint;
    // Cells stay tappable on phones but denser on tablets.
    final gridExtent = switch (bp) {
      WaiterBreakpoint.compact => 150.0,
      WaiterBreakpoint.medium => 180.0,
      WaiterBreakpoint.expanded => 200.0,
    };
    final chipRowHeight = bp == WaiterBreakpoint.compact ? 52.0 : 58.0;
    return Column(
      children: [
        SizedBox(
          height: chipRowHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final c = _categories[i];
              final selected = c.id == _selectedCategoryId;
              return ChoiceChip(
                label: Text(c.name),
                selected: selected,
                onSelected: (_) => _loadProducts(c.id),
                selectedColor: context.appPrimary.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: selected ? context.appPrimary : context.appText,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: context.appSurfaceAlt,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                  side: BorderSide(
                    color: selected ? context.appPrimary : context.appBorder,
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: _loadingProducts
              ? Center(
                  child: CircularProgressIndicator(color: context.appPrimary),
                )
              : _products.isEmpty
                  ? Center(
                      child: Text(
                        translationService.t('waiter_no_products'),
                        style: TextStyle(color: context.appTextMuted),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: gridExtent,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1,
                      ),
                      itemCount: _products.length,
                      itemBuilder: (_, i) {
                        final p = _products[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _addProductToCart(p),
                          child: Ink(
                            decoration: BoxDecoration(
                              color: context.appCardBg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: context.appBorder),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: context.appSurfaceAlt,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        LucideIcons.utensils,
                                        color: context.appTextMuted,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  p.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.appText,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_displayPrice(p.price).toStringAsFixed(ApiConstants.digitsNumber)} ${ApiConstants.currency}',
                                  style: TextStyle(
                                    color: context.appPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildCart(
    BuildContext context,
    List<CartItem> items, {
    ScrollController? scrollController,
  }) {
    final sent = _cart.sentItemsFor(widget.table.id);
    final subtotal = _cart.subtotalFor(widget.table.id);
    final draftSubtotal = _cart.draftSubtotalFor(widget.table.id);
    return Container(
      color: context.appSurface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Icon(LucideIcons.users,
                    size: 18, color: context.appTextMuted),
                const SizedBox(width: 6),
                Text(
                  translationService.t('waiter_guests'),
                  style: TextStyle(color: context.appTextMuted),
                ),
                const Spacer(),
                IconButton(
                  iconSize: 22,
                  constraints: const BoxConstraints(
                    minWidth: WaiterSizes.minTapTarget,
                    minHeight: WaiterSizes.minTapTarget,
                  ),
                  onPressed: _guests > 1
                      ? () {
                          setState(() => _guests--);
                          _cart.setGuests(widget.table.id, _guests);
                          _broadcastUpdate();
                        }
                      : null,
                  icon: const Icon(LucideIcons.minus),
                ),
                Text('$_guests',
                    style: TextStyle(
                      color: context.appText,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    )),
                IconButton(
                  iconSize: 22,
                  constraints: const BoxConstraints(
                    minWidth: WaiterSizes.minTapTarget,
                    minHeight: WaiterSizes.minTapTarget,
                  ),
                  onPressed: () {
                    setState(() => _guests++);
                    _cart.setGuests(widget.table.id, _guests);
                    _broadcastUpdate();
                  },
                  icon: const Icon(LucideIcons.plus),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: (items.isEmpty && sent.isEmpty)
                ? Center(
                    child: Text(
                      translationService.t('waiter_cart_empty'),
                      style: TextStyle(color: context.appTextMuted),
                    ),
                  )
                : ListView(
                    controller: scrollController,
                    children: [
                      if (sent.isNotEmpty)
                        _sectionHeader(
                          context,
                          translationService.t('waiter_already_sent'),
                          LucideIcons.checkCheck,
                          context.appSuccess,
                        ),
                      for (final sentItem in sent) _sentRow(context, sentItem),
                      if (items.isNotEmpty)
                        _sectionHeader(
                          context,
                          translationService.t('waiter_draft_items'),
                          LucideIcons.pencil,
                          context.appPrimary,
                        ),
                      for (var i = 0; i < items.length; i++)
                        _draftRow(context, items[i], i),
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.appSurfaceAlt,
              border: Border(
                top: BorderSide(color: context.appBorder),
              ),
            ),
            child: Column(
              children: [
                if (sent.isNotEmpty) ...[
                  Row(
                    children: [
                      Text(
                        translationService.t('waiter_sent_total'),
                        style: TextStyle(color: context.appTextMuted, fontSize: 12),
                      ),
                      const Spacer(),
                      Text(
                        '${_displayPrice(subtotal - draftSubtotal).toStringAsFixed(ApiConstants.digitsNumber)} ${ApiConstants.currency}',
                        style: TextStyle(
                          color: context.appTextMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  children: [
                    Text(
                      translationService.t('waiter_subtotal'),
                      style: TextStyle(color: context.appTextMuted),
                    ),
                    const Spacer(),
                    Text(
                      '${_displayPrice(subtotal).toStringAsFixed(ApiConstants.digitsNumber)} ${ApiConstants.currency}',
                      style: TextStyle(
                        color: context.appText,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: (!_canSubmit || items.isEmpty)
                              ? null
                              : _payLater,
                          style: FilledButton.styleFrom(
                            backgroundColor: context.appPrimary,
                            foregroundColor: Colors.white,
                          ),
                          icon: (_sending || _rehydrating)
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(LucideIcons.clock),
                          label: Text(
                            translationService.t('pay_later'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: (!_canSubmit ||
                                (sent.isEmpty && items.isEmpty))
                            ? null
                            : _printBill,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.appPrimary,
                          side: BorderSide(color: context.appPrimary),
                        ),
                        icon: const Icon(LucideIcons.receipt, size: 18),
                        label: Text(translationService.t('waiter_create_invoice')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
