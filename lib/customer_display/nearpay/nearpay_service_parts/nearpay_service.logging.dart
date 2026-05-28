part of '../nearpay_service.dart';

// Pure logging + masking + JWT-decode helpers extracted from
// nearpay_service.dart. None of them touch instance state; they're
// moved as an extension solely to drop the host file below the
// god-file threshold while keeping the same `_npLog(...)` invocation
// syntax everywhere they're called.

extension _NearPayServiceLogging on NearPayService {
  void _npLog(String message, {Object? error, StackTrace? stackTrace}) {
    final timestamp = DateTime.now().toIso8601String();
    final fullMessage = '[$timestamp] $message';

    developer.log(
      '[NearPay] $fullMessage',
      name: 'NearPay',
      error: error,
      stackTrace: stackTrace,
    );
    AppLogger.logNearPay(fullMessage);

    // Also print to console for immediate visibility
    if (kDebugMode) {
      print('🔷 NearPay: $fullMessage');
      if (error != null) {
        print('   Error: $error');
        if (stackTrace != null) {
          print('   Stack: $stackTrace');
        }
      }
    }
  }

  void _npLogDetail(String title, Map<String, dynamic> details) {
    final timestamp = DateTime.now().toIso8601String();
    final detailsStr = details.entries
        .map((e) => '   ${e.key}: ${e.value}')
        .join('\n');
    final fullMessage = '[$timestamp] 📋 $title\n$detailsStr';

    developer.log('[NearPay] $fullMessage', name: 'NearPay');
    AppLogger.logNearPay(fullMessage);

    if (kDebugMode) {
      debugPrint('📋 NearPay: $title');
      details.forEach((key, value) {
        debugPrint('   $key: $value');
      });
    }
  }

  Future<void> _logDeveloperCertLoaded() async {
    try {
      final cert = await rootBundle.load('assets/certs/developer_cert.pem');
      developer.log(
        '[NearPay] developer_cert.pem loaded — ${cert.lengthInBytes} bytes',
        name: 'NearPay',
      );
      AppLogger.logNearPay(
        'developer_cert.pem loaded — ${cert.lengthInBytes} bytes',
      );
    } catch (e, stackTrace) {
      developer.log(
        '[NearPay] developer_cert.pem load failed: $e',
        name: 'NearPay',
        error: e,
        stackTrace: stackTrace,
      );
      AppLogger.logNearPay('developer_cert.pem load failed: $e');
      if (kDebugMode) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: e,
            stack: stackTrace,
            library: 'NearPay',
            context: ErrorDescription('developer_cert.pem load failed'),
          ),
        );
      }
    }
  }

  String _mask(String? value, {int visible = 4}) {
    if (value == null || value.isEmpty) return 'MISSING';
    if (value.length <= visible) {
      return '${value.substring(0, value.length)}***';
    }
    return '${value.substring(0, visible)}***';
  }

  String _maskId(String? value) => _mask(value, visible: 6);

  /// Safely decode base64 JWT part (for logging header/payload structure)
  String _safeBase64Decode(String part) {
    try {
      final normalized = base64Url.normalize(part);
      final decoded = utf8.decode(base64Url.decode(normalized));
      // Return max 200 chars
      return decoded.length > 200 ? '${decoded.substring(0, 200)}...' : decoded;
    } catch (e) {
      return 'DECODE_ERROR: $e';
    }
  }

  /// Extract only the keys from JWT payload (not values — no secrets)
  String _safePayloadKeys(String part) {
    try {
      final normalized = base64Url.normalize(part);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final map = jsonDecode(decoded);
      if (map is Map) {
        return _extractKeys(map).join(', ');
      }
      return 'NOT_A_MAP';
    } catch (e) {
      return 'DECODE_ERROR: $e';
    }
  }

  /// Recursively extract keys from nested map
  List<String> _extractKeys(Map map, [String prefix = '']) {
    final keys = <String>[];
    for (final entry in map.entries) {
      final key = prefix.isEmpty ? '${entry.key}' : '$prefix.${entry.key}';
      keys.add(key);
      if (entry.value is Map) {
        keys.addAll(_extractKeys(entry.value as Map, key));
      }
    }
    return keys;
  }
}
