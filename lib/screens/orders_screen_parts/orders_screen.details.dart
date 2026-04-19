// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../orders_screen.dart';

extension OrdersScreenDetails on _OrdersScreenState {
  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> _loadRefundedMealsForBooking(
    int orderId,
  ) async {
    try {
      return await _orderService.getRefundedMeals(
        bookingId: orderId.toString(),
      );
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> _showBookingDetails(int orderId) async {
    try {
      final details = await _orderService.getBookingDetails(orderId.toString());
      final enrichedDetails = await _enrichBookingDetailsForDialog(
        orderId: orderId,
        details: details,
      );
      _orderDetailsRawResponse = enrichedDetails;
      if (!mounted) return;
      Booking? selectedBooking;
      for (final booking in _bookings) {
        if (booking.id == orderId) {
          selectedBooking = booking;
          break;
        }
      }
      final canEdit = selectedBooking != null
          ? _canCreateInvoiceForBooking(selectedBooking)
          : false;
      showDialog(
        context: context,
        builder: (context) => BookingDetailsDialog(
          bookingData: enrichedDetails,
          onEditOrder: canEdit && selectedBooking != null
              ? () => _showEditOrderDialog(selectedBooking!)
              : null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Booking? localBooking;
      for (final booking in _bookings) {
        if (booking.id == orderId) {
          localBooking = booking;
          break;
        }
      }

      if (localBooking != null) {
        List<Map<String, dynamic>> invoiceItems = const [];
        double? invoiceTax;
        double? invoiceGrandTotal;
        try {
          final invoiceId = await _resolveInvoiceIdForBooking(orderId);
          if (invoiceId != null) {
            final invoiceDetails =
                await _orderService.getInvoice(invoiceId.toString());
            final invoicePayload = invoiceDetails['data'];
            final invoiceMap = invoicePayload is Map
                ? (invoicePayload['invoice'] is Map
                    ? (invoicePayload['invoice'] as Map)
                    : invoicePayload)
                : null;
            if (invoiceMap is Map) {
              invoiceTax = _parseNum(invoiceMap['tax'] ?? invoiceMap['vat']);
              invoiceGrandTotal = _parseNum(
                invoiceMap['grand_total'] ??
                    invoiceMap['invoice_total'] ??
                    invoiceMap['total'],
              );

              final possibleItemKeys = [
                'items',
                'invoice_items',
                'meals',
                'booking_meals',
                'booking_products',
                'sales_meals',
                'card',
                'cart',
              ];
              for (final key in possibleItemKeys) {
                final rawItems =
                    invoiceMap[key] ?? (invoicePayload as Map)[key];
                if (rawItems is List) {
                  invoiceItems = rawItems
                      .whereType<Map>()
                      .map((e) => e.map((k, v) => MapEntry(k.toString(), v))
                        ..putIfAbsent(
                          'meal_name',
                          () => e['name'] ?? e['item_name'],
                        ))
                      .toList();
                  if (invoiceItems.isNotEmpty) break;
                }
              }
            }
          }
        } catch (_) {
          // Keep local fallback only.
        }

        if (!mounted) return;
        final refundedMeals = await _loadRefundedMealsForBooking(orderId);
        final rawItems = invoiceItems.isNotEmpty
            ? invoiceItems
            : localBooking.meals
                .map(
                  (m) => {
                    'id': m.id,
                    'meal_id': m.mealId,
                    'meal_name': m.mealName,
                    'quantity': m.quantity,
                    'unit_price': m.unitPrice,
                    'total': m.total,
                    'notes': m.notes,
                  },
                )
                .toList();
        final fallbackData = {
          'data': {
            'id': localBooking.id,
            'order_number': localBooking.orderNumber ?? localBooking.id,
            'status': localBooking.status,
            'date': localBooking.date,
            'total': localBooking.total,
            'tax': invoiceTax ?? localBooking.tax,
            'discount': localBooking.discount,
            'grand_total': invoiceGrandTotal ?? localBooking.total,
            'customer_name': localBooking.customerName,
            'customer_phone': localBooking.customerPhone,
            'table_name': localBooking.tableName,
            'notes': localBooking.notes,
            'meals': rawItems,
            if (refundedMeals.isNotEmpty) 'refunded_meals': refundedMeals,
          },
        };
        showDialog(
          context: context,
          builder: (context) => BookingDetailsDialog(
            bookingData: fallbackData,
            onEditOrder: localBooking != null &&
                    _canCreateInvoiceForBooking(localBooking)
                ? () => _showEditOrderDialog(localBooking!)
                : null,
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr(
                'تعذر تحميل التفاصيل من السيرفر، تم عرض البيانات المحلية',
                'Server details unavailable, local data is shown instead.',
              ),
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'تعذر جلب تفاصيل الطلب: $e',
              'Unable to fetch order details: $e',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _showEditOrderDialog(Booking booking) async {
    final canEditPayLater = _canCreateInvoiceForBooking(booking);
    if (!canEditPayLater) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr(
            'التعديل مسموح فقط لطلبات الدفع لاحقاً وغير مدفوعة',
            'Editing is allowed only for unpaid pay-later orders',
          )),
        ),
      );
      return;
    }
    final locked = isOrderLockedValue(booking.status) ||
        isOrderLockedValue(booking.raw['status']);
    if (locked) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('لا يمكن تعديل الطلب بعد إغلاقه',
              'Order can no longer be edited')),
        ),
      );
      return;
    }

    Map<String, dynamic> details;
    try {
      final rawDetails =
          await _orderService.getBookingDetails(booking.id.toString());
      details = await _enrichBookingDetailsForDialog(
        orderId: booking.id,
        details: rawDetails,
      );
    } catch (e) {
      details = {
        'data': {
          'id': booking.id,
          'order_number': booking.orderNumber ?? booking.id,
          'status': booking.status,
          'type': booking.type,
          'notes': booking.notes,
          'meals': booking.meals
              .map(
                (m) => {
                  'id': m.id,
                  'meal_id': m.mealId,
                  'meal_name': m.mealName,
                  'quantity': m.quantity,
                  'unit_price': m.unitPrice,
                  'total': m.total,
                  'notes': m.notes,
                },
              )
              .toList(),
        },
      };
      if (mounted) {
        final message = ErrorHandler.toUserMessage(
          e,
          fallback: _tr(
            'تعذر تحميل التفاصيل من السيرفر، تم عرض البيانات المحلية',
            'Server details unavailable, local data is shown instead.',
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    }

    if (!mounted) return;
    final updated = await showDialog<bool>(
      context: context,
      builder: (context) => EditOrderDialog(
        booking: booking,
        bookingData: details,
        onPrintChanges: widget.onPrintOrderChanges,
      ),
    );

    if (updated == true) {
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('تم تحديث الطلب', 'Order updated')),
        ),
      );
    }
  }

  Future<Map<String, dynamic>> _enrichBookingDetailsForDialog({
    required int orderId,
    required Map<String, dynamic> details,
  }) async {
    var payload = details['data'] is Map
        ? Map<String, dynamic>.from(details['data'] as Map)
        : Map<String, dynamic>.from(details);
    // API nests booking data inside 'booking' key — flatten it so the dialog
    // can find id, booking_number, daily_order_number, etc. at the top level.
    if (payload['booking'] is Map && payload['id'] == null) {
      final inner = Map<String, dynamic>.from(payload['booking'] as Map);
      for (final e in payload.entries) {
        if (e.key != 'booking') inner.putIfAbsent(e.key, () => e.value);
      }
      payload = inner;
    }
    // Ensure orderId is always present
    payload['id'] ??= orderId;

    String? resolveLocalized(dynamic value) {
      if (value == null) return null;
      if (value is Map) {
        final langCode = translationService.currentLanguageCode
            .trim()
            .toLowerCase();
        final useAr =
            langCode.startsWith('ar') || langCode.startsWith('ur');
        final preferred = useAr ? 'ar' : 'en';
        final localized = value[preferred]?.toString().trim();
        if (localized != null && localized.isNotEmpty) return localized;
        for (final v in value.values) {
          final s = v?.toString().trim() ?? '';
          if (s.isNotEmpty) return s;
        }
        return null;
      }
      var s = value.toString().trim();
      if (s.startsWith('{') && s.contains('"ar"')) {
        try {
          final parsed = Map<String, dynamic>.from(jsonDecode(s) as Map);
          return resolveLocalized(parsed);
        } catch (_) {}
      }
      return s.isNotEmpty ? s : null;
    }

    String? pickMealName(Map<String, dynamic> normalized) {
      final mealMap = normalized['meal'] is Map
          ? (normalized['meal'] as Map)
          : null;
      return resolveLocalized(normalized['meal_name']) ??
          resolveLocalized(normalized['name']) ??
          resolveLocalized(normalized['item_name']) ??
          (mealMap != null ? resolveLocalized(mealMap['name']) : null);
    }

    // Build a lookup from booking_meals by meal_id for price enrichment
    Map<String, Map<String, dynamic>> buildPriceLookup(dynamic source) {
      if (source is! Map) return const {};
      final m = source.map((k, v) => MapEntry(k.toString(), v));
      final lookup = <String, Map<String, dynamic>>{};
      for (final key in ['booking_meals', 'meals', 'items']) {
        final raw = m[key];
        if (raw is! List) continue;
        for (final item in raw) {
          if (item is! Map) continue;
          final row = item.map((k, v) => MapEntry(k.toString(), v));
          final id = (row['id'] ?? row['meal_id'])?.toString();
          if (id != null && id.isNotEmpty) lookup[id] = row;
        }
      }
      return lookup;
    }

    void enrichWithPrice(Map<String, dynamic> item, Map<String, Map<String, dynamic>> priceLookup) {
      final hasPrice = item['price'] != null || item['unit_price'] != null || item['total'] != null;
      if (hasPrice) return;
      // Try to find price from booking_meals by meal_id or id
      final mealId = (item['meal_id'] ?? item['id'])?.toString();
      if (mealId != null && priceLookup.containsKey(mealId)) {
        final src = priceLookup[mealId]!;
        item['price'] ??= src['price'];
        item['unit_price'] ??= src['unit_price'] ?? src['price'];
        item['total'] ??= src['total'] ?? src['price'];
      }
      // Also try nested meal object
      if (item['price'] == null && item['meal'] is Map) {
        final mealObj = (item['meal'] as Map);
        item['price'] ??= mealObj['price'];
        item['unit_price'] ??= mealObj['unit_price'] ?? mealObj['price'];
        item['total'] ??= mealObj['price'];
      }
    }

    List<Map<String, dynamic>> extractItems(dynamic source) {
      if (source is! Map) return const [];
      final map = source.map((k, v) => MapEntry(k.toString(), v));
      final priceLookup = buildPriceLookup(source);
      final sections = map['sections'];
      if (sections is List) {
        final sectionItems = <Map<String, dynamic>>[];
        for (final section in sections) {
          if (section is! Map) continue;
          final sectionMap = section.map((k, v) => MapEntry(k.toString(), v));
          final items = sectionMap['items'];
          if (items is List) {
            for (final item in items) {
              if (item is Map) {
                final normalized =
                    item.map((k, v) => MapEntry(k.toString(), v));
                final resolvedName = pickMealName(normalized);
                if (resolvedName != null) {
                  normalized['meal_name'] = resolvedName;
                }
                enrichWithPrice(normalized, priceLookup);
                sectionItems.add(normalized);
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
        final raw = map[key];
        if (raw is List) {
          final rows = raw.whereType<Map>().map((e) {
            final normalized = e.map((k, v) => MapEntry(k.toString(), v));
            final resolvedName = pickMealName(normalized);
            if (resolvedName != null) {
              normalized['meal_name'] = resolvedName;
            }
            return normalized;
          }).toList();
          if (rows.isNotEmpty) return rows;
        }
      }
      return const [];
    }

    final hasItems = extractItems(payload).isNotEmpty;
    final currentTax = _parseNum(
      payload['tax'] ??
          payload['vat'] ??
          payload['tax_value'] ??
          payload['tax_amount'],
    );
    final hasTax = currentTax > 0;
    final refundedMeals = await _loadRefundedMealsForBooking(orderId);

    try {
      final invoiceId = await _resolveInvoiceIdForBooking(orderId);
      if (invoiceId != null) {
        Map<String, dynamic> invoiceDetails;
        try {
          invoiceDetails = await _orderService.getInvoice(invoiceId.toString());
        } catch (_) {
          invoiceDetails =
              await _orderService.getInvoiceHelper(invoiceId.toString());
        }

        final invoicePayload = invoiceDetails['data'];
        final invoicePayloadMap = invoicePayload is Map
            ? invoicePayload.map((k, v) => MapEntry(k.toString(), v))
            : <String, dynamic>{};
        final invoiceData = invoicePayloadMap['invoice'] is Map
            ? (invoicePayloadMap['invoice'] as Map)
                .map((k, v) => MapEntry(k.toString(), v))
            : Map<String, dynamic>.from(invoicePayloadMap);

        final invoiceItems = extractItems(invoiceData).isNotEmpty
            ? extractItems(invoiceData)
            : extractItems(invoicePayloadMap);
        if (invoiceItems.isNotEmpty) {
          payload['meals'] = invoiceItems;
        } else if (!hasItems) {
          payload['meals'] = const <Map<String, dynamic>>[];
        }

        final invoiceTaxValue = invoiceData['tax'] ??
            invoiceData['vat'] ??
            invoiceData['tax_value'] ??
            invoiceData['tax_amount'] ??
            invoicePayloadMap['tax'] ??
            invoicePayloadMap['tax_value'];
        if (_parseNum(invoiceTaxValue) > 0) {
          payload['tax'] = invoiceTaxValue;
        } else if (!hasTax && currentTax > 0) {
          payload['tax'] = currentTax;
        }

        final invoiceSubtotalValue = invoiceData['sub_total'] ??
            invoiceData['total_before_tax'] ??
            invoicePayloadMap['sub_total'] ??
            invoicePayloadMap['total_before_tax'];
        if (_parseNum(invoiceSubtotalValue) > 0) {
          payload['total'] = invoiceSubtotalValue;
        } else {
          // Calculate subtotal = grand_total - tax when sub_total is missing
          final invoiceTotal = _parseNum(
            invoiceData['grand_total'] ??
                invoiceData['invoice_total'] ??
                invoiceData['total'] ??
                invoicePayloadMap['grand_total'] ??
                invoicePayloadMap['total'],
          );
          final invoiceTax = _parseNum(
            invoiceData['tax'] ??
                invoiceData['vat'] ??
                invoiceData['tax_value'] ??
                invoicePayloadMap['tax'] ??
                invoicePayloadMap['tax_value'],
          );
          if (invoiceTotal > 0 && invoiceTax > 0) {
            payload['total'] = invoiceTotal - invoiceTax;
          } else if (invoiceTotal > 0 && _parseNum(payload['total']) <= 0) {
            payload['total'] = invoiceTotal;
          }
        }

        final invoiceGrandTotalValue = invoiceData['grand_total'] ??
            invoiceData['invoice_total'] ??
            invoiceData['final_total'] ??
            invoiceData['total'] ??
            invoicePayloadMap['grand_total'] ??
            invoicePayloadMap['invoice_total'] ??
            invoicePayloadMap['final_total'] ??
            invoicePayloadMap['total'];
        if (_parseNum(invoiceGrandTotalValue) > 0) {
          payload['grand_total'] = invoiceGrandTotalValue;
        } else if (_parseNum(payload['grand_total']) <= 0) {
          payload['grand_total'] = payload['total'];
        }

        final invoiceNumber = (invoiceData['invoice_number'] ??
                invoicePayloadMap['invoice_number'])
            ?.toString()
            .trim();
        if (invoiceNumber != null && invoiceNumber.isNotEmpty) {
          payload['invoice_number'] = invoiceNumber;
        }

        final invoiceStatus =
            (invoiceData['status'] ?? invoicePayloadMap['status'])
                ?.toString()
                .trim();
        if (invoiceStatus != null && invoiceStatus.isNotEmpty) {
          payload['invoice_status'] = invoiceStatus;
        }

        payload['invoice_id'] ??=
            invoiceData['id'] ?? invoicePayloadMap['id'] ?? invoiceId;
      }
    } catch (_) {
      // Keep available booking payload.
    }

    // Pass raw items + refunded_meals separately.
    // BookingDetailsDialog._extractMeals handles the single merge.
    if (refundedMeals.isNotEmpty) {
      payload['refunded_meals'] = refundedMeals;
    }

    return {'data': payload};
  }

  Future<int?> _resolveInvoiceIdForBooking(int orderId) async {
    final bookingIdText = orderId.toString();

    // 1) Dedicated booking->invoice endpoint.
    try {
      final invoice = await _orderService.getBookingInvoice(bookingIdText);
      _orderInvoiceRawResponse = invoice;
      final directId = _extractInvoiceId(invoice, strict: false);
      if (directId != null) return directId;
    } catch (_) {
      // Continue with fallbacks.
    }

    // 2) Booking details may include invoice_id.
    try {
      final bookingDetails =
          await _orderService.getBookingDetails(bookingIdText);
      final bookingData = bookingDetails['data'];
      if (bookingData is Map) {
        final normalized = bookingData.map((k, v) => MapEntry(k.toString(), v));
        final idFromDetails = _extractInvoiceId(normalized, strict: false);
        if (idFromDetails != null) return idFromDetails;
      }
    } catch (_) {
      // Continue with list fallback.
    }

    // 3) Search invoices list and match by booking/order id.
    try {
      final invoicesResponse = await _orderService.getInvoices(
        page: 1,
        perPage: 100,
        search: bookingIdText,
      );
      final list = _extractListResponse(invoicesResponse);
      if (list is List) {
        for (final row in list.whereType<Map>()) {
          final item = row.map((k, v) => MapEntry(k.toString(), v));
          final rowBookingId = item['booking_id']?.toString();
          final rowOrderId = item['order_id']?.toString();
          if (rowBookingId == bookingIdText || rowOrderId == bookingIdText) {
            final invoiceId = _extractInvoiceId(item, strict: true);
            if (invoiceId != null) return invoiceId;
          }
        }
      }
    } catch (_) {
      // Final failure handled by caller.
    }

    return null;
  }

  int? _extractInvoiceId(
    Map<String, dynamic> payload, {
    bool strict = false,
  }) {
    int? parseId(dynamic idValue) {
      if (idValue is int) return idValue;
      if (idValue is String) return int.tryParse(idValue);
      return null;
    }

    bool looksLikeInvoiceMap(Map<String, dynamic> map) {
      if (map['invoice_id'] != null) return true;
      if (map['invoice_number'] != null) return true;
      if (map['invoice'] is Map) return true;
      return false;
    }

    final directInvoiceId = parseId(payload['invoice_id']);
    if (directInvoiceId != null) return directInvoiceId;

    if (!strict && looksLikeInvoiceMap(payload)) {
      final rootId = parseId(payload['id']);
      if (rootId != null) return rootId;
    }

    final data = payload['data'];
    if (data is Map) {
      final normalized = data.map((k, v) => MapEntry(k.toString(), v));

      final explicitId = parseId(normalized['invoice_id']);
      if (explicitId != null) return explicitId;

      final nestedInvoice = normalized['invoice'];
      if (nestedInvoice is Map) {
        final normalizedInvoice = nestedInvoice.map(
          (k, v) => MapEntry(k.toString(), v),
        );
        final nestedId = parseId(
          normalizedInvoice['invoice_id'] ?? normalizedInvoice['id'],
        );
        if (nestedId != null) return nestedId;
      }

      if (looksLikeInvoiceMap(normalized)) {
        final mapId = parseId(normalized['id']);
        if (mapId != null) return mapId;
      }
    }

    if (data is List) {
      for (final row in data.whereType<Map>()) {
        final normalized = row.map((k, v) => MapEntry(k.toString(), v));

        final explicitId = parseId(normalized['invoice_id']);
        if (explicitId != null) return explicitId;

        final nestedInvoice = normalized['invoice'];
        if (nestedInvoice is Map) {
          final normalizedInvoice = nestedInvoice.map(
            (k, v) => MapEntry(k.toString(), v),
          );
          final nestedId = parseId(
            normalizedInvoice['invoice_id'] ?? normalizedInvoice['id'],
          );
          if (nestedId != null) return nestedId;
        }

        if (looksLikeInvoiceMap(normalized)) {
          final listId = parseId(normalized['id']);
          if (listId != null) return listId;
        }
      }
    }

    if (!strict) {
      final permissiveId = parseId(payload['id']);
      if (permissiveId != null) return permissiveId;

      // Fallback: data.id when response has no typical invoice fields
      if (data is Map) {
        final dataId = parseId(
          (data as Map).map((k, v) => MapEntry(k.toString(), v))['id'],
        );
        if (dataId != null) return dataId;
      }
    }

    return null;
  }
}
