library order_panel;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models.dart';
import '../models/customer.dart';
import '../dialogs/customer_selection_dialog.dart';
import '../services/display_app_service.dart';
import '../services/api/api_constants.dart';
import '../services/language_service.dart';
import '../services/app_themes.dart';
import '../locator.dart';
import '../dialogs/improved_display_connection_dialog.dart';
import 'connectivity_status_indicator.dart';
import '../services/cashier_sound_service.dart';


part 'order_panel_parts/order_panel.helpers.dart';
part 'order_panel_parts/order_panel.cart_display.dart';
part 'order_panel_parts/order_panel.cart_widgets.dart';
part 'order_panel_parts/order_panel.item_actions.dart';
part 'order_panel_parts/order_panel.car_pad.dart';
part 'order_panel_parts/order_panel.footer_and_menu.dart';

class OrderPanel extends StatefulWidget {
  final List<CartItem> cart;
  final double totalAmount;
  final Function(String, double) onUpdateQuantity;
  final Function(String) onRemove;
  final VoidCallback onClear;
  final VoidCallback onPay;
  final VoidCallback onPayLater;
  final Function(String, double, DiscountType) onDiscount;
  final Function(String) onToggleFree;
  final Function(double, {DiscountType type}) onOrderDiscount;
  final VoidCallback onToggleOrderFree;
  final bool isOrderFree;
  final double orderDiscount;
  final TableItem? selectedTable;
  final VoidCallback onCancelTable;
  final Function(String)? onBookingLongPress;
  final Function(CartItem)? onShowItemDetails;

  // Customer selection
  final Customer? selectedCustomer;
  final Function(Customer?) onSelectCustomer;

  // Added Ecosystem fields
  final String selectedOrderType;
  final List<Map<String, dynamic>> typeOptions; // Added real type options
  final Function(String) onOrderTypeChanged;
  final Function(String) onApplyCoupon;
  final VoidCallback onBrowsePromocodes;
  final PromoCode? appliedPromoCode;
  final VoidCallback? onClearPromoCode;
  final TextEditingController orderNotesController;
  final TextEditingController carNumberController;
  final bool requireCustomerSelection;
  final bool cdsEnabled;
  final bool kdsEnabled;
  final double taxRate;

  /// When true, the panel operates in salon mode:
  /// - Order type dropdown is hidden (type is always "services")
  /// - Customer selection is always required
  /// - Cart items display employee name + date/time
  /// - Booking payload uses the salon card format
  final bool isSalonMode;

  const OrderPanel({
    super.key,
    required this.cart,
    required this.totalAmount,
    required this.onUpdateQuantity,
    required this.onRemove,
    required this.onClear,
    required this.onPay,
    required this.onPayLater,
    required this.onDiscount,
    required this.onToggleFree,
    required this.onOrderDiscount,
    required this.onToggleOrderFree,
    required this.isOrderFree,
    required this.orderDiscount,
    this.selectedTable,
    required this.onCancelTable,
    this.onBookingLongPress,
    this.onShowItemDetails,
    this.selectedCustomer,
    required this.onSelectCustomer,
    required this.selectedOrderType,
    required this.typeOptions, // Added
    required this.onOrderTypeChanged,
    required this.onApplyCoupon,
    required this.onBrowsePromocodes,
    this.appliedPromoCode,
    this.onClearPromoCode,
    required this.orderNotesController,
    required this.carNumberController,
    this.requireCustomerSelection = true,
    this.cdsEnabled = true,
    this.kdsEnabled = true,
    this.taxRate = 0.15,
    this.isSalonMode = false,
  });

  @override
  State<OrderPanel> createState() => _OrderPanelState();
}

class _OrderPanelState extends State<OrderPanel> {
  Timer? _longPressTimer;
  String? _pressingCartId;
  final TextEditingController _couponController = TextEditingController();
  late DisplayAppService _displayService;
  ConnectionStatus? _lastConnectionStatus;
  DisplayMode? _lastDisplayMode;
  String? _lastSyncedCartFingerprint;
  bool _carPadArabicLetters = false;
  // PERF: debounce the CDS/KDS cart sync. didUpdateWidget fires for every
  // keystroke and every quantity tap. Without a debounce we re-encode the
  // full cart JSON dozens of times per second; with a ~120ms debounce we
  // coalesce bursts into a single send and the UI stays fluid.
  Timer? _cartSyncDebounce;

  void initState() {
    super.initState();
    _displayService = getIt<DisplayAppService>();
    _lastConnectionStatus = _displayService.status;
    _lastDisplayMode = _displayService.currentMode;
    _displayService.addListener(_onDisplayServiceUpdate);
  }

  @override

  void didUpdateWidget(OrderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cdsEnabled &&
        (_displayService.isConnected || _displayService.isPresentationActive)) {
      _scheduleCartDisplayUpdate();
    }
  }

  void _scheduleCartDisplayUpdate() {
    _cartSyncDebounce?.cancel();
    _cartSyncDebounce =
        Timer(const Duration(milliseconds: 120), _updateCartDisplay);
  }


  void dispose() {
    _longPressTimer?.cancel();
    _cartSyncDebounce?.cancel();
    _couponController.dispose();
    _displayService.removeListener(_onDisplayServiceUpdate);
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final subtotal =
        widget.cart.fold<double>(0.0, (sum, item) => sum + item.totalPrice);
    final tax = subtotal * widget.taxRate.clamp(0.0, 1.0);
    final hasItems = widget.cart.isNotEmpty;
    final displayIntegrationEnabled = widget.cdsEnabled || widget.kdsEnabled;

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: context.appSurface,
        border: Border(left: BorderSide(color: context.appBorder)),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                widget.isSalonMode
                                    ? _tr('الحجز الحالي', 'Current Booking')
                                    : _tr('الطلب الحالي', 'Current Order'),
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: context.appText)),
                            Row(
                              children: [
                                const ConnectivityStatusIndicator(
                                  iconSize: 18,
                                  padding:
                                      EdgeInsets.symmetric(horizontal: 4),
                                ),
                                // Display Connection Button
                                Material(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  child: InkWell(
                                    onTap: displayIntegrationEnabled
                                        ? () => _showDisplayConnectionDialog()
                                        : null,
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            (displayIntegrationEnabled &&
                                                    _displayService.isConnected)
                                                ? LucideIcons.cast
                                                : LucideIcons.monitorOff,
                                            size: 18,
                                            color: (displayIntegrationEnabled &&
                                                    _displayService.isConnected)
                                                ? const Color(0xFF22C55E)
                                                : const Color(0xFF94A3B8),
                                          ),
                                          if (displayIntegrationEnabled &&
                                              _displayService.isConnected) ...[
                                            const SizedBox(width: 4),
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                color: _displayService
                                                            .currentMode ==
                                                        DisplayMode.cds
                                                    ? const Color(0xFFF58220)
                                                    : const Color(0xFFF59E0B),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Order Type Dropdown — hidden in salon mode
                        if (!widget.isSalonMode) _buildOrderTypeSelector(),

                        if (!widget.isSalonMode && _isCarOrderType) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: widget.carNumberController,
                            readOnly: true,
                            enableInteractiveSelection: false,
                            onTap: _openCarNumberPad,
                            decoration: InputDecoration(
                              labelText: _tr('رقم السيارة', 'Car Number'),
                              hintText:
                                  _tr('مثال: ABC-1234', 'Example: ABC-1234'),
                              prefixIcon: const Icon(LucideIcons.car),
                              suffixIcon: const Icon(Icons.dialpad_outlined),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide:
                                    const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 12),

                        // Table/Customer Info
                        _buildCustomerInfo(),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: context.appBorder),

                  // Coupon Section
                  _buildCouponSection(),

                  Divider(height: 1, color: context.appBorder),

                  // Cart Items
                  widget.cart.isEmpty
                      ? _buildEmptyCart()
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: widget.cart.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final item = widget.cart[index];
                            return RepaintBoundary(
                              key: ValueKey(item.cartId),
                              child: _buildCartItem(item),
                            );
                          },
                        ),

                  // Order Notes
                  _buildOrderNotes(),
                ],
              ),
            ),
          ),

          // Footer
          _buildFooter(subtotal, tax, hasItems),
        ],
      ),
    );
  }


}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _SummaryRow({required this.label, required this.value, this.color});
  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? context.appTextMuted;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: resolvedColor, fontSize: 14)),
        Text(value,
            style: TextStyle(
                color: resolvedColor,
                fontSize: 14,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}
