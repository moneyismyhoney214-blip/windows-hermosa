class ReconciliationReceiptsResponse {
  ReconciliationReceipt? receipt;
  String? reconciliationId;

  ReconciliationReceiptsResponse({
    this.receipt,
    this.reconciliationId,
  });

  factory ReconciliationReceiptsResponse.fromJson(Map<String, dynamic> json) {
    return ReconciliationReceiptsResponse(
      receipt: json['receipt'] != null
          ? ReconciliationReceipt.fromJson(json['receipt'])
          : null,
      reconciliationId: json['reconciliation_id'],
    );
  }
}

class ReconciliationReceipt {
  final String id;
  final String standard;
  final String operationType;
  final dynamic data; // Using dynamic for JsonElement equivalent
  final Reconciliation reconciliation;
  final String createdAt;
  final String updatedAt;

  ReconciliationReceipt({
    required this.id,
    required this.standard,
    required this.operationType,
    this.data,
    required this.reconciliation,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReconciliationReceipt.fromJson(Map<String, dynamic> json) {
    return ReconciliationReceipt(
      id: json['id'],
      standard: json['standard'],
      operationType: json['operationType'],
      data: json['data'],
      // This can be any JSON object
      reconciliation: Reconciliation.fromJson(json['reconciliation']),
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'standard': standard,
      'operationType': operationType,
      'data': data, // Can be any dynamic JSON structure
      'reconciliation': reconciliation.toJson(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

class Reconciliation {
  String? id;

  Reconciliation({this.id});

  factory Reconciliation.fromJson(Map<String, dynamic> json) {
    return Reconciliation(
      id: json['id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
    };
  }
}
