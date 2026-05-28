// Extracted from nearpay_service.dart as part of the R7 god-file split.
// Public class — consumers (`remote_nearpay_dispatcher`, `waiter_billing_service`,
// `main_screen.payment.dart`) already import it via `nearpay_service.dart`,
// which now re-exports this file so no consumer needs to change its import.

class NearPayPaymentResult {
  final bool success;
  final String referenceId;
  final String? transactionId;
  final double? amount;
  final String? errorMessage;

  const NearPayPaymentResult._({
    required this.success,
    required this.referenceId,
    this.transactionId,
    this.amount,
    this.errorMessage,
  });

  factory NearPayPaymentResult.success({
    required String referenceId,
    required String transactionId,
    required double amount,
  }) {
    return NearPayPaymentResult._(
      success: true,
      referenceId: referenceId,
      transactionId: transactionId,
      amount: amount,
    );
  }

  factory NearPayPaymentResult.failure({
    required String referenceId,
    required String message,
  }) {
    return NearPayPaymentResult._(
      success: false,
      referenceId: referenceId,
      errorMessage: message,
    );
  }
}
