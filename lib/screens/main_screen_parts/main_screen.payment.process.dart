// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, avoid_dynamic_calls, library_private_types_in_public_api
// JSON wire-boundary / message-dispatch layer — dynamic accesses accepted pending typed-model refactor.
part of '../main_screen.dart';

extension MainScreenPaymentProcess on _MainScreenState {
  Future<void> _processPayment({
    required String type,
    List<Map<String, dynamic>>? pays,
    bool showLoadingOverlay = true,
    bool showSuccessDialog = true,
    bool clearCartOnSuccess = true,
    bool isNearPayCardFlow = false,
  }) async {
    Log.d('pay',
        'process start type=$type orderType=$_selectedOrderType '
        'table=${_selectedTable?.id ?? '-'} '
        'lastTable=${_lastSelectedTable?.id ?? '-'} '
        'cart=${_cart.length} pays=${pays?.length ?? 0} '
        'nearPay=$isNearPayCardFlow');
    if (_cart.isEmpty) {
      if (mounted) {
        UiFeedback.warning(context, translationService.t('cart_empty_error'));
      }
      return;
    }

    if (type == 'payment' && !_hasAnyEnabledPayMethod()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 3),
            content: Text(
              'لا توجد طرق دفع مفعّلة لهذا الفرع. فعّل طريقة دفع من لوحة التحكم ثم أعد المحاولة.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final carNumber = _carNumberController.text.trim();
    if (_isCarOrderType() && carNumber.isEmpty) {
      if (mounted) {
        UiFeedback.warning(context, _trUi(
                'رقم السيارة مطلوب لطلبات السيارات',
                'Car number is required for car orders',
              ));
      }
      return;
    }
    if (!mounted) return;

    final resolvedTableSelection = _selectedTable ?? _lastSelectedTable;
    if (_selectedTable == null && resolvedTableSelection != null && mounted) {
      setState(() => _selectedTable = resolvedTableSelection);
    }
    final selectedTableForValidation = resolvedTableSelection;
    final requiresTableForBookingValidation =
        _isTableOrderType(_selectedOrderType);
    if (requiresTableForBookingValidation &&
        selectedTableForValidation == null) {
      Log.d('pay', 'process missing table — queue and route');
      if (type == 'payment') {
        _queuePendingPaymentAfterTableSelection(
          type: type,
          pays: pays,
          showLoadingOverlay: showLoadingOverlay,
          showSuccessDialog: showSuccessDialog,
          clearCartOnSuccess: clearCartOnSuccess,
          isNearPayCardFlow: isNearPayCardFlow,
        );
      }
      setState(() => _activeTab = 'tables');
      return;
    }

    // Loading overlay suppressed — payment proceeds in the background; Navigator.pop guards below short-circuit.
    showLoadingOverlay = false;

    // Snapshot for salon-only optimistic cart clear; declared outside try so catch can restore on throw.
    List<CartItem>? optimisticClearSnapshot;

    try {
      final orderService = getIt<OrderService>();
      final displayService = getIt<DisplayAppService>();
      if (type == 'payment' && _isCdsEnabled) {
        displayService.pinCdsModeTemporarily(
          duration: const Duration(seconds: 18),
        );
      }
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final grossOrderTotal = _grossOrderTotal;
      double appliedDiscountAmount =
          _resolveEffectiveDiscountAmount(grossOrderTotal);
      double orderTotal =
          (grossOrderTotal - appliedDiscountAmount).clamp(0.0, double.infinity);
      double payableTotal = orderTotal;
      String? promoCodeId = _activePromoCode?.id;
      String? promoCodeValue = _activePromoCode?.code.trim();
      String? promoDiscountType = _activePromoCode == null
          ? null
          : (_activePromoCode!.type == DiscountType.percentage
              ? 'percentage'
              : 'fixed');
      var promoRemovedDueToExpiry = false;

      void clearActivePromoSelectionLocally() {
        if (_activePromoCode == null) return;
        _applyPromoCode(null);
      }

      final cartItemsForOrder =
          _cart.where((item) => item.quantity > 0).toList();
      if (cartItemsForOrder.isEmpty) {
        throw Exception(translationService.t('cart_empty_error'));
      }

      // Optimistic cart clear (salon-only): salon createBooking ~1.5–2s; restore on throw.
      if (_isSalonMode && clearCartOnSuccess && _cart.isNotEmpty) {
        optimisticClearSnapshot = List<CartItem>.from(_cart);
        setState(() {
          _cart.clear();
        });
        _syncDisplayCartFromMain();
      }
      final selectedTableForOrder = resolvedTableSelection;
      Log.d('pay',
          'order table resolved=${selectedTableForOrder?.id ?? '-'}');
      final bookingOrderType =
          _resolveOrderTypeForBooking(selectedTableForOrder);
      final requiresTableForBooking = _isTableOrderType(_selectedOrderType);
      String? resolvedTableName;
      if (selectedTableForOrder != null) {
        final rawName = selectedTableForOrder.number.trim();
        resolvedTableName =
            rawName.isNotEmpty ? rawName : selectedTableForOrder.id.trim();
      }
      final hasResolvedTableName =
          resolvedTableName != null && resolvedTableName.trim().isNotEmpty;

      // Backend enforces table_name for dine-in/table order types.
      if (requiresTableForBooking &&
          (selectedTableForOrder == null || !hasResolvedTableName)) {
        if (type == 'payment') {
          _queuePendingPaymentAfterTableSelection(
            type: type,
            pays: pays,
            showLoadingOverlay: showLoadingOverlay,
            showSuccessDialog: showSuccessDialog,
            clearCartOnSuccess: clearCartOnSuccess,
            isNearPayCardFlow: isNearPayCardFlow,
          );
        }
        if (showLoadingOverlay && mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        if (mounted) {
          UiFeedback.warning(context, _trUi(
                  'اختر طاولة صالحة قبل إكمال العملية',
                  'Select a valid table before continuing',
                ));
          setState(() => _activeTab = 'tables');
        }
        return;
      }

      final orderItemsSnapshot = _buildOrderItemsSnapshot(cartItemsForOrder);
      final kdsItemsPayload = _buildKdsItemsPayload(cartItemsForOrder);
      bool kdsOrderDispatched = false;
      bool kdsScreenReceivedOrder = false;

      Log.d('pay', 'creating booking with order type=\$bookingOrderType');
      Log.d('pay', 'selectedOrderType=\$_selectedOrderType');
      final Map<String, dynamic> bookingData;
      if (_isSalonMode) {
        // Salon booking type: 'packageServices' if any cart item has package_service_id, else null.
        final hasPackageItems = cartItemsForOrder.any((item) =>
            item.salonData != null && item.salonData!['package_service_id'] != null);
        bookingData = <String, dynamic>{
          'type': hasPackageItems ? 'packageServices' : null,
          'date': dateStr,
          if (_selectedCustomer != null)
            'customer_id': _selectedCustomer!.id.toString(),
          'type_extra': {
            'car_number': null,
            'table_name': null,
            'latitude': null,
            'longitude': null,
          },
        };
      } else {
        bookingData = <String, dynamic>{
          'type': bookingOrderType,
          'date': dateStr,
          if (selectedTableForOrder != null)
            'table_id': selectedTableForOrder.id,
          if (_selectedCustomer != null)
            'customer_id': _selectedCustomer!.id.toString(),
          'type_extra': {
            if (carNumber.isNotEmpty) 'car_number': carNumber,
            if (requiresTableForBooking && selectedTableForOrder != null) ...{
              'table_name': resolvedTableName,
              'table_id': selectedTableForOrder.id,
            },
            'latitude': null,
            'longitude': null,
          },
        };
      }
      Log.d('pay',
          'booking payload table type=$bookingOrderType '
          'table_id=${selectedTableForOrder?.id} '
          'table_name=$resolvedTableName');

      // Snapshot order-level discount & promo BEFORE _clearCart() resets them.
      final snapshotOrderDiscount = _orderDiscount;
      final snapshotOrderDiscountType = _orderDiscountType;
      final snapshotIsOrderFree = _isOrderFree;
      final snapshotPromo = _activePromoCode;

      final discountSnapshot = pph.OrderDiscountSnapshot(
        orderDiscount: snapshotOrderDiscount,
        orderDiscountType: snapshotOrderDiscountType,
        isOrderFree: snapshotIsOrderFree,
        promo: snapshotPromo,
        grossOrderTotal: grossOrderTotal,
      );
      double resolveItemApiDiscount(CartItem item) =>
          pph.resolveItemApiDiscount(item, discountSnapshot);

      // Build items in API-compatible "card" shape.
      final List<Map<String, dynamic>> cartItems = [];
      if (_isSalonMode) {
        for (var item in cartItemsForOrder) {
          final salon = item.salonData ?? <String, dynamic>{};
          final effectiveDiscount = resolveItemApiDiscount(item);
          cartItems.add({
            'package_service_id': salon['package_service_id'],
            'item_name': salon['item_name'] ?? item.product.name,
            'service_id': salon['service_id'] ??
                int.tryParse(item.product.id) ??
                item.product.id,
            'minutes': salon['minutes'] ?? 0,
            'employee_name': salon['employee_name'] ?? '',
            'employee_id': salon['employee_id'],
            'date': salon['date'] ?? dateStr,
            'time': salon['time'] ?? '',
            'session_numbers': salon['session_numbers'] ?? 0,
            'quantity': item.quantity.round().clamp(1, 9999),
            'price': item.product.price,
            'unitPrice': item.product.price,
            'modified_unit_price': salon['modified_unit_price'],
            if (item.notes.isNotEmpty) 'note': item.notes,
            if (effectiveDiscount > 0) 'discount': effectiveDiscount,
            if (effectiveDiscount > 0) 'discount_type': '%',
          });
        }
      } else {
        for (var item in cartItemsForOrder) {
          final addonIds = _toAddonIdList(item.selectedExtras);
          final effectiveDiscount = resolveItemApiDiscount(item);
          final qty = item.quantity > 0 ? item.quantity : 1.0;
          cartItems.add({
            'item_name': item.product.name,
            'meal_id': item.product.id,
            'price': item.product.price * qty,
            'unitPrice': item.product.price,
            'modified_unit_price': null,
            'quantity': qty,
            'addons': addonIds,
            if (item.notes.isNotEmpty) 'note': item.notes,
            if (effectiveDiscount > 0) 'discount': effectiveDiscount,
            if (effectiveDiscount > 0) 'discount_type': '%',
          });
        }
      }
      // Keep both keys for compatibility across accounts.
      bookingData['card'] = cartItems;
      if (!_isSalonMode) bookingData['meals'] = cartItems;

      final bookingResponse = await orderService.createBooking(
        bookingData,
        paymentType: type,
      );
      final parsedBooking = pph.parseBookingResponse(bookingResponse);
      if (parsedBooking.orderId == null) {
        final backendMessage = bookingResponse['message']?.toString();
        throw Exception(
          ErrorHandler.normalizeBackendMessage(
            backendMessage,
            defaultMessage: 'فشل إنشاء الطلب',
          ),
        );
      }
      final orderId = parsedBooking.orderId!;
      final backendOrderId = parsedBooking.backendOrderId;
      final backendDailyOrderNumber = parsedBooking.backendDailyOrderNumber;
      final bookingDataMap = parsedBooking.bookingDataMap;
      final bookingNode = parsedBooking.bookingNode;
      final bookingProductIds = parsedBooking.bookingProductIds;
      // ignore: unused_local_variable
      final bookingProductsData = parsedBooking.bookingProductsData;
      final bookingMealsData = parsedBooking.bookingMealsData;
      final displayOrderRef = parsedBooking.displayOrderRef;
      Log.d('pay',
          'booking/order mapping resolved booking.id=$orderId '
          'order.id=${backendOrderId ?? '-'} '
          'order_number=${backendDailyOrderNumber ?? '-'}');
      _lastCreatedBookingId = orderId;

      // Fast path: close loading and show success immediately; invoice/KDS/printing run in background.
      if (showLoadingOverlay && mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (clearCartOnSuccess) {
        _clearCart();
      }


      if (type == 'payment') {
        unawaited(
          _showCashPaymentSuccessOnCds(
            displayService: displayService,
            pays: pays?.whereType<Map<String, dynamic>>().toList() ?? const [],
          ),
        );
      }

      // Fire-and-forget: table reservation doesn't block payment
      if (selectedTableForOrder != null) {
        final tableCapture = selectedTableForOrder;
        // Pay-now orders flip free→occupied→free within seconds; only mirror genuine pay-later bookings to waiters.
        final mirrorPendingToMesh = type != 'payment';
        unawaited(() async {
          final synced = await _syncTableReservationForOrder(
            tableCapture,
            reserved: true,
            mirrorToMesh: mirrorPendingToMesh,
            bookingId: mirrorPendingToMesh ? orderId : null,
            total: orderTotal,
            itemCount: cartItems.length,
          );
          if (!synced && mounted) {
            UiFeedback.warning(context, _trUi(
                    'تم إنشاء الطلب ولكن تعذر تحديث حالة الطاولة تلقائياً. يرجى التحقق من شاشة الطاولات.',
                    'Order was created, but table status could not be updated automatically. Please verify from tables screen.',
                  ));
          }
        }());
      }
      if (_isKdsEnabled) {
        unawaited(() async {
          try {
            final firstDispatchAcked = await _dispatchOrderToKdsWithAck(
              displayService: displayService,
              orderId: orderId,
              orderNumber: displayOrderRef,
              orderType: bookingOrderType,
              items: kdsItemsPayload,
              note: _orderNotesController.text.isNotEmpty
                  ? _orderNotesController.text
                  : null,
              total: orderTotal,
              invoice: _buildKdsInvoicePayload(
                bookingId: orderId,
                orderId: backendOrderId,
                orderNumber: displayOrderRef,
                invoiceId: null,
                invoiceNumber: null,
                type: type,
                orderTotal: orderTotal,
                grossOrderTotal: grossOrderTotal,
                discountAmount: appliedDiscountAmount,
                promoCodeId: promoCodeId,
                promoCode: promoCodeValue,
                promoDiscountType: promoDiscountType,
                orderItems: orderItemsSnapshot,
                cashFloatSnapshot: _buildCashFloatSnapshot(),
              ),
            );
            kdsOrderDispatched = true;
            kdsScreenReceivedOrder = firstDispatchAcked;
          } catch (e) {
            debugPrint('⚠️ Failed to dispatch NEW_ORDER after booking #$orderId: $e');
          }
        }());
      }

      Future<void>? bookingDetailsFuture;
      if (bookingProductIds.isEmpty) {
        bookingDetailsFuture = () async {
          try {
            final bookingDetails = await orderService.getBookingDetails(orderId);
            final detailsData = bookingDetails['data'];
            final detected = pph.extractBookingProductId(detailsData);
            if (detected != null) {
              bookingProductIds.add(detected);
            }

            if (detailsData is Map) {
              final detailsMeals = detailsData['booking_meals'];
              if (detailsMeals is List) {
                for (final m in detailsMeals) {
                  final mealMap = pph.asStringKeyMap(m);
                  if (mealMap != null) {
                    bookingMealsData.add(mealMap);
                  }
                }
              }
            }
          } catch (e) {
            debugPrint(
                '⚠️ Could not fetch booking details for booking_product_id: $e');
          }
        }();
      }

      // Step 2: Create Invoice — runs after loading closed; errors surface as snackbar.
      try {
      if (bookingDetailsFuture != null) await bookingDetailsFuture;
      final dynamic primaryBookingProductId =
          bookingProductIds.isNotEmpty ? bookingProductIds.first : null;
      if (primaryBookingProductId != null) {
        debugPrint('ℹ️ booking_product_id detected: $primaryBookingProductId');
      }
      String? invoiceNumber;
      String? invoiceId;
      Map<String, dynamic>? invoicePayload;
      List<Map<String, dynamic>> normalizedPays = const [];
      if (type == 'payment') {
        final List<Map<String, dynamic>> calcItems;
        final String calcItemsKey;
        if (_isSalonMode) {
          calcItemsKey = 'sales_services';
          calcItems = cartItemsForOrder.map((item) {
            final salon = item.salonData ?? <String, dynamic>{};
            return {
              'service_id': salon['service_id'] ?? int.tryParse(item.product.id),
              'service_name': salon['item_name'] ?? item.product.name,
              'employee_id': salon['employee_id'] ?? '',
              'quantity': item.quantity.round().clamp(1, 9999),
              'price': item.product.price,
              'unit_price': item.product.price,
              'modified_unit_price': salon['modified_unit_price'] ?? '',
              'package_service_id': salon['package_service_id'] ?? '',
              'date': salon['date'] ?? '',
              'time': salon['time'] ?? '',
              'session_numbers': salon['session_numbers'] ?? '',
              'booking_service_id': salon['booking_service_id'] ?? '',
              'discount': '',
              'discount_type': '%',
            };
          }).toList();
        } else {
          calcItemsKey = 'items';
          calcItems = cartItemsForOrder
              .map(
                (item) => {
                  'meal_id': int.tryParse(item.product.id) ?? item.product.id,
                  'quantity': item.quantity.round().clamp(1, 9999),
                  'price': item.product.price,
                },
              )
              .toList();
        }
        // Server rule: applied deposit must not exceed invoice total or calculate/invoices returns 422.
        int? effectiveDepositId;
        if (_isSalonMode && _selectedDepositId != null) {
          final subtotal = cartItemsForOrder.fold<double>(
              0.0, (sum, it) => sum + it.product.price * it.quantity);
          final depositPrice = _lookupSelectedDepositPrice();
          if (depositPrice <= subtotal + 0.01) {
            effectiveDepositId = _selectedDepositId;
          } else {
            debugPrint(
                '⚠️ Skipping deposit_id=$_selectedDepositId: price $depositPrice > subtotal $subtotal');
          }
        }
        final calculationPayload = {
          calcItemsKey: calcItems,
          'discount': _orderDiscount,
          if (promoCodeId != null) 'promocode_id': promoCodeId,
          if (promoCodeValue != null && promoCodeValue.isNotEmpty)
            'promocodeValue': promoCodeValue,
          if (promoCodeValue != null && promoCodeValue.isNotEmpty)
            'promocode_name': promoCodeValue,
          if (promoDiscountType != null) 'discount_type': promoDiscountType,
          if (effectiveDepositId != null) 'deposit_id': effectiveDepositId,
        };
        try {
          final calcResponse = await orderService.calculateInvoice(
            calculationPayload,
          );
          payableTotal = pph.extractExpectedInvoiceTotal(
            calcResponse,
            orderTotal,
            isSalonMode: _isSalonMode,
          );
          // Guard against non-positive total: fallback to local cart total, never zero (zero rejects invoice).
          if (payableTotal <= 0 && orderTotal > 0) {
            payableTotal = orderTotal;
          }
          if ((payableTotal - payableTotal.roundToDouble()).abs() <= 0.02) {
            payableTotal = payableTotal.roundToDouble();
          } else {
            payableTotal = double.parse(payableTotal.toStringAsFixed(ApiConstants.digitsNumber));
          }
        } on ApiException catch (e) {
          if (e.statusCode == 422 &&
              !promoRemovedDueToExpiry &&
              pph.isExpiredPromoMessage(e.message)) {
            promoRemovedDueToExpiry = true;
            promoCodeId = null;
            promoCodeValue = null;
            promoDiscountType = null;
            clearActivePromoSelectionLocally();
            appliedDiscountAmount =
                _resolveEffectiveDiscountAmount(grossOrderTotal);
            orderTotal = (grossOrderTotal - appliedDiscountAmount)
                .clamp(0.0, double.infinity);
            payableTotal = double.parse(orderTotal.toStringAsFixed(ApiConstants.digitsNumber));
            Log.d('pay', '♻️ Promo expired while calculating invoice; continuing without promo');
          } else {
            // Non-blocking: some accounts reject calculate but accept create invoice payload.
            Log.w('pay', '⚠️ Calculate invoice failed, continuing to create invoice: $e');
          }
        } catch (e) {
          Log.w('pay', '⚠️ Calculate invoice failed, continuing to create invoice: $e');
        }
        normalizedPays = _buildNormalizedPays(
          pays,
          targetTotal: payableTotal,
        );
        normalizedPays = _buildUpdatePaysPayload(
          normalizedPays,
          payableTotal,
          preserveCardAmounts: isNearPayCardFlow,
        );
        final hasCardPayment = normalizedPays.any((pay) {
          final method = _normalizePayMethod(pay['pay_method']?.toString());
          return method == 'card';
        });
        if (_isProfileNearPayEnabled && hasCardPayment && !isNearPayCardFlow) {
          throw Exception('دفع البطاقة يجب أن يتم عبر NearPay فقط');
        }

        final invoiceItems = cartItemsForOrder.map(
          (item) {
            final addonIds = _toAddonIdList(item.selectedExtras);
            final effectiveDiscount = resolveItemApiDiscount(item);
            final salon = item.salonData ?? <String, dynamic>{};
            final isSalonItem = _isSalonMode && salon.isNotEmpty;

            if (isSalonItem) {
              return {
                'service_id': salon['service_id'] ?? int.tryParse(item.product.id),
                'service_name': salon['item_name'] ?? item.product.name,
                'employee_id': salon['employee_id'] ?? '',
                'quantity': item.quantity.round().clamp(1, 9999),
                'price': item.product.price,
                'unit_price': item.product.price,
                'modified_unit_price': salon['modified_unit_price'] ?? '',
                'package_service_id': salon['package_service_id'] ?? '',
                'date': salon['date'] ?? '',
                'time': salon['time'] ?? '',
                'session_numbers': salon['session_numbers'] ?? '',
                'booking_service_id': salon['booking_service_id'] ?? '',
                'discount': effectiveDiscount > 0 ? effectiveDiscount : '',
                'discount_type': '%',
                'addons': [],
              };
            }

            final qty = item.quantity > 0 ? item.quantity : 1.0;
            return {
              'item_name': item.product.name,
              'meal_id': int.tryParse(item.product.id) ?? item.product.id,
              'price': item.product.price * qty,
              'unitPrice': item.product.price,
              'modified_unit_price': null,
              'quantity': qty,
              'addons': addonIds,
              if (item.notes.isNotEmpty) 'note': item.notes,
              if (effectiveDiscount > 0) 'discount': effectiveDiscount,
              if (effectiveDiscount > 0) 'discount_type': '%',
            };
          },
        ).toList();
        final mealNameById = <String, String>{};
        final mealPriceById = <String, double>{};
        // Queue local cart discounts per meal_id — backend booking_meals may not echo them back.
        final mealDiscountQueue = <String, List<CartItem>>{};
        for (final item in cartItemsForOrder) {
          final mealId =
              (int.tryParse(item.product.id) ?? item.product.id).toString();
          mealNameById.putIfAbsent(mealId, () => item.product.name);
          mealPriceById.putIfAbsent(mealId, () => item.product.price);
          mealDiscountQueue.putIfAbsent(mealId, () => []).add(item);
        }

        final salesMeals = <Map<String, dynamic>>[];
        final usedBookingMealIds = <int>{};

        // Prefer booking_meals: contains canonical booking IDs.
        for (final meal in bookingMealsData) {
          final bookingMealIdRaw = meal['id'] ?? meal['booking_meal_id'];
          final bookingMealId = pph.toSafeInt(bookingMealIdRaw, fallback: 0);
          if (bookingMealId <= 0 ||
              usedBookingMealIds.contains(bookingMealId)) {
            continue;
          }

          final mealIdRaw = meal['meal_id'] ?? meal['product_id'];
          final mealIdStr = mealIdRaw?.toString() ?? '';
          final quantityRaw = pph.toSafeDouble(meal['quantity'], fallback: 1.0);
          final quantity = quantityRaw > 0 ? quantityRaw : 1.0;
          final unitPrice = pph.toSafeDouble(
            meal['unit_price'] ?? meal['price'] ?? mealPriceById[mealIdStr],
            fallback: 0.0,
          );
          final totalPrice = pph.toSafeDouble(
            meal['total'] ?? meal['price'],
            fallback: unitPrice * quantity,
          );

          // Combine per-item + order-level discounts as a single %.
          final localQueue = mealDiscountQueue[mealIdStr];
          final localItem =
              (localQueue != null && localQueue.isNotEmpty) ? localQueue.removeAt(0) : null;

          String discountValue = meal['discount']?.toString() ?? '';
          String discountTypeValue = meal['discount_type']?.toString() ?? '%';

          if (localItem != null) {
            final effectiveDiscount = resolveItemApiDiscount(localItem);
            if (effectiveDiscount > 0) {
              discountValue = effectiveDiscount.toString();
              discountTypeValue = '%';
            }
          }

          salesMeals.add({
            'booking_meal_id': bookingMealId,
            'meal_id': int.tryParse(mealIdStr) ?? mealIdRaw ?? mealIdStr,
            'quantity': quantity,
            'meal_name':
                meal['meal_name']?.toString() ?? mealNameById[mealIdStr] ?? '',
            'unit_price': unitPrice,
            'price': totalPrice,
            'total': totalPrice,
            'discount': discountValue,
            'discount_type': discountTypeValue,
            'notes': meal['notes']?.toString() ?? '',
          });
          usedBookingMealIds.add(bookingMealId);
        }

        // Do not fabricate sales_meals IDs from booking_products IDs; fall back to items/card payload.
        final hasValidSalesMealBookingIds = salesMeals.isNotEmpty &&
            salesMeals.every(
              (m) => pph.toSafeInt(m['booking_meal_id'], fallback: 0) > 0,
            );
        // Use normalizedPays (already adjusted to payableTotal); salesMeals totals can drift from backend.
        final paysForSalesMeals = normalizedPays;
        if (invoiceItems.isEmpty) {
          throw Exception('يجب أن تحتوي الفاتورة علي عناصر.');
        }

        final bookingIdValue = int.tryParse(orderId) ?? orderId;
        final orderIdValue =
            backendOrderId != null && int.tryParse(backendOrderId) != null
                ? int.parse(backendOrderId)
                : (backendOrderId ?? bookingIdValue);
        final bookingCustomerMap = pph.asStringKeyMap(bookingDataMap?['customer']);
        final customerIdValue = _selectedCustomer?.id ??
            bookingDataMap?['customer_id'] ??
            bookingCustomerMap?['id'];
        final promoFields = <String, dynamic>{
          if (promoCodeId != null) 'promocode_id': promoCodeId,
          if (promoCodeValue != null && promoCodeValue.isNotEmpty)
            'promocodeValue': promoCodeValue,
          if (promoCodeValue != null && promoCodeValue.isNotEmpty)
            'promocode_name': promoCodeValue,
          if (promoDiscountType != null) 'discount_type': promoDiscountType,
        };
        final isCashOnlyPayment = normalizedPays.length == 1 &&
            _normalizePayMethod(
                  normalizedPays.first['pay_method']?.toString(),
                ) ==
                'cash';
        Log.d('pay', 'creating invoice with order type=\$bookingOrderType');

        Map<String, dynamic> invoiceResponse;
        Object? lastInvoiceError;
        final attemptObjs = InvoiceAttemptsBuilder.build(
          orderService: orderService,
          isSalonMode: _isSalonMode,
          isCashOnlyPayment: isCashOnlyPayment,
          isNearPayCardFlow: isNearPayCardFlow,
          hasValidSalesMealBookingIds: hasValidSalesMealBookingIds,
          isCashEnabledForInvoice: _isMethodEnabledForInvoice('cash'),
          customerIdValue: customerIdValue,
          bookingIdValue: bookingIdValue,
          orderIdValue: orderIdValue,
          primaryBookingProductId: primaryBookingProductId,
          effectiveDepositId: effectiveDepositId,
          promoFields: promoFields,
          dateStr: dateStr,
          bookingOrderType: bookingOrderType,
          carNumber: carNumber,
          selectedTableForOrder: selectedTableForOrder,
          payableTotal: payableTotal,
          normalizedPays: normalizedPays,
          paysForSalesMeals: paysForSalesMeals,
          invoiceItems: invoiceItems,
          salesMeals: salesMeals,
          bookingProductIds: bookingProductIds,
        );
        // Backwards-compatible map representation for the retry loop's in-place payload mutation.
        final attempts = attemptObjs
            .map((a) => <String, dynamic>{
                  'label': a.label,
                  'run': a.run,
                  'payload': a.payload,
                })
            .toList();

        Map<String, dynamic>? resolvedInvoice;
        String? resolvedAttemptLabel;
        double? resolvedAttemptPaysTotal;
        var checkedForExistingInvoice = false;
        Future<bool> tryResolveExistingInvoice() async {
          try {
            final bookingDetails =
                await orderService.getBookingDetails(orderId);
            final bookingDetailsMap = pph.asStringKeyMap(bookingDetails['data']);
            final hasInvoice = bookingDetailsMap?['has_invoice'] == true;
            final existingInvoiceId =
                bookingDetailsMap?['invoice_id']?.toString();
            if (hasInvoice &&
                existingInvoiceId != null &&
                existingInvoiceId.isNotEmpty) {
              resolvedInvoice =
                  await orderService.getInvoice(existingInvoiceId);
              resolvedAttemptLabel = 'existing_invoice_on_booking';
              Log.d('pay', 'ℹ️ booking already has invoice, reusing invoice_id=$existingInvoiceId');
              return true;
            }
          } catch (lookupError) {
            Log.e('pay', '⚠️ booking already used but existing invoice lookup failed: $lookupError');
          }
          return false;
        }

        List<Map<String, dynamic>> normalizePaysToExactTotal(
          dynamic rawPays,
          double expectedTotal,
        ) {
          final paysList = rawPays is List
              ? rawPays
                  .whereType<Map>()
                  .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
                  .toList()
              : <Map<String, dynamic>>[];
          if (paysList.isEmpty) {
            return [
              {'pay_method': 'cash', 'amount': expectedTotal},
            ];
          }

          final normalized = <Map<String, dynamic>>[];
          for (var i = 0; i < paysList.length; i++) {
            final pay = paysList[i];
            final method = _normalizePayMethod(pay['pay_method']?.toString());
            final amount = (pay['amount'] as num?)?.toDouble() ??
                double.tryParse(pay['amount']?.toString() ?? '') ??
                0.0;
            normalized.add({
              ...pay,
              'pay_method': method,
              'amount': amount,
              if (pay['index'] == null) 'index': i,
            });
          }

          final adjusted = _buildUpdatePaysPayload(
            normalized,
            expectedTotal,
            preserveCardAmounts: isNearPayCardFlow,
          );
          for (var i = 0; i < adjusted.length; i++) {
            final method = adjusted[i]['pay_method']?.toString() ?? 'cash';
            adjusted[i] = {
              ...normalized[i],
              'pay_method': method,
              'amount': adjusted[i]['amount'],
              if (normalized[i]['index'] == null) 'index': i,
            };
          }
          return adjusted;
        }

        void stripPromoFromAllAttemptPayloads(double targetTotal) {
          for (final attempt in attempts) {
            final payload = attempt['payload'];
            if (payload is! Map<String, dynamic>) continue;
            pph.stripPromoFieldsFromPayload(payload);
            if (payload.containsKey('pays')) {
              payload['pays'] = normalizePaysToExactTotal(
                payload['pays'],
                targetTotal,
              );
            }
          }
        }

        final retriedAfterPaysAdjustment = <String>{};
        for (var i = 0; i < attempts.length; i++) {
          final attempt = attempts[i];
          final attemptLabel =
              attempt['label']?.toString() ?? 'unknown_attempt';
          final runner =
              attempt['run'] as Future<Map<String, dynamic>> Function();
          final payload = attempt['payload'];
          // Do NOT log full payload (PII + transaction details) — log label + payload-size only.
          try {
            final payloadSize = payload is Map
                ? '${payload.length} keys'
                : '${payload.toString().length} chars';
            Log.d('pay', 'createInvoice attempt [$attemptLabel] payload=$payloadSize');
          } catch (e) {
            Log.d('catch', 'non-fatal: $e');
            Log.d('pay', 'createInvoice attempt [$attemptLabel]');
          }
          try {
            resolvedInvoice = await runner();
            resolvedAttemptLabel = attemptLabel;
            if (payload is Map<String, dynamic>) {
              final copiedPays = pph.clonePaysList(payload['pays']);
              if (copiedPays.isNotEmpty) {
                final paysTotal = pph.sumPaysAmounts(
                  copiedPays,
                  digits: ApiConstants.digitsNumber,
                );
                if (paysTotal > 0) {
                  resolvedAttemptPaysTotal = paysTotal;
                }
              }
            }
            Log.d('pay', 'createInvoice success via \$attemptLabel');
            break;
          } on ApiException catch (e) {
            lastInvoiceError = e;
            final status = e.statusCode ?? 0;
            if (status == 401 || status == 403) rethrow;
            if (!checkedForExistingInvoice) {
              checkedForExistingInvoice = true;
              if (await tryResolveExistingInvoice()) {
                break;
              }
            }

            if (status == 422 &&
                !promoRemovedDueToExpiry &&
                pph.isExpiredPromoMessage(e.message)) {
              promoRemovedDueToExpiry = true;
              promoCodeId = null;
              promoCodeValue = null;
              promoDiscountType = null;
              clearActivePromoSelectionLocally();
              appliedDiscountAmount =
                  _resolveEffectiveDiscountAmount(grossOrderTotal);
              orderTotal = (grossOrderTotal - appliedDiscountAmount)
                  .clamp(0.0, double.infinity);
              payableTotal = double.parse(orderTotal.toStringAsFixed(ApiConstants.digitsNumber));
              normalizedPays = _buildNormalizedPays(
                pays,
                targetTotal: payableTotal,
              );
              normalizedPays = _buildUpdatePaysPayload(
                normalizedPays,
                payableTotal,
                preserveCardAmounts: isNearPayCardFlow,
              );
              stripPromoFromAllAttemptPayloads(payableTotal);
              retriedAfterPaysAdjustment.clear();
              Log.d('pay', '♻️ Promo expired during invoice creation; removed promo and retrying without it');
              i--;
              continue;
            }

            final expectedTotal =
                pph.extractExpectedPaysTotalFromMessage(e.message);
            if (status == 422 &&
                expectedTotal != null &&
                payload is Map<String, dynamic> &&
                payload.containsKey('pays') &&
                !retriedAfterPaysAdjustment.contains(attemptLabel)) {
              final currentPays = payload['pays'];
              final adjustedPays = normalizePaysToExactTotal(
                currentPays,
                expectedTotal,
              );
              payload['pays'] = adjustedPays;
              retriedAfterPaysAdjustment.add(attemptLabel);
              Log.d('pay', '♻️ Adjusted pays for [$attemptLabel] to match backend total=$expectedTotal and retrying same attempt');
              i--;
              continue;
            }

            Log.w('pay',
                'createInvoice failed [$attemptLabel] status=$status '
                'message=${e.message} '
                'payloadKeys=${payload is Map ? payload.keys.toList() : 'unknown'}');
          } catch (e) {
            lastInvoiceError = e;
            Log.w('pay', 'createInvoice failed [\$attemptLabel]', error: e);
          }
        }

        if (resolvedInvoice == null) {
          if (lastInvoiceError is ApiException) {
            final normalizedMessage = lastInvoiceError.message;
            final bookingAlreadyUsed =
                normalizedMessage.contains('رقم الحجز') &&
                    (normalizedMessage.contains('مستخدمة') ||
                        normalizedMessage.contains('مُستخدمة') ||
                        normalizedMessage.contains('مستخدم'));

            if (bookingAlreadyUsed) {
              try {
                final bookingDetails =
                    await orderService.getBookingDetails(orderId);
                final bookingDetailsMap =
                    pph.asStringKeyMap(bookingDetails['data']);
                final hasInvoice = bookingDetailsMap?['has_invoice'] == true;
                final existingInvoiceId =
                    bookingDetailsMap?['invoice_id']?.toString();
                if (hasInvoice &&
                    existingInvoiceId != null &&
                    existingInvoiceId.isNotEmpty) {
                  resolvedInvoice =
                      await orderService.getInvoice(existingInvoiceId);
                  resolvedAttemptLabel = 'existing_invoice_on_booking';
                  Log.d('pay', 'ℹ️ booking already has invoice, reusing invoice_id=$existingInvoiceId');
                }
              } catch (lookupError) {
                Log.e('pay', '⚠️ booking already used but existing invoice lookup failed: $lookupError');
              }
            }

            if (resolvedInvoice == null) {
              throw lastInvoiceError;
            }
          }
          if (resolvedInvoice == null) {
            throw Exception('فشل إنشاء الفاتورة بعد جميع محاولات الربط');
          }
        }
        if (resolvedAttemptLabel != null) {
          Log.d('pay', 'invoice creation strategy = \$resolvedAttemptLabel');
        }
        invoiceResponse = resolvedInvoice!;
        invoiceNumber = invoiceResponse['data']?['invoice_number']?.toString();
        final invoiceDataMap = pph.asStringKeyMap(invoiceResponse['data']);
        invoiceId = invoiceDataMap?['id']?.toString();
        final rawInvoicePayload = invoiceResponse['data'];
        if (rawInvoicePayload is Map<String, dynamic>) {
          invoicePayload = rawInvoicePayload;
        } else if (rawInvoicePayload is Map) {
          invoicePayload = rawInvoicePayload
              .map((key, value) => MapEntry(key.toString(), value));
        }

        if (invoiceId != null && invoiceId.isNotEmpty) {
          // Salon-only: notify invoices/orders screens immediately to skip 15s poll.
          if (_isSalonMode) {
            try {
              getIt<SalonInvoiceEvents>().emitCreated(
                invoiceId: invoiceId,
                invoiceNumber: invoiceNumber,
                bookingId: orderId,
                orderNumber: displayOrderRef,
              );
            } catch (e) {
              Log.w('pay', 'failed to emit SalonInvoiceCreated event', error: e);
            }
          }

          final resolvedPaysTotal = resolvedAttemptPaysTotal;
          final finalInvoiceTotal =
              (resolvedPaysTotal != null && resolvedPaysTotal > 0)
                  ? resolvedPaysTotal
                  : pph.extractExpectedInvoiceTotal(
                      invoiceResponse,
                      payableTotal,
                      isSalonMode: _isSalonMode,
                    );
          final updatePaysSource = normalizedPays;
          var updatePaysPayload =
              _buildUpdatePaysPayload(updatePaysSource, finalInvoiceTotal);
          final skipUpdatePays = <String>{
            'multipart_backend_exact',
            'json_cash_with_sales_meals',
            'multipart_cash_with_sales_meals',
            'json_cash_postman_exact',
            'multipart_cash_postman_exact',
            'json_postman_pays_only',
            'multipart_postman_pays_only',
            // Orders-section slim payload: updatePays risks 422→backend cancels just-created invoice.
            'json_orders_section_slim',
            'multipart_orders_section_slim',
            'existing_invoice_on_booking',
          }.contains(resolvedAttemptLabel);

          final invoiceIdValue = invoiceId;
          unawaited(() async {
            if (invoiceIdValue.isEmpty) {
              return;
            }
            try {
              await orderService.updateInvoiceDate(
                invoiceId: invoiceIdValue,
                date: dateStr,
              );

              if (skipUpdatePays) {
                Log.d('pay', 'ℹ️ Skipping updatePays for invoice_id=$invoiceId to avoid duplicate/cancelled invoices on backend.');
                return;
              }

              await orderService.updateInvoicePays(
                invoiceIdValue,
                pays: updatePaysPayload,
                date: dateStr,
              );
            } on ApiException catch (e) {
              if (skipUpdatePays) return;
              final expectedTotal =
                  pph.extractExpectedPaysTotalFromMessage(e.message);
              if ((e.statusCode ?? 0) == 422 && expectedTotal != null) {
                updatePaysPayload = _buildUpdatePaysPayload(
                  updatePaysSource,
                  expectedTotal,
                );
                Log.d('pay', '♻️ Adjusted updatePays payload to backend total=$expectedTotal and retrying');
                try {
                  await orderService.updateInvoicePays(
                    invoiceIdValue,
                    pays: updatePaysPayload,
                    date: dateStr,
                  );
                } on ApiException catch (retryError) {
                  final retryExpectedTotal =
                      pph.extractExpectedPaysTotalFromMessage(
                            retryError.message,
                          ) ??
                          expectedTotal;
                  if ((retryError.statusCode ?? 0) == 422 &&
                      retryExpectedTotal > 0) {
                    final preferredMethod =
                        updatePaysPayload.first['pay_method']?.toString() ??
                            normalizedPays
                                .firstWhere(
                                  (p) =>
                                      p['pay_method']
                                          ?.toString()
                                          .trim()
                                          .isNotEmpty ==
                                      true,
                                  orElse: () => {'pay_method': 'cash'},
                                )['pay_method']
                                .toString();
                    final forcedPayload = _buildUpdatePaysPayload(
                      [
                        {
                          'name': preferredMethod == 'card'
                              ? 'البطاقة'
                              : 'دفع نقدي',
                          'pay_method': preferredMethod,
                          'amount': retryExpectedTotal,
                          'index': 0,
                        },
                      ],
                      retryExpectedTotal,
                    );
                    Log.d('pay', '♻️ Final updatePays fallback with exact backend total=$retryExpectedTotal method=$preferredMethod');
                    await orderService.updateInvoicePays(
                      invoiceIdValue,
                      pays: forcedPayload,
                      date: dateStr,
                    );
                  }
                }
              }
            } catch (e) {
              Log.w('pay', '⚠️ updateInvoicePays failed for invoice_id=$invoiceId: $e');
            }
          }());
        }
      }

      if (type == 'payment') {
        unawaited(_recordCashTransaction(normalizedPays));
      }

      // Capture table name before table release clears it.
      final capturedTableNumber = _selectedTable?.number
          ?? _lastSelectedTable?.number
          ?? selectedTableForOrder?.number;

      if (type == 'payment') {
        unawaited(_releaseTableAfterPayment(
          orderId: orderId,
          selectedTableForOrder: selectedTableForOrder,
          bookingDataMap: bookingDataMap,
          bookingNode: bookingNode,
        ));
      }

      // Debug-only discount snapshot (PII-adjacent; strips in release via Log).
      Log.d('pay',
          'discount snapshot applied=$appliedDiscountAmount '
          'gross=$grossOrderTotal net=$orderTotal isFree=$_isOrderFree');

      final printTimerStart = DateTime.now();
      debugPrint('⏱️ [PRINT_TIMER] START enrichment');

      // Use server-confirmed payableTotal and displayOrderRef (daily number), not orderTotal/orderId.
      final providerTypeCode = _resolveDeliveryProviderTypeCode();
      final receiptOrderType = providerTypeCode ??
          ((_isMenuListActive && _activeMenuListName.isNotEmpty)
              ? '$bookingOrderType ($_activeMenuListName)'
              : bookingOrderType);
      final enrichedPayload = await _resolveInvoicePayloadForPreview(
        invoiceId,
        invoicePayload,
        orderService: orderService,
      );
      if (enrichedPayload != null) {
        invoicePayload = enrichedPayload;
      }

      await _enrichOrderItemsWithTranslations(
        orderItemsSnapshot: orderItemsSnapshot,
        invoicePayload: invoicePayload,
        orderId: orderId,
      );

      final receiptData = _buildOrderReceiptData(
        orderId: displayOrderRef,
        invoiceNumber: invoiceNumber,
        orderItems: orderItemsSnapshot,
        orderTotal: payableTotal,
        orderType: receiptOrderType,
        type: type,
        pays: normalizedPays,
        invoicePayload: invoicePayload,
        carNumber: carNumber,
        tableNumber: capturedTableNumber,
        discountAmount:
            _isOrderFree ? grossOrderTotal
            : (appliedDiscountAmount > 0 ? appliedDiscountAmount : null),
        discountPercentage: _activePromoCode?.type == DiscountType.percentage
            ? _activePromoCode?.discount
            : (_isOrderFree ? 100.0
                : (_orderDiscountType == DiscountType.percentage && _orderDiscount > 0
                    ? _orderDiscount : null)),
        discountName: _isOrderFree
            ? _trUi('طلب مجاني', 'Free Order')
            : (_activePromoCode != null
                ? '${_trUi('كوبون', 'Coupon')}: ${_activePromoCode!.code}'
                : (_orderDiscount > 0
                    ? (_orderDiscountType == DiscountType.percentage
                        ? '${_trUi('خصم', 'Discount')} ${_orderDiscount.toStringAsFixed(0)}%'
                        : _trUi('خصم يدوي', 'Manual Discount'))
                    : null)),
      );
      unawaited(() async {
        // Push final KDS payload with resolved invoice/promo/cash-float context.
        if (_isKdsEnabled && kdsOrderDispatched) {
          try {
            displayService.sendOrderToKitchen(
              orderId: orderId,
              orderNumber: displayOrderRef,
              orderType: bookingOrderType,
              items: kdsItemsPayload,
              note: _orderNotesController.text.isNotEmpty
                  ? _orderNotesController.text
                  : null,
              total: orderTotal,
              invoice: _buildKdsInvoicePayload(
                bookingId: orderId,
                orderId: backendOrderId,
                orderNumber: displayOrderRef,
                invoiceId: invoiceId,
                invoiceNumber: invoiceNumber,
                type: type,
                orderTotal: orderTotal,
                grossOrderTotal: grossOrderTotal,
                discountAmount: appliedDiscountAmount,
                promoCodeId: promoCodeId,
                promoCode: promoCodeValue,
                promoDiscountType: promoDiscountType,
                orderItems: orderItemsSnapshot,
                cashFloatSnapshot: _buildCashFloatSnapshot(),
              ),
              switchMode: false,
            );
          } catch (e) {
            Log.w('pay', 'failed to push final KDS payload for #\$orderId', error: e);
          }
        }

        if (_isKdsEnabled && !kdsScreenReceivedOrder) {
          try {
            final fallbackDispatchAcked = await _dispatchOrderToKdsWithAck(
              displayService: displayService,
              orderId: orderId,
              orderNumber: displayOrderRef,
              orderType: bookingOrderType,
              items: kdsItemsPayload,
              note: _orderNotesController.text.isNotEmpty
                  ? _orderNotesController.text
                  : null,
              total: orderTotal,
              invoice: _buildKdsInvoicePayload(
                bookingId: orderId,
                orderId: backendOrderId,
                orderNumber: displayOrderRef,
                invoiceId: invoiceId,
                invoiceNumber: invoiceNumber,
                type: type,
                orderTotal: orderTotal,
                grossOrderTotal: grossOrderTotal,
                discountAmount: appliedDiscountAmount,
                promoCodeId: promoCodeId,
                promoCode: promoCodeValue,
                promoDiscountType: promoDiscountType,
                orderItems: orderItemsSnapshot,
                cashFloatSnapshot: _buildCashFloatSnapshot(),
              ),
            );
            kdsOrderDispatched = true;
            kdsScreenReceivedOrder =
                kdsScreenReceivedOrder || fallbackDispatchAcked;
            if (fallbackDispatchAcked) {
              Log.d('pay', 'NEW_ORDER fallback dispatch to KDS (ACK) #\$orderId');
            } else {
              Log.w('pay', '⚠️ Fallback NEW_ORDER dispatch sent but ACK still not confirmed: #$orderId');
            }
          } catch (e) {
            Log.w('pay', 'failed fallback NEW_ORDER #\$orderId', error: e);
          }
        }

        final kdsHandledThisPayment =
            type == 'payment' && kdsScreenReceivedOrder;
        final shouldDispatchKitchenPrint =
            !kdsHandledThisPayment || _allowPrintWithKds;
        if (shouldDispatchKitchenPrint) {
          try {
            // Enrich kitchen items with bilingual names: invoicePayload then booking details fallback.
            List<dynamic> apiItemsList = const [];

            final invoiceItems = (invoicePayload?['items']) ??
                (invoicePayload?['sales_meals']) ??
                (invoicePayload?['meals']);
            if (invoiceItems is List && invoiceItems.isNotEmpty) {
              apiItemsList = invoiceItems;
              Log.d('pay', '🔍 ENRICH: using invoicePayload items (${invoiceItems.length})');
            } else {
              Log.d('pay', '🔍 ENRICH: invoicePayload is ${invoicePayload == null ? "NULL" : "empty items"}');
            }

            if (apiItemsList.isEmpty && orderId.isNotEmpty) {
              try {
                final orderService = getIt<OrderService>();
                final bookingDetails = await orderService.getBookingDetails(orderId);
                final bookingData = bookingDetails['data'] ?? bookingDetails;
                final bookingNode = (bookingData is Map && bookingData['booking'] is Map)
                    ? bookingData['booking']
                    : bookingData;
                Log.d('pay', '🔍 ENRICH: bookingNode keys=${bookingNode is Map ? bookingNode.keys.toList() : "NOT_MAP"}');
                final bookingItems = (bookingNode is Map)
                    ? (bookingNode['meals'] ??
                        bookingNode['items'] ??
                        bookingNode['sales_meals'] ??
                        bookingNode['booking_meals'] ??
                        bookingNode['card'])
                    : null;
                if (bookingItems is List && bookingItems.isNotEmpty) {
                  apiItemsList = bookingItems;
                  final firstItem = bookingItems[0];
                  Log.d('pay', '🔍 ENRICH: booking items found (${bookingItems.length}), first item keys=${firstItem is Map ? firstItem.keys.toList() : "NOT_MAP"}');
                  if (firstItem is Map) {
                    Log.d('pay',
                        'enrich first item item_name="${firstItem['item_name']}" '
                        'meal_name="${firstItem['meal_name']}" '
                        'name="${firstItem['name']}" '
                        'name_en="${firstItem['name_en']}"');
                  }
                } else {
                  Log.d('pay', '🔍 ENRICH: no booking items found (bookingItems=${bookingItems?.runtimeType})');
                }
              } catch (e) {
                Log.w('pay', 'could not fetch booking details for bilingual names', error: e);
              }
            }

            final String kitchenPriLang = printerLanguageSettings.primary;

            final enrichedItems = orderItemsSnapshot.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = Map<String, dynamic>.from(entry.value);

              if (idx < apiItemsList.length) {
                final apiItem = apiItemsList[idx];
                if (apiItem is Map) {
                  final mealTranslations = apiItem['meal_name_translations'];
                  if (mealTranslations is Map) {
                    final existing = item['localizedNames'];
                    final merged = existing is Map
                        ? Map<String, String>.from(existing.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')))
                        : <String, String>{};
                    for (final te in mealTranslations.entries) {
                      final val = te.value?.toString().trim() ?? '';
                      if (val.isNotEmpty) {
                        merged[te.key.toString()] = val;
                      }
                    }
                    item['localizedNames'] = merged;
                    item['meal_name_translations'] = mealTranslations;
                  }

                  final addonsTranslations = apiItem['addons_translations'];
                  if (addonsTranslations is List) {
                    item['addons_translations'] = addonsTranslations;
                  }

                  // Try combined bilingual item_name "عربي - English".
                  final currentNameEn = item['nameEn']?.toString().trim() ?? '';
                  if (currentNameEn.isEmpty) {
                    final apiName = (apiItem['item_name'] ??
                        apiItem['meal_name'] ??
                        apiItem['name'])?.toString() ?? '';
                    if (apiName.contains(' - ')) {
                      item['nameAr'] = apiName.split(' - ').first.trim();
                      item['nameEn'] = apiName.split(' - ').last.trim();
                    }
                    if ((item['nameEn']?.toString().trim() ?? '').isEmpty) {
                      final explicitEn = (apiItem['name_en'] ??
                          apiItem['item_name_en'] ??
                          apiItem['meal_name_en'])?.toString().trim() ?? '';
                      if (explicitEn.isNotEmpty) {
                        item['nameEn'] = explicitEn;
                      }
                    }
                  }
                }
              }

              final localizedNames = item['localizedNames'];
              if (localizedNames is Map) {
                final resolvedName = localizedNames[kitchenPriLang]?.toString().trim() ?? '';
                if (resolvedName.isNotEmpty) {
                  item['name'] = resolvedName;
                } else if (kitchenPriLang == 'en' && (item['nameEn']?.toString().trim() ?? '').isNotEmpty) {
                  item['name'] = item['nameEn'];
                }
              }

              return item;
            }).toList();

            // Salon turn slip uses daily-only value; displayOrderRef would leak booking_id when daily is empty.
            await _triggerKitchenPrint(
              orderId: orderId,
              invoiceNumber: invoiceNumber,
              orderItems: enrichedItems,
              dailyOrderNumber: _isSalonMode
                  ? ((backendDailyOrderNumber?.isNotEmpty ?? false)
                      ? backendDailyOrderNumber
                      : null)
                  : displayOrderRef,
              capturedTableNumber: capturedTableNumber,
              carNumber: carNumber,
              // Cart already cleared by fast-path; pass pre-clear snapshot so salon turn slip sees services.
              salonCartSnapshot: cartItemsForOrder,
            );
          } catch (e) {
            Log.d('MainScreenPaymentProcess', 'kitchen printer dispatch failed (non-fatal): $e');
          }
        } else {
          Log.d('pay', 'ℹ️ Kitchen printer dispatch skipped for #$orderId because KDS handled this paid order and print-with-KDS is disabled.');
        }

        if (_isCdsEnabled &&
            (displayService.isConnected || displayService.isPresentationActive)) {
          displayService.clearCart();
        }
      }());

      if (type == 'payment') {
        final elapsed = DateTime.now().difference(printTimerStart).inMilliseconds;
        debugPrint('⏱️ [PRINT_TIMER] PRINT after ${elapsed}ms (enrichment + build)');
        unawaited(
          _autoPrintReceiptCopies(
            receiptData: receiptData,
            invoiceId: invoiceId,
          ),
        );
      }
      } catch (invoiceError) {
        // Booking already succeeded — show warning, allow user to retry invoice from orders.
        if (mounted) {
          debugPrint('⚠️ Post-booking error (booking OK, invoice failed): $invoiceError');
          UiFeedback.warning(context, _trUi(
                  'تم حفظ الطلب بنجاح ولكن تعذر إصدار الفاتورة. يمكنك إصدارها من شاشة الطلبات.',
                  'Order saved but invoice creation failed. You can create it from the orders screen.',
                ));
        }

        // NearPay already captured the card — print a minimal receipt; formal invoice can be issued later.
        if (isNearPayCardFlow && type == 'payment' && mounted) {
          try {
            final fallbackPays = _buildNormalizedPays(
              pays,
              targetTotal: payableTotal,
            );
            final fallbackReceipt = _buildOrderReceiptData(
              orderId: displayOrderRef,
              invoiceNumber: null,
              orderItems: orderItemsSnapshot,
              orderTotal: payableTotal,
              orderType: bookingOrderType,
              type: type,
              pays: fallbackPays,
              invoicePayload: null,
              carNumber: carNumber,
              tableNumber: _selectedTable?.number ?? _lastSelectedTable?.number,
            );
            unawaited(_autoPrintReceiptCopies(
              receiptData: fallbackReceipt,
              invoiceId: null,
            ));
            debugPrint(
              '🧾 NearPay fallback receipt dispatched (invoice failed but card was charged).',
            );
          } catch (e) {
            debugPrint('⚠️ NearPay fallback receipt build failed: $e');
          }
        }
      }
    } catch (e) {
      if (showLoadingOverlay && mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Restore optimistic cart clear so user can fix and retry after booking failure.
      if (optimisticClearSnapshot != null && mounted) {
        setState(() {
          _cart
            ..clear()
            ..addAll(optimisticClearSnapshot!);
        });
        _syncDisplayCartFromMain();
      }

      if (mounted) {
        // Backend rejects 422 "الحقل العميل مطلوب" when the branch enforces
        // customer selection. Retry would fail identically — guide the user
        // to pick a customer instead of looping the failure.
        final responseErrors = e is ApiException && e.responseBody is Map
            ? (e.responseBody as Map)['errors']
            : null;
        final isMissingCustomer = e is ApiException &&
            e.statusCode == 422 &&
            _selectedCustomer == null &&
            (e.message.contains('العميل') ||
                (responseErrors is Map &&
                    responseErrors.containsKey('customer_id')));
        if (isMissingCustomer) {
          // Persist so the settings toggle locks ON and the cart label flips
          // to "* required" without waiting for another failed booking.
          unawaited(_markCustomerRequiredByBackend());
          UiFeedback.warning(
            context,
            _trUi(
              'هذا الفرع يتطلب اختيار العميل قبل إنشاء الطلب.',
              'This branch requires choosing a customer before creating the order.',
            ),
          );
        } else {
          final userMessage = ErrorHandler.toUserMessage(
            e,
            fallback: 'تعذر حفظ الطلب حاليًا. حاول مرة أخرى.',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 3),
              content: Text(userMessage),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'إعادة المحاولة',
                textColor: Colors.white,
                onPressed: () {
                  unawaited(
                    _processPayment(
                      type: type,
                      pays: pays,
                      showLoadingOverlay: showLoadingOverlay,
                      showSuccessDialog: showSuccessDialog,
                      clearCartOnSuccess: clearCartOnSuccess,
                      isNearPayCardFlow: isNearPayCardFlow,
                    ),
                  );
                },
              ),
            ),
          );
        }
      }
    }
  }
}
