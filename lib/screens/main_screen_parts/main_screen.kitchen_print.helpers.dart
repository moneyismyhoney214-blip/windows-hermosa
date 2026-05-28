// Kitchen-print helpers — split from main_screen.kitchen_print.dart for size.
// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, library_private_types_in_public_api
part of '../main_screen.dart';

extension MainScreenKitchenPrintHelpers on _MainScreenState {
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

  /// Pick the salon-service name in the printer's primary language.
  ///
  /// Walks the same fallback chain the restaurant kitchen-ticket flow uses,
  /// so toggling printer language affects salon turn slips identically:
  /// 1. `translations` map keyed by language code (e.g. `{ar: "...", en: "..."}`)
  /// 2. `productLocalized` — `Product.nameForLang(lang)` already applied by caller
  /// 3. `snapshotName` — the booking-time `item_name` snapshot
  /// 4. `productName` — the raw fallback name
  String _resolveSalonServiceName({
    required String lang,
    dynamic translations,
    String productLocalized = '',
    String? snapshotName,
    String productName = '',
  }) {
    String trim(String? s) => (s ?? '').trim();

    if (translations is Map) {
      final preferred = trim(translations[lang]?.toString());
      if (preferred.isNotEmpty) return preferred;
      // Sticky fallback within the map (any non-empty translation beats
      // dropping back to the snapshot, which may be the same string).
      for (final v in translations.values) {
        final s = trim(v?.toString());
        if (s.isNotEmpty) return s;
      }
    }

    final viaProduct = trim(productLocalized);
    if (viaProduct.isNotEmpty) return viaProduct;

    final snap = trim(snapshotName);
    if (snap.isNotEmpty) return snap;

    return trim(productName);
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
}
