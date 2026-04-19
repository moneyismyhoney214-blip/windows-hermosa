import 'package:flutter/material.dart';
import 'dart:async';

import 'display_language_service.dart';
import 'nearpay/nearpay_service.dart';

class NearPayPaymentScreen extends StatefulWidget {
  final double amount;
  final String sessionId;
  final String? customerReference;
  final Future<void> Function(Map<String, dynamic> transactionData)
      onPaymentComplete;
  final Future<void> Function(String message)? onPaymentFailed;
  final Future<void> Function()? onPaymentCancelled;
  final void Function(String status, String message)? onStatusChanged;
  final String languageCode;

  const NearPayPaymentScreen({
    super.key,
    required this.amount,
    required this.sessionId,
    this.customerReference,
    required this.onPaymentComplete,
    this.onPaymentFailed,
    this.onPaymentCancelled,
    this.onStatusChanged,
    this.languageCode = 'ar',
  });

  @override
  State<NearPayPaymentScreen> createState() => _NearPayPaymentScreenState();
}

class _NearPayPaymentScreenState extends State<NearPayPaymentScreen> {
  String _statusMessage = 'جاري التهيئة...';
  bool _isProcessing = false;
  String? _errorMessage;
  final NearPayService _nearPayService = NearPayService();

  @override
  void initState() {
    super.initState();
    _processPayment();
  }

  Future<void> _processPayment() async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _statusMessage = 'ضع البطاقة على الجهاز';
    });

    try {
      // The SDK was already fully initialized during NearPay bootstrap.
      // Do NOT call initialize() here — re-connecting to the terminal while
      // a session is active disrupts the SDK and prevents the UI from showing.
      final referenceId = widget.customerReference ??
          DateTime.now().millisecondsSinceEpoch.toString();

      // SDK UI appears automatically as a native overlay when purchase() fires.
      final result = await _nearPayService.executePurchaseWithSession(
        amount: widget.amount,
        sessionId: widget.sessionId,
        referenceId: referenceId,
        onStatusUpdate: (status) {
          if (mounted) {
            setState(() {
              _statusMessage = status;
            });
          }
          widget.onStatusChanged?.call(status, '');
        },
      );

      if (!mounted) return;

      if (result.success) {
        final transactionData = {
          'transactionId': result.transactionId!,
          'amount': widget.amount,
          'referenceId': widget.customerReference,
          'sessionId': widget.sessionId,
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'completed',
        };
        await widget.onPaymentComplete(transactionData);
        if (mounted) Navigator.of(context).pop();
      } else {
        setState(() {
          _isProcessing = false;
          _errorMessage = result.errorMessage ?? 'فشل الدفع';
        });
        await widget.onPaymentFailed?.call(_errorMessage!);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = e.toString();
        });
        await widget.onPaymentFailed?.call(e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isProcessing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isProcessing) {
          _showCancelWarning();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          title: Text(DisplayLanguageService.t('nearpay_payment', languageCode: widget.languageCode)),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              if (_isProcessing) {
                _showCancelWarning();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isProcessing) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text(
                    _statusMessage,
                    style: const TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                ] else if (_errorMessage != null) ...[
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 64,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(fontSize: 18, color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCancelWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(DisplayLanguageService.t('warning_title', languageCode: widget.languageCode)),
        content: Text(DisplayLanguageService.t('confirm_cancel_payment', languageCode: widget.languageCode)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(DisplayLanguageService.t('no', languageCode: widget.languageCode)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
              widget.onPaymentCancelled?.call();
            },
            child: Text(DisplayLanguageService.t('yes', languageCode: widget.languageCode), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
