import '../services/receipt_builder_service.dart';

/// Pure totals calculator used by the cashier + waiter flows.
///
/// Holds the per-branch tax configuration (`isTaxEnabled`, `taxRate`) and
/// answers questions about how to split a number into its subtotal/tax
/// components, or compose a grand total from gross + discounts.
///
/// Stateless from the outside — every call is referentially transparent
/// for a given instance. Construct one per branch session and reuse it
/// from the screen extension instead of letting that extension carry
/// the math.
class OrderTotalsCalculator {
  /// Whether the active branch charges tax on outgoing invoices.
  final bool isTaxEnabled;

  /// Tax rate as a fraction in `[0, 1]`. The screen stores it as a
  /// percentage and divides by 100 before instantiating — the calculator
  /// itself does not assume an upper bound except non-negative.
  final double taxRate;

  const OrderTotalsCalculator({
    required this.isTaxEnabled,
    required this.taxRate,
  });

  /// Convenience constructor for the "no tax" case.
  const OrderTotalsCalculator.noTax()
      : isTaxEnabled = false,
        taxRate = 0.0;

  /// Returns the VAT amount that should be added to a tax-exclusive
  /// [subtotal]. Returns 0 when tax is off, the rate is non-positive,
  /// or the subtotal is non-positive.
  double taxAmountFromSubtotal(double subtotal) {
    if (!isTaxEnabled || taxRate <= 0 || subtotal <= 0) return 0.0;
    return subtotal * taxRate;
  }

  /// Given a tax-inclusive [total], return the pre-tax subtotal. Thin
  /// delegate to [ReceiptBuilderService] so receipt + cashier layers
  /// share the same rounding behavior. When tax is off this is the
  /// identity.
  double subtotalFromTaxInclusiveTotal(double total) =>
      ReceiptBuilderService.subtotalFromTaxInclusiveTotal(
        total,
        isTaxEnabled: isTaxEnabled,
        taxRate: taxRate,
      );

  /// Given a tax-inclusive [total], return the VAT portion. Thin
  /// delegate to [ReceiptBuilderService]. Returns 0 when tax is off.
  double taxFromTaxInclusiveTotal(double total) =>
      ReceiptBuilderService.taxFromTaxInclusiveTotal(
        total,
        isTaxEnabled: isTaxEnabled,
        taxRate: taxRate,
      );

  /// Compose a tax-inclusive grand total from a [gross] amount and
  /// optional [manualDiscount] / [promoDiscount] reductions. When
  /// [isOrderFree] the result is 0 regardless of inputs.
  ///
  ///   net = max(0, gross - manualDiscount - promoDiscount)
  ///   tax = isTaxEnabled ? net * taxRate : 0
  ///   grand = net + tax
  ///
  /// Returns a [GrandTotal] so callers can read both the net and tax
  /// without re-computing.
  GrandTotal composeGrandTotal({
    required double gross,
    double manualDiscount = 0.0,
    double promoDiscount = 0.0,
    bool isOrderFree = false,
  }) {
    if (isOrderFree) {
      return const GrandTotal(net: 0, tax: 0, grand: 0);
    }
    var net = gross - manualDiscount - promoDiscount;
    if (net < 0) net = 0;
    final tax = taxAmountFromSubtotal(net);
    return GrandTotal(net: net, tax: tax, grand: net + tax);
  }
}

/// Result bundle for [OrderTotalsCalculator.composeGrandTotal].
///
/// Immutable. Equality compares all three fields so the result can be
/// used safely as a key (e.g. as a fingerprint in receipt caches).
class GrandTotal {
  final double net;
  final double tax;
  final double grand;

  const GrandTotal({
    required this.net,
    required this.tax,
    required this.grand,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GrandTotal &&
          other.net == net &&
          other.tax == tax &&
          other.grand == grand);

  @override
  int get hashCode => Object.hash(net, tax, grand);

  @override
  String toString() =>
      'GrandTotal(net: $net, tax: $tax, grand: $grand)';
}
