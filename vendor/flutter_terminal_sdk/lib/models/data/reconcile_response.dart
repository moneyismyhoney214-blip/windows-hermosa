import 'package:flutter_terminal_sdk/models/data/scheme.dart';

import 'details.dart';
import 'label_value.dart';
import 'dto/language_content.dart';
import 'merchant.dart';

class ReconciliationResponse {
  final String id;
  final String date;
  final String time;
  final String startDate;
  final String startTime;
  final String endDate;
  final String endTime;
  final Merchant merchant;
  final String cardAcceptorTerminalId;
  final String posSoftwareVersionNumber;
  final String cardSchemeSponsorId;
  final LabelValue<bool> isBalanced;
  final List<Scheme> schemes;

  /// Kotlin: detailsDTO: DetailsDTO
  final Details detailsDTO;
  final LanguageContent currency;
  final String systemTraceAuditNumber;

  // Nullable / optional fields from Kotlin
  final String? merchantId;
  final String? deviceId;
  final String? clientId;
  final ID? terminal;
  final Reconciliation? reconciliation;
  final String? userId;
  final String? createdAt;
  final String? updatedAt;
  final String? qrCode;

  const ReconciliationResponse({
    required this.id,
    required this.date,
    required this.time,
    required this.startDate,
    required this.startTime,
    required this.endDate,
    required this.endTime,
    required this.merchant,
    required this.cardAcceptorTerminalId,
    required this.posSoftwareVersionNumber,
    required this.cardSchemeSponsorId,
    required this.isBalanced,
    required this.schemes,
    required this.detailsDTO,
    required this.currency,
    required this.systemTraceAuditNumber,
    this.merchantId,
    this.deviceId,
    this.clientId,
    this.terminal,
    this.reconciliation,
    this.userId,
    this.createdAt,
    this.updatedAt,
    this.qrCode,
  });

  factory ReconciliationResponse.fromJson(Map<String, dynamic> json) {
    // Support both "details" and "detailsDTO" keys
    final detailsJson =
        (json['detailsDTO'] ?? json['details']) as Map<String, dynamic>;

    return ReconciliationResponse(
      id: json['id'] as String,
      date: json['date'] as String,
      time: json['time'] as String,
      startDate: json['startDate'] as String,
      startTime: json['startTime'] as String,
      endDate: json['endDate'] as String,
      endTime: json['endTime'] as String,
      merchant: Merchant.fromJson(json['merchant'] as Map<String, dynamic>),
      cardAcceptorTerminalId: json['cardAcceptorTerminalId'] as String,
      posSoftwareVersionNumber: json['posSoftwareVersionNumber'] as String,
      cardSchemeSponsorId: json['cardSchemeSponsorId'] as String,
      isBalanced:
          LabelValue<bool>.fromJson(json['isBalanced'] as Map<String, dynamic>),
      schemes: ((json['schemes'] as List<dynamic>?) ?? const [])
          .map((e) => Scheme.fromJson(e as Map<String, dynamic>))
          .toList(),
      detailsDTO: Details.fromJson(detailsJson),
      currency:
          LanguageContent.fromJson(json['currency'] as Map<String, dynamic>),
      systemTraceAuditNumber: json['systemTraceAuditNumber'] as String,

      // Nullable fields
      merchantId: json['merchantId'] as String?,
      deviceId: json['deviceId'] as String?,
      clientId: json['clientId'] as String?,
      terminal: json['terminal'] == null
          ? null
          : ID.fromJson(json['terminal'] as Map<String, dynamic>),
      reconciliation: json['reconciliation'] == null
          ? null
          : Reconciliation.fromJson(
              json['reconciliation'] as Map<String, dynamic>),
      userId: json['userId'] as String?,
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
      qrCode: json['qrCode'] as String?,
    );
  }
}

//@kotlinx.serialization.Serializable public final data class ID public constructor(id: kotlin.String) {
class ID {
  final String id;

  const ID({required this.id});

  factory ID.fromJson(Map<String, dynamic> json) {
    return ID(
      id: json['id'] as String,
    );
  }
}

//@kotlinx.serialization.Serializable public final data class Reconciliation public constructor(id: kotlin.String) {
class Reconciliation {
  final String id;

  const Reconciliation({required this.id});

  factory Reconciliation.fromJson(Map<String, dynamic> json) {
    return Reconciliation(
      id: json['id'] as String,
    );
  }
}
