import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'nearpay_preflight.dart';

/// Track NearPay performance and reliability metrics
class NearPayTelemetry {
  static Future<void> logPreFlightResult(PreFlightResult result) async {
    final payload = {
      'success': result.success,
      'failed_at': result.failedAt,
      'errors': result.errors,
      'warnings': result.warnings,
      'timestamp': DateTime.now().toIso8601String(),
      'device_model': await _getDeviceModel(),
      'android_version': await _getAndroidVersion(),
      'details': result.toJson(),
    };

    await _sendToBackend('/nearpay/telemetry/preflight', payload);
  }

  static Future<void> logPaymentAttempt({
    required bool success,
    required Duration duration,
    String? errorCode,
  }) async {
    final payload = {
      'success': success,
      'duration_ms': duration.inMilliseconds,
      'error_code': errorCode,
      'timestamp': DateTime.now().toIso8601String(),
      'device_model': await _getDeviceModel(),
      'android_version': await _getAndroidVersion(),
    };

    await _sendToBackend('/nearpay/telemetry/payment', payload);
  }

  static Future<void> _sendToBackend(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('np_backend_url');
      final authToken = prefs.getString('np_auth_token');
      if (baseUrl == null || baseUrl.isEmpty) return;

      final uri = _joinUrl(baseUrl, path);
      final headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };
      if (authToken != null && authToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      await http
          .post(uri, headers: headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[NearPayTelemetry] Failed to send telemetry: $e');
    }
  }

  static Future<String> _getDeviceModel() async {
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        return '${info.manufacturer} ${info.model}';
      }
      return Platform.operatingSystem;
    } catch (_) {
      return 'unknown';
    }
  }

  static Future<int> _getAndroidVersion() async {
    try {
      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        return info.version.sdkInt;
      }
    } catch (_) {
      return 0;
    }
    return 0;
  }

  static Uri _joinUrl(String base, String path) {
    final trimmed = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$trimmed$normalized');
  }
}
