// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../order_panel.dart';

extension OrderPanelCartDisplay on _OrderPanelState {
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
        (_displayService.isConnected || _displayService.isPresentationActive)) {
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

    // Reuse the items already built for the payload, enriched with discount info
    final displayItems = widget.cart.map((item) {
      final basePrice = item.product.price;
      final extrasPrice =
          item.selectedExtras.fold<double>(0.0, (sum, e) => sum + e.price);
      final originalUnitPrice = basePrice + extrasPrice;
      final originalTotal = originalUnitPrice * item.quantity;
      final discType = item.discountType == DiscountType.percentage
          ? 'percentage'
          : 'amount';

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
        'original_unit_price': originalUnitPrice,
        'original_total': originalTotal,
        'final_total': item.totalPrice,
        'discount': item.discount,
        'discount_type': discType,
        'discountType': discType,
        'is_free': item.isFree,
        'isFree': item.isFree,
      };
    }).toList();

    _displayService.updateCartDisplay(
      items: displayItems,
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
}
