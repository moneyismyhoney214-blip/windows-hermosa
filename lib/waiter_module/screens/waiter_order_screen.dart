import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../dialogs/payment_tender_dialog.dart';
import '../../locator.dart';
import '../../models.dart';
import '../../services/api/product_service.dart';
import '../../services/api/api_constants.dart';
import '../../services/app_themes.dart';
import '../../services/language_service.dart';
import '../models/waiter_table_event.dart';
import '../services/waiter_billing_service.dart';
import '../services/waiter_cart_store.dart';
import '../services/waiter_controller.dart';
import '../services/waiter_kitchen_bridge.dart';
import '../services/waiter_order_outbox.dart';
import '../services/waiter_print_dispatcher.dart';
import '../services/waiter_table_registry.dart';
import '../theme/waiter_design.dart';

/// Screen where the waiter assembles the order for a specific table and
/// fires it to the kitchen (KDS + printer) with one button.
class WaiterOrderScreen extends StatefulWidget {
  final TableItem table;
  final WaiterController controller;

  const WaiterOrderScreen({
    super.key,
    required this.table,
    required this.controller,
  });

  @override
  State<WaiterOrderScreen> createState() => _WaiterOrderScreenState();
}

class _WaiterOrderScreenState extends State<WaiterOrderScreen> {
  final ProductService _productService = getIt<ProductService>();
  final WaiterCartStore _cart = getIt<WaiterCartStore>();
  final WaiterTableRegistry _registry = getIt<WaiterTableRegistry>();
  final WaiterKitchenBridge _bridge = getIt<WaiterKitchenBridge>();
  final WaiterOrderOutbox _outbox = getIt<WaiterOrderOutbox>();
  final WaiterBillingService _billing = getIt<WaiterBillingService>();
  // Direct-instantiated rather than pulled from getIt so a hot-reload
  // after adding this service to the locator doesn't crash the screen —
  // setupLocator() only runs on cold start. The dispatcher's own
  // dependencies (PrinterService, PrintOrchestratorService, etc.) are
  // long-registered so its default constructor resolves them fine.
  final WaiterPrintDispatcher _printDispatcher = WaiterPrintDispatcher();

  List<CategoryModel> _categories = const [];
  String? _selectedCategoryId;
  List<Product> _products = const [];
  bool _loadingCategories = true;
  bool _loadingProducts = false;
  bool _sending = false;

  int _guests = 1;
  StreamSubscription<WaiterTableEventEnvelope>? _eventSub;

  @override
  void initState() {
    super.initState();
    _cart.addListener(_onCart);
    // Mark the waiter as "actively composing an order". The home screen
    // uses this to suppress the pickup banner + call sound while the
    // waiter is in the middle of taking an order.
    widget.controller.setActiveOrderingTable(widget.table.id);
    // Listen for table-lifecycle events that originate *elsewhere* (the
    // cashier paying, or another waiter releasing). We react to events
    // that affect this table so the waiter doesn't keep editing a stale
    // order.
    _eventSub = widget.controller.onTableEvent.listen(_onExternalTableEvent);

    // Defensive: if the registry already knows the table was paid (e.g.
    // the cashier collected while this device was offline and we later
    // reconciled), wipe any stale local cart and bail out — keeps the
    // waiter from resending items that were already closed out.
    if (_registry.paidFor(widget.table.id) &&
        _cart.allItemsFor(widget.table.id).isNotEmpty) {
      _cart.clearTable(widget.table.id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(translationService.t('waiter_status_paid'))),
        );
        Navigator.of(context).pop();
      });
      return;
    }

    // Initialize from whatever the waiter previously set; do NOT fall back
    // to table.seats — the backend capacity is not the guest count.
    final existingGuests = _cart.guestsFor(widget.table.id) ??
        _registry.guestCountFor(widget.table.id);
    if (existingGuests != null && existingGuests > 0) _guests = existingGuests;
    _loadCategories();
    _announceAssignment();
    // Hydrate tax config so price displays are tax-inclusive from the
    // first frame (matches the cashier's behaviour). Non-blocking — the
    // UI shows raw prices until the first build after the fetch lands.
    unawaited(_hydrateTaxConfig());
  }

  Future<void> _hydrateTaxConfig() async {
    try {
      await _billing.refreshTaxConfig();
      if (mounted) setState(() {});
    } catch (_) {
      /* non-fatal: fall back to tax-exclusive display */
    }
  }

  /// Tax-inclusive display of a raw (pre-tax) price. Applied everywhere a
  /// meal / addon price is shown in the waiter UI so the waiter sees the
  /// same number the customer will pay, matching the cashier module's
  /// UX. Backend payloads still carry pre-tax `unit_price` — tax is applied
  /// server-side when the invoice is finalised.
  double _displayPrice(double raw) => _billing.applyTax(raw);

  @override
  void dispose() {
    _cart.removeListener(_onCart);
    _eventSub?.cancel();
    // Release the active-order flag so the pickup banner is unblocked.
    // Scoped to this table id — guards against a nav race where screen
    // A's dispose fires after screen B's init.
    widget.controller.clearActiveOrderingTable(widget.table.id);
    super.dispose();
  }

  void _onExternalTableEvent(WaiterTableEventEnvelope env) {
    final event = env.event;
    if (event.tableId != widget.table.id) return;
    // Self-echoes are handled inline by `_runBillFlow` / the card's
    // "تحرير الطاولة" action on the tables grid
    // — responding here would double-pop / stack SnackBars on top of
    // the success sheet. Use the envelope flag instead of comparing
    // ids: the cashier broadcasts events with waiterId=owner (me) even
    // though the *sender* is the cashier, so an id-based filter would
    // incorrectly mask cashier-paid events from the waiter owner.
    if (env.fromSelf) return;

    if (event.kind == TableLifecycleKind.paid ||
        event.kind == TableLifecycleKind.released) {
      _cart.clearTable(widget.table.id);
      if (!mounted) return;
      final label = event.kind == TableLifecycleKind.paid
          ? translationService.t('waiter_bill_done')
          : translationService.t('waiter_release');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(label)),
      );
      Navigator.of(context).pop();
    }
  }

  void _onCart() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await _productService.getCategories();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _selectedCategoryId = cats.isNotEmpty ? cats.first.id : null;
        _loadingCategories = false;
      });
      if (_selectedCategoryId != null) {
        await _loadProducts(_selectedCategoryId!);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCategories = false);
    }
  }

  Future<void> _loadProducts(String categoryId) async {
    setState(() {
      _loadingProducts = true;
      _selectedCategoryId = categoryId;
    });
    try {
      final p = await _productService.getProducts(categoryId: categoryId);
      if (!mounted) return;
      setState(() {
        _products = p.where((x) => x.isActive).toList();
        _loadingProducts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingProducts = false);
    }
  }

  void _announceAssignment() {
    final me = widget.controller.session.self;
    if (me == null) return;
    final existingOwner = _registry.ownerIdFor(widget.table.id);
    if (existingOwner != null && existingOwner != me.id) return;
    // If the table is already in paymentPending (pay-later booked) or
    // paid, re-broadcasting `assigned`/`takingOrder` would clobber that
    // state on every peer. Skip — the state is already where it needs
    // to be; the waiter is here in Edit-Order mode.
    if (_registry.paymentPendingFor(widget.table.id) ||
        _registry.paidFor(widget.table.id)) {
      return;
    }
    // If the waiter already has items on this table (re-opening mid-service),
    // don't demote the cashier UI back to "جاري اخذ الطلب" — emit a regular
    // assigned event so it stays in the occupied state.
    final existingCart = _cart.allItemsFor(widget.table.id);
    final hasExistingItems = existingCart.isNotEmpty;
    widget.controller.broadcastTableEvent(
      TableLifecycleEvent(
        kind: hasExistingItems
            ? TableLifecycleKind.assigned
            : TableLifecycleKind.takingOrder,
        tableId: widget.table.id,
        tableNumber: widget.table.number,
        waiterId: me.id,
        waiterName: me.name,
        guestCount: _guests,
        items: _snapshotItems(),
      ),
    );
  }

  void _broadcastUpdate() {
    final me = widget.controller.session.self;
    if (me == null) return;
    widget.controller.broadcastTableEvent(
      TableLifecycleEvent(
        kind: TableLifecycleKind.updated,
        tableId: widget.table.id,
        tableNumber: widget.table.number,
        waiterId: me.id,
        waiterName: me.name,
        guestCount: _guests,
        itemCount: _cart.itemCountFor(widget.table.id),
        total: _cart.subtotalFor(widget.table.id),
        items: _snapshotItems(),
      ),
    );
  }

  List<TableItemSnapshot> _snapshotItems() {
    final langCode = translationService.currentLanguageCode;
    return _cart
        .allItemsFor(widget.table.id)
        .map((it) => TableItemSnapshot(
              name: it.product.nameForLang(langCode),
              quantity: it.quantity,
              unitPrice: it.product.price,
              note: it.notes.isEmpty ? null : it.notes,
              mealId: it.product.id,
              categoryId: it.product.categoryId,
            ))
        .toList(growable: false);
  }

  void _addProductToCart(Product product) {
    _cart.addItem(
      widget.table.id,
      CartItem(
        cartId: const Uuid().v4(),
        product: product,
        quantity: 1,
      ),
    );
    _cart.setGuests(widget.table.id, _guests);
    _broadcastUpdate();
  }

  /// Broadcasts the draft order to the kitchen (KDS over the mesh /
  /// offline outbox) without touching the backend. Kept as a private
  /// helper so [_payLater] can reuse it.
  ///
  /// When [isEdit] is true, the order id is suffixed with an `edit-{ts}`
  /// segment so the KDS prints a supplemental ticket alongside the
  /// original booking instead of mistaking it for a re-send / duplicate.
  /// The [orderNumber] is tagged `-EDIT` for the same reason, keeping
  /// kitchen staff aware that the items are an addition to an existing
  /// table. This mirrors the cashier's delta-print intent, translated
  /// through the only printing channel the waiter device has access to.
  Future<void> _dispatchToKds({
    required String orderId,
    bool isEdit = false,
  }) async {
    final me = widget.controller.session.self!;
    final items = _cart
        .itemsFor(widget.table.id)
        .map(_cartItemToWire)
        .toList(growable: false);
    if (items.isEmpty) return; // nothing to print
    final ts = DateTime.now().millisecondsSinceEpoch;
    final dispatchOrderId =
        isEdit ? '$orderId-edit-$ts' : orderId;
    final orderNumber = isEdit
        ? 'T${widget.table.number}-EDIT-${ts % 10000}'
        : 'T${widget.table.number}-${orderId.substring(0, 4).toUpperCase()}';
    final total = _cart.subtotalFor(widget.table.id);

    if (_bridge.isConnected) {
      await _bridge.sendNewOrder(
        orderId: dispatchOrderId,
        orderNumber: orderNumber,
        tableNumber: widget.table.number,
        items: items,
        waiter: me,
        total: total,
      );
    } else {
      // Queue — offline flush will push when connectivity returns.
      await _outbox.enqueue(
        orderId: dispatchOrderId,
        orderNumber: orderNumber,
        tableId: widget.table.id,
        tableNumber: widget.table.number,
        waiterId: me.id,
        waiterName: me.name,
        items: items,
        total: total,
        branchId: ApiConstants.branchId.toString(),
      );
    }
  }

  /// Replaces the old "Send to Kitchen" action. Mirrors the cashier's
  /// "دفع لاحقاً" button: creates a real backend booking with
  /// `payment_type=later`, fires the KDS broadcast, locks the table to
  /// pay-later state for peers (so another waiter can't re-claim it and
  /// the cashier sees the pending bill), and pops back to the tables
  /// list. The waiter can later re-enter the table via "Edit Order" to
  /// add/modify items.
  Future<void> _payLater() async {
    if (!_cart.hasItems(widget.table.id)) return;
    if (_sending) return; // single-flight guard
    setState(() => _sending = true);
    final me = widget.controller.session.self!;
    final allItems = _cart.allItemsFor(widget.table.id);
    final subtotal = _cart.subtotalFor(widget.table.id);
    final total = _billing.applyTax(subtotal);
    // If the registry already has a booking id for this table (pay-later
    // submitted earlier, waiter reopened via Edit Order), update that
    // booking in place instead of creating a duplicate.
    final existingBookingId = _registry.bookingIdFor(widget.table.id);
    // Retry-guard: if a previous _payLater attempt created a booking on
    // the backend but dropped the connection before we got the id back,
    // the cart store holds that booking id. Feed it into processBill via
    // existingBookingId so it skips createBooking — otherwise a network
    // retry double-books the table.
    final pendingBookingId = _cart.pendingBookingIdFor(widget.table.id);
    String? bookingId = existingBookingId;
    String? dailyOrderNumber;
    try {
      if (existingBookingId != null) {
        // 1a. Edit-order path — PATCH the existing booking with the
        //     combined cart (sent + draft items).
        await _billing.updateBookingItems(
          bookingId: existingBookingId,
          table: widget.table,
          items: allItems,
          guests: _guests,
        );
        // Edit doesn't regenerate the daily_order_number — the booking
        // already has one from its original creation. Fetch it so the
        // supplemental kitchen ticket carries the original human ref
        // ("#1012-EDIT") instead of the UUID placeholder.
        dailyOrderNumber =
            await _billing.fetchDailyOrderNumber(existingBookingId);
      } else {
        // 1b. First submission — create the pay-later booking via the
        //     same BillingService + OrderService.createBooking path the
        //     cashier uses. `payLater` is derived from pays[0].pay_method
        //     ='pay_later' inside _processBillWithPayload, which skips
        //     NearPay + invoice creation and simply persists the booking.
        final result = await _billing.processBill(
          table: widget.table,
          items: allItems,
          guests: _guests,
          waiterName: me.name,
          pays: [
            {
              'name': 'دفع لاحق',
              'pay_method': 'pay_later',
              'amount': total,
              'index': 0,
            },
          ],
          // On retry, reuse the bookingId from a previous failed attempt
          // so processBill skips createBooking. Mirrors the cashier's
          // _runBillFlow existingBookingId pattern.
          existingBookingId: pendingBookingId,
        );
        if (!mounted) return;
        if (!result.success) {
          // Capture any bookingId the backend DID accept before the
          // failure — e.g. createBooking succeeded but NearPay/invoice
          // declined. The next retry passes it back in via
          // existingBookingId so we don't ghost-book the table.
          final partialBookingId = result.bookingId ?? pendingBookingId;
          if (partialBookingId != null) {
            _cart.setPendingBookingId(widget.table.id, partialBookingId);
          }
          unawaited(WaiterHaptics.warn());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: context.appDanger,
              duration: const Duration(seconds: 6),
              content: Text(
                'تعذّر تأكيد الطلب: ${result.errorMessage ?? ''}',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
          return;
        }
        bookingId = result.bookingId;
        dailyOrderNumber = result.dailyOrderNumber;
        // Success — any retry state is now stale; clear it so a future
        // edit on this table doesn't accidentally reuse the id.
        _cart.clearPendingBookingId(widget.table.id);
      }

      // 2. Fire the KDS broadcast using the backend-assigned booking id.
      //    On edit re-entries the dispatch uses an `-edit-{ts}` suffix
      //    so the kitchen prints a supplemental ticket with only the
      //    new items (drafts) rather than mistaking it for a duplicate
      //    of the original. Matches the cashier's Edit-Order intent of
      //    triggering a "changes" kitchen ticket.
      final broadcastId = bookingId ?? const Uuid().v4();
      final isEdit = existingBookingId != null;
      // Snapshot the draft items BEFORE markDraftAsSent wipes them —
      // the kitchen print needs them to know what to cook, and on an
      // edit we want *only* the new drafts (not the already-sent ones)
      // so the chef doesn't re-cook the original order.
      final kitchenItemsSnapshot =
          List<CartItem>.from(_cart.itemsFor(widget.table.id));
      try {
        await _dispatchToKds(orderId: broadcastId, isEdit: isEdit);
      } catch (e) {
        debugPrint('⚠️ KDS dispatch failed (non-fatal): $e');
      }

      // 2b. Physical kitchen ticket. Same rule as the cashier: pay-later
      //     always prints (the chef needs a paper ticket because KDS is
      //     a screen, not an action). Respects the printKitchenInvoices
      //     toggle in the device behaviour tab.
      try {
        // Prefer the backend-assigned daily_order_number so the ticket
        // carries the same human-facing ref the cashier would print.
        // On edit-order re-entries it came from getBookingDetails; on
        // first submission from the createBooking response. Only fall
        // back to the placeholder if both paths failed.
        final fallback =
            'T${widget.table.number}-${broadcastId.substring(0, broadcastId.length < 4 ? broadcastId.length : 4).toUpperCase()}';
        final base = (dailyOrderNumber != null && dailyOrderNumber.isNotEmpty)
            ? dailyOrderNumber
            : fallback;
        final orderNumber = isEdit ? '$base-EDIT' : base;
        await _printDispatcher.printKitchenTicket(
          bookingId: broadcastId,
          orderNumber: orderNumber,
          items: kitchenItemsSnapshot,
          tableNumber: widget.table.number,
          waiterName: me.name,
          // Pay-later always paper-prints — don't gate on KDS dispatch.
          kdsAlreadyDispatched: false,
        );
      } catch (e) {
        debugPrint('⚠️ Kitchen print failed (non-fatal): $e');
      }

      // 3. Promote the draft so re-entering the order screen (via
      //    "Edit Order") shows the items as sent rather than draft.
      _cart.markDraftAsSent(widget.table.id);

      // 4. Broadcast the lifecycle: paymentPending is the exact state
      //    we want — occupied, non-claimable by other waiters, and
      //    tagged as eligible for Edit Order on the tables card.
      widget.controller.broadcastTableEvent(
        TableLifecycleEvent(
          kind: TableLifecycleKind.paymentPending,
          tableId: widget.table.id,
          tableNumber: widget.table.number,
          waiterId: me.id,
          waiterName: me.name,
          guestCount: _guests,
          total: total,
          itemCount: _cart.itemCountFor(widget.table.id),
          orderId: broadcastId,
          items: _snapshotItems(),
        ),
      );
      unawaited(WaiterHaptics.success());

      // 5. Pop back to the tables list — the waiter's done taking the
      //    order. Their own grid will hide this table (owner-hide rule)
      //    while peers see it as "Order Taken".
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      unawaited(WaiterHaptics.warn());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Map<String, dynamic> _cartItemToWire(CartItem item) {
    final langCode = translationService.currentLanguageCode;
    return {
      'product_id': item.product.id,
      'name': item.product.nameForLang(langCode),
      'quantity': item.quantity,
      'notes': item.notes,
      'price': item.product.price,
      'extras': item.selectedExtras
          .map((e) => {'id': e.id, 'name': e.name, 'price': e.price})
          .toList(),
      'total_price': item.totalPrice,
      'category_id': item.product.categoryId,
    };
  }

  @override
  Widget build(BuildContext context) {
    final items = _cart.itemsFor(widget.table.id);
    return Scaffold(
      backgroundColor: context.appBg,
      appBar: AppBar(
        backgroundColor: context.appHeaderBg,
        foregroundColor: context.appText,
        elevation: 0,
        title: Text(
          '${translationService.t('waiter_table')} ${widget.table.number}',
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: Center(child: _kdsStatusChip(context)),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (_, constraints) {
          final wide = constraints.maxWidth >= 700;
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: _buildPicker(context)),
                Container(width: 1, color: context.appBorder),
                Expanded(flex: 2, child: _buildCart(context, items)),
              ],
            );
          }
          return _buildPicker(context);
        }),
      ),
      floatingActionButton: LayoutBuilder(builder: (_, constraints) {
        final wide = MediaQuery.sizeOf(context).width >= 700;
        if (wide) return const SizedBox.shrink();
        final itemCount = _cart.itemCountFor(widget.table.id);
        return FloatingActionButton.extended(
          backgroundColor: context.appPrimary,
          foregroundColor: Colors.white,
          onPressed: () => _openCartSheet(context),
          icon: Badge(
            isLabelVisible: itemCount > 0,
            label: Text('$itemCount'),
            child: const Icon(LucideIcons.shoppingCart),
          ),
          label: Text(
            '${_displayPrice(_cart.subtotalFor(widget.table.id)).toStringAsFixed(2)} ${ApiConstants.currency}',
          ),
        );
      }),
    );
  }

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

  Widget _sentRow(BuildContext context, CartItem item) {
    return ListTile(
      dense: true,
      leading: Icon(LucideIcons.check,
          size: 16, color: context.appSuccess.withValues(alpha: 0.8)),
      title: Text(
        item.product.name,
        style: TextStyle(color: context.appText),
      ),
      subtitle: Text(
        '${item.quantity.toStringAsFixed(item.quantity == item.quantity.toInt() ? 0 : 1)} × ${_displayPrice(item.product.price).toStringAsFixed(2)}${item.notes.isNotEmpty ? "  •  ${item.notes}" : ""}',
        style: TextStyle(color: context.appTextMuted, fontSize: 11),
      ),
      trailing: Text(
        _displayPrice(item.totalPrice).toStringAsFixed(2),
        style: TextStyle(
          color: context.appTextMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _draftRow(BuildContext context, CartItem item, int i) {
    return ListTile(
      dense: true,
      title: Text(
        item.product.name,
        style: TextStyle(color: context.appText),
      ),
      subtitle: GestureDetector(
        onTap: () => _editItemNotes(i, item),
        child: Text(
          item.notes.isEmpty
              ? '${item.quantity.toStringAsFixed(item.quantity == item.quantity.toInt() ? 0 : 1)} × ${_displayPrice(item.product.price).toStringAsFixed(2)}'
              : '${item.quantity.toStringAsFixed(0)} × ${_displayPrice(item.product.price).toStringAsFixed(2)}  •  ${item.notes}',
          style: TextStyle(
            color:
                item.notes.isEmpty ? context.appTextMuted : context.appPrimary,
            fontSize: 11,
          ),
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
    final result = await showDialog<String>(
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
    // Match the cashier: pull enabled-pay-methods + tax config from the
    // branch settings right before showing the tender dialog.
    await _billing.refreshPayMethods();
    // Ensure the NearPay global flag + SDK bootstrap are in sync with the
    // profile before the tender dialog offers card methods. Same effect
    // as main_screen.session.dart's login-time bootstrap for the cashier.
    unawaited(_billing.hydrateNearPayConfig());
    final me = widget.controller.session.self!;
    final subtotal = _cart.subtotalFor(widget.table.id);
    // The backend computes invoice totals tax-inclusive. If we send only the
    // subtotal here the pays won't match and the backend creates a cancelled
    // draft invoice before the retry. Apply the branch VAT rate up-front.
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

    // If a pay-later booking already exists for this table, invoice THAT
    // booking instead of creating a fresh one. Same pattern as the cashier:
    //   edit_order_dialog PATCHes the booking via updateBookingItems, then
    //   the tables/orders screen creates the invoice against the same
    //   booking_id.
    //
    // Source of existingBookingId, in priority order:
    //   1. registry.bookingIdFor — authoritative after a successful
    //      pay-later broadcast (peers / re-entry populate this).
    //   2. cart.pendingBookingIdFor — captured from a previous attempt
    //      whose response we lost but whose booking DID land on the
    //      backend. Mirrors the retry-guard used in _payLater.
    final existingBookingId =
        _registry.bookingIdFor(widget.table.id) ??
        _cart.pendingBookingIdFor(widget.table.id);

    // If there are new drafts (waiter re-entered via "Edit Order" and added
    // items), PATCH them onto the existing booking first so the invoice
    // includes them. If the booking has no new drafts this is a no-op path.
    if (existingBookingId != null && _cart.hasItems(widget.table.id)) {
      try {
        await _billing.updateBookingItems(
          bookingId: existingBookingId,
          table: widget.table,
          items: allItems,
          guests: _guests,
        );
        // Fire a supplemental kitchen ticket for the newly-added drafts,
        // same as _payLater's edit path.
        try {
          await _dispatchToKds(orderId: existingBookingId, isEdit: true);
        } catch (e) {
          debugPrint('⚠️ KDS dispatch failed (non-fatal): $e');
        }
        _cart.markDraftAsSent(widget.table.id);
      } catch (e) {
        unawaited(WaiterHaptics.warn());
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: context.appDanger,
            content: Text(
              '${translationService.t('waiter_bill_failed')}: $e',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
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
    final me = widget.controller.session.self!;

    // Fire-and-forward: no blocking progress dialog — the bill flow is
    // fast enough on the backend that the old "جاري إنشاء الفاتورة…"
    // spinner was more disruptive than helpful. Callers still get the
    // success sheet / error snackbar once processBill resolves.
    final result = await _billing.processBill(
      table: widget.table,
      items: allItems,
      guests: _guests,
      waiterName: me.name,
      pays: pays,
      existingBookingId: existingBookingId,
    );

    if (!mounted) return;

    if (!result.success) {
      // Don't wipe the cart — keep the waiter's work so they can retry
      // with one tap, or pick a different pay method.
      // Persist the partial bookingId so a later retry (e.g. via the
      // Pay Later button after snackbar dismissal) doesn't double-book.
      final persistedBookingId = result.bookingId ?? existingBookingId;
      if (persistedBookingId != null) {
        _cart.setPendingBookingId(widget.table.id, persistedBookingId);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: context.appDanger,
          duration: const Duration(seconds: 8),
          content: Text(
            '${translationService.t('waiter_bill_failed')}: ${result.errorMessage ?? ''}',
            style: const TextStyle(color: Colors.white),
          ),
          action: SnackBarAction(
            textColor: Colors.white,
            label: translationService.t('waiter_retry'),
            // Preserve any bookingId the backend already accepted so the
            // retry doesn't create a duplicate ghost booking. If the
            // failure happened before createBooking (e.g. NearPay flag
            // off), bookingId is null and we start fresh.
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

    // Success — clear any in-flight bookingId we were retrying against
    // so the next action on this table doesn't try to reuse a now-paid
    // booking id.
    _cart.clearPendingBookingId(widget.table.id);

    // Broadcast paid/open-bill depending on whether it was pay-later.
    final payLater = result.paymentMethod == 'pay_later';

    // Physical prints (cashier receipt + optional kitchen ticket). Fire
    // BEFORE the success sheet so the thermal printer is already humming
    // by the time the waiter sees the summary. Errors are swallowed
    // inside the dispatcher — a down printer shouldn't fail the flow.
    if (!payLater && result.invoiceId != null) {
      // Pay-now: print cashier receipt (mirrors main_screen.payment
      // _autoPrintReceiptCopies). Respects autoPrintCashier +
      // autoPrintCustomerSecondCopy toggles.
      unawaited(
        _printDispatcher.printCashierReceipt(
          invoiceId: result.invoiceId!,
          invoiceNumber: result.invoiceNumber,
          dailyOrderNumber: result.dailyOrderNumber,
          items: allItems,
          totalInclVat: total,
          vatRate: _billing.taxRate,
          tableNumber: widget.table.number,
          waiterName: me.name,
          pays: pays,
        ),
      );
      // Pay-now kitchen ticket: same rule as the cashier — if KDS is
      // enabled and the "allow print with KDS" toggle is off, skip (the
      // kitchen already has the order on-screen). The dispatcher reads
      // both flags and returns early when gated out.
      final bookingIdForKitchen =
          result.bookingId ?? existingBookingId ?? '';
      if (bookingIdForKitchen.isNotEmpty && allItems.isNotEmpty) {
        // Prefer the backend daily_order_number (e.g. "#1023") over the
        // invoice number or the UUID-suffix placeholder, so the kitchen
        // ticket matches the reference on the cashier-side receipt.
        final fallback =
            'T${widget.table.number}-${bookingIdForKitchen.substring(0, bookingIdForKitchen.length < 4 ? bookingIdForKitchen.length : 4).toUpperCase()}';
        final orderNumber = result.dailyOrderNumber?.isNotEmpty == true
            ? result.dailyOrderNumber!
            : (result.invoiceNumber ?? fallback);
        unawaited(
          _printDispatcher.printKitchenTicket(
            bookingId: bookingIdForKitchen,
            orderNumber: orderNumber,
            items: allItems,
            tableNumber: widget.table.number,
            waiterName: me.name,
            invoiceNumber: result.invoiceNumber,
            // Pay-now path: KDS has already seen the order via the mesh
            // broadcast, so feed the flag through and let allowPrintWithKds
            // decide whether to print the paper ticket too.
            kdsAlreadyDispatched: true,
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

    // Show success sheet (invoice summary).
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _BillPreview(
        tableNumber: widget.table.number,
        guests: _guests,
        waiterName: me.name,
        items: allItems,
        total: total,
        invoiceNumber: result.invoiceNumber ?? result.bookingId,
        paid: !payLater,
        displayPrice: _displayPrice,
      ),
    );

    if (!payLater) {
      // Paid-but-still-seated scenario: don't auto-release. Keep the
      // table in the "paid" ownership state so it stays "Unavailable"
      // in the waiters grid + cashier tables screen until the waiter
      // explicitly taps "Release Table" (card 3-dots menu) when the
      // guests actually leave. Clear the local cart so stale items
      // don't resurface if the waiter re-opens the card.
      _cart.clearTable(widget.table.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Widget _kdsStatusChip(BuildContext context) {
    final connected = _bridge.isConnected;
    final color = connected ? context.appSuccess : context.appDanger;
    final label = connected
        ? translationService.t('waiter_kds_connected')
        : translationService.t('waiter_kds_offline');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(connected ? LucideIcons.wifi : LucideIcons.wifiOff,
              size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
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
    // Grid cell size: chunky enough for easy tapping on phones, but
    // denser on tablets so we aren't staring at a 3-product grid on a 10"
    // screen. Aspect also drops slightly as cells grow so the image area
    // stays square-ish.
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
                                  '${_displayPrice(p.price).toStringAsFixed(2)} ${ApiConstants.currency}',
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
                        '${_displayPrice(subtotal - draftSubtotal).toStringAsFixed(2)} ${ApiConstants.currency}',
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
                      '${_displayPrice(subtotal).toStringAsFixed(2)} ${ApiConstants.currency}',
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
                          onPressed: (_sending || items.isEmpty)
                              ? null
                              : _payLater,
                          style: FilledButton.styleFrom(
                            backgroundColor: context.appPrimary,
                            foregroundColor: Colors.white,
                          ),
                          icon: _sending
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
                        onPressed: (sent.isEmpty && items.isEmpty)
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

/// Simple bill preview sheet — displays the full order and copies it to
/// clipboard-style print layout. Real thermal/HTML printing is delegated to
/// the existing cashier-side services once the backend account is ready.
class _BillPreview extends StatelessWidget {
  final String tableNumber;
  final int guests;
  final String waiterName;
  final List<CartItem> items;
  final double total;
  final String? invoiceNumber;
  final bool paid;
  /// Converts a raw (pre-tax) price into the display price shown to the
  /// waiter. Always applied before `toStringAsFixed` so per-line totals
  /// match the footer.
  final double Function(double) displayPrice;

  const _BillPreview({
    required this.tableNumber,
    required this.guests,
    required this.waiterName,
    required this.items,
    required this.total,
    required this.displayPrice,
    this.invoiceNumber,
    this.paid = false,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(LucideIcons.receipt, color: context.appPrimary),
                const SizedBox(width: 8),
                Text(
                  '${translationService.t('waiter_bill_for_table')} $tableNumber',
                  style: TextStyle(
                    color: context.appText,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '$guests ${translationService.t('waiter_guests_short')}',
                  style: TextStyle(color: context.appTextMuted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${translationService.t('waiter_served_by')}: $waiterName',
                    style: TextStyle(color: context.appTextMuted, fontSize: 12),
                  ),
                ),
                if (invoiceNumber != null && invoiceNumber!.isNotEmpty)
                  Text(
                    '#$invoiceNumber',
                    style: TextStyle(
                      color: context.appTextMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            if (paid) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.appSuccess.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.checkCircle,
                        size: 14, color: context.appSuccess),
                    const SizedBox(width: 4),
                    Text(
                      translationService.t('waiter_status_paid'),
                      style: TextStyle(
                        color: context.appSuccess,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Divider(height: 24),
            ConstrainedBox(
              // Let the item list grow with the screen — 320px caps at
              // ~6 rows which overflows the sheet on small phones and
              // wastes space on tablets.
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.45,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: context.appDivider,
                ),
                itemBuilder: (_, i) {
                  final it = items[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Text('${it.quantity.toInt()}×',
                            style: TextStyle(color: context.appTextMuted)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            it.product.name,
                            style: TextStyle(color: context.appText),
                          ),
                        ),
                        Text(
                          displayPrice(it.totalPrice).toStringAsFixed(2),
                          style: TextStyle(
                            color: context.appText,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 24),
            Row(
              children: [
                Text(
                  translationService.t('waiter_total'),
                  style: TextStyle(
                    color: context.appText,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const Spacer(),
                Text(
                  '${total.toStringAsFixed(2)} ${ApiConstants.currency}',
                  style: TextStyle(
                    color: context.appPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: context.appPrimary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(LucideIcons.check),
                label: Text(translationService.t('waiter_close')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
