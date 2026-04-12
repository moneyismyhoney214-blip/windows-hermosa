import 'package:flutter_terminal_sdk/models/data/transaction_response.dart';

import 'intent_details.dart';

class PurchaseResponse {
  final IntentDetails? details;
  final String? status;

  const PurchaseResponse({
    required this.details,
    required this.status,
  });

  /// JSON factory (deserialization)
  factory PurchaseResponse.fromJson(dynamic json) {
    return PurchaseResponse(
      details: IntentDetails.fromJson(json['details']),
      status: json['status'] as String?,
    );
  }

  TransactionResponse? getLastTransaction() {
    return details?.transactions.last;
  }

  Receipt? getLastReceipt() {
    return details?.transactions.last.events?[0].receipt;
  }

  @override
  String toString() => 'PurchaseResponse(details: $details, status: $status)';
}
