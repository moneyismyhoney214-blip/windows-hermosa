

class AuthorizeReceipt {
  final String id;
  final String? amountOther;
  final CurrencyDto currency;
  final String? createdAt;
  final String? completedAt;
  final bool pinRequired;
  final List<PerformanceDto> performance;
  final CardDto? card;
  final List<AuthEventDto> events;

  AuthorizeReceipt({
    required this.id,
    this.amountOther,
    required this.currency,
    this.createdAt,
    this.completedAt,
    required this.pinRequired,
    required this.performance,
    this.card,
    required this.events,
  });

  factory AuthorizeReceipt.fromJson(Map<String, dynamic> json) {
    return AuthorizeReceipt(
      id: json['id'],
      amountOther: json['amountOther'],
      currency: CurrencyDto.fromJson(json['currency']),
      createdAt: json['createdAt'],
      completedAt: json['completedAt'],
      pinRequired: json['pinRequired'],
      performance: (json['performance'] as List)
          .map((item) => PerformanceDto.fromJson(item))
          .toList(),
      card: json['card'] != null ? CardDto.fromJson(json['card']) : null,
      events: (json['events'] as List)
          .map((item) => AuthEventDto.fromJson(item))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amountOther': amountOther,
      'currency': currency.toJson(),
      'createdAt': createdAt,
      'completedAt': completedAt,
      'pinRequired': pinRequired,
      'performance': performance.map((item) => item.toJson()).toList(),
      'card': card?.toJson(),
      'events': events.map((item) => item.toJson()).toList(),
    };
  }
}

class PerformanceDto {
  final String type;
  final int timeStamp;

  PerformanceDto({
    required this.type,
    required this.timeStamp,
  });

  factory PerformanceDto.fromJson(Map<String, dynamic> json) {
    return PerformanceDto(
      type: json['type'],
      timeStamp: json['timeStamp'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'timeStamp': timeStamp,
    };
  }
}

class CurrencyDto {
  final String arabic;
  final String english;

  CurrencyDto({
    required this.arabic,
    required this.english,
  });

  factory CurrencyDto.fromJson(Map<String, dynamic> json) {
    return CurrencyDto(
      arabic: json['arabic'],
      english: json['english'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'arabic': arabic,
      'english': english,
    };
  }
}

class CardDto {
  final String? brandCode;
  final String? pan;
  final String? exp;
  final String? panSuffix;

  CardDto({
    this.brandCode,
    this.pan,
    this.exp,
    this.panSuffix,
  });

  factory CardDto.fromJson(Map<String, dynamic> json) {
    return CardDto(
      brandCode: json['brandCode'],
      pan: json['pan'],
      exp: json['exp'],
      panSuffix: json['panSuffix'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'brandCode': brandCode,
      'pan': pan,
      'exp': exp,
      'panSuffix': panSuffix,
    };
  }
}

class AuthEventDto {
  final AuthReceiptDto? receipt;
  final String? rrn;
  final String? status;

  AuthEventDto({
    this.receipt,
    this.rrn,
    this.status,
  });

  factory AuthEventDto.fromJson(Map<String, dynamic> json) {
    return AuthEventDto(
      receipt: json['receipt'] != null
          ? AuthReceiptDto.fromJson(json['receipt'])
          : null,
      rrn: json['rrn'],
      status: json['status'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'receipt': receipt?.toJson(),
      'rrn': rrn,
      'status': status,
    };
  }
}

class AuthReceiptDto {
  final String standard;
  final String id;
  final ReceiptDataDto data;

  AuthReceiptDto({
    required this.standard,
    required this.id,
    required this.data,
  });

  factory AuthReceiptDto.fromJson(Map<String, dynamic> json) {
    return AuthReceiptDto(
      standard: json['standard'],
      id: json['id'],
      data: ReceiptDataDto.fromJson(json['data']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'standard': standard,
      'id': id,
      'data': data.toJson(),
    };
  }
}

class ReceiptDataDto {
  final String transactionUuid;
  final List<String> supportedLanguages;
  final String receiptType;
  final String status;
  final String authCode;
  final String actionCode;
  final String amount;
  final AmountAuthorizedDto amountAuthorized;
  final CurrencyDto currency;
  final String stan;
  final String rrn;
  final String tid;
  final String startAt;
  final String endAt;
  final String version;
  final CardDto card;
  final MerchantDto merchant;
  final List<MetaDto> meta;
  final String qrCode;

  ReceiptDataDto({
    required this.transactionUuid,
    required this.supportedLanguages,
    required this.receiptType,
    required this.status,
    required this.authCode,
    required this.actionCode,
    required this.amount,
    required this.amountAuthorized,
    required this.currency,
    required this.stan,
    required this.rrn,
    required this.tid,
    required this.startAt,
    required this.endAt,
    required this.version,
    required this.card,
    required this.merchant,
    required this.meta,
    required this.qrCode,
  });

  factory ReceiptDataDto.fromJson(Map<String, dynamic> json) {
    return ReceiptDataDto(
      transactionUuid: json['transactionUuid'],
      supportedLanguages:
      List<String>.from(json['supportedLanguages'] ?? []),
      receiptType: json['receiptType'],
      status: json['status'],
      authCode: json['authCode'],
      actionCode: json['actionCode'],
      amount: json['amount'],
      amountAuthorized: AmountAuthorizedDto.fromJson(json['amountAuthorized']),
      currency: CurrencyDto.fromJson(json['currency']),
      stan: json['stan'],
      rrn: json['rrn'],
      tid: json['tid'],
      startAt: json['startAt'],
      endAt: json['endAt'],
      version: json['version'],
      card: CardDto.fromJson(json['card']),
      merchant: MerchantDto.fromJson(json['merchant']),
      meta: (json['meta'] as List)
          .map((e) => MetaDto.fromJson(e))
          .toList(),
      qrCode: json['qrCode'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transactionUuid': transactionUuid,
      'supportedLanguages': supportedLanguages,
      'receiptType': receiptType,
      'status': status,
      'authCode': authCode,
      'actionCode': actionCode,
      'amount': amount,
      'amountAuthorized': amountAuthorized.toJson(),
      'currency': currency.toJson(),
      'stan': stan,
      'rrn': rrn,
      'tid': tid,
      'startAt': startAt,
      'endAt': endAt,
      'version': version,
      'card': card.toJson(),
      'merchant': merchant.toJson(),
      'meta': meta.map((e) => e.toJson()).toList(),
      'qrCode': qrCode,
    };
  }
}
class MetaDto {
  final String key;
  final String value;

  MetaDto({
    required this.key,
    required this.value,
  });

  factory MetaDto.fromJson(Map<String, dynamic> json) {
    return MetaDto(
      key: json['key'],
      value: json['value'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'value': value,
    };
  }
}

class AmountAuthorizedDto {
  final String value;

  AmountAuthorizedDto({
    required this.value,
  });

  factory AmountAuthorizedDto.fromJson(Map<String, dynamic> json) {
    return AmountAuthorizedDto(
      value: json['value'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'value': value,
    };
  }
}


class MerchantDto {
  final String id;
  final MerchantNameDto name;
  final MerchantAddressDto address;
  final String phone;
  final String mcc;
  final BankDto bank;

  MerchantDto({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.mcc,
    required this.bank,
  });

  factory MerchantDto.fromJson(Map<String, dynamic> json) {
    return MerchantDto(
      id: json['id'],
      name: MerchantNameDto.fromJson(json['name']),
      address: MerchantAddressDto.fromJson(json['address']),
      phone: json['phone'],
      mcc: json['mcc'],
      bank: BankDto.fromJson(json['bank']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name.toJson(),
      'address': address.toJson(),
      'phone': phone,
      'mcc': mcc,
      'bank': bank.toJson(),
    };
  }
}

class MerchantNameDto {
  final String en;
  final String ar;

  MerchantNameDto({
    required this.en,
    required this.ar,
  });

  factory MerchantNameDto.fromJson(Map<String, dynamic> json) {
    return MerchantNameDto(
      en: json['en'],
      ar: json['ar'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'en': en,
      'ar': ar,
    };
  }
}


class MerchantAddressDto {
  final String en;
  final String ar;

  MerchantAddressDto({
    required this.en,
    required this.ar,
  });

  factory MerchantAddressDto.fromJson(Map<String, dynamic> json) {
    return MerchantAddressDto(
      en: json['en'],
      ar: json['ar'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'en': en,
      'ar': ar,
    };
  }
}

class BankDto {
  final String id;
  final MerchantNameDto name;

  BankDto({
    required this.id,
    required this.name,
  });

  factory BankDto.fromJson(Map<String, dynamic> json) {
    return BankDto(
      id: json['id'],
      name: MerchantNameDto.fromJson(json['name']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name.toJson(),
    };
  }
}


