/// NearPay Terminal SDK Models
/// Converted from Kotlin to Dart

/// Transaction Status
enum NearPayStatus { approved, declined }

/// Card Scheme Types
enum CardScheme {
  mc, // Mastercard - credit
  dm, // Maestro
  p1, // Mada
  vc, // Visa
  up, // Union Pay
  dc, // Discover
  jc, // JCB
  ax, // American Express
  gn, // GCCNET
}

/// Transaction Types
enum TransactionType {
  purchase, // 00
  refund, // 20
}

/// Currency Codes
enum Currency {
  sar, // Saudi Riyal
  usd, // US Dollar
  tryy, // Turkish Lira (renamed because 'try' is a reserved keyword)
}

/// Purchase Response
class PurchaseResponse {
  final String? status;
  final IntentDetails? details;
  final Receipt? receipt;
  final TransactionResponse? transaction;

  PurchaseResponse({this.status, this.details, this.receipt, this.transaction});

  factory PurchaseResponse.fromJson(Map<String, dynamic> json) {
    return PurchaseResponse(
      status: json['status'],
      details: json['details'] != null
          ? IntentDetails.fromJson(json['details'])
          : null,
      receipt: json['receipt'] != null
          ? Receipt.fromJson(json['receipt'])
          : null,
      transaction: json['transaction'] != null
          ? TransactionResponse.fromJson(json['transaction'])
          : null,
    );
  }

  bool get isApproved => status?.toUpperCase() == 'APPROVED';
}

/// Transaction Response
class TransactionResponse {
  final String id;
  final NearPayStatus? status;
  final String? amount;
  final Currency? currency;
  final String? createdAt;
  final String? completedAt;
  final String? canceledAt;
  final String? cancelReason;
  final String? referenceId;
  final String? orderId;
  final bool? pinRequired;
  final Card? card;
  final List<Event>? events;
  final String? amountOther;
  final List<Performance>? performance;

  TransactionResponse({
    required this.id,
    this.status,
    this.amount,
    this.currency,
    this.createdAt,
    this.completedAt,
    this.canceledAt,
    this.cancelReason,
    this.referenceId,
    this.orderId,
    this.pinRequired,
    this.card,
    this.events,
    this.amountOther,
    this.performance,
  });

  factory TransactionResponse.fromJson(Map<String, dynamic> json) {
    return TransactionResponse(
      id: json['id'],
      status: _parseStatus(json['status']),
      amount: json['amount'],
      currency: _parseCurrency(json['currency']),
      createdAt: json['createdAt'],
      completedAt: json['completedAt'],
      canceledAt: json['canceledAt'],
      cancelReason: json['cancelReason'],
      referenceId: json['referenceId'],
      orderId: json['orderId'],
      pinRequired: json['pinRequired'],
      card: json['card'] != null ? Card.fromJson(json['card']) : null,
      events: json['events'] != null
          ? (json['events'] as List).map((e) => Event.fromJson(e)).toList()
          : null,
      amountOther: json['amountOther'],
      performance: json['performance'] != null
          ? (json['performance'] as List)
                .map((e) => Performance.fromJson(e))
                .toList()
          : null,
    );
  }

  static NearPayStatus? _parseStatus(String? status) {
    if (status == null) return null;
    switch (status.toUpperCase()) {
      case 'APPROVED':
        return NearPayStatus.approved;
      case 'DECLINED':
        return NearPayStatus.declined;
      default:
        return null;
    }
  }

  static Currency? _parseCurrency(String? currency) {
    if (currency == null) return null;
    switch (currency.toUpperCase()) {
      case 'SAR':
        return Currency.sar;
      case 'USD':
        return Currency.usd;
      case 'TRY':
        return Currency.tryy;
      default:
        return null;
    }
  }
}

/// Card Information
class Card {
  final String? pan;
  final String? exp;

  Card({this.pan, this.exp});

  factory Card.fromJson(Map<String, dynamic> json) {
    return Card(pan: json['pan'], exp: json['exp']);
  }

  /// Masked PAN (e.g., **** **** **** 1234)
  String get maskedPan {
    if (pan == null || pan!.length < 4) return '****';
    return '**** **** **** ${pan!.substring(pan!.length - 4)}';
  }
}

/// Transaction Event
class Event {
  final String rrn;
  final String? stan;
  final String? type;
  final NearPayStatus status;
  final Receipt receipt;

  Event({
    required this.rrn,
    this.stan,
    this.type,
    required this.status,
    required this.receipt,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      rrn: json['rrn'],
      stan: json['stan'],
      type: json['type'],
      status:
          TransactionResponse._parseStatus(json['status']) ??
          NearPayStatus.declined,
      receipt: Receipt.fromJson(json['receipt']),
    );
  }
}

/// Receipt
class Receipt {
  final String type;
  final String id;
  final String data;

  Receipt({required this.type, required this.id, required this.data});

  factory Receipt.fromJson(Map<String, dynamic> json) {
    return Receipt(type: json['type'], id: json['id'], data: json['data']);
  }
}

/// Receipt Data
class ReceiptData {
  final String id;
  final Merchant? merchant;
  final CardScheme? cardScheme;
  final String? cardSchemeSponsor;
  final String? startDate;
  final String? startTime;
  final String? endDate;
  final String? endTime;
  final String? terminalId;
  final String? systemTraceAuditNumber;
  final String? posSoftwareVersion;
  final String? retrievalReferenceNumber;
  final TransactionType? transactionType;
  final bool? isApproved;
  final bool? isRefunded;
  final bool? isReversed;
  final String? approvalCode;
  final String? actionCode;
  final String? statusMessage;
  final String? pan;
  final String? cardExpiration;
  final LabelField<String>? amountAuthorized;
  final LabelField<String>? amountOther;
  final Currency? currency;
  final String? verificationMethod;
  final String? receiptLineOne;
  final String? receiptLineTwo;
  final String? thanksMessage;
  final String? saveReceiptMessage;
  final String? entryMode;
  final String? applicationIdentifier;
  final String? terminalVerificationResult;
  final String? transactionStateInformation;
  final String? cardholderVerificationResult;
  final String? cryptogramInformationData;
  final String? applicationCryptogram;
  final String? kernelId;
  final String? paymentAccountReference;
  final String? panSuffix;
  final String? customerReferenceNumber;
  final String? qrCode;
  final String? transactionUuid;
  final String? vasData;

  ReceiptData({
    required this.id,
    this.merchant,
    this.cardScheme,
    this.cardSchemeSponsor,
    this.startDate,
    this.startTime,
    this.endDate,
    this.endTime,
    this.terminalId,
    this.systemTraceAuditNumber,
    this.posSoftwareVersion,
    this.retrievalReferenceNumber,
    this.transactionType,
    this.isApproved,
    this.isRefunded,
    this.isReversed,
    this.approvalCode,
    this.actionCode,
    this.statusMessage,
    this.pan,
    this.cardExpiration,
    this.amountAuthorized,
    this.amountOther,
    this.currency,
    this.verificationMethod,
    this.receiptLineOne,
    this.receiptLineTwo,
    this.thanksMessage,
    this.saveReceiptMessage,
    this.entryMode,
    this.applicationIdentifier,
    this.terminalVerificationResult,
    this.transactionStateInformation,
    this.cardholderVerificationResult,
    this.cryptogramInformationData,
    this.applicationCryptogram,
    this.kernelId,
    this.paymentAccountReference,
    this.panSuffix,
    this.customerReferenceNumber,
    this.qrCode,
    this.transactionUuid,
    this.vasData,
  });

  factory ReceiptData.fromJson(Map<String, dynamic> json) {
    return ReceiptData(
      id: json['id'],
      merchant: json['merchant'] != null
          ? Merchant.fromJson(json['merchant'])
          : null,
      cardScheme: _parseCardScheme(json['cardScheme']),
      cardSchemeSponsor: json['cardSchemeSponsor'],
      startDate: json['startDate'],
      startTime: json['startTime'],
      endDate: json['endDate'],
      endTime: json['endTime'],
      terminalId: json['terminalId'],
      systemTraceAuditNumber: json['systemTraceAuditNumber'],
      posSoftwareVersion: json['posSoftwareVersion'],
      retrievalReferenceNumber: json['retrievalReferenceNumber'],
      transactionType: _parseTransactionType(json['transactionType']),
      isApproved: json['isApproved'],
      isRefunded: json['isRefunded'],
      isReversed: json['isReversed'],
      approvalCode: json['approvalCode'],
      actionCode: json['actionCode'],
      statusMessage: json['statusMessage'],
      pan: json['pan'],
      cardExpiration: json['cardExpiration'],
      amountAuthorized: json['amountAuthorized'] != null
          ? LabelField<String>.fromJson(json['amountAuthorized'])
          : null,
      amountOther: json['amountOther'] != null
          ? LabelField<String>.fromJson(json['amountOther'])
          : null,
      currency: TransactionResponse._parseCurrency(json['currency']),
      verificationMethod: json['verificationMethod'],
      receiptLineOne: json['receiptLineOne'],
      receiptLineTwo: json['receiptLineTwo'],
      thanksMessage: json['thanksMessage'],
      saveReceiptMessage: json['saveReceiptMessage'],
      entryMode: json['entryMode'],
      applicationIdentifier: json['applicationIdentifier'],
      terminalVerificationResult: json['terminalVerificationResult'],
      transactionStateInformation: json['transactionStateInformation'],
      cardholderVerificationResult: json['cardholderVerificationResult'],
      cryptogramInformationData: json['cryptogramInformationData'],
      applicationCryptogram: json['applicationCryptogram'],
      kernelId: json['kernelId'],
      paymentAccountReference: json['paymentAccountReference'],
      panSuffix: json['panSuffix'],
      customerReferenceNumber: json['customerReferenceNumber'],
      qrCode: json['qrCode'],
      transactionUuid: json['transactionUuid'],
      vasData: json['vasData'],
    );
  }

  static CardScheme? _parseCardScheme(String? scheme) {
    if (scheme == null) return null;
    switch (scheme.toUpperCase()) {
      case 'MC':
        return CardScheme.mc;
      case 'DM':
        return CardScheme.dm;
      case 'P1':
        return CardScheme.p1;
      case 'VC':
        return CardScheme.vc;
      case 'UP':
        return CardScheme.up;
      case 'DC':
        return CardScheme.dc;
      case 'JC':
        return CardScheme.jc;
      case 'AX':
        return CardScheme.ax;
      case 'GN':
        return CardScheme.gn;
      default:
        return null;
    }
  }

  static TransactionType? _parseTransactionType(String? type) {
    if (type == null) return null;
    switch (type.toUpperCase()) {
      case 'PURCHASE':
      case '00':
        return TransactionType.purchase;
      case 'REFUND':
      case '20':
        return TransactionType.refund;
      default:
        return null;
    }
  }
}

/// Merchant Information
class Merchant {
  final String? name;
  final String? address;
  final String? id;

  Merchant({this.name, this.address, this.id});

  factory Merchant.fromJson(Map<String, dynamic> json) {
    return Merchant(
      name: json['name'],
      address: json['address'],
      id: json['id'],
    );
  }
}

/// Label Field
class LabelField<T> {
  final String label;
  final T value;

  LabelField({required this.label, required this.value});

  factory LabelField.fromJson(Map<String, dynamic> json) {
    return LabelField(label: json['label'], value: json['value']);
  }
}

/// Intent Details
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
  final List<TransactionResponse>? transactions;

  IntentDetails({
    required this.intentId,
    this.referenceId,
    required this.type,
    this.status,
    this.amount,
    this.pinRequired = false,
    this.createdAt,
    this.completedAt,
    this.receiptsUrl,
    this.transactions,
  });

  factory IntentDetails.fromJson(Map<String, dynamic> json) {
    return IntentDetails(
      intentId: json['intenet_id'] ?? json['intentId'],
      referenceId: json['reference_id'] ?? json['referenceId'],
      type: json['type'],
      status: json['status'],
      amount: json['amount'],
      pinRequired: json['pin_required'] ?? json['pinRequired'] ?? false,
      createdAt: json['created_at'] ?? json['createdAt'],
      completedAt: json['completed_at'] ?? json['completedAt'],
      receiptsUrl: json['group_receipts_url'] ?? json['receiptsUrl'],
      transactions: json['transactions'] != null
          ? (json['transactions'] as List)
                .map((e) => TransactionResponse.fromJson(e))
                .toList()
          : null,
    );
  }

  /// Get last transaction
  TransactionResponse? getLastTransaction() {
    if (transactions == null || transactions!.isEmpty) return null;
    return transactions!.last;
  }

  /// Get last receipt
  Receipt? getLastReceipt() {
    final lastTransaction = getLastTransaction();
    if (lastTransaction?.events == null || lastTransaction!.events!.isEmpty) {
      return null;
    }
    return lastTransaction.events!.first.receipt;
  }
}

/// Refund Response
class RefundResponse {
  final String? status;
  final IntentDetails? details;
  final Receipt? receipt;
  final TransactionResponse? transaction;

  RefundResponse({this.status, this.details, this.receipt, this.transaction});

  factory RefundResponse.fromJson(Map<String, dynamic> json) {
    return RefundResponse(
      status: json['status'],
      details: json['details'] != null
          ? IntentDetails.fromJson(json['details'])
          : null,
      receipt: json['receipt'] != null
          ? Receipt.fromJson(json['receipt'])
          : null,
      transaction: json['transaction'] != null
          ? TransactionResponse.fromJson(json['transaction'])
          : null,
    );
  }

  bool get isApproved => status?.toUpperCase() == 'APPROVED';
}

/// Reverse Response
class ReverseResponse {
  final String? amount;
  final String? completedAt;
  final String? createdAt;
  final String intentId;
  final bool pinRequired;
  final String? receiptsUrl;
  final String? referenceId;
  final String? status;
  final String type;
  final List<TransactionResponse>? transactions;

  ReverseResponse({
    this.amount,
    this.completedAt,
    this.createdAt,
    required this.intentId,
    required this.pinRequired,
    this.receiptsUrl,
    this.referenceId,
    this.status,
    required this.type,
    this.transactions,
  });

  factory ReverseResponse.fromJson(Map<String, dynamic> json) {
    return ReverseResponse(
      amount: json['amount'],
      completedAt: json['completedAt'],
      createdAt: json['createdAt'],
      intentId: json['intentId'],
      pinRequired: json['pinRequired'] ?? false,
      receiptsUrl: json['receiptsUrl'],
      referenceId: json['referenceId'],
      status: json['status'],
      type: json['type'],
      transactions: json['transactions'] != null
          ? (json['transactions'] as List)
                .map((e) => TransactionResponse.fromJson(e))
                .toList()
          : null,
    );
  }

  bool get isApproved => status?.toUpperCase() == 'APPROVED';
}

/// User
class NearPayUser {
  final String? name;
  final String? email;
  final String? mobile;
  final String? userUUID;

  NearPayUser({this.name, this.email, this.mobile, this.userUUID});

  factory NearPayUser.fromJson(Map<String, dynamic> json) {
    return NearPayUser(
      name: json['name'],
      email: json['email'],
      mobile: json['mobile'],
      userUUID: json['userUUID'],
    );
  }
}

/// Terminal Connection
class TerminalConnection {
  final TerminalConnectionData terminalConnectionData;

  TerminalConnection({required this.terminalConnectionData});

  factory TerminalConnection.fromJson(Map<String, dynamic> json) {
    return TerminalConnection(
      terminalConnectionData: TerminalConnectionData.fromJson(
        json['terminalConnectionData'],
      ),
    );
  }
}

/// Terminal Connection Data
class TerminalConnectionData {
  final String? name;
  final String tid;
  final String uuid;
  final bool busy;
  final String mode;
  final bool isLocked;
  final bool hasProfile;
  final String userUUID;

  TerminalConnectionData({
    this.name,
    required this.tid,
    this.uuid = '',
    this.busy = false,
    required this.mode,
    this.isLocked = false,
    this.hasProfile = false,
    required this.userUUID,
  });

  factory TerminalConnectionData.fromJson(Map<String, dynamic> json) {
    return TerminalConnectionData(
      name: json['name'],
      tid: json['tid'],
      uuid: json['uuid'] ?? '',
      busy: json['busy'] ?? false,
      mode: json['mode'],
      isLocked: json['isLocked'] ?? false,
      hasProfile: json['hasProfile'] ?? false,
      userUUID: json['userUUID'],
    );
  }
}

/// Terminal Information
class TerminalInfo {
  final String terminalId;
  final String bankId;
  final String merchantId;
  final String vendorId;
  final String merchantCategoryCode;

  TerminalInfo({
    required this.terminalId,
    required this.bankId,
    required this.merchantId,
    required this.vendorId,
    required this.merchantCategoryCode,
  });

  factory TerminalInfo.fromJson(Map<String, dynamic> json) {
    return TerminalInfo(
      terminalId: json['terminalId'],
      bankId: json['bankId'],
      merchantId: json['merchantId'],
      vendorId: json['vendorId'],
      merchantCategoryCode: json['merchantCategoryCode'],
    );
  }
}

/// Performance Data
class Performance {
  final String? type;
  final int? duration;
  final String? timestamp;

  Performance({this.type, this.duration, this.timestamp});

  factory Performance.fromJson(Map<String, dynamic> json) {
    return Performance(
      type: json['type'],
      duration: json['duration'],
      timestamp: json['timestamp'],
    );
  }
}

/// Otp Response
class OtpResponse {
  final String? message;

  OtpResponse({this.message});

  factory OtpResponse.fromJson(Map<String, dynamic> json) {
    return OtpResponse(message: json['message']);
  }
}

/// Error/Failure Classes
abstract class NearPayFailure {
  final String? message;

  NearPayFailure({this.message});
}

class SendTransactionFailure extends NearPayFailure {
  SendTransactionFailure({super.message});
}

class RefundTransactionFailure extends NearPayFailure {
  RefundTransactionFailure({super.message});
}

class AuthorizeFailure extends NearPayFailure {
  AuthorizeFailure({super.message});
}

class ReverseTransactionFailure extends NearPayFailure {
  ReverseTransactionFailure({super.message});
}

class ReconcileFailure extends NearPayFailure {
  ReconcileFailure({super.message});
}

class ConnectTerminalFailure extends NearPayFailure {
  ConnectTerminalFailure({super.message});
}

class VerifyMobileFailure extends NearPayFailure {
  VerifyMobileFailure({super.message});
}

class VerifyEmailFailure extends NearPayFailure {
  VerifyEmailFailure({super.message});
}

class JWTLoginFailure extends NearPayFailure {
  JWTLoginFailure({super.message});
}

class GetTerminalsFailure extends NearPayFailure {
  GetTerminalsFailure({super.message});
}

class VoidFailure extends NearPayFailure {
  VoidFailure({super.message});
}

class CaptureAuthorizationFailure extends NearPayFailure {
  CaptureAuthorizationFailure({super.message});
}

class TipTransactionFailure extends NearPayFailure {
  TipTransactionFailure({super.message});
}

class GetIntentFailure extends NearPayFailure {
  GetIntentFailure({super.message});
}

class GetReconciliationListFailure extends NearPayFailure {
  GetReconciliationListFailure({super.message});
}

class GetReconciliationFailure extends NearPayFailure {
  GetReconciliationFailure({super.message});
}

class GetIntentsListFailure extends NearPayFailure {
  GetIntentsListFailure({super.message});
}

class IncrementAuthorizationFailure extends NearPayFailure {
  IncrementAuthorizationFailure({super.message});
}

class CaptureAuthorizationWithTapFailure extends NearPayFailure {
  CaptureAuthorizationWithTapFailure({super.message});
}

class OTPMobileFailure extends NearPayFailure {
  OTPMobileFailure({super.message});
}

class OTPEmailFailure extends NearPayFailure {
  OTPEmailFailure({super.message});
}

/// Permission Status
class NearPayPermissionStatus {
  final String permission;
  final bool isGranted;

  NearPayPermissionStatus({required this.permission, required this.isGranted});

  factory NearPayPermissionStatus.fromJson(Map<String, dynamic> json) {
    return NearPayPermissionStatus(
      permission: json['permission'],
      isGranted: json['isGranted'],
    );
  }
}

/// Canceled State
class CanceledState {
  final bool canceled;

  CanceledState({required this.canceled});

  factory CanceledState.fromJson(Map<String, dynamic> json) {
    return CanceledState(canceled: json['canceled']);
  }
}

/// Reconciliation Response
class ReconciliationResponse {
  final String id;
  final String date;
  final String time;
  final String startDate;
  final String startTime;
  final String endDate;
  final String endTime;
  final Merchant? merchant;
  final String cardAcceptorTerminalId;
  final String posSoftwareVersionNumber;
  final String cardSchemeSponsorId;
  final LabelField<bool>? isBalanced;
  final List<Scheme>? schemes;
  final Details? details;
  final LanguageContent? currency;
  final String systemTraceAuditNumber;

  ReconciliationResponse({
    required this.id,
    required this.date,
    required this.time,
    required this.startDate,
    required this.startTime,
    required this.endDate,
    required this.endTime,
    this.merchant,
    required this.cardAcceptorTerminalId,
    required this.posSoftwareVersionNumber,
    required this.cardSchemeSponsorId,
    this.isBalanced,
    this.schemes,
    this.details,
    this.currency,
    required this.systemTraceAuditNumber,
  });

  factory ReconciliationResponse.fromJson(Map<String, dynamic> json) {
    return ReconciliationResponse(
      id: json['id'],
      date: json['date'],
      time: json['time'],
      startDate: json['startDate'],
      startTime: json['startTime'],
      endDate: json['endDate'],
      endTime: json['endTime'],
      merchant: json['merchant'] != null
          ? Merchant.fromJson(json['merchant'])
          : null,
      cardAcceptorTerminalId: json['cardAcceptorTerminalId'],
      posSoftwareVersionNumber: json['posSoftwareVersionNumber'],
      cardSchemeSponsorId: json['cardSchemeSponsorId'],
      isBalanced: json['isBalanced'] != null
          ? LabelField<bool>.fromJson(json['isBalanced'])
          : null,
      schemes: json['schemes'] != null
          ? (json['schemes'] as List).map((e) => Scheme.fromJson(e)).toList()
          : null,
      details: json['details'] != null
          ? Details.fromJson(json['details'])
          : null,
      currency: json['currency'] != null
          ? LanguageContent.fromJson(json['currency'])
          : null,
      systemTraceAuditNumber: json['systemTraceAuditNumber'],
    );
  }
}

/// Scheme
class Scheme {
  final String? name;
  final String? count;
  final String? amount;

  Scheme({this.name, this.count, this.amount});

  factory Scheme.fromJson(Map<String, dynamic> json) {
    return Scheme(
      name: json['name'],
      count: json['count'],
      amount: json['amount'],
    );
  }
}

/// Details
class Details {
  final DetailItem? total;
  final DetailItem? purchase;
  final DetailItem? purchaseReversal;
  final DetailItem? refund;
  final DetailItem? refundReversal;

  Details({
    this.total,
    this.purchase,
    this.purchaseReversal,
    this.refund,
    this.refundReversal,
  });

  factory Details.fromJson(Map<String, dynamic> json) {
    return Details(
      total: json['total'] != null ? DetailItem.fromJson(json['total']) : null,
      purchase: json['purchase'] != null
          ? DetailItem.fromJson(json['purchase'])
          : null,
      purchaseReversal: json['purchaseReversal'] != null
          ? DetailItem.fromJson(json['purchaseReversal'])
          : null,
      refund: json['refund'] != null
          ? DetailItem.fromJson(json['refund'])
          : null,
      refundReversal: json['refundReversal'] != null
          ? DetailItem.fromJson(json['refundReversal'])
          : null,
    );
  }
}

/// Detail Item
class DetailItem {
  final LanguageContent? label;
  final String? total;
  final int? count;

  DetailItem({this.label, this.total, this.count});

  factory DetailItem.fromJson(Map<String, dynamic> json) {
    return DetailItem(
      label: json['label'] != null
          ? LanguageContent.fromJson(json['label'])
          : null,
      total: json['total'],
      count: json['count'],
    );
  }
}

/// Language Content
class LanguageContent {
  final String? arabic;
  final String? english;
  final String? turkish;

  LanguageContent({this.arabic, this.english, this.turkish});

  factory LanguageContent.fromJson(Map<String, dynamic> json) {
    return LanguageContent(
      arabic: json['arabic'],
      english: json['english'],
      turkish: json['turkish'],
    );
  }
}

/// Transactions Response
class TransactionsResponse {
  final List<Transaction>? data;
  final Pagination? pagination;

  TransactionsResponse({this.data, this.pagination});

  factory TransactionsResponse.fromJson(Map<String, dynamic> json) {
    return TransactionsResponse(
      data: json['data'] != null
          ? (json['data'] as List).map((e) => Transaction.fromJson(e)).toList()
          : null,
      pagination: json['pagination'] != null
          ? Pagination.fromJson(json['pagination'])
          : null,
    );
  }
}

/// Transaction (List Item)
class Transaction {
  final String uuid;
  final String scheme;
  final String? customerReferenceNumber;
  final String? pan;
  final String amountAuthorized;
  final String transactionType;
  final Currency? currency;
  final bool isApproved;
  final bool isReversed;
  final bool isReconciled;
  final String startDate;
  final String startTime;
  final List<Performance>? performance;

  Transaction({
    required this.uuid,
    required this.scheme,
    this.customerReferenceNumber,
    this.pan,
    required this.amountAuthorized,
    required this.transactionType,
    this.currency,
    required this.isApproved,
    required this.isReversed,
    required this.isReconciled,
    required this.startDate,
    required this.startTime,
    this.performance,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      uuid: json['uuid'],
      scheme: json['scheme'],
      customerReferenceNumber: json['customerReferenceNumber'],
      pan: json['pan'],
      amountAuthorized: json['amountAuthorized'],
      transactionType: json['transactionType'],
      currency: TransactionResponse._parseCurrency(json['currency']),
      isApproved: json['isApproved'],
      isReversed: json['isReversed'],
      isReconciled: json['isReconciled'],
      startDate: json['startDate'],
      startTime: json['startTime'],
      performance: json['performance'] != null
          ? (json['performance'] as List)
                .map((e) => Performance.fromJson(e))
                .toList()
          : null,
    );
  }
}

/// Pagination
class Pagination {
  final int? totalPages;
  final int currentPage;
  final int? totalData;

  Pagination({this.totalPages, required this.currentPage, this.totalData});

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      totalPages: json['total_pages'] ?? json['totalPages'],
      currentPage: json['current_page'] ?? json['currentPage'],
      totalData: json['total_data'] ?? json['totalData'],
    );
  }
}

/// Receipts Response
class ReceiptsResponse {
  final List<ReceiptItem>? receipts;

  ReceiptsResponse({this.receipts});

  factory ReceiptsResponse.fromJson(Map<String, dynamic> json) {
    return ReceiptsResponse(
      receipts: json['receipts'] != null
          ? (json['receipts'] as List)
                .map((e) => ReceiptItem.fromJson(e))
                .toList()
          : null,
    );
  }
}

/// Receipt Item
class ReceiptItem {
  final String id;
  final String operationType;
  final String standard;
  final String data;
  final String transactionUuid;

  ReceiptItem({
    required this.id,
    required this.operationType,
    required this.standard,
    required this.data,
    required this.transactionUuid,
  });

  factory ReceiptItem.fromJson(Map<String, dynamic> json) {
    return ReceiptItem(
      id: json['id'],
      operationType: json['operationType'],
      standard: json['standard'],
      data: json['data'],
      transactionUuid: json['transactionUuid'],
    );
  }
}

/// Reconciliation List Response
class ReconciliationListResponse {
  final List<ReconciliationItem>? data;
  final Pagination? pagination;

  ReconciliationListResponse({this.data, this.pagination});

  factory ReconciliationListResponse.fromJson(Map<String, dynamic> json) {
    return ReconciliationListResponse(
      data: json['data'] != null
          ? (json['data'] as List)
                .map((e) => ReconciliationItem.fromJson(e))
                .toList()
          : null,
      pagination: json['pagination'] != null
          ? Pagination.fromJson(json['pagination'])
          : null,
    );
  }
}

/// Reconciliation Item
class ReconciliationItem {
  final String id;
  final String date;
  final String time;
  final String startDate;
  final String startTime;
  final LabelField<bool>? isBalanced;
  final String? total;
  final Currency? currency;

  ReconciliationItem({
    required this.id,
    required this.date,
    required this.time,
    required this.startDate,
    required this.startTime,
    this.isBalanced,
    this.total,
    this.currency,
  });

  factory ReconciliationItem.fromJson(Map<String, dynamic> json) {
    return ReconciliationItem(
      id: json['id'],
      date: json['date'],
      time: json['time'],
      startDate: json['startDate'],
      startTime: json['startTime'],
      isBalanced: json['isBalanced'] != null
          ? LabelField<bool>.fromJson(json['isBalanced'])
          : null,
      total: json['total'],
      currency: TransactionResponse._parseCurrency(json['currency']),
    );
  }
}

/// Reconciliation Receipts Response
class ReconciliationReceiptsResponse {
  final ReconciliationReceipt? receipt;
  final String? reconciliationId;

  ReconciliationReceiptsResponse({this.receipt, this.reconciliationId});

  factory ReconciliationReceiptsResponse.fromJson(Map<String, dynamic> json) {
    return ReconciliationReceiptsResponse(
      receipt: json['receipt'] != null
          ? ReconciliationReceipt.fromJson(json['receipt'])
          : null,
      reconciliationId: json['reconciliationId'],
    );
  }
}

/// Reconciliation Receipt
class ReconciliationReceipt {
  final String id;
  final String standard;
  final String operationType;
  final ReconciliationReceiptData? data;
  final Reconciliation? reconciliation;
  final String createdAt;
  final String updatedAt;

  ReconciliationReceipt({
    required this.id,
    required this.standard,
    required this.operationType,
    this.data,
    this.reconciliation,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReconciliationReceipt.fromJson(Map<String, dynamic> json) {
    return ReconciliationReceipt(
      id: json['id'],
      standard: json['standard'],
      operationType: json['operationType'],
      data: json['data'] != null
          ? ReconciliationReceiptData.fromJson(json['data'])
          : null,
      reconciliation: json['reconciliation'] != null
          ? Reconciliation.fromJson(json['reconciliation'])
          : null,
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
    );
  }
}

/// Reconciliation
class Reconciliation {
  final String id;

  Reconciliation({required this.id});

  factory Reconciliation.fromJson(Map<String, dynamic> json) {
    return Reconciliation(id: json['id']);
  }
}

/// Reconciliation Receipt Data
class ReconciliationReceiptData {
  final String date;
  final String hour;
  final String bankName;
  final String grandTotal;
  final String documentRef;
  final String businessName;
  final String serialNumber;
  final String businessNumber;
  final String terminalNumber;
  final List<EndOfDaySummaryItem>? endOfDaySummary;
  final String businessAddressAndTelephone;

  ReconciliationReceiptData({
    required this.date,
    required this.hour,
    required this.bankName,
    required this.grandTotal,
    required this.documentRef,
    required this.businessName,
    required this.serialNumber,
    required this.businessNumber,
    required this.terminalNumber,
    this.endOfDaySummary,
    required this.businessAddressAndTelephone,
  });

  factory ReconciliationReceiptData.fromJson(Map<String, dynamic> json) {
    return ReconciliationReceiptData(
      date: json['date'],
      hour: json['hour'],
      bankName: json['bankName'],
      grandTotal: json['grandTotal'],
      documentRef: json['documentRef'],
      businessName: json['businessName'],
      serialNumber: json['serialNumber'],
      businessNumber: json['businessNumber'],
      terminalNumber: json['terminalNumber'],
      endOfDaySummary: json['endOfDaySummary'] != null
          ? (json['endOfDaySummary'] as List)
                .map((e) => EndOfDaySummaryItem.fromJson(e))
                .toList()
          : null,
      businessAddressAndTelephone: json['businessAddressAndTelephone'],
    );
  }
}

/// End of Day Summary Item
class EndOfDaySummaryItem {
  final String? type;
  final String? count;
  final String? amount;

  EndOfDaySummaryItem({this.type, this.count, this.amount});

  factory EndOfDaySummaryItem.fromJson(Map<String, dynamic> json) {
    return EndOfDaySummaryItem(
      type: json['type'],
      count: json['count'],
      amount: json['amount'],
    );
  }
}

/// Intents List Response
class IntentsListResponse {
  final List<IntentItem>? data;
  final Pagination? pagination;

  IntentsListResponse({this.data, this.pagination});

  factory IntentsListResponse.fromJson(Map<String, dynamic> json) {
    return IntentsListResponse(
      data: json['data'] != null
          ? (json['data'] as List).map((e) => IntentItem.fromJson(e)).toList()
          : null,
      pagination: json['pagination'] != null
          ? Pagination.fromJson(json['pagination'])
          : null,
    );
  }
}

/// Intent Item
class IntentItem {
  final String? customerReferenceNumber;
  final String? amount;
  final String id;
  final String? originalIntentID;

  IntentItem({
    this.customerReferenceNumber,
    this.amount,
    required this.id,
    this.originalIntentID,
  });

  factory IntentItem.fromJson(Map<String, dynamic> json) {
    return IntentItem(
      customerReferenceNumber: json['customer_reference_number'],
      amount: json['amount'],
      id: json['id'],
      originalIntentID: json['original_intent_id'],
    );
  }
}

/// Void Authorization Response
class VoidAuthorizationResponse {
  final String? status;
  final IntentDetails? details;
  final Receipt? receipt;
  final TransactionResponse? transaction;

  VoidAuthorizationResponse({
    this.status,
    this.details,
    this.receipt,
    this.transaction,
  });

  factory VoidAuthorizationResponse.fromJson(Map<String, dynamic> json) {
    return VoidAuthorizationResponse(
      status: json['status'],
      details: json['details'] != null
          ? IntentDetails.fromJson(json['details'])
          : null,
      receipt: json['receipt'] != null
          ? Receipt.fromJson(json['receipt'])
          : null,
      transaction: json['transaction'] != null
          ? TransactionResponse.fromJson(json['transaction'])
          : null,
    );
  }

  bool get isApproved => status?.toUpperCase() == 'APPROVED';
}

/// Authorize Response
class AuthorizeResponse {
  final String? amount;
  final String? completedAt;
  final String? createdAt;
  final String intentId;
  final bool pinRequired;
  final String? receiptsUrl;
  final String? referenceId;
  final String? status;
  final String type;
  final List<AuthorizeReceipt>? transactions;

  AuthorizeResponse({
    this.amount,
    this.completedAt,
    this.createdAt,
    required this.intentId,
    required this.pinRequired,
    this.receiptsUrl,
    this.referenceId,
    this.status,
    required this.type,
    this.transactions,
  });

  factory AuthorizeResponse.fromJson(Map<String, dynamic> json) {
    return AuthorizeResponse(
      amount: json['amount'],
      completedAt: json['completedAt'],
      createdAt: json['createdAt'],
      intentId: json['intentId'],
      pinRequired: json['pinRequired'] ?? false,
      receiptsUrl: json['receiptsUrl'],
      referenceId: json['referenceId'],
      status: json['status'],
      type: json['type'],
      transactions: json['transactions'] != null
          ? (json['transactions'] as List)
                .map((e) => AuthorizeReceipt.fromJson(e))
                .toList()
          : null,
    );
  }

  bool get isApproved => status?.toUpperCase() == 'APPROVED';
}

/// Authorize Receipt
class AuthorizeReceipt {
  final String id;
  final String? amountOther;
  final Currency? currency;
  final String? createdAt;
  final String? completedAt;
  final bool pinRequired;
  final List<Performance>? performance;
  final Card? card;
  final List<AuthEvent>? events;

  AuthorizeReceipt({
    required this.id,
    this.amountOther,
    this.currency,
    this.createdAt,
    this.completedAt,
    required this.pinRequired,
    this.performance,
    this.card,
    this.events,
  });

  factory AuthorizeReceipt.fromJson(Map<String, dynamic> json) {
    return AuthorizeReceipt(
      id: json['id'],
      amountOther: json['amountOther'],
      currency: TransactionResponse._parseCurrency(json['currency']),
      createdAt: json['createdAt'],
      completedAt: json['completedAt'],
      pinRequired: json['pinRequired'] ?? false,
      performance: json['performance'] != null
          ? (json['performance'] as List)
                .map((e) => Performance.fromJson(e))
                .toList()
          : null,
      card: json['card'] != null ? Card.fromJson(json['card']) : null,
      events: json['events'] != null
          ? (json['events'] as List).map((e) => AuthEvent.fromJson(e)).toList()
          : null,
    );
  }
}

/// Auth Event
class AuthEvent {
  final String rrn;
  final String? stan;
  final String? type;
  final NearPayStatus status;
  final Receipt receipt;

  AuthEvent({
    required this.rrn,
    this.stan,
    this.type,
    required this.status,
    required this.receipt,
  });

  factory AuthEvent.fromJson(Map<String, dynamic> json) {
    return AuthEvent(
      rrn: json['rrn'],
      stan: json['stan'],
      type: json['type'],
      status:
          TransactionResponse._parseStatus(json['status']) ??
          NearPayStatus.declined,
      receipt: Receipt.fromJson(json['receipt']),
    );
  }
}

/// Capture Response
class CaptureResponse {
  final String id;
  final String? amountOther;
  final Currency? currency;
  final String? createdAt;
  final String? completedAt;
  final bool pinRequired;
  final List<Performance>? performance;
  final Card? card;
  final List<CaptureEvent>? events;

  CaptureResponse({
    required this.id,
    this.amountOther,
    this.currency,
    this.createdAt,
    this.completedAt,
    required this.pinRequired,
    this.performance,
    this.card,
    this.events,
  });

  factory CaptureResponse.fromJson(Map<String, dynamic> json) {
    return CaptureResponse(
      id: json['id'],
      amountOther: json['amountOther'],
      currency: TransactionResponse._parseCurrency(json['currency']),
      createdAt: json['createdAt'],
      completedAt: json['completedAt'],
      pinRequired: json['pinRequired'] ?? false,
      performance: json['performance'] != null
          ? (json['performance'] as List)
                .map((e) => Performance.fromJson(e))
                .toList()
          : null,
      card: json['card'] != null ? Card.fromJson(json['card']) : null,
      events: json['events'] != null
          ? (json['events'] as List)
                .map((e) => CaptureEvent.fromJson(e))
                .toList()
          : null,
    );
  }
}

/// Capture Event
class CaptureEvent {
  final String rrn;
  final String? stan;
  final String? type;
  final NearPayStatus status;
  final Receipt receipt;

  CaptureEvent({
    required this.rrn,
    this.stan,
    this.type,
    required this.status,
    required this.receipt,
  });

  factory CaptureEvent.fromJson(Map<String, dynamic> json) {
    return CaptureEvent(
      rrn: json['rrn'],
      stan: json['stan'],
      type: json['type'],
      status:
          TransactionResponse._parseStatus(json['status']) ??
          NearPayStatus.declined,
      receipt: Receipt.fromJson(json['receipt']),
    );
  }
}

/// Increment Response
class IncrementResponse {
  final String id;
  final String? amountOther;
  final Currency? currency;
  final String? createdAt;
  final String? completedAt;
  final bool pinRequired;
  final List<Performance>? performance;
  final Card? card;
  final List<IncrementEvent>? events;

  IncrementResponse({
    required this.id,
    this.amountOther,
    this.currency,
    this.createdAt,
    this.completedAt,
    required this.pinRequired,
    this.performance,
    this.card,
    this.events,
  });

  factory IncrementResponse.fromJson(Map<String, dynamic> json) {
    return IncrementResponse(
      id: json['id'],
      amountOther: json['amountOther'],
      currency: TransactionResponse._parseCurrency(json['currency']),
      createdAt: json['createdAt'],
      completedAt: json['completedAt'],
      pinRequired: json['pinRequired'] ?? false,
      performance: json['performance'] != null
          ? (json['performance'] as List)
                .map((e) => Performance.fromJson(e))
                .toList()
          : null,
      card: json['card'] != null ? Card.fromJson(json['card']) : null,
      events: json['events'] != null
          ? (json['events'] as List)
                .map((e) => IncrementEvent.fromJson(e))
                .toList()
          : null,
    );
  }
}

/// Increment Event
class IncrementEvent {
  final String rrn;
  final String? stan;
  final String? type;
  final NearPayStatus status;
  final Receipt receipt;

  IncrementEvent({
    required this.rrn,
    this.stan,
    this.type,
    required this.status,
    required this.receipt,
  });

  factory IncrementEvent.fromJson(Map<String, dynamic> json) {
    return IncrementEvent(
      rrn: json['rrn'],
      stan: json['stan'],
      type: json['type'],
      status:
          TransactionResponse._parseStatus(json['status']) ??
          NearPayStatus.declined,
      receipt: Receipt.fromJson(json['receipt']),
    );
  }
}
