import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nfc_manager/nfc_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nearpay_config_service.dart';

class HardwareCheckResult {
  final Map<String, bool> checks;
  final List<String> warnings;
  final List<String> errors;
  final bool allPassed;

  const HardwareCheckResult({
    required this.checks,
    required this.warnings,
    required this.errors,
    required this.allPassed,
  });

  Map<String, dynamic> toJson() => {
    'checks': checks,
    'warnings': warnings,
    'errors': errors,
    'allPassed': allPassed,
  };
}

class PermissionCheckResult {
  final Map<String, PermissionStatus> checks;
  final List<String> missing;
  final bool allGranted;

  const PermissionCheckResult({
    required this.checks,
    required this.missing,
    required this.allGranted,
  });

  Map<String, dynamic> toJson() => {
    'checks': checks.map((k, v) => MapEntry(k, v.toString())),
    'missing': missing,
    'allGranted': allGranted,
  };
}

class ConfigCheckResult {
  final Map<String, dynamic> checks;
  final List<String> errors;
  final bool isValid;

  const ConfigCheckResult({
    required this.checks,
    required this.errors,
    required this.isValid,
  });

  Map<String, dynamic> toJson() => {
    'checks': checks,
    'errors': errors,
    'isValid': isValid,
  };
}

class NetworkCheckResult {
  final Map<String, dynamic> checks;
  final List<String> warnings;
  final List<String> errors;
  final bool isReachable;

  const NetworkCheckResult({
    required this.checks,
    required this.warnings,
    required this.errors,
    required this.isReachable,
  });

  Map<String, dynamic> toJson() => {
    'checks': checks,
    'warnings': warnings,
    'errors': errors,
    'isReachable': isReachable,
  };
}

class NearPayValidator {
  /// Check all hardware prerequisites
  Future<HardwareCheckResult> validateHardware() async {
    final checks = <String, bool>{};
    final warnings = <String>[];
    final errors = <String>[];

    if (!Platform.isAndroid) {
      errors.add('NearPay SDK requires Android device');
      return HardwareCheckResult(
        checks: checks,
        warnings: warnings,
        errors: errors,
        allPassed: errors.isEmpty,
      );
    }

    // 1. NFC Hardware
    NfcAvailability? availability;
    try {
      availability = await NfcManager.instance.checkAvailability();
      final nfcHardware = availability != NfcAvailability.unsupported;
      checks['nfc_hardware'] = nfcHardware;
      if (!nfcHardware) {
        errors.add('NFC hardware not available on this device');
      }
    } catch (e) {
      checks['nfc_hardware'] = false;
      errors.add('Failed to check NFC: $e');
    }

    // 2. NFC Enabled
    try {
      final nfcEnabled =
          availability == NfcAvailability.enabled || await _isNfcEnabled();
      checks['nfc_enabled'] = nfcEnabled;
      if (!nfcEnabled) {
        warnings.add('NFC is available but disabled - guide user to enable');
      }
    } catch (e) {
      checks['nfc_enabled'] = false;
      warnings.add('Could not verify NFC status: $e');
    }

    // 3. Android Version
    final androidVersion = await _getAndroidVersion();
    checks['android_version'] = androidVersion >= 28;
    if (androidVersion < 28) {
      errors.add('Android 9+ (API 28) required, found API $androidVersion');
    }

    // 4. Bluetooth (for some terminals)
    try {
      final bluetoothAvailable = await _checkBluetooth();
      checks['bluetooth'] = bluetoothAvailable;
      if (!bluetoothAvailable) {
        warnings.add('Bluetooth not available - some terminals may not work');
      }
    } catch (e) {
      warnings.add('Could not verify Bluetooth: $e');
    }

    // 5. GPS/Location (required by NearPay SDK)
    try {
      final gpsEnabled = await _checkGPS();
      checks['gps'] = gpsEnabled;
      if (!gpsEnabled) {
        warnings.add('Location services disabled - required by NearPay');
      }
    } catch (e) {
      warnings.add('Could not verify GPS: $e');
    }

    return HardwareCheckResult(
      checks: checks,
      warnings: warnings,
      errors: errors,
      allPassed: errors.isEmpty,
    );
  }

  /// Validate all required permissions
  Future<PermissionCheckResult> validatePermissions() async {
    final checks = <String, PermissionStatus>{};
    final missing = <String>[];

    // Required permissions for NearPay
    final requiredPermissions = <String, Permission>{
      'Location': Permission.location,
      'Phone State': Permission.phone,
    };

    for (final entry in requiredPermissions.entries) {
      try {
        final status = await entry.value.status;
        checks[entry.key] = status;

        if (!status.isGranted) {
          missing.add(entry.key);
        }
      } catch (e) {
        checks[entry.key] = PermissionStatus.denied;
        missing.add(entry.key);
      }
    }

    return PermissionCheckResult(
      checks: checks,
      missing: missing,
      allGranted: missing.isEmpty,
    );
  }

  /// Verify SDK configuration is complete and valid
  Future<ConfigCheckResult> validateConfiguration() async {
    final checks = <String, dynamic>{};
    final errors = <String>[];

    // 1. Check saved auth data
    final prefs = await SharedPreferences.getInstance();

    final branchId =
        prefs.getInt('np_branch_id') ??
        int.tryParse(prefs.getString('np_branch_id') ?? '');
    checks['branch_id'] = branchId != null;
    if (branchId == null) {
      errors.add('Branch ID not configured');
    }

    final backendUrl = prefs.getString('np_backend_url');
    checks['backend_url'] = backendUrl != null;
    if (backendUrl == null || backendUrl.isEmpty) {
      errors.add('Backend URL not configured');
    } else {
      // Validate URL format
      final uri = Uri.tryParse(backendUrl);
      if (uri == null || !uri.hasScheme) {
        checks['backend_url_valid'] = false;
        errors.add('Invalid backend URL format');
      } else {
        checks['backend_url_valid'] = true;
      }
    }

    final authToken = prefs.getString('np_auth_token');
    checks['auth_token'] = authToken != null;
    if (authToken == null || authToken.isEmpty) {
      errors.add('Auth token not configured');
    }

    // 2. Check Google Cloud Project Number
    final storedProjectNumber = prefs.getString('np_google_project_number');
    final projectNumber = storedProjectNumber?.trim().isNotEmpty == true
        ? storedProjectNumber
        : NearPayConfigService.googleCloudProjectNumber.toString();
    checks['google_project_number'] =
        projectNumber != null && projectNumber.isNotEmpty;
    if (projectNumber == null || projectNumber.isEmpty) {
      errors.add(
        'Google Cloud Project Number missing - Play Integrity will fail',
      );
    }

    // 3. Verify environment setting
    final environment =
        prefs.getString('np_environment') ??
        (kReleaseMode ? 'production' : 'sandbox');
    const forcedEnvironment = String.fromEnvironment(
      'NEARPAY_SDK_ENV',
      defaultValue: '',
    );
    final normalizedForcedEnvironment = forcedEnvironment.trim().toLowerCase();
    checks['environment'] = environment;
    checks['forced_environment'] = normalizedForcedEnvironment.isEmpty
        ? 'none'
        : normalizedForcedEnvironment;
    if (kReleaseMode &&
        environment == 'sandbox' &&
        normalizedForcedEnvironment != 'sandbox') {
      errors.add(
        'Release build using sandbox environment without explicit override',
      );
    }

    return ConfigCheckResult(
      checks: checks,
      errors: errors,
      isValid: errors.isEmpty,
    );
  }

  /// Check network connectivity and backend reachability
  Future<NetworkCheckResult> validateNetwork() async {
    final checks = <String, dynamic>{};
    final warnings = <String>[];
    final errors = <String>[];

    // 1. Internet connectivity
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasInternet = connectivityResult != ConnectivityResult.none;
      checks['internet'] = hasInternet;

      if (!hasInternet) {
        errors.add('No internet connection');
        return NetworkCheckResult(
          checks: checks,
          warnings: warnings,
          errors: errors,
          isReachable: false,
        );
      }
    } catch (e) {
      errors.add('Failed to check connectivity: $e');
    }

    // 2. Backend reachability (non-blocking — /ping may not exist)
    try {
      final prefs = await SharedPreferences.getInstance();
      final backendUrl = prefs.getString('np_backend_url');

      if (backendUrl != null && backendUrl.isNotEmpty) {
        final pingStart = DateTime.now();
        final pingUri = _joinUrl(backendUrl, '/ping');
        final response = await http
            .get(pingUri)
            .timeout(const Duration(seconds: 5));
        final latency = DateTime.now().difference(pingStart).inMilliseconds;

        checks['backend_reachable'] = response.statusCode == 200;
        checks['backend_latency_ms'] = latency;

        if (response.statusCode != 200) {
          warnings.add('Backend /ping returned ${response.statusCode}');
        }

        if (latency > 3000) {
          warnings.add('High latency: ${latency}ms - payments may be slow');
        }
      } else {
        errors.add('Backend URL missing - cannot check reachability');
      }
    } catch (e) {
      // /ping timeout or DNS failure is a warning, not a fatal error.
      // The actual payment endpoints may still work fine.
      warnings.add('Backend /ping unreachable: $e');
      checks['backend_reachable'] = false;
    }

    // 3. NearPay API reachability
    try {
      const nearPayApiUrl = 'https://api.nearpay.io/health';
      final response = await http
          .get(Uri.parse(nearPayApiUrl))
          .timeout(const Duration(seconds: 5));
      checks['nearpay_api_reachable'] = response.statusCode == 200;
    } catch (e) {
      warnings.add('Could not verify NearPay API: $e');
    }

    // 4. NearPay SDK endpoint reachability
    // This check is advisory only. Endpoint routing can change by SDK/env, so
    // avoid blocking payments based on this probe alone.
    try {
      final prefs = await SharedPreferences.getInstance();
      final env = prefs.getString('np_environment')?.toLowerCase();
      final host = env == 'sandbox' ? '158.101.242.225' : 'api.nearpay.io';
      final socket = await Socket.connect(
        host,
        443,
        timeout: const Duration(seconds: 5),
      );
      socket.destroy();
      checks['nearpay_sdk_server_reachable'] = true;
      checks['nearpay_sdk_server_host'] = host;
    } catch (e) {
      checks['nearpay_sdk_server_reachable'] = false;
      warnings.add('Could not verify NearPay SDK endpoint reachability: $e');
    }

    return NetworkCheckResult(
      checks: checks,
      warnings: warnings,
      errors: errors,
      isReachable: errors.isEmpty,
    );
  }

  Future<bool> _isNfcEnabled() async {
    final availability = await NfcManager.instance.checkAvailability();
    return availability == NfcAvailability.enabled;
  }

  Future<int> _getAndroidVersion() async {
    if (!Platform.isAndroid) return 0;
    final info = await DeviceInfoPlugin().androidInfo;
    return info.version.sdkInt;
  }

  Future<bool> _checkBluetooth() async {
    if (!Platform.isAndroid) return false;
    try {
      final status = await Permission.bluetooth.status;
      if (status.isGranted) return true;
      final connectStatus = await Permission.bluetoothConnect.status;
      return connectStatus.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkGPS() async {
    if (!Platform.isAndroid) return false;
    try {
      final status = await Permission.location.serviceStatus;
      return status.isEnabled;
    } catch (_) {
      return false;
    }
  }

  Uri _joinUrl(String base, String path) {
    final trimmed = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$trimmed$normalized');
  }
}
