// نموذج الإكسترا
class ProductExtra {
  final String id;
  final String name;
  final String nameEn;
  final double price;

  const ProductExtra({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.price,
  });
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

  const Product({
    required this.id,
    required this.name,
    required this.nameEn,
    required this.basePrice,
    required this.category,
    required this.imageUrl,
    this.availableExtras = const [],
    this.isAvailable = true,
  });
}

enum DiscountType { amount, percentage }

// نموذج عنصر السلة
class CartItem {
  final String cartId;
  final Product product;
  int quantity;
  final List<ProductExtra> selectedExtras;
  bool isBumped;

  // ✅ خصائص الخصم
  final double discount;
  final DiscountType discountType;
  final bool isFree;
  final double? originalUnitPrice;
  final double? originalTotal;
  final double? finalTotal; // السعر النهائي بعد الخصم

  CartItem({
    required this.cartId,
    required this.product,
    this.quantity = 1,
    this.selectedExtras = const [],
    this.isBumped = false,
    this.discount = 0.0,
    this.discountType = DiscountType.amount,
    this.isFree = false,
    this.originalUnitPrice,
    this.originalTotal,
    this.finalTotal,
  });

  double get totalPrice {
    if (isFree) return 0.0;

    double extrasTotal = selectedExtras.fold(
      0.0,
      (sum, extra) => sum + extra.price,
    );
    double baseTotal = (product.basePrice + extrasTotal) * quantity;

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

    double extrasTotal = selectedExtras.fold(
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

