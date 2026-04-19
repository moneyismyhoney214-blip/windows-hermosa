import 'package:flutter/foundation.dart';

import '../../locator.dart';
import '../../services/api/api_constants.dart';
import '../../services/api/base_client.dart';
import 'app_logger.dart';
import 'nearpay_service.dart';
import 'nearpay_config_service.dart';

/// NearPay Bootstrap — centralized initialization entrypoint.
///
/// Mirrors the two-step flow that the reference implementation runs on the
/// Display App side:
///   1. `saveInitData(...)` — persists branch_id / backend_url / auth_token
///      and pre-loads terminal IDs from `/seller/nearpay/terminal/config`.
///   2. `initialize()` — executes the full 5-step SDK bootstrap
///      (SDK init → terminal config → JWT fetch → jwtLogin → terminal ready).
///
/// In the reference project the Cashier sends these values to the Display App
/// via a `NEARPAY_INIT` WebSocket message. Because we now run the SDK inside
/// the cashier process itself, we call `saveInitData` locally with the same
/// payload shape.
class NearPayBootstrap {
  NearPayBootstrap._();

  static bool _bootstrapped = false;
  static Future<bool>? _inFlight;

  /// Whether NearPay has been fully bootstrapped (init data saved + SDK ready).
  static bool get isBootstrapped => _bootstrapped;

  /// Build the payload that `NearPayService.saveInitData(...)` expects.
  ///
  /// Matches the exact field names used by the Cashier when it emits the
  /// `NEARPAY_INIT` WebSocket message in the reference project.
  static Map<String, dynamic> _buildInitPayload() {
    return <String, dynamic>{
      'branch_id': ApiConstants.branchId,
      'backend_url': ApiConstants.baseUrl,
      'auth_token': BaseClient().getToken() ?? '',
    };
  }

  /// Quick check: do we have the bare minimum values needed to bootstrap?
  static bool canBootstrap() {
    final token = BaseClient().getToken();
    return ApiConstants.branchId > 0 &&
        ApiConstants.baseUrl.isNotEmpty &&
        token != null &&
        token.isNotEmpty;
  }

  /// Save init data into the NearPayService singleton.
  ///
  /// Safe to call multiple times; each call refreshes the cached token and
  /// re-validates the backend URL.
  static Future<void> saveInitData() async {
    final service = getIt<NearPayService>();
    final payload = _buildInitPayload();
    await service.saveInitData(payload);
  }

  /// Ensure NearPay is fully initialized and the terminal is ready.
  ///
  /// Returns `true` if the SDK is ready to accept a payment, `false` otherwise.
  /// Safe to call from anywhere (e.g. just before kicking off a purchase) —
  /// concurrent calls join the same in-flight task.
  static Future<bool> ensureInitialized() async {
    final config = NearPayConfigService();
    final token = BaseClient().getToken();
    AppLogger.logNearPay(
      '🟡 Bootstrap.ensureInitialized() called '
      '(enabled=${config.isNearPayEnabled}, '
      'sdkInitialized=${config.isSdkInitialized}, '
      'bootstrapped=$_bootstrapped, inFlight=${_inFlight != null}, '
      'branchId=${ApiConstants.branchId}, '
      'baseUrl=${ApiConstants.baseUrl.isNotEmpty ? ApiConstants.baseUrl : "EMPTY"}, '
      'hasToken=${token != null && token.isNotEmpty})',
    );

    // Respect the profile flag — bail early if NearPay is disabled.
    final shouldInit = await config.shouldInitializeSdk;
    if (!shouldInit) {
      final reason = !config.isNearPayEnabled
          ? 'profile flag is OFF — did login response include options.nearpay=true?'
          : 'device reports no NFC hardware';
      debugPrint('⚠️ NearPayBootstrap: shouldInitializeSdk=false — $reason');
      AppLogger.logNearPay(
        '⚠️ Bootstrap aborted: shouldInitializeSdk=false — $reason',
      );
      return false;
    }

    if (!canBootstrap()) {
      debugPrint(
        '⚠️ NearPayBootstrap: missing branch/url/token — cannot initialize',
      );
      AppLogger.logNearPay(
        '⚠️ Bootstrap aborted: missing branch/url/token '
        '(branchId=${ApiConstants.branchId}, '
        'baseUrlEmpty=${ApiConstants.baseUrl.isEmpty}, '
        'tokenMissing=${token == null || token.isEmpty})',
      );
      return false;
    }

    final existing = _inFlight;
    if (existing != null) {
      AppLogger.logNearPay('⏳ Bootstrap join: existing in-flight task');
      return existing;
    }

    final future = _doInitialize();
    _inFlight = future;
    try {
      final ok = await future;
      _bootstrapped = ok;
      AppLogger.logNearPay(
        ok
            ? '✅ Bootstrap complete: SDK ready'
            : '❌ Bootstrap complete: SDK NOT ready (see prior error)',
      );
      return ok;
    } finally {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    }
  }

  static Future<bool> _doInitialize() async {
    try {
      final service = getIt<NearPayService>();
      await saveInitData();
      return await service.ensureReady();
    } catch (e, stack) {
      debugPrint('❌ NearPayBootstrap failed: $e');
      debugPrintStack(stackTrace: stack);
      return false;
    }
  }

  /// Clear local bootstrap state (e.g. on logout).
  /// The underlying `NearPayService.reset()` handles SDK-level cleanup.
  static Future<void> reset() async {
    _bootstrapped = false;
    _inFlight = null;
    try {
      final service = getIt<NearPayService>();
      await service.reset();
    } catch (e) {
      debugPrint('⚠️ NearPayBootstrap.reset() failed: $e');
    }
  }
}
