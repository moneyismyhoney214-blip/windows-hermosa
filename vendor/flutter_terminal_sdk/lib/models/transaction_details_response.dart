
class Merchant {
  String id;
  Name name;
  Address address;
  String categoryCode;

  Merchant({
    required this.id,
    required this.name,
    required this.address,
    required this.categoryCode,
  });

  factory Merchant.fromJson(Map<String, dynamic> json) {
    return Merchant(
      id: json['id'] ?? '',
      name: Name.fromJson(json['name'] ?? {}),
      address: Address.fromJson(json['address'] ?? {}),
      categoryCode: json['category_code'] ?? '',
    );
  }
}

class Name {
  String arabic;
  String english;

  Name({
    required this.arabic,
    required this.english,
  });

  factory Name.fromJson(Map<String, dynamic> json) {
    return Name(
      arabic: json['arabic'] ?? '',
      english: json['english'] ?? '',
    );
  }
}

class Address {
  String arabic;
  String english;

  Address({
    required this.arabic,
    required this.english,
  });

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      arabic: json['arabic'] ?? '',
      english: json['english'] ?? '',
    );
  }
}

class CardScheme {
  Name name;
  String id;

  CardScheme({
    required this.name,
    required this.id,
  });

  factory CardScheme.fromJson(Map<String, dynamic> json) {
    return CardScheme(
      name: Name.fromJson(json['name'] ?? {}),
      id: json['id'] ?? '',
    );
  }
}

class TransactionType {
  Name name;
  String id;

  TransactionType({
    required this.name,
    required this.id,
  });

  factory TransactionType.fromJson(Map<String, dynamic> json) {
    return TransactionType(
      name: Name.fromJson(json['name'] ?? {}),
      id: json['id'] ?? '',
    );
  }
}

class Amount {
  Name label;
  String value;

  Amount({
    required this.label,
    required this.value,
  });

  factory Amount.fromJson(Map<String, dynamic> json) {
    return Amount(
      label: Name.fromJson(json['label'] ?? {}),
      value: json['value'] ?? '0.00',
    );
  }
}

class Receipt {
  String id;
  Merchant merchant;
  String type;
  String startDate;
  String startTime;
  String cardSchemeSponsor;
  String tid;
  String systemTraceAuditNumber;
  String posSoftwareVersionNumber;
  String retrievalReferenceNumber;
  CardScheme cardScheme;
  TransactionType transactionType;
  String pan;
  String cardExpiration;
  Amount amountAuthorized;
  Amount amountOther;
  Name currency;
  Name statusMessage;
  bool isApproved;
  bool isRefunded;
  bool isReversed;
  Amount approvalCode;
  Name verificationMethod;
  String endDate;
  String endTime;
  Name receiptLineOne;
  Name receiptLineTwo;
  Name thanksMessage;
  Name saveReceiptMessage;
  String entryMode;
  String actionCode;
  String applicationIdentifier;
  String terminalVerificationResult;
  String transactionStateInformation;
  String cardholaderVerficationResult;
  String cryptogramInformationData;
  String applicationCryptogram;
  String kernelId;
  String paymentAccountReference;
  String panSuffix;
  String transactionUuid;
  String qrCode;

  Receipt({
    required this.id,
    required this.merchant,
    required this.type,
    required this.startDate,
    required this.startTime,
    required this.cardSchemeSponsor,
    required this.tid,
    required this.systemTraceAuditNumber,
    required this.posSoftwareVersionNumber,
    required this.retrievalReferenceNumber,
    required this.cardScheme,
    required this.transactionType,
    required this.pan,
    required this.cardExpiration,
    required this.amountAuthorized,
    required this.amountOther,
    required this.currency,
    required this.statusMessage,
    required this.isApproved,
    required this.isRefunded,
    required this.isReversed,
    required this.approvalCode,
    required this.verificationMethod,
    required this.endDate,
    required this.endTime,
    required this.receiptLineOne,
    required this.receiptLineTwo,
    required this.thanksMessage,
    required this.saveReceiptMessage,
    required this.entryMode,
    required this.actionCode,
    required this.applicationIdentifier,
    required this.terminalVerificationResult,
    required this.transactionStateInformation,
    required this.cardholaderVerficationResult,
    required this.cryptogramInformationData,
    required this.applicationCryptogram,
    required this.kernelId,
    required this.paymentAccountReference,
    required this.panSuffix,
    required this.transactionUuid,
    required this.qrCode,
  });

  factory Receipt.fromJson(Map<String, dynamic> json) {
    return Receipt(
      id: json['id'] ?? '',
      merchant: Merchant.fromJson(json['merchant'] ?? {}),
      type: json['type'] ?? '',
      startDate: json['start_date'] ?? '',
      startTime: json['start_time'] ?? '',
      cardSchemeSponsor: json['card_scheme_sponsor'] ?? '',
      tid: json['tid'] ?? '',
      systemTraceAuditNumber: json['system_trace_audit_number'] ?? '',
      posSoftwareVersionNumber: json['pos_software_version_number'] ?? '',
      retrievalReferenceNumber: json['retrieval_reference_number'] ?? '',
      cardScheme: CardScheme.fromJson(json['card_scheme'] ?? {}),
      transactionType: TransactionType.fromJson(json['transaction_type'] ?? {}),
      pan: json['pan'] ?? '',
      cardExpiration: json['card_expiration'] ?? '',
      amountAuthorized: Amount.fromJson(json['amount_authorized'] ?? {}),
      amountOther: Amount.fromJson(json['amount_other'] ?? {}),
      currency: Name.fromJson(json['currency'] ?? {}),
      statusMessage: Name.fromJson(json['status_message'] ?? {}),
      isApproved: json['is_approved'] ?? false,
      isRefunded: json['is_refunded'] ?? false,
      isReversed: json['is_reversed'] ?? false,
      approvalCode: Amount.fromJson(json['approval_code'] ?? {}),
      verificationMethod: Name.fromJson(json['verification_method'] ?? {}),
      endDate: json['end_date'] ?? '',
      endTime: json['end_time'] ?? '',
      receiptLineOne: Name.fromJson(json['receipt_line_one'] ?? {}),
      receiptLineTwo: Name.fromJson(json['receipt_line_two'] ?? {}),
      thanksMessage: Name.fromJson(json['thanks_message'] ?? {}),
      saveReceiptMessage: Name.fromJson(json['save_receipt_message'] ?? {}),
      entryMode: json['entry_mode'] ?? '',
      actionCode: json['action_code'] ?? '',
      applicationIdentifier: json['application_identifier'] ?? '',
      terminalVerificationResult: json['terminal_verification_result'] ?? '',
      transactionStateInformation: json['transaction_state_information'] ?? '',
      cardholaderVerficationResult: json['cardholader_verfication_result'] ?? '',
      cryptogramInformationData: json['cryptogram_information_data'] ?? '',
      applicationCryptogram: json['application_cryptogram'] ?? '',
      kernelId: json['kernel_id'] ?? '',
      paymentAccountReference: json['payment_account_reference'] ?? '',
      panSuffix: json['pan_suffix'] ?? '',
      transactionUuid: json['transaction_uuid'] ?? '',
      qrCode: json['qr_code'] ?? '',
    );
  }
}

class Receipts {
  List<Receipt> receipts;

  Receipts({required this.receipts});

  factory Receipts.fromJson(Map<String, dynamic> json) {
    var list = json['receipts'] as List;
    List<Receipt> receiptList = list.map((i) => Receipt.fromJson(i)).toList();
    return Receipts(receipts: receiptList);
  }
}
