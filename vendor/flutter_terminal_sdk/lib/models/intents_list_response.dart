class IntentsListResponse {
  final List<Intent> data;
  final Pagination pagination;

  IntentsListResponse({
    required this.data,
    required this.pagination,
  });

  factory IntentsListResponse.fromJson(Map<String, dynamic> json) {
    return IntentsListResponse(
      data: (json['data'] as List<dynamic>?)
              ?.map((e) => Intent.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      pagination: Pagination.fromJson(
          json['pagination'] as Map<String, dynamic>? ?? {}),
    );
  }
}

/// Note: If the name `Intent` clashes with Flutter's Actions/Shortcuts API
/// in your imports, consider renaming to `TerminalIntent` or prefixing imports.
class Intent {
  final String? customerReferenceNumber;
  final String? terminalId;
  final String? amount;
  final String id;
  final String? originalIntentId; // Kotlin: originalIntentID
  final String? status;
  final String type;
  final String? createdAt;
  final String? completedAt;
  final String? cancelledAt;
  final List<IntentTransaction>? transactions;

  const Intent({
    this.terminalId,
    this.customerReferenceNumber,
    this.amount,
    required this.id,
    this.originalIntentId,
    this.status,
    required this.type,
    this.createdAt,
    this.completedAt,
    this.cancelledAt,
    this.transactions,
  });

  /// Flexible factory:
  /// - Accepts both camelCase and snake_case keys.
  /// - Also tolerates `originalIntentID` (all-caps ID) from some payloads.
  factory Intent.fromJson(Map<String, dynamic> json) {
    String? str(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v == null) continue;
        if (v is String) return v;
      }
      return null;
    }

    String req(List<String> keys, String fieldName) {
      final v = str(keys);
      if (v == null) {
        throw StateError('Missing required field: $fieldName');
      }
      return v;
    }

    return Intent(
      terminalId: str([
        'terminalID',
        'terminal_id',
      ]),
      customerReferenceNumber: str([
        'customerReferenceNumber',
        'customer_reference_number',
      ]),
      amount: str(['amount']),
      id: req(['id'], 'id'),
      originalIntentId: str([
        'originalIntentId',
        'originalIntentID', // tolerate Kotlin-style ID suffix
        'original_intent_id',
      ]),
      status: str(['status']),
      type: req(['type'], 'type'),
      createdAt: str(['createdAt', 'created_at']),
      completedAt: str(['completedAt', 'completed_at']),
      cancelledAt: str(['cancelledAt', 'cancelled_at']),
      transactions:  (json['transactions'] as List<dynamic>?)
              ?.map((e) =>
                  IntentTransaction.fromJson(e as Map<String, dynamic>))
              .toList()

    );
  }

  @override
  String toString() =>
      'Intent(id: $id, type: $type, status: $status, amount: $amount, '
      'customerReferenceNumber: $customerReferenceNumber, '
      'originalIntentId: $originalIntentId, createdAt: $createdAt, '
      'completedAt: $completedAt, cancelledAt: $cancelledAt)';
}

class Currency {
  final String arabic;
  final String english;

  Currency({
    required this.arabic,
    required this.english,
  });

  factory Currency.fromJson(Map<String, dynamic> json) {
    return Currency(
      arabic: json['arabic'] as String? ?? '',
      english: json['english'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'arabic': arabic,
        'english': english,
      };
}

class Performance {
  final String type;
  final num timeStamp; // Ensure it's int

  Performance({
    required this.type,
    required this.timeStamp,
  });

  factory Performance.fromJson(Map<String, dynamic> json) {
    return Performance(
        type: json['type'] as String? ?? '',
        timeStamp: (json['timeStamp'] as num?)?.toInt() ?? 0);
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'timeStamp': timeStamp,
      };
}

class Pagination {
  final int currentPage;
  final int totalPages;
  final int totalData;

  Pagination({
    required this.currentPage,
    required this.totalPages,
    required this.totalData,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      currentPage: (json['current_page'] as num?)?.toInt() ?? 0,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 0,
      totalData: (json['total_data'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'current_page': currentPage,
        'total_pages': totalPages,
        'total_data': totalData,
      };
}

class IntentTransaction {
  final String uuid;
  final String? pan;
  final LanguageContent? scheme;
  final String? amountAuthorized;
  final CurrencyDto? currency;
  final bool? isApproved;
  final bool? isReversed;
  final String? retrievalReferenceNumber;
  final String? customerReferenceNumber;

  IntentTransaction({
    required this.uuid,
    this.pan,
    this.scheme,
    this.amountAuthorized,
    this.currency,
    this.isApproved,
    this.retrievalReferenceNumber,
    this.customerReferenceNumber,
    this.isReversed
  });

  factory IntentTransaction.fromJson(Map<String, dynamic> json) {
    return IntentTransaction(
      uuid: json['uuid'] as String? ?? '',
      pan: json['pan'] as String?,
      scheme: json['scheme'] != null
          ? LanguageContent.fromJson(json['scheme'] as Map<String, dynamic>)
          : null,
      amountAuthorized: json['amountAuthorized'] as String?,
      currency: json['currency'] != null
          ? CurrencyDto.fromJson(json['currency'] as Map<String, dynamic>)
          : null,
      isApproved: json['isApproved'] as bool?,
      isReversed: json['isReversed'] as bool?,
      retrievalReferenceNumber: json['retrievalReferenceNumber'] as String?,
      customerReferenceNumber: json['customerReferenceNumber'] as String?,
    );
  }
}

class CurrencyDto {
  final String? code;
  final int? decimals;
  final String? name;
  final String? number;

  CurrencyDto({
    this.code,
    this.decimals,
    this.name,
    this.number,
  });

  factory CurrencyDto.fromJson(Map<String, dynamic> json) {
    return CurrencyDto(
      code: json['code'] as String?,
      decimals: (json['decimals'] as num?)?.toInt(),
      name: json['name'] as String?,
      number: json['number'] as String?,
    );
  }
}

class LanguageContent {
  final String? arabic;
  final String? english;
  final String? turkish;

  LanguageContent({
    this.arabic,
    this.english,
    this.turkish,
  });

  factory LanguageContent.fromJson(Map<String, dynamic> json) {
    return LanguageContent(
      arabic: json['arabic'] as String?,
      english: json['english'] as String?,
      turkish: json['turkish'] as String?,
    );
  }
}