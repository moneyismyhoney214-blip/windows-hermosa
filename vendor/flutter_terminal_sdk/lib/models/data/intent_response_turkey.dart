// intent_response_turkey.dart
import 'dto/transaction_response_turkey.dart';

class IntentResponseTurkey {
  final IntentDetailsTurkey details;
  final String? status;

  const IntentResponseTurkey({
    required this.details,
    this.status,
  });

  TransactionResponseTurkey? getLastTransaction() {
    if (details.transactions.isNotEmpty) {
      return details.transactions.last;
    }
    return null;
  }

  ReceiptDataTurkey? getLastReceipt() {
    final lastTransaction = getLastTransaction();
    return lastTransaction?.getBKMReceipt();
  }

  /// JSON factory (deserialization)
  factory IntentResponseTurkey.fromJson(Map<String, dynamic> json) {
    return IntentResponseTurkey(
      details: IntentDetailsTurkey.fromJson(json['details']),
      status: json['status'] as String?,
    );
  }

  @override
  String toString() {
    return 'IntentResponseTurkey(details: $details, status: $status)';
  }
}

class IntentDetailsTurkey {
  final String intentId;
  final String? referenceId;
  final String type;
  final String? status;
  final String? amount;
  final bool pinRequired;
  final String? createdAt;
  final String? completedAt;
  final String? receiptsUrl;
  final List<TransactionResponseTurkey> transactions;

  const IntentDetailsTurkey({
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

  TransactionResponseTurkey? getLastTransaction() {
    if (transactions.isNotEmpty) {
      return transactions.last;
    }
    return null;
  }

  Receipt? getLastReceipt() {
    final lastTransaction = getLastTransaction();
    if (lastTransaction != null &&
        lastTransaction.events != null &&
        lastTransaction.events!.isNotEmpty) {
      return lastTransaction.events![0].receipt;
    }
    return null;
  }

  /// JSON factory (deserialization)
  factory IntentDetailsTurkey.fromJson(dynamic json) {
    return IntentDetailsTurkey(
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
          .map((e) => TransactionResponseTurkey.fromJson(e))
          .toList(growable: false),
    );
  }

  @override
  String toString() {
    return 'IntentDetailsTurkey(intentId: $intentId, referenceId: $referenceId, '
        'type: $type, status: $status, amount: $amount, pinRequired: $pinRequired, '
        'createdAt: $createdAt, completedAt: $completedAt, receiptsUrl: $receiptsUrl, '
        'transactions: ${transactions.length})';
  }
}
