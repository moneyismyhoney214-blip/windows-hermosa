// Kitchen-print entry triggers + _SalonTurnRow class.
// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, library_private_types_in_public_api
part of '../main_screen.dart';

extension MainScreenKitchenPrint on _MainScreenState {
  Future<void> _triggerKitchenPrint({
    required String orderId,
    String? invoiceNumber,
    required List<Map<String, dynamic>> orderItems,
    String? dailyOrderNumber,
    String? capturedTableNumber,
    String? carNumber,
    List<CartItem>? salonCartSnapshot,
  }) async {
    // Salon mode replaces the kitchen ticket with one turn slip per booked
    // service (طابعة الأدوار). Delegate BEFORE the `_printKitchenInvoices`
    // guard — the cashier setting toggles restaurant kitchen tickets, not
    // salon turn slips. Restaurant flow keeps its original gating.
    if (_isSalonMode) {
      await _triggerSalonTurnPrint(
        orderId: orderId,
        invoiceNumber: invoiceNumber,
        dailyOrderNumber: dailyOrderNumber,
        cartSnapshot: salonCartSnapshot,
      );
      return;
    }

    if (!_printKitchenInvoices) return;

    List<DeviceConfig> kitchenPrinters = const [];
    try {
      final deviceService = getIt<DeviceService>();
      kitchenPrinters =
          (await deviceService.getDevices()).where(_isUsablePrinter).toList();
    } catch (e) {
      debugPrint('⚠️ Failed to load printers for kitchen print: $e');
    }
    if (kitchenPrinters.isEmpty) {
      kitchenPrinters =
          _devices.where(_isUsablePrinter).toList(growable: false);
    }
    if (kitchenPrinters.isEmpty) {
      _showMissingPrinterSnackBar();
      return;
    }

    final orchestrator = getIt<PrintOrchestratorService>();
    final orderService = getIt<OrderService>();
    final categoryRouteRegistry = getIt<CategoryPrinterRouteRegistry>();
    final kitchenRouteRegistry = getIt<KitchenPrinterRouteRegistry>();
    final roleRegistry = getIt<PrinterRoleRegistry>();
    await Future.wait(<Future<void>>[
      categoryRouteRegistry.initialize(),
      kitchenRouteRegistry.initialize(),
      roleRegistry.initialize(),
    ]);

    // Kitchen tickets go ONLY to kitchen/kds/bar printers — never cashier or general.
    kitchenPrinters = kitchenPrinters.where((p) {
      final role = roleRegistry.resolveRole(p);
      return role == PrinterRole.kitchen ||
          role == PrinterRole.kds ||
          role == PrinterRole.bar;
    }).toList(growable: false);
    if (kitchenPrinters.isEmpty) {
      debugPrint('ℹ️ No kitchen-role printer found, skipping kitchen ticket');
      return;
    }
    final hasCategoryAssignments = categoryRouteRegistry.hasAnyAssignments();

    final generalNote = _orderNotesController.text.trim().isEmpty
        ? null
        : _orderNotesController.text.trim();
    final effectiveOrderNumber = (dailyOrderNumber?.trim().isNotEmpty == true)
        ? dailyOrderNumber!
        : '#$orderId';
    final String cashierName = _userName;

    // Build kitchen order type: prefer a canonical delivery-provider code
    // (e.g. `hungerstation_delivery`) so the kitchen ticket translator shows
    // "هنقر ستيشن (توصيل)" instead of a raw `services (HungerStation)` string.
    final kitchenProviderTypeCode = _resolveDeliveryProviderTypeCode();
    final kitchenOrderType = kitchenProviderTypeCode ??
        ((_isMenuListActive && _activeMenuListName.isNotEmpty)
            ? '$_selectedOrderType ($_activeMenuListName)'
            : _selectedOrderType);
    final kitchenSuffix = (_isMenuListActive && _activeMenuListName.isNotEmpty)
        ? _activeMenuListName
        : '';

    final baseTemplateMeta = _composeKitchenTemplateMeta(
      fallbackOrderNumber: effectiveOrderNumber,
      fallbackOrderType: kitchenOrderType,
      fallbackInvoiceNumber: invoiceNumber,
      fallbackNote: generalNote,
    );
    final kitchenIds = _resolveKitchenIdsForReceiptGeneration();
    final localFallbackItems = orderItems
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

    final dispatchedBySections = await _dispatchKitchenPrintFromBookingSections(
      orderService: orderService,
      orchestrator: orchestrator,
      categoryRegistry: categoryRouteRegistry,
      printers: kitchenPrinters,
      orderId: orderId,
      fallbackOrderType: kitchenOrderType,
      fallbackNote: generalNote,
      fallbackInvoiceNumber: invoiceNumber,
      baseTemplateMeta: baseTemplateMeta,
      clientName: _selectedCustomer?.name,
      clientPhone: _selectedCustomer?.mobile,
      tableNumber: capturedTableNumber,
      carNumber: carNumber,
    );
    if (dispatchedBySections) return;

    var printedAny = false;
    var apiAttempted = false;
    var onlyKnownSkipErrors = true;

    final String? clientName = _selectedCustomer?.name;
    final String? clientPhone = _selectedCustomer?.mobile;
    final String? tableNumber = capturedTableNumber;

    for (final kitchenId in kitchenIds) {
      apiAttempted = true;

      Map<String, dynamic> kitchenReceipt;
      try {
        kitchenReceipt = await orderService.generateKitchenReceiptByBooking(
          bookingId: orderId,
          kitchenId: kitchenId,
        );
      } catch (e) {
        final isKnownSkipError =
            _isKitchenAlreadySentError(e) || _isNoKitchenMealsError(e);
        if (isKnownSkipError) {
          Log.d('kitchen-print',
              'generate-by-booking skipped for booking=$orderId '
              'kitchen_id=$kitchenId (already sent / no meals)');
          continue;
        }
        onlyKnownSkipErrors = false;
        Log.w('kitchen-print',
            'generate-by-booking failed for booking=$orderId '
            'kitchen_id=$kitchenId', error: e);
        continue;
      }

      final resolvedPayload = _resolveKitchenPrintPayloadFromApi(
        apiResponse: kitchenReceipt,
        fallbackOrderId: orderId,
        fallbackOrderType: _selectedOrderType,
        fallbackItems: hasCategoryAssignments
            ? localFallbackItems
            : const <Map<String, dynamic>>[],
        fallbackNote: generalNote,
        fallbackInvoiceNumber: invoiceNumber,
      );

      final resolvedItems =
          (resolvedPayload['items'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map>()
              .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
              .toList(growable: false);

      final resolvedOrderNumber = effectiveOrderNumber;
      final rawApiOrderType =
          resolvedPayload['orderType']?.toString() ?? _selectedOrderType;
      // Append menu list / table suffix same as invoice
      final resolvedOrderType = kitchenSuffix.isNotEmpty
          ? '$rawApiOrderType ($kitchenSuffix)'
          : rawApiOrderType;
      final resolvedNote = resolvedPayload['note']?.toString() ?? generalNote;
      final resolvedInvoiceNumber =
          resolvedPayload['invoiceNumber']?.toString() ?? invoiceNumber;
      final resolvedTemplateMetaRaw = _asStringMap(
        resolvedPayload['templateMeta'],
      );
      final resolvedTemplateMeta = <String, dynamic>{
        ...baseTemplateMeta,
        if (resolvedTemplateMetaRaw != null) ...resolvedTemplateMetaRaw,
      };

      if (hasCategoryAssignments) {
        final itemsForCategoryDispatch =
            resolvedItems.isNotEmpty ? resolvedItems : localFallbackItems;
        try {
          final delivered = await _dispatchKitchenPrintByCategoryRouting(
            orchestrator: orchestrator,
            categoryRegistry: categoryRouteRegistry,
            printers: kitchenPrinters,
            orderNumber: resolvedOrderNumber,
            orderType: resolvedOrderType,
            items: itemsForCategoryDispatch,
            note: resolvedNote,
            invoiceNumber: resolvedInvoiceNumber,
            templateMeta: resolvedTemplateMeta,
            clientName: clientName,
            clientPhone: clientPhone,
            tableNumber: tableNumber,
            carNumber: carNumber,
            cashierName: cashierName,
            isRtl: _useArabicUi,
          );
          if (delivered) {
            printedAny = true;
            Log.d('kitchen-print',
                'category-routed dispatched for booking=$orderId');
          } else {
            onlyKnownSkipErrors = false;
          }
        } catch (e) {
          onlyKnownSkipErrors = false;
          Log.w('kitchen-print',
              'category-routed failed for booking=$orderId', error: e);
        }
        break;
      }

      if (resolvedItems.isEmpty) {
        // Successful API call with no items for this kitchen route.
        // Keep fallback path available in case parsing/shape differs by account.
        onlyKnownSkipErrors = false;
        Log.d('kitchen-print',
            'receipt has no items for booking=$orderId kitchen_id=$kitchenId');
        continue;
      }

      final routePrinters = _resolveKitchenPrintersForKitchenRoute(
        routeRegistry: kitchenRouteRegistry,
        kitchenId: kitchenId,
        allKitchenIds: kitchenIds,
        candidatePrinters: kitchenPrinters,
      );

      try {
        final result = await orchestrator.enqueueKitchenPrint(
          printers: routePrinters,
          orderNumber: resolvedOrderNumber,
          orderType: resolvedOrderType,
          items: resolvedItems,
          note: resolvedNote,
          invoiceNumber: resolvedInvoiceNumber,
          templateMeta: resolvedTemplateMeta,
          clientName: clientName,
          clientPhone: clientPhone,
          tableNumber: tableNumber,
          carNumber: carNumber,
          cashierName: cashierName,
          isRtl: _useArabicUi,
          primaryLang: _resolveKitchenInvoiceLang(),
        );
        if (result.success) {
          printedAny = true;
          Log.d('kitchen-print',
              'dispatched for booking=$orderId kitchen_id=$kitchenId '
              'printers=${routePrinters.map((p) => p.name).join(', ')}');
          continue;
        }

        onlyKnownSkipErrors = false;
        if (!mounted) return;
        UiFeedback.warning(context, result.userMessage ?? 'تعذر الطباعة — تحقق من اتصال الطابعة');
      } catch (e) {
        onlyKnownSkipErrors = false;
        Log.w('kitchen-print',
            'failed to enqueue for booking=$orderId kitchen_id=$kitchenId',
            error: e);
      }
    }

    if (printedAny) return;

    // If backend explicitly says "already sent" or "no meals", avoid local reprint.
    if (apiAttempted && onlyKnownSkipErrors) {
      Log.d('kitchen-print',
          'skipped for booking=$orderId due to known backend state '
          '(already sent / no meals)');
      return;
    }


    if (hasCategoryAssignments) {
      try {
        final delivered = await _dispatchKitchenPrintByCategoryRouting(
          orchestrator: orchestrator,
          categoryRegistry: categoryRouteRegistry,
          printers: kitchenPrinters,
          orderNumber: effectiveOrderNumber,
          orderType: kitchenOrderType,
          items: localFallbackItems,
          note: generalNote,
          invoiceNumber: invoiceNumber,
          templateMeta: baseTemplateMeta,
          clientName: clientName,
          clientPhone: clientPhone,
          tableNumber: capturedTableNumber,
          carNumber: carNumber,
          cashierName: cashierName,
          isRtl: _useArabicUi,
        );
        if (delivered) {
          Log.d('kitchen-print', 'category-routed fallback dispatched for #$orderId');
          return;
        }
      } catch (e) {
        Log.w('kitchen-print', 'category-routed fallback failed for #$orderId', error: e);
      }
    }

    try {
      final fallbackResult = await orchestrator.enqueueKitchenPrint(
        printers: kitchenPrinters,
        orderNumber: effectiveOrderNumber,
        orderType: kitchenOrderType,
        items: localFallbackItems,
        note: generalNote,
        invoiceNumber: invoiceNumber,
        templateMeta: baseTemplateMeta,
        clientName: clientName,
        clientPhone: clientPhone,
        tableNumber: capturedTableNumber,
        carNumber: carNumber,
        cashierName: cashierName,
        printerName: null,
        isRtl: _useArabicUi,
        primaryLang: _resolveKitchenInvoiceLang(),
      );
      if (!mounted) return;
      if (!fallbackResult.success) {
        UiFeedback.warning(context, fallbackResult.userMessage ??
                  'تعذر الطباعة — تحقق من اتصال الطابعة');
      }
    } catch (e) {
      Log.w('kitchen-print', 'failed to enqueue fallback for #$orderId', error: e);
    }
  }

  // ── Salon module: per-service turn slip (طابعة الأدوار) ────────────
  //
  // Emits one ticket per salon cart item to every printer tagged with the
  // kitchen/KDS/bar role — same targeting as the restaurant kitchen print,
  // but with a distinct layout (see `_buildSalonTurnView`). The orchestrator
  // is bypassed: salon tickets don't share the kitchen's grouping/backend
  // receipt-generation semantics, and each service counts as an independent
  // job (a booking with 3 services prints 3 tickets per printer).
  Future<void> _triggerSalonTurnPrint({
    required String orderId,
    String? invoiceNumber,
    String? dailyOrderNumber,
    List<CartItem>? cartSnapshot,
  }) async {
    try {
      // The fast-path payment flow clears `_cart` BEFORE this trigger fires
      // (so the UI feels instant). Without a snapshot the loop below would
      // walk an empty cart and silently print nothing — leaving only the
      // cashier-receipt fallback to fire on the kitchen-tagged printer,
      // which is what the user reports. Prefer the explicit snapshot the
      // caller captured before the cart was cleared; only fall back to the
      // live cart for callers that fire mid-edit (cart still populated).
      final List<CartItem> cartItems = (cartSnapshot != null && cartSnapshot.isNotEmpty)
          ? cartSnapshot
          : _cart.toList(growable: false);
      final deviceService = getIt<DeviceService>();
      final roleRegistry = getIt<PrinterRoleRegistry>();
      await roleRegistry.initialize();

      var allPrinters =
          (await deviceService.getDevices()).where(_isUsablePrinter).toList();
      if (allPrinters.isEmpty) {
        allPrinters = _devices.where(_isUsablePrinter).toList(growable: false);
      }
      var printers = allPrinters.where((p) {
        final role = roleRegistry.resolveRole(p);
        return role == PrinterRole.kitchen ||
            role == PrinterRole.kds ||
            role == PrinterRole.bar;
      }).toList(growable: false);
      // Fallback: salon kiosks usually have a single printer assigned to
      // the cashier role. Without this fallback the turn slip silently
      // skips printing whenever the user hasn't tagged any printer with
      // the Adwar/kitchen role. We still prefer dedicated kitchen
      // printers when they exist.
      if (printers.isEmpty) {
        printers = allPrinters;
        if (printers.isNotEmpty) {
          debugPrint(
            'ℹ️ No printer tagged as أدوار/kitchen — using ${printers.length} '
            'available printer(s) for the salon turn slip',
          );
        }
      }
      if (printers.isEmpty) {
        debugPrint('ℹ️ No printers available — skipping salon turn slip');
        return;
      }

      // Build the list of (service, employee, price) rows from the current
      // cart. Each cart item carries its salonData snapshot.
      //
      // Service name is resolved against the printer's primary language so
      // the salon turn slip respects the same language toggle the
      // restaurant kitchen ticket already honours (printer-language ≠ UI
      // language). Order: API translation map on the salonData snapshot →
      // the Product's bilingual fields → the booking-time `item_name`
      // snapshot → the raw product name as last resort.
      final lang = _resolveKitchenInvoiceLang();
      final salonServices = <_SalonTurnRow>[];
      final employeeLookup = <int, String>{
        for (final e in _salonEmployees)
          if (e['id'] is num) (e['id'] as num).toInt(): (e['name'] ?? '').toString(),
      };
      for (final item in cartItems) {
        final salon = item.salonData ?? const <String, dynamic>{};
        final empRaw = salon['employee_id'];
        final empId = empRaw is num
            ? empRaw.toInt()
            : (empRaw is String ? int.tryParse(empRaw) : null);
        final employeeName = (salon['employee_name']?.toString().trim().isNotEmpty ==
                true)
            ? salon['employee_name'].toString()
            : (empId != null ? (employeeLookup[empId] ?? '') : '');
        // Notes: prefer the salonData snapshot the picker dialog stamped
        // onto the cart entry, then fall back to the cart-level `notes`
        // field (used by older paths). Joined with " · " when both
        // surfaces carry text so the slip preserves every comment.
        final salonNote = (salon['notes'] ?? '').toString().trim();
        final cartNote = item.notes.trim();
        final mergedNotes = (salonNote.isNotEmpty && cartNote.isNotEmpty &&
                salonNote != cartNote)
            ? '$salonNote · $cartNote'
            : (salonNote.isNotEmpty ? salonNote : cartNote);
        salonServices.add(_SalonTurnRow(
          serviceName: _resolveSalonServiceName(
            lang: lang,
            translations: salon['service_name_translations'] ??
                salon['name_translations'] ??
                salon['meal_name_translations'],
            productLocalized: item.product.nameForLang(lang),
            snapshotName: salon['item_name']?.toString(),
            productName: item.product.name,
          ),
          employeeName: employeeName,
          price: item.product.price * item.quantity,
          notes: mergedNotes,
        ));
      }
      if (salonServices.isEmpty) return;

      final dateStr = (salonServices.isNotEmpty &&
              cartItems.isNotEmpty &&
              cartItems.first.salonData?['date']?.toString().isNotEmpty == true)
          ? cartItems.first.salonData!['date'].toString()
          : DateFormat('yyyy-MM-dd').format(DateTime.now());
      final timeStr = (cartItems.isNotEmpty &&
              cartItems.first.salonData?['time']?.toString().isNotEmpty == true)
          ? cartItems.first.salonData!['time'].toString()
          : DateFormat('hh:mm a').format(DateTime.now());

      final bookingNumber = orderId;
      final resolvedInvoiceNumber = (invoiceNumber?.trim().isNotEmpty == true)
          ? invoiceNumber!
          : '#$orderId';

      final customerName = (_selectedCustomer?.name.trim().isNotEmpty == true)
          ? _selectedCustomer!.name
          : '-';

      // Shop header — reuse the cashier-receipt cached seller/branch info.
      final sellerAr = _firstNonEmptyText(<dynamic>[
        _cachedBranchMap?['seller_name'],
        _cachedBranchMap?['name'],
        _cachedSellerInfo?['name'],
      ]);
      final sellerEn = _cachedSellerNameEn;
      final addressLine = _firstNonEmptyText(<dynamic>[
        _cachedBranchMap?['address'],
        _cachedBranchAddressEn,
      ]);
      final phones = <String>[];
      final branchPhone = _firstNonEmptyText(<dynamic>[
        _cachedBranchMap?['mobile'],
        _cachedBranchMap?['phone'],
        _cachedSellerInfo?['mobile'],
        _cachedSellerInfo?['phone'],
      ]);
      if (branchPhone != null && branchPhone.isNotEmpty) {
        phones.add(branchPhone);
      }

      // The backend exposes the uploaded brand logo as `seller.logo`. It may
      // live at the top of the cached seller map or nested inside the branch
      // map depending on which API hydrated the cache first.
      final logoUrl = _firstNonEmptyText(<dynamic>[
        _cachedSellerInfo?['logo'],
        _cachedBranchMap?['seller'] is Map
            ? (_cachedBranchMap!['seller'] as Map)['logo']
            : null,
        _cachedBranchMap?['logo'],
      ]);

      final printerService = getIt<PrinterService>();

      for (var i = 0; i < salonServices.length; i++) {
        final row = salonServices[i];
        final priceFormatted = row.price.toStringAsFixed(ApiConstants.digitsNumber);
        for (final printer in printers) {
          try {
            await printerService.printSalonTurnTicket(
              printer,
              invoiceNumber: resolvedInvoiceNumber,
              bookingNumber: bookingNumber,
              dailyOrderNumber: dailyOrderNumber,
              dateStr: dateStr,
              timeStr: timeStr,
              serviceIndex: i + 1,
              customerName: customerName,
              serviceName: row.serviceName,
              employeeName: row.employeeName.isNotEmpty ? row.employeeName : '-',
              priceFormatted: priceFormatted,
              notes: row.notes,
              sellerNameAr: sellerAr,
              sellerNameEn: sellerEn,
              addressLine: addressLine,
              phones: phones,
              logoUrl: logoUrl,
            );
          } catch (e) {
            debugPrint('⚠️ Salon turn print failed on ${printer.name}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ _triggerSalonTurnPrint failed: $e');
    }
  }

  /// Prints salon turn slips driven by a booking-detail response instead of
  /// the live cart. Used by the new Bookings + Review-Tickets tabs whose
  /// "create" dialogs run outside `_MainScreenState` and therefore can't
  /// reach `_cart` / `_selectedCustomer` / the branch-info caches.
  ///
  /// [bookingData] must follow the `/seller/branches/{id}/bookings/{id}`
  /// shape — i.e. `{id, user:{name}, booking_services:[{service_name,
  /// employee:{fullname}, price|total_price, date, time, notes}]}`.
  /// Same printer-resolution policy as [_triggerSalonTurnPrint]: prefers
  /// kitchen/KDS/bar-tagged printers, falls back to every available
  /// printer when no role is set, no-ops when zero printers exist.
  Future<void> triggerSalonTurnPrintFromBookingResponse({
    required String orderId,
    required Map<String, dynamic> bookingData,
  }) async {
    if (!_isSalonMode) return;
    try {
      final servicesRaw = bookingData['booking_services'];
      if (servicesRaw is! List || servicesRaw.isEmpty) return;

      final lang = _resolveKitchenInvoiceLang();
      final rows = <_SalonTurnRow>[];
      for (final raw in servicesRaw) {
        if (raw is! Map) continue;
        final s = Map<String, dynamic>.from(raw);
        // The salon backend returns `service_name` either as a plain string
        // or as a `{ar: "...", en: "..."}` map (matching how
        // orders_screen.details.dart already resolves it). Walk both shapes
        // through the printer-language picker so the turn slip prints in
        // the same language the cashier configured for tickets.
        final serviceName = _resolveSalonServiceName(
          lang: lang,
          translations: s['service_name_translations'] ??
              s['name_translations'] ??
              s['meal_name_translations'] ??
              (s['service_name'] is Map ? s['service_name'] : null) ??
              (s['service'] is Map &&
                      (s['service'] as Map)['name'] is Map
                  ? (s['service'] as Map)['name']
                  : null),
          snapshotName: s['service_name'] is String
              ? s['service_name'] as String
              : (s['item_name']?.toString() ??
                  (s['service'] is Map
                      ? (s['service'] as Map)['name']?.toString()
                      : null)),
          productName: '',
          productLocalized: '',
        );
        final empMap = s['employee'];
        final employeeName = (empMap is Map
                ? (empMap['fullname'] ?? empMap['name'] ?? '')
                : '')
            .toString();
        final priceRaw = s['total_price'] ?? s['service_price'] ?? s['price'] ?? 0;
        final price = priceRaw is num
            ? priceRaw.toDouble()
            : double.tryParse(priceRaw.toString()) ?? 0.0;
        final notes = (s['notes'] ?? '').toString().trim();
        rows.add(_SalonTurnRow(
          serviceName: serviceName,
          employeeName: employeeName.isNotEmpty ? employeeName : '-',
          price: price,
          notes: notes,
        ));
      }
      if (rows.isEmpty) return;

      // Resolve printers — same role policy as the cart-based path.
      final deviceService = getIt<DeviceService>();
      final roleRegistry = getIt<PrinterRoleRegistry>();
      await roleRegistry.initialize();

      var allPrinters =
          (await deviceService.getDevices()).where(_isUsablePrinter).toList();
      if (allPrinters.isEmpty) {
        allPrinters = _devices.where(_isUsablePrinter).toList(growable: false);
      }
      var printers = allPrinters.where((p) {
        final role = roleRegistry.resolveRole(p);
        return role == PrinterRole.kitchen ||
            role == PrinterRole.kds ||
            role == PrinterRole.bar;
      }).toList(growable: false);
      if (printers.isEmpty) {
        printers = allPrinters;
        if (printers.isNotEmpty) {
          debugPrint(
            'ℹ️ No printer tagged as أدوار/kitchen — using ${printers.length} '
            'available printer(s) for the salon turn slip',
          );
        }
      }
      if (printers.isEmpty) return;

      // Date / time / customer pulled straight from the booking payload so
      // the slip matches what the cashier actually booked.
      final firstService = servicesRaw.first as Map?;
      final dateStr =
          (firstService?['date']?.toString().trim().isNotEmpty == true)
              ? firstService!['date'].toString()
              : DateFormat('yyyy-MM-dd').format(DateTime.now());
      final timeStr =
          (firstService?['time']?.toString().trim().isNotEmpty == true)
              ? firstService!['time'].toString()
              : DateFormat('hh:mm a').format(DateTime.now());

      final user = bookingData['user'];
      final customerName = (user is Map
              ? (user['name'] ?? user['fullname'] ?? '-')
              : '-')
          .toString();

      final invoiceNumberRaw = bookingData['invoice_number']?.toString();
      final bookingNumber = (bookingData['booking_number']?.toString() ??
              orderId)
          .replaceFirst(RegExp(r'^#'), '');
      final dailyOrderNumber =
          bookingData['daily_order_number']?.toString();
      final resolvedInvoiceNumber =
          (invoiceNumberRaw?.trim().isNotEmpty ?? false)
              ? invoiceNumberRaw!
              : '#$bookingNumber';

      // Branch header — booking-detail responses include branch info
      // already, but we still prefer the cashier-receipt cache when
      // populated (it carries the English fallbacks).
      final branchMap = bookingData['branch'];
      final sellerAr = _firstNonEmptyText(<dynamic>[
        _cachedBranchMap?['seller_name'],
        _cachedBranchMap?['name'],
        branchMap is Map ? branchMap['seller_name'] : null,
        _cachedSellerInfo?['name'],
      ]);
      final sellerEn = _cachedSellerNameEn;
      final addressLine = _firstNonEmptyText(<dynamic>[
        _cachedBranchMap?['address'],
        branchMap is Map ? branchMap['address'] : null,
        _cachedBranchAddressEn,
      ]);
      final phones = <String>[];
      final branchPhone = _firstNonEmptyText(<dynamic>[
        _cachedBranchMap?['mobile'],
        branchMap is Map ? branchMap['mobile'] : null,
        _cachedBranchMap?['phone'],
        branchMap is Map ? branchMap['telephone'] : null,
        _cachedSellerInfo?['mobile'],
      ]);
      if (branchPhone != null && branchPhone.isNotEmpty) {
        phones.add(branchPhone);
      }
      final logoUrl = _firstNonEmptyText(<dynamic>[
        _cachedSellerInfo?['logo'],
        _cachedBranchMap?['seller'] is Map
            ? (_cachedBranchMap!['seller'] as Map)['logo']
            : null,
        _cachedBranchMap?['logo'],
        branchMap is Map ? branchMap['logo'] : null,
        branchMap is Map && branchMap['seller'] is Map
            ? (branchMap['seller'] as Map)['logo']
            : null,
      ]);

      final printerService = getIt<PrinterService>();
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final priceFormatted =
            row.price.toStringAsFixed(ApiConstants.digitsNumber);
        for (final printer in printers) {
          try {
            await printerService.printSalonTurnTicket(
              printer,
              invoiceNumber: resolvedInvoiceNumber,
              bookingNumber: bookingNumber,
              dailyOrderNumber: dailyOrderNumber,
              dateStr: dateStr,
              timeStr: timeStr,
              serviceIndex: i + 1,
              customerName: customerName,
              serviceName: row.serviceName,
              employeeName:
                  row.employeeName.isNotEmpty ? row.employeeName : '-',
              priceFormatted: priceFormatted,
              notes: row.notes,
              sellerNameAr: sellerAr,
              sellerNameEn: sellerEn,
              addressLine: addressLine,
              phones: phones,
              logoUrl: logoUrl,
            );
          } catch (e) {
            debugPrint(
                '⚠️ Salon turn print failed on ${printer.name}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ triggerSalonTurnPrintFromBookingResponse failed: $e');
    }
  }
}

class _SalonTurnRow {
  final String serviceName;
  final String employeeName;
  final double price;
  final String notes;
  const _SalonTurnRow({
    required this.serviceName,
    required this.employeeName,
    required this.price,
    this.notes = '',
  });
}
