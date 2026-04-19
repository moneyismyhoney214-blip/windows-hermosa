// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../main_screen.dart';

extension MainScreenCart on _MainScreenState {
  bool _isCarOrderType([String? type]) {
    final selected =
        _normalizeOrderTypeValue(type ?? _selectedOrderType).toLowerCase();
    if (selected == 'cars' ||
        selected == 'car' ||
        selected == 'drive_through' ||
        selected == 'drive-through') {
      return true;
    }
    final matched = _orderTypeOptions.cast<Map<String, dynamic>?>().firstWhere(
          (t) => t?['value']?.toString() == (type ?? _selectedOrderType),
          orElse: () => null,
        );
    final label = matched?['label']?.toString().toLowerCase() ?? '';
    return label.contains('سيار') || label.contains('car');
  }

  bool _isTableOrderType([String? type]) {
    final selected =
        _normalizeOrderTypeValue(type ?? _selectedOrderType).toLowerCase();
    if (selected == 'restaurant_internal' ||
        selected == 'restaurant_table' ||
        selected == 'table') {
      return true;
    }
    final matched = _orderTypeOptions.cast<Map<String, dynamic>?>().firstWhere(
          (t) => t?['value']?.toString() == (type ?? _selectedOrderType),
          orElse: () => null,
        );
    final label = matched?['label']?.toString().toLowerCase() ?? '';
    return label.contains('طاول') || label.contains('table');
  }

  String _preferredTableOrderType() {
    const preferredValues = <String>[
      'restaurant_internal',
      'restaurant_table',
      'table',
    ];

    for (final value in preferredValues) {
      final exists = _orderTypeOptions.any(
        (option) => option['value']?.toString() == value,
      );
      if (exists) return value;
    }

    for (final option in _orderTypeOptions) {
      final label = option['label']?.toString().toLowerCase() ?? '';
      if (label.contains('طاول') || label.contains('table')) {
        final value = option['value']?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }

    // Fallback used when booking settings options are missing from backend.
    return 'restaurant_internal';
  }

  String _preferredNonTableOrderType() {
    const preferredValues = <String>[
      'services',
      'restaurant_pickup',
      'restaurant_delivery',
      'restaurant_parking',
    ];

    for (final value in preferredValues) {
      final exists = _orderTypeOptions.any(
        (option) => option['value']?.toString() == value,
      );
      if (exists) return value;
    }

    for (final option in _orderTypeOptions) {
      final value = option['value']?.toString().trim() ?? '';
      final label = option['label']?.toString().toLowerCase() ?? '';
      if (value.isEmpty) continue;
      if (_isTableOrderType(value)) continue;
      if (label.contains('طاول') || label.contains('table')) continue;
      return value;
    }

    // Fallback used when booking settings options are missing from backend.
    return 'services';
  }

  String _normalizeOrderTypeValue(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'null') {
      return 'restaurant_pickup';
    }
    switch (normalized) {
      case 'pickup':
      case 'takeaway':
      case 'take_away':
      case 'restaurant_takeaway':
      case 'restaurant_take_away':
        return 'restaurant_pickup';
      case 'dine_in':
      case 'dinein':
      case 'internal':
      case 'inside':
      case 'restaurant_table':
      case 'table':
        return 'restaurant_internal';
      case 'delivery':
      case 'home_delivery':
      case 'restaurant_home_delivery':
        return 'restaurant_delivery';
      case 'restaurant_parking':
      case 'parking':
      case 'drive_through':
      case 'drive-through':
      case 'cars':
      case 'car':
        return 'restaurant_parking';
      case 'services':
      case 'service':
      case 'restaurant_services':
        return 'services';
      default:
        return normalized;
    }
  }

  /// If the active menu list is a known delivery provider
  /// (HungerStation, Talabat, Jahez), return a canonical order-type code
  /// like `hungerstation_delivery` / `hungerstation_pickup` based on
  /// `_menuListPriceType`. Returns null if no known provider matches.
  String? _resolveDeliveryProviderTypeCode() {
    if (!_isMenuListActive) return null;
    final rawName = _activeMenuListName.trim();
    if (rawName.isEmpty) return null;
    final lower = rawName.toLowerCase();
    final suffix = _menuListPriceType == 'pickup' ? 'pickup' : 'delivery';
    String? base;
    if (lower.contains('hunger') || rawName.contains('هنقر') || rawName.contains('هنجر')) {
      base = 'hungerstation';
    } else if (lower.contains('talabat') || rawName.contains('طلبات')) {
      base = 'talabat';
    } else if (lower.contains('jahez') || lower.contains('gahez') || rawName.contains('جاهز')) {
      base = 'jahez';
    }
    return base == null ? null : '${base}_$suffix';
  }

  String _resolveOrderTypeForBooking(TableItem? selectedTable) {
    // Use the selected type as-is – the dropdown already holds the exact
    // value the backend expects.  Do NOT run _normalizeOrderTypeValue here
    // because it can map e.g. 'cars' → 'restaurant_parking' which the API
    // rejects with 422.
    final selectedType = _selectedOrderType.trim();
    if (selectedTable == null) {
      if (_isTableOrderType(selectedType)) return _preferredNonTableOrderType();
      return selectedType;
    }
    if (_isTableOrderType(selectedType)) return selectedType;
    return _preferredTableOrderType();
  }


  double get _grossOrderTotal {
    if (_isOrderFree) return 0.0;
    // Quick cache check: recompute only when cart changes
    final cartHash = Object.hashAll([
      _cart.length,
      for (final item in _cart) ...[item.quantity, item.totalPrice],
      _isTaxEnabled, _taxRate,
    ]);
    if (cartHash == _lastCartHashForTotal && _cachedGrossOrderTotal != null) {
      return _cachedGrossOrderTotal!;
    }
    final subtotal = _cart.fold<double>(
      0,
      (sum, item) => sum + item.totalPrice,
    );
    final tax = _taxAmountFromSubtotal(subtotal);
    _cachedGrossOrderTotal = subtotal + tax;
    _lastCartHashForTotal = cartHash;
    return _cachedGrossOrderTotal!;
  }

  void _queuePendingPaymentAfterTableSelection({
    required String type,
    List<Map<String, dynamic>>? pays,
    required bool showLoadingOverlay,
    required bool showSuccessDialog,
    required bool clearCartOnSuccess,
    required bool isNearPayCardFlow,
  }) {
    print(
      '🧾 [PAY] queue pending type=$type showLoading=$showLoadingOverlay showSuccess=$showSuccessDialog clearCart=$clearCartOnSuccess nearPay=$isNearPayCardFlow',
    );
    _pendingPaymentTypeAfterTableSelection = type;
    _pendingPaymentPaysAfterTableSelection = pays == null
        ? null
        : pays.map((p) => Map<String, dynamic>.from(p)).toList(growable: false);
    _pendingPaymentShowLoadingAfterTableSelection = showLoadingOverlay;
    _pendingPaymentShowSuccessAfterTableSelection = showSuccessDialog;
    _pendingPaymentClearCartAfterTableSelection = clearCartOnSuccess;
    _pendingPaymentNearPayAfterTableSelection = isNearPayCardFlow;
  }

  void _clearPendingPaymentAfterTableSelection() {
    if (_pendingPaymentTypeAfterTableSelection != null) {
      print(
        '🧾 [PAY] clear pending type=$_pendingPaymentTypeAfterTableSelection',
      );
    }
    _pendingPaymentTypeAfterTableSelection = null;
    _pendingPaymentPaysAfterTableSelection = null;
    _pendingPaymentShowLoadingAfterTableSelection = true;
    _pendingPaymentShowSuccessAfterTableSelection = true;
    _pendingPaymentClearCartAfterTableSelection = false;
    _pendingPaymentNearPayAfterTableSelection = false;
  }

  double _resolveEffectiveDiscountAmount(double grossTotal) {
    if (grossTotal <= 0) return 0.0;

    // Free order = 100% discount
    if (_isOrderFree) return grossTotal;

    // Start with manual discount (خصم إضافي)
    double discount;
    if (_orderDiscountType == DiscountType.percentage && _orderDiscount > 0) {
      discount = grossTotal * (_orderDiscount / 100);
    } else {
      discount = _orderDiscount;
    }

    // ADD promo code discount on top (not replace)
    if (_activePromoCode != null) {
      double promoDiscount;
      if (_activePromoCode!.type == DiscountType.percentage) {
        promoDiscount = grossTotal * (_activePromoCode!.discount / 100);
      } else {
        promoDiscount = _activePromoCode!.discount;
      }
      if (_activePromoCode!.maxDiscount != null &&
          promoDiscount > _activePromoCode!.maxDiscount!) {
        promoDiscount = _activePromoCode!.maxDiscount!;
      }
      discount += promoDiscount;
    }
    return discount.clamp(0.0, grossTotal);
  }

  double get _totalAmount {
    if (_isOrderFree) return 0.0;
    final grossTotal = _grossOrderTotal;
    final discount = _resolveEffectiveDiscountAmount(grossTotal);
    return (grossTotal - discount).clamp(0.0, double.infinity);
  }

  void _onProductTap(Product product) async {
    // ── Salon mode ──
    if (_isSalonMode) {
      // ── Package Services mode ──
      if (_salonServiceType == 'packageServices') {
        final packageData = _findSalonPackageById(product.id);
        if (packageData == null) {
          _addToCartWithExtras(product, const [], 1.0, '');
          return;
        }

        final results = await SalonPackageSelectionDialog.show(
          context,
          packageData: packageData,
          employees: _salonEmployees,
          serviceEmployeeMap: _serviceEmployeeMap,
        );

        if (results != null && results.isNotEmpty && mounted) {
          if (getIt.isRegistered<CashierSoundService>()) {
            getIt<CashierSoundService>().playButtonSound();
          }
          HapticFeedback.lightImpact();
          setState(() {
            for (final result in results) {
              final unitPrice = (result['unitPrice'] is num)
                  ? (result['unitPrice'] as num).toDouble()
                  : product.price;
              final qty = (result['quantity'] is num)
                  ? (result['quantity'] as num).toDouble()
                  : 1.0;

              final salonProduct = Product(
                id: (result['service_id'] ?? product.id).toString(),
                name: result['item_name']?.toString() ?? product.name,
                price: unitPrice,
                category: product.category,
                isActive: true,
                image: product.image,
              );

              final employeeName = result['employee_name']?.toString() ?? '';
              final date = result['date']?.toString() ?? '';
              final time = result['time']?.toString() ?? '';
              final notes = [
                if (employeeName.isNotEmpty) employeeName,
                if (date.isNotEmpty) date,
                if (time.isNotEmpty) time,
              ].join(' | ');

              _cart.add(
                CartItem(
                  cartId: DateTime.now().millisecondsSinceEpoch.toString(),
                  product: salonProduct,
                  quantity: qty,
                  notes: notes,
                  salonData: result,
                ),
              );
            }
          });
          _syncDisplayCartFromMain();
        }
        return;
      }

      // ── Regular Services mode ──
      final serviceData = _findSalonServiceById(product.id);
      if (serviceData == null) {
        _addToCartWithExtras(product, const [], 1.0, '');
        return;
      }

      // Get employees assigned to this specific service (fallback to all)
      final serviceId = int.tryParse(product.id) ?? 0;
      final serviceEmployees = _serviceEmployeeMap[serviceId];
      final employeesForDialog =
          (serviceEmployees != null && serviceEmployees.isNotEmpty)
              ? serviceEmployees
              : _salonEmployees;

      final result = await SalonServiceSelectionDialog.show(
        context,
        serviceData: serviceData,
        employees: employeesForDialog,
      );

      if (result != null && mounted) {
        // Convert dialog result to a CartItem via Product + extras
        final unitPrice = (result['unitPrice'] is num)
            ? (result['unitPrice'] as num).toDouble()
            : product.price;
        final qty = (result['quantity'] is num)
            ? (result['quantity'] as num).toDouble()
            : 1.0;

        final salonProduct = Product(
          id: product.id,
          name: result['item_name']?.toString() ?? product.name,
          price: unitPrice,
          category: product.category,
          isActive: true,
          image: product.image,
        );

        // Build extras from addons if present
        final List<Extra> extras = [];
        if (result['addons'] is List) {
          for (final addon in result['addons'] as List) {
            if (addon is Map<String, dynamic>) {
              extras.add(Extra(
                id: (addon['id'] ?? '').toString(),
                name: (addon['name'] ?? '').toString(),
                price: (addon['price'] is num)
                    ? (addon['price'] as num).toDouble()
                    : 0.0,
              ));
            }
          }
        }

        // Build notes with employee + date/time info
        final employeeName = result['employee_name']?.toString() ?? '';
        final date = result['date']?.toString() ?? '';
        final time = result['time']?.toString() ?? '';
        final notes = [
          if (employeeName.isNotEmpty) employeeName,
          if (date.isNotEmpty) date,
          if (time.isNotEmpty) time,
        ].join(' | ');

        // For salon: add directly (no merging) and attach salonData
        if (getIt.isRegistered<CashierSoundService>()) {
          getIt<CashierSoundService>().playButtonSound();
        }
        HapticFeedback.lightImpact();
        setState(() {
          _cart.add(
            CartItem(
              cartId: DateTime.now().millisecondsSinceEpoch.toString(),
              product: salonProduct,
              quantity: qty,
              selectedExtras: extras,
              notes: notes,
              salonData: result,
            ),
          );
        });
        _syncDisplayCartFromMain();
      }
      return;
    }

    // ── Restaurant mode: existing product tap logic ──
    if (await _handleDisabledMealTap(product)) {
      return;
    }
    if (!mounted) return;

    // Decide whether to open the customization dialog. The old logic only
    // checked `product.extras` (the inline menu field) and missed meals
    // whose add-ons live on the separate `meal_addons` endpoint, hiding
    // them from the cashier. Now we also consult a cached presence check:
    //   • inline extras present  → open dialog immediately.
    //   • inline extras empty    → ask ProductService (cached per-meal).
    //     - addons exist         → open dialog.
    //     - no addons anywhere   → drop straight into cart (no friction).
    if (product.extras.isNotEmpty) {
      _openCustomizationDialog(product);
      return;
    }
    final productService = getIt<ProductService>();
    final hasAddons = await productService.mealHasAddons(product.id);
    if (!mounted) return;
    if (hasAddons) {
      _openCustomizationDialog(product);
    } else {
      _addToCartWithExtras(product, const [], 1.0, '');
    }
  }

  void _openCustomizationDialog(Product product) {
    showDialog(
      context: context,
      builder: (context) => ProductCustomizationDialog(
        product: product,
        taxRate: _isTaxEnabled ? _taxRate : 0.0,
        onConfirm: (p, extras, qty, notes) {
          _addToCartWithExtras(p, extras, qty, notes);
        },
      ),
    );
  }

  void _addToCartWithExtras(
    Product product,
    List<Extra> extras,
    double quantity,
    String notes,
  ) {
    if (_isKdsEnabled && _mealAvailabilityService.isMealDisabled(product.id)) {
      unawaited(_handleDisabledMealTap(product));
      return;
    }

    if (getIt.isRegistered<CashierSoundService>()) {
      getIt<CashierSoundService>().playButtonSound();
    }
    HapticFeedback.lightImpact();
    setState(() {
      // Check if the same product with same extras and notes already exists
      final existingIndex = _cart.indexWhere((cartItem) {
        if (cartItem.product.id != product.id) return false;
        if (cartItem.notes != notes) return false;
        // Compare extras by IDs
        final existingIds = cartItem.selectedExtras.map((e) => e.id).toList()..sort();
        final newIds = extras.map((e) => e.id).toList()..sort();
        if (existingIds.length != newIds.length) return false;
        for (var i = 0; i < existingIds.length; i++) {
          if (existingIds[i] != newIds[i]) return false;
        }
        return true;
      });

      if (existingIndex >= 0) {
        _cart[existingIndex].quantity += quantity;
      } else {
        _cart.add(
          CartItem(
            cartId: DateTime.now().millisecondsSinceEpoch.toString(),
            product: product,
            quantity: quantity,
            selectedExtras: extras,
            notes: notes,
          ),
        );
      }
    });
    _syncDisplayCartFromMain();
  }

  void _handleMealAvailabilitySync(Map<String, dynamic> payload) {
    if (!_isKdsEnabled) return;

    final mealName = payload['meal_name']?.toString().trim();
    final isDisabled = payload['is_disabled'] == true;
    _mealAvailabilityService.applyKdsRealtimeUpdate(payload);

    if (mounted && mealName != null && mealName.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isDisabled
                ? _trUi(
                    'الوجبة "$mealName" أصبحت: نفذت',
                    'Meal "$mealName" is now sold out',
                  )
                : _trUi(
                    'تمت إعادة تفعيل الوجبة "$mealName"',
                    'Meal "$mealName" is available again',
                  ),
          ),
          backgroundColor:
              isDisabled ? const Color(0xFFB91C1C) : const Color(0xFF166534),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Rebuild to reflect meal availability change in product grid
    if (mounted) setState(() {});
  }

  Future<bool> _handleDisabledMealTap(Product product) async {
    if (!_isKdsEnabled) return false;

    if (!_mealAvailabilityService.isMealDisabled(product.id)) {
      return false;
    }

    HapticFeedback.heavyImpact();
    final alternatives = _mealAvailabilityService.suggestAlternatives(
      product,
      _filteredProducts,
    );

    if (!mounted) return true;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            const SizedBox(width: 8),
            Text(translationService.t('meal_out_of_stock')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(translationService.t('meal_unavailable_currently', args: {'name': product.name})),
            if (alternatives.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'بدائل مقترحة:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: alternatives
                    .map(
                      (item) => ActionChip(
                        label: Text(item.name),
                        onPressed: () {
                          Navigator.pop(context);
                          _onProductTap(item);
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(translationService.t('close')),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              await _mealAvailabilityService.refreshFromApi(force: true);
              if (!context.mounted) return;
              Navigator.pop(context);
              if (!_mealAvailabilityService.isMealDisabled(product.id)) {
                _onProductTap(product);
              }
            },
            icon: const Icon(Icons.refresh),
            label: Text(translationService.t('retry')),
          ),
        ],
      ),
    );

    return true;
  }

  void _updateQuantity(String cartId, double delta) {
    HapticFeedback.selectionClick();
    final index = _cart.indexWhere((item) => item.cartId == cartId);
    if (_isKdsEnabled &&
        delta > 0 &&
        index >= 0 &&
        _mealAvailabilityService.isMealDisabled(_cart[index].product.id)) {
      unawaited(_handleDisabledMealTap(_cart[index].product));
      return;
    }

    setState(() {
      if (index >= 0) {
        _cart[index].quantity += delta;
        if (_cart[index].quantity <= 0) _cart[index].quantity = 1;
      }
    });
    _syncDisplayCartFromMain();
  }

  void _removeFromCart(String cartId) {
    HapticFeedback.selectionClick();
    setState(() {
      _cart.removeWhere((item) => item.cartId == cartId);
    });
    _syncDisplayCartFromMain();
  }

  void _clearCart() {
    HapticFeedback.mediumImpact();
    setState(() {
      _cart.clear();
      _orderDiscount = 0.0;
      _orderDiscountType = DiscountType.amount;
      _activePromoCode = null;
      _isOrderFree = false;
      _carNumberController.clear();
    });
    _syncDisplayCartFromMain();
  }

  Map<String, dynamic> _buildTableReservationPayload(
    TableItem table, {
    required bool reserved,
  }) {
    return <String, dynamic>{
      'name': table.number,
      'seats': table.seats,
      'status': reserved ? 'occupied' : 'available',
      'occupied_minutes': reserved ? 1 : 0,
      'waiter_name': reserved ? 'محجوز' : null,
    };
  }

  Future<bool> _syncTableReservationForOrder(
    TableItem table, {
    required bool reserved,
  }) async {
    try {
      await _tableService.updateTable(
        table.id,
        _buildTableReservationPayload(table, reserved: reserved),
      );
      print(
        '✅ table reservation synced table=${table.id} reserved=$reserved',
      );
      return true;
    } catch (e) {
      try {
        final latest = await _tableService.getTableDetails(table.id);
        final payloadSource = latest ?? table;
        await _tableService.updateTable(
          table.id,
          _buildTableReservationPayload(payloadSource, reserved: reserved),
        );
        print(
          '✅ table reservation synced on retry table=${table.id} reserved=$reserved',
        );
        return true;
      } catch (retryError) {
        print(
          '⚠️ table reservation sync failed table=${table.id} reserved=$reserved error=$e retry=$retryError',
        );
        return false;
      }
    }
  }

  void _syncDisplayCartFromMain() {
    if (!_isCdsEnabled) return;
    final displayService = getIt<DisplayAppService>();
    if (!displayService.isConnected && !displayService.isPresentationActive) {
      return;
    }
    final grossTotal = _grossOrderTotal;
    final effectiveDiscount = _resolveEffectiveDiscountAmount(grossTotal);
    final promoCodeValue = _activePromoCode?.code.trim();
    final promoCodeId = _activePromoCode?.id;
    final promoDiscountType = _activePromoCode == null
        ? null
        : (_activePromoCode!.type == DiscountType.percentage
            ? 'percentage'
            : 'fixed');
    final promoDiscountTypeForDisplay =
        promoDiscountType == 'fixed' ? 'amount' : promoDiscountType;
    final cashFloatSnapshot = _buildCashFloatSnapshot();
    final subtotal =
        _cart.fold<double>(0.0, (sum, item) => sum + item.totalPrice);
    final tax = _taxAmountFromSubtotal(subtotal);
    final taxPercentage = double.parse((_taxRate * 100).toStringAsFixed(4));
    final beforeDiscountTotal = subtotal + tax;
    final discountAmountForDisplay = _isOrderFree
        ? beforeDiscountTotal
        : effectiveDiscount.clamp(0.0, beforeDiscountTotal);
    final discountedTotalForDisplay = _isOrderFree
        ? 0.0
        : (beforeDiscountTotal - discountAmountForDisplay)
            .clamp(0.0, double.infinity);
    final effectiveDiscountPercentForDisplay = beforeDiscountTotal <= 0
        ? 0.0
        : ((discountAmountForDisplay / beforeDiscountTotal) * 100)
            .clamp(0.0, 100.0)
            .toDouble();
    final orderDiscountTypeForDisplay = _isOrderFree
        ? 'percentage'
        : (promoDiscountTypeForDisplay ??
            (_orderDiscount > 0 ? 'amount' : null));
    final orderDiscountValueForDisplay = _isOrderFree
        ? 100.0
        : (_activePromoCode != null
            ? _sanitizeDiscountInput(_activePromoCode!.discount)
            : (_orderDiscount > 0
                ? _sanitizeDiscountInput(_orderDiscount)
                : 0.0));
    final discountSourceForDisplay = _isOrderFree
        ? 'free'
        : (_activePromoCode != null
            ? 'promo'
            : (_orderDiscount > 0 ? 'manual' : 'none'));
    final promoPayload = promoCodeValue == null || promoCodeValue.isEmpty
        ? null
        : <String, dynamic>{
            if (promoCodeId != null) 'id': promoCodeId,
            'code': promoCodeValue,
            if (promoDiscountTypeForDisplay != null)
              'discount_type': promoDiscountTypeForDisplay,
            'discount_amount': discountAmountForDisplay,
          };
    final payload = {
      'items': _cart
          .map((item) => {
                'cartId': item.cartId,
                'meal_id': item.product.id,
                'productId': item.product.id,
                'name': item.product.name,
                'category_name': item.product.category,
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
      'tax_rate': _taxRate,
      'tax_percentage': taxPercentage,
      'has_tax': _isTaxEnabled,
      'total': discountedTotalForDisplay,
      'original_total': beforeDiscountTotal,
      'discount_amount': discountAmountForDisplay,
      'discounted_total': discountedTotalForDisplay,
      'is_order_free': _isOrderFree,
      'isOrderFree': _isOrderFree,
      if (orderDiscountTypeForDisplay != null)
        'order_discount_type': orderDiscountTypeForDisplay,
      'order_discount_value': orderDiscountValueForDisplay,
      'order_discount_percent': effectiveDiscountPercentForDisplay,
      'discount_source': discountSourceForDisplay,
      if (promoCodeValue != null && promoCodeValue.isNotEmpty)
        'promocodeValue': promoCodeValue,
      if (promoCodeId != null) 'promocode_id': promoCodeId,
      if (promoDiscountTypeForDisplay != null)
        'discount_type': promoDiscountTypeForDisplay,
      if (promoPayload != null) 'promo': promoPayload,
      'cash_float': cashFloatSnapshot,
      'orderNumber': '',
      'orderType': _selectedOrderType,
      'note': _orderNotesController.text.trim().isEmpty
          ? null
          : _orderNotesController.text.trim(),
    };
    final fingerprint = jsonEncode(payload);
    if (fingerprint == _lastMainCartFingerprint) {
      return;
    }
    _lastMainCartFingerprint = fingerprint;
    displayService.updateCartDisplay(
      items: _cart.map((item) {
        final basePrice = item.product.price;
        final extrasPrice =
            item.selectedExtras.fold<double>(0.0, (sum, e) => sum + e.price);
        final originalUnitPrice = basePrice + extrasPrice;
        final originalTotal = originalUnitPrice * item.quantity;

        return {
          'cartId': item.cartId,
          'meal_id': item.product.id,
          'productId': item.product.id,
          'name': item.product.name,
          'category_name': item.product.category,
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
      taxRate: _taxRate,
      hasTax: _isTaxEnabled,
      total: discountedTotalForDisplay,
      promoCode: promoCodeValue,
      promoCodeId: promoCodeId,
      promoDiscountType: promoDiscountTypeForDisplay,
      discountAmount: discountAmountForDisplay,
      originalTotal: beforeDiscountTotal,
      discountedTotal: discountedTotalForDisplay,
      cashFloatSnapshot: cashFloatSnapshot,
      orderNumber: '',
      orderType: _selectedOrderType,
      note: _orderNotesController.text.trim().isEmpty
          ? null
          : _orderNotesController.text.trim(),
      isOrderFree: _isOrderFree,
      orderDiscountType: orderDiscountTypeForDisplay,
      orderDiscountValue: orderDiscountValueForDisplay,
      orderDiscountPercent: effectiveDiscountPercentForDisplay,
      discountSource: discountSourceForDisplay,
    );
  }

  double _sanitizeDiscountInput(double value) {
    if (!value.isFinite) return 0.0;
    return value < 0 ? 0.0 : value;
  }

  double _clampCartItemDiscount(CartItem item, double raw, DiscountType type) {
    final sanitized = _sanitizeDiscountInput(raw);
    if (type == DiscountType.percentage) {
      return sanitized.clamp(0.0, 100.0).toDouble();
    }
    final extrasTotal =
        item.selectedExtras.fold<double>(0.0, (sum, e) => sum + e.price);
    final baseTotal = (item.product.price + extrasTotal) * item.quantity;
    return sanitized.clamp(0.0, baseTotal).toDouble();
  }

  void _setOrderDiscount(double rawDiscount, {DiscountType type = DiscountType.amount}) {
    final sanitized = _sanitizeDiscountInput(rawDiscount);
    final subtotal =
        _cart.fold<double>(0.0, (sum, item) => sum + item.totalPrice);
    final gross = subtotal + _taxAmountFromSubtotal(subtotal);

    double clamped;
    if (type == DiscountType.percentage) {
      clamped = sanitized.clamp(0.0, 100.0).toDouble();
    } else {
      clamped = sanitized.clamp(0.0, gross).toDouble();
    }

    setState(() {
      _orderDiscount = clamped;
      _orderDiscountType = type;
      if (_isOrderFree) {
        _isOrderFree = false;
      }
    });
    _syncDisplayCartFromMain();
  }

  void _toggleOrderFreeState() {
    setState(() {
      _isOrderFree = !_isOrderFree;
      if (_isOrderFree) {
        _orderDiscount = 0.0;
      }
    });
    _syncDisplayCartFromMain();
  }

  void _updateDiscount(String cartId, double discount, DiscountType type) {
    setState(() {
      final index = _cart.indexWhere((item) => item.cartId == cartId);
      if (index >= 0) {
        _cart[index].discount =
            _clampCartItemDiscount(_cart[index], discount, type);
        _cart[index].discountType = type;
        if (_cart[index].isFree && _cart[index].discount > 0) {
          _cart[index].isFree = false;
        }
      }
    });
    _syncDisplayCartFromMain();
  }

  void _toggleFree(String cartId) {
    setState(() {
      final index = _cart.indexWhere((item) => item.cartId == cartId);
      if (index >= 0) {
        _cart[index].isFree = !_cart[index].isFree;
        if (_cart[index].isFree) {
          _cart[index].discount = 0.0;
        }
      }
    });
    _syncDisplayCartFromMain();
  }

  Future<void> _showBookingDetails(String cartId) async {
    if (_cart.isEmpty) return;
    final orderId = _lastCreatedBookingId;
    if (orderId == null || orderId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(translationService.t('no_saved_order_number')),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final orderService = getIt<OrderService>();
      final bookingDetails = await orderService.getBookingDetails(orderId);

      if (mounted) Navigator.pop(context);

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) =>
              BookingDetailsDialog(bookingData: bookingDetails),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(translationService.t('failed_load_order', args: {'error': e.toString()})),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showMealDetailsForCartItem(CartItem item) {
    showDialog(
      context: context,
      builder: (context) => MealDetailsDialog(product: item.product),
    );
  }
}
