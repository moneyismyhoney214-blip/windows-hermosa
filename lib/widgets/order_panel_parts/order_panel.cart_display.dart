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

    final cashierLang =
        ApiConstants.acceptLanguage.trim().toLowerCase().isEmpty
            ? 'ar'
            : ApiConstants.acceptLanguage.trim().toLowerCase();
    Map<String, String> mergedNames(CartItem item) {
      final merged = <String, String>{
        ...item.product.localizedNames,
        ...ProductService.cachedNamesFor(item.product.id),
      };
      merged.putIfAbsent(cashierLang, () => item.product.name);
      if (item.product.nameAr.isNotEmpty) {
        merged.putIfAbsent('ar', () => item.product.nameAr);
      }
      if (item.product.nameEn.isNotEmpty) {
        merged.putIfAbsent('en', () => item.product.nameEn);
      }
      return merged;
    }

    List<Map<String, dynamic>> extrasPayload(CartItem item) {
      return item.selectedExtras.map((e) {
        final extraMerged = <String, String>{
          ...e.optionTranslations,
          ...ProductService.cachedOptionNamesFor(e.id),
        };
        extraMerged.putIfAbsent(cashierLang, () => e.name);
        return <String, dynamic>{
          'id': e.id,
          'name': e.name,
          'name_lang': cashierLang,
          'nameEn': extraMerged['en'] ?? e.name,
          'nameAr': extraMerged['ar'] ?? '',
          'localizedNames': extraMerged,
          'price': e.price,
        };
      }).toList();
    }

    final payload = {
      'items': widget.cart.map((item) {
                final merged = mergedNames(item);
                return {
                  'cartId': item.cartId,
                  'productId': item.product.id,
                  'name': item.product.name,
                  'name_lang': cashierLang,
                  'nameEn': merged['en'] ?? '',
                  'nameAr': merged['ar'] ?? '',
                  'localizedNames': merged,
                  'quantity': item.quantity,
                  'price': item.product.price,
                  'extras': extrasPayload(item),
                  'totalPrice': item.totalPrice,
                  'notes': item.notes,
                };
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
      final merged = mergedNames(item);

      return {
        'cartId': item.cartId,
        'productId': item.product.id,
        'name': item.product.name,
        'name_lang': cashierLang,
        'nameEn': merged['en'] ?? '',
        'nameAr': merged['ar'] ?? '',
        'localizedNames': merged,
        'quantity': item.quantity,
        'price': item.product.price,
        'extras': extrasPayload(item),
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
      invoicePrimaryLang: printerLanguageSettings.primary,
      invoiceSecondaryLang: printerLanguageSettings.secondary,
      invoiceAllowSecondary: printerLanguageSettings.allowSecondary,
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
    if (!mounted) return;

    if (!widget.cdsEnabled && !widget.kdsEnabled) {
      _showDisplayStatusSnack(
        _tr('CDS و KDS متوقفان من الإعدادات',
            'CDS and KDS are disabled from settings'),
        Colors.orange,
      );
      return;
    }

    if (_displayService.isConnected) {
      final ip = _displayService.connectedIp ?? '';
      _showDisplayStatusSnack(
        _tr('متصل بشاشة العرض${ip.isNotEmpty ? ' ($ip)' : ''}',
            'Connected to display${ip.isNotEmpty ? ' ($ip)' : ''}'),
        const Color(0xFF22C55E),
      );
      return;
    }

    if (_displayService.isConnecting || _displayService.isReconnecting) {
      _showDisplayStatusSnack(
        _tr('جاري الاتصال بشاشة العرض...', 'Connecting to display...'),
        Colors.blue,
      );
      return;
    }

    final savedIp = _displayService.connectedIp?.trim() ?? '';
    if (savedIp.isEmpty) {
      _showDisplayStatusSnack(
        _tr('لم يتم إعداد شاشة العرض. قم بالإعداد من الإعدادات',
            'No display configured. Configure it from Settings'),
        Colors.orange,
      );
      return;
    }

    var mode = _displayService.currentMode;
    if (mode == DisplayMode.none) {
      mode = widget.cdsEnabled ? DisplayMode.cds : DisplayMode.kds;
    }

    _showDisplayStatusSnack(
      _tr('جاري إعادة الاتصال بـ $savedIp', 'Reconnecting to $savedIp'),
      Colors.blue,
    );

    unawaited(() async {
      try {
        await _displayService.connectWithMode(
          savedIp,
          port: _displayService.connectedPort,
          mode: mode,
        );
      } catch (_) {
        if (!mounted) return;
        _showDisplayStatusSnack(
          _tr('تعذر الاتصال بشاشة العرض',
              'Failed to connect to display'),
          Colors.red,
        );
      }
    }());
  }

  void _showDisplayStatusSnack(String message, Color color) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
