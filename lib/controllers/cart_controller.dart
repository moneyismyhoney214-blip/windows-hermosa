import 'package:flutter/foundation.dart';

import '../models.dart';
import 'order_totals_calculator.dart';

/// Owns the cashier's working cart — line items, the order-level discount,
/// the active promo, the "order is free" flag — and notifies listeners on
/// every mutation. Replaces the ad-hoc `setState`-driven cart that used to
/// live inside `_MainScreenState`, so cart logic becomes:
///
///   1. Independently testable (no widget tree required).
///   2. Centralised — mutations can't slip past notifications.
///   3. Reusable — waiter & customer-display can subscribe to the same
///      controller without forking logic.
///
/// The controller deliberately does NOT do I/O. Anything that has to talk
/// to the backend (promo lookup, deposit consumption, table reservation)
/// stays in the screen-level handlers; they call back into the controller
/// once they've resolved an external value.
class CartController extends ChangeNotifier {
  CartController({OrderTotalsCalculator? totals})
      : _totals = totals ?? const OrderTotalsCalculator.noTax();

  final OrderTotalsCalculator _totals;

  final List<CartItem> _items = [];
  double _orderDiscount = 0.0;
  DiscountType _orderDiscountType = DiscountType.amount;
  PromoCode? _activePromoCode;
  bool _isOrderFree = false;

  // ---- Reads -----------------------------------------------------------

  /// Live view of the cart. Returned list is unmodifiable so callers can't
  /// silently mutate items without going through the controller (which
  /// would skip the notify hook).
  List<CartItem> get items => List.unmodifiable(_items);

  /// Direct, mutable handle to the backing list. **Only for the in-progress
  /// migration from `_MainScreenState`** — call sites that mutate this list
  /// must call [notifyMutation] afterwards so listeners (display, waiter
  /// subscribers) see the change. New code should use the typed mutators
  /// ([addItem], [removeItem], [updateQuantity]) instead.
  List<CartItem> get mutableItems => _items;

  /// Manual notify hook used by the migration period. Calls
  /// [notifyListeners] without going through one of the typed mutators
  /// — needed for callers that still touch [mutableItems] directly.
  void notifyMutation() => notifyListeners();

  /// Direct count of distinct line items. Cheaper than `items.length`
  /// because it skips the list copy.
  int get lineCount => _items.length;

  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  double get orderDiscount => _orderDiscount;
  DiscountType get orderDiscountType => _orderDiscountType;
  PromoCode? get activePromoCode => _activePromoCode;
  bool get isOrderFree => _isOrderFree;

  /// Sum of `totalPrice` across all line items (after per-item discounts
  /// but before order-level discount, promo, or tax). When the order is
  /// free the gross is zero by definition.
  double get gross {
    if (_isOrderFree) return 0.0;
    var total = 0.0;
    for (final item in _items) {
      total += item.totalPrice;
    }
    return total;
  }

  /// Effective order-level discount in currency units, clamped to gross.
  /// Percentage discounts are converted, amount discounts stay as-is.
  double effectiveOrderDiscount() {
    if (_isOrderFree) return gross;
    final g = gross;
    if (g <= 0) return 0.0;
    final raw = _orderDiscountType == DiscountType.percentage
        ? g * (_orderDiscount.clamp(0.0, 100.0) / 100.0)
        : _orderDiscount;
    return raw.clamp(0.0, g);
  }

  /// Net total after the order-level discount (still before tax).
  double get net {
    final n = gross - effectiveOrderDiscount();
    return n < 0 ? 0.0 : n;
  }

  /// Tax + net + grand total bundle using the configured calculator.
  /// We pass `gross` plus the resolved manual discount so the calculator
  /// can apply tax-inclusive math correctly (it expects the raw gross,
  /// not a pre-netted value).
  GrandTotal get totals => _totals.composeGrandTotal(
        gross: gross,
        manualDiscount: effectiveOrderDiscount(),
        isOrderFree: _isOrderFree,
      );

  // ---- Mutations -------------------------------------------------------

  /// Append a line item. Two items with the same `cartId` are NOT merged
  /// — the cashier is in charge of treating "same product different
  /// extras" as a new line, and the screen has its own dedup rules
  /// (which it applies before calling this method).
  void addItem(CartItem item) {
    _items.add(item);
    notifyListeners();
  }

  /// Adjust the quantity of a line by `delta` (positive or negative).
  /// Quantity is clamped to a minimum of 1 — going to zero is treated
  /// as "the user wants to remove this line" and should be done via
  /// [removeItem] instead. Returns true if the item was found.
  bool updateQuantity(String cartId, double delta) {
    final i = _items.indexWhere((it) => it.cartId == cartId);
    if (i < 0) return false;
    var q = _items[i].quantity + delta;
    if (q <= 0) q = 1;
    _items[i].quantity = q;
    notifyListeners();
    return true;
  }

  /// Overwrite quantity directly. Used by the salon flow which sets
  /// session-count from the dialog. Same min-1 clamp applies.
  bool setQuantity(String cartId, double quantity) {
    final i = _items.indexWhere((it) => it.cartId == cartId);
    if (i < 0) return false;
    _items[i].quantity = quantity <= 0 ? 1 : quantity;
    notifyListeners();
    return true;
  }

  bool removeItem(String cartId) {
    final before = _items.length;
    _items.removeWhere((it) => it.cartId == cartId);
    if (_items.length == before) return false;
    notifyListeners();
    return true;
  }

  /// Set per-line discount (different from the order-level discount).
  /// Clamps via the same rules as [CartItem.totalPrice].
  bool updateLineDiscount(String cartId, double discount, DiscountType type) {
    final i = _items.indexWhere((it) => it.cartId == cartId);
    if (i < 0) return false;
    _items[i].discount = discount < 0 ? 0 : discount;
    _items[i].discountType = type;
    notifyListeners();
    return true;
  }

  /// Toggle a single line's "free" flag.
  bool toggleLineFree(String cartId) {
    final i = _items.indexWhere((it) => it.cartId == cartId);
    if (i < 0) return false;
    _items[i].isFree = !_items[i].isFree;
    notifyListeners();
    return true;
  }

  /// Empty the cart and reset every order-level field. The caller (screen)
  /// owns side-effects like clearing the car-number input or refetching
  /// deposits — the controller deliberately stops at state.
  void clear() {
    _items.clear();
    _orderDiscount = 0.0;
    _orderDiscountType = DiscountType.amount;
    _activePromoCode = null;
    _isOrderFree = false;
    notifyListeners();
  }

  void setOrderDiscount(double value, {DiscountType type = DiscountType.amount}) {
    final clamped = value < 0 ? 0.0 : value;
    if (_orderDiscount == clamped && _orderDiscountType == type) return;
    _orderDiscount = clamped;
    _orderDiscountType = type;
    notifyListeners();
  }

  void setOrderFree(bool value) {
    if (_isOrderFree == value) return;
    _isOrderFree = value;
    notifyListeners();
  }

  void toggleOrderFree() => setOrderFree(!_isOrderFree);

  void applyPromoCode(PromoCode code) {
    _activePromoCode = code;
    notifyListeners();
  }

  void clearPromoCode() {
    if (_activePromoCode == null) return;
    _activePromoCode = null;
    notifyListeners();
  }
}
