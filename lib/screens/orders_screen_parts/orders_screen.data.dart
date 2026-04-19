// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../orders_screen.dart';

class _PageScan {
  final int page;
  final Map<String, dynamic> response;
  _PageScan(this.page, this.response);
}

extension OrdersScreenData on _OrdersScreenState {
  Future<void> _loadData() async {
    _syncSearchQueryFromInput(normalizeController: true);

    setState(() {
      _isLoading = true;
      _error = null;
      _bookingPage = 1;
      _bookings = [];
      _bookingsRawResponse = {};
      _hasMoreBookings = true;
      _selectedBookingIds.clear();
    });

    try {
      final todayDateStr = _todayForApi();
      final orderIdSearch = _orderIdSearchValue;

      Future<Map<String, dynamic>> bookingsFuture;
      if (orderIdSearch.isNotEmpty) {
        bookingsFuture = _loadBookingsForOrderSearch(
          orderIdSearch: orderIdSearch,
          dateFromStr: todayDateStr,
          dateToStr: todayDateStr,
        );
      } else {
        bookingsFuture = _orderService.getBookings(
          page: 1,
          dateFrom: todayDateStr,
          dateTo: todayDateStr,
          search: _searchQueryForApi.isEmpty ? null : _searchQueryForApi,
          status: _selectedStatus == 'all' ? null : _selectedStatus,
        );
      }

      final bookingsResponse = await bookingsFuture;
      _processBookings(bookingsResponse, append: false);

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } on UnauthorizedException {
      return;
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _loadBookingsForOrderSearch({
    required String orderIdSearch,
    required String dateFromStr,
    required String dateToStr,
  }) async {
    final primaryResponse = await _orderService.getBookings(
      page: 1,
      dateFrom: dateFromStr,
      dateTo: dateToStr,
      search: orderIdSearch,
      status: _selectedStatus == 'all' ? null : _selectedStatus,
    );

    final primaryMatches = _bookingsFromResponse(primaryResponse)
        .where((booking) => _matchesOrderSearch(booking, orderIdSearch))
        .toList();
    if (primaryMatches.isNotEmpty) {
      return _buildSearchResponseFromMatches(primaryMatches);
    }

    // PERF: previous implementation scanned up to 8 pages sequentially, so
    // a miss took 8 full round-trips (~4-10 s). We now fan out pages 2..8
    // in parallel with Future.wait. Page 1 was already fetched as the
    // primary search above, so we skip it here.
    const maxPagesToScan = 8;
    final localMatches = <Booking>[];

    final dateScopedPages = await Future.wait<_PageScan>(
      List<Future<_PageScan>>.generate(maxPagesToScan - 1, (i) {
        final page = i + 2;
        return _orderService
            .getBookings(
          page: page,
          dateFrom: dateFromStr,
          dateTo: dateToStr,
          status: _selectedStatus == 'all' ? null : _selectedStatus,
        )
            .then((response) => _PageScan(page, response))
            .catchError((_) => _PageScan(page, const <String, dynamic>{}));
      }),
      eagerError: false,
    );

    for (final scan in dateScopedPages..sort((a, b) => a.page.compareTo(b.page))) {
      final pageBookings = _bookingsFromResponse(scan.response);
      if (pageBookings.isEmpty) continue;
      localMatches.addAll(
        pageBookings
            .where((booking) => _matchesOrderSearch(booking, orderIdSearch)),
      );
      if (localMatches.isNotEmpty) {
        return _buildSearchResponseFromMatches(localMatches);
      }
    }

    // Last fallback for explicit order-id search: query without date filters
    // because many environments store historical orders outside "today"
    // and backend search might only match globally. Again run all pages
    // in parallel so the total latency is ~1 round-trip, not 8.
    final globalPages = await Future.wait<_PageScan>(
      List<Future<_PageScan>>.generate(maxPagesToScan, (i) {
        final page = i + 1;
        return _orderService
            .getBookings(
          page: page,
          search: orderIdSearch,
          status: _selectedStatus == 'all' ? null : _selectedStatus,
        )
            .then((response) => _PageScan(page, response))
            .catchError((_) => _PageScan(page, const <String, dynamic>{}));
      }),
      eagerError: false,
    );

    for (final scan in globalPages..sort((a, b) => a.page.compareTo(b.page))) {
      final pageBookings = _bookingsFromResponse(scan.response);
      if (pageBookings.isEmpty) continue;
      localMatches.addAll(
        pageBookings
            .where((booking) => _matchesOrderSearch(booking, orderIdSearch)),
      );
      if (localMatches.isNotEmpty) {
        return _buildSearchResponseFromMatches(localMatches);
      }
    }

    return primaryResponse;
  }

  Future<void> _loadMoreData() async {
    if (!mounted || _isLoadingMore) return;
    _syncSearchQueryFromInput(normalizeController: true);

    setState(() => _isLoadingMore = true);

    try {
      final todayDateStr = _todayForApi();
      final orderIdSearch = _orderIdSearchValue;

      if (!_hasMoreBookings) return;
      if (orderIdSearch.isNotEmpty) {
        _hasMoreBookings = false;
        return;
      }
      final nextPage = _bookingPage + 1;
      final data = await _orderService.getBookings(
        page: nextPage,
        dateFrom: todayDateStr,
        dateTo: todayDateStr,
        search: _searchQueryForApi.isEmpty ? null : _searchQueryForApi,
        status: _selectedStatus == 'all' ? null : _selectedStatus,
      );
      _processBookings(data, append: true);
      _bookingPage = nextPage;
    } catch (e) {
      print('Error loading more: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _showCreateInvoiceDialog(Booking booking) async {
    Map<String, bool> tenderEnabledMethods = const {
      'cash': false,
      'card': false,
      'mada': false,
      'visa': false,
      'benefit': false,
      'stc': false,
      'bank_transfer': false,
      'wallet': false,
      'cheque': false,
      'petty_cash': false,
      'pay_later': false,
      'tabby': false,
      'tamara': false,
      'keeta': false,
      'my_fatoorah': false,
      'jahez': false,
      'talabat': false,
    };

    try {
      tenderEnabledMethods =
          await getIt<BranchService>().getEnabledPayMethods();
    } catch (_) {}
    // "Pay later" is not a valid pay_method for invoice payments.
    tenderEnabledMethods['pay_later'] = false;

    final hasAnyEnabled = tenderEnabledMethods.values.any((v) => v == true);
    if (!hasAnyEnabled) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr(
            'لا توجد طرق دفع مفعّلة لهذا الفرع. فعّل طريقة دفع من لوحة التحكم ثم أعد المحاولة.',
            'No payment methods are enabled for this branch.',
          )),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!mounted) return;
    double resolveInvoiceTotal() {
      double round2(double v) => double.parse(v.toStringAsFixed(2));
      return round2(_bookingGrandTotal(booking));
    }

    // Use the active branch's tax config instead of a hardcoded 15% —
    // otherwise the pay-later dialog shows a tax breakdown for a total that
    // has no tax baked in, and vice-versa for non-standard tax rates.
    final branchService = getIt<BranchService>();
    final dialogTaxRate =
        branchService.cachedHasTax ? branchService.cachedTaxRate : 0.0;

    showDialog(
      context: context,
      builder: (context) => PaymentTenderDialog(
        total: resolveInvoiceTotal(),
        taxRate: dialogTaxRate,
        enabledMethods: tenderEnabledMethods,
        onConfirm: () async {
          Navigator.pop(context);
          await _processDeferredInvoice(
            booking,
            [
              {
                'name': 'دفع نقدي',
                'pay_method': 'cash',
                'amount': resolveInvoiceTotal(),
                'index': 0
              }
            ],
          );
        },
        onConfirmWithPays: (pays) async {
          Navigator.pop(context);
          await _processDeferredInvoice(booking, pays);
        },
      ),
    );
  }

  Future<void> _processDeferredInvoice(
      Booking booking, List<Map<String, dynamic>> pays) async {
    setState(() => _payingBookingIds.add(booking.id));
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      List<Map<String, dynamic>> apiPays = [];
      for (int i = 0; i < pays.length; i++) {
        final amount = (pays[i]['amount'] as num?)?.toDouble() ?? 0.0;
        apiPays.add({
          'name': pays[i]['name'],
          'pay_method': pays[i]['pay_method'],
          'amount': double.parse(amount.toStringAsFixed(2)),
          'index': i,
        });
      }

      List<Map<String, dynamic>> extractItems(Map<String, dynamic> payload) {
        final sections = payload['sections'];
        if (sections is List) {
          final sectionItems = <Map<String, dynamic>>[];
          for (final section in sections) {
            if (section is! Map) continue;
            final sectionMap = section.map((k, v) => MapEntry(k.toString(), v));
            final items = sectionMap['items'];
            if (items is List) {
              for (final item in items) {
                if (item is Map) {
                  sectionItems.add(
                    item.map((k, v) => MapEntry(k.toString(), v)),
                  );
                }
              }
            }
          }
          if (sectionItems.isNotEmpty) return sectionItems;
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
          final raw = payload[key];
          if (raw is List) {
            final rows = raw
                .whereType<Map>()
                .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
                .toList();
            if (rows.isNotEmpty) return rows;
          }
        }
        return const <Map<String, dynamic>>[];
      }

      List<Map<String, dynamic>> mapItemsToInvoicePayload(
        List<Map<String, dynamic>> rawItems,
      ) {
        final items = <Map<String, dynamic>>[];
        for (final raw in rawItems) {
          dynamic pick(dynamic value) => value == null ? null : value;
          final mealMap = (raw['meal'] is Map)
              ? (raw['meal'] as Map).map((k, v) => MapEntry(k.toString(), v))
              : const <String, dynamic>{};
          final mealId = pick(raw['meal_id'] ?? mealMap['id']);
          final productId = pick(raw['product_id'] ?? raw['productId']);
          final bookingMealId = pick(raw['booking_meal_id'] ?? raw['id']);
          final bookingProductId = pick(raw['booking_product_id'] ?? raw['id']);
          final fallbackId = pick(raw['id']);
          final quantityRaw = raw['quantity'] ?? raw['qty'] ?? raw['count'];
          final quantity = (quantityRaw is num)
              ? quantityRaw.toInt()
              : int.tryParse('$quantityRaw') ?? 1;
          final totalRaw = raw['total'] ?? raw['line_total'];
          final unitRaw = raw['unit_price'] ??
              raw['unitPrice'] ??
              raw['price'] ??
              mealMap['price'];
          var unitPrice = _parseNum(unitRaw);
          final total = _parseNum(totalRaw);
          if (unitPrice <= 0 && total > 0 && quantity > 0) {
            unitPrice = total / quantity;
          }
          String? resolveItemName() {
            final directName = raw['item_name'] ?? raw['meal_name'];
            if (directName != null) return directName.toString();
            final rawName = mealMap['name'];
            if (rawName == null) return null;
            final rawText = rawName.toString();
            final trimmed = rawText.trim();
            if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
              try {
                final parsed = jsonDecode(trimmed);
                if (parsed is Map) {
                  final map = parsed.map((k, v) => MapEntry(k.toString(), v));
                  return (map['ar'] ?? map['en'] ?? map.values.first)
                      ?.toString();
                }
              } catch (_) {
                return rawText;
              }
            }
            return rawText;
          }

          final resolvedItemName = resolveItemName();
          if (mealId == null && productId == null && fallbackId == null) {
            continue;
          }
          items.add({
            if (bookingMealId != null) 'booking_meal_id': bookingMealId,
            if (bookingProductId != null)
              'booking_product_id': bookingProductId,
            if (mealId != null) 'meal_id': mealId,
            if (mealId == null && productId != null) 'product_id': productId,
            if (mealId == null && productId == null) 'id': fallbackId,
            if (resolvedItemName != null) 'item_name': resolvedItemName,
            'quantity': quantity,
            'price': unitPrice,
            'unitPrice': unitPrice,
          });
        }
        return items;
      }

      List<Map<String, dynamic>> itemsPayload = booking.meals
          .map((m) => {
                'meal_id': m.mealId,
                'booking_meal_id': m.id,
                'item_name': m.mealName,
                'quantity': m.quantity,
                'price': m.unitPrice,
                'unitPrice': m.unitPrice,
              })
          .toList();

      // Try from booking.raw if meals list was empty
      if (itemsPayload.isEmpty && booking.raw.isNotEmpty) {
        final rawItems = extractItems(Map<String, dynamic>.from(booking.raw));
        if (rawItems.isNotEmpty) {
          itemsPayload = mapItemsToInvoicePayload(rawItems);
        }
      }

      if (itemsPayload.isEmpty) {
        try {
          final details =
              await _orderService.getBookingDetails(booking.id.toString());
          final detailMap =
              _asMap(details['data']) ?? _asMap(details) ?? const {};
          var rawItems = extractItems(Map<String, dynamic>.from(detailMap));
          // If still empty, try nested structures
          if (rawItems.isEmpty) {
            final nestedCandidates = [
              detailMap['booking'],
              detailMap['order'],
              detailMap['invoice'],
              detailMap['data'],
            ];
            for (final candidate in nestedCandidates) {
              if (candidate is Map) {
                final nested = candidate.map((k, v) => MapEntry(k.toString(), v));
                rawItems = extractItems(Map<String, dynamic>.from(nested));
                if (rawItems.isNotEmpty) break;
              }
            }
          }
          itemsPayload = mapItemsToInvoicePayload(rawItems);
        } catch (_) {
          // Ignore; handled below if items remain empty.
        }
      }

      if (itemsPayload.isEmpty) {
        throw Exception(_tr('الطلب بدون عناصر', 'Order has no items'));
      }

      double round2(double v) => double.parse(v.toStringAsFixed(2));
      double computeItemsSubtotal(List<Map<String, dynamic>> items) {
        double sum = 0.0;
        for (final item in items) {
          final qty = (item['quantity'] as num?)?.toDouble() ??
              double.tryParse(item['quantity']?.toString() ?? '') ??
              0.0;
          final unit = (item['unitPrice'] as num?)?.toDouble() ??
              (item['price'] as num?)?.toDouble() ??
              double.tryParse(item['unitPrice']?.toString() ?? '') ??
              double.tryParse(item['price']?.toString() ?? '') ??
              0.0;
          sum += unit * qty;
        }
        return round2(sum);
      }

      double resolveExpectedTotal(List<Map<String, dynamic>> items) {
        final subtotal =
            booking.total > 0 ? booking.total : computeItemsSubtotal(items);
        final total = subtotal + booking.tax - booking.discount;
        return round2(total > 0 ? total : subtotal);
      }

      double extractExpectedTotalFromCalc(dynamic response, double fallback) {
        if (response is! Map) return fallback;
        final map = response.map((k, v) => MapEntry(k.toString(), v));
        final candidates = <dynamic>[
          map['total'],
          map['invoice_total'],
          map['grand_total'],
          if (map['data'] is Map) (map['data'] as Map)['total'],
          if (map['data'] is Map) (map['data'] as Map)['invoice_total'],
          if (map['data'] is Map) (map['data'] as Map)['grand_total'],
          if (map['data'] is Map) (map['data'] as Map)['total_with_tax'],
        ];
        for (final c in candidates) {
          if (c is num) return c.toDouble();
          if (c is String) {
            final parsed = double.tryParse(c);
            if (parsed != null) return parsed;
          }
        }
        return fallback;
      }

      var expectedTotal = resolveExpectedTotal(itemsPayload);
      try {
        final calcResponse = await _orderService.calculateInvoice(
          {
            'items': itemsPayload,
            if (booking.discount > 0) 'discount': booking.discount,
          },
        );
        expectedTotal = round2(
          extractExpectedTotalFromCalc(calcResponse, expectedTotal),
        );
      } catch (_) {
        // Non-blocking: keep booking-derived total when calculate fails.
      }
      double sumPays(List<Map<String, dynamic>> pays) {
        double sum = 0.0;
        for (final pay in pays) {
          final amount = (pay['amount'] as num?)?.toDouble() ??
              double.tryParse(pay['amount']?.toString() ?? '') ??
              0.0;
          sum += amount;
        }
        return round2(sum);
      }

      if (apiPays.isEmpty) {
        apiPays = [
          {
            'name': 'دفع نقدي',
            'pay_method': 'cash',
            'amount': expectedTotal,
            'index': 0,
          }
        ];
      } else {
        final currentTotal = sumPays(apiPays);
        final diff = round2(expectedTotal - currentTotal);
        if (diff.abs() >= 0.01) {
          // Adjust the last payment line to match backend total.
          final lastIndex = apiPays.length - 1;
          final lastAmount = (apiPays[lastIndex]['amount'] as num?)
                  ?.toDouble() ??
              double.tryParse(apiPays[lastIndex]['amount']?.toString() ?? '') ??
              0.0;
          apiPays[lastIndex]['amount'] = round2(lastAmount + diff);
        }
      }

      List<Map<String, dynamic>> buildSalesMeals(
        List<Map<String, dynamic>> items,
      ) {
        final salesMeals = <Map<String, dynamic>>[];
        for (final item in items) {
          final quantityRaw = item['quantity'] ?? 1;
          final quantity = (quantityRaw is num)
              ? quantityRaw.toInt()
              : int.tryParse('$quantityRaw') ?? 1;
          final unitRaw =
              item['unitPrice'] ?? item['unit_price'] ?? item['price'] ?? 0;
          final unitPrice = (unitRaw is num)
              ? unitRaw.toDouble()
              : double.tryParse(unitRaw.toString()) ?? 0.0;
          final total = double.parse(
            (unitPrice * quantity).toStringAsFixed(2),
          );
          salesMeals.add({
            if (item['booking_meal_id'] != null)
              'booking_meal_id': item['booking_meal_id'],
            if (item['meal_id'] != null) 'meal_id': item['meal_id'],
            if (item['item_name'] != null) 'meal_name': item['item_name'],
            'quantity': quantity,
            'price': unitPrice,
            'unit_price': unitPrice,
            'unitPrice': unitPrice,
            'total': total,
            'discount_type': '%',
          });
        }
        return salesMeals;
      }

      final salesMealsPayload = buildSalesMeals(itemsPayload);

      final payload = <String, dynamic>{
        'branch_id': ApiConstants.branchId,
        'booking_id': booking.id,
        'date': dateStr,
        'cash_back': 0,
        'pays': apiPays,
        if (salesMealsPayload.isNotEmpty) 'sales_meals': salesMealsPayload,
      };

      // Retry once if backend says total mismatch — adjust pays to match.
      double? extractExpectedTotal(String msg) {
        final m = RegExp(r'\(([\d.]+)\)').firstMatch(msg);
        return double.tryParse(m?.group(1) ?? '');
      }

      List<Map<String, dynamic>> adjustPays(
          List<Map<String, dynamic>> pays, double target) {
        final nonZero = pays
            .where((p) => ((p['amount'] as num?)?.toDouble() ?? 0) > 0)
            .toList();
        if (nonZero.isEmpty) {
          return [
            {
              'name': 'دفع نقدي',
              'pay_method': 'cash',
              'amount': target,
              'index': 0
            }
          ];
        }
        final currentSum = nonZero.fold<double>(
            0, (s, p) => s + ((p['amount'] as num?)?.toDouble() ?? 0));
        final diff = double.parse((target - currentSum).toStringAsFixed(2));
        if (diff.abs() >= 0.01) {
          final last = nonZero.last;
          nonZero[nonZero.length - 1] = {
            ...last,
            'amount': double.parse(
              (((last['amount'] as num?)?.toDouble() ?? 0) + diff)
                  .clamp(0.0, double.infinity)
                  .toStringAsFixed(2),
            ),
          };
        }
        return nonZero
            .asMap()
            .entries
            .map((e) => {...e.value, 'index': e.key})
            .toList();
      }

      Map<String, dynamic> invoiceResponse;
      try {
        invoiceResponse = await _orderService.createInvoice(payload);
      } on ApiException catch (e) {
        if (e.statusCode == 422) {
          final expected = extractExpectedTotal(e.message);
          if (expected != null) {
            payload['pays'] = adjustPays(apiPays, expected);
            try {
              invoiceResponse = await _orderService.createInvoice(payload);
            } catch (_) {
              // Last resort: try multipart directly
              invoiceResponse =
                  await _orderService.createInvoiceMultipart(payload);
            }
          } else {
            rethrow;
          }
        } else {
          rethrow;
        }
      }

      debugPrint('🧾 createInvoice response keys: ${invoiceResponse.keys.toList()}');
      final responseData = invoiceResponse['data'];
      if (responseData is Map) {
        debugPrint('🧾 response.data keys: ${responseData.keys.toList()}');
        final nestedInvoice = responseData['invoice'];
        if (nestedInvoice is Map) {
          debugPrint('🧾 response.data.invoice keys: ${nestedInvoice.keys.toList()}');
          debugPrint('🧾 response.data.invoice.id: ${nestedInvoice['id']}');
          debugPrint('🧾 response.data.invoice.invoice_id: ${nestedInvoice['invoice_id']}');
        }
        debugPrint('🧾 response.data.id: ${responseData['id']}');
        debugPrint('🧾 response.data.invoice_id: ${responseData['invoice_id']}');
      }
      debugPrint('🧾 response.id: ${invoiceResponse['id']}');
      debugPrint('🧾 response.invoice_id: ${invoiceResponse['invoice_id']}');

      final invoiceId = _extractInvoiceId(invoiceResponse, strict: false);
      debugPrint('🧾 Extracted invoiceId: $invoiceId');
      booking.raw['has_invoice'] = true;
      if (invoiceId != null) {
        booking.raw['invoice_id'] = invoiceId;
      }

      final orderIdText = (booking.orderId ?? booking.id).toString();
      try {
        _displayAppService.notifyInvoiceCreated(
          orderId: orderIdText,
          invoiceId: invoiceId,
          invoiceNumber: booking.invoiceNumber ?? invoiceId?.toString(),
          orderNumber: booking.orderNumber ?? booking.bookingNumberRaw,
          total: booking.total,
        );
      } catch (e) {
        debugPrint('⚠️ Unable to notify invoice creation to display: $e');
      }

      try {
        if (!isOrderLockedValue(booking.status) &&
            !isOrderLockedValue(booking.raw['status'])) {
          final statusResponse = await _orderService.updateBookingStatus(
            orderId: booking.id.toString(),
            status: 7,
          );
          _updateStatusRawResponse = statusResponse;
          _displayAppService.sendOrderStatusUpdateToDisplay(
            orderId: booking.id.toString(),
            status: 7,
          );
        }
      } catch (e) {
        debugPrint('⚠️ Unable to lock order after invoice: $e');
      }

      // Auto-print receipt — use same logic as normal payment flow
      final resolvedInvoiceId = invoiceId?.toString() ?? '';
      final resolvedInvoiceNumber = booking.invoiceNumber ?? invoiceId?.toString() ?? '';
      final resolvedDailyOrder = booking.orderNumber ?? booking.bookingNumberRaw ?? '';
      final effectiveInvoiceId = resolvedInvoiceId.isNotEmpty ? resolvedInvoiceId : booking.id.toString();
      debugPrint('🖨️ Order pay: invoiceId=$resolvedInvoiceId invoiceNumber=$resolvedInvoiceNumber dailyOrder=$resolvedDailyOrder');

      debugPrint('🖨️ onPrintReceipt callback: ${widget.onPrintReceipt != null ? "SET" : "NULL"}');
      if (widget.onPrintReceipt != null) {
        // Use the same printing logic as the normal payment flow
        unawaited(() async {
          try {
            debugPrint('🖨️ Building receipt data for invoice=$effectiveInvoiceId...');
            final receiptData = await _buildReceiptDataForInvoice(
              invoiceId: effectiveInvoiceId,
              invoiceNumber: resolvedInvoiceNumber,
              dailyOrderNumber: resolvedDailyOrder,
            );
            debugPrint('🖨️ Receipt data: ${receiptData != null ? "OK (${receiptData.items.length} items)" : "NULL"}');
            if (receiptData != null) {
              debugPrint('🖨️ Calling onPrintReceipt...');
              await widget.onPrintReceipt!(
                receiptData: receiptData,
                invoiceId: effectiveInvoiceId,
              );
              debugPrint('🖨️ onPrintReceipt completed.');
            } else {
              debugPrint('⚠️ receiptData is null — skipping print');
            }
          } catch (e) {
            debugPrint('⚠️ Print after create invoice failed: $e');
          }
        }());
      } else {
        unawaited(_printCashierReceiptForOrder(
          invoiceId: effectiveInvoiceId,
          invoiceNumber: resolvedInvoiceNumber,
          dailyOrderNumber: resolvedDailyOrder,
        ));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              _tr('تم إنشاء الفاتورة بنجاح', 'Invoice created successfully')),
        ),
      );
      await _loadData();
      widget.onNavigateToInvoices?.call();
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException &&
          e.statusCode == 422 &&
          (e.userMessage ?? e.message).contains('عناصر') &&
          (booking.orderId == null ||
              booking.orderId == 0 ||
              booking.raw['order_id'] == null)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tr(
              'لا يمكن إنشاء فاتورة لهذا الطلب لأن الطلب لا يملك Order ID في السيرفر.',
              'Cannot create invoice: order has no Order ID on server.',
            )),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final userMessage = ErrorHandler.toUserMessage(
        e,
        fallback: _tr('تعذر إنشاء الفاتورة', 'Failed to create invoice'),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userMessage)),
      );
    } finally {
      if (mounted) setState(() => _payingBookingIds.remove(booking.id));
    }
  }

  /// Fetch invoice from API and build OrderReceiptData for printing.
  Future<OrderReceiptData?> _buildReceiptDataForInvoice({
    required String invoiceId,
    String? invoiceNumber,
    String? dailyOrderNumber,
  }) async {
    try {
      final invoiceResponse = await _orderService.getInvoice(invoiceId);
      final rawEnvelope =
          invoiceResponse.map((k, v) => MapEntry(k.toString(), v));
      final envelope = (rawEnvelope['data'] is Map)
          ? (rawEnvelope['data'] as Map)
              .map((k, v) => MapEntry(k.toString(), v))
          : rawEnvelope;

      final invoice = (envelope['invoice'] is Map)
          ? (envelope['invoice'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : envelope;
      final branch = (envelope['branch'] is Map)
          ? (envelope['branch'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
      final seller = (branch['seller'] is Map)
          ? (branch['seller'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};
      final originalSeller = (branch['original_seller'] is Map)
          ? (branch['original_seller'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : <String, dynamic>{};

      String pick(List<dynamic> candidates) {
        for (final c in candidates) {
          final t = c?.toString().trim();
          if (t != null && t.isNotEmpty && t.toLowerCase() != 'null') return t;
        }
        return '';
      }

      String? pickNullable(List<dynamic> candidates) {
        final r = pick(candidates);
        return r.isNotEmpty ? r : null;
      }

      // Parse items with addons
      final items = (invoice['items'] as List?)?.map((item) {
            final m = (item is Map)
                ? item.map((k, v) => MapEntry(k.toString(), v))
                : <String, dynamic>{};
            final qty = double.tryParse(m['quantity']?.toString() ?? '') ?? 1;
            final mealPrice = double.tryParse(m['meal_price']?.toString() ?? '') ?? 0;
            final lineTotal = double.tryParse(m['total']?.toString() ?? '') ?? 0;
            final unitPrice = mealPrice > 0 ? mealPrice : (qty > 0 ? lineTotal / qty : lineTotal);
            final total = lineTotal > 0 ? lineTotal : mealPrice * qty;

            // Parse bilingual name
            final rawName = m['item_name']?.toString() ?? '';
            String arName = rawName;
            String enName = rawName;
            if (rawName.contains(' - ')) {
              arName = rawName.split(' - ').first.trim();
              enName = rawName.split(' - ').last.trim();
            }

            // Parse addons — pick per-language names from the parallel
            // `addons_translations` list when available so the cashier
            // invoice renders the addon in the chosen invoice language.
            final addons = <ReceiptAddon>[];
            final rawAddons = m['addons'] ?? m['extras'];
            final rawAddonTranslations = m['addons_translations'];
            if (rawAddons is List) {
              for (var i = 0; i < rawAddons.length; i++) {
                final addon = rawAddons[i];
                if (addon is! Map) continue;
                final addonMap =
                    addon.map((k, v) => MapEntry(k.toString(), v));

                final localized = <String, String>{};
                if (rawAddonTranslations is List &&
                    i < rawAddonTranslations.length) {
                  final tr = rawAddonTranslations[i];
                  final optionMap = (tr is Map) ? tr['option'] : null;
                  if (optionMap is Map) {
                    for (final entry in optionMap.entries) {
                      final v = entry.value?.toString().trim() ?? '';
                      if (v.isEmpty) continue;
                      localized[entry.key.toString().trim().toLowerCase()] = v;
                    }
                  }
                }

                final fallbackAr = addonMap['name']?.toString() ??
                    addonMap['name_ar']?.toString() ??
                    '';
                final fallbackEn = addonMap['name_en']?.toString() ??
                    addonMap['name']?.toString() ??
                    '';

                addons.add(ReceiptAddon(
                  nameAr: localized['ar']?.isNotEmpty == true
                      ? localized['ar']!
                      : fallbackAr,
                  nameEn: localized['en']?.isNotEmpty == true
                      ? localized['en']!
                      : fallbackEn,
                  price: double.tryParse(addonMap['price']?.toString() ?? '') ?? 0,
                  localizedNames: localized,
                ));
              }
            }

            return ReceiptItem(
              nameAr: arName,
              nameEn: enName,
              quantity: qty,
              unitPrice: unitPrice,
              total: total,
              addons: addons.isNotEmpty ? addons : null,
            );
          }).toList() ??
          [];

      final totalStr = invoice['total']?.toString() ?? '0';
      final taxStr = invoice['tax']?.toString() ?? '0';
      final grandStr = invoice['grand_total']?.toString() ?? '0';
      final totalExcl = double.tryParse(totalStr) ?? 0;
      final tax = double.tryParse(taxStr) ?? 0;
      final parsedGrand = double.tryParse(grandStr) ?? 0;
      final grandTotal = parsedGrand > 0 ? parsedGrand : (totalExcl + tax);

      // Resolve daily order number from invoice API (priority) or fallback
      final resolvedOrderNumber = pick([
        invoice['daily_order_number'],
        invoice['order_number'],
        envelope['daily_order_number'],
      ]);
      final effectiveOrderNumber = resolvedOrderNumber.isNotEmpty
          ? resolvedOrderNumber
          : (dailyOrderNumber ?? '');

      // Resolve customer info
      final customer = invoice['customer'] ?? invoice['client'] ?? envelope['customer'];
      String? clientName;
      String? clientPhone;
      if (customer is Map) {
        clientName = customer['name']?.toString();
        clientPhone = (customer['mobile'] ?? customer['phone'])?.toString();
      } else if (customer is String && customer.isNotEmpty) {
        clientName = customer;
      }

      // Resolve order type
      final orderType = pickNullable([
        invoice['order_type'], invoice['type'],
        envelope['order_type'], envelope['type'],
      ]);

      // Resolve payments
      final paysList = invoice['pays'] ?? invoice['payments'] ?? envelope['pays'];
      final payments = <ReceiptPayment>[];
      if (paysList is List) {
        for (final p in paysList) {
          if (p is Map) {
            final method = p['pay_method']?.toString() ?? p['method']?.toString() ?? 'cash';
            final amount = double.tryParse(p['amount']?.toString() ?? '0') ?? 0;
            payments.add(ReceiptPayment(methodLabel: method, amount: amount));
          }
        }
      }

      // Resolve discount
      final discountAmount = double.tryParse(
        (invoice['discount'] ?? invoice['discount_amount'] ?? '0').toString(),
      ) ?? 0;

      // Resolve seller name (bilingual)
      final sellerNameRaw = pick([seller['name'], branch['seller_name'], branch['name']]);
      String sellerNameAr = sellerNameRaw;
      String sellerNameEn = sellerNameRaw;
      if (sellerNameRaw.contains(' - ') || sellerNameRaw.contains(' | ')) {
        final sep = sellerNameRaw.contains(' | ') ? ' | ' : ' - ';
        sellerNameAr = sellerNameRaw.split(sep).first.trim();
        sellerNameEn = sellerNameRaw.split(sep).last.trim();
      }

      // Resolve logo
      String? logoUrl = pickNullable([
        seller['logo'], originalSeller['logo'],
        branch['logo'], branch['image'],
      ]);
      if (logoUrl != null && logoUrl.startsWith('/')) {
        logoUrl = 'https://portal.hermosaapp.com$logoUrl';
      }

      return OrderReceiptData(
        invoiceNumber: pick([invoice['invoice_number'], invoiceNumber]),
        issueDateTime: pick([invoice['ISO8601'], invoice['date']]),
        sellerNameAr: sellerNameAr,
        sellerNameEn: sellerNameEn,
        vatNumber: pick([
          seller['tax_number'], originalSeller['tax_number'],
          branch['tax_number'], seller['vat_number'],
        ]),
        branchName: pick([branch['seller_name'], branch['name']]),
        items: items,
        totalExclVat: totalExcl,
        vatAmount: tax,
        totalInclVat: grandTotal,
        paymentMethod: pick([invoice['payment_methods']]),
        payments: payments,
        qrCodeBase64: pick([envelope['qr_image'], invoice['qr_image']]),
        sellerLogo: logoUrl,
        zatcaQrImage: pickNullable([envelope['qr_image'], invoice['qr_image'], invoice['zatca_qr_image']]),
        branchAddress: pickNullable([branch['address'], branch['district']]),
        branchAddressEn: pickNullable([branch['address_en'], branch['district_en']]),
        branchMobile: pickNullable([branch['mobile'], branch['phone']]),
        commercialRegisterNumber: pickNullable([
          seller['commercial_register'], originalSeller['commercial_register'],
          branch['commercial_number'], seller['commercial_register_number'],
        ]),
        cashierName: pickNullable([
          invoice['cashier'] is Map ? (invoice['cashier'] as Map)['fullname'] : null,
          invoice['cashier_name'],
        ]),
        orderNumber: effectiveOrderNumber,
        orderType: orderType,
        clientName: clientName,
        clientPhone: clientPhone,
        orderDiscountAmount: discountAmount > 0 ? discountAmount : null,
        issueDate: pickNullable([invoice['date']]),
        issueTime: pickNullable([invoice['time']]),
      );
    } catch (e) {
      debugPrint('⚠️ Failed to build receipt data from invoice: $e');
      return null;
    }
  }

  /// Print cashier receipt ONLY for a pay-later order that just got invoiced.
  /// NO kitchen ticket — food was already prepared.
  Future<void> _printCashierReceiptForOrder({
    String? invoiceId,
    String? invoiceNumber,
    String? dailyOrderNumber,
  }) async {
    try {
      if (invoiceId == null || invoiceId.isEmpty) {
        debugPrint('⚠️ _printCashierReceiptForOrder: no invoiceId, skipping');
        return;
      }

      final deviceService = getIt<DeviceService>();
      final printerService = getIt<PrinterService>();
      final roleRegistry = getIt<PrinterRoleRegistry>();
      await roleRegistry.initialize();

      final devices = await deviceService.getDevices();
      final cashierPrinters = devices.where((d) {
        if (d.ip.isEmpty && (d.bluetoothAddress?.isEmpty ?? true)) return false;
        final role = roleRegistry.resolveRole(d);
        return role == PrinterRole.cashierReceipt || role == PrinterRole.general;
      }).toList();

      if (cashierPrinters.isEmpty) {
        debugPrint('ℹ️ No cashier printer for order invoice print');
        return;
      }

      // Fetch full invoice details for receipt data
      final invoiceResponse = await _orderService.getInvoice(invoiceId);
      final rawEnvelope = invoiceResponse.map((k, v) => MapEntry(k.toString(), v));
      final envelope = (rawEnvelope['data'] is Map)
          ? (rawEnvelope['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
          : rawEnvelope;

      final invoice = (envelope['invoice'] is Map)
          ? envelope['invoice'] as Map<String, dynamic>
          : envelope;
      final branch = (envelope['branch'] is Map)
          ? envelope['branch'] as Map<String, dynamic>
          : <String, dynamic>{};
      final seller = (branch['seller'] is Map)
          ? branch['seller'] as Map<String, dynamic>
          : <String, dynamic>{};

      String _pick(List<dynamic> candidates) {
        for (final c in candidates) {
          final t = c?.toString().trim();
          if (t != null && t.isNotEmpty && t.toLowerCase() != 'null') return t;
        }
        return '';
      }

      final items = (invoice['items'] as List?)?.map((item) {
        final m = item is Map ? item : <String, dynamic>{};
        final price = double.tryParse(m['meal_price']?.toString() ?? '') ??
            double.tryParse(m['total']?.toString() ?? '') ?? 0;
        return ReceiptItem(
          nameAr: m['item_name']?.toString() ?? '',
          nameEn: m['item_name']?.toString() ?? '',
          quantity: double.tryParse(m['quantity']?.toString() ?? '') ?? 1,
          unitPrice: price,
          total: price,
        );
      }).toList() ?? [];

      final totalStr = invoice['total']?.toString() ?? '0';
      final taxStr = invoice['tax']?.toString() ?? '0';
      final grandStr = invoice['grand_total']?.toString() ?? totalStr;
      final totalExcl = double.tryParse(totalStr) ?? 0;
      final tax = double.tryParse(taxStr) ?? 0;
      final grandTotal = double.tryParse(grandStr) ?? (totalExcl + tax);

      final receiptData = OrderReceiptData(
        invoiceNumber: _pick([invoice['invoice_number'], invoiceNumber]),
        issueDateTime: _pick([invoice['ISO8601'], invoice['date']]),
        sellerNameAr: _pick([branch['seller_name']]),
        sellerNameEn: _pick([branch['seller_name']]),
        vatNumber: _pick([seller['tax_number'], branch['tax_number']]),
        branchName: _pick([branch['seller_name']]),
        items: items,
        totalExclVat: totalExcl,
        vatAmount: tax,
        totalInclVat: grandTotal,
        paymentMethod: _pick([invoice['payment_methods']]),
        qrCodeBase64: _pick([envelope['qr_image'], invoice['qr_image']]),
        branchAddress: _pick([branch['address'], branch['district']]),
        branchMobile: _pick([branch['mobile']]),
        commercialRegisterNumber: _pick([seller['commercial_register']]),
        cashierName: _pick([(invoice['cashier'] is Map ? invoice['cashier']['fullname'] : null)]),
        orderNumber: dailyOrderNumber,
        issueDate: _pick([invoice['date']]),
        issueTime: _pick([invoice['time']]),
      );

      for (final printer in cashierPrinters) {
        try {
          await printerService.printReceipt(printer, receiptData, jobType: 'cashier');
        } catch (e) {
          debugPrint('⚠️ Cashier receipt print failed for order invoice: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to print cashier receipt for order: $e');
    }
  }
}
