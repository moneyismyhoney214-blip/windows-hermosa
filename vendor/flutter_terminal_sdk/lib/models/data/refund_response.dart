import 'intent_details.dart';
import 'transaction_response.dart';

class RefundResponse {
  final IntentDetails details;
  final String? status;

  const RefundResponse({
    required this.details,
    this.status,
  });

  TransactionResponse? getLastTransaction() {
    if (details.transactions.isNotEmpty) {
      return details.transactions.last;
    }
    return null;
  }

  Receipt? getLastReceipt() {
    final lastTransaction = getLastTransaction();
    return lastTransaction?.events?[0].receipt;
  }

  /// JSON factory (deserialization)
  factory RefundResponse.fromJson(Map<String, dynamic> json) {
    return RefundResponse(
      details: IntentDetails.fromJson(json['details']),
      status: json['status'] as String?,
    );
  }

  @override
  String toString() {
    return 'RefundResponse(details: $details, status: $status)';
  }
}
