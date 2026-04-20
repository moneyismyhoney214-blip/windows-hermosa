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
  }

  @override
  void dispose() {
    _cart.removeListener(_onCart);
    _eventSub?.cancel();
    super.dispose();
  }

  void _onExternalTableEvent(WaiterTableEventEnvelope env) {
    final event = env.event;
    if (event.tableId != widget.table.id) return;
    // Self-echoes are handled inline by `_runBillFlow` / `_releaseTable`
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
    widget.controller.broadcastTableEvent(
      TableLifecycleEvent(
        kind: TableLifecycleKind.assigned,
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

  Future<void> _sendToKitchen() async {
    if (!_cart.hasItems(widget.table.id)) return;
    setState(() => _sending = true);
    try {
      final me = widget.controller.session.self!;
      final items = _cart
          .itemsFor(widget.table.id)
          .map(_cartItemToWire)
          .toList(growable: false);
      final orderId = const Uuid().v4();
      final orderNumber = 'T${widget.table.number}-${orderId.substring(0, 4).toUpperCase()}';
      final total = _cart.subtotalFor(widget.table.id);

      if (_bridge.isConnected) {
        await _bridge.sendNewOrder(
          orderId: orderId,
          orderNumber: orderNumber,
          tableNumber: widget.table.number,
          items: items,
          waiter: me,
          total: total,
        );
      } else {
        // Queue — offline flush will push when connectivity returns.
        await _outbox.enqueue(
          orderId: orderId,
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

      // Promote the draft to "sent" so the waiter can keep the table open
      // and add more items later (which will send as an additional order).
      _cart.markDraftAsSent(widget.table.id);

      // Broadcast the lifecycle so cashier viewer updates.
      widget.controller.broadcastTableEvent(
        TableLifecycleEvent(
          kind: TableLifecycleKind.updated,
          tableId: widget.table.id,
          tableNumber: widget.table.number,
          waiterId: me.id,
          waiterName: me.name,
          guestCount: _guests,
          total: _cart.subtotalFor(widget.table.id),
          itemCount: _cart.itemCountFor(widget.table.id),
          orderId: orderId,
          items: _snapshotItems(),
        ),
      );
      unawaited(WaiterHaptics.success());
      if (!mounted) return;
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

  Future<void> _releaseTable() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.appSurface,
        title: Text(translationService.t('waiter_release_table_title')),
        content: Text(translationService.t('waiter_release_table_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(translationService.t('waiter_cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.appDanger),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(translationService.t('waiter_release')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final me = widget.controller.session.self!;
    // Ownership guard: if the registry shows the table was quietly
    // re-assigned to another waiter (e.g. the waiter who took over after
    // a shift change), don't broadcast a RELEASED that would clobber
    // their state. Just pop locally.
    final currentOwner = _registry.ownerIdFor(widget.table.id);
    if (currentOwner != null && currentOwner != me.id) {
      if (!mounted) return;
      Navigator.of(context).pop();
      return;
    }
    widget.controller.broadcastTableEvent(TableLifecycleEvent(
      kind: TableLifecycleKind.released,
      tableId: widget.table.id,
      tableNumber: widget.table.number,
      waiterId: me.id,
      waiterName: me.name,
    ));
    _cart.clearTable(widget.table.id);
    if (!mounted) return;
    Navigator.of(context).pop();
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
            padding: const EdgeInsetsDirectional.only(end: 4),
            child: Center(child: _kdsStatusChip(context)),
          ),
          IconButton(
            tooltip: translationService.t('waiter_release'),
            onPressed: _releaseTable,
            icon: Icon(LucideIcons.logOut, color: context.appDanger),
          ),
        ],
      ),
      body: LayoutBuilder(builder: (_, constraints) {
        final wide = constraints.maxWidth >= 720;
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
      floatingActionButton: LayoutBuilder(builder: (_, constraints) {
        final wide = MediaQuery.sizeOf(context).width >= 720;
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
            '${_cart.subtotalFor(widget.table.id).toStringAsFixed(2)} ${ApiConstants.currency}',
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
        '${item.quantity.toStringAsFixed(item.quantity == item.quantity.toInt() ? 0 : 1)} × ${item.product.price.toStringAsFixed(2)}${item.notes.isNotEmpty ? "  •  ${item.notes}" : ""}',
        style: TextStyle(color: context.appTextMuted, fontSize: 11),
      ),
      trailing: Text(
        item.totalPrice.toStringAsFixed(2),
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
              ? '${item.quantity.toStringAsFixed(item.quantity == item.quantity.toInt() ? 0 : 1)} × ${item.product.price.toStringAsFixed(2)}'
              : '${item.quantity.toStringAsFixed(0)} × ${item.product.price.toStringAsFixed(2)}  •  ${item.notes}',
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

    await _runBillFlow(pays: selectedPays, total: total, allItems: allItems);
  }

  Future<void> _runBillFlow({
    required List<Map<String, dynamic>> pays,
    required double total,
    required List<CartItem> allItems,
    String? existingBookingId,
  }) async {
    final me = widget.controller.session.self!;

    // Show a blocking progress dialog while booking + NearPay run.
    final progress = ValueNotifier<String>(
      translationService.t('waiter_bill_processing'),
    );
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: context.appSurface,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: context.appPrimary),
              const SizedBox(width: 16),
              Flexible(
                child: ValueListenableBuilder<String>(
                  valueListenable: progress,
                  builder: (_, v, __) => Text(
                    v,
                    style: TextStyle(color: context.appText),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final result = await _billing.processBill(
      table: widget.table,
      items: allItems,
      guests: _guests,
      waiterName: me.name,
      pays: pays,
      existingBookingId: existingBookingId,
      onStatus: (s) => progress.value = _humanizeStatus(s),
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss progress

    if (!result.success) {
      // Don't wipe the cart — keep the waiter's work so they can retry
      // with one tap, or pick a different pay method.
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
              existingBookingId: result.bookingId,
            ),
          ),
        ),
      );
      return;
    }

    // Broadcast paid/open-bill depending on whether it was pay-later.
    final payLater = result.paymentMethod == 'pay_later';
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
      ),
    );

    if (!payLater) {
      // Close + clear the table after paid (keep pay-later open for cashier).
      _cart.clearTable(widget.table.id);
      widget.controller.broadcastTableEvent(TableLifecycleEvent(
        kind: TableLifecycleKind.released,
        tableId: widget.table.id,
        tableNumber: widget.table.number,
        waiterId: me.id,
        waiterName: me.name,
      ));
      if (mounted) Navigator.of(context).pop();
    }
  }

  String _humanizeStatus(String raw) {
    switch (raw) {
      case 'creating_booking':
        return translationService.t('waiter_bill_creating');
      case 'preparing_nearpay':
        return translationService.t('waiter_bill_preparing_card');
      case 'charging_card':
        return translationService.t('waiter_bill_charging_card');
      case 'creating_invoice':
        return translationService.t('waiter_bill_creating_invoice');
      case 'updating_pays':
        return translationService.t('waiter_bill_updating_pays');
      case 'printing_receipt':
        return translationService.t('waiter_bill_printing_receipt');
      case 'done':
        return translationService.t('waiter_bill_done');
    }
    return raw;
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
    return Column(
      children: [
        SizedBox(
          height: 54,
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
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 160,
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
                                  '${p.price.toStringAsFixed(2)} ${ApiConstants.currency}',
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
                        '${(subtotal - draftSubtotal).toStringAsFixed(2)} ${ApiConstants.currency}',
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
                      '${subtotal.toStringAsFixed(2)} ${ApiConstants.currency}',
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
                              : _sendToKitchen,
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
                              : const Icon(LucideIcons.send),
                          label: Text(
                            translationService.t('waiter_send_to_kitchen'),
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

  const _BillPreview({
    required this.tableNumber,
    required this.guests,
    required this.waiterName,
    required this.items,
    required this.total,
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
              constraints: const BoxConstraints(maxHeight: 320),
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
                          it.totalPrice.toStringAsFixed(2),
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
