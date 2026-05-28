import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../dialogs/booking_details_dialog.dart';
import '../../dialogs/booking_refund_dialog.dart';
import '../../dialogs/customer_selection_dialog.dart';
import '../../dialogs/edit_order_dialog.dart';
import '../../dialogs/payment_tender_dialog.dart';
import '../../dialogs/product_customization_dialog.dart';
import '../../locator.dart';
import '../../models.dart';
import '../../models/booking_invoice.dart';
import '../../models/customer.dart';
import '../../services/api/api_constants.dart';
import '../../services/api/order_service.dart';
import '../../services/api/product_service.dart';
import '../../services/app_themes.dart';
import '../../services/display_app_service.dart';
import '../../services/language_service.dart';
import '../../services/logger_service.dart';
import '../../services/waitlist_service.dart';
import '../../utils/order_status.dart';
import '../../utils/ui_feedback.dart';
import '../models/waiter.dart';
import '../models/waiter_table_event.dart';
import '../services/waiter_billing_service.dart';
import '../services/waiter_cart_store.dart';
import '../services/waiter_controller.dart';
import '../services/waiter_device_prefs.dart';
import '../services/waiter_kitchen_bridge.dart';
import '../services/waiter_order_outbox.dart';
import '../services/waiter_print_dispatcher.dart';
import '../services/waiter_table_customer_store.dart';
import '../services/waiter_table_registry.dart';
import '../theme/waiter_design.dart';

part 'waiter_order_screen_parts/waiter_order_screen.builders.dart';

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
  final WaiterTableCustomerStore _customerStore =
      getIt<WaiterTableCustomerStore>();
  // Shared via getIt so ReceiptBuilderCache survives across screen mounts.
  final WaiterPrintDispatcher _printDispatcher = getIt<WaiterPrintDispatcher>();

  List<CategoryModel> _categories = const [];
  String? _selectedCategoryId;
  List<Product> _products = const [];
  bool _loadingCategories = true;
  bool _loadingProducts = false;
  bool _sending = false;
  /// True while we're rebuilding `_sent` from the backend after an app
  /// restart. Pay-later / pay-now must not fire during this window — the
  /// cart would look empty and a PATCH would wipe the booking.
  bool _rehydrating = false;

  /// True once this screen has broadcast the transient `takingOrder`
  /// lifecycle for this table (i.e. it was opened with an empty cart).
  /// `dispose()` uses this to reliably release the table on exit even if
  /// `session.self` went null or ownership shifted while the screen was
  /// open — otherwise the table stays stuck at "جاري اخذ الطلب" on peers.
  bool _announcedTakingOrder = false;

  /// Flips to true if a *remote* device (cashier or another waiter) edits,
  /// refunds, or cancels this table's booking while this screen is open.
  /// Once set, this screen refuses to commit (pay-later / pay-now) because
  /// our local cart is now a stale view of the booking — a PATCH would
  /// clobber the remote change. We pop the waiter back to the tables grid
  /// (clearing the stale cart) so re-opening re-hydrates from the backend.
  bool _externallyChanged = false;

  int _guests = 1;
  /// When true, this table must be linked to a customer before the
  /// waiter can submit an order (pay-later) or create an invoice. Mirrors
  /// the restaurant's "require customer selection" gate; toggled from the
  /// waiter profile screen.
  bool _requireCustomerSelection = false;
  StreamSubscription<WaiterTableEventEnvelope>? _eventSub;

  @override
  void initState() {
    super.initState();
    _cart.addListener(_onCart);
    _customerStore.addListener(_onCustomerLink);
    unawaited(_customerStore.initialize());
    WaiterDevicePrefs.isRequireCustomerSelectionEnabled().then((v) {
      if (mounted) setState(() => _requireCustomerSelection = v);
    });
    // Suppresses home-screen pickup banner/sound while composing.
    widget.controller.setActiveOrderingTable(widget.table.id);
    // Watch for external mutations to this table's booking.
    _eventSub = widget.controller.onTableEvent.listen(_onExternalTableEvent);

    // Defensive: if registry already knows table was paid, wipe stale cart + bail.
    if (_registry.paidFor(widget.table.id) &&
        _cart.allItemsFor(widget.table.id).isNotEmpty) {
      _cart.clearTable(widget.table.id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        UiFeedback.info(context, translationService.t('waiter_status_paid'));
        Navigator.of(context).pop();
      });
      return;
    }

    // Don't fall back to table.seats — backend capacity != guest count.
    final existingGuests = _cart.guestsFor(widget.table.id) ??
        _registry.guestCountFor(widget.table.id);
    if (existingGuests != null && existingGuests > 0) _guests = existingGuests;
    _loadCategories();
    _announceAssignment();
    // Non-blocking — UI shows raw prices until first build after fetch lands.
    unawaited(_hydrateTaxConfig());
    // Rehydrate sent cart on post-restart entry — registry is persisted but cart isn't,
    // so a Pay Later without this would PATCH with empty cart and wipe the booking.
    // Microtask defer so first setState fires after initState returns.
    Future.microtask(_rehydrateSentFromBackendIfNeeded);
  }

  Future<void> _rehydrateSentFromBackendIfNeeded() async {
    if (!_registry.paymentPendingFor(widget.table.id)) return;
    if (_cart.allItemsFor(widget.table.id).isNotEmpty) return;
    final bookingId = _registry.bookingIdFor(widget.table.id);
    if (bookingId == null || bookingId.isEmpty) return;
    if (mounted) setState(() => _rehydrating = true);
    try {
      final rawDetails =
          await getIt<OrderService>().getBookingDetails(bookingId);
      final inner = (rawDetails['data'] is Map)
          ? Map<String, dynamic>.from(rawDetails['data'] as Map)
          : Map<String, dynamic>.from(rawDetails);
      final items = _extractMealsFromResponse(inner)
          .map(_cartItemFromRawMeal)
          .toList();
      if (items.isEmpty) return;
      _cart.setSentItems(widget.table.id, items);
    } catch (e) {
      debugPrint('⚠️ _rehydrateSentFromBackendIfNeeded failed: $e');
    } finally {
      if (mounted) setState(() => _rehydrating = false);
    }
  }

  List<Map<String, dynamic>> _extractMealsFromResponse(
      Map<String, dynamic> payload) {
    // Flatten `booking` sub-map (same shape handling as tables screen enrichment).
    Map<String, dynamic> flat = payload;
    if (payload['booking'] is Map && payload['id'] == null) {
      final inner = Map<String, dynamic>.from(payload['booking'] as Map);
      for (final e in payload.entries) {
        if (e.key != 'booking') inner.putIfAbsent(e.key, () => e.value);
      }
      flat = inner;
    }
    const keys = [
      'meals',
      'booking_meals',
      'booking_products',
      'booking_items',
      'items',
      'invoice_items',
      'sales_meals',
      'card',
      'cart',
    ];
    for (final key in keys) {
      final raw = flat[key];
      if (raw is! List) continue;
      final rows = raw
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      if (rows.isNotEmpty) return rows;
    }
    return const [];
  }

  CartItem _cartItemFromRawMeal(Map<String, dynamic> row) {
    final mealId = (row['meal_id'] ?? row['id'])?.toString() ?? '';
    final name =
        (row['meal_name'] ?? row['item_name'] ?? row['name'] ?? '').toString();
    double toDouble(Object? v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.trim()) ?? 0.0;
      return 0.0;
    }

    final qty = toDouble(row['quantity']);
    final unitPrice = (row['unit_price'] != null)
        ? toDouble(row['unit_price'])
        : (toDouble(row['price']) / (qty == 0 ? 1 : qty));

    // Harvest translations so rehydrated stub keeps bilingual kitchen/receipt printing.
    final localizedNames = <String, String>{};
    for (final key in const [
      'meal_name_translations',
      'name_translations',
      'translations',
      'localizedNames',
      'localized_names',
      'names',
    ]) {
      final src = row[key];
      if (src is Map) {
        src.forEach((k, v) {
          final code = k.toString().trim().toLowerCase();
          final value = v?.toString().trim() ?? '';
          if (code.isNotEmpty && value.isNotEmpty) {
            localizedNames.putIfAbsent(code, () => value);
          }
        });
      }
    }
    for (final code in const ['ar', 'en', 'es', 'tr', 'hi', 'ur']) {
      final v = (row['name_$code'] ?? row['meal_name_$code'])
          ?.toString()
          .trim();
      if (v != null && v.isNotEmpty) {
        localizedNames.putIfAbsent(code, () => v);
      }
    }
    final nameAr = (row['name_ar'] ??
                row['meal_name_ar'] ??
                row['nameAr'] ??
                localizedNames['ar'] ??
                '')
            .toString();
    final nameEn = (row['name_en'] ??
                row['meal_name_en'] ??
                row['nameEn'] ??
                localizedNames['en'] ??
                '')
            .toString();

    final extras = <Extra>[];
    final addonsRaw = row['addons'] ?? row['extras'];
    if (addonsRaw is List) {
      for (final entry in addonsRaw) {
        if (entry is Map) {
          try {
            extras.add(Extra.fromJson(
                entry.map((k, v) => MapEntry(k.toString(), v))));
          } catch (e) {
            Log.d('WaiterOrderScreen', 'addon Extra.fromJson failed (non-fatal): $e');
          }
        }
      }
    }
    return CartItem(
      cartId: const Uuid().v4(),
      product: Product(
        id: mealId,
        name: name,
        nameAr: nameAr,
        nameEn: nameEn,
        price: unitPrice,
        category: '',
        categoryId: row['category_id']?.toString(),
        localizedNames: localizedNames,
      ),
      quantity: qty == 0 ? 1.0 : qty,
      selectedExtras: extras,
      notes: (row['note'] ?? row['notes'] ?? '').toString(),
    );
  }

  Future<void> _hydrateTaxConfig() async {
    try {
      await _billing.refreshTaxConfig();
      if (mounted) setState(() {});
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
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
    _customerStore.removeListener(_onCustomerLink);
    _eventSub?.cancel();
    // Scoped to this table id — guards a nav race where dispose A fires after init B.
    widget.controller.clearActiveOrderingTable(widget.table.id);
    // Aggressive release on exit: any leftover takingOrder state would strand the
    // table on peers indefinitely if we bail without committing.
    final me = widget.controller.session.self;
    final ownerId = _registry.ownerIdFor(widget.table.id);
    final cartEmpty = _cart.allItemsFor(widget.table.id).isEmpty;
    final notCommitted = !_registry.paymentPendingFor(widget.table.id) &&
        !_registry.paidFor(widget.table.id);
    final claimedBySomeoneElse =
        ownerId != null && me != null && ownerId != me.id;
    final mine = ownerId == null ||
        (me != null && ownerId == me.id) ||
        _announcedTakingOrder ||
        _registry.takingOrderFor(widget.table.id);
    if (cartEmpty && notCommitted && !claimedBySomeoneElse && mine) {
      widget.controller.broadcastTableEvent(TableLifecycleEvent(
        kind: TableLifecycleKind.released,
        tableId: widget.table.id,
        tableNumber: widget.table.number,
        // Fall back to registry if session vanished mid-teardown — ids are advisory for release.
        waiterId: me?.id ?? ownerId ?? '',
        waiterName:
            me?.name ?? _registry.ownerNameFor(widget.table.id) ?? '',
      ));
    }
    super.dispose();
  }

  void _onExternalTableEvent(WaiterTableEventEnvelope env) {
    final event = env.event;
    if (event.tableId != widget.table.id) return;
    // Use envelope.fromSelf, NOT id comparison — cashier broadcasts with waiterId=owner
    // even though sender is the cashier, so id filter would miss cashier-paid events.
    if (env.fromSelf) return;

    if (event.kind == TableLifecycleKind.paid ||
        event.kind == TableLifecycleKind.released) {
      _cart.clearTable(widget.table.id);
      if (!mounted) return;
      final label = event.kind == TableLifecycleKind.paid
          ? translationService.t('waiter_bill_done')
          : translationService.t('waiter_release');
      UiFeedback.info(context, label);
      Navigator.of(context).pop();
      return;
    }

    // Other lifecycle events from another device = cart is stale. Block further commits.
    // If a commit is in flight, raise the flag only; otherwise bail to grid to re-hydrate.
    if (_externallyChanged) return;
    _externallyChanged = true;
    if (_sending) return;
    _cart.clearTable(widget.table.id);
    if (!mounted) return;
    UiFeedback.error(context, translationService.t('waiter_order_changed_elsewhere'));
    Navigator.of(context).pop();
  }

  void _onCart() {
    if (mounted) setState(() {});
  }

  void _onCustomerLink() {
    if (mounted) setState(() {});
  }

  // --- Customer ↔ table binding ---

  /// Customer id pinned to this table — a manual "link customer" wins,
  /// otherwise the waitlist party this table was opened/seated for.
  String? _linkedCustomerId() =>
      _customerStore.linkFor(widget.table.id)?.customerId ??
      waitlistService.customerIdForTable(widget.table.id);

  /// Display name of the pinned customer (manual link → waitlist party),
  /// or null when the table isn't linked to anyone.
  String? _linkedCustomerName() {
    final manual = _customerStore.linkFor(widget.table.id);
    if (manual != null && manual.customerName.isNotEmpty) {
      return manual.customerName;
    }
    return waitlistService.customerNameForTable(widget.table.id);
  }

  bool get _hasLinkedCustomer => _linkedCustomerId() != null;

  /// Settle hold on commit — until then hold stays `notified` so backing out
  /// with empty cart doesn't destroy the queued party. Safe to call repeatedly.
  Future<void> _settleWaitlistHoldOnCommit() async {
    try {
      final held = waitlistService.entryForTable(widget.table.id);
      if (held != null) await waitlistService.markSeated(held.id);
    } catch (e) {
      Log.d('WaiterOrderScreen', 'settle waitlist hold on commit failed (non-fatal): $e');
    }
  }

  /// Open the shared customer picker (search + add-new) and pin whoever
  /// the waiter picks to this table.
  Future<void> _promptLinkCustomer() async {
    final picked = await showDialog<Customer>(
      context: context,
      builder: (_) => const CustomerSelectionDialog(),
    );
    if (picked == null || !mounted) return;
    await _customerStore.bind(
      tableId: widget.table.id,
      customerId: picked.id,
      customerName: picked.name,
    );
    if (mounted) setState(() {});
  }

  /// Gate used by [_payLater] / [_printBill]. When "require customer" is
  /// on and nothing is linked yet, force the picker; returns false (and
  /// shows a snackbar) if the waiter dismisses it without picking anyone.
  Future<bool> _ensureCustomerLinked() async {
    if (!_requireCustomerSelection) return true;
    if (_hasLinkedCustomer) return true;
    await _promptLinkCustomer();
    if (!mounted) return false;
    if (_hasLinkedCustomer) return true;
    UiFeedback.info(context, translationService.t('waiter_customer_required_snack'));
    return false;
  }

  // --- Order actions (⋮) — Details / Edit / Refund / Cancel ---

  Widget _buildOrderActionsMenu(BuildContext context) {
    final bookingId = _registry.bookingIdFor(widget.table.id);
    if (bookingId == null || bookingId.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: translationService.t('options'),
      icon: const Icon(LucideIcons.moreVertical),
      onSelected: (v) async {
        switch (v) {
          case 'details':
            await _orderActionDetails(bookingId);
            break;
          case 'edit':
            await _orderActionEdit(bookingId);
            break;
          case 'refund':
            await _orderActionRefund(bookingId);
            break;
          case 'cancel':
            await _orderActionCancel(bookingId);
            break;
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'details',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(LucideIcons.fileText, size: 16, color: Color(0xFF2563EB)),
            const SizedBox(width: 8),
            Text(translationService.t('waiter_action_order_details')),
          ]),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(LucideIcons.edit3, size: 16, color: Color(0xFF0F766E)),
            const SizedBox(width: 8),
            Text(translationService.t('waiter_action_edit_order')),
          ]),
        ),
        PopupMenuItem(
          value: 'refund',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(LucideIcons.undo2, size: 16, color: Color(0xFFEF4444)),
            const SizedBox(width: 8),
            Text(translationService.t('waiter_action_refund')),
          ]),
        ),
        PopupMenuItem(
          value: 'cancel',
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(LucideIcons.xCircle, size: 16, color: Color(0xFFDC2626)),
            const SizedBox(width: 8),
            Text(translationService.t('waiter_action_cancel_booking')),
          ]),
        ),
      ],
    );
  }

  Future<Map<String, dynamic>?> _fetchOrderDetails(String bookingId) async {
    try {
      return await getIt<OrderService>().getBookingDetails(bookingId);
    } catch (e) {
      if (mounted) {
        UiFeedback.info(context, '${translationService.t('waiter_retry')}: $e');
      }
      return null;
    }
  }

  /// Backend often leaves `customer_name` as default even when linked by id —
  /// prefer the pinned customer for display.
  void _applyLinkedCustomerName(Map<String, dynamic> details) {
    final name = _linkedCustomerName();
    if (name != null && name.trim().isNotEmpty) {
      details['customer_name'] = name.trim();
      details['client_name'] = name.trim();
    }
  }

  Future<void> _orderActionDetails(String bookingId) async {
    final details = await _fetchOrderDetails(bookingId);
    if (details == null || !mounted) return;
    _applyLinkedCustomerName(details);
    await showDialog<void>(
      context: context,
      builder: (_) => BookingDetailsDialog(
        bookingData: details,
        onEditOrder: () => _orderActionEdit(bookingId, prefetched: details),
        onRefund: () => _orderActionRefund(bookingId),
      ),
    );
  }

  Future<void> _orderActionEdit(
    String bookingId, {
    Map<String, dynamic>? prefetched,
  }) async {
    final details = prefetched ?? await _fetchOrderDetails(bookingId);
    if (details == null || !mounted) return;
    _applyLinkedCustomerName(details);
    final data = (details['data'] is Map)
        ? Map<String, dynamic>.from(details['data'] as Map)
        : Map<String, dynamic>.from(details);
    data['id'] ??= int.tryParse(bookingId) ?? bookingId;
    _applyLinkedCustomerName(data);
    final booking = Booking.fromJson(data);
    if (isOrderLockedValue(booking.status) || isOrderLockedValue(data['status'])) {
      UiFeedback.info(context, translationService.t('waiter_edit_locked'));
      return;
    }
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => EditOrderDialog(
        booking: booking,
        bookingData: details,
        taxRate: _billing.taxRate,
        onPrintChanges: (
          changes,
          orderNumber, {
          bool isFullCancel = false,
          String? customerName,
          String? employeeName,
        }) {
          unawaited(_printDispatcher.printKitchenChangeTicket(
            changes: changes,
            orderNumber: orderNumber,
            isFullCancel: isFullCancel,
          ));
        },
      ),
    );
    if (updated == true) await _reconcileBookingFromBackend(bookingId);
  }

  Future<void> _orderActionRefund(String bookingId) async {
    final refunded = await showBookingRefundDialog(
      context: context,
      bookingId: bookingId,
      bookingLabel: translationService.t(
        'waiter_booking_table_label',
        args: {'table': widget.table.number},
      ),
    );
    if (refunded == null) return;
    await _reconcileBookingFromBackend(bookingId);
  }

  Future<void> _orderActionCancel(String bookingId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.appSurface,
        title: Text(
          translationService.t('waiter_action_cancel_booking'),
          style: TextStyle(color: ctx.appText),
        ),
        content: Text(
          translationService.t(
            'waiter_cancel_booking_body',
            args: {'table': widget.table.number},
          ),
          style: TextStyle(color: ctx.appText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(translationService.t('waiter_cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: Text(translationService.t('waiter_confirm_cancel')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await getIt<OrderService>().updateBookingStatus(
        orderId: bookingId,
        status: 8,
      );
      getIt<DisplayAppService>().notifyOrderCancelled(orderId: bookingId);
    } catch (e) {
      if (!mounted) return;
      UiFeedback.error(context, 'فشل إلغاء الحجز: $e');
      return;
    }
    // Kitchen cancel ticket from the items we have locally.
    final cancelItems = _cart.itemsFor(widget.table.id);
    if (cancelItems.isNotEmpty) {
      final changes = cancelItems
          .map((it) => OrderChange(
                type: 'cancel',
                name: it.product.name,
                quantity: it.quantity.round(),
              ))
          .toList();
      unawaited(_printDispatcher.printKitchenChangeTicket(
        changes: changes,
        orderNumber: bookingId,
        isFullCancel: true,
      ));
    }
    final me = widget.controller.session.self;
    widget.controller.broadcastTableEvent(TableLifecycleEvent(
      kind: TableLifecycleKind.released,
      tableId: widget.table.id,
      tableNumber: widget.table.number,
      waiterId: me?.id ?? _registry.ownerIdFor(widget.table.id) ?? '',
      waiterName: me?.name ?? _registry.ownerNameFor(widget.table.id) ?? '',
    ));
    _cart.clearTable(widget.table.id);
    if (!mounted) return;
    UiFeedback.success(context, 'تم إلغاء حجز الطاولة ${widget.table.number}');
    Navigator.of(context).pop();
  }

  /// After an edit/refund from this screen, re-pull the authoritative
  /// state: rebuild the sent cart, and either release the table (booking
  /// gone) or re-broadcast the fresh snapshot to peers.
  Future<void> _reconcileBookingFromBackend(String bookingId) async {
    try {
      final after = await getIt<OrderService>().getBookingDetails(bookingId);
      if (after['status']?.toString().trim() == '500') return;
      final inner = (after['data'] is Map)
          ? Map<String, dynamic>.from(after['data'] as Map)
          : Map<String, dynamic>.from(after);
      inner['id'] ??= int.tryParse(bookingId) ?? bookingId;
      final refreshed = Booking.fromJson(inner);
      final statusStr = refreshed.status.toString().toLowerCase();
      final rawMeals = _extractMealsFromResponse(inner);
      final cancelled = statusStr == '8' ||
          statusStr == 'cancelled' ||
          statusStr == 'canceled' ||
          statusStr.contains('cancel');
      _cart.clearTable(widget.table.id);
      if (cancelled) {
        final me = widget.controller.session.self;
        widget.controller.broadcastTableEvent(TableLifecycleEvent(
          kind: TableLifecycleKind.released,
          tableId: widget.table.id,
          tableNumber: widget.table.number,
          waiterId: me?.id ?? _registry.ownerIdFor(widget.table.id) ?? '',
          waiterName: me?.name ?? _registry.ownerNameFor(widget.table.id) ?? '',
        ));
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (rawMeals.isEmpty) return;
      _cart.setSentItems(
        widget.table.id,
        rawMeals.map(_cartItemFromRawMeal).toList(),
      );
      _broadcastUpdate();
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
    }
  }

  Widget _buildCustomerAction(BuildContext context) {
    final name = _linkedCustomerName();
    if (name == null || name.isEmpty) {
      return TextButton.icon(
        onPressed: _promptLinkCustomer,
        icon: const Icon(LucideIcons.userPlus, size: 16),
        label: Text(translationService.t('waiter_link_customer')),
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _promptLinkCustomer,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: context.appPrimary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.user, size: 14, color: context.appPrimary),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.appPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(LucideIcons.pencil, size: 12, color: context.appPrimary),
            ],
          ),
        ),
      ),
    );
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
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
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
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
      if (!mounted) return;
      setState(() => _loadingProducts = false);
    }
  }

  void _announceAssignment() {
    final me = widget.controller.session.self;
    if (me == null) return;
    final existingOwner = _registry.ownerIdFor(widget.table.id);
    if (existingOwner != null && existingOwner != me.id) return;
    // Skip if already paymentPending/paid — re-broadcasting would clobber peer state.
    if (_registry.paymentPendingFor(widget.table.id) ||
        _registry.paidFor(widget.table.id)) {
      return;
    }
    // Re-opening mid-service emits `assigned`, not `takingOrder`, to avoid demoting.
    final existingCart = _cart.allItemsFor(widget.table.id);
    final hasExistingItems = existingCart.isNotEmpty;
    if (!hasExistingItems) {
      // Record so dispose() reliably releases regardless of ownership shifts.
      _announcedTakingOrder = true;
    }
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

  /// Mirrors cashier's _onProductTap: open customization dialog when product
  /// has extras (declared or via meal-has-addons), else add direct.
  Future<void> _addProductToCart(Product product) async {
    if (product.extras.isNotEmpty) {
      _openCustomizationDialog(product);
      return;
    }
    bool hasAddons = false;
    try {
      hasAddons = await _productService.mealHasAddons(product.id);
    } catch (e) {
      Log.d('catch', 'non-fatal: $e');
      // Network failure — fall back to direct add so a blip doesn't block order taking.
    }
    if (!mounted) return;
    if (hasAddons) {
      _openCustomizationDialog(product);
    } else {
      _addProductDirect(product, const <Extra>[], 1.0, '');
    }
  }

  void _openCustomizationDialog(Product product) {
    showDialog<void>(
      context: context,
      builder: (_) => ProductCustomizationDialog(
        product: product,
        taxRate: _billing.taxRate,
        onConfirm: _addProductDirect,
      ),
    );
  }

  void _addProductDirect(
    Product product,
    List<Extra> extras,
    double quantity,
    String notes,
  ) {
    _cart.addItem(
      widget.table.id,
      CartItem(
        cartId: const Uuid().v4(),
        product: product,
        quantity: quantity,
        selectedExtras: extras,
        notes: notes,
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
    required Waiter me,
    required String orderId,
    bool isEdit = false,
  }) async {
    final items = _cart
        .itemsFor(widget.table.id)
        .map(_cartItemToWire)
        .toList(growable: false);
    if (items.isEmpty) return;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final dispatchOrderId =
        isEdit ? '$orderId-edit-$ts' : orderId;
    final orderNumber = isEdit
        ? 'T${widget.table.number}-EDIT-${ts % 10000}'
        : 'T${widget.table.number}-${orderId.substring(0, 4).toUpperCase()}';
    final total = _cart.subtotalFor(widget.table.id);

    // "Socket connected" ≠ "order delivered" — wait for ACK or fall through
    // to the offline outbox so a frozen KDS doesn't silently drop the order.
    if (_bridge.isConnected) {
      try {
        await _bridge.sendNewOrder(
          orderId: dispatchOrderId,
          orderNumber: orderNumber,
          tableNumber: widget.table.number,
          items: items,
          waiter: me,
          total: total,
        );
        if (await _bridge.awaitOrderAck(dispatchOrderId)) return;
        debugPrint(
            '⚠️ KDS did not ACK $dispatchOrderId — queuing for offline flush');
      } catch (e) {
        debugPrint('⚠️ KDS send failed ($e) — queuing for offline flush');
      }
    }
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

  /// Replaces the old "Send to Kitchen" action. Mirrors the cashier's
  /// "دفع لاحقاً" button: creates a real backend booking with
  /// `payment_type=later`, fires the KDS broadcast, locks the table to
  /// pay-later state for peers (so another waiter can't re-claim it and
  /// the cashier sees the pending bill), and pops back to the tables
  /// list. The waiter can later re-enter the table via "Edit Order" to
  /// add/modify items.
  /// Surfaced on the UI so the Pay Later / Create Invoice buttons
  /// stay disabled while we're rebuilding `_sent` from the backend.
  /// Without this gate, a fast waiter could tap Pay Later during the
  /// post-restart rehydrate and PATCH the booking with an empty item
  /// list — silently deleting everything on the server.
  bool get _canSubmit => !_sending && !_rehydrating && !_externallyChanged;

  /// Hard block: this table's booking was changed on another device, so
  /// our cart is stale and a commit would clobber it. Bounce to the
  /// tables grid (the cart was already cleared when the flag flipped, or
  /// we clear it here on the retry path) so re-opening re-hydrates.
  bool _abortIfExternallyChanged() {
    if (!_externallyChanged) return false;
    _cart.clearTable(widget.table.id);
    if (mounted) {
      UiFeedback.error(context, translationService.t('waiter_order_changed_elsewhere'));
      Navigator.of(context).pop();
    }
    return true;
  }

  Future<void> _payLater() async {
    if (_abortIfExternallyChanged()) return;
    if (!_cart.hasItems(widget.table.id)) return;
    if (!_canSubmit) return;
    // Raise single-flight flag BEFORE any await — second tap during customer-link
    // dialog could otherwise slip past _canSubmit and trigger duplicate createBooking.
    setState(() => _sending = true);
    if (!await _ensureCustomerLinked()) {
      if (mounted) setState(() => _sending = false);
      return;
    }
    final me = widget.controller.session.self;
    if (me == null) {
      setState(() => _sending = false);
      return;
    }
    final allItems = _cart.allItemsFor(widget.table.id);
    final subtotal = _cart.subtotalFor(widget.table.id);
    final total = _billing.applyTax(subtotal);
    // A booking carries at most ONE invoice — when `paid`, treat bookingId as gone
    // and start fresh, so a second-round PATCH doesn't orphan new items.
    final priorRoundInvoiced = _registry.paidFor(widget.table.id);
    final existingBookingId =
        priorRoundInvoiced ? null : _registry.bookingIdFor(widget.table.id);
    // Retry-guard for crashed-mid-create: pendingBookingId lets processBill skip
    // createBooking and prevents double-booking on network retry.
    final pendingBookingId = _cart.pendingBookingIdFor(widget.table.id);
    String? bookingId = existingBookingId;
    String? dailyOrderNumber;
    try {
      if (existingBookingId != null) {
        // 1a. Edit-order — PATCH existing booking with combined cart.
        await _billing.updateBookingItems(
          bookingId: existingBookingId,
          table: widget.table,
          items: allItems,
          guests: _guests,
        );
        // Fetch daily_order_number so supplemental kitchen ticket has original ref.
        dailyOrderNumber =
            await _billing.fetchDailyOrderNumber(existingBookingId);
      } else {
        // 1b. First submission — pay-later via BillingService.processBill.
        final result = await _billing.processBill(
          table: widget.table,
          items: allItems,
          guests: _guests,
          waiterName: me.name,
          customerId: _linkedCustomerId(),
          pays: [
            {
              'name': 'دفع لاحق',
              'pay_method': 'pay_later',
              'amount': total,
              'index': 0,
            },
          ],
          // Retry reuses pendingBookingId so processBill skips createBooking.
          existingBookingId: pendingBookingId,
        );
        if (!result.success) {
          // Capture partial bookingId for retry so we don't ghost-book the table.
          final partialBookingId = result.bookingId ?? pendingBookingId;
          if (partialBookingId != null) {
            _cart.setPendingBookingId(widget.table.id, partialBookingId);
          }
          unawaited(WaiterHaptics.warn());
          if (mounted) {
            UiFeedback.info(context, 'تعذّر تأكيد الطلب: ${result.errorMessage ?? ''}');
          }
          return;
        }
        bookingId = result.bookingId;
        dailyOrderNumber = result.dailyOrderNumber;
        // Clear retry state so a future edit doesn't accidentally reuse the id.
        _cart.clearPendingBookingId(widget.table.id);
      }

      // Booking persisted — remaining steps run regardless of mount state so the
      // kitchen ticket, draft promotion, and lifecycle broadcast can't be lost.
      // Only the snackbar + pop below are gated on `mounted`.
      // (See docs/WAITER_MODULE_QA_FINDINGS.md B-1.)
      final broadcastId = bookingId ?? const Uuid().v4();
      final isEdit = existingBookingId != null;
      final kitchenItemsSnapshot =
          List<CartItem>.from(_cart.itemsFor(widget.table.id));
      unawaited(() async {
        try {
          await _dispatchToKds(me: me, orderId: broadcastId, isEdit: isEdit);
        } catch (e) {
          debugPrint('⚠️ KDS dispatch failed (non-fatal): $e');
        }
      }());

      // 2b. Physical kitchen ticket — pay-later always prints (paper > KDS for prep).
      unawaited(() async {
        try {
          final base = (dailyOrderNumber != null && dailyOrderNumber.isNotEmpty)
              ? dailyOrderNumber
              : (bookingId != null && bookingId.isNotEmpty
                  ? '#$bookingId'
                  : '#$broadcastId');
          final orderNumber = isEdit ? '$base-EDIT' : base;
          await _printDispatcher.printKitchenTicket(
            bookingId: broadcastId,
            orderNumber: orderNumber,
            items: kitchenItemsSnapshot,
            tableNumber: widget.table.number,
            waiterName: me.name,
            kdsAlreadyDispatched: false,
          );
        } catch (e) {
          debugPrint('⚠️ Kitchen print failed (non-fatal): $e');
        }
      }());

      // 3. Promote draft to sent so re-entry shows items as sent.
      _cart.markDraftAsSent(widget.table.id);
      // Force flush — a crash in the 300ms debounce window would re-dispatch on relaunch.
      await _cart.flushNow();

      // 3b. Settle waitlist party that was holding this table.
      unawaited(_settleWaitlistHoldOnCommit());

      // 4. paymentPending = occupied + non-claimable + Edit Order eligible.
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

      // 5. Stay on screen for further service.
      if (mounted) {
        UiFeedback.info(context, translationService.t('waiter_bill_pending'));
      }
      // Bail if remote edit/refund landed mid-commit so waiter isn't stuck with disabled buttons.
      if (_externallyChanged && mounted) Navigator.of(context).pop();
    } catch (e) {
      unawaited(WaiterHaptics.warn());
      if (mounted) {
        UiFeedback.info(context, e.toString());
      }
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
        actions: [_buildCustomerAction(context), _buildOrderActionsMenu(context)],
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
            '${_displayPrice(_cart.subtotalFor(widget.table.id)).toStringAsFixed(ApiConstants.digitsNumber)} ${ApiConstants.currency}',
          ),
        );
      }),
    );
  }
}
