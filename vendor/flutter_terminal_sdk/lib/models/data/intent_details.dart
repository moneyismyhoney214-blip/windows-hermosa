// intent_details.dart
import 'transaction_response.dart';

class IntentDetails {
  final String intentId;
  final String? referenceId;
  final String type;
  final String? status;
  final String? amount;
  final bool pinRequired;
  final String? createdAt;
  final String? completedAt;
  final String? receiptsUrl;
  final List<TransactionResponse> transactions;

  const IntentDetails({
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

  /// JSON factory (deserialization)
  factory IntentDetails.fromJson(dynamic json) {
    return IntentDetails(
      intentId: json['intentId'] as String,
      referenceId: json['referenceId'] as String?,
      type: json['type'] as String,
      status: json['status'] as String?,
      amount: json['amount'] as String?,
      pinRequired: (json['pinRequired'] as bool?) ?? false,
      createdAt: json['createdAt'] as String?,
      completedAt: json['completedAt'] as String?,
      receiptsUrl: json['receiptsUrl'] as String?,
      transactions: (json['transactions'] as List<dynamic>? ?? const [])
          .map((e) => TransactionResponse.fromJson(e))
          .toList(growable: false),
    );
  }

  @override
  String toString() =>
      'IntentDetails(intentId: $intentId, referenceId: $referenceId, type: $type, '
      'status: $status, amount: $amount, pinRequired: $pinRequired, createdAt: $createdAt, '
      'completedAt: $completedAt, receiptsUrl: $receiptsUrl, transactions: ${transactions.length})';
}
