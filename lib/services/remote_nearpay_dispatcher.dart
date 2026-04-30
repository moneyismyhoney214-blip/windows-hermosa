import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../customer_display/nearpay/nearpay_service.dart' show NearPayPaymentResult;
import '../locator.dart';
import 'display_app_service.dart';

/// Routes a NearPay card payment over the existing cashier↔display_app
/// WebSocket channel instead of running the local Android-only NearPay
/// SDK.
///
/// Used on iOS where the NearPay SDK has no native implementation:
/// the cashier app sends a `START_PAYMENT` request to a paired
/// display_app device (Sunmi Android terminal with the SDK), which
/// runs the actual card flow and replies with `PAYMENT_SUCCESS` /
/// `PAYMENT_FAILED` / `PAYMENT_CANCELLED`. The dispatcher wraps that
/// asynchronous round-trip into the same `NearPayPaymentResult` shape
/// as the local SDK so call sites need a single platform gate, not a
/// rewrite.
class RemoteNearPayDispatcher {
  RemoteNearPayDispatcher._();
  static final RemoteNearPayDispatcher instance = RemoteNearPayDispatcher._();

  /// Whether remote dispatch must be used on the current platform.
  /// True on iOS (and macOS/web for completeness — the local SDK is
  /// Android-only). Android continues to drive NearPay in-process.
  static bool get isRequired {
    if (kIsWeb) return true;
    return !Platform.isAndroid;
  }

  /// Default timeout — the SDK card flow itself can take 60–90s
  /// once the customer is fumbling for the card. Keep this generous.
  static const Duration _defaultTimeout = Duration(minutes: 3);

  bool _busy = false;

  /// Send the payment to the paired display_app and wait for the
  /// result. The signature mirrors `NearPayService.executePurchaseWithSession`.
  Future<NearPayPaymentResult> requestRemotePurchase({
    required double amount,
    required String referenceId,
    String? sessionId,
    void Function(String status)? onStatusUpdate,
    Duration timeout = _defaultTimeout,
  }) async {
    if (_busy) {
      return NearPayPaymentResult.failure(
        referenceId: referenceId,
        message: 'هناك عملية دفع قيد التنفيذ بالفعل',
      );
    }

    final DisplayAppService display;
    try {
      display = getIt<DisplayAppService>();
    } catch (e) {
      return NearPayPaymentResult.failure(
        referenceId: referenceId,
        message: 'لم يتم تهيئة خدمة شاشة العميل: $e',
      );
    }

    if (!display.isConnected) {
      return NearPayPaymentResult.failure(
        referenceId: referenceId,
        message:
            'لا يوجد اتصال بجهاز شاشة العميل. تحقق من الإعدادات وحاول مرة أخرى.',
      );
    }

    _busy = true;
    final completer = Completer<NearPayPaymentResult>();

    void resolve(NearPayPaymentResult result) {
      if (!completer.isCompleted) completer.complete(result);
    }

    display.setCallbacks(
      onPaymentStatus: (status, message) {
        if (onStatusUpdate != null) {
          final text = (message != null && message.trim().isNotEmpty)
              ? message
              : status;
          onStatusUpdate(text);
        }
      },
      onPaymentSuccess: (Map<String, dynamic> data) {
        final txId = (data['transactionId'] ??
                data['transaction_id'] ??
                data['id'] ??
                referenceId)
            .toString();
        final amt = (data['amount'] is num)
            ? (data['amount'] as num).toDouble()
            : amount;
        resolve(NearPayPaymentResult.success(
          referenceId: referenceId,
          transactionId: txId,
          amount: amt,
        ));
      },
      onPaymentFailed: (errorMessage) {
        resolve(NearPayPaymentResult.failure(
          referenceId: referenceId,
          message: errorMessage,
        ));
      },
      onPaymentCancelled: () {
        resolve(NearPayPaymentResult.failure(
          referenceId: referenceId,
          message: 'تم إلغاء عملية الدفع',
        ));
      },
    );

    try {
      onStatusUpdate?.call('إرسال طلب الدفع لشاشة العميل...');
      display.startPayment(
        amount: amount,
        orderNumber: sessionId ?? const Uuid().v4(),
        customerReference: referenceId,
      );

      final result = await completer.future.timeout(timeout, onTimeout: () {
        return NearPayPaymentResult.failure(
          referenceId: referenceId,
          message: 'انتهت مهلة انتظار رد جهاز شاشة العميل',
        );
      });
      return result;
    } catch (e) {
      return NearPayPaymentResult.failure(
        referenceId: referenceId,
        message: 'تعذر إرسال طلب الدفع: $e',
      );
    } finally {
      display.clearCallbacks();
      _busy = false;
    }
  }
}
