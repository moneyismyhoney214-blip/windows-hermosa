import 'package:flutter_terminal_sdk/models/data/transaction_response.dart';

import 'intent_details.dart';

class AuthorizeResponse {
  final IntentDetails? details;
  final String? status;

  const AuthorizeResponse({
    required this.details,
    required this.status,
  });

  /// JSON factory (deserialization)
  factory AuthorizeResponse.fromJson(dynamic json) {
    return AuthorizeResponse(
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
      'AuthorizeResponse(details: ${details.toString()}, status: $status)';
}
