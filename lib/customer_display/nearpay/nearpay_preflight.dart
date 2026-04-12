import 'package:flutter/foundation.dart';

import 'nearpay_health_check.dart';
import 'nearpay_service.dart';
import 'nearpay_validator.dart';

class PreFlightResult {
  final bool success;
  final Map<String, dynamic> results;
  final List<String> errors;
  final List<String> warnings;
  final String? failedAt;

  const PreFlightResult({
    required this.success,
    required this.results,
    required this.errors,
    required this.warnings,
    required this.failedAt,
  });

  Map<String, dynamic> toJson() => {
        'success': success,
        'results': results.map(
          (key, value) => MapEntry(
            key,
            value is HardwareCheckResult
                ? value.toJson()
                : value is PermissionCheckResult
                    ? value.toJson()
                    : value is ConfigCheckResult
                        ? value.toJson()
                        : value is NetworkCheckResult
                            ? value.toJson()
                            : value is HealthCheckResult
                                ? value.toJson()
                                : value,
          ),
        ),
        'errors': errors,
        'warnings': warnings,
        'failedAt': failedAt,
      };
}

/// Orchestrate all pre-flight checks before allowing payments
class NearPayPreFlight {
  static Future<PreFlightResult> runAllChecks() async {
    final validator = NearPayValidator();
    final results = <String, dynamic>{};
    final allErrors = <String>[];
    final allWarnings = <String>[];

    debugPrint('🚀 [PreFlight] Starting comprehensive NearPay validation...');

    // 1. Hardware
    debugPrint('🔍 [PreFlight] Checking hardware...');
    final hardware = await validator.validateHardware();
    results['hardware'] = hardware;
    allErrors.addAll(hardware.errors);
    allWarnings.addAll(hardware.warnings);

    if (!hardware.allPassed) {
      debugPrint('❌ [PreFlight] Hardware check failed');
      return _buildFailure(results, allErrors, allWarnings, 'hardware');
    }
    debugPrint('✅ [PreFlight] Hardware OK');

    // 2. Permissions
    debugPrint('🔍 [PreFlight] Checking permissions...');
    final permissions = await validator.validatePermissions();
    results['permissions'] = permissions;

    if (!permissions.allGranted) {
      allErrors.add('Missing permissions: ${permissions.missing.join(", ")}');
      debugPrint('❌ [PreFlight] Permissions check failed');
      return _buildFailure(results, allErrors, allWarnings, 'permissions');
    }
    debugPrint('✅ [PreFlight] Permissions OK');

    // 3. Configuration
    debugPrint('🔍 [PreFlight] Checking configuration...');
    final config = await validator.validateConfiguration();
    results['config'] = config;
    allErrors.addAll(config.errors);

    if (!config.isValid) {
      debugPrint('❌ [PreFlight] Configuration check failed');
      return _buildFailure(results, allErrors, allWarnings, 'configuration');
    }
    debugPrint('✅ [PreFlight] Configuration OK');

    // 4. Network
    debugPrint('🔍 [PreFlight] Checking network...');
    final network = await validator.validateNetwork();
    results['network'] = network;
    allErrors.addAll(network.errors);
    allWarnings.addAll(network.warnings);

    if (!network.isReachable) {
      debugPrint('❌ [PreFlight] Network check failed');
      return _buildFailure(results, allErrors, allWarnings, 'network');
    }
    debugPrint('✅ [PreFlight] Network OK');

    // 5. SDK Health Check (full initialization test)
    debugPrint('🔍 [PreFlight] Running SDK health check...');
    final healthCheck = NearPayHealthCheck(NearPayService());
    final health = await healthCheck.runFullHealthCheck();
    results['health'] = health;
    allErrors.addAll(health.errors);

    if (!health.success) {
      debugPrint('❌ [PreFlight] SDK health check failed');
      return _buildFailure(results, allErrors, allWarnings, 'sdk_health');
    }
    debugPrint('✅ [PreFlight] SDK health check passed');

    // ALL CHECKS PASSED
    debugPrint('✅ [PreFlight] All checks passed - NearPay ready for payments');

    return PreFlightResult(
      success: true,
      results: results,
      errors: const [],
      warnings: allWarnings,
      failedAt: null,
    );
  }

  static PreFlightResult _buildFailure(
    Map<String, dynamic> results,
    List<String> errors,
    List<String> warnings,
    String failedAt,
  ) {
    return PreFlightResult(
      success: false,
      results: results,
      errors: errors,
      warnings: warnings,
      failedAt: failedAt,
    );
  }
}
