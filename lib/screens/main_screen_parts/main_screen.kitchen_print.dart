// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../main_screen.dart';

extension MainScreenKitchenPrint on _MainScreenState {
  /// Read the device-local printer primary language (ar/en/hi/ur/es/tr) so the
  /// kitchen ticket can resolve item names from `meal_name_translations`.
  String _resolveKitchenInvoiceLang() => printerLanguageSettings.primary;

  Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  String? _firstNonEmptyText(Iterable<dynamic> candidates) {
    for (final candidate in candidates) {
      final text = candidate?.toString().trim();
      if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return null;
  }

  double _toSafeDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  Map<String, dynamic> _composeKitchenTemplateMeta({
    Map<String, dynamic>? source,
    String? fallbackOrderNumber,
    String? fallbackOrderType,
    String? fallbackInvoiceNumber,
    String? fallbackNote,
  }) {
    Map<String, dynamic> mapOrEmpty(dynamic value) {
      return _asStringMap(value) ?? const <String, dynamic>{};
    }

    final root = source ?? const <String, dynamic>{};
    final envelope =
        mapOrEmpty(root['data']).isNotEmpty ? mapOrEmpty(root['data']) : root;

    final invoice = mapOrEmpty(envelope['invoice']).isNotEmpty
        ? mapOrEmpty(envelope['invoice'])
        : mapOrEmpty(root['invoice']);
    final booking = mapOrEmpty(envelope['booking']).isNotEmpty
        ? mapOrEmpty(envelope['booking'])
        : mapOrEmpty(invoice['booking']);
    final branch = mapOrEmpty(envelope['branch']).isNotEmpty
        ? mapOrEmpty(envelope['branch'])
        : mapOrEmpty(invoice['branch']);
    final seller = mapOrEmpty(branch['seller']).isNotEmpty
        ? mapOrEmpty(branch['seller'])
        : mapOrEmpty(envelope['seller']);
    final client = mapOrEmpty(invoice['client']).isNotEmpty
        ? mapOrEmpty(invoice['client'])
        : mapOrEmpty(envelope['client']);
    final typeExtra = mapOrEmpty(booking['type_extra']).isNotEmpty
        ? mapOrEmpty(booking['type_extra'])
        : mapOrEmpty(envelope['type_extra']);

    final date = _firstNonEmptyText(<dynamic>[
      invoice['date'],
      booking['date'],
      envelope['date'],
    ]);
    final time = _firstNonEmptyText(<dynamic>[
      invoice['time'],
      booking['time'],
      envelope['time'],
    ]);

    final meta = <String, dynamic>{
      'language_code': ApiConstants.acceptLanguage,
    };

    void put(String key, String? value) {
      if (value != null && value.trim().isNotEmpty) {
        meta[key] = value.trim();
      }
    }

    put(
        'seller_name',
        _firstNonEmptyText(<dynamic>[
          branch['seller_name'],
          branch['name'],
          seller['seller_name'],
          seller['name'],
        ]));
    put(
        'branch_name',
        _firstNonEmptyText(<dynamic>[
          branch['name'],
          branch['seller_name'],
        ]));
    put(
        'branch_address',
        _firstNonEmptyText(<dynamic>[
          branch['address'],
          envelope['address'],
        ]));
    put(
        'branch_mobile',
        _firstNonEmptyText(<dynamic>[
          branch['mobile'],
          branch['phone'],
          envelope['mobile'],
        ]));
    put(
        'branch_telephone',
        _firstNonEmptyText(<dynamic>[
          branch['telephone'],
          branch['phone'],
          envelope['telephone'],
        ]));
    put(
        'cashier_name',
        _firstNonEmptyText(<dynamic>[
          mapOrEmpty(invoice['cashier'])['fullname'],
          mapOrEmpty(invoice['cashier'])['name'],
          envelope['cashier_name'],
          _userName,
        ]));
    put(
        'order_number',
        _firstNonEmptyText(<dynamic>[
          booking['daily_order_number'],
          booking['order_number'],
          envelope['order_number'],
          fallbackOrderNumber,
        ]));
    put(
        'daily_order_number',
        _firstNonEmptyText(<dynamic>[
          booking['daily_order_number'],
          envelope['daily_order_number'],
        ]));
    put(
        'order_type',
        _firstNonEmptyText(<dynamic>[
          booking['type'],
          envelope['type'],
          fallbackOrderType,
          _selectedOrderType,
        ]));
    put(
        'invoice_number',
        _firstNonEmptyText(<dynamic>[
          invoice['invoice_number'],
          envelope['invoice_number'],
          fallbackInvoiceNumber,
        ]));
    put(
        'table_name',
        _firstNonEmptyText(<dynamic>[
          typeExtra['table_name'],
          booking['table_name'],
          _selectedTable?.number,
        ]));
    put(
        'car_number',
        _firstNonEmptyText(<dynamic>[
          typeExtra['car_number'],
          booking['car_number'],
          _carNumberController.text.trim(),
        ]));
    put(
        'client_name',
        _firstNonEmptyText(<dynamic>[
          client['name'],
          booking['customer_name'],
          _selectedCustomer?.name,
        ]));
    put(
        'client_phone',
        _firstNonEmptyText(<dynamic>[
          client['mobile'],
          client['phone'],
          booking['customer_phone'],
          _selectedCustomer?.mobile,
        ]));
    put(
        'booking_note',
        _firstNonEmptyText(<dynamic>[
          booking['notes'],
          booking['note'],
          envelope['notes'],
          envelope['note'],
          fallbackNote,
          _orderNotesController.text.trim(),
        ]));
    put('date', date);
    put('time', time);
    put(
        'commercial_register_number',
        _firstNonEmptyText(<dynamic>[
          branch['commercial_register_number'],
          branch['commercial_register'],
          seller['commercial_register_number'],
          seller['commercial_register'],
          envelope['commercial_register_number'],
        ]));

    return meta;
  }

  String _normalizeCategoryToken(String value) {
    return value.trim().toLowerCase();
  }

  String? _resolveCategoryIdByName(String? categoryName) {
    final normalizedName = _normalizeCategoryToken(categoryName ?? '');
    if (normalizedName.isEmpty) return null;

    for (final category in _categories) {
      final id = category.id.trim();
      if (id.isEmpty || id.toLowerCase() == 'all') continue;

      final name = _normalizeCategoryToken(category.name);
      if (name.isEmpty || name == 'all' || name == 'الكل') continue;
      if (name == normalizedName) {
        return id;
      }
    }
    return null;
  }

  String? _resolveCategoryIdFromPrintItem(Map<String, dynamic> item) {
    final rawCategoryId = _firstNonEmptyText(<dynamic>[
      item['category_id'],
      item['categoryId'],
      item['cat_id'],
      item['section_id'],
    ]);
    if (rawCategoryId != null && rawCategoryId.isNotEmpty) {
      return rawCategoryId;
    }

    final categoryName = _firstNonEmptyText(<dynamic>[
      item['category_name'],
      item['category'],
      item['section_name'],
      item['categoryName'],
    ]);
    return _resolveCategoryIdByName(categoryName);
  }

  Future<bool> _dispatchKitchenPrintByCategoryRouting({
    required PrintOrchestratorService orchestrator,
    required CategoryPrinterRouteRegistry categoryRegistry,
    required List<DeviceConfig> printers,
    required String orderNumber,
    required String orderType,
    required List<Map<String, dynamic>> items,
    String? note,
    String? invoiceNumber,
    Map<String, dynamic>? templateMeta,
    String? clientName,
    String? clientPhone,
    String? tableNumber,
    String? carNumber,
    String? cashierName,
    bool isRtl = true,
  }) async {
    cashierName ??= AuthService().getUser()?['name']?.toString();
    if (printers.isEmpty || items.isEmpty) return false;
    if (!categoryRegistry.hasAnyAssignments()) return false;

    final printerIds = printers.map((p) => p.id).toList(growable: false);
    final printerById = <String, DeviceConfig>{
      for (final printer in printers) printer.id: printer,
    };
    final printersWithoutAssignments = printers
        .where(
            (printer) => !categoryRegistry.hasAssignmentsForPrinter(printer.id))
        .toList(growable: false);

    final groupedByPrinter = <String, List<Map<String, dynamic>>>{};

    for (final rawItem in items) {
      final item = Map<String, dynamic>.from(rawItem);
      final categoryId = _resolveCategoryIdFromPrintItem(item);
      List<String> targetPrinterIds = const <String>[];
      if (categoryId != null && categoryId.isNotEmpty) {
        targetPrinterIds = categoryRegistry.resolvePrinterIdsForCategoryId(
          categoryId: categoryId,
          availablePrinterIds: printerIds,
        );
      }

      if (targetPrinterIds.isEmpty) {
        if (printersWithoutAssignments.isNotEmpty) {
          // Send to unassigned printers only (not ALL)
          targetPrinterIds =
              printersWithoutAssignments.map((printer) => printer.id).toList();
        } else if (printerIds.isNotEmpty) {
          // No unassigned printers — send to all kitchen printers
          targetPrinterIds = printerIds;
        }
      }

      for (final printerId in targetPrinterIds) {
        groupedByPrinter
            .putIfAbsent(printerId, () => <Map<String, dynamic>>[])
            .add(item);
      }
    }

    var delivered = false;
    for (final entry in groupedByPrinter.entries) {
      final printer = printerById[entry.key];
      if (printer == null || entry.value.isEmpty) continue;

      // Category-routed tickets intentionally don't print the "Dept / القسم"
      // header: the category name is already implicit in the items list, and
      // the cashier asked us to keep tickets terse for category-bound
      // printers. Passing `printerName: null` makes the kitchen view skip
      // that line entirely.

      final result = await orchestrator.enqueueKitchenPrint(
        printers: <DeviceConfig>[printer],
        orderNumber: orderNumber,
        orderType: orderType,
        items: entry.value,
        note: note,
        invoiceNumber: invoiceNumber,
        templateMeta: templateMeta,
        clientName: clientName,
        clientPhone: clientPhone,
        tableNumber: tableNumber,
        carNumber: carNumber,
        cashierName: cashierName,
        printerName: null,
        isRtl: isRtl,
        primaryLang: _resolveKitchenInvoiceLang(),
      );

      if (result.success) {
        delivered = true;
      }
    }

    return delivered;
  }

  List<int> _resolveKitchenIdsForReceiptGeneration() {
    final kitchenIds = <int>{};
    for (final device in _devices) {
      if (!device.id.startsWith('kitchen:')) continue;
      final parsed = int.tryParse(device.id.split(':').last);
      if (parsed != null && parsed > 0) {
        kitchenIds.add(parsed);
      }
    }

    if (kitchenIds.isEmpty) {
      // No kitchen devices configured — return empty so the caller
      // skips per-kitchen API calls and falls through to category
      // routing or the all-printers fallback.
      return <int>[];
    }

    final sorted = kitchenIds.toList()..sort();
    return sorted;
  }

  bool _isKitchenAlreadySentError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('sended to kitchen in the past')) return true;

    if (error is ApiException) {
      final joined =
          '${error.message} ${error.userMessage ?? ''}'.toLowerCase().trim();
      if (joined.contains('sended to kitchen in the past')) return true;
    }
    return false;
  }

  bool _isNoKitchenMealsError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('no meals found for this booking')) return true;

    if (error is ApiException) {
      final joined =
          '${error.message} ${error.userMessage ?? ''}'.toLowerCase().trim();
      if (joined.contains('no meals found for this booking')) return true;
    }
    return false;
  }

  List<DeviceConfig> _resolveKitchenPrintersForKitchenRoute({
    required KitchenPrinterRouteRegistry routeRegistry,
    required int kitchenId,
    required List<int> allKitchenIds,
    required List<DeviceConfig> candidatePrinters,
  }) {
    if (candidatePrinters.isEmpty) return const <DeviceConfig>[];
    final byId = <String, DeviceConfig>{
      for (final printer in candidatePrinters) printer.id: printer,
    };
    final resolvedIds = routeRegistry.resolvePrinterIdsForKitchen(
      kitchenId: kitchenId,
      availablePrinterIds: candidatePrinters.map((p) => p.id).toList(),
      knownKitchenIds: allKitchenIds,
    );
    final resolved = <DeviceConfig>[];
    for (final id in resolvedIds) {
      final printer = byId[id];
      if (printer != null) {
        resolved.add(printer);
      }
    }
    return resolved.isNotEmpty ? resolved : candidatePrinters;
  }

  String? _readLocalizedText(dynamic value) {
    if (value == null) return null;
    if (value is Iterable) {
      final texts = <String>[];
      for (final candidate in value) {
        final text = _readLocalizedText(candidate);
        if (text != null && text.isNotEmpty) {
          texts.add(text);
        }
      }
      if (texts.isEmpty) return null;

      for (final text in texts) {
        final hasArabic = _containsArabicChars(text);
        if (_useArabicUi && hasArabic) return text;
        if (!_useArabicUi && !hasArabic) return text;
      }
      return texts.first;
    }
    if (value is Map) {
      final map = value.map(
        (k, v) => MapEntry(k.toString().trim().toLowerCase(), v),
      );
      final languageKeys = <String>[
        _normalizedLanguageCode,
        if (_useArabicUi) 'ar' else 'en',
        if (_useArabicUi) 'en' else 'ar',
      ];
      final candidates = <dynamic>[
        for (final code in languageKeys) map[code],
        for (final code in languageKeys) map['name_$code'],
        for (final code in languageKeys) map['title_$code'],
        map['name'],
        map['name_display'],
        map['title'],
        map['label'],
      ];
      for (final candidate in candidates) {
        final text = _readLocalizedText(candidate);
        if (text != null && text.isNotEmpty) return text;
      }
      for (final candidate in map.values) {
        final text = _readLocalizedText(candidate);
        if (text != null && text.isNotEmpty) return text;
      }
      return null;
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return null;
      final looksLikeJson =
          (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
              (trimmed.startsWith('[') && trimmed.endsWith(']'));
      if (looksLikeJson) {
        try {
          final decoded = jsonDecode(trimmed);
          final parsed = _readLocalizedText(decoded);
          if (parsed != null && parsed.isNotEmpty) return parsed;
        } catch (_) {
          // keep raw text fallback
        }
      }
      final fromLegacyMap = _extractLegacyLocalizedFromString(trimmed);
      if (fromLegacyMap != null && fromLegacyMap.isNotEmpty) {
        return fromLegacyMap;
      }
      final fromListDump = _extractFirstMeaningfulFromListString(trimmed);
      if (fromListDump != null && fromListDump.isNotEmpty) {
        return fromListDump;
      }
      final normalized = _stripWrappingQuotes(trimmed);
      if (normalized.isEmpty || normalized.toLowerCase() == 'null') return null;
      return normalized;
    }
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  String _normalizePrinterToken(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  List<DeviceConfig> _resolveSectionTargetPrinters({
    required Map<String, dynamic> section,
    required List<DeviceConfig> candidates,
  }) {
    if (candidates.isEmpty) return const <DeviceConfig>[];

    final targetIp = _firstNonEmptyText(<dynamic>[
      section['ip'],
      section['printer_ip'],
      section['ip_address'],
    ]);
    final targetName = _firstNonEmptyText(<dynamic>[
      section['printer'],
      section['printer_name'],
      section['name'],
    ]);

    if (targetIp != null && targetIp.isNotEmpty) {
      final normalizedIp = targetIp.trim().toLowerCase();
      final isLoopback =
          normalizedIp == 'localhost' || normalizedIp.startsWith('127.');
      if (!isLoopback) {
        final byIp = candidates
            .where((printer) => printer.ip.trim() == targetIp.trim())
            .toList(growable: false);
        if (byIp.isNotEmpty) return byIp;
      }
    }

    if (targetName != null && targetName.isNotEmpty) {
      final normalizedTarget = _normalizePrinterToken(targetName);
      final exact = candidates
          .where(
            (printer) =>
                _normalizePrinterToken(printer.name) == normalizedTarget,
          )
          .toList(growable: false);
      if (exact.isNotEmpty) return exact;

      final fuzzy = candidates.where((printer) {
        final token = _normalizePrinterToken(printer.name);
        return token.contains(normalizedTarget) ||
            normalizedTarget.contains(token);
      }).toList(growable: false);
      if (fuzzy.isNotEmpty) return fuzzy;
    }

    return const <DeviceConfig>[];
  }

  List<Map<String, dynamic>> _normalizeBookingSectionItems({
    required dynamic rawItems,
    String? sectionCategoryId,
    String? sectionCategoryName,
  }) {
    if (rawItems is! List || rawItems.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final items = <Map<String, dynamic>>[];
    for (final raw in rawItems) {
      final item = _asStringMap(raw);
      if (item == null) continue;
      final meal = _asStringMap(item['meal']);

      final nameAr = _firstNonEmptyText(<dynamic>[
        item['name_ar'],
        item['meal_name_ar'],
        meal?['name_ar'],
        item['name'],
        item['meal_name'],
      ]) ?? '';

      final nameEn = _firstNonEmptyText(<dynamic>[
        item['name_en'],
        item['meal_name_en'],
        meal?['name_en'],
        item['item_name_en'],
      ]) ?? '';
      
      if (nameAr.isEmpty && nameEn.isEmpty) continue;

      final quantity = _toSafeDouble(
        item['quantity'] ?? item['qty'] ?? item['count'],
        fallback: 1.0,
      );
      final unitPrice = _toSafeDouble(
        item['unit_price'] ?? item['modified_unit_price'] ?? item['price'],
      );
      final total = _toSafeDouble(
        item['total'] ?? item['line_total'] ?? item['price_total'],
        fallback: quantity * unitPrice,
      );

      final note = _firstNonEmptyText(<dynamic>[item['notes'], item['note']]);
      final categoryId = _firstNonEmptyText(<dynamic>[
            item['category_id'],
            meal?['category_id'],
            sectionCategoryId,
          ]) ??
          _resolveCategoryIdByName(sectionCategoryName);
      final categoryName = _firstNonEmptyText(<dynamic>[
            item['category_name'],
            sectionCategoryName,
          ]) ??
          _readLocalizedText(meal?['category']?['name']);

      final extrasRaw = item['addons'] ??
          item['extras'] ??
          item['add_ons'] ??
          item['meal_operations'] ??
          item['operations'] ??
          item['modifiers'];
      final extras = extrasRaw is List
          ? extrasRaw
              .map((entry) => _asStringMap(entry))
              .whereType<Map<String, dynamic>>()
              .map((entry) {
                final optionMap = _asStringMap(entry['meal_option']) ??
                    _asStringMap(entry['option']);
                final attributeMap = _asStringMap(entry['attribute']);
                final extraName = _firstNonEmptyText(<dynamic>[
                      entry['name'],
                      entry['addon_name'],
                      entry['operation_name'],
                      entry['option_name'],
                      optionMap?['name'],
                      attributeMap?['name'],
                      entry['title'],
                    ]) ??
                    _readLocalizedText(entry['name']) ??
                    '';
                return <String, dynamic>{
                  'name': extraName,
                  if (optionMap != null || attributeMap != null)
                    'translations': {
                      if (optionMap != null) 'option': optionMap,
                      if (attributeMap != null) 'attribute': attributeMap,
                    },
                };
              })
              .where((entry) =>
                  entry['name']?.toString().trim().isNotEmpty == true)
              .toList(growable: false)
          : const <Map<String, dynamic>>[];

      // Pass meal_name_translations and addons_translations for multilingual support
      final mealNameTranslations = item['meal_name_translations'] ?? meal?['meal_name_translations'];
      final addonsTranslations = item['addons_translations'] ?? meal?['addons_translations'];

      items.add({
        'nameAr': nameAr,
        'nameEn': nameEn,
        'name': nameAr.isNotEmpty ? nameAr : nameEn,
        if (categoryId != null && categoryId.isNotEmpty)
          'category_id': categoryId,
        if (categoryName != null && categoryName.isNotEmpty)
          'category_name': categoryName,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'total': total,
        if (note != null && note.isNotEmpty) 'notes': note,
        if (extras.isNotEmpty) 'extras': extras,
        if (mealNameTranslations != null) 'meal_name_translations': mealNameTranslations,
        if (addonsTranslations != null) 'addons_translations': addonsTranslations,
      });
    }

    return items;
  }

  Future<bool> _dispatchKitchenPrintFromBookingSections({
    required OrderService orderService,
    required PrintOrchestratorService orchestrator,
    required CategoryPrinterRouteRegistry categoryRegistry,
    required List<DeviceConfig> printers,
    required String orderId,
    required String fallbackOrderType,
    String? fallbackNote,
    String? fallbackInvoiceNumber,
    Map<String, dynamic>? baseTemplateMeta,
    String? clientName,
    String? clientPhone,
    String? tableNumber,
    String? carNumber,
  }) async {
    final cashierName = AuthService().getUser()?['name']?.toString();
    if (printers.isEmpty) return false;

    Map<String, dynamic> detailsResponse;
    try {
      detailsResponse = await orderService.getBookingDetails(orderId);
    } catch (e) {
      print('⚠️ Failed to fetch booking details for sections #$orderId: $e');
      return false;
    }

    final data = _asStringMap(detailsResponse['data']) ?? detailsResponse;
    final detailsTemplateMeta = _composeKitchenTemplateMeta(
      source: detailsResponse,
      fallbackOrderNumber: '#$orderId',
      fallbackOrderType: fallbackOrderType,
      fallbackInvoiceNumber: fallbackInvoiceNumber,
      fallbackNote: fallbackNote,
    );
    final mergedBaseMeta = <String, dynamic>{
      ...?baseTemplateMeta,
      ...detailsTemplateMeta,
    };
    final rawSections = data['sections'];
    if (rawSections is! List || rawSections.isEmpty) {
      return false;
    }

    var orderNumber = _firstNonEmptyText(<dynamic>[
          data['booking_number'],
          data['daily_order_number'],
          data['order_number'],
          data['id'],
        ]) ??
        '#$orderId';
    if (RegExp(r'^\d+$').hasMatch(orderNumber)) {
      orderNumber = '#$orderNumber';
    }
    final orderType = _firstNonEmptyText(<dynamic>[
          data['type_text'],
          data['type'],
        ]) ??
        fallbackOrderType;
    final bookingNote = _firstNonEmptyText(<dynamic>[
          data['notes'],
          data['note'],
        ]) ??
        fallbackNote;

    var deliveredAny = false;
    for (final rawSection in rawSections) {
      final section = _asStringMap(rawSection);
      if (section == null) continue;

      final sectionCategoryId = _firstNonEmptyText(<dynamic>[
        section['category_id'],
      ]);
      final sectionCategoryName = _firstNonEmptyText(<dynamic>[
            section['category_name'],
          ]) ??
          _readLocalizedText(_asStringMap(section['category'])?['name']);

      final sectionItems = _normalizeBookingSectionItems(
        rawItems: section['items'],
        sectionCategoryId: sectionCategoryId,
        sectionCategoryName: sectionCategoryName,
      );
      if (sectionItems.isEmpty) continue;

      final sectionTemplateMeta = <String, dynamic>{
        ...mergedBaseMeta,
        'order_number': orderNumber,
        'order_type': orderType,
      };
      if (bookingNote != null && bookingNote.isNotEmpty) {
        sectionTemplateMeta['booking_note'] = bookingNote;
      }

      var targetPrinters = _resolveSectionTargetPrinters(
        section: section,
        candidates: printers,
      );

      if (targetPrinters.isEmpty && categoryRegistry.hasAnyAssignments()) {
        final deliveredViaCategory =
            await _dispatchKitchenPrintByCategoryRouting(
          orchestrator: orchestrator,
          categoryRegistry: categoryRegistry,
          printers: printers,
          orderNumber: orderNumber,
          orderType: orderType,
          items: sectionItems,
          note: bookingNote,
          invoiceNumber: fallbackInvoiceNumber,
          templateMeta: sectionTemplateMeta,
          clientName: clientName,
          clientPhone: clientPhone,
          tableNumber: tableNumber,
          carNumber: carNumber,
          cashierName: cashierName,
          isRtl: _useArabicUi,
        );
        if (deliveredViaCategory) {
          deliveredAny = true;
          continue;
        }
      }

      if (targetPrinters.isEmpty) {
        targetPrinters = printers;
      }

      try {
        final result = await orchestrator.enqueueKitchenPrint(
          printers: targetPrinters,
          orderNumber: orderNumber,
          orderType: orderType,
          items: sectionItems,
          note: bookingNote,
          invoiceNumber: fallbackInvoiceNumber,
          templateMeta: sectionTemplateMeta,
          clientName: clientName,
          clientPhone: clientPhone,
          tableNumber: tableNumber,
          carNumber: carNumber,
          cashierName: cashierName,
          // Section-routed tickets are implicitly category-scoped too —
          // the section itself maps to a category, so printing the
          // device/department name on top is noise. Leave this null.
          printerName: null,
          isRtl: _useArabicUi,
          primaryLang: _resolveKitchenInvoiceLang(),
        );
        if (result.success) {
          deliveredAny = true;
        }
      } catch (e) {
        print('⚠️ Failed section dispatch for booking=$orderId: $e');
      }
    }

    if (deliveredAny) {
      print('✅ Kitchen print dispatched using backend sections for #$orderId');
    }
    return deliveredAny;
  }

  Map<String, dynamic>? _selectBestKitchenReceiptNode(dynamic root) {
    final stack = <dynamic>[root];
    Map<String, dynamic>? best;
    var bestScore = -1;

    int score(Map<String, dynamic> map) {
      var value = 0;
      if (map['items'] is List) value += 8;
      if (map['booking_meals'] is List) value += 8;
      if (map['meals'] is List) value += 8;
      if (map['products'] is List) value += 4;
      if (map['card'] is List) value += 4;
      if (map.containsKey('order_number') || map.containsKey('orderNumber')) {
        value += 3;
      }
      if (map.containsKey('booking_id') || map.containsKey('order_id')) {
        value += 3;
      }
      if (map.containsKey('invoice_number') ||
          map.containsKey('invoiceNumber')) {
        value += 2;
      }
      if (map.containsKey('note') || map.containsKey('notes')) {
        value += 1;
      }
      return value;
    }

    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (node is List) {
        stack.addAll(node);
        continue;
      }

      final map = _asStringMap(node);
      if (map == null) continue;

      final currentScore = score(map);
      if (currentScore > bestScore) {
        bestScore = currentScore;
        best = map;
      }

      for (final value in map.values) {
        if (value is Map || value is List) {
          stack.add(value);
        }
      }
    }

    return best;
  }

  List<Map<String, dynamic>> _normalizeKitchenReceiptItems(
    dynamic rawItems,
    List<Map<String, dynamic>> fallbackItems,
  ) {
    final fallback = fallbackItems
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);

    if (rawItems is! List || rawItems.isEmpty) return fallback;

    final items = <Map<String, dynamic>>[];
    for (final raw in rawItems) {
      final item = _asStringMap(raw);
      if (item == null) continue;

      final nameAr = _firstNonEmptyText(<dynamic>[
        item['name_ar'],
        item['nameAr'],
        item['name'],
        item['meal_name'],
        item['item_name'],
      ]) ?? '';

      final nameEn = _firstNonEmptyText(<dynamic>[
        item['name_en'],
        item['nameEn'],
        item['item_name_en'],
      ]) ?? '';

      String resolvedAr = nameAr;
      String resolvedEn = nameEn;
      
      if (resolvedEn.trim().isEmpty && resolvedAr.contains(' - ')) {
        resolvedAr = nameAr.split(' - ').first.trim();
        resolvedEn = nameAr.split(' - ').last.trim();
      }

      if (resolvedAr.isEmpty && resolvedEn.isEmpty) continue;

      final quantity = _toSafeDouble(
        item['quantity'] ?? item['qty'] ?? item['count'],
        fallback: 1.0,
      );
      final unitPrice = _toSafeDouble(
        item['unit_price'] ?? item['unitPrice'] ?? item['price'],
      );
      final total = _toSafeDouble(
        item['total'] ?? item['line_total'] ?? item['price_total'],
        fallback: unitPrice * quantity,
      );
      final categoryName = _firstNonEmptyText(
            <dynamic>[
              item['category_name'],
              item['category'],
              item['section_name'],
              item['categoryName'],
            ],
          ) ??
          '';
      final categoryId = _firstNonEmptyText(
            <dynamic>[
              item['category_id'],
              item['categoryId'],
              item['cat_id'],
              item['section_id'],
            ],
          ) ??
          _resolveCategoryIdByName(categoryName);
      final notes =
          _firstNonEmptyText(<dynamic>[item['notes'], item['note']]) ?? '';

      // The kitchen API may key addons under several names — check each.
      final extrasRaw = item['extras'] ??
          item['addons'] ??
          item['add_ons'] ??
          item['meal_operations'] ??
          item['operations'] ??
          item['modifiers'] ??
          item['meal_addons'];
      final extras = extrasRaw is List
          ? extrasRaw
              .whereType<Map>()
              .map((entry) {
                final extra = _asStringMap(entry);
                if (extra == null) return <String, dynamic>{};
                final optionMap = _asStringMap(extra['option']);
                final attributeMap = _asStringMap(extra['attribute']);
                return {
                  'name': _firstNonEmptyText(<dynamic>[
                        extra['name'],
                        extra['addon_name'],
                        extra['operation_name'],
                        extra['option_name'],
                        optionMap?['name'],
                        attributeMap?['name'],
                        extra['title'],
                      ]) ??
                      '',
                  if (optionMap != null || attributeMap != null)
                    'translations': {
                      if (optionMap != null) 'option': optionMap,
                      if (attributeMap != null) 'attribute': attributeMap,
                    },
                };
              })
              .where((entry) => (entry['name']?.toString().isNotEmpty ?? false))
              .toList(growable: false)
          : const <Map<String, dynamic>>[];

      // Pass translations for multilingual kitchen tickets
      final mealNameTranslations = item['meal_name_translations'];
      final addonsTranslations = item['addons_translations'];
      final localizedNames = item['localizedNames'] ?? item['localized_names'];

      items.add({
        'nameAr': resolvedAr,
        'nameEn': resolvedEn,
        'name': resolvedAr.isNotEmpty ? resolvedAr : resolvedEn,
        if (localizedNames != null) 'localizedNames': localizedNames,
        if (categoryName.isNotEmpty) 'category_name': categoryName,
        if (categoryId != null && categoryId.isNotEmpty)
          'category_id': categoryId,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'total': total,
        if (notes.isNotEmpty) 'notes': notes,
        if (extras.isNotEmpty) 'extras': extras,
        if (mealNameTranslations != null) 'meal_name_translations': mealNameTranslations,
        if (addonsTranslations != null) 'addons_translations': addonsTranslations,
      });
    }

    return items.isEmpty ? fallback : items;
  }

  Map<String, dynamic> _resolveKitchenPrintPayloadFromApi({
    required Map<String, dynamic> apiResponse,
    required String fallbackOrderId,
    required String fallbackOrderType,
    required List<Map<String, dynamic>> fallbackItems,
    String? fallbackNote,
    String? fallbackInvoiceNumber,
  }) {
    final node = _selectBestKitchenReceiptNode(apiResponse) ?? const {};

    final rawItems = node['items'] ??
        node['booking_meals'] ??
        node['meals'] ??
        node['products'] ??
        node['card'];
    final items = _normalizeKitchenReceiptItems(rawItems, fallbackItems);

    var orderNumber = _firstNonEmptyText(<dynamic>[
          node['order_number'],
          node['orderNumber'],
          node['booking_number'],
          node['booking_id'],
          node['order_id'],
        ]) ??
        '#$fallbackOrderId';
    if (RegExp(r'^\d+$').hasMatch(orderNumber)) {
      orderNumber = '#$orderNumber';
    }

    final orderType = _firstNonEmptyText(<dynamic>[
          node['type'],
          node['order_type'],
          node['booking_type'],
        ]) ??
        fallbackOrderType;
    final note = _firstNonEmptyText(<dynamic>[
          node['note'],
          node['notes'],
          node['kitchen_note'],
        ]) ??
        fallbackNote;
    final invoiceNumber = _firstNonEmptyText(<dynamic>[
          node['invoice_number'],
          node['invoiceNumber'],
        ]) ??
        fallbackInvoiceNumber;

    final templateMeta = _composeKitchenTemplateMeta(
      source: apiResponse,
      fallbackOrderNumber: orderNumber,
      fallbackOrderType: orderType,
      fallbackInvoiceNumber: invoiceNumber,
      fallbackNote: note,
    );

    return {
      'orderNumber': orderNumber,
      'orderType': orderType,
      'items': items,
      'note': note,
      'invoiceNumber': invoiceNumber,
      'templateMeta': templateMeta,
    };
  }

  Future<void> _triggerKitchenPrint({
    required String orderId,
    String? invoiceNumber,
    required List<Map<String, dynamic>> orderItems,
    String? dailyOrderNumber,
    String? capturedTableNumber,
    String? carNumber,
  }) async {
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
    final String? cashierName = _userName;

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
          print(
            'ℹ️ generate-by-booking skipped for booking=$orderId kitchen_id=$kitchenId (already sent/no meals).',
          );
          continue;
        }
        onlyKnownSkipErrors = false;
        print(
          '⚠️ generate-by-booking failed for booking=$orderId kitchen_id=$kitchenId: $e',
        );
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
            print(
              '✅ Category-routed kitchen print dispatched for booking=$orderId',
            );
          } else {
            onlyKnownSkipErrors = false;
          }
        } catch (e) {
          onlyKnownSkipErrors = false;
          print(
            '⚠️ Failed category-routed kitchen print for booking=$orderId: $e',
          );
        }
        break;
      }

      if (resolvedItems.isEmpty) {
        // Successful API call with no items for this kitchen route.
        // Keep fallback path available in case parsing/shape differs by account.
        onlyKnownSkipErrors = false;
        print(
          'ℹ️ Kitchen receipt has no items for booking=$orderId kitchen_id=$kitchenId',
        );
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
          print(
            '✅ Kitchen print dispatched for booking=$orderId kitchen_id=$kitchenId printers=${routePrinters.map((p) => p.name).join(', ')}',
          );
          continue;
        }

        onlyKnownSkipErrors = false;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.userMessage ?? 'تعذر الطباعة — تحقق من اتصال الطابعة',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      } catch (e) {
        onlyKnownSkipErrors = false;
        print(
          '⚠️ Failed to enqueue kitchen print for booking=$orderId kitchen_id=$kitchenId: $e',
        );
      }
    }

    if (printedAny) return;

    // If backend explicitly says "already sent" or "no meals", avoid local reprint.
    if (apiAttempted && onlyKnownSkipErrors) {
      print(
        'ℹ️ Kitchen printing skipped for booking=$orderId due to known backend state (already sent/no meals).',
      );
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
          print('✅ Category-routed fallback print dispatched for #$orderId');
          return;
        }
      } catch (e) {
        print('⚠️ Failed category-routed fallback print for #$orderId: $e');
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              fallbackResult.userMessage ??
                  'تعذر الطباعة — تحقق من اتصال الطابعة',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('⚠️ Failed to enqueue kitchen fallback print for #$orderId: $e');
    }
  }
}
