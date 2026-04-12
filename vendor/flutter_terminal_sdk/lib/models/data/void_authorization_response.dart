import 'package:flutter_terminal_sdk/models/data/transaction_response.dart';

import 'intent_details.dart';

class VoidAuthorizationResponse {
  final IntentDetails? details;
  final String? status;

  const VoidAuthorizationResponse({
    required this.details,
    required this.status,
  });

  /// JSON factory (deserialization)
  factory VoidAuthorizationResponse.fromJson(dynamic json) {
    return VoidAuthorizationResponse(
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
  String toString() =>
      'VoidAuthorizationResponse(details: $details, status: $status)';
}
