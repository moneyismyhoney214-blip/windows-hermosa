import 'dart:convert';
import 'package:flutter/services.dart';
import '../../errors/errors.dart';
import '../../helper/helper.dart';
import 'dto/approval_code.dart';
import 'dto/currency_content.dart';
import 'dto/card_scheme.dart';
import 'dto/lable_field.dart';
import 'dto/transaction_response_turkey.dart';
import 'dto/transaction_response_usa.dart';
import 'merchant.dart' as mr;
import 'dto/transaction_type.dart' as tt;

class ReceiptsResponse {
  List<ReceiptDto>? receipts;

  ReceiptsResponse({required this.receipts});

  factory ReceiptsResponse.fromJson(Map<String, dynamic> json) {
    return ReceiptsResponse(
      receipts: (json['receipts'] as List)
          .map((item) => ReceiptDto.fromJson(item))
          .toList(),
    );
  }
}

class ReceiptDto {
  String? id;
  String? standard;
  String? operationType;
  String? data;

  ReceiptDto(
      {required this.id,
      required this.standard,
      required this.operationType,
      required this.data});

  factory ReceiptDto.fromJson(Map<String, dynamic> json) {
    return ReceiptDto(
      id: json['id'],
      standard: json['standard'],
      operationType: json['operationType'],
      data: json['data'],
    );
  }

  ReceiptDataTurkey getBKMReceipt() {
    if (data == null) {
      throw Exception("Data is null");
    }
    return ReceiptDataTurkey.fromJson(jsonDecode(data!));
  }

  AuthorizeReceipt getEPXReceipt() {
    if (data == null) {
      throw Exception("Data is null");
    }
    return AuthorizeReceipt.fromJson(jsonDecode(data!));
  }

  ReceiptData getMadaReceipt() {
    if (data == null) {
      throw Exception("Data is null");
    }
    return ReceiptData.fromJson(jsonDecode(data!));
  }
}

class ReceiptData {
  final MethodChannel _channel = const MethodChannel('nearpay_plugin');
  final String id;
  final mr.Merchant merchant;
  final String type;
  final String startDate;
  final String startTime;
  final String endDate;
  final String endTime;
  final String cardSchemeSponsor;
  final String terminalId;
  final String systemTraceAuditNumber;
  final String posSoftwareVersion;
  final String retrievalReferenceNumber;
  final CardScheme cardScheme;
  final tt.TransactionType transactionType;
  final String pan;
  final String cardExpiration;
  final LabelField<String> amountAuthorized;
  final LabelField<String> amountOther;
  final CurrencyContent currency;
  final CurrencyContent statusMessage;
  final bool isApproved;
  final bool isRefunded;
  final bool isReversed;
  final ApprovalCode approvalCode;
  final CurrencyContent verificationMethod;
  final CurrencyContent receiptLineOne;
  final CurrencyContent receiptLineTwo;
  final CurrencyContent thanksMessage;
  final CurrencyContent saveReceiptMessage;
  final String entryMode;
  final String actionCode;
  final String applicationIdentifier;
  final String terminalVerificationResult;
  final String transactionStateInformation;
  final String cardholderVerificationResult;
  final String cryptogramInformationData;
  final String applicationCryptogram;
  final String kernelId;
  final String paymentAccountReference;
  final String? panSuffix;
  final String? qrCode;
  final String transactionUuid;

  ReceiptData({
    required this.id,
    required this.merchant,
    required this.type,
    required this.startDate,
    required this.startTime,
    required this.endDate,
    required this.endTime,
    required this.cardSchemeSponsor,
    required this.terminalId,
    required this.systemTraceAuditNumber,
    required this.posSoftwareVersion,
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
    required this.receiptLineOne,
    required this.receiptLineTwo,
    required this.thanksMessage,
    required this.saveReceiptMessage,
    required this.entryMode,
    required this.actionCode,
    required this.applicationIdentifier,
    required this.terminalVerificationResult,
    required this.transactionStateInformation,
    required this.cardholderVerificationResult,
    required this.cryptogramInformationData,
    required this.applicationCryptogram,
    required this.kernelId,
    required this.paymentAccountReference,
    this.panSuffix,
    this.qrCode,
    required this.transactionUuid,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'merchant': merchant.toJson(),
      'type': type,
      'startDate': startDate,
      'startTime': startTime,
      'endDate': endDate,
      'endTime': endTime,
      'cardSchemeSponsor': cardSchemeSponsor,
      'terminalId': terminalId,
      'systemTraceAuditNumber': systemTraceAuditNumber,
      'posSoftwareVersion': posSoftwareVersion,
      'retrievalReferenceNumber': retrievalReferenceNumber,
      'cardScheme': cardScheme.toJson(),
      'transactionType': transactionType.toJson(),
      'pan': pan,
      'cardExpiration': cardExpiration,
      'amountAuthorized': amountAuthorized.toJson(),
      'amountOther': amountOther.toJson(),
      'currency': currency.toJson(),
      'statusMessage': statusMessage.toJson(),
      'isApproved': isApproved,
      'isRefunded': isRefunded,
      'isReversed': isReversed,
      'approvalCode': approvalCode.toJson(),
      'verificationMethod': verificationMethod.toJson(),
      'receiptLineOne': receiptLineOne.toJson(),
      'receiptLineTwo': receiptLineTwo.toJson(),
      'thanksMessage': thanksMessage.toJson(),
      'saveReceiptMessage': saveReceiptMessage.toJson(),
      'entryMode': entryMode,
      'actionCode': actionCode,
      'applicationIdentifier': applicationIdentifier,
      'terminalVerificationResult': terminalVerificationResult,
      'transactionStateInformation': transactionStateInformation,
      'cardholderVerificationResult': cardholderVerificationResult,
      'cryptogramInformationData': cryptogramInformationData,
      'applicationCryptogram': applicationCryptogram,
      'kernelId': kernelId,
      'paymentAccountReference': paymentAccountReference,
      'panSuffix': panSuffix,
      'qrCode': qrCode,
      'transactionUuid': transactionUuid,
    };
  }

  Future<Uint8List> toImage({
    int? receiptWidth,
    int? fontSize,
  }) async {
    final receiptPayload = jsonEncode(toJson());

    try {
      final response = await callAndReturnMapResponse(
        'toImage',
        {
          "receiptWidth": receiptWidth,
          "fontSize": fontSize,
          "receiptPayload": receiptPayload,
        },
        _channel,
      );

      if (response["status"] == "success") {
        return base64Decode(response["imageData"]);
      } else {
        throw NearpayException(
            response["message"] ?? "Convert to image failed");
      }
    } catch (e) {
      rethrow;
    }
  }

  factory ReceiptData.fromJson(Map<String, dynamic> json) {
    return ReceiptData(
      id: json['id'],
      merchant: mr.Merchant.fromJson(json['merchant']),
      type: json['type'],
      startDate: json['startDate'],
      startTime: json['startTime'],
      endDate: json['endDate'],
      endTime: json['endTime'],
      cardSchemeSponsor: json['cardSchemeSponsor'],
      terminalId: json['terminalId'],
      systemTraceAuditNumber: json['systemTraceAuditNumber'],
      posSoftwareVersion: json['posSoftwareVersion'],
      retrievalReferenceNumber: json['retrievalReferenceNumber'],
      cardScheme: CardScheme.fromJson(json['cardScheme']),
      transactionType: tt.TransactionType.fromJson(json['transactionType']),
      pan: json['pan'],
      cardExpiration: json['cardExpiration'],
      amountAuthorized: LabelField<String>.fromJson(json['amountAuthorized']),
      amountOther: LabelField<String>.fromJson(json['amountOther']),
      currency: CurrencyContent.fromJson(json['currency']),
      statusMessage: CurrencyContent.fromJson(json['statusMessage']),
      isApproved: json['isApproved'],
      isRefunded: json['isRefunded'],
      isReversed: json['isReversed'],
      approvalCode: ApprovalCode.fromJson(json['approvalCode']),
      verificationMethod: CurrencyContent.fromJson(json['verificationMethod']),
      receiptLineOne: CurrencyContent.fromJson(json['receiptLineOne']),
      receiptLineTwo: CurrencyContent.fromJson(json['receiptLineTwo']),
      thanksMessage: CurrencyContent.fromJson(json['thanksMessage']),
      saveReceiptMessage: CurrencyContent.fromJson(json['saveReceiptMessage']),
      entryMode: json['entryMode'],
      actionCode: json['actionCode'],
      applicationIdentifier: json['applicationIdentifier'],
      terminalVerificationResult: json['terminalVerificationResult'],
      transactionStateInformation: json['transactionStateInformation'],
      cardholderVerificationResult: json['cardholderVerificationResult'],
      cryptogramInformationData: json['cryptogramInformationData'],
      applicationCryptogram: json['applicationCryptogram'],
      kernelId: json['kernelId'],
      paymentAccountReference: json['paymentAccountReference'],
      panSuffix: json['panSuffix'],
      qrCode: json['qrCode'],
      transactionUuid: json['transactionUuid'],
    );

    // create toJson method
  }
}
