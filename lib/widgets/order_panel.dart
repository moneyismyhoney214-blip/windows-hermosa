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
import '../locator.dart';
import '../dialogs/improved_display_connection_dialog.dart';
import '../services/cashier_sound_service.dart';

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
  final Function(double) onOrderDiscount;
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

  bool get _useArabicUi {
    final code = translationService.currentLanguageCode.trim().toLowerCase();
    return code.startsWith('ar') || code.startsWith('ur');
  }

  String _tr(String ar, String en) {
    return _useArabicUi ? ar : en;
  }

  String _canonicalOrderTypeValue(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'pickup':
      case 'takeaway':
      case 'take_away':
      case 'restaurant_takeaway':
      case 'restaurant_take_away':
      case 'restaurant_pickup':
        return 'restaurant_pickup';
      case 'dine_in':
      case 'dinein':
      case 'internal':
      case 'inside':
      case 'table':
      case 'restaurant_table':
      case 'restaurant_internal':
        return 'restaurant_internal';
      case 'delivery':
      case 'home_delivery':
      case 'restaurant_home_delivery':
      case 'restaurant_delivery':
        return 'restaurant_delivery';
      case 'parking':
      case 'restaurant_parking':
      case 'drive_through':
      case 'drive-through':
      case 'cars':
      case 'car':
        return 'cars';
      case 'service':
      case 'services':
      case 'restaurant_services':
        return 'services';
      default:
        return normalized;
    }
  }

  String _orderTypeLabel(Map<String, dynamic> option) {
    final fallback = option['label']?.toString() ?? '';
    switch (_canonicalOrderTypeValue(option['value']?.toString() ?? '')) {
      case 'restaurant_pickup':
        return _tr('سفري', 'Pickup');
      case 'restaurant_internal':
        return _tr('داخل المطعم', 'Dine In');
      case 'restaurant_delivery':
        return _tr('توصيل', 'Delivery');
      case 'cars':
        return _tr('سيارة', 'Car');
      case 'services':
        return _tr('محلي', 'Local');
      default:
        return fallback;
    }
  }

  bool get _isCarOrderType {
    final selected = _canonicalOrderTypeValue(widget.selectedOrderType);
    if (selected == 'cars') {
      return true;
    }

    final matched = widget.typeOptions.cast<Map<String, dynamic>?>().firstWhere(
          (t) => t?['value']?.toString() == widget.selectedOrderType,
          orElse: () => null,
        );
    final label = matched?['label']?.toString().toLowerCase() ?? '';
    return label.contains('سيار') || label.contains('car');
  }

  @override
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
    // Update display when cart changes and connected in CDS mode
    if (widget.cdsEnabled &&
        _displayService.isConnected &&
        _displayService.currentMode == DisplayMode.cds) {
      _updateCartDisplay();
    }
  }

  void _onDisplayServiceUpdate() {
    final currentStatus = _displayService.status;
    final currentMode = _displayService.currentMode;
    final statusChanged = currentStatus != _lastConnectionStatus;
    final modeChanged = currentMode != _lastDisplayMode;
    _lastConnectionStatus = currentStatus;
    _lastDisplayMode = currentMode;

    // Avoid cart echo loop on CART_UPDATED acknowledgements.
    if ((statusChanged || modeChanged) &&
        widget.cdsEnabled &&
        _displayService.isConnected &&
        _displayService.currentMode == DisplayMode.cds) {
      _updateCartDisplay(force: true);
    }

    if (mounted && (statusChanged || modeChanged)) {
      setState(() {});
    }
  }

  void _updateCartDisplay({bool force = false}) {
    if (!widget.cdsEnabled) return;
    if (!_displayService.isConnected && !_displayService.isPresentationActive) return;

    final subtotal =
        widget.cart.fold<double>(0.0, (sum, item) => sum + item.totalPrice);
    final tax = subtotal * widget.taxRate.clamp(0.0, 1.0);
    final beforeDiscountTotal = subtotal + tax;
    final orderDiscountAmount = widget.isOrderFree
        ? beforeDiscountTotal
        : widget.orderDiscount.clamp(0.0, beforeDiscountTotal).toDouble();
    final afterDiscountTotal = widget.isOrderFree
        ? 0.0
        : (beforeDiscountTotal - orderDiscountAmount).clamp(
            0.0,
            double.infinity,
          );

    final payload = {
      'items': widget.cart
          .map((item) => {
                'cartId': item.cartId,
                'productId': item.product.id,
                'name': item.product.name,
                'quantity': item.quantity,
                'price': item.product.price,
                'extras': item.selectedExtras
                    .map((e) => {
                          'id': e.id,
                          'name': e.name,
                          'price': e.price,
                        })
                    .toList(),
                'totalPrice': item.totalPrice,
                'notes': item.notes,
              })
          .toList(),
      'subtotal': subtotal,
      'tax': tax,
      'total': afterDiscountTotal,
      'original_total': beforeDiscountTotal,
      'discount_amount': orderDiscountAmount,
      'discounted_total': afterDiscountTotal,
      'is_order_free': widget.isOrderFree,
      'isOrderFree': widget.isOrderFree,
      'orderNumber': '',
    };

    final fingerprint = jsonEncode(payload);
    if (!force && fingerprint == _lastSyncedCartFingerprint) {
      return;
    }
    _lastSyncedCartFingerprint = fingerprint;

    _displayService.updateCartDisplay(
      items: widget.cart.map((item) {
        final basePrice = item.product.price;
        final extrasPrice =
            item.selectedExtras.fold<double>(0.0, (sum, e) => sum + e.price);
        final originalUnitPrice = basePrice + extrasPrice;
        final originalTotal = originalUnitPrice * item.quantity;

        return {
          'cartId': item.cartId,
          'productId': item.product.id,
          'name': item.product.name,
          'quantity': item.quantity,
          'price': item.product.price,
          'extras': item.selectedExtras
              .map((e) => {
                    'id': e.id,
                    'name': e.name,
                    'price': e.price,
                  })
              .toList(),
          'totalPrice': item.totalPrice,
          'notes': item.notes,
          // ✅ Discount info for CDS
          'original_unit_price': originalUnitPrice,
          'original_total': originalTotal,
          'final_total': item.totalPrice,
          'discount': item.discount,
          'discount_type': item.discountType == DiscountType.percentage
              ? 'percentage'
              : 'amount',
          'discountType': item.discountType == DiscountType.percentage
              ? 'percentage'
              : 'amount',
          'is_free': item.isFree,
          'isFree': item.isFree,
        };
      }).toList(),
      subtotal: subtotal,
      tax: tax,
      taxRate: widget.taxRate,
      hasTax: widget.taxRate > 0,
      total: afterDiscountTotal,
      discountAmount: orderDiscountAmount,
      originalTotal: beforeDiscountTotal,
      discountedTotal: afterDiscountTotal,
      isOrderFree: widget.isOrderFree,
      orderNumber: '',
    );
  }

  void _startLongPress(String cartId) {
    _pressingCartId = cartId;
    _longPressTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _pressingCartId == cartId) {
        if (widget.onBookingLongPress != null) {
          widget.onBookingLongPress!(cartId);
        }
      }
    });
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _pressingCartId = null;
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _couponController.dispose();
    _displayService.removeListener(_onDisplayServiceUpdate);
    super.dispose();
  }

  void _showDisplayConnectionDialog() {
    if (!widget.cdsEnabled && !widget.kdsEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('CDS و KDS متوقفان من الإعدادات',
              'CDS and KDS are disabled from settings')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => ImprovedDisplayConnectionDialog(
        onConnect: (ip, port, mode) async {
          final targetMode =
              mode.toLowerCase() == 'cds' ? DisplayMode.cds : DisplayMode.kds;
          if (targetMode == DisplayMode.cds && !widget.cdsEnabled) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _tr('CDS غير مفعّل من الإعدادات',
                      'CDS is disabled from settings'),
                ),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }
          if (targetMode == DisplayMode.kds && !widget.kdsEnabled) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _tr('KDS غير مفعّل من الإعدادات',
                      'KDS is disabled from settings'),
                ),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }
          await _displayService.connectWithMode(
            ip,
            port: port,
            mode: targetMode,
          );
        },
        onDisconnect: () => _displayService.disconnect(),
        isConnected: _displayService.isConnected,
        currentIp: _displayService.connectedIp,
      ),
    );
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
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(left: BorderSide(color: Color(0xFFE2E8F0))),
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
                            Text(_tr('الطلب الحالي', 'Current Order'),
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B))),
                            Row(
                              children: [
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

                        // Order Type Dropdown
                        _buildOrderTypeSelector(),

                        if (_isCarOrderType) ...[
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
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),

                  // Coupon Section
                  _buildCouponSection(),

                  const Divider(height: 1, color: Color(0xFFF1F5F9)),

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
                            return _buildCartItem(item);
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

  Widget _buildOrderTypeSelector() {
    if (widget.typeOptions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: widget.typeOptions
                  .any((t) => t['value'] == widget.selectedOrderType)
              ? widget.selectedOrderType
              : widget.typeOptions.first['value'].toString(),
          isExpanded: true,
          icon: const Icon(LucideIcons.chevronDown, size: 18),
          items: widget.typeOptions.where((t) {
            final val = t['value']?.toString().toLowerCase() ?? '';
            // Strict enforcement: only show restaurant-related types.
            // This prevents salon types (walk-in, appointment) from being selectable.
            return val.startsWith('restaurant_') ||
                val == 'cars' ||
                val == 'car' ||
                val == 'services' ||
                val == 'service';
          }).map((t) {
            return DropdownMenuItem<String>(
              value: t['value'].toString(),
              child: Text(_orderTypeLabel(t),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            );
          }).toList(),
          onChanged: (v) => widget.onOrderTypeChanged(v!),
        ),
      ),
    );
  }

  Widget _buildCustomerInfo() {
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
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: widget.selectedCustomer != null
                  ? const Color(0xFFF58220)
                  : const Color(0xFFF1F5F9)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: widget.selectedTable != null ||
                      widget.selectedCustomer != null
                  ? const Color(0xFFFFF7ED)
                  : const Color(0xFFE2E8F0),
              child: Icon(
                  widget.selectedTable != null
                      ? LucideIcons.layout
                      : LucideIcons.user,
                  size: 16,
                  color: widget.selectedTable != null ||
                          widget.selectedCustomer != null
                      ? const Color(0xFFC2410C)
                      : const Color(0xFF64748B)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                  widget.selectedTable != null
                      ? _tr(
                          'طاولة ${widget.selectedTable!.number}',
                          'Table ${widget.selectedTable!.number}',
                        )
                      : widget.selectedCustomer?.name ??
                          (widget.requireCustomerSelection
                              ? _tr('يجب اختيار عميل', 'Customer is required')
                              : _tr(
                                  'اختيار العميل (اختياري)',
                                  'Select Customer (Optional)',
                                )),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: widget.selectedTable != null ||
                              widget.selectedCustomer != null
                          ? const Color(0xFFC2410C)
                          : (widget.requireCustomerSelection
                              ? Colors.red
                              : const Color(0xFF64748B))),
                  overflow: TextOverflow.ellipsis),
            ),
            if (widget.selectedTable != null)
              IconButton(
                icon: const Icon(LucideIcons.x, size: 16, color: Colors.red),
                onPressed: widget.onCancelTable,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            else if (widget.selectedCustomer != null)
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
                      ? const Color(0xFFFFF7ED)
                      : Colors.white,
                  border: Border.all(
                    color: hasPromo
                        ? const Color(0xFFF58220)
                        : const Color(0xFFCBD5E1),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasPromo ? LucideIcons.badgePercent : LucideIcons.ticket,
                      size: 18,
                      color: hasPromo
                          ? const Color(0xFFF58220)
                          : const Color(0xFF94A3B8),
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
                              ? const Color(0xFFC2410C)
                              : const Color(0xFF94A3B8),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!hasPromo)
                      const Icon(LucideIcons.search,
                          size: 16, color: Color(0xFF94A3B8)),
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
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(LucideIcons.wallet,
                size: 32, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 16),
          Text(_tr('لا توجد عناصر', 'No items'),
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 16)),
          const SizedBox(height: 4),
          Text(_tr('ابدأ بإضافة منتجات للسلة', 'Start adding products to cart'),
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildCartItem(CartItem item) {
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

  Widget _buildQuantityControls(CartItem item) {
    String formatQty(double qty) {
      return qty.toStringAsFixed(0);
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
                children: const [
                  Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Amount')),
                  Padding(
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

  Future<void> _openCarNumberPad() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        var value = widget.carNumberController.text.trim();
        var useArabic = _carPadArabicLetters;

        const englishLetters = <String>[
          'A',
          'B',
          'C',
          'D',
          'E',
          'F',
          'G',
          'H',
          'I',
          'J',
          'K',
          'L',
          'M',
          'N',
          'O',
          'P',
          'Q',
          'R',
          'S',
          'T',
          'U',
          'V',
          'W',
          'X',
          'Y',
          'Z',
        ];
        const arabicLetters = <String>[
          'ا',
          'ب',
          'ت',
          'ث',
          'ج',
          'ح',
          'خ',
          'د',
          'ر',
          'س',
          'ص',
          'ط',
          'ع',
          'ف',
          'ق',
          'ك',
          'ل',
          'م',
          'ن',
          'ه',
          'و',
          'ي',
        ];
        const digits = <String>['1', '2', '3', '4', '5', '6', '7', '8', '9'];

        return StatefulBuilder(
          builder: (context, setModalState) {
            void append(String token) {
              if (value.length >= 18) return;
              setModalState(() => value = '$value$token');
            }

            void removeLast() {
              if (value.isEmpty) return;
              setModalState(() => value = value.substring(0, value.length - 1));
            }

            Widget buildKey(
              String label, {
              VoidCallback? onTap,
              Color? color,
              Color? textColor,
              IconData? icon,
            }) {
              return InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color ?? const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: icon != null
                      ? Icon(icon, size: 18, color: textColor ?? Colors.black87)
                      : Text(
                          label,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: textColor ?? Colors.black87,
                          ),
                        ),
                ),
              );
            }

            final letterSet = useArabic ? arabicLetters : englishLetters;
            final size = MediaQuery.of(context).size;
            final isTablet = size.shortestSide >= 600;

            Widget buildHeader() {
              return Row(
                children: [
                  Expanded(
                    child: Text(
                      _tr('رقم السيارة', 'Car Number'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(_tr('إغلاق', 'Close')),
                  ),
                ],
              );
            }

            Widget buildValueBox() {
              return Container(
                height: 52,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.car, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        value.isEmpty
                            ? _tr('ادخل رقم السيارة', 'Enter car number')
                            : value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: value.isEmpty
                              ? const Color(0xFF94A3B8)
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget buildActionsRow() {
              return Row(
                children: [
                  Expanded(
                    child: buildKey(
                      useArabic ? 'AR' : 'EN',
                      onTap: () => setModalState(() {
                        useArabic = !useArabic;
                        _carPadArabicLetters = useArabic;
                      }),
                      color: const Color(0xFFE2E8F0),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: buildKey('-', onTap: () => append('-')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: buildKey(
                      '',
                      icon: Icons.backspace_outlined,
                      onTap: removeLast,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: buildKey(
                      _tr('مسح', 'Clear'),
                      onTap: () => setModalState(() => value = ''),
                      color: const Color(0xFFFEE2E2),
                      textColor: const Color(0xFFB91C1C),
                    ),
                  ),
                ],
              );
            }

            Widget buildDigitsGrid() {
              return GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.8,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  ...digits.map((d) => buildKey(d, onTap: () => append(d))),
                  buildKey('0', onTap: () => append('0')),
                  buildKey(
                    _tr('تم', 'Done'),
                    onTap: () => Navigator.pop(context, value),
                    color: const Color(0xFF10B981),
                    textColor: Colors.white,
                  ),
                  buildKey(
                    _tr('حفظ', 'Save'),
                    onTap: () => Navigator.pop(context, value),
                    color: const Color(0xFFF58220),
                    textColor: Colors.white,
                  ),
                ],
              );
            }

            Widget buildLetters() {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: letterSet
                    .map(
                      (letter) => SizedBox(
                        width: 48,
                        child: buildKey(letter, onTap: () => append(letter)),
                      ),
                    )
                    .toList(growable: false),
              );
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: isTablet
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            buildHeader(),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      buildValueBox(),
                                      const SizedBox(height: 12),
                                      buildActionsRow(),
                                      const SizedBox(height: 10),
                                      buildDigitsGrid(),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 4,
                                  child: buildLetters(),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            buildHeader(),
                            const SizedBox(height: 8),
                            buildValueBox(),
                            const SizedBox(height: 12),
                            buildActionsRow(),
                            const SizedBox(height: 10),
                            buildDigitsGrid(),
                            const SizedBox(height: 10),
                            buildLetters(),
                          ],
                        ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      widget.carNumberController.text = result.trim();
      setState(() {});
    }
  }

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
    if (!widget.requireCustomerSelection) {
      onConfirmed();
      return;
    }

    // Enforce explicit customer selection only when setting is enabled.
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
      color: const Color(0xFFF8FAFC),
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12.0),
            child: Divider(color: Color(0xFFE2E8F0)),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_tr('الإجمالي', 'Total'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Color(0xFF1E293B))),
              Text(
                  '${widget.totalAmount.toStringAsFixed(2)} ${ApiConstants.currency}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Color(0xFF1E293B))),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Icon(LucideIcons.moreVertical,
            color: Color(0xFF94A3B8), size: 20),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_tr('خصم على الطلب', 'Order Discount')),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration:
              InputDecoration(labelText: _tr('قيمة الخصم', 'Discount Value')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_tr('إلغاء', 'Cancel'))),
          ElevatedButton(
            onPressed: () {
              widget.onOrderDiscount(double.tryParse(controller.text) ?? 0.0);
              Navigator.pop(context);
            },
            child: Text(_tr('حفظ', 'Save')),
          ),
        ],
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

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _SummaryRow({required this.label, required this.value, this.color});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: color ?? const Color(0xFF64748B), fontSize: 14)),
        Text(value,
            style: TextStyle(
                color: color ?? const Color(0xFF64748B),
                fontSize: 14,
                fontWeight: FontWeight.bold)),
      ],
    );
  }
}
