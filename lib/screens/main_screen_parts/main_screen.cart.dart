// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, library_private_types_in_public_api
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

    return 'services';
  }

  String _normalizeOrderTypeValue(String value) =>
      ReceiptBuilderService.normalizeOrderTypeValue(value);

  /// Canonical delivery provider order-type code (HungerStation/Talabat/Jahez), or null.
  String? _resolveDeliveryProviderTypeCode() =>
      ReceiptBuilderService.resolveDeliveryProviderTypeCode(
        isMenuListActive: _isMenuListActive,
        activeMenuListName: _activeMenuListName,
        menuListPriceType: _menuListPriceType,
      );

  String _resolveOrderTypeForBooking(TableItem? selectedTable) {
    // Use selected type as-is; normalize would map e.g. 'cars'→'restaurant_parking' which 422s.
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
    final cartHash = Object.hashAll([
      _cart.length,
      for (final item in _cart) ...[item.quantity, item.totalPrice],
      _isTaxEnabled, _taxRate,
    ]);
    if (cartHash == _lastCartHashForTotal && _cachedGrossOrderTotal != null) {
      return _cachedGrossOrderTotal!;
    }
    final cartSum = _cart.fold<double>(
      0,
      (sum, item) => sum + item.totalPrice,
    );
    // Salon services are tax-inclusive on backend; don't re-add VAT.
    if (_isSalonMode) {
      _cachedGrossOrderTotal = cartSum;
    } else {
      final tax = _taxAmountFromSubtotal(cartSum);
      _cachedGrossOrderTotal = cartSum + tax;
    }
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
    Log.d('pay',
        'queue pending type=$type showLoading=$showLoadingOverlay '
        'showSuccess=$showSuccessDialog clearCart=$clearCartOnSuccess '
        'nearPay=$isNearPayCardFlow');
    _pendingPaymentTypeAfterTableSelection = type;
    _pendingPaymentPaysAfterTableSelection = pays?.map((p) => Map<String, dynamic>.from(p)).toList(growable: false);
    _pendingPaymentShowLoadingAfterTableSelection = showLoadingOverlay;
    _pendingPaymentShowSuccessAfterTableSelection = showSuccessDialog;
    _pendingPaymentClearCartAfterTableSelection = clearCartOnSuccess;
    _pendingPaymentNearPayAfterTableSelection = isNearPayCardFlow;
  }

  void _clearPendingPaymentAfterTableSelection() {
    if (_pendingPaymentTypeAfterTableSelection != null) {
      Log.d('pay',
          'clear pending type=$_pendingPaymentTypeAfterTableSelection');
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
    if (_isOrderFree) return grossTotal;

    double discount;
    if (_orderDiscountType == DiscountType.percentage && _orderDiscount > 0) {
      discount = grossTotal * (_orderDiscount / 100);
    } else {
      discount = _orderDiscount;
    }

    // Promo code adds on top of manual discount, not replaces.
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
    if (_isSalonMode) {
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
            unawaited(getIt<CashierSoundService>().playButtonSound());
          }
          unawaited(HapticFeedback.lightImpact());
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

      final serviceData = _findSalonServiceById(product.id);
      if (serviceData == null) {
        _addToCartWithExtras(product, const [], 1.0, '');
        return;
      }

      // Employees assigned to this service, fallback to all.
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
        shopLogoUrl: _salonBranchLogoUrl,
      );

      if (result != null && mounted) {
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

        final employeeName = result['employee_name']?.toString() ?? '';
        final date = result['date']?.toString() ?? '';
        final time = result['time']?.toString() ?? '';
        final notes = [
          if (employeeName.isNotEmpty) employeeName,
          if (date.isNotEmpty) date,
          if (time.isNotEmpty) time,
        ].join(' | ');

        // Salon: add directly (no merging) and attach salonData.
        if (getIt.isRegistered<CashierSoundService>()) {
          unawaited(getIt<CashierSoundService>().playButtonSound());
        }
        unawaited(HapticFeedback.lightImpact());
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

    if (await _handleDisabledMealTap(product)) {
      return;
    }
    if (!mounted) return;

    // Open customization dialog when inline extras OR meal_addons exist.
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
      // Merge if same product + extras + notes already in cart.
      final existingIndex = _cart.indexWhere((cartItem) {
        if (cartItem.product.id != product.id) return false;
        if (cartItem.notes != notes) return false;
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
      UiFeedback.info(context, isDisabled
                ? _trUi(
                    'الوجبة "$mealName" أصبحت: نفذت',
                    'Meal "$mealName" is now sold out',
                  )
                : _trUi(
                    'تمت إعادة تفعيل الوجبة "$mealName"',
                    'Meal "$mealName" is available again',
                  ));
    }

    if (mounted) setState(() {});
  }

  Future<bool> _handleDisabledMealTap(Product product) async {
    if (!_isKdsEnabled) return false;

    if (!_mealAvailabilityService.isMealDisabled(product.id)) {
      return false;
    }

    unawaited(HapticFeedback.heavyImpact());
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
            onPressed: () {
              _mealAvailabilityService.markMealAvailable(
                product.id,
                mealName: product.name,
              );
              _displayAppService.notifyMealAvailabilityChange(
                mealId: product.id,
                mealName: product.name,
                categoryName: product.category,
                isDisabled: false,
              );
              Navigator.pop(context);
            },
            icon: const Icon(Icons.power_settings_new),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            label: Text(translationService.t('activate_meal')),
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
      // Deposits are per-invoice; clear on cart-clear so next booking starts fresh.
      if (_isSalonMode) {
        _selectedDepositId = null;
      }
    });
    // Refetch deposits so a just-consumed one drops off the picker.
    if (_isSalonMode && _selectedCustomer != null) {
      _loadCustomerDeposits(_selectedCustomer!.id);
    }
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
    bool mirrorToMesh = true,
    String? bookingId,
    double? total,
    int? itemCount,
  }) async {
    bool ok;
    try {
      await _tableService.updateTable(
        table.id,
        _buildTableReservationPayload(table, reserved: reserved),
      );
      Log.d('table',
          'reservation synced table=${table.id} reserved=$reserved');
      ok = true;
    } catch (e) {
      try {
        final latest = await _tableService.getTableDetails(table.id);
        final payloadSource = latest ?? table;
        await _tableService.updateTable(
          table.id,
          _buildTableReservationPayload(payloadSource, reserved: reserved),
        );
        Log.d('table',
            'reservation synced on retry table=${table.id} reserved=$reserved');
        ok = true;
      } catch (retryError) {
        Log.w('table',
            'reservation sync failed table=${table.id} reserved=$reserved',
            error: retryError);
        ok = false;
      }
    }
    // Mirror into the waiter mesh; best-effort so mesh hiccups can't fail payment.
    if (mirrorToMesh) {
      try {
        getIt<CashierMeshBootstrap>().broadcastCashierTableState(
          tableId: table.id,
          tableNumber: table.number,
          reserved: reserved,
          bookingId: reserved ? bookingId : null,
          total: reserved ? total : null,
          itemCount: reserved ? itemCount : null,
        );
      } catch (e) {
        Log.d('MainScreenCart', 'broadcast cashier table state to mesh failed (non-fatal): $e');
      }
    }
    return ok;
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
    final cartSum =
        _cart.fold<double>(0.0, (sum, item) => sum + item.totalPrice);
    // Salon prices are tax-inclusive — derive pre-tax subtotal/tax instead of adding VAT.
    final double subtotal;
    final double tax;
    if (_isSalonMode) {
      subtotal = _subtotalFromTaxInclusiveTotal(cartSum);
      tax = _taxFromTaxInclusiveTotal(cartSum);
    } else {
      subtotal = cartSum;
      tax = _taxAmountFromSubtotal(subtotal);
    }
    final taxPercentage = double.parse((_taxRate * 100).toStringAsFixed(4));
    final beforeDiscountTotal = _isSalonMode ? cartSum : (subtotal + tax);
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
    final cashierLang =
        ApiConstants.acceptLanguage.trim().toLowerCase().isEmpty
            ? 'ar'
            : ApiConstants.acceptLanguage.trim().toLowerCase();
    final payload = {
      'items': _cart
          .map((item) {
                // Merge translations for CDS language resolution (product → cache → active name).
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
                final nameAr = merged['ar'] ?? '';
                final nameEn = merged['en'] ?? '';
                final extrasTotal = item.selectedExtras
                    .fold<double>(0.0, (s, e) => s + e.price);
                final unitWithExtras = item.product.price + extrasTotal;
                final itemQty = item.quantity > 0 ? item.quantity : 0.0;
                final itemOriginalTotal = unitWithExtras * itemQty;
                final itemFinalTotal = item.totalPrice;
                final itemDiscountTypeStr =
                    item.discountType == DiscountType.percentage
                        ? 'percentage'
                        : 'amount';
                return {
                'cartId': item.cartId,
                'meal_id': item.product.id,
                'productId': item.product.id,
                'name': item.product.name,
                'name_lang': cashierLang,
                'nameEn': nameEn,
                'nameAr': nameAr,
                'localizedNames': merged,
                'category_name': item.product.category,
                'quantity': item.quantity,
                'price': item.product.price,
                'extras': item.selectedExtras.map((e) {
                  final extraMerged = <String, String>{
                    ...e.optionTranslations,
                    ...ProductService.cachedOptionNamesFor(e.id),
                  };
                  extraMerged.putIfAbsent(cashierLang, () => e.name);
                  return {
                    'id': e.id,
                    'name': e.name,
                    'name_lang': cashierLang,
                    'nameEn': extraMerged['en'] ?? e.name,
                    'nameAr': extraMerged['ar'] ?? '',
                    'localizedNames': extraMerged,
                    'price': e.price,
                  };
                }).toList(),
                'totalPrice': itemFinalTotal,
                'notes': item.notes,
                'discount': item.discount,
                'discount_type': itemDiscountTypeStr,
                'is_free': item.isFree,
                'original_unit_price': unitWithExtras,
                'original_total': itemOriginalTotal,
                'final_total': itemFinalTotal,
              };
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
      'invoice_primary_lang': printerLanguageSettings.primary,
      'invoice_secondary_lang': printerLanguageSettings.secondary,
      'invoice_allow_secondary': printerLanguageSettings.allowSecondary,
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

    // Salon mode: mirror the per-service "turn slip" rows (customer + service
    // + employee + price) so the Display App CDS can render them as ticket
    // cards alongside the cart. Restaurant flow leaves this null.
    List<Map<String, dynamic>>? salonTickets;
    if (_isSalonMode) {
      final lang = _resolveKitchenInvoiceLang();
      final customerName =
          (_selectedCustomer?.name.trim().isNotEmpty == true)
              ? _selectedCustomer!.name
              : '-';
      final customerPhone =
          (_selectedCustomer?.mobile?.trim().isNotEmpty == true)
              ? _selectedCustomer!.mobile!
              : '';
      final employeeLookup = <int, String>{
        for (final e in _salonEmployees)
          if (e['id'] is num)
            (e['id'] as num).toInt(): (e['name'] ?? '').toString(),
      };
      final bookingNumber = _lastCreatedBookingId ?? '';
      salonTickets = <Map<String, dynamic>>[];
      for (var i = 0; i < _cart.length; i++) {
        final item = _cart[i];
        final salon = item.salonData ?? const <String, dynamic>{};
        final empRaw = salon['employee_id'];
        final empId = empRaw is num
            ? empRaw.toInt()
            : (empRaw is String ? int.tryParse(empRaw) : null);
        final employeeName = (salon['employee_name']?.toString().trim().isNotEmpty ==
                true)
            ? salon['employee_name'].toString()
            : (empId != null ? (employeeLookup[empId] ?? '') : '');
        final salonNote = (salon['notes'] ?? '').toString().trim();
        final cartNote = item.notes.trim();
        final mergedNotes = (salonNote.isNotEmpty &&
                cartNote.isNotEmpty &&
                salonNote != cartNote)
            ? '$salonNote · $cartNote'
            : (salonNote.isNotEmpty ? salonNote : cartNote);
        final serviceName = _resolveSalonServiceName(
          lang: lang,
          translations: salon['service_name_translations'] ??
              salon['name_translations'] ??
              salon['meal_name_translations'],
          productLocalized: item.product.nameForLang(lang),
          snapshotName: salon['item_name']?.toString(),
          productName: item.product.name,
        );
        final totalPrice = item.product.price * item.quantity;
        final priceFormatted =
            totalPrice.toStringAsFixed(ApiConstants.digitsNumber);
        salonTickets.add(<String, dynamic>{
          'service_index': i + 1,
          'cart_id': item.cartId,
          'customer_name': customerName,
          if (customerPhone.isNotEmpty) 'customer_phone': customerPhone,
          'service_name': serviceName,
          'employee_name': employeeName.isNotEmpty ? employeeName : '-',
          'price': totalPrice,
          'price_formatted': priceFormatted,
          'currency': ApiConstants.currency,
          if (mergedNotes.isNotEmpty) 'notes': mergedNotes,
          'date_str': (salon['date']?.toString().trim().isNotEmpty == true)
              ? salon['date'].toString()
              : '',
          'time_str': (salon['time']?.toString().trim().isNotEmpty == true)
              ? salon['time'].toString()
              : '',
          if (bookingNumber.isNotEmpty) 'booking_number': bookingNumber,
        });
      }
    }

    displayService.updateCartDisplay(
      items: _cart.map((item) {
        final basePrice = item.product.price;
        final extrasPrice =
            item.selectedExtras.fold<double>(0.0, (sum, e) => sum + e.price);
        final originalUnitPrice = basePrice + extrasPrice;
        final originalTotal = originalUnitPrice * item.quantity;
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

        return {
          'cartId': item.cartId,
          'meal_id': item.product.id,
          'productId': item.product.id,
          'name': item.product.name,
          'name_lang': cashierLang,
          'nameEn': merged['en'] ?? '',
          'nameAr': merged['ar'] ?? '',
          'localizedNames': merged,
          'category_name': item.product.category,
          'quantity': item.quantity,
          'price': item.product.price,
          'extras': item.selectedExtras.map((e) {
            final extraMerged = <String, String>{
              ...e.optionTranslations,
              ...ProductService.cachedOptionNamesFor(e.id),
            };
            extraMerged.putIfAbsent(cashierLang, () => e.name);
            return {
              'id': e.id,
              'name': e.name,
              'name_lang': cashierLang,
              'nameEn': extraMerged['en'] ?? e.name,
              'nameAr': extraMerged['ar'] ?? '',
              'localizedNames': extraMerged,
              'price': e.price,
            };
          }).toList(),
          'totalPrice': item.totalPrice,
          'notes': item.notes,
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
      invoicePrimaryLang: printerLanguageSettings.primary,
      invoiceSecondaryLang: printerLanguageSettings.secondary,
      invoiceAllowSecondary: printerLanguageSettings.allowSecondary,
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
      salonTickets: salonTickets,
      branchModule: ApiConstants.branchModule,
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
        UiFeedback.warning(context, translationService.t('no_saved_order_number'));
      }
      return;
    }
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    ));

    try {
      final orderService = getIt<OrderService>();
      final bookingDetails = await orderService.getBookingDetails(orderId);

      if (mounted) Navigator.pop(context);

      if (mounted) {
        unawaited(showDialog(
          context: context,
          builder: (context) =>
              BookingDetailsDialog(bookingData: bookingDetails),
        ));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        UiFeedback.error(context, translationService.t('failed_load_order', args: {'error': e.toString()}));
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
