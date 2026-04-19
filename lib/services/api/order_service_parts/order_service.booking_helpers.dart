// ignore_for_file: unused_element, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../order_service.dart';

extension OrderServiceBookingHelpers on OrderService {
  bool _isDeliveryOrderType(String type) {
    final normalized = type.trim().toLowerCase();
    return normalized == 'restaurant_delivery' ||
        normalized == 'delivery' ||
        normalized == 'home_delivery';
  }

  String? _normalizeCoordinate(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty || raw.toLowerCase() == 'null') return null;
    final parsed = double.tryParse(raw.replaceAll(',', '.'));
    if (parsed == null) return null;
    return parsed.toString();
  }

  Map<String, dynamic> _normalizeBookingPayload(
    Map<String, dynamic> source, {
    bool forceDeliveryCoordinates = false,
  }) {
    final normalized = Map<String, dynamic>.from(source);

    var type = normalized['type']?.toString().trim() ?? '';
    if (type.isEmpty || type.toLowerCase() == 'null') {
      // For salon module, keep type as-is (null/empty is valid for services)
      if (ApiConstants.branchModule == 'salons') {
        // Only set type for packageServices, leave null for regular services
        if (type != 'packageServices' && type != 'packageservices') {
          normalized.remove('type');
        }
      } else {
        type = 'restaurant_pickup';
        normalized['type'] = type;
      }
    } else {
      normalized['type'] = type;
    }
    if (normalized['date'] == null || normalized['date'].toString().isEmpty) {
      normalized['date'] = DateTime.now().toIso8601String().split('T').first;
    }

    final cardRaw = normalized['card'];
    final mealsRaw = normalized['meals'];
    final hasCard = cardRaw is List && cardRaw.isNotEmpty;
    final hasMeals = mealsRaw is List && mealsRaw.isNotEmpty;
    if (!hasCard && hasMeals) {
      normalized['card'] = List<dynamic>.from(mealsRaw);
    }
    if (!hasMeals && hasCard) {
      normalized['meals'] = List<dynamic>.from(cardRaw);
    }

    final rawTypeExtra = normalized['type_extra'];
    final typeExtra = rawTypeExtra is Map
        ? rawTypeExtra.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};

    typeExtra.putIfAbsent('car_number', () => null);
    typeExtra.putIfAbsent('table_name', () => null);

    if (_isDeliveryOrderType(type)) {
      final latitude = _normalizeCoordinate(typeExtra['latitude']);
      final longitude = _normalizeCoordinate(typeExtra['longitude']);
      typeExtra['latitude'] =
          latitude ?? (forceDeliveryCoordinates ? '0' : null);
      typeExtra['longitude'] =
          longitude ?? (forceDeliveryCoordinates ? '0' : null);
    } else {
      typeExtra.putIfAbsent('latitude', () => null);
      typeExtra.putIfAbsent('longitude', () => null);
    }

    normalized['type_extra'] = typeExtra;
    return normalized;
  }

  bool _requiresDeliveryCoordsFallback(String message) {
    final lower = message.toLowerCase();
    return lower.contains('latitude') ||
        lower.contains('longitude') ||
        lower.contains('type_extra') ||
        lower.contains('type extra');
  }

  bool _isInvalidType422(String message) {
    final lower = message.toLowerCase();
    return lower.contains('الحقل النوع غير صحيح') ||
        lower.contains('type field is invalid') ||
        (lower.contains('type') && lower.contains('invalid'));
  }

  List<String> _bookingTypeFallbackCandidates(String currentType) {
    final normalized = currentType.trim().toLowerCase();
    const carAliases = <String>[
      'restaurant_parking',
      'cars',
      'car',
      'drive_through',
      'drive-through',
      'parking',
    ];

    if (!carAliases.contains(normalized)) return const [];
    return <String>[
      'restaurant_parking',
      'cars',
      'car',
    ].where((candidate) => candidate != normalized).toList(growable: false);
  }

  bool _isRetryableBookingTransportError(Object error) {
    final message = error.toString().toLowerCase();
    final isHeaderClose =
        message.contains('connection closed before full header');
    final isSocket = message.contains('socketexception');
    final isTimeout =
        message.contains('timeoutexception') || message.contains('timed out');
    final isClientTransport = message.contains('clientexception') &&
        (message.contains('connection') ||
            message.contains('socket') ||
            message.contains('network') ||
            message.contains('handshake'));
    final isTaggedTransport = message.contains('transport_error');
    return isHeaderClose ||
        isSocket ||
        isTimeout ||
        isClientTransport ||
        isTaggedTransport;
  }

  Future<Map<String, dynamic>> _createBookingWithJsonRetry(
    Map<String, dynamic> payload,
  ) async {
    const maxAttempts = 2; // Keep it low to avoid duplicate orders.
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final response = await _client.post(
          ApiConstants.bookingsEndpoint,
          payload,
        );
        return _rememberResponse('create_order', response);
      } catch (e) {
        final hasMoreAttempts = attempt < maxAttempts - 1;
        if (!hasMoreAttempts || !_isRetryableBookingTransportError(e)) {
          rethrow;
        }
        final retryAttempt = attempt + 1;
        print(
          '⚠️ createBooking transport error, retrying JSON request (attempt $retryAttempt/$maxAttempts): $e',
        );
        await Future<void>.delayed(
          Duration(milliseconds: 350 * retryAttempt),
        );
      }
    }
    throw Exception('Failed to create booking request');
  }

  Future<Map<String, dynamic>> _createBookingWithMultipartRetry(
    Map<String, String> fields,
  ) async {
    const maxAttempts = 2; // Keep it low to avoid duplicate orders.
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final response = await _client.postMultipart(
          ApiConstants.bookingsEndpoint,
          fields,
        );
        return _rememberResponse('create_order', response);
      } catch (e) {
        final hasMoreAttempts = attempt < maxAttempts - 1;
        if (!hasMoreAttempts || !_isRetryableBookingTransportError(e)) {
          rethrow;
        }
        final retryAttempt = attempt + 1;
        print(
          '⚠️ createBooking transport error, retrying multipart request (attempt $retryAttempt/$maxAttempts): $e',
        );
        await Future<void>.delayed(
          Duration(milliseconds: 350 * retryAttempt),
        );
      }
    }
    throw Exception('Failed to create booking multipart request');
  }

  Future<Map<String, dynamic>> _createBookingMultipart(
    Map<String, dynamic> bookingData,
  ) async {
    final normalized = _normalizeBookingPayload(
      bookingData,
      forceDeliveryCoordinates: true,
    );
    final fields = <String, String>{
      if (normalized['customer_id'] != null)
        'customer_id': normalized['customer_id'].toString(),
      if (normalized['table_id'] != null)
        'table_id': normalized['table_id'].toString(),
      if (normalized['date'] != null) 'date': normalized['date'].toString(),
      if (normalized['type'] != null) 'type': normalized['type'].toString(),
    };

    final typeExtra = normalized['type_extra'];
    if (typeExtra is Map) {
      final type = normalized['type']?.toString().trim() ?? '';
      for (final entry in typeExtra.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value == null) {
          if (_isDeliveryOrderType(type) &&
              (key == 'latitude' || key == 'longitude')) {
            fields['type_extra[$key]'] = '0';
          } else {
            fields['type_extra[$key]'] = '';
          }
          continue;
        }
        fields['type_extra[$key]'] = value.toString();
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

        addField('item_name', item['item_name'] ?? item['name']);
        addField(
          'meal_id',
          item['meal_id'] ?? item['product_id'] ?? item['productId'],
        );
        addField('price', item['price']);
        addField('unitPrice', item['unitPrice'] ?? item['unit_price']);
        addField('modified_unit_price', item['modified_unit_price']);
        addField('quantity', item['quantity']);
        addField('note', item['note'] ?? item['notes']);

        final discount = item['discount'];
        if (discount != null && discount.toString().isNotEmpty) {
          addField('discount', discount);
          addField('discount_type', item['discount_type'] ?? '%');
        }

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
              fields['$keyName[$i][addons][$j][addon_id]'] = addon.toString();
            }
          }
        }
      }
    }

    addItemsToFields('card', normalized['card']);
    addItemsToFields('meals', normalized['meals']);

    return _createBookingWithMultipartRetry(fields);
  }
}
