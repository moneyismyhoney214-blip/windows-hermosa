import 'package:flutter_terminal_sdk/models/data/transaction_response.dart';

import 'intent_details.dart';

class IncrementResponse {
  final IntentDetails? details;
  final String? status;

  const IncrementResponse({
    required this.details,
    required this.status,
  });

  /// JSON factory (deserialization)
  factory IncrementResponse.fromJson(dynamic json) {
    return IncrementResponse(
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
  String toString() => 'IncrementResponse(details: $details, status: $status)';
}
