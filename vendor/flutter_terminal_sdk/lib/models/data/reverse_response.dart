// reverse_response.dart

import 'package:flutter_terminal_sdk/models/data/transaction_response.dart';

class ReverseResponse {
  final ReverseDetails details;
  final String? status;

  const ReverseResponse({
    required this.details,
    this.status,
  });

  TransactionResponse? getLastTransaction() {
    if (details.transactions?.isNotEmpty == true) {
      return details.transactions?.last;
    }
    return null;
  }

  Receipt? getLastReceipt() {
    final lastTransaction = getLastTransaction();
    return lastTransaction?.events?[0].receipt;
  }

  /// JSON factory (deserialization)
  factory ReverseResponse.fromJson(Map<String, dynamic> json) {
    return ReverseResponse(
      details: ReverseDetails.fromJson(json['details']),
      status: json['status'] as String?,
    );
  }

  @override
  String toString() {
    return 'ReverseResponse(details: $details, status: $status)';
  }
}

class ReverseDetails {
  final String? intentId;
  final String? referenceId;
  final String? type;
  final String? status;
  final String? amount;
  final bool? pinRequired;
  final String? createdAt;
  final String? completedAt;
  final String? receiptsUrl;
  final List<TransactionResponse>? transactions;

  const ReverseDetails({
    required this.intentId,
    this.referenceId,
    required this.type,
    this.status,
    this.amount,
    this.pinRequired = false,
    this.createdAt,
    this.completedAt,
    this.receiptsUrl,
    required this.transactions,
  });

  /// Flexible factory: supports both camelCase and snake_case.
  factory ReverseDetails.fromJson(Map<String, dynamic> json) {
    return ReverseDetails(
        intentId: json['intentId'],
        referenceId: json['referenceId'],
        type: json['type'],
        status: json['status'],
        amount: json['amount'],
        pinRequired: json['pinRequired'] ?? false,
        createdAt: json['createdAt'],
        completedAt: json['completedAt'],
        receiptsUrl: json['receiptsUrl'],
        transactions: (json['transactions'] as List<dynamic>? ?? const [])
            .map((e) => TransactionResponse.fromJson(e))
            .toList(growable: false));
  }

  @override
  String toString() =>
      'ReverseDetails(intentId: $intentId, referenceId: $referenceId, type: $type, '
      'status: $status, amount: $amount, pinRequired: $pinRequired, '
      'createdAt: $createdAt, completedAt: $completedAt, '
      'receiptsUrl: $receiptsUrl, transactions: ${transactions?.length})';
}
