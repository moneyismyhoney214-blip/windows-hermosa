import 'package:flutter_terminal_sdk/models/data/transaction_response.dart';

import 'intent_details.dart';

class CaptureResponse {
  final IntentDetails? details;
  final String? status;

  const CaptureResponse({
    required this.details,
    required this.status,
  });

  /// JSON factory (deserialization)
  factory CaptureResponse.fromJson(dynamic json) {
    return CaptureResponse(
      details: IntentDetails.fromJson(json['details']),
      status: json['status'] as String?,
    );
  }

  TransactionResponse? getLastTransaction() {
    return details?.transactions.last;
  }

  Receipt? getLastReceipt() {
    if (details?.transactions.isEmpty ?? true) {
      return null;
    }
    if (details?.transactions.last.events?.isEmpty == true) {
      return null;
    }
    return details?.transactions.last.events?.first.receipt;
  }

  @override
  String toString() => 'CaptureResponse(details: $details, status: $status)';
}
