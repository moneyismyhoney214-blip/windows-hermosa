/// NearPay Configuration Service
///
/// Manages NearPay SDK configuration and initialization settings.
///
/// IMPORTANT: NearPay SDK is NOT initialized by default.
/// It will only be initialized when:
/// 1. Cashier sends login/seller endpoint with options: { nearpay: true }
/// 2. Country is set to Saudi Arabia (SA), NOT Turkey (TR)
/// 3. Google Cloud Project Number is provided
/// 4. Device has NFC capability (checked at runtime)
library;

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';

import 'app_logger.dart';

class NearPayConfigService {
  static final NearPayConfigService _instance =
      NearPayConfigService._internal();
  factory NearPayConfigService() => _instance;
  NearPayConfigService._internal();

  bool _isNearPayEnabled = false;
  bool _isSdkInitialized = false;
  bool? _isNfcAvailable;
  bool? _isNfcEnabled;
  Future<NfcAvailability> Function()? _nfcAvailabilityProbe;

  // Saudi Arabia configuration
  static const String country = 'SA';
  static const int googleCloudProjectNumber =
      764962961378; // From security_config.dart (removed)
  static const String androidApplicationId = 'display.hermosaapp.com';

  Future<NfcAvailability> _checkNfcAvailability() async {
    final probe = _nfcAvailabilityProbe;
    if (probe != null) {
      return probe();
    }
    return NfcManager.instance.checkAvailability();
  }

  @visibleForTesting
  void setNfcAvailabilityProbeForTesting(
    Future<NfcAvailability> Function()? probe,
  ) {
    _nfcAvailabilityProbe = probe;
  }

  void _npLog(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      '[NearPay] $message',
      name: 'NearPay',
      error: error,
      stackTrace: stackTrace,
    );
    AppLogger.logNearPay(message);
  }

  /// Check if NearPay is enabled for this seller
  bool get isNearPayEnabled => _isNearPayEnabled;

  /// Check if SDK is initialized
  bool get isSdkInitialized => _isSdkInitialized;

  /// Check if NFC is available on this device
  ///
  /// IMPORTANT: If device has no NFC, NearPay SDK CANNOT be used
  /// The SDK requires NFC hardware to read cards
  ///
  /// Only cache positive results for hardware availability (hardware doesn't
  /// appear/disappear at runtime). Negative results are not cached so that
  /// if the check failed transiently, we retry next time.
  Future<bool> get isNfcAvailable async {
    if (_isNfcAvailable == true) return true;

    try {
      // Check if NFC hardware exists (not just enabled)
      // unsupported = no NFC hardware at all
      // enabled/disabled = hardware exists
      final availability = await _checkNfcAvailability();
      _isNfcAvailable = availability != NfcAvailability.unsupported;

      if (_isNfcAvailable!) {
        _npLog('✅ NFC hardware is available on this device');
      } else {
        _npLog('❌ NFC hardware is NOT available on this device');
        _npLog('   → NearPay SDK requires NFC to read cards');
        _npLog('   → Use external payment (cashier device or cash)');
      }

      return _isNfcAvailable!;
    } catch (e) {
      _npLog('❌ Error checking NFC availability: $e', error: e);
      // Don't cache — transient error, retry next time
      return false;
    }
  }

  /// Check if NFC is enabled on this device
  ///
  /// IMPORTANT: Even if NFC hardware exists, it might be disabled in settings
  Future<bool> get isNfcEnabled async {
    // Never cache NFC enabled state — user can toggle NFC on/off at any time
    // Always re-check so the app reflects the current state.
    final nfcAvailable = await isNfcAvailable;
    if (!nfcAvailable) {
      _isNfcEnabled = false;
      return false;
    }

    try {
      // Actually check if NFC is enabled (not just hardware available)
      final availability = await _checkNfcAvailability();
      _isNfcEnabled = availability == NfcAvailability.enabled;

      if (_isNfcEnabled!) {
        _npLog('✅ NFC is enabled on this device');
      } else {
        _npLog('⚠️ NFC hardware exists but is disabled in device settings');
      }
      return _isNfcEnabled!;
    } catch (e) {
      _npLog('⚠️ NFC may be disabled in device settings: $e', error: e);
      _isNfcEnabled = false;
      return false;
    }
  }

  /// Check if NearPay payment is possible on this device
  ///
  /// Returns true ONLY if ALL conditions are met:
  /// 1. NearPay is enabled for this seller (from backend)
  /// 2. SDK is initialized
  /// 3. Device has NFC hardware ← CRITICAL
  /// 4. NFC is enabled in device settings ← CRITICAL
  ///
  /// ⚠️ IMPORTANT: If device has no NFC, NearPay SDK CANNOT work
  /// The payment must be processed externally (cashier device with NFC, cash, etc.)
  Future<bool> get isNearPayPaymentPossible async {
    if (!_isNearPayEnabled) {
      _npLog('❌ NearPay payment not possible: NearPay not enabled for seller');
      return false;
    }

    if (!_isSdkInitialized) {
      _npLog('❌ NearPay payment not possible: SDK not initialized');
      _npLog('   → Call markSdkInitialized() after successful SDK init');
      return false;
    }

    final nfcAvailable = await isNfcAvailable;
    if (!nfcAvailable) {
      _npLog('❌ NearPay payment not possible: Device has NO NFC hardware');
      _npLog('   → NearPay SDK requires NFC to read cards');
      _npLog('   → Use external payment (cashier device or cash)');
      return false;
    }

    final nfcEnabled = await isNfcEnabled;
    if (!nfcEnabled) {
      _npLog('❌ NearPay payment not possible: NFC is disabled in settings');
      _npLog('   → User must enable NFC in device settings');
      return false;
    }

    _npLog('✅ NearPay payment is possible (NFC available and enabled)');
    return true;
  }

  /// Check if NearPay SDK should be initialized
  ///
  /// Returns true only if:
  /// 1. NearPay is enabled for this seller
  /// 2. Device has NFC hardware
  ///
  /// Use this BEFORE calling FlutterTerminalSdk().initialize()
  /// to avoid initializing SDK on devices without NFC
  Future<bool> get shouldInitializeSdk async {
    if (!_isNearPayEnabled) {
      _npLog('ℹ️ SDK should NOT initialize: NearPay not enabled');
      return false;
    }

    final nfcAvailable = await isNfcAvailable;
    if (!nfcAvailable) {
      _npLog('ℹ️ SDK should NOT initialize: Device has no NFC');
      _npLog('   → NearPay SDK cannot work without NFC hardware');
      return false;
    }

    _npLog('✅ SDK should initialize: NearPay enabled and NFC available');
    return true;
  }

  /// Enable NearPay based on seller options from login/seller endpoint
  ///
  /// Cashier must send: {
  ///   "options": {
  ///     "nearpay": true
  ///   }
  /// }
  void setNearPayEnabled(bool enabled) {
    _isNearPayEnabled = enabled;
    if (enabled) {
      _npLog('✅ NearPay enabled for this seller');
    } else {
      _npLog('ℹ️ NearPay disabled for this seller');
    }
  }

  /// Mark SDK as initialized
  void markSdkInitialized() {
    _isSdkInitialized = true;
    _npLog('✅ NearPay SDK initialized for country: $country');
  }

  /// Mark NFC status (called after checking with SDK)
  void markNfcStatus({required bool available, required bool enabled}) {
    _isNfcAvailable = available;
    _isNfcEnabled = enabled;

    if (!available) {
      _npLog('⚠️ NFC hardware not available on this device');
    } else if (!enabled) {
      _npLog('⚠️ NFC is available but disabled in device settings');
    } else {
      _npLog('✅ NFC is available and enabled');
    }
  }

  /// Get initialization parameters
  /// NOTE: Environment is determined at runtime in nearpay_service.dart
  /// using kReleaseMode flag. This method is for reference only.
  Map<String, dynamic> getInitializationParams() {
    return {
      'country': country, // SA for Saudi Arabia, NOT TR (Turkey)
      'googleCloudProjectNumber': googleCloudProjectNumber,
      'environment': 'determined by kReleaseMode (see nearpay_service.dart)',
    };
  }

  /// Reset configuration (on logout)
  void reset() {
    _isNearPayEnabled = false;
    _isSdkInitialized = false;
    _isNfcAvailable = null;
    _isNfcEnabled = null;
    _nfcAvailabilityProbe = null;
    _npLog('🔄 NearPay config reset');
  }

  /// Get NearPay status summary for debugging
  Map<String, dynamic> getStatusSummary() {
    return {
      'isNearPayEnabled': _isNearPayEnabled,
      'isSdkInitialized': _isSdkInitialized,
      'isNfcAvailable': _isNfcAvailable,
      'isNfcEnabled': _isNfcEnabled,
      'country': country,
    };
  }
}
