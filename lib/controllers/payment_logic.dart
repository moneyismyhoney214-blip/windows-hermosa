import '../services/receipt_builder_service.dart';

/// Pure-function helpers extracted out of `main_screen.payment.dart`.
///
/// Everything here is stateless and testable. Stateful concerns
/// (snackbars, navigation, mutating `_cart`, talking to print services)
/// stay in the screen extension — only the pure transforms migrate.
class PaymentLogic {
  PaymentLogic._();

  /// Normalize a free-form pay-method string into the canonical token
  /// used everywhere else (`cash`, `card`, `mada`, `visa`, etc.).
  /// Thin delegate to [ReceiptBuilderService] so call-sites in screens
  /// don't have to import the receipt module directly.
  static String normalizePayMethod(String? method) =>
      ReceiptBuilderService.normalizePayMethod(method);

  /// Robust amount-extractor that accepts `num`, `String`, or `null`.
  /// Returns 0 for anything it can't make sense of (NaN, currency
  /// suffixes, RTL marks, etc.). Pulled out so [isCashOnlyPayment] and
  /// [sumPayments] share the same parsing rules instead of drifting.
  static double _amountOf(Map<String, dynamic> pay) {
    final raw = pay['amount'];
    if (raw == null) return 0.0;
    if (raw is num) return raw.toDouble();
    // Strip non-numeric noise: currency suffixes ("12.50 ر.س"), commas,
    // RTL marks. Anything left that parses gets through; 'NaN' returns
    // null from `double.tryParse` so we land on 0.
    final cleaned =
        raw.toString().replaceAll(RegExp(r'[^\d.\-]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  /// `true` when every positive-amount payment in [pays] is cash.
  /// Returns `false` when [pays] is empty or all amounts are <= 0 —
  /// callers should treat that as "no-op" not "cash-only".
  ///
  /// Pure. No dependency on screen state.
  static bool isCashOnlyPayment(List<Map<String, dynamic>> pays) {
    if (pays.isEmpty) return false;
    var hasPositiveAmount = false;
    for (final pay in pays) {
      final amount = _amountOf(pay);
      if (amount <= 0) continue;
      hasPositiveAmount = true;
      final normalized = normalizePayMethod(pay['pay_method']?.toString());
      if (normalized != 'cash') return false;
    }
    return hasPositiveAmount;
  }

  /// Sum the positive amounts in [pays]. Useful for tender-vs-total
  /// reconciliation outside the screen layer.
  static double sumPayments(List<Map<String, dynamic>> pays) {
    var total = 0.0;
    for (final pay in pays) {
      final amount = _amountOf(pay);
      if (amount > 0) total += amount;
    }
    return total;
  }

  /// Apply the order-level discount + promo to [grossOrderTotal] and
  /// return the net total. Promo and manual discounts compose
  /// additively up to the gross (the result is clamped to >= 0).
  ///
  ///   net = max(0, gross - manualDiscount - promoDiscount)
  ///
  /// Set [isOrderFree] to true to force the result to 0 (used for
  /// free-of-charge promotional orders).
  static double applyOrderDiscounts({
    required double grossOrderTotal,
    required double manualDiscount,
    required double promoDiscount,
    required bool isOrderFree,
  }) {
    if (isOrderFree) return 0.0;
    final net = grossOrderTotal - manualDiscount - promoDiscount;
    return net < 0 ? 0.0 : net;
  }
}
