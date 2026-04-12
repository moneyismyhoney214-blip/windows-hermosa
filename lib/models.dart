// Forced update for build_runner
import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

import 'package:hermosa_pos/services/api/api_constants.dart';

part 'models.g.dart';

String _normalizeNumberString(String input) {
  // Handle Arabic/Persian digits and decimal separators from localized APIs.
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  const persianDigits = '۰۱۲۳۴۵۶۷۸۹';

  var normalized = input.trim();
  for (var i = 0; i < 10; i++) {
    normalized = normalized.replaceAll(arabicDigits[i], i.toString());
    normalized = normalized.replaceAll(persianDigits[i], i.toString());
  }

  normalized = normalized.replaceAll('٫', '.').replaceAll('٬', ',');

  // Extract first numeric token to avoid dots from currency symbols like "ر.س".
  final match = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(normalized);
  if (match == null) return '';

  var number = match.group(0) ?? '';
  if (number.contains(',') && !number.contains('.')) {
    number = number.replaceAll(',', '.');
  } else {
    number = number.replaceAll(',', '');
  }
  return number;
}

double _parseApiPrice(dynamic value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  if (value is String) {
    final cleaned = _normalizeNumberString(value);
    return double.tryParse(cleaned) ?? 0.0;
  }
  return double.tryParse(value.toString()) ?? 0.0;
}

double? _parseApiPriceNullable(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) {
    final cleaned = _normalizeNumberString(value);
    return double.tryParse(cleaned);
  }
  return double.tryParse(value.toString());
}

bool _parseApiBool(dynamic value, {bool defaultValue = false}) {
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return defaultValue;
    if (['1', 'true', 'yes', 'on', 'active'].contains(normalized)) {
      return true;
    }
    if (['0', 'false', 'no', 'off', 'inactive'].contains(normalized)) {
      return false;
    }
    return defaultValue;
  }
  if (value is Map) {
    // Some accounts return wrapped values like {value:1} or {status:true}
    final map = value.cast<dynamic, dynamic>();
    final candidate =
        map['value'] ?? map['status'] ?? map['is_active'] ?? map['active'];
    return _parseApiBool(candidate, defaultValue: defaultValue);
  }
  return defaultValue;
}

String _normalizeLanguageCode(String? value) {
  final raw = value?.trim().toLowerCase() ?? '';
  if (raw.isEmpty) return '';
  final segments = raw.split(RegExp(r'[-_]'));
  return segments.isNotEmpty ? segments.first : raw;
}

List<String> _localizedLanguagePreference({String? preferredLanguageCode}) {
  final preference = <String>[];

  void addCode(String? code) {
    final normalized = _normalizeLanguageCode(code);
    if (normalized.isEmpty || preference.contains(normalized)) return;
    preference.add(normalized);
  }

  final normalizedPreferred = _normalizeLanguageCode(preferredLanguageCode);
  final normalizedApiLanguage =
      _normalizeLanguageCode(ApiConstants.acceptLanguage);
  final effectivePrimary = normalizedPreferred.isNotEmpty
      ? normalizedPreferred
      : normalizedApiLanguage;
  final prefersArabicFallback =
      effectivePrimary == 'ar' || effectivePrimary == 'ur';

  addCode(preferredLanguageCode);
  addCode(ApiConstants.acceptLanguage);
  addCode('en');
  if (prefersArabicFallback) {
    addCode('ar');
  }
  return preference;
}

String? _readLocalizedText(
  dynamic value, {
  String? preferredLanguageCode,
}) {
  if (value == null) return null;

  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  if (value is Iterable) {
    for (final entry in value) {
      final text = _readLocalizedText(
        entry,
        preferredLanguageCode: preferredLanguageCode,
      );
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  if (value is Map) {
    final map = value.map(
      (key, val) => MapEntry(key.toString().trim().toLowerCase(), val),
    );
    final languageOrder = _localizedLanguagePreference(
        preferredLanguageCode: preferredLanguageCode);

    for (final code in languageOrder) {
      final direct = _readLocalizedText(
        map[code],
        preferredLanguageCode: preferredLanguageCode,
      );
      if (direct != null && direct.isNotEmpty) return direct;

      const prefixes = <String>['name_', 'title_', 'label_', 'value_'];
      for (final prefix in prefixes) {
        final prefixed = _readLocalizedText(
          map['$prefix$code'],
          preferredLanguageCode: preferredLanguageCode,
        );
        if (prefixed != null && prefixed.isNotEmpty) return prefixed;
      }
    }

    const commonKeys = <String>[
      'name_display',
      'name',
      'title',
      'label',
      'text'
    ];
    for (final key in commonKeys) {
      final text = _readLocalizedText(
        map[key],
        preferredLanguageCode: preferredLanguageCode,
      );
      if (text != null && text.isNotEmpty) return text;
    }

    for (final entry in map.values) {
      final text = _readLocalizedText(
        entry,
        preferredLanguageCode: preferredLanguageCode,
      );
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

@JsonSerializable()
class Extra {
  final String id;
  final String name;
  final double price;

  const Extra({required this.id, required this.name, required this.price});

  factory Extra.fromJson(Map<String, dynamic> json) {
    String? readText(dynamic value) => _readLocalizedText(value);

    final id = json['id']?.toString() ??
        json['option']?['id']?.toString() ??
        json['attribute_id']?.toString() ??
        json['operation_id']?.toString() ??
        json['addon_id']?.toString() ??
        json['option_id']?.toString() ??
        '';
    final resolvedName = readText(json['name']) ??
        (json['option'] is Map ? readText(json['option']['name']) : null) ??
        readText(json['attribute_name']) ??
        readText(json['operation_name']) ??
        readText(json['addon_name']) ??
        readText(json['option_name']) ??
        readText(json['title']) ??
        readText(json['label']) ??
        'Extra';
    final price = _parseApiPrice(
      json['price'] ??
          json['operation_price'] ??
          json['attribute_price'] ??
          json['addon_price'] ??
          json['option_price'] ??
          json['extra_price'],
    );
    return Extra(id: id, name: resolvedName, price: price);
  }
  Map<String, dynamic> toJson() => _$ExtraToJson(this);
}

@JsonSerializable()
class Product {
  final String id;
  final String name;
  final String nameAr;
  final String nameEn;
  @JsonKey(name: 'unit_price')
  final double price;
  @JsonKey(name: 'category_name')
  final String category;
  /// Numeric category ID from the API (e.g. "15").
  /// Used directly for kitchen print routing so routing does not
  /// depend on category-name lookup at print time.
  @JsonKey(name: 'category_id')
  final String? categoryId;
  @JsonKey(name: 'is_active', defaultValue: true)
  final bool isActive;
  final String? image;
  @JsonKey(defaultValue: [])
  final List<Extra> extras;

  const Product({
    required this.id,
    required this.name,
    this.nameAr = '',
    this.nameEn = '',
    required this.price,
    required this.category,
    this.categoryId,
    this.isActive = true,
    this.image,
    this.extras = const [],
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    final normalized = Map<String, dynamic>.from(json);
    final preferredCode = _normalizeLanguageCode(ApiConstants.acceptLanguage);
    final prefersArabicUi = preferredCode == 'ar' || preferredCode == 'ur';

    normalized['name'] = _readLocalizedText([
          if (preferredCode.isNotEmpty) normalized['name_$preferredCode'],
          if (preferredCode.isNotEmpty) normalized['title_$preferredCode'],
          normalized['name_display'],
          normalized['name'],
          if (!prefersArabicUi) normalized['name_en'],
          if (!prefersArabicUi) normalized['title_en'],
          if (!prefersArabicUi) normalized['meal_name_en'],
          if (!prefersArabicUi) normalized['item_name_en'],
          normalized['meal_name'],
          normalized['item_name'],
          normalized['title'],
          normalized['label'],
          if (prefersArabicUi) normalized['name_en'],
          if (prefersArabicUi) normalized['title_en'],
          if (prefersArabicUi) normalized['meal_name_en'],
          if (prefersArabicUi) normalized['item_name_en'],
        ], preferredLanguageCode: preferredCode) ??
        'Meal';

    normalized['nameAr'] = _readLocalizedText([
      normalized['name_ar'],
      normalized['name_display_ar'],
      normalized['title_ar'],
      normalized['meal_name_ar'],
      normalized['item_name_ar'],
      normalized['nameAr'],
    ]) ?? '';

    normalized['nameEn'] = _readLocalizedText([
      normalized['name_en'],
      normalized['name_display_en'],
      normalized['title_en'],
      normalized['meal_name_en'],
      normalized['item_name_en'],
      normalized['nameEn'],
    ]) ?? '';

    final normalizedCategory = _readLocalizedText([
      normalized['category_display'],
      normalized['category_name'],
      normalized['category'],
      normalized['cat_name'],
      normalized['title_category'],
      if (normalized['category_data'] is Map)
        (normalized['category_data'] as Map)['name_display'],
      if (normalized['category_data'] is Map)
        (normalized['category_data'] as Map)['name'],
      if (normalized['category_details'] is Map)
        (normalized['category_details'] as Map)['name_display'],
      if (normalized['category_details'] is Map)
        (normalized['category_details'] as Map)['name'],
    ]);
    normalized['category_name'] = normalizedCategory ?? '';

    // Resolve category_id from multiple possible API field names.
    // Priority: category_id > cat_id > nested category/category_data.id
    final rawCatId = normalized['category_id'] ??
        normalized['cat_id'] ??
        (normalized['category_data'] is Map
            ? normalized['category_data']['id']
            : null) ??
        (normalized['category_details'] is Map
            ? normalized['category_details']['id']
            : null) ??
        (normalized['category'] is Map
            ? normalized['category']['id']
            : null);
    if (rawCatId != null) {
      normalized['category_id'] = rawCatId.toString();
    }

    // Handle id being int or string in API
    if (normalized['id'] is int) {
      normalized['id'] = normalized['id'].toString();
    }

    // Handle price mapping and parsing
    // API returns 'price' as "6.00 SAR", model expects 'unit_price' as double
    normalized['unit_price'] = _parseApiPrice(
      normalized['unit_price'] ?? normalized['price'],
    );

    // Handle image path normalization - Meals use portal.hermosaapp.com
    if (normalized['image'] != null && normalized['image'] is String) {
      String imagePath = normalized['image'];
      if (imagePath.isNotEmpty && !imagePath.startsWith('http')) {
        if (!imagePath.startsWith('/')) {
          imagePath = '/$imagePath';
        }
        // Specific requirement: Meals images from portal.hermosaapp.com
        normalized['image'] = 'https://portal.hermosaapp.com$imagePath';
      }
    }

    // Handle extras/addons - API might use different field names
    List<dynamic>? extrasData;

    // Handle boolean values that may arrive as map/string/number
    normalized['is_active'] =
        _parseApiBool(normalized['is_active'], defaultValue: true);

    // Try different possible field names for add-ons
    if (normalized['extras'] != null && normalized['extras'] is List) {
      extrasData = normalized['extras'] as List;
    } else if (normalized['add_ons'] != null && normalized['add_ons'] is List) {
      extrasData = normalized['add_ons'] as List;
    } else if (normalized['addons'] != null && normalized['addons'] is List) {
      extrasData = normalized['addons'] as List;
    } else if (normalized['meal_addons'] != null &&
        normalized['meal_addons'] is List) {
      extrasData = normalized['meal_addons'] as List;
    } else if (normalized['options'] != null && normalized['options'] is List) {
      extrasData = normalized['options'] as List;
    } else if (normalized['modifiers'] != null &&
        normalized['modifiers'] is List) {
      extrasData = normalized['modifiers'] as List;
    } else if (normalized['cooking_type'] != null &&
        normalized['cooking_type'] is List) {
      extrasData = normalized['cooking_type'] as List;
    } else if (normalized['meal_attributes'] != null &&
        normalized['meal_attributes'] is List) {
      extrasData = normalized['meal_attributes'] as List;
    } else if (normalized['operations'] != null &&
        normalized['operations'] is List) {
      extrasData = normalized['operations'] as List;
    } else if (normalized['meal_options'] != null &&
        normalized['meal_options'] is List) {
      extrasData = normalized['meal_options'] as List;
    }

    // Normalize extras data to match Extra model
    if (extrasData != null && extrasData.isNotEmpty) {
      normalized['extras'] = extrasData.map((item) {
        if (item is Map) {
          final normalizedItem = item is Map<String, dynamic>
              ? item
              : item.map((k, v) => MapEntry(k.toString(), v));
          // Handle different field names within each extra/addon
          final extraMap = <String, dynamic>{};

          // ID mapping
          if (normalizedItem['id'] != null) {
            extraMap['id'] = normalizedItem['id'].toString();
          } else if (normalizedItem['option'] is Map &&
              normalizedItem['option']['id'] != null) {
            extraMap['id'] = normalizedItem['option']['id'].toString();
          } else if (normalizedItem['attribute_id'] != null) {
            extraMap['id'] = normalizedItem['attribute_id'].toString();
          } else if (normalizedItem['operation_id'] != null) {
            extraMap['id'] = normalizedItem['operation_id'].toString();
          } else if (normalizedItem['addon_id'] != null) {
            extraMap['id'] = normalizedItem['addon_id'].toString();
          } else if (normalizedItem['option_id'] != null) {
            extraMap['id'] = normalizedItem['option_id'].toString();
          } else {
            extraMap['id'] = DateTime.now().millisecondsSinceEpoch.toString();
          }

          // Name mapping
          if (normalizedItem['name'] != null) {
            extraMap['name'] = normalizedItem['name'];
          } else if (normalizedItem['option'] is Map &&
              normalizedItem['option']['name'] != null) {
            extraMap['name'] = normalizedItem['option']['name'];
          } else if (normalizedItem['attribute_name'] != null) {
            extraMap['name'] = normalizedItem['attribute_name'];
          } else if (normalizedItem['operation_name'] != null) {
            extraMap['name'] = normalizedItem['operation_name'];
          } else if (normalizedItem['addon_name'] != null) {
            extraMap['name'] = normalizedItem['addon_name'];
          } else if (normalizedItem['option_name'] != null) {
            extraMap['name'] = normalizedItem['option_name'];
          } else if (normalizedItem['title'] != null) {
            extraMap['name'] = normalizedItem['title'];
          } else if (normalizedItem['label'] != null) {
            extraMap['name'] = normalizedItem['label'];
          } else {
            extraMap['name'] = 'Extra';
          }

          // Price mapping
          if (normalizedItem['price'] != null) {
            extraMap['price'] = _parseApiPrice(normalizedItem['price']);
          } else if (normalizedItem['operation_price'] != null) {
            extraMap['price'] =
                _parseApiPrice(normalizedItem['operation_price']);
          } else if (normalizedItem['attribute_price'] != null) {
            extraMap['price'] =
                _parseApiPrice(normalizedItem['attribute_price']);
          } else if (normalizedItem['addon_price'] != null) {
            extraMap['price'] = _parseApiPrice(normalizedItem['addon_price']);
          } else if (normalizedItem['option_price'] != null) {
            extraMap['price'] = _parseApiPrice(normalizedItem['option_price']);
          } else if (normalizedItem['extra_price'] != null) {
            extraMap['price'] = _parseApiPrice(normalizedItem['extra_price']);
          } else {
            extraMap['price'] = 0.0;
          }

          return extraMap;
        }
        return item;
      }).toList();
    }

    return _$ProductFromJson(normalized);
  }
  Map<String, dynamic> toJson() => _$ProductToJson(this);
}

enum DiscountType { amount, percentage }

@JsonSerializable()
class CartItem {
  final String cartId;
  final Product product;
  double quantity;
  @JsonKey(defaultValue: [])
  final List<Extra> selectedExtras;
  double discount;
  @JsonKey(defaultValue: DiscountType.amount)
  DiscountType discountType;
  bool isFree;
  @JsonKey(defaultValue: '')
  String notes; // Added notes

  CartItem({
    required this.cartId,
    required this.product,
    this.quantity = 1.0,
    this.selectedExtras = const [],
    this.discount = 0.0,
    this.discountType = DiscountType.amount,
    this.isFree = false,
    this.notes = '',
  });

  factory CartItem.fromJson(Map<String, dynamic> json) =>
      _$CartItemFromJson(json);
  Map<String, dynamic> toJson() => _$CartItemToJson(this);

  double get totalPrice {
    if (isFree) return 0.0;
    final basePrice =
        (product.price + selectedExtras.fold(0.0, (sum, e) => sum + e.price)) *
            quantity;

    if (discountType == DiscountType.percentage) {
      // Percentage discount must always stay in [0, 100].
      final validPercentage = discount.clamp(0.0, 100.0);
      return basePrice * (1 - (validPercentage / 100));
    }
    // Amount discount must stay in [0, basePrice].
    final validDiscount = discount.clamp(0.0, basePrice);
    return basePrice - validDiscount;
  }
}

// IconData is not directly serializable. We'll handle it manually or skip it from JSON for now,
// assuming the API returns an icon name/key instead of raw IconData.
// For simplicity in this step, we'll make icon strictly runtime or map a string info.
// We will exclude 'icon' from JSON generation or use a custom converter if needed.
// Here we'll ignore it for JSON to avoid build errors, assuming UI maps ID to Icon.

@JsonSerializable()
class CategoryModel {
  final String id;
  final String name;
  final String? type;
  @JsonKey(name: 'parent_id')
  final String? parentId;
  @JsonKey(includeFromJson: false, includeToJson: false)
  final IconData icon;
  @JsonKey(
      name:
          'icon') // Map API 'icon' url to this field, but we'll handle parsing manually if needed
  final String? imageUrl;

  const CategoryModel({
    required this.id,
    required this.name,
    this.type,
    this.parentId,
    this.icon = Icons.category,
    this.imageUrl,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    // Create a mutable copy
    final mutableJson = Map<String, dynamic>.from(json);

    // Handle id mapping (prefer 'id', fallback to 'value', 'category_id', 'cat_id')
    if (mutableJson['id'] == null) {
      if (mutableJson['value'] != null) {
        mutableJson['id'] = mutableJson['value'].toString();
      } else if (mutableJson['category_id'] != null) {
        mutableJson['id'] = mutableJson['category_id'].toString();
      } else if (mutableJson['cat_id'] != null) {
        mutableJson['id'] = mutableJson['cat_id'].toString();
      }
    } else if (mutableJson['id'] is int) {
      mutableJson['id'] = mutableJson['id'].toString();
    }

    // Handle name mapping (prefer 'name', fallback to 'label', 'category_name', 'title')
    if (mutableJson['name'] == null) {
      if (mutableJson['label'] != null) {
        mutableJson['name'] = mutableJson['label'];
      } else if (mutableJson['category_name'] != null) {
        mutableJson['name'] = mutableJson['category_name'];
      } else if (mutableJson['title'] != null) {
        mutableJson['name'] = mutableJson['title'];
      }
    }

    mutableJson['name'] = _readLocalizedText([
          mutableJson['name_display'],
          mutableJson['name'],
          mutableJson['label'],
          mutableJson['category_name'],
          mutableJson['title'],
        ]) ??
        'Unknown';

    // Normalize parent_id
    if (mutableJson['parent_id'] is int) {
      mutableJson['parent_id'] = mutableJson['parent_id'].toString();
    }

    // Ensure imageUrl (mapped to 'icon') is set from various possible fields
    if (mutableJson['icon'] == null) {
      if (mutableJson['image'] != null) {
        mutableJson['icon'] = mutableJson['image'];
      } else if (mutableJson['icon_url'] != null) {
        mutableJson['icon'] = mutableJson['icon_url'];
      } else if (mutableJson['image_url'] != null) {
        mutableJson['icon'] = mutableJson['image_url'];
      }
    }

    // Handle icon/image path normalization
    if (mutableJson['icon'] != null && mutableJson['icon'] is String) {
      String iconPath = mutableJson['icon'];
      if (iconPath.isNotEmpty && !iconPath.startsWith('http')) {
        if (!iconPath.startsWith('/')) {
          iconPath = '/$iconPath';
        }
        mutableJson['icon'] = '${ApiConstants.baseUrl}$iconPath';
      }
    }

    return _$CategoryModelFromJson(mutableJson);
  }
  Map<String, dynamic> toJson() => _$CategoryModelToJson(this);
}

class NavItem {
  final String id;
  final IconData icon;
  final String label;

  const NavItem({required this.id, required this.icon, required this.label});
}

enum PrinterConnectionType { wifi, bluetooth }

@JsonSerializable()
class DeviceConfig {
  final String id;
  String name;
  String ip;
  @JsonKey(defaultValue: '9100')
  String port;
  String type;
  String model;
  @JsonKey(defaultValue: PrinterConnectionType.wifi)
  PrinterConnectionType connectionType;
  String? bluetoothAddress;
  String? bluetoothName;
  @JsonKey(defaultValue: false)
  bool isOnline;
  @JsonKey(defaultValue: 1)
  int copies;
  @JsonKey(defaultValue: 58)
  int paperWidthMm;

  DeviceConfig({
    required this.id,
    required this.name,
    required this.ip,
    this.port = '9100',
    required this.type,
    required this.model,
    this.connectionType = PrinterConnectionType.wifi,
    this.bluetoothAddress,
    this.bluetoothName,
    this.isOnline = false,
    this.copies = 1,
    this.paperWidthMm = 58,
  });

  factory DeviceConfig.fromJson(Map<String, dynamic> json) =>
      _$DeviceConfigFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceConfigToJson(this);
}

enum TableStatus { available, occupied, printed }

@JsonSerializable()
class TableItem {
  final String id;
  @JsonKey(name: 'name') // API uses 'name' for table number
  final String number;
  @JsonKey(name: 'floor_id', defaultValue: 'f1')
  final String floorId;
  @JsonKey(defaultValue: 4)
  final int seats;
  @JsonKey(defaultValue: TableStatus.available)
  TableStatus
      status; // API doesn't seem to return status yet, default available
  @JsonKey(name: 'occupied_minutes', defaultValue: 0)
  int occupiedMinutes;
  @JsonKey(name: 'waiter_name')
  String? waiterName;
  @JsonKey(defaultValue: false)
  bool isPaid;
  @JsonKey(name: 'qr_image')
  final String? qrImage;
  @JsonKey(name: 'is_active', defaultValue: true)
  final bool isActive;
  @JsonKey(includeFromJson: false, includeToJson: false)
  double? positionX;
  @JsonKey(includeFromJson: false, includeToJson: false)
  double? positionY;

  TableItem({
    required this.id,
    required this.number,
    this.floorId = 'f1', // Default floor
    this.seats = 4, // Default seats
    this.status = TableStatus.available,
    this.occupiedMinutes = 0,
    this.waiterName,
    this.isPaid = false,
    this.qrImage,
    this.isActive = true,
    this.positionX,
    this.positionY,
  });

  factory TableItem.fromJson(Map<String, dynamic> json) {
    final normalized = Map<String, dynamic>.from(json);

    // Handle id being int or string
    final rawId = normalized['id'] ??
        normalized['table_id'] ??
        normalized['tableId'] ??
        normalized['tableID'];
    if (rawId != null) {
      normalized['id'] = rawId;
    }
    if (normalized['id'] is int) {
      normalized['id'] = normalized['id'].toString();
    }

    // Handle name/number being int or string
    // API sometimes uses 'name', sometimes 'number'
    final rawName = normalized['name'] ??
        normalized['table_name'] ??
        normalized['tableName'] ??
        normalized['number'];
    if (rawName != null) {
      normalized['name'] = rawName;
    }
    if (normalized['name'] == null && normalized['number'] != null) {
      normalized['name'] = normalized['number'].toString();
    } else if (normalized['name'] is int) {
      normalized['name'] = normalized['name'].toString();
    }

    // Handle seats mapping from common backend keys
    final rawSeats =
        normalized['seats'] ?? normalized['chairs'] ?? normalized['capacity'];
    final parsedSeats = rawSeats is num
        ? rawSeats.toInt()
        : int.tryParse(rawSeats?.toString() ?? '');
    normalized['seats'] =
        (parsedSeats != null && parsedSeats > 0) ? parsedSeats : 4;

    // Map floor_id (1->f1, 2->f2)
    if (normalized['floor_id'] != null) {
      final fId = normalized['floor_id'].toString();
      if (fId == '1') {
        normalized['floor_id'] = 'f1';
      } else if (fId == '2') {
        normalized['floor_id'] = 'f2';
      } else {
        // Keep original if it's already a string or unknown, usually safely parsed as string by json_serializable
        // But since we annotated with name='floor_id', we should ensure it's what we want
        normalized['floor_id'] = fId;
      }
    }

    // Handle status mapping
    if (normalized['status'] != null) {
      final s = normalized['status'].toString().trim().toLowerCase();
      final occupiedLike = <String>{
        '1',
        'occupied',
        'busy',
        'reserved',
        'booked',
        'booking',
        'pending',
      };
      final printedLike = <String>{'2', 'printed'};

      if (occupiedLike.contains(s)) {
        normalized['status'] = TableStatus.occupied;
      } else if (printedLike.contains(s)) {
        normalized['status'] = TableStatus.printed;
      } else {
        normalized['status'] = TableStatus.available;
      }
    }

    final hasReservationHints = _parseApiBool(normalized['is_reserved']) ||
        _parseApiBool(normalized['reserved']) ||
        normalized['booking_id'] != null ||
        normalized['current_booking'] != null;
    if ((normalized['status'] == null ||
            normalized['status'] == TableStatus.available) &&
        hasReservationHints) {
      normalized['status'] = TableStatus.occupied;
    }

    // Handle boolean values that may arrive as map/string/number
    normalized['is_active'] =
        _parseApiBool(normalized['is_active'], defaultValue: true);
    normalized['isPaid'] =
        _parseApiBool(normalized['isPaid'] ?? normalized['is_paid']);

    return TableItem(
      id: normalized['id']?.toString() ?? '',
      number: normalized['name']?.toString() ?? '',
      floorId: normalized['floor_id']?.toString() ?? 'f1',
      seats: normalized['seats'] as int? ?? 4,
      status: normalized['status'] is TableStatus
          ? normalized['status'] as TableStatus
          : TableStatus.available,
      occupiedMinutes:
          int.tryParse(normalized['occupied_minutes']?.toString() ?? '0') ?? 0,
      waiterName: normalized['waiter_name']?.toString(),
      isPaid: _parseApiBool(normalized['isPaid'] ?? normalized['is_paid']),
      qrImage: normalized['qr_image']?.toString(),
      isActive: _parseApiBool(normalized['is_active'], defaultValue: true),
    );
  }
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': number,
        'floor_id': floorId,
        'seats': seats,
        'status': status.name,
        'occupied_minutes': occupiedMinutes,
        'waiter_name': waiterName,
        'isPaid': isPaid,
        'qr_image': qrImage,
        'is_active': isActive,
      };
}

@JsonSerializable()
class PromoCode {
  final String id;
  final String code;
  final double discount;
  @JsonKey(name: 'discount_type')
  final DiscountType type;

  // Extra display fields from API
  final double? maxDiscount;
  final String? maxDiscountDisplay;
  final double? minPay;
  final String? minPayDisplay;
  final String? durationFrom;
  final String? durationTo;
  final int? maxUse;
  final bool isActive;

  const PromoCode({
    required this.id,
    required this.code,
    required this.discount,
    required this.type,
    this.maxDiscount,
    this.maxDiscountDisplay,
    this.minPay,
    this.minPayDisplay,
    this.durationFrom,
    this.durationTo,
    this.maxUse,
    this.isActive = true,
  });

  factory PromoCode.fromJson(Map<String, dynamic> json) {
    final normalized = Map<String, dynamic>.from(json);

    final rawId = normalized['id'] ??
        normalized['promocode_id'] ??
        normalized['promo_id'] ??
        normalized['value'];
    normalized['id'] = rawId?.toString() ?? '';

    final rawCode = _readLocalizedText(
          normalized['code'] ??
              normalized['promocode'] ??
              normalized['promocodeValue'] ??
              normalized['promocode_name'] ??
              normalized['name'] ??
              normalized['label'],
        ) ??
        '';
    normalized['code'] = rawCode;

    final rawDiscount = normalized['discount'] ??
        normalized['discount_value'] ??
        normalized['percentage'] ??
        normalized['value'] ??
        normalized['amount'];
    normalized['discount'] = _parseApiPrice(rawDiscount);

    final typeToken = (normalized['discount_type'] ??
            normalized['discountType'] ??
            normalized['type'])
        ?.toString()
        .trim()
        .toLowerCase();
    if (typeToken == 'percentage' ||
        typeToken == 'percent' ||
        typeToken == '%') {
      normalized['discount_type'] = 'percentage';
    } else {
      // Backend commonly sends "fixed" for amount discounts.
      normalized['discount_type'] = 'amount';
    }

    final base = _$PromoCodeFromJson(normalized);
    return PromoCode(
      id: base.id,
      code: base.code,
      discount: base.discount,
      type: base.type,
      maxDiscount: _parseApiPriceNullable(json['max_discount']),
      maxDiscountDisplay: json['max_discount_display']?.toString(),
      minPay: _parseApiPriceNullable(json['min_pay']),
      minPayDisplay: json['min_pay_display']?.toString(),
      durationFrom: json['duration_from']?.toString(),
      durationTo: json['duration_to']?.toString(),
      maxUse: json['max_use'] is num ? (json['max_use'] as num).toInt() : null,
      isActive: json['is_active'] == true ||
          json['is_active'] == 1 ||
          json['is_active']?.toString() == 'true',
    );
  }

  Map<String, dynamic> toJson() => _$PromoCodeToJson(this);
}
