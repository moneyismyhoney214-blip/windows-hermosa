class ReceiptAddon {
  final String nameAr;
  final String nameEn;
  final double price;

  /// Per-language translations for the addon option name, keyed by ISO code
  /// (`ar`, `en`, `hi`, `ur`, `tr`, `es`). Populated when the source payload
  /// carries an `addons_translations` entry or the cart's Extra had
  /// `optionTranslations`. Empty means the renderer should fall back to
  /// `nameAr` / `nameEn`.
  final Map<String, String> localizedNames;

  ReceiptAddon({
    required this.nameAr,
    required this.nameEn,
    required this.price,
    this.localizedNames = const {},
  });

  /// Language-aware name lookup for the invoice renderer. Falls back through
  /// `localizedNames[code]` → English → Arabic → `nameAr` / `nameEn` so the
  /// caller always gets a non-empty string.
  String nameFor(String code) {
    final normalized = code.trim().toLowerCase();
    final direct = localizedNames[normalized];
    if (direct != null && direct.isNotEmpty) return direct;
    if (normalized == 'en' && nameEn.isNotEmpty) return nameEn;
    if (normalized == 'ar' && nameAr.isNotEmpty) return nameAr;
    final en = localizedNames['en'];
    if (en != null && en.isNotEmpty) return en;
    if (nameEn.isNotEmpty) return nameEn;
    final ar = localizedNames['ar'];
    if (ar != null && ar.isNotEmpty) return ar;
    return nameAr;
  }

  factory ReceiptAddon.fromMap(Map<String, dynamic> map) {
    double parseNum(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    final rawLocalized = map['localizedNames'] ?? map['translations'];
    final localized = <String, String>{};
    if (rawLocalized is Map) {
      for (final entry in rawLocalized.entries) {
        final value = entry.value?.toString().trim() ?? '';
        if (value.isEmpty) continue;
        localized[entry.key.toString().trim().toLowerCase()] = value;
      }
    }

    return ReceiptAddon(
      nameAr: map['nameAr'] ?? map['name_ar'] ?? '',
      nameEn: map['nameEn'] ?? map['name_en'] ?? '',
      price: parseNum(map['price']),
      localizedNames: localized,
    );
  }
}

class ReceiptPayment {
  final String methodLabel;
  final double amount;

  ReceiptPayment({
    required this.methodLabel,
    required this.amount,
  });

  factory ReceiptPayment.fromMap(Map<String, dynamic> map) {
    double parseNum(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }
    return ReceiptPayment(
      methodLabel: map['methodLabel'] ?? '',
      amount: parseNum(map['amount']),
    );
  }
}

class ReceiptItem {
  final String nameAr;
  final String nameEn;
  final double quantity;
  final double unitPrice;
  final double total;
  final List<ReceiptAddon>? addons;
  // خصم
  final double? discountAmount;
  final double? discountPercentage;
  final String? discountName;
  final double? originalPrice;

  ReceiptItem({
    required this.nameAr,
    required this.nameEn,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.addons,
    this.discountAmount,
    this.discountPercentage,
    this.discountName,
    this.originalPrice,
  });

  factory ReceiptItem.fromMap(Map<String, dynamic> map) {
    double parseNum(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return ReceiptItem(
      nameAr: map['nameAr'] ?? '',
      nameEn: map['nameEn'] ?? '',
      quantity: parseNum(map['quantity']),
      unitPrice: parseNum(map['unitPrice']),
      total: parseNum(map['total']),
      addons: (map['addons'] as List? ?? [])
          .map((e) => ReceiptAddon.fromMap(e))
          .toList(),
      discountAmount: parseNum(map['discountAmount']) > 0
          ? parseNum(map['discountAmount'])
          : null,
      discountPercentage: parseNum(map['discountPercentage']) > 0
          ? parseNum(map['discountPercentage'])
          : null,
      discountName: map['discountName']?.toString(),
      originalPrice: parseNum(map['originalPrice']) > 0
          ? parseNum(map['originalPrice'])
          : null,
    );
  }

  bool get hasDiscount => discountAmount != null && discountAmount! > 0;
}

class OrderReceiptData {
  final String invoiceNumber;
  final String issueDateTime;
  final String sellerNameAr;
  final String sellerNameEn;
  final String vatNumber;
  final String branchName;
  final String carNumber;
  final List<ReceiptItem> items;
  final double totalExclVat;
  final double vatAmount;
  final double totalInclVat;
  final String paymentMethod;
  final List<ReceiptPayment> payments;
  final String qrCodeBase64;

  // حقول إضافية للفاتورة الكاملة
  final String? sellerLogo;
  final String? zatcaQrImage;
  final String? branchAddress;
  final String? branchAddressEn;
  final String? branchMobile;
  final String? issueDate;
  final String? issueTime;
  final String? commercialRegisterNumber;
  final String? cashierName;
  // خصم على مستوى الطلب
  final double? orderDiscountAmount;
  final double? orderDiscountPercentage;
  final String? orderDiscountName;
  // نوع الطلب
  final String? orderType;
  // رقم الطلب
  final String? orderNumber;
  final String? clientName;
  final String? clientPhone;
  final String? tableNumber;

  OrderReceiptData({
    required this.invoiceNumber,
    required this.issueDateTime,
    required this.sellerNameAr,
    required this.sellerNameEn,
    required this.vatNumber,
    required this.branchName,
    this.carNumber = '',
    required this.items,
    required this.totalExclVat,
    required this.vatAmount,
    required this.totalInclVat,
    required this.paymentMethod,
    this.payments = const [],
    required this.qrCodeBase64,
    this.sellerLogo,
    this.zatcaQrImage,
    this.branchAddress,
    this.branchAddressEn,
    this.branchMobile,
    this.issueDate,
    this.issueTime,
    this.commercialRegisterNumber,
    this.cashierName,
    this.orderDiscountAmount,
    this.orderDiscountPercentage,
    this.orderDiscountName,
    this.orderType,
    this.orderNumber,
    this.clientName,
    this.clientPhone,
    this.tableNumber,
  });

  factory OrderReceiptData.fromMap(Map<String, dynamic> map) {
    double parseNum(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    // استخراج التاريخ والوقت من issueDateTime
    String? extractDate(String? dateTime) {
      if (dateTime == null || dateTime.isEmpty) return null;
      try {
        final parts = dateTime.split(' ');
        return parts.isNotEmpty ? parts[0] : null;
      } catch (e) {
        return null;
      }
    }

    String? extractTime(String? dateTime) {
      if (dateTime == null || dateTime.isEmpty) return null;
      try {
        final parts = dateTime.split(' ');
        return parts.length > 1 ? parts[1] : null;
      } catch (e) {
        return null;
      }
    }

    final issueDateTime = map['issueDateTime'] ?? '';

    return OrderReceiptData(
      invoiceNumber: map['invoiceNumber'] ?? '',
      issueDateTime: issueDateTime,
      sellerNameAr: map['sellerNameAr'] ?? '',
      sellerNameEn: map['sellerNameEn'] ?? '',
      vatNumber: map['vatNumber'] ?? '',
      branchName: map['branchName'] ?? '',
      carNumber: map['carNumber'] ?? '',
      items: (map['items'] as List? ?? [])
          .map((e) => ReceiptItem.fromMap(e))
          .toList(),
      totalExclVat: parseNum(map['totalExclVat']),
      vatAmount: parseNum(map['vatAmount']),
      totalInclVat: parseNum(map['totalInclVat']),
      paymentMethod: map['paymentMethod'] ?? '',
      payments: (map['payments'] as List? ?? [])
          .map((e) => ReceiptPayment.fromMap(e))
          .toList(),
      qrCodeBase64: map['qrCodeBase64'] ?? '',
      sellerLogo: map['sellerLogo'],
      zatcaQrImage: map['zatcaQrImage'],
      branchAddress: map['branchAddress'],
      branchMobile: map['branchMobile'],
      issueDate: map['issueDate'] ?? extractDate(issueDateTime),
      issueTime: map['issueTime'] ?? extractTime(issueDateTime),
      commercialRegisterNumber: map['commercialRegisterNumber'],
      cashierName: map['cashierName'],
      orderDiscountAmount: parseNum(map['orderDiscountAmount']) > 0
          ? parseNum(map['orderDiscountAmount'])
          : null,
      orderDiscountPercentage: parseNum(map['orderDiscountPercentage']) > 0
          ? parseNum(map['orderDiscountPercentage'])
          : null,
      orderDiscountName: map['orderDiscountName']?.toString(),
      orderType: map['orderType']?.toString(),
      orderNumber: map['orderNumber']?.toString(),
      clientName: map['clientName']?.toString(),
      clientPhone: map['clientPhone']?.toString(),
      tableNumber: map['tableNumber']?.toString(),
    );
  }

  bool get hasOrderDiscount =>
      orderDiscountAmount != null && orderDiscountAmount! > 0;
}
