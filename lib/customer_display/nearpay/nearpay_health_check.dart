import 'package:flutter/foundation.dart';
import 'package:flutter_terminal_sdk/models/terminal_response.dart';

import 'nearpay_backend_service.dart';
import 'nearpay_service.dart';

class HealthCheckResult {
  final Map<String, bool> steps;
  final List<String> errors;
  final bool success;
  final Duration duration;

  const HealthCheckResult({
    required this.steps,
    required this.errors,
    required this.success,
    required this.duration,
  });

  Map<String, dynamic> toJson() => {
    'steps': steps,
    'errors': errors,
    'success': success,
    'duration_ms': duration.inMilliseconds,
  };
}

/// Comprehensive SDK health check
class NearPayHealthCheck {
  final NearPayService _nearPayService;

  NearPayHealthCheck(this._nearPayService);

  /// Full end-to-end SDK initialization test.
  ///
  /// Step order MUST match [NearPayService.initialize]:
  ///   1. SDK init
  ///   2. Fetch terminal config (sets _tid / _terminalUuid)
  ///   3. Fetch JWT (sends terminal_tid & terminal_id to backend)
  ///   4. jwtLogin with JWT
  ///   5. Connect terminal
  Future<HealthCheckResult> runFullHealthCheck() async {
    final steps = <String, bool>{};
    final errors = <String>[];
    final startTime = DateTime.now();

    // ── Step 1: Initialize SDK ──────────────────────────────────────────
    try {
      debugPrint('🔧 [HealthCheck] Step 1/5: Initializing SDK...');
      await _nearPayService.initializeSdkOnly();
      steps['sdk_initialized'] = true;
      debugPrint('✅ [HealthCheck] SDK initialized');
    } catch (e) {
      steps['sdk_initialized'] = false;
      errors.add('SDK initialization failed: $e');
      return _buildResult(steps, errors, startTime);
    }

    // ── Step 2: Fetch terminal config FIRST (needed for JWT request) ────
    late final Map<String, String> terminalData;
    try {
      debugPrint('🔧 [HealthCheck] Step 2/5: Fetching terminal config...');
      terminalData = await _nearPayService.fetchTerminalDataForHealthCheck();
      steps['terminals_fetched'] = true;
      debugPrint('✅ [HealthCheck] Terminal config loaded');
    } catch (e) {
      steps['terminals_fetched'] = false;
      errors.add('Terminal config fetch failed: $e');
      return _buildResult(steps, errors, startTime);
    }

    // ── Step 3: Fetch JWT (now includes terminal_tid & terminal_id) ─────
    late final NearPayJwtPayload jwt;
    try {
      debugPrint('🔧 [HealthCheck] Step 3/5: Fetching JWT...');
      final jwtStart = DateTime.now();
      jwt = await _nearPayService.fetchJwtPayloadForHealthCheck();
      final jwtDuration = DateTime.now().difference(jwtStart);

      steps['jwt_fetched'] = true;
      debugPrint(
        '✅ [HealthCheck] JWT fetched (${jwtDuration.inMilliseconds}ms)',
      );

      if (jwt.expiresIn != null && jwt.expiresIn! < 60) {
        errors.add('JWT expires in ${jwt.expiresIn}s - too short');
      }
    } catch (e) {
      steps['jwt_fetched'] = false;
      errors.add('JWT fetch failed: $e');
      return _buildResult(steps, errors, startTime);
    }

    // ── Step 4: Login to NearPay with JWT ───────────────────────────────
    late final TerminalModel loginTerminal;
    try {
      debugPrint('🔧 [HealthCheck] Step 4/5: Logging in to NearPay...');
      loginTerminal = await _nearPayService.jwtLoginForHealthCheck(jwt.token);
      steps['nearpay_login'] = true;
      debugPrint('✅ [HealthCheck] Logged in to NearPay');
    } catch (e) {
      steps['nearpay_login'] = false;
      errors.add('NearPay login failed: $e');
      return _buildResult(steps, errors, startTime);
    }

    // ── Step 5: Use the terminal returned by jwtLogin ────────────────────
    try {
      debugPrint('🔧 [HealthCheck] Step 5/5: Applying terminal from jwtLogin...');
      _nearPayService.applyTerminalForHealthCheck(
        terminal: loginTerminal,
        terminalId: terminalData['tid']!,
        terminalUUID: terminalData['terminalUUID']!,
      );

      steps['terminal_connected'] = true;
      debugPrint(
        '✅ [HealthCheck] Terminal ready: ${terminalData['tid']}',
      );
    } catch (e) {
      steps['terminal_connected'] = false;
      errors.add('Terminal setup failed: $e');
      return _buildResult(steps, errors, startTime);
    }

    // All steps passed
    final totalDuration = DateTime.now().difference(startTime);
    debugPrint(
      '✅ [HealthCheck] All checks passed in ${totalDuration.inSeconds}s',
    );

    return _buildResult(steps, errors, startTime, success: true);
  }

  HealthCheckResult _buildResult(
    Map<String, bool> steps,
    List<String> errors,
    DateTime startTime, {
    bool success = false,
  }) {
    return HealthCheckResult(
      steps: steps,
      errors: errors,
      success: success && errors.isEmpty,
      duration: DateTime.now().difference(startTime),
    );
  }
}
