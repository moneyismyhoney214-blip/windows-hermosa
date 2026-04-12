import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_terminal_sdk/models/data/intent_details.dart';
import 'package:flutter_terminal_sdk/models/data/reconciliation_list_response.dart';
import 'package:flutter_terminal_sdk/models/purchase_void_callbacks.dart';
import 'package:flutter_terminal_sdk/models/authorized_callbacks.dart';
import 'package:flutter_terminal_sdk/models/refund_callbacks.dart';
import 'package:flutter_terminal_sdk/models/refund_void_callbacks.dart';
import '../errors/errors.dart';
import '../helper/helper.dart';
import 'capture_authorization_with_tap_callbacks.dart';
import 'card_reader_callbacks.dart';
import 'data/authorize_response.dart';
import 'data/capture_response.dart';
import 'data/dto/payment_text.dart';
import 'data/intent_response_turkey.dart';
import 'data/purchase_response.dart';
import 'data/reconcile_response.dart';
import 'data/reconciliation_receipts_response.dart';
import 'data/increment_response.dart';
import 'data/refund_response.dart';
import 'data/reverse_response.dart';
import 'data/void_authorization_response.dart';
import 'intents_list_response.dart';
import 'open_refund_callbacks.dart';
import 'purchase_callbacks.dart';
import 'data/payment_scheme.dart';

class TerminalModel {
  final String? name;
  final PaymentText? paymentText;
  final String? terminalUUID;
  final String? tid;
  final String? client;

  final MethodChannel _channel = const MethodChannel('nearpay_plugin');
  final Map<String, AuthorizedCallbacks> _activeAuthorizeCallbacks = {};
  final Map<String, PurchaseCallbacks> _activePurchaseCallbacks = {};
  final Map<String, PurchaseCallbacks> _activePurchaseWithTipCallbacks = {};
  final Map<String, PurchaseCallbacks> _activeInstallmentsCallbacks = {};
  final Map<String, PurchaseVoidCallbacks> _activePurchaseVoidCallbacks = {};
  final Map<String, RefundCallbacks> _activeRefundCallbacks = {};
  final Map<String, OpenRefundCallbacks> _activeOpenRefundCallbacks = {};
  final Map<String, RefundVoidCallbacks> _activeRefundVoidCallbacks = {};
  final Map<String, CaptureAuthorizationWithTapCallbacks>
      _activeCaptureAuthorizationWithTapCallbacks = {};

  TerminalModel({
    this.name,
    this.paymentText,
    required this.terminalUUID,
    required this.tid,
    this.client,
  }) {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  factory TerminalModel.fromJson(Map<String, dynamic> json) {
    return TerminalModel(
      tid: json['tid'] as String?,
      terminalUUID: json['terminalUUID'] as String?,
      name: json['name'] as String?,
      client: json['client'] as String?,
      paymentText: json['paymentText'] != null
          ? PaymentText.fromJson(json['paymentText'])
          : null,
    );
  }

  @override
  String toString() {
    return 'TerminalModel(name: $name, paymentText: $paymentText, terminalUUID: $terminalUUID, tid: $tid , client: $client)';
  }

  // isTerminalReady
  Future<bool> isTerminalReady() async {
    final response = await callAndReturnMapResponse(
      'isTerminalReady',
      {'terminalUUID': terminalUUID},
      _channel,
    );

    final status = response['status'];
    if (status == 'success') {
      return response['data'] as bool;
    } else {
      final message =
          response['message'] ?? 'Failed to check terminal readiness';
      throw NearpayException(message);
    }
  }

  // dismissReaderUi
  Future<bool> dismissReaderUi() async {
    final response = await callAndReturnMapResponse(
      'dismissReaderUi',
      {'terminalUUID': terminalUUID},
      _channel,
    );

    final status = response['status'];
    if (status == 'success') {
      return response['data'] as bool;
    } else {
      final message =
          response['message'] ?? 'Failed to check terminal readiness';
      throw NearpayException(message);
    }
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method == 'purchaseEvent' ||
        call.method == 'refundEvent' ||
        call.method == 'purchaseVoidEvent' ||
        call.method == 'refundVoidEvent' ||
        call.method == 'openRefundEvent' ||
        call.method == 'authorizeEvent' ||
        call.method == 'captureAuthorizationWithTapEvent' ||
        call.method == 'purchaseWithTipEvent' ||
        call.method == 'installmentsEvent') {
      final args = Map<String, dynamic>.from(call.arguments);
      final intentUUID = args['intentUUID'] as String?;
      final eventType = args['type'] as String;
      final message = args['message'] as String?;
      // print message
      if (kDebugMode) {
        print(
            "Received $eventType for intentUUID $intentUUID: message => $message");
      }

      final rawData = args['data'];
      Map<String, dynamic>? data;

      if (rawData is String) {
        // If data is a JSON string, decode it
        try {
          data = jsonDecode(rawData);
        } catch (e) {
          // print("Error decoding JSON string for $eventType: $e");
        }
      } else if (rawData is Map) {
        // If data is already a map, cast it properly
        data = Map<String, dynamic>.from(rawData);
      }

      switch (call.method) {
        case 'purchaseEvent':
          final PurchaseCallbacks? callbacks =
              _activePurchaseCallbacks[intentUUID];

          if (callbacks == null) {
            if (kDebugMode) {
              print("No active purchase callbacks for intentUUID: $intentUUID");
            }
            return;
          }

          _handleEvent(
              eventType,
              message,
              data,
              callbacks.cardReaderCallbacks,
              callbacks.onTransactionPurchaseCompleted,
              callbacks.onSendTransactionFailure);
          break;
        case 'installmentsEvent':
          final PurchaseCallbacks? callbacks =
              _activeInstallmentsCallbacks[intentUUID];

          if (callbacks == null) {
            if (kDebugMode) {
              print("No active purchase callbacks for intentUUID: $intentUUID");
            }
            return;
          }

          _handleEvent(
              eventType,
              message,
              data,
              callbacks.cardReaderCallbacks,
              callbacks.onTransactionPurchaseCompleted,
              callbacks.onSendTransactionFailure);
          break;
        case 'purchaseWithTipEvent':
          final PurchaseCallbacks? callbacks =
              _activePurchaseWithTipCallbacks[intentUUID];

          if (callbacks == null) {
            if (kDebugMode) {
              print("No active purchase callbacks for intentUUID: $intentUUID");
            }
            return;
          }

          _handleEvent(
              eventType,
              message,
              data,
              callbacks.cardReaderCallbacks,
              callbacks.onTransactionPurchaseCompleted,
              callbacks.onSendTransactionFailure);
          break;
        case 'authorizeEvent':
          final AuthorizedCallbacks? callbacks =
              _activeAuthorizeCallbacks[intentUUID];

          if (callbacks == null) {
            if (kDebugMode) {
              print(
                  "No active authorized callbacks for intentUUID: $intentUUID");
            }
            return;
          }

          _handleEvent(
              eventType,
              message,
              data,
              callbacks.cardReaderCallbacks,
              callbacks.onSendAuthorizedCompleted,
              callbacks.onSendTransactionFailure);
          break;
        case 'refundEvent':
          final RefundCallbacks? callbacks = _activeRefundCallbacks[intentUUID];

          if (callbacks == null) {
            if (kDebugMode) {
              print("No active refund callbacks for intentUUID: $intentUUID");
            }
            return;
          }

          _handleEvent(
              eventType,
              message,
              data,
              callbacks.cardReaderCallbacks,
              callbacks.onTransactionRefundCompleted,
              callbacks.onSendTransactionFailure);
          break;
        case 'openRefundEvent':
          final OpenRefundCallbacks? callbacks =
              _activeOpenRefundCallbacks[intentUUID];

          if (callbacks == null) {
            if (kDebugMode) {
              print(
                  "No active open refund callbacks for intentUUID: $intentUUID");
            }
            return;
          }

          _handleEvent(
              eventType,
              message,
              data,
              callbacks.cardReaderCallbacks,
              callbacks.onTransactionOpenRefundCompleted,
              callbacks.onSendTransactionFailure);
          break;
        case 'purchaseVoidEvent':
          final PurchaseVoidCallbacks? callbacks =
              _activePurchaseVoidCallbacks[intentUUID];

          if (callbacks == null) {
            if (kDebugMode) {
              print(
                  "No active purchase void callbacks for intentUUID: $intentUUID");
            }
            return;
          }

          _handleEvent(
              eventType,
              message,
              data,
              callbacks.cardReaderCallbacks,
              callbacks.onSendPurchaseVoidCompleted,
              callbacks.onSendPurchaseVoidFailure);
          break;
        case 'captureAuthorizationWithTapEvent':
          final uuid = args['uuid'] as String;

          final CaptureAuthorizationWithTapCallbacks? callbacks =
              _activeCaptureAuthorizationWithTapCallbacks[uuid];

          if (callbacks == null) {
            if (kDebugMode) {
              print(
                  "No active capture authorization with tap callbacks for intentUUID: $uuid");
            }
            return;
          }

          _handleEvent(
              eventType,
              message,
              data,
              callbacks.cardReaderCallbacks,
              callbacks.onAuthorizedResponseWithTapCompleted,
              callbacks.onSendTransactionFailure);
          break;
        case 'refundVoidEvent':
          final RefundVoidCallbacks? callbacks =
              _activeRefundVoidCallbacks[intentUUID];

          if (callbacks == null) {
            if (kDebugMode) {
              print(
                  "No active refund void callbacks for intentUUID: $intentUUID");
            }
            return;
          }

          _handleEvent(eventType, message, data, callbacks.cardReaderCallbacks,
              callbacks.onRefundVoidCompleted, callbacks.onRefundVoidFailure);
          break;
      }
    }
  }

  void _handleEvent(
    String eventType,
    String? message,
    Map<String, dynamic>? data,
    CardReaderCallbacks? cardReaderCallbacks,
    Function? onSuccess,
    Function(String)? onFailure,
  ) {
    switch (eventType) {
      case 'readerDisplayed':
        cardReaderCallbacks?.onReaderDisplayed?.call();
        break;
      case 'readerDismissed':
        cardReaderCallbacks?.onReaderDismissed?.call();
        break;
      case 'readerClosed':
        cardReaderCallbacks?.onReaderClosed?.call();
        break;
      case 'readingStarted':
        cardReaderCallbacks?.onReadingStarted?.call();
        break;
      case 'readerWaiting':
        cardReaderCallbacks?.onReaderWaiting?.call();
        break;
      case 'readerReading':
        cardReaderCallbacks?.onReaderReading?.call();
        break;
      case 'readerRetry':
        cardReaderCallbacks?.onReaderRetry?.call();
        break;
      case 'pinEntering':
        cardReaderCallbacks?.onPinEntering?.call();
        break;
      case 'readerFinished':
        cardReaderCallbacks?.onReaderFinished?.call();
        break;
      case 'readerError':
        if (message != null) {
          cardReaderCallbacks?.onReaderError?.call(message);
        }
        break;
      case 'cardReadSuccess':
        cardReaderCallbacks?.onCardReadSuccess?.call();
        break;
      case 'cardReadFailure':
        if (message != null) {
          cardReaderCallbacks?.onCardReadFailure?.call(message);
        }
        break;
      case 'sendTransactionFailure':
        if (message != null) {
          onFailure?.call(message);
        }
        break;
      case 'authorizeFailure':
        if (message != null) {
          onFailure?.call(message);
        }
        break;
      case 'sendPurchaseTransactionCompleted':
        if (data != null) {
          try {
            final purchaseResponse = PurchaseResponse.fromJson(data);
            onSuccess?.call(purchaseResponse);
          } catch (e) {
            onFailure?.call("Error parsing PurchaseResponse: $e");
          }
        }
        break;
      case 'sendPurchaseWithTipTransactionCompleted':
        if (data != null) {
          try {
            final purchaseResponse = PurchaseResponse.fromJson(data);
            onSuccess?.call(purchaseResponse);
          } catch (e) {
            onFailure?.call("Error parsing PurchaseResponse: $e");
          }
        }
        break;
      case 'sendInstallmentsTransactionCompleted':
        if (data != null) {
          try {
            final purchaseResponse = PurchaseResponse.fromJson(data);
            onSuccess?.call(purchaseResponse);
          } catch (e) {
            onFailure?.call("Error parsing PurchaseResponse: $e");
          }
        }
        break;
      case 'sendRefundTransactionCompleted':
        if (data != null) {
          try {
            final refundResponse = RefundResponse.fromJson(data);
            onSuccess?.call(refundResponse);
          } catch (e) {
            onFailure?.call("Error parsing RefundResponse: $e");
          }
        }
        break;
      case 'sendOpenRefundTransactionCompleted':
        if (data != null) {
          try {
            final refundResponse = RefundResponse.fromJson(data);
            onSuccess?.call(refundResponse);
          } catch (e) {
            onFailure?.call("Error parsing RefundResponse: $e");
          }
        }
        break;
      case 'authorizeCompleted':
        if (data != null) {
          try {
            final authorizeResponse = AuthorizeResponse.fromJson(data);
            onSuccess?.call(authorizeResponse);
          } catch (e) {
            onFailure?.call("Error parsing AuthorizeResponse: $e");
          }
        }
        break;
      case 'captureWithTapCompleted':
        if (data != null) {
          try {
            final captureResponse = CaptureResponse.fromJson(data);
            onSuccess?.call(captureResponse);
          } catch (e) {
            onFailure?.call("Error parsing AuthorizeResponse: $e");
          }
        }
        break;
      case 'sendTransactionVoidCompleted':
        if (data != null) {
          try {
            final intentResponseTurkey = IntentResponseTurkey.fromJson(data);
            onSuccess?.call(intentResponseTurkey);
          } catch (e) {
            onFailure?.call("Error parsing IntentResponseTurkey: $e");
          }
        }
        break;
      default:
        onFailure?.call("Unknown event type: $eventType");
        break;
    }
  }

  void dispose() {
    _activePurchaseCallbacks.clear();
    _activeRefundCallbacks.clear();
    _activeOpenRefundCallbacks.clear();
    _activePurchaseVoidCallbacks.clear();
    _activeRefundVoidCallbacks.clear();
    _activeAuthorizeCallbacks.clear();
    _activeCaptureAuthorizationWithTapCallbacks.clear();
    _activePurchaseWithTipCallbacks.clear();
    _activeInstallmentsCallbacks.clear();
  }

  /// reverseTerminal
  Future<ReverseResponse> reverseTransaction({
    required String intentId,
  }) async {
    final response = await callAndReturnMapResponse(
      'reverseTransaction',
      {
        'terminalUUID': terminalUUID,
        'intentId': intentId,
      },
      _channel,
    );

    final status = response['status'];
    if (status == 'success') {
      final data = response['data'] as Map<String, dynamic>;
      return ReverseResponse.fromJson(data);
    } else {
      final message = response['message'] ?? 'Failed to reverse transaction';
      throw NearpayException(message);
    }
  }

  Future<String> purchase({
    required String intentUUID,
    required int amount,
    PaymentScheme? scheme,
    String? customerReferenceNumber,
    required PurchaseCallbacks callbacks,
  }) async {
    _activePurchaseCallbacks[intentUUID] = callbacks;

    try {
      final response = await callAndReturnMapResponse(
        'purchase',
        {
          "uuid": terminalUUID,
          "amount": amount,
          "scheme": scheme?.name,
          "intentUUID": intentUUID,
          "customerReferenceNumber": customerReferenceNumber,
        },
        _channel,
      );

      if (response["status"] == "success") {
        return intentUUID;
      } else {
        _activePurchaseCallbacks.remove(intentUUID);
        throw NearpayException(response["message"] ?? "Purchase failed");
      }
    } catch (e) {
      _activePurchaseCallbacks.remove(intentUUID);
      rethrow;
    }
  }

  Future<String> purchaseWithTip({
    required String intentUUID,
    required int amount,
    required int amountOther,
    PaymentScheme? scheme,
    String? customerReferenceNumber,
    required PurchaseCallbacks callbacks,
  }) async {
    _activePurchaseWithTipCallbacks[intentUUID] = callbacks;

    try {
      final response = await callAndReturnMapResponse(
        'purchaseWithTip',
        {
          "uuid": terminalUUID,
          "amount": amount,
          "amountOther": amountOther,
          "scheme": scheme?.name,
          "intentUUID": intentUUID,
          "customerReferenceNumber": customerReferenceNumber,
        },
        _channel,
      );

      if (response["status"] == "success") {
        return intentUUID;
      } else {
        _activePurchaseWithTipCallbacks.remove(intentUUID);
        throw NearpayException(response["message"] ?? "Purchase failed");
      }
    } catch (e) {
      _activePurchaseWithTipCallbacks.remove(intentUUID);
      rethrow;
    }
  }

  Future<String> installments({
    required String intentUUID,
    required int amount,
    required int numberOfInstallments,
    PaymentScheme? scheme,
    String? customerReferenceNumber,
    required PurchaseCallbacks callbacks,
  }) async {
    _activeInstallmentsCallbacks[intentUUID] = callbacks;

    try {
      final response = await callAndReturnMapResponse(
        'installments',
        {
          "uuid": terminalUUID,
          "amount": amount,
          "numberOfInstallments": numberOfInstallments,
          "scheme": scheme?.name,
          "intentUUID": intentUUID,
          "customerReferenceNumber": customerReferenceNumber,
        },
        _channel,
      );

      if (response["status"] == "success") {
        return intentUUID;
      } else {
        _activeInstallmentsCallbacks.remove(intentUUID);
        throw NearpayException(response["message"] ?? "Purchase failed");
      }
    } catch (e) {
      _activeInstallmentsCallbacks.remove(intentUUID);
      rethrow;
    }
  }

  Future<String> purchaseVoid({
    required String intentUUID,
    required int amount,
    PaymentScheme? scheme,
    String? customerReferenceNumber,
    required PurchaseVoidCallbacks callbacks,
  }) async {
    _activePurchaseVoidCallbacks[intentUUID] = callbacks;

    try {
      final response = await callAndReturnMapResponse(
        'purchaseVoid',
        {
          "uuid": terminalUUID,
          "amount": amount,
          "scheme": scheme?.name,
          "intentUUID": intentUUID,
          "customerReferenceNumber": customerReferenceNumber,
        },
        _channel,
      );

      if (response["status"] == "success") {
        return intentUUID;
      } else {
        _activePurchaseVoidCallbacks.remove(intentUUID);
        throw NearpayException(response["message"] ?? "Purchase failed");
      }
    } catch (e) {
      _activePurchaseVoidCallbacks.remove(intentUUID);
      rethrow;
    }
  }

  Future<String> refund({
    required String intentUUID,
    required String refundUuid,
    required int amount,
    PaymentScheme? scheme,
    String? customerReferenceNumber,
    required RefundCallbacks callbacks,
  }) async {
    _activeRefundCallbacks[intentUUID] = callbacks;

    try {
      final response = await callAndReturnMapResponse(
        'refund',
        {
          "terminalUUID": terminalUUID,
          "intentUUID": intentUUID,
          "refundUuid": refundUuid,
          "amount": amount,
          "customerReferenceNumber": customerReferenceNumber,
          "scheme": scheme?.name,
        },
        _channel,
      );

      if (response["status"] == "success") {
        return refundUuid;
      } else {
        _activeRefundCallbacks.remove(intentUUID);
        throw NearpayException(response["message"] ?? "Refund failed");
      }
    } catch (e) {
      _activeRefundCallbacks.remove(intentUUID);
      rethrow;
    }
  }

  Future<String> openRefund({
    required String intentUUID,
    required int amount,
    PaymentScheme? scheme,
    String? customerReferenceNumber,
    required OpenRefundCallbacks callbacks,
  }) async {
    _activeOpenRefundCallbacks[intentUUID] = callbacks;

    try {
      final response = await callAndReturnMapResponse(
        'openRefund',
        {
          "terminalUUID": terminalUUID,
          "intentUUID": intentUUID,
          "amount": amount,
          "customerReferenceNumber": customerReferenceNumber,
          "scheme": scheme?.name,
        },
        _channel,
      );

      if (response["status"] == "success") {
        return intentUUID;
      } else {
        _activeOpenRefundCallbacks.remove(intentUUID);
        throw NearpayException(response["message"] ?? "Refund failed");
      }
    } catch (e) {
      _activeOpenRefundCallbacks.remove(intentUUID);
      rethrow;
    }
  }

  Future<String> refundVoid({
    required String refundUuid,
    required int amount,
    PaymentScheme? scheme,
    String? customerReferenceNumber,
    required RefundVoidCallbacks callbacks,
  }) async {
    _activeRefundVoidCallbacks[refundUuid] = callbacks;

    try {
      final response = await callAndReturnMapResponse(
        'refundVoid',
        {
          "terminalUUID": terminalUUID,
          "refundUuid": refundUuid,
          "amount": amount,
          "customerReferenceNumber": customerReferenceNumber,
          "scheme": scheme?.name,
        },
        _channel,
      );

      if (response["status"] == "success") {
        return refundUuid;
      } else {
        _activeRefundVoidCallbacks.remove(refundUuid);
        throw NearpayException(response["message"] ?? "Refund failed");
      }
    } catch (e) {
      _activeRefundVoidCallbacks.remove(refundUuid);
      rethrow;
    }
  }

  Future<IntentDetails> getIntent({
    required String intentUUID,
  }) async {
    try {
      final response = await callAndReturnMapResponse(
        'getIntent',
        {
          "terminalUUID": terminalUUID,
          "intentUUID": intentUUID,
        },
        _channel,
      );

      if (response["status"] == "success") {
        return IntentDetails.fromJson(response['data']);
      } else {
        throw NearpayException(
            response["message"] ?? "Get Transaction Details Failed");
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<IntentsListResponse> getIntentList({
    int? page,
    int? pageSize,
    bool? isReconciled,
    String? startDate,
    String? endDate,
    String? customerReferenceNumber,
  }) async {
    final result = await callAndReturnMapResponse(
      'getIntentList',
      {
        "terminalUUID": terminalUUID,
        "page": page,
        "pageSize": pageSize,
        "isReconciled": isReconciled,
        "startDate": startDate,
        "endDate": endDate,
        "customerReferenceNumber": customerReferenceNumber,
      },
      _channel,
    );
    final status = result['status'];
    if (status == 'success') {
      final data = result['data'] as Map<String, dynamic>;

      final myData = IntentsListResponse.fromJson(data);
      return myData;
    } else {
      final message = result['message'] ?? 'Unknown error';
      throw NearpayException('Failed to retrieve Transactions: $message');
    }
  }

  Future<ReconciliationResponse> getReconciliation({
    required String uuid,
  }) async {
    try {
      final response = await callAndReturnMapResponse(
        'getReconciliation',
        {
          "terminalUUID": terminalUUID,
          "uuid": uuid,
        },
        _channel,
      );

      if (response["status"] == "success") {
        final data = response['data'] as Map<String, dynamic>;
        return ReconciliationResponse.fromJson(data);
      } else {
        throw NearpayException(
            response["message"] ?? "Get Reconcile Details Failed");
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<ReconciliationListResponse> getReconciliationList({
    required int page,
    required int pageSize,
    num? startDate,
    num? endDate,
  }) async {
    final result = await callAndReturnMapResponse(
      'getReconciliationList',
      {
        "terminalUUID": terminalUUID,
        "page": page,
        "pageSize": pageSize,
        "startDate": startDate,
        "endDate": endDate,
      },
      _channel,
    );
    final status = result['status'];
    if (status == 'success') {
      final data = result['data'] as Map<String, dynamic>;
      return ReconciliationListResponse.fromJson(data);
    } else {
      final message = result['message'] ?? 'Unknown error';
      throw NearpayException('Failed to retrieve Reconcile: $message');
    }
  }

  Future<ReconciliationReceiptsResponse> reconcile() async {
    final response = await callAndReturnMapResponse(
      'reconcile',
      {
        'terminalUUID': terminalUUID,
      },
      _channel,
    );

    final status = response['status'];
    if (status == 'success') {
      final data = response['data'] as Map<String, dynamic>;
      final dataModel = ReconciliationReceiptsResponse.fromJson(data);
      return dataModel;
    } else {
      final message = response['message'] ?? 'Failed to connect to terminal';
      throw NearpayException(message);
    }
  }

  // authorize
  Future<String> authorize({
    required String uuid,
    required int amount,
    PaymentScheme? scheme,
    String? customerReferenceNumber,
    required AuthorizedCallbacks callbacks,
  }) async {
    _activeAuthorizeCallbacks[uuid] = callbacks;

    try {
      final response = await callAndReturnMapResponse(
        'authorize',
        {
          "terminalUUID": terminalUUID,
          "amount": amount,
          "scheme": scheme?.name,
          "uuid": uuid,
          "customerReferenceNumber": customerReferenceNumber,
        },
        _channel,
      );

      if (response["status"] == "success") {
        return uuid;
      } else {
        _activeAuthorizeCallbacks.remove(uuid);
        throw NearpayException(response["message"] ?? "authorize failed");
      }
    } catch (e) {
      _activeAuthorizeCallbacks.remove(uuid);
      rethrow;
    }
  }

  // voidAuthorization
  Future<VoidAuthorizationResponse> voidAuthorization({
    required String uuid,
  }) async {
    final response = await callAndReturnMapResponse(
      'voidAuthorization',
      {
        'terminalUUID': terminalUUID,
        'uuid': uuid,
      },
      _channel,
    );

    final status = response['status'];
    if (status == 'success') {
      final data = response['data'] as Map<String, dynamic>;
      return VoidAuthorizationResponse.fromJson(data);
    } else {
      final message = response['message'] ?? 'Failed to void authorization';
      throw NearpayException(message);
    }
  }

  // incrementAuthorization
  Future<IncrementResponse> incrementAuthorization({
    required String uuid,
    required String authorizationUuid,
    required int amount,
  }) async {
    final response = await callAndReturnMapResponse(
      'incrementAuthorization',
      {
        'terminalUUID': terminalUUID,
        'uuid': uuid,
        'authorizationUuid': authorizationUuid,
        'amount': amount,
      },
      _channel,
    );

    final status = response['status'];
    if (status == 'success') {
      final data = response['data'] as Map<String, dynamic>;
      return IncrementResponse.fromJson(data);
    } else {
      final message =
          response['message'] ?? 'Failed to increment authorization';
      throw NearpayException(message);
    }
  }

  // getPendingTotal

  Future<String?> getPendingTotal() async {
    final response = await callAndReturnMapResponse(
      'getPendingTotal',
      {
        'terminalUUID': terminalUUID,
      },
      _channel,
    );

    final status = response['status'];
    if (status == 'success') {
      return response['data'];
    } else {
      final message = response['message'] ?? 'Failed to get pending total';
      throw NearpayException(message);
    }
  }

  // getTerminalConfig
  Future<String?> getTerminalConfig() async {
    final response = await callAndReturnMapResponse(
      'getTerminalConfig',
      {
        'terminalUUID': terminalUUID,
      },
      _channel,
    );

    final status = response['status'];
    if (status == 'success') {
      return response['data'];
    } else {
      final message = response['message'] ?? 'Failed to get terminal config';
      throw NearpayException(message);
    }
  }

  // captureAuthorization
  Future<CaptureResponse> captureAuthorization({
    required String uuid,
    required String authorizationUuid,
    required int amount,
  }) async {
    final response = await callAndReturnMapResponse(
      'captureAuthorization',
      {
        'terminalUUID': terminalUUID,
        'authorizationUuid': authorizationUuid,
        'uuid': uuid,
        'amount': amount,
      },
      _channel,
    );

    final status = response['status'];
    if (status == 'success') {
      final data = response['data'] as Map<String, dynamic>;
      return CaptureResponse.fromJson(data);
    } else {
      final message = response['message'] ?? 'Failed to capture authorization';
      throw NearpayException(message);
    }
  }

  // captureAuthorization
  Future<String> captureAuthorizationWithTap({
    required String uuid,
    required String authorizationUuid,
    required int amount,
    required CaptureAuthorizationWithTapCallbacks callbacks,
  }) async {
    _activeCaptureAuthorizationWithTapCallbacks[uuid] = callbacks;
    try {
      final response = await callAndReturnMapResponse(
        'captureAuthorizationWithTap',
        {
          'terminalUUID': terminalUUID,
          'authorizationUuid': authorizationUuid,
          'uuid': uuid,
          'amount': amount,
        },
        _channel,
      );

      if (response['status'] == 'success') {
        return uuid;
      } else {
        _activeCaptureAuthorizationWithTapCallbacks.remove(uuid);
        final message =
            response['message'] ?? 'Failed to capture authorization';
        throw NearpayException(message);
      }
    } catch (e) {
      _activeCaptureAuthorizationWithTapCallbacks.remove(uuid);
      rethrow;
    }
  }

// tipTransaction
  Future<PurchaseResponse> tipTransaction({
    required String id,
    required int amount,
  }) async {
    try {
      final response = await callAndReturnMapResponse(
        'tipTransaction',
        {
          "terminalUUID": terminalUUID,
          "id": id,
          "amount": amount,
        },
        _channel,
      );

      if (response["status"] == "success") {
        return PurchaseResponse.fromJson(response['data']);
      } else {
        throw NearpayException(response["message"] ?? "Tip failed");
      }
    } catch (e) {
      rethrow;
    }
  }
}
