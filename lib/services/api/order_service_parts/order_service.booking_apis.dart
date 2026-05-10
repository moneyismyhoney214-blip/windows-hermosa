// ignore_for_file: unused_element, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../order_service.dart';

extension OrderServiceBookingApis on OrderService {
  /// Create a new booking/order
  /// [paymentType] is 'payment' for pay-now or 'later' for deferred payment
  Future<Map<String, dynamic>> createBooking(
    Map<String, dynamic> bookingData, {
    String paymentType = 'payment',
  }) async {
    // OFFLINE MODE: Save locally and queue for sync
    if (_connectivity.isOffline) {
      return _createBookingOffline(bookingData, paymentType: paymentType);
    }

    final normalizedPayload = _normalizeBookingPayload(bookingData);
    Map<String, dynamic> applyCacheSideEffect(Map<String, dynamic> response) {
      // Prepend the freshly-created booking to today's cached lists so the
      // orders screen renders it instantly on next open. The screen
      // otherwise paints stale cached data (without the new row) for 3-4s
      // while the network refresh runs.
      unawaited(_pushCreatedBookingToCache(response));
      // Drop the (employee, service, date) slot cache too — the slot the
      // cashier just consumed is still in there for up to 2 minutes, and
      // without this purge the next customer sees the same time as
      // available and the cashier ends up double-booking the employee.
      try {
        getIt<SalonEmployeeService>().invalidateAvailableTimesCache();
      } catch (_) {}
      return response;
    }

    try {
      return applyCacheSideEffect(
        await _createBookingWithJsonRetry(normalizedPayload),
      );
    } on ApiException catch (e) {
      final hasMeals = normalizedPayload['meals'] is List;
      final hasCard = normalizedPayload['card'] is List;
      final needsCardFallback =
          hasMeals && !hasCard && e.message.contains('السلة');
      if (needsCardFallback) {
        final fallbackPayload = Map<String, dynamic>.from(normalizedPayload);
        fallbackPayload['card'] = fallbackPayload.remove('meals');
        try {
          return applyCacheSideEffect(
            await _createBookingWithJsonRetry(fallbackPayload),
          );
        } on ApiException catch (_) {}
        try {
          return applyCacheSideEffect(
            await _createBookingMultipart(fallbackPayload),
          );
        } on ApiException catch (_) {}
      }

      final normalizedType =
          normalizedPayload['type']?.toString().trim().toLowerCase() ?? '';
      final hasUnhandledNullMatch = (e.statusCode ?? 0) >= 500 &&
          e.message.toLowerCase().contains('unhandled match case null');

      if (hasUnhandledNullMatch) {
        final nullSafePayload = Map<String, dynamic>.from(normalizedPayload);
        final typeExtraRaw = nullSafePayload['type_extra'];
        if (typeExtraRaw is Map) {
          nullSafePayload['type_extra'] = typeExtraRaw.map(
            (key, value) => MapEntry(
              key.toString(),
              value ?? '',
            ),
          );
        }

        try {
          return applyCacheSideEffect(
            await _createBookingWithJsonRetry(nullSafePayload),
          );
        } on ApiException catch (_) {}

        try {
          return applyCacheSideEffect(
            await _createBookingMultipart(nullSafePayload),
          );
        } on ApiException catch (_) {}
      }

      if (e.statusCode == 422 &&
          _isDeliveryOrderType(normalizedType) &&
          _requiresDeliveryCoordsFallback(e.message)) {
        final deliveryFallback = _normalizeBookingPayload(
          normalizedPayload,
          forceDeliveryCoordinates: true,
        );
        try {
          return applyCacheSideEffect(
            await _createBookingWithJsonRetry(deliveryFallback),
          );
        } on ApiException catch (_) {}
        try {
          return applyCacheSideEffect(
            await _createBookingMultipart(deliveryFallback),
          );
        } on ApiException catch (_) {}
      }

      if (e.statusCode == 422 && _isInvalidType422(e.message)) {
        final candidates = _bookingTypeFallbackCandidates(normalizedType);
        for (final candidateType in candidates) {
          final typeFallbackPayload =
              Map<String, dynamic>.from(normalizedPayload)
                ..['type'] = candidateType;
          try {
            return applyCacheSideEffect(
              await _createBookingWithJsonRetry(typeFallbackPayload),
            );
          } on ApiException catch (_) {}
          try {
            return applyCacheSideEffect(
              await _createBookingMultipart(typeFallbackPayload),
            );
          } on ApiException catch (_) {}
        }
      }

      if (e.statusCode == 422) {
        try {
          return applyCacheSideEffect(
            await _createBookingMultipart(normalizedPayload),
          );
        } on ApiException catch (_) {}
      }
      rethrow;
    }
  }

  /// Prepend a freshly-created booking row to today's cached `bookings_*`
  /// entries so the orders screen renders it instantly on next open. The
  /// cache key encodes (dateFrom, dateTo, status, search); we update every
  /// today-keyed entry so the order shows up regardless of the active
  /// filter chip. Errors here must never propagate — a stale cache is far
  /// less harmful than a failed booking creation.
  Future<void> _pushCreatedBookingToCache(
    Map<String, dynamic> createResponse,
  ) async {
    try {
      final bookingRow = _extractBookingRowFromCreateResponse(createResponse);
      if (bookingRow == null) return;
      final today = DateTime.now();
      final todayStr =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final prefixes = <String>[
        'bookings_${todayStr}_$todayStr',
        'bookings_${todayStr}_null',
        'bookings_null_$todayStr',
        'bookings_null_null',
      ];
      final updatedKeys = <String>{};
      for (final prefix in prefixes) {
        final keys = await _cache.keysWithPrefix(prefix);
        for (final key in keys) {
          if (!updatedKeys.add(key)) continue;
          final cached = await _cache.get(key);
          if (cached is! Map) continue;
          final cachedMap = cached.map((k, v) => MapEntry(k.toString(), v));
          final dataField = cachedMap['data'];
          if (dataField is! List) continue;
          final dataList = List<dynamic>.from(dataField);
          final newId = bookingRow['id'];
          if (newId != null &&
              dataList.any((row) =>
                  row is Map &&
                  (row['id'] == newId || row['id']?.toString() == newId.toString()))) {
            continue; // already present
          }
          dataList.insert(0, bookingRow);
          cachedMap['data'] = dataList;
          await _cache.set(
            key,
            cachedMap,
            expiry: const Duration(minutes: 30),
          );
        }
      }
    } catch (e) {
      print('⚠️ optimistic booking cache update failed: $e');
    }
  }

  Map<String, dynamic>? _extractBookingRowFromCreateResponse(
    Map<String, dynamic> response,
  ) {
    final data = response['data'];
    Map? candidate;
    if (data is Map) {
      // Common shape: { data: { booking: { ... } } } or { data: { ... } }.
      if (data['booking'] is Map) {
        candidate = data['booking'] as Map;
      } else if (data['id'] != null || data['booking_number'] != null) {
        candidate = data;
      }
    } else if (data is List && data.isNotEmpty && data.first is Map) {
      candidate = data.first as Map;
    } else if (response['booking'] is Map) {
      candidate = response['booking'] as Map;
    } else if (response['id'] != null) {
      candidate = response;
    }
    if (candidate == null) return null;
    return candidate.map((k, v) => MapEntry(k.toString(), v));
  }

  /// Create drive-through booking using official payload format.
  Future<Map<String, dynamic>> createDriveThroughBooking({
    required int customerId,
    required List<Map<String, dynamic>> card,
    String? carNumber,
    String? tableName,
    String? latitude,
    String? longitude,
  }) async {
    final payload = <String, dynamic>{
      'customer_id': customerId,
      'card': card,
      'type': 'restaurant_parking',
      'type_extra': {
        'car_number': carNumber,
        'table_name': tableName,
        'latitude': latitude,
        'longitude': longitude,
      },
    };
    return createBooking(payload);
  }

  /// Synchronous-ish read of the most recent cached bookings response for
  /// the same filters used by [getBookings]. Returns `null` when nothing is
  /// cached yet. Intended for salon-mode optimistic UI: paint stale data
  /// instantly while the network call refreshes in the background.
  Future<Map<String, dynamic>?> getCachedBookings({
    String? status,
    String? type,
    String? dateFrom,
    String? dateTo,
    String? search,
  }) async {
    final cacheKey = 'bookings_${[dateFrom, dateTo, status, search].join('_')}';
    final cached = await _cache.get(cacheKey);
    if (cached is Map<String, dynamic>) return cached;
    if (cached is Map) {
      return cached.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  /// Get bookings list with filters (offline-first)
  Future<Map<String, dynamic>> getBookings({
    String? status,
    String? type,
    String? dateFrom,
    String? dateTo,
    String? search,
    int page = 1,
    int perPage = 20,
    String platform = 'dashboard',
    bool skipGlobalAuth = false,
  }) async {
    // OFFLINE MODE
    if (_connectivity.isOffline) {
      return _getBookingsOffline();
    }

    // Check if token is available first
    final token = _client.getToken();
    if (token == null || token.isEmpty) {
      print('⚠️ getBookings: No token available');
      throw UnauthorizedException('No authentication token');
    }

    final queryParams = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
      'platform': platform,
    };
    if (status != null && status.isNotEmpty) queryParams['status'] = status;
    if (type != null) queryParams['type'] = type;
    if (dateFrom != null) queryParams['date_from'] = dateFrom;
    if (dateTo != null) queryParams['date_to'] = dateTo;
    if (search != null && search.isNotEmpty) queryParams['search'] = search;

    final queryString = Uri(queryParameters: queryParams).query;
    final endpoint = queryString.isNotEmpty
        ? '${ApiConstants.bookingsEndpoint}?$queryString'
        : ApiConstants.bookingsEndpoint;
    final cacheKey = 'bookings_${[dateFrom, dateTo, status, search].join('_')}';

    try {
      final response =
          await _client.get(endpoint, skipGlobalAuth: skipGlobalAuth);
      final normalized = _rememberResponse('get_all_orders', response);
      if (response != null && page == 1) {
        // Cache the result for resilience
        await _cache.set(
          cacheKey,
          normalized,
          expiry: const Duration(minutes: 30),
        );
        // Save to SQLite for offline
        if (normalized['data'] is List) {
          await _offlineDb.saveServerOrders(
            (normalized['data'] as List).cast<Map<String, dynamic>>(),
            ApiConstants.branchId,
          );
        }
      }
      return normalized;
    } catch (e) {
      // Fallback to offline
      final offline = await _getBookingsOffline();
      if ((offline['data'] as List?)?.isNotEmpty == true) return offline;
      if (page == 1) {
        final cached = await _cache.get(cacheKey);
        if (cached != null) return cached;
      }
      rethrow;
    }
  }

  BookingSettings _emptyBookingSettings() {
    // Safe runtime defaults when backend create-metadata endpoint is unstable.
    return BookingSettings(
      typeOptions: [
        OptionItem(label: 'محلي', value: 'services'),
        OptionItem(label: 'استلام من الفرع', value: 'restaurant_pickup'),
        OptionItem(label: 'داخل المطعم', value: 'restaurant_internal'),
        OptionItem(label: 'توصيل', value: 'restaurant_delivery'),
        OptionItem(label: 'سيارة', value: 'restaurant_parking'),
      ],
      tableOptions: [],
    );
  }

  String _buildBookingCreateMetadataEndpointWithDefaults() {
    // Backend create endpoint expects these filters; calling without them
    // may trigger "Unhandled match case NULL" on some branches. Salon
    // branches need `type=services` — passing `meals` there returns an empty
    // catalogue and the debug dump shows a misleading response.
    final type = ApiConstants.branchModule == 'salons' ? 'services' : 'meals';
    final query = Uri(queryParameters: <String, String>{
      'type': type,
      'is_favourite': '0',
      'category_id': '',
      'is_home': '0',
      'is_delivery': '0',
      'page': '1',
      'search': '',
      'limit': '100',
      'per_page': '100',
    }).query;
    return '${ApiConstants.bookingCreateMetadataEndpoint}?$query';
  }

  BookingSettings? _parseBookingSettingsResponse(dynamic response) {
    final normalized = _ensureMapResponse(response);
    final data = normalized['data'];

    if (data is Map) {
      final mapped = data.map((key, value) => MapEntry(key.toString(), value));
      if (mapped['typeOptions'] is List || mapped['tableOptions'] is List) {
        return BookingSettings.fromJson({'data': mapped});
      }
    }

    if (normalized['typeOptions'] is List ||
        normalized['tableOptions'] is List) {
      return BookingSettings.fromJson({
        'data': {
          'typeOptions': normalized['typeOptions'] ?? const [],
          'tableOptions': normalized['tableOptions'] ?? const [],
        },
      });
    }

    return null;
  }

  Map<String, dynamic> _serializeBookingSettings(BookingSettings settings) {
    return <String, dynamic>{
      'data': {
        'typeOptions': settings.typeOptions
            .map((option) => {'label': option.label, 'value': option.value})
            .toList(),
        'tableOptions': settings.tableOptions
            .map((option) => {'label': option.label, 'value': option.value})
            .toList(),
      },
    };
  }

  /// Get booking settings (types and tables)
  Future<BookingSettings> getBookingSettings() async {
    final token = _client.getToken();
    if (token == null || token.isEmpty) {
      print('⚠️ getBookingSettings: No token available');
      return _emptyBookingSettings();
    }
    if (ApiConstants.branchId <= 0) {
      print('⚠️ getBookingSettings: branchId is 0');
      return _emptyBookingSettings();
    }

    final disabledFlag =
        await _cache.get(_bookingCreateMetadataDisabledCacheKey);
    if (disabledFlag == true) {
      _skipBookingCreateMetadataEndpoint = true;
    }

    final createEndpoint = _buildBookingCreateMetadataEndpointWithDefaults();
    final endpoints = <String>[
      if (!_skipBookingCreateMetadataEndpoint) createEndpoint,
      ApiConstants.bookingsEndpoint,
    ];
    BookingSettings? fallback;

    for (final endpoint in endpoints) {
      try {
        final response = await _client.get(endpoint);

        // 🔍 DEBUG: Print and save raw API response
        print('=' * 70);
        print('🔍 DEBUG: Booking Settings Raw API Response');
        print('📍 Endpoint: $endpoint');

        // Save to file for analysis
        try {
          final file = File('BOOKING_SETTINGS_RAW_RESPONSE.json');
          await file.writeAsString(
            const JsonEncoder.withIndent('  ').convert(response),
          );
          print('💾 Response saved to: BOOKING_SETTINGS_RAW_RESPONSE.json');
        } catch (e) {
          print('⚠️  Could not save response to file: $e');
        }

        print('=' * 70);

        final parsed = _parseBookingSettingsResponse(response);
        if (parsed == null) continue;

        fallback ??= parsed;
        final hasOptions =
            parsed.typeOptions.isNotEmpty || parsed.tableOptions.isNotEmpty;
        if (!hasOptions) continue;

        await _cache.set(
          'booking_settings',
          _serializeBookingSettings(parsed),
          expiry: const Duration(hours: 12),
        );
        return parsed;
      } catch (e) {
        if (endpoint == createEndpoint) {
          final lower = e.toString().toLowerCase();
          final isBackendBug = lower.contains('unhandled match case null') ||
              (e is ApiException && (e.statusCode ?? 0) >= 500);
          if (isBackendBug) {
            _skipBookingCreateMetadataEndpoint = true;
            await _cache.set(
              _bookingCreateMetadataDisabledCacheKey,
              true,
              expiry: const Duration(hours: 6),
            );
            print(
              '⚠️ booking/create metadata endpoint disabled for this session due to backend 5xx.',
            );
          }
        }
        print('⚠️ getBookingSettings failed endpoint=$endpoint error=$e');
      }
    }

    if (fallback != null) {
      final ensured = _ensureServicesType(fallback);
      await _cache.set(
        'booking_settings',
        _serializeBookingSettings(ensured),
        expiry: const Duration(hours: 12),
      );
      return ensured;
    }

    final cached = await _cache.get('booking_settings');
    BookingSettings? fromCache;
    if (cached is Map<String, dynamic>) {
      fromCache = BookingSettings.fromJson(cached);
    } else if (cached is Map) {
      fromCache = BookingSettings.fromJson(
        cached.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    if (fromCache != null) {
      return _ensureServicesType(fromCache);
    }

    final safeFallback = _emptyBookingSettings();
    await _cache.set(
      'booking_settings',
      _serializeBookingSettings(safeFallback),
      expiry: const Duration(hours: 12),
    );
    return safeFallback;
  }

  /// Ensure 'services' (محلي/Local) type is always present in booking settings.
  BookingSettings _ensureServicesType(BookingSettings settings) {
    final hasServices = settings.typeOptions.any(
      (o) => o.value.trim().toLowerCase() == 'services' ||
             o.value.trim().toLowerCase() == 'service' ||
             o.value.trim().toLowerCase() == 'restaurant_services',
    );
    if (hasServices) return settings;
    return BookingSettings(
      typeOptions: [
        OptionItem(label: 'محلي', value: 'services'),
        ...settings.typeOptions,
      ],
      tableOptions: settings.tableOptions,
    );
  }

  /// Get create booking page data (for form options)
  Future<Map<String, dynamic>> getBookingCreateData() async {
    final response = await _client.get(
      '${ApiConstants.bookingsEndpoint}/create',
    );
    return _rememberResponse('get_booking_create_data', response);
  }

  /// Create invoice (enriches items from booking details + multipart retry)
  Future<Map<String, dynamic>> createInvoice(
    Map<String, dynamic> invoiceData,
  ) async {
    // OFFLINE MODE: Save invoice locally and queue for sync
    if (_connectivity.isOffline) {
      final localId = await _offlineDb.saveLocalInvoice(
          invoiceData, ApiConstants.branchId);
      await _offlineDb.addToSyncQueue(
        operation: 'CREATE_INVOICE',
        endpoint: ApiConstants.invoicesEndpoint,
        method: 'POST',
        payload: invoiceData,
        localRefTable: 'invoices',
        localRefId: localId,
      );
      return _rememberResponse('create_invoice', {
        'status': 200,
        'data': {'id': localId, '_is_local': true, ...invoiceData},
      });
    }

    final enrichedInvoiceData = await _ensureInvoiceItems(invoiceData);
    final normalizedInvoiceData = _normalizeInvoicePayloadForPostman(
      enrichedInvoiceData,
    );
    try {
      final response = await _client.post(
        ApiConstants.invoicesEndpoint,
        normalizedInvoiceData,
      );
      return _rememberResponse('create_invoice', response);
    } on ApiException catch (e) {
      final status = e.statusCode ?? 0;
      final message = e.userMessage ?? e.message;
      final hasItems = _hasInvoiceItems(enrichedInvoiceData);
      final needsMultipart =
          status == 422 && message.contains('عناصر') && hasItems;
      if (!needsMultipart) rethrow;
      // Retry using multipart/form-data
      return createInvoiceMultipart(enrichedInvoiceData);
    }
  }

  /// Create invoice using multipart/form-data
  /// Some branches validate nested pays only in multipart keys (pays[0][...]).
  Future<Map<String, dynamic>> createInvoiceMultipart(
    Map<String, dynamic> invoiceData,
  ) async {
    final fields = <String, String>{
      if (invoiceData['customer_id'] != null)
        'customer_id': invoiceData['customer_id'].toString(),
      'branch_id':
          (invoiceData['branch_id'] ?? ApiConstants.branchId).toString(),
      if (invoiceData['order_id'] != null)
        'order_id': invoiceData['order_id'].toString(),
      if (invoiceData['booking_id'] != null)
        'booking_id': invoiceData['booking_id'].toString(),
      if (invoiceData['booking_product_id'] != null)
        'booking_product_id': invoiceData['booking_product_id'].toString(),
      if (invoiceData['parent_invoice_id'] != null)
        'parent_invoice_id': invoiceData['parent_invoice_id'].toString(),
      if (invoiceData['promocode_id'] != null)
        'promocode_id': invoiceData['promocode_id'].toString(),
      if (invoiceData['deposit_id'] != null)
        'deposit_id': invoiceData['deposit_id'].toString(),
      if (invoiceData['date'] != null) 'date': invoiceData['date'].toString(),
      'cash_back': (invoiceData['cash_back'] ?? 0).toString(),
      if (invoiceData['promocodeValue'] != null)
        'promocodeValue': invoiceData['promocodeValue'].toString(),
      if (invoiceData['type'] != null) 'type': invoiceData['type'].toString(),
    };
    fields.addAll(_withOrderIdentifierCompatFields(invoiceData));

    final typeExtra = invoiceData['type_extra'];
    if (typeExtra is Map) {
      final normalized = typeExtra.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      for (final entry in normalized.entries) {
        if (entry.value == null) continue;
        fields['type_extra[${entry.key}]'] = entry.value.toString();
      }
    }

    void addItemsToFields(String keyName, dynamic source) {
      if (source is! List || source.isEmpty) return;
      for (var i = 0; i < source.length; i++) {
        final row = source[i];
        if (row is! Map) continue;
        final item = row.map((key, value) => MapEntry(key.toString(), value));
        void addField(String fieldKey, dynamic value) {
          if (value == null) return;
          fields['$keyName[$i][$fieldKey]'] = value.toString();
        }

        addField('booking_meal_id', item['booking_meal_id']);
        addField('meal_id', item['meal_id']);
        addField('meal_name',
            item['meal_name'] ?? item['item_name'] ?? item['name']);
        addField('quantity', item['quantity']);
        addField('price', item['price']);
        addField('unit_price', item['unit_price'] ?? item['unitPrice']);
        addField('total', item['total']);
        addField('modified_unit_price', item['modified_unit_price']);
        addField('note', item['note'] ?? item['notes']);

        // Always send discount & discount_type per item (matching website
        // behavior). Empty string = no discount.
        fields['$keyName[$i][discount]'] =
            (item['discount'] ?? '').toString();
        fields['$keyName[$i][discount_type]'] =
            (item['discount_type'] ?? '%').toString();

        final addons = item['addons'];
        if (addons is List) {
          for (var j = 0; j < addons.length; j++) {
            final addon = addons[j];
            if (addon is Map) {
              final normalizedAddon = addon.map(
                (key, value) => MapEntry(key.toString(), value),
              );
              final addonId =
                  normalizedAddon['addon_id'] ?? normalizedAddon['id'];
              if (addonId != null) {
                fields['$keyName[$i][addons][$j][addon_id]'] =
                    addonId.toString();
              }
              if (normalizedAddon['name'] != null) {
                fields['$keyName[$i][addons][$j][name]'] =
                    normalizedAddon['name'].toString();
              }
              if (normalizedAddon['price'] != null) {
                fields['$keyName[$i][addons][$j][price]'] =
                    normalizedAddon['price'].toString();
              }
            } else if (addon != null) {
              // Backward compatibility: addons as plain id list.
              fields['$keyName[$i][addons][$j][addon_id]'] = addon.toString();
            }
          }
        }
      }
    }

    addItemsToFields('card', invoiceData['card']);
    addItemsToFields('items', invoiceData['items']);
    addItemsToFields('meals', invoiceData['meals']);
    addItemsToFields('sales_meals', invoiceData['sales_meals']);
    addItemsToFields('sales_services', invoiceData['sales_services']);

    final pays = invoiceData['pays'];
    if (pays is List && pays.isNotEmpty) {
      for (var i = 0; i < pays.length; i++) {
        final pay = pays[i];
        if (pay is! Map) continue;
        final normalized = pay.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        fields['pays[$i][name]'] =
            (normalized['name'] ?? normalized['pay_method'] ?? 'cash')
                .toString();
        fields['pays[$i][pay_method]'] =
            (normalized['pay_method'] ?? 'cash').toString();
        fields['pays[$i][amount]'] = (normalized['amount'] ?? 0).toString();
        fields['pays[$i][index]'] = (normalized['index'] ?? i).toString();
      }
    }

    final response = await _client.postMultipart(
      ApiConstants.invoicesEndpoint,
      fields,
    );
    return _rememberResponse('create_invoice', response);
  }

  /// Calculate invoice totals
  Future<Map<String, dynamic>> calculateInvoice(
    Map<String, dynamic> invoiceData,
  ) async {
    try {
      final response = await _client.post(
        ApiConstants.calculateInvoiceEndpoint,
        invoiceData,
      );
      return _rememberResponse('calculate_invoice', response);
    } on ApiException catch (e) {
      final hasItems = invoiceData['items'] is List;
      final hasCard = invoiceData['card'] is List;
      final needsCardFallback =
          hasItems && !hasCard && e.message.contains('السلة');
      if (!needsCardFallback) rethrow;

      final fallbackPayload = Map<String, dynamic>.from(invoiceData);
      fallbackPayload['card'] = fallbackPayload.remove('items');
      final response = await _client.post(
        ApiConstants.calculateInvoiceEndpoint,
        fallbackPayload,
      );
      return _rememberResponse('calculate_invoice', response);
    }
  }

  /// Mirror of [getCachedBookings] for invoices: returns the most recent
  /// cached page-1 response so the salon UI can paint instantly while a
  /// fresh fetch runs in the background.
  Future<Map<String, dynamic>?> getCachedInvoices({
    String? dateFrom,
    String? dateTo,
  }) async {
    final cached = await _cache.get('invoices_${dateFrom}_$dateTo');
    if (cached is Map<String, dynamic>) return cached;
    if (cached is Map) {
      return cached.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  /// Get invoices list
  Future<Map<String, dynamic>> getInvoices({
    String? dateFrom,
    String? dateTo,
    String? status,
    String? search,
    String? invoiceType,
    int page = 1,
    int perPage = 20,
  }) async {
    // Check if token is available first
    final token = _client.getToken();
    if (token == null || token.isEmpty) {
      print('⚠️ getInvoices: No token available');
      throw UnauthorizedException('No authentication token');
    }

    final queryParams = <String, String>{
      'page': page.toString(),
      'per_page': perPage.toString(),
    };
    if (dateFrom != null) queryParams['date_from'] = dateFrom;
    if (dateTo != null) queryParams['date_to'] = dateTo;
    if (status != null && status.isNotEmpty) queryParams['status'] = status;
    if (search != null && search.isNotEmpty) queryParams['search'] = search;
    if (invoiceType != null && invoiceType.isNotEmpty) {
      queryParams['invoice_type'] = invoiceType;
    }

    final queryString =
        queryParams.entries.map((e) => '${e.key}=${e.value}').join('&');
    final endpoint = '${ApiConstants.invoicesEndpoint}?$queryString';

    try {
      final response = await _client.get(endpoint);
      final normalized = _rememberResponse('get_invoices', response);
      if (response != null && page == 1) {
        await _cache.set(
          'invoices_${dateFrom}_$dateTo',
          normalized,
          expiry: const Duration(minutes: 30),
        );
      }
      return normalized;
    } catch (e) {
      if (page == 1) {
        final cached = await _cache.get('invoices_${dateFrom}_$dateTo');
        if (cached != null) return cached;
      }
      rethrow;
    }
  }

  /// Get single invoice details
  Future<Map<String, dynamic>> getInvoice(String invoiceId) async {
    final response = await _client.get(
      ApiConstants.invoiceDetailsEndpoint(invoiceId),
    );
    return _rememberResponse('get_invoice_details', response);
  }

  /// Get invoice helper details (alternative endpoint)
  Future<Map<String, dynamic>> getInvoiceHelper(String invoiceId) async {
    final response = await _client.get(
      '/seller/helpers/branches/${ApiConstants.branchId}/invoices/$invoiceId',
    );
    return _rememberResponse('get_invoice_helper', response);
  }

  /// Get booking invoice
  Future<Map<String, dynamic>> getBookingInvoice(String orderId) async {
    final response = await _client.get(
      ApiConstants.bookingInvoiceEndpoint(orderId),
    );
    return _rememberResponse('get_order_invoices', response);
  }

  /// Get booking/order details
  Future<Map<String, dynamic>> getBookingDetails(String orderId) async {
    final normalizedOrderId = _normalizeBookingIdOrThrow(orderId);
    try {
      final response = await _client.get(
        ApiConstants.bookingDetailsEndpoint(normalizedOrderId),
      );
      return _rememberResponse('get_order_details', response);
    } on ApiException catch (e) {
      final message = e.message.toLowerCase();
      final routeNotFound =
          e.statusCode == 404 && message.contains('route_not_found');
      final bookingItemsError =
          e.statusCode == 500 && message.contains('booking_items');

      if (routeNotFound || bookingItemsError) {
        try {
          final servicesEndpoint =
              '/seller/services/branches/${ApiConstants.branchId}/bookings/$normalizedOrderId';
          final servicesResponse = await _client.get(servicesEndpoint);
          return _rememberResponse('get_order_details', servicesResponse);
        } on ApiException {
          // Continue to graceful fallback below.
        }
      }

      if (routeNotFound || bookingItemsError || e.statusCode == 404) {
        try {
          final fromList =
              await _lookupBookingDetailsFromList(normalizedOrderId);
          if (fromList != null) {
            return fromList;
          }
        } on ApiException {
          // Continue to graceful fallback below.
        }
      }

      if (e.statusCode == 500 && message.contains('booking_items')) {
        return _rememberResponse('get_order_details', {
          'status': 500,
          'message':
              'تعذر جلب تفاصيل الطلب الآن بسبب مشكلة مؤقتة في الخادم، وتم متابعة العمل بالبيانات المتاحة.',
          'data': {
            'id': int.tryParse(normalizedOrderId) ?? normalizedOrderId,
            'order_id': int.tryParse(normalizedOrderId) ?? normalizedOrderId,
            'booking_id': int.tryParse(normalizedOrderId) ?? normalizedOrderId,
            'meals': <dynamic>[],
          },
        });
      }
      rethrow;
    }
  }

  /// Update booking status
  /// API contract differs by environment. Try multiple compatible payload forms.
  Future<Map<String, dynamic>> updateBookingStatus({
    required String orderId,
    required int status,
  }) async {
    final normalizedOrderId = _normalizeBookingIdOrThrow(orderId);
    final primaryEndpoint =
        '/seller/branches/${ApiConstants.branchId}/status/bookings/$normalizedOrderId';
    final legacyEndpoint =
        '/seller/status/branches/${ApiConstants.branchId}/bookings/$normalizedOrderId';
    final statusValue = status.toString();

    // Keep attempts limited to avoid rate limiting.
    final attempts = <Future<dynamic> Function()>[
      () => _client.put(primaryEndpoint, {
            'status': statusValue,
          }),
      () => _client.patch(primaryEndpoint, {
            'status': statusValue,
          }),
      () => _client.patchMultipart(primaryEndpoint, {
            'status': statusValue,
          }),
      () => _client.patchMultipart(legacyEndpoint, {
            'status': statusValue,
          }),
      () => _client.patch(legacyEndpoint, {
            'status': statusValue,
          }),
    ];

    ApiException? lastApiError;
    Object? lastTransportError;

    for (var i = 0; i < attempts.length; i++) {
      final hasMoreAttempts = i < attempts.length - 1;
      try {
        final response = await attempts[i]();
        // Status changes (cancel / complete / archive) free up the slot
        // the booking was holding. Drop the salon slot cache so the
        // freshly-released time isn't still hidden behind 2-minute-old
        // cached data when another customer asks for it.
        try {
          getIt<SalonEmployeeService>().invalidateAvailableTimesCache();
        } catch (_) {}
        return _rememberResponse('update_order_status', response);
      } on ApiException catch (e) {
        lastApiError = e;
        // Don't retry on rate limiting errors (422 with "Too Many Attempts")
        if (e.statusCode == 422 &&
            (e.message.contains('Too Many') ||
                e.message.contains('محاولات كثيرة'))) {
          print('⚠️ Rate limited on updateBookingStatus - skipping retries');
          rethrow;
        }
        if (!hasMoreAttempts || !_shouldRetryStatusUpdate(e)) {
          rethrow;
        }
        final attemptNo = i + 1;
        print(
          '⚠️ updateBookingStatus attempt $attemptNo/${attempts.length} failed with ${e.statusCode}: ${e.message}. Trying alternate request format.',
        );
      } catch (e) {
        lastTransportError = e;
        if (!hasMoreAttempts || !_isRetryableBookingTransportError(e)) {
          rethrow;
        }
        final attemptNo = i + 1;
        print(
          '⚠️ updateBookingStatus transport issue on attempt $attemptNo/${attempts.length}: $e. Retrying with alternate request format.',
        );
      }
    }

    if (lastApiError != null) throw lastApiError;
    if (lastTransportError != null) throw lastTransportError;
    throw ApiException('Unable to update booking status');
  }

  /// Refund order preview (source of truth endpoint)
  /// API: GET /seller/refund/branches/{branchId}/bookings/{orderId}
  Future<Map<String, dynamic>> showBookingRefund(String orderId) async {
    final normalizedOrderId = _normalizeBookingIdOrThrow(orderId);
    return _getWithFallbackEndpoints(
      _bookingRefundEndpoints(normalizedOrderId),
      responseKey: 'show_booking_refund',
    );
  }

  /// Process order refund (source of truth endpoint)
  /// Backend expects POST with Laravel method-spoofing: multipart form-data
  /// containing `_method=PATCH` and `refund[i]=<booking_service_id>` per item.
  /// Native PATCH and JSON bodies are rejected by the salon controller.
  /// API: POST /seller/refund/branches/{branchId}/bookings/{orderId}
  Future<Map<String, dynamic>> processBookingRefund({
    required String orderId,
    Map<String, dynamic> payload = const {},
  }) async {
    final normalizedOrderId = _normalizeBookingIdOrThrow(orderId);

    final refundArray = await _resolveBookingRefundArray(
      normalizedOrderId: normalizedOrderId,
      providedRefund: payload['refund'],
    );

    if (refundArray.isEmpty) {
      throw ApiException(
        'لا توجد عناصر قابلة للاسترجاع في هذا الطلب.',
        statusCode: 422,
        userMessage:
            'لا يمكن استرجاع هذا الطلب. قد يكون تم استرجاعه بالفعل أو تم دفعه.',
      );
    }

    final fields = <String, String>{'_method': 'PATCH'};
    for (var i = 0; i < refundArray.length; i++) {
      fields['refund[$i]'] = refundArray[i].toString();
    }

    final endpoints = _bookingRefundEndpoints(normalizedOrderId);
    ApiException? lastError;
    for (final endpoint in endpoints) {
      try {
        final response = await _client.postMultipart(endpoint, fields);
        return _rememberResponse('process_booking_refund', response);
      } on ApiException catch (e) {
        lastError = e;
        if (!_isFallbackEligibleApiError(e)) rethrow;
      }
    }
    throw lastError ?? ApiException('REFUND_FAILED');
  }

  /// Send WhatsApp message for a single booking.
  /// API: POST /seller/booking/send-whatsapp/{orderId}
  Future<Map<String, dynamic>> sendOrderWhatsApp({
    required String orderId,
    required String message,
  }) async {
    final response = await _client.post(
      ApiConstants.sendOrderWhatsAppEndpoint(orderId),
      {'message': message},
    );
    return _rememberResponse('send_order_whatsapp', response);
  }

  /// Send WhatsApp message for multiple bookings.
  /// API: POST /seller/booking/send-multi-whatsapp/{branchId}
  Future<Map<String, dynamic>> sendMultiOrdersWhatsApp({
    required List<int> orderIds,
    required String message,
  }) async {
    final response = await _client.post(
      ApiConstants.sendMultiOrdersWhatsAppEndpoint(),
      {'order_ids': orderIds, 'message': message},
    );
    return _rememberResponse('send_multi_orders_whatsapp', response);
  }

  /// Update booking data (table name / notes / salon reschedule)
  Future<Map<String, dynamic>> updateBookingData({
    required String orderId,
    String? tableName,
    String? notes,
    String? date,
    String? time,
    int? employeeId,
  }) async {
    final endpoint = '/seller/update-booking-data/$orderId';
    final payload = <String, dynamic>{};
    if (tableName != null) payload['table_name'] = tableName;
    if (notes != null) payload['notes'] = notes;
    if (date != null) payload['date'] = date;
    if (time != null) payload['time'] = time;
    if (employeeId != null) payload['employee_id'] = employeeId;

    final response = await _client.post(endpoint, payload);
    // updateBookingData reschedules the booking_service (employee / date /
    // time), so the slot graph just shifted. Drop the cache for the same
    // reason the createBooking / updateBookingItems paths do.
    if (date != null || time != null || employeeId != null) {
      try {
        getIt<SalonEmployeeService>().invalidateAvailableTimesCache();
      } catch (_) {}
    }
    return _rememberResponse('update_order_data', response);
  }
}
