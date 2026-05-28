// نموذج الإكسترا
class ProductExtra {
  final String id;
  final String name;
  final String nameEn;
  final double price;
  final Map<String, String> localizedNames;

  const ProductExtra({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.price,
    this.localizedNames = const <String, String>{},
  });

  /// Resolve the addon name for [langCode] with a graceful fallback through
  /// the stored translations, the Arabic/English shorthand fields, and the
  /// raw `name` as a last resort.
  String nameFor(String langCode) {
    final code = langCode.trim().toLowerCase();
    final direct = localizedNames[code]?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    if (code == 'ar' && name.isNotEmpty) return name;
    if (code == 'en' && nameEn.isNotEmpty) return nameEn;
    final en = localizedNames['en']?.trim();
    if (en != null && en.isNotEmpty) return en;
    final ar = localizedNames['ar']?.trim();
    if (ar != null && ar.isNotEmpty) return ar;
    if (name.isNotEmpty) return name;
    return nameEn;
  }
}

// نموذج المنتج
class Product {
  final String id;
  final String name;
  final String nameEn;
  final double basePrice;
  final String category;
  final String imageUrl;
  final List<ProductExtra> availableExtras;
  final bool isAvailable;
  final Map<String, String> localizedNames;

  const Product({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.basePrice,
    required this.category,
    required this.imageUrl,
    this.availableExtras = const [],
    this.isAvailable = true,
    this.localizedNames = const <String, String>{},
  });

  /// Resolve the meal name for [langCode] with a graceful fallback through
  /// the stored translations, the Arabic/English shorthand fields, and the
  /// raw `name` as a last resort.
  String nameFor(String langCode) {
    final code = langCode.trim().toLowerCase();
    final direct = localizedNames[code]?.trim();
    if (direct != null && direct.isNotEmpty) return direct;
    if (code == 'ar' && name.isNotEmpty) return name;
    if (code == 'en' && nameEn.isNotEmpty) return nameEn;
    final en = localizedNames['en']?.trim();
    if (en != null && en.isNotEmpty) return en;
    final ar = localizedNames['ar']?.trim();
    if (ar != null && ar.isNotEmpty) return ar;
    if (name.isNotEmpty) return name;
    return nameEn;
  }
}

enum DiscountType { amount, percentage }

// نموذج عنصر السلة
class CartItem {
  final String cartId;
  final Product product;
  double quantity;
  final List<ProductExtra> selectedExtras;
  bool isBumped;

  // ✅ خصائص الخصم
  final double discount;
  final DiscountType discountType;
  final bool isFree;
  final double? originalUnitPrice;
  final double? originalTotal;
  final double? finalTotal; // السعر النهائي بعد الخصم

  /// Per-item note stamped by the cashier (mirrors what the printed
  /// receipt shows under each line). Rendered on the embedded CDS so the
  /// customer sees the same instructions the kitchen does.
  final String notes;

  CartItem({
    required this.cartId,
    required this.product,
    this.quantity = 1.0,
    this.selectedExtras = const [],
    this.isBumped = false,
    this.discount = 0.0,
    this.discountType = DiscountType.amount,
    this.isFree = false,
    this.originalUnitPrice,
    this.originalTotal,
    this.finalTotal,
    this.notes = '',
  });

  double get totalPrice {
    if (isFree) return 0.0;

    final double extrasTotal = selectedExtras.fold(
      0.0,
      (sum, extra) => sum + extra.price,
    );
    final double baseTotal = (product.basePrice + extrasTotal) * quantity;

    // Apply discount with strict clamping to avoid negative totals.
    if (discount > 0) {
      if (discountType == DiscountType.percentage) {
        final safePercent = discount.clamp(0.0, 100.0).toDouble();
        final discountAmount = baseTotal * (safePercent / 100.0);
        return (baseTotal - discountAmount).clamp(0.0, baseTotal).toDouble();
      }
      final safeAmount = discount.clamp(0.0, baseTotal).toDouble();
      return (baseTotal - safeAmount).clamp(0.0, baseTotal).toDouble();
    }

    return baseTotal;
  }

  // السعر الأصلي قبل الخصم
  double get originalPrice {
    if (originalTotal != null) return originalTotal!;

    final double extrasTotal = selectedExtras.fold(
      0.0,
      (sum, extra) => sum + extra.price,
    );
    return (product.basePrice + extrasTotal) * quantity;
  }

  // هل يوجد خصم؟
  bool get hasDiscount => discount > 0 || isFree;

  // قيمة الخصم المحسوبة
  double get discountValue {
    if (isFree) return originalPrice;
    if (discount <= 0) return 0.0;

    if (discountType == DiscountType.percentage) {
      final safePercent = discount.clamp(0.0, 100.0).toDouble();
      return originalPrice * (safePercent / 100.0);
    } else {
      return discount.clamp(0.0, originalPrice).toDouble();
    }
  }

  String get displayName => product.name;
  String get displayNameEn => product.nameEn;

  /// Resolve the meal name for [langCode] using the product's translations.
  String displayNameFor(String langCode) => product.nameFor(langCode);
}

// حالات الطلب
enum OrderStatus { pending, preparing, ready, served, completed, cancelled }

// نموذج الطلب
class Order {
  final String id;
  final String orderNumber;
  final OrderStatus status;
  final List<CartItem> items;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? note;
  final double subtotal;
  final double tax;
  final double total;
  final String orderType; // dine_in, take_away, delivery, car, table

  Order({
    required this.id,
    required this.orderNumber,
    this.status = OrderStatus.pending,
    required this.items,
    required this.createdAt,
    this.completedAt,
    this.note,
    required this.subtotal,
    required this.tax,
    required this.total,
    this.orderType = 'dine_in',
  });
}

