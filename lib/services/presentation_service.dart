import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service that manages the Android Presentation API for dual-screen devices.
///
/// On devices like Sunmi D2s that have two screens in one device,
/// this service detects the secondary display and shows the customer-facing
/// Flutter UI on it using Android's Presentation API.
///
/// If no secondary display is detected, the app falls back to the existing
/// WebSocket-based DisplayAppService for connecting to a separate device.
class PresentationService extends ChangeNotifier {
  static final PresentationService _instance = PresentationService._internal();
  factory PresentationService() => _instance;
  PresentationService._internal();

  static const _channel = MethodChannel('com.hermosaapp.presentation');

  bool _hasSecondaryDisplay = false;
  bool _isPresentationShowing = false;
  bool _isSecondaryReady = false;
  Map<String, dynamic>? _displayInfo;

  // Callbacks from secondary display
  void Function(Map<String, dynamic>)? onMealAvailabilityToggle;

  bool get hasSecondaryDisplay => _hasSecondaryDisplay;
  bool get isPresentationShowing => _isPresentationShowing;
  bool get isSecondaryReady => _isSecondaryReady;
  Map<String, dynamic>? get displayInfo => _displayInfo;

  /// Whether the device supports dual-screen presentation mode.
  /// True = dual-screen device (like Sunmi D2s), use Presentation API.
  /// False = single-screen device, use WebSocket to connect to external display.
  bool get isDualScreenDevice => _hasSecondaryDisplay;

  /// Initialize the service and detect secondary displays.
  Future<void> initialize() async {
    _setupMethodCallHandler();
    await checkForSecondaryDisplay();
  }

  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onSecondaryDisplayReady':
          _isSecondaryReady = true;
          debugPrint('[Presentation] Secondary display Flutter engine ready');
          notifyListeners();
          return true;
        case 'onDisplayAdded':
          debugPrint('[Presentation] Display added: ${call.arguments}');
          await checkForSecondaryDisplay();
          return true;
        case 'onDisplayRemoved':
          debugPrint('[Presentation] Display removed: ${call.arguments}');
          _isPresentationShowing = false;
          _isSecondaryReady = false;
          await checkForSecondaryDisplay();
          return true;
        case 'onMealAvailabilityToggle':
          final data = call.arguments;
          if (data is Map) {
            onMealAvailabilityToggle?.call(
              data.map((k, v) => MapEntry(k.toString(), v)),
            );
          }
          return true;
        default:
          return null;
      }
    });
  }

  /// Check if the device has a secondary display.
  Future<bool> checkForSecondaryDisplay() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasSecondaryDisplay');
      _hasSecondaryDisplay = result ?? false;

      if (_hasSecondaryDisplay) {
        final info = await _channel
            .invokeMethod<Map<Object?, Object?>>('getSecondaryDisplayInfo');
        if (info != null) {
          _displayInfo = info.map((k, v) => MapEntry(k.toString(), v));
          debugPrint(
            '[Presentation] Secondary display found: '
            '${_displayInfo!['name']} '
            '(${_displayInfo!['width']}x${_displayInfo!['height']})',
          );
        }
      } else {
        _displayInfo = null;
        debugPrint('[Presentation] No secondary display detected');
      }

      notifyListeners();
      return _hasSecondaryDisplay;
    } on MissingPluginException {
      // Not running on Android or platform doesn't support it
      _hasSecondaryDisplay = false;
      debugPrint('[Presentation] Platform does not support Presentation API');
      return false;
    } catch (e) {
      debugPrint('[Presentation] Error checking display: $e');
      _hasSecondaryDisplay = false;
      return false;
    }
  }

  /// Show the customer display on the secondary screen.
  Future<bool> showPresentation() async {
    if (!_hasSecondaryDisplay) {
      debugPrint('[Presentation] No secondary display to show on');
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('showPresentation');
      _isPresentationShowing = result ?? false;
      debugPrint(
        '[Presentation] Show presentation: $_isPresentationShowing',
      );
      notifyListeners();
      return _isPresentationShowing;
    } catch (e) {
      debugPrint('[Presentation] Error showing presentation: $e');
      _isPresentationShowing = false;
      return false;
    }
  }

  /// Dismiss the presentation from the secondary screen.
  Future<void> dismissPresentation() async {
    try {
      await _channel.invokeMethod('dismissPresentation');
      _isPresentationShowing = false;
      _isSecondaryReady = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[Presentation] Error dismissing: $e');
    }
  }

  /// Send cart data to the secondary display.
  Future<void> updateCart(Map<String, dynamic> cartData) async {
    await _sendToSecondary('UPDATE_CART', cartData);
  }

  /// Send mode change to secondary display.
  Future<void> setMode(String mode) async {
    await _sendToSecondary('SET_MODE', {'mode': mode});
  }

  /// Send payment start to secondary display.
  Future<void> startPayment(Map<String, dynamic> paymentData) async {
    await _sendToSecondary('START_PAYMENT', paymentData);
  }

  /// Send payment result to secondary display.
  Future<void> updatePaymentStatus(
    String status, {
    String? message,
    Map<String, dynamic>? transactionData,
  }) async {
    await _sendToSecondary('PAYMENT_STATUS', {
      'status': status,
      'message': message,
      'transactionData': transactionData,
    });
  }

  /// Send catalog context to secondary display.
  Future<void> updateCatalogContext(Map<String, dynamic> context) async {
    await _sendToSecondary('CATALOG_CONTEXT', context);
  }

  /// Send language change to secondary display.
  Future<void> setLanguage(String languageCode) async {
    await _sendToSecondary('LANGUAGE_CHANGED', {'language_code': languageCode});
  }

  /// Send status overlay (e.g., refund confirmation) to secondary display.
  Future<void> showStatusOverlay(Map<String, dynamic> overlay) async {
    await _sendToSecondary('STATUS_OVERLAY', overlay);
  }

  /// Clear status overlay on secondary display.
  Future<void> clearStatusOverlay() async {
    await _sendToSecondary('CLEAR_STATUS_OVERLAY', {});
  }

  /// Generic method to send data to the secondary display.
  Future<void> _sendToSecondary(
    String type,
    Map<String, dynamic> data,
  ) async {
    if (!_isPresentationShowing || !_isSecondaryReady) return;

    try {
      await _channel.invokeMethod('sendToSecondaryDisplay', {
        'type': type,
        'data': data,
      });
    } catch (e) {
      debugPrint('[Presentation] Error sending $type: $e');
    }
  }

  @override
  void dispose() {
    dismissPresentation();
    super.dispose();
  }
}
