import '../services/api/api_constants.dart';

double _parseFlexibleDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();

  var text = value.toString().trim();
  if (text.isEmpty) return 0.0;

  text = text.replaceAll(',', '').replaceAll(RegExp(r'[^0-9.\-]'), '');

  return double.tryParse(text) ?? 0.0;
}

int? _parseFlexibleInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return int.tryParse(text);
}

String _normalizeBookingLanguageCode(String? value) {
  final raw = value?.trim().toLowerCase() ?? '';
  if (raw.isEmpty) return '';
  final parts = raw.split(RegExp(r'[-_]'));
  return parts.isNotEmpty ? parts.first : raw;
}

String? _readLocalizedBookingText(dynamic value) {
  if (value == null) return null;
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
  if (value is Iterable) {
    for (final item in value) {
      final text = _readLocalizedBookingText(item);
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }
  if (value is Map) {
    final map = value
        .map((key, val) => MapEntry(key.toString().trim().toLowerCase(), val));
    final languagePreference = <String>[];
    void addCode(String? code) {
      final normalized = _normalizeBookingLanguageCode(code);
      if (normalized.isEmpty || languagePreference.contains(normalized)) return;
      languagePreference.add(normalized);
    }

    addCode(ApiConstants.acceptLanguage);
    addCode('en');
    addCode('ar');

    for (final code in languagePreference) {
      final direct = _readLocalizedBookingText(map[code]);
      if (direct != null && direct.isNotEmpty) return direct;
      final byName = _readLocalizedBookingText(map['name_$code']);
      if (byName != null && byName.isNotEmpty) return byName;
      final byTitle = _readLocalizedBookingText(map['title_$code']);
      if (byTitle != null && byTitle.isNotEmpty) return byTitle;
    }

    for (final key in const ['name_display', 'name', 'title', 'label']) {
      final text = _readLocalizedBookingText(map[key]);
      if (text != null && text.isNotEmpty) return text;
    }

    for (final item in map.values) {
      final text = _readLocalizedBookingText(item);
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

String? _firstMeaningfulText(
  List<dynamic> values, {
  bool allowZero = true,
}) {
  for (final value in values) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
      continue;
    }
    if (!allowZero) {
      final normalized = text.startsWith('#') ? text.substring(1) : text;
      final parsed = int.tryParse(normalized);
      if (parsed != null && parsed == 0) {
        continue;
      }
    }
    return text;
  }
  return null;
}

List<Map<String, dynamic>> _extractBookingMealRows(
  Map<String, dynamic> source, {
  Map<String, dynamic>? orderMap,
  Map<String, dynamic>? bookingMap,
}) {
  List<Map<String, dynamic>> fromDynamic(dynamic value) {
    if (value is! List) return const <Map<String, dynamic>>[];
    final rows = <Map<String, dynamic>>[];
    for (final row in value.whereType<Map>()) {
      rows.add(row.map((k, v) => MapEntry(k.toString(), v)));
    }
    return rows;
  }

  final candidates = <dynamic>[
    source['meals'],
    source['booking_meals'],
    source['booking_products'],
    source['sales_meals'],
    source['items'],
    source['card'],
    orderMap?['meals'],
    orderMap?['booking_meals'],
    orderMap?['booking_products'],
    bookingMap?['meals'],
    bookingMap?['booking_meals'],
    bookingMap?['booking_products'],
  ];

  for (final candidate in candidates) {
    final rows = fromDynamic(candidate);
    if (rows.isNotEmpty) return rows;
  }
  return const <Map<String, dynamic>>[];
}

/// Booking model representing an order/booking
class Booking {
  final int id;
  final int? orderId;
  final String? orderNumber;
  final String? bookingNumberRaw;
  final String type;
  final String status;
  final int? tableId;
  final String? tableName;
  final String date;
  final double total;
  final double tax;
  final double discount;
  final String? customerName;
  final String? customerPhone;
  final List<BookingMeal> meals;
  final String createdAt;
  final String? updatedAt;
  final String? invoiceNumber;
  final bool isPaid;
  final String? notes;
  final String? platform;
  final Map<String, dynamic>? typeExtra;
  final Map<String, dynamic> raw;

  Booking({
    required this.id,
    this.orderId,
    this.orderNumber,
    this.bookingNumberRaw,
    required this.type,
    required this.status,
    this.tableId,
    this.tableName,
    required this.date,
    required this.total,
    required this.tax,
    required this.discount,
    this.customerName,
    this.customerPhone,
    required this.meals,
    required this.createdAt,
    this.updatedAt,
    this.invoiceNumber,
    required this.isPaid,
    this.notes,
    this.platform,
    this.typeExtra,
    this.raw = const {},
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    final orderMap = json['order'] is Map
        ? (json['order'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : null;
    final bookingMap = json['booking'] is Map
        ? (json['booking'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : null;

    final id = _parseFlexibleInt(
          json['booking_id'] ?? json['id'] ?? bookingMap?['id'],
        ) ??
        0;
    final orderId = _parseFlexibleInt(
      json['order_id'] ?? orderMap?['id'] ?? bookingMap?['order_id'],
    );
    final tableId = _parseFlexibleInt(
      json['table_id'] ?? bookingMap?['table_id'],
    );
    final typeExtraMap = json['type_extra'] is Map
        ? Map<String, dynamic>.from(json['type_extra'] as Map)
        : bookingMap?['type_extra'] is Map
            ? Map<String, dynamic>.from(bookingMap!['type_extra'] as Map)
            : null;
    final orderNumber = _firstMeaningfulText(
      [
        json['daily_order_number'],
        bookingMap?['daily_order_number'],
        json['order_number'],
        bookingMap?['order_number'],
        orderMap?['order_number'],
      ],
      allowZero: false,
    );
    final mealRows = _extractBookingMealRows(
      json,
      orderMap: orderMap,
      bookingMap: bookingMap,
    );

    return Booking(
      id: id,
      orderId: orderId,
      // Real cashier order number should be prioritized over booking reference.
      orderNumber: orderNumber,
      bookingNumberRaw: _firstMeaningfulText([
        json['booking_number'],
        bookingMap?['booking_number'],
      ]),
      type: _firstMeaningfulText([
            json['type'],
            bookingMap?['type'],
          ]) ??
          '',
      status: json['status']?.toString() ?? 'pending',
      tableId: tableId,
      tableName: json['table_name']?.toString() ??
          typeExtraMap?['table_name']?.toString(),
      date: _firstMeaningfulText([
            json['date'],
            bookingMap?['date'],
          ]) ??
          '',
      total: _parseFlexibleDouble(
          json['total'] ?? json['total_price'] ?? json['grand_total']),
      tax: _parseFlexibleDouble(json['tax']),
      discount: _parseFlexibleDouble(json['discount']),
      customerName: json['customer_name']?.toString() ??
          json['customer']?['name']?.toString() ??
          json['client']?.toString(),
      customerPhone: json['customer_phone']?.toString() ??
          json['customer']?['mobile']?.toString() ??
          json['phone']?.toString(),
      meals: mealRows.map((e) => BookingMeal.fromJson(e)).toList(),
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString(),
      invoiceNumber: json['invoice_number']?.toString(),
      isPaid: json['is_paid'] == true ||
          json['status']?.toString() == '7' ||
          json['status']?.toString() == 'completed',
      notes: json['notes']?.toString(),
      platform: json['platform']?.toString(),
      typeExtra: typeExtraMap,
      raw: Map<String, dynamic>.from(json),
    );
  }

  String? get bookingNumber => bookingNumberRaw ?? orderNumber;

  int get itemCount {
    var quantitySum = 0;
    for (final meal in meals) {
      if (meal.quantity > 0) {
        quantitySum += meal.quantity;
      }
    }
    if (quantitySum > 0) return quantitySum;

    int? parsePositiveInt(dynamic value) {
      final parsed = _parseFlexibleInt(value);
      if (parsed == null || parsed <= 0) return null;
      return parsed;
    }

    final counterCandidates = <dynamic>[
      raw['items_count'],
      raw['meals_count'],
      raw['products_count'],
      raw['booking_meals_count'],
      raw['booking_products_count'],
      raw['count'],
      raw['quantity'],
      raw['qty'],
    ];
    for (final candidate in counterCandidates) {
      final parsed = parsePositiveInt(candidate);
      if (parsed != null) return parsed;
    }

    final fallbackRows = _extractBookingMealRows(raw);
    if (fallbackRows.isNotEmpty) return fallbackRows.length;
    return 0;
  }

  String get statusDisplay {
    final apiStatusDisplay = raw['status_display']?.toString().trim();
    if (apiStatusDisplay != null && apiStatusDisplay.isNotEmpty) {
      return apiStatusDisplay;
    }

    switch (status) {
      case '1':
      case 'confirmed':
      case 'new':
      case 'pending':
        return 'جديد';
      case '2':
      case 'started':
        return 'بدأ';
      case '3':
        return 'انتهي';
      case '4':
      case 'preparing':
      case 'processing':
        return 'جاري التحضير';
      case '5':
      case 'ready':
      case 'ready_for_delivery':
        return 'جاهز للتوصيل';
      case '6':
      case 'on_the_way':
      case 'out_for_delivery':
        return 'قيد التوصيل';
      case '7':
      case 'finished':
      case 'done':
      case 'completed':
        return 'مكتمل';
      case '8':
      case 'cancelled':
      case 'canceled':
        return 'ملغي';
      default:
        return status;
    }
  }

  String get typeDisplay {
    final apiTypeText = raw['type_text']?.toString().trim();
    if (apiTypeText != null && apiTypeText.isNotEmpty) {
      return apiTypeText;
    }

    switch (type) {
      case 'restaurant_delivery':
        return 'دليفري';
      case 'restaurant_table':
        return 'طاولة';
      case 'services':
        return 'محلي';
      default:
        return type;
    }
  }
}

class BookingMeal {
  final int id;
  final int mealId;
  final String mealName;
  final int quantity;
  final double unitPrice;
  final double total;
  final String? notes;

  BookingMeal({
    required this.id,
    required this.mealId,
    required this.mealName,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.notes,
  });

  factory BookingMeal.fromJson(Map<String, dynamic> json) {
    // Handle id being int or string
    var id = json['id'];
    if (id is String) {
      id = int.tryParse(id) ?? 0;
    } else {
      id ??= 0;
    }

    // Handle meal_id being int or string
    var mealId = json['meal_id'];
    if (mealId is String) {
      mealId = int.tryParse(mealId) ?? 0;
    } else {
      mealId ??= 0;
    }

    // Handle quantity being int or string
    var quantity = json['quantity'];
    if (quantity is String) {
      quantity = int.tryParse(quantity) ?? 0;
    } else {
      quantity ??= 0;
    }

    // API returns 'price' as the LINE TOTAL (unit * qty), NOT unit price.
    // 'unit_price' is often null. 'total' is also often null.
    // We need to handle this correctly:
    // - total = total ?? price (since price IS the line total)
    // - unitPrice = unit_price ?? (price / quantity)
    final rawPrice = _parseFlexibleDouble(json['price']);
    final rawUnitPrice = _parseFlexibleDouble(
        json['unit_price'] ?? json['unitPrice']);
    final rawTotal = _parseFlexibleDouble(
        json['total'] ?? json['total_price'] ?? json['line_total']);
    final qty = quantity is int && quantity > 0 ? quantity : 1;

    final double resolvedTotal;
    final double resolvedUnitPrice;

    if (rawTotal > 0) {
      resolvedTotal = rawTotal;
      resolvedUnitPrice = rawUnitPrice > 0 ? rawUnitPrice : rawTotal / qty;
    } else if (rawPrice > 0) {
      // 'price' from API is the line total when unit_price is null
      if (rawUnitPrice > 0) {
        resolvedUnitPrice = rawUnitPrice;
        resolvedTotal = rawPrice; // price is line total
      } else {
        // price is line total, derive unit price
        resolvedTotal = rawPrice;
        resolvedUnitPrice = rawPrice / qty;
      }
    } else {
      resolvedTotal = 0;
      resolvedUnitPrice = rawUnitPrice;
    }

    return BookingMeal(
      id: id,
      mealId: mealId,
      mealName: _readLocalizedBookingText(
            [json['meal_name'], json['name'], json['item_name'], json['title']],
          ) ??
          '',
      quantity: qty,
      unitPrice: resolvedUnitPrice,
      total: resolvedTotal,
      notes: json['notes']?.toString(),
    );
  }
}

/// Invoice model
class Invoice {
  final int id;
  final String invoiceNumber;
  final String date;
  final String? customerName;
  final double total;
  final double tax;
  final double discount;
  final double paid;
  final String status;
  final String? payMethod;
  final int? orderId;
  final String createdAt;
  final String? updatedAt;
  final double grandTotal;
  final double remaining;
  final String? notes;
  final Map<String, dynamic> raw;

  Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.date,
    this.customerName,
    required this.total,
    required this.tax,
    required this.discount,
    required this.paid,
    required this.status,
    this.payMethod,
    this.orderId,
    required this.createdAt,
    this.updatedAt,
    required this.grandTotal,
    required this.remaining,
    this.notes,
    this.raw = const {},
  });

  factory Invoice.fromJson(Map<String, dynamic> json) {
    // Handle id being int or string
    var id = json['id'];
    if (id is String) {
      id = int.tryParse(id) ?? 0;
    } else {
      id ??= 0;
    }

    // Handle order_id being int or string
    var orderId =
        json['order_id'] ?? json['order']?['id'] ?? json['booking_id'];
    if (orderId is String) {
      orderId = int.tryParse(orderId);
    }

    return Invoice(
      id: id,
      invoiceNumber:
          json['invoice_number']?.toString() ?? json['id']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ??
          json['customer']?['name']?.toString() ??
          json['client']?.toString(),
      total: _parseFlexibleDouble(
          json['total'] ?? json['grand_total'] ?? json['invoice_total']),
      tax: _parseFlexibleDouble(json['tax']),
      discount: _parseFlexibleDouble(json['discount']),
      paid: _parseFlexibleDouble(json['paid']),
      status: json['status']?.toString() ?? '',
      payMethod: json['pay_method']?.toString() ?? json['pays']?.toString(),
      orderId: orderId,
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString(),
      grandTotal: _parseFlexibleDouble(
          json['grand_total'] ?? json['total'] ?? json['invoice_total']),
      remaining: _parseFlexibleDouble(json['remaining'] ?? json['unpaid']),
      notes: json['notes']?.toString(),
      raw: Map<String, dynamic>.from(json),
    );
  }

  String get statusDisplay {
    final apiStatusDisplay = raw['status_display']?.toString().trim();
    if (apiStatusDisplay != null && apiStatusDisplay.isNotEmpty) {
      return apiStatusDisplay;
    }

    switch (status) {
      case '2':
      case 'paid':
        return 'مدفوع';
      case '1':
      case 'pending':
        return 'معلق';
      case '3':
      case 'partial':
        return 'مدفوع جزئياً';
      case '4':
      case 'refunded':
        return 'مسترجع';
      default:
        return status;
    }
  }
}

/// Payment Method model
class PaymentMethod {
  final String id;
  final String name;
  final String code;
  final bool isActive;

  PaymentMethod({
    required this.id,
    required this.name,
    required this.code,
    required this.isActive,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      isActive: json['is_active'] ?? true,
    );
  }
}

/// Booking Response
class BookingResponse {
  final List<Booking> data;
  final int status;
  final String? message;

  BookingResponse({
    required this.data,
    required this.status,
    this.message,
  });

  factory BookingResponse.fromJson(Map<String, dynamic> json) {
    return BookingResponse(
      data: (json['data'] as List?)?.map((e) => Booking.fromJson(e)).toList() ??
          [],
      status: json['status'] ?? 200,
      message: json['message'],
    );
  }
}

class OptionItem {
  final String label;
  final String value;

  OptionItem({required this.label, required this.value});

  factory OptionItem.fromJson(Map<String, dynamic> json) {
    return OptionItem(
      label: json['label']?.toString() ?? '',
      value: json['value']?.toString() ?? '',
    );
  }
}

class BookingSettings {
  final List<OptionItem> typeOptions;
  final List<OptionItem> tableOptions;

  BookingSettings({
    required this.typeOptions,
    required this.tableOptions,
  });

  factory BookingSettings.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is Map<String, dynamic>) {
      return BookingSettings(
        typeOptions: (data['typeOptions'] as List?)
                ?.map((e) => OptionItem.fromJson(e))
                .toList() ??
            [],
        tableOptions: (data['tableOptions'] as List?)
                ?.map((e) => OptionItem.fromJson(e))
                .toList() ??
            [],
      );
    }
    return BookingSettings(typeOptions: [], tableOptions: []);
  }
}

/// Invoice Response
class InvoiceResponse {
  final List<Invoice> data;
  final int status;
  final String? message;
  final int? currentPage;
  final int? lastPage;
  final int? total;

  InvoiceResponse({
    required this.data,
    required this.status,
    this.message,
    this.currentPage,
    this.lastPage,
    this.total,
  });

  factory InvoiceResponse.fromJson(Map<String, dynamic> json) {
    return InvoiceResponse(
      data: (json['data'] as List?)?.map((e) => Invoice.fromJson(e)).toList() ??
          [],
      status: json['status'] ?? 200,
      message: json['message'],
      currentPage: json['meta']?['current_page'],
      lastPage: json['meta']?['last_page'],
      total: json['meta']?['total'],
    );
  }
}
