import 'base_client.dart';
import 'api_constants.dart';
import 'package:hermosa_pos/services/cache_service.dart';
import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:hermosa_pos/services/offline/connectivity_service.dart';
import 'package:hermosa_pos/locator.dart';

/// Service for branch-specific operations and settings
class BranchService {
  final BaseClient _client = BaseClient();
  final CacheService _cache = getIt<CacheService>();
  final OfflineDatabaseService _offlineDb = OfflineDatabaseService();
  final ConnectivityService _connectivity = ConnectivityService();
  String? _lastPayMethodsNotice;
  String? get lastPayMethodsNotice => _lastPayMethodsNotice;

  static const Map<String, bool> _noEnabledPayMethods = {
    'cash': false,
    'card': false,
    'mada': false,
    'visa': false,
    'benefit': false,
    'stc': false,
    'bank_transfer': false,
    'wallet': false,
    'cheque': false,
  };

  /// Get branch settings (pay methods, required fields, etc.) - offline-first
  Future<Map<String, dynamic>> getBranchSettings() async {
    if (ApiConstants.branchId <= 0) {
      print('⚠️ Skip branch settings: branchId is 0');
      return {};
    }

    if (_connectivity.isOffline) {
      return _getBranchSettingsOffline();
    }

    final token = _client.getToken();
    if (token == null || token.isEmpty) {
      print('⚠️ Skip branch settings: no auth token');
      return _getBranchSettingsOffline();
    }

    // Try multiple possible endpoint paths
    final endpoints = [
      '/seller/branches/${ApiConstants.branchId}/settings',
      '/seller/branch-settings/${ApiConstants.branchId}',
      '/seller/branch/setting/${ApiConstants.branchId}',
      ApiConstants.branchSettingEndpoint,
    ];

    for (final endpoint in endpoints) {
      try {
        final response = await _client.get(endpoint, skipGlobalAuth: true);
        final extracted = _extractSettingsPayload(response);
        if (extracted.isNotEmpty) {
          print('✅ Branch settings loaded from: $endpoint');
          // Save to SQLite for offline
          await _offlineDb.saveBranchSettings(ApiConstants.branchId, extracted);
          return extracted;
        }
      } catch (e) {
        print('⚠️ Branch settings endpoint failed ($endpoint): $e');
        continue;
      }
    }

    // All endpoints failed — serve from offline database
    return _getBranchSettingsOffline();
  }

  Future<Map<String, dynamic>> _getBranchSettingsOffline() async {
    try {
      final local = await _offlineDb.getBranchSettings(ApiConstants.branchId);
      if (local != null && local.isNotEmpty) return local;
    } catch (_) {}
    return {};
  }

  Future<Map<String, dynamic>> getBranchInfo(int branchId) async {
    final endpoint = '/seller/get_branches/$branchId';
    final response = await _client.get(endpoint);
    if (response is Map<String, dynamic>) {
      return response;
    }
    if (response is Map) {
      return response.map((key, value) => MapEntry(key.toString(), value));
    }
    return {};
  }

  Future<String> getBranchLogoUrl(int branchId) async {
    try {
      final response = await getBranchInfo(branchId);
      Map<String, dynamic> current = response;
      for (var i = 0; i < 6; i++) {
        if (current['logo'] != null) {
          return current['logo'].toString();
        }
        final data = current['data'];
        if (data is Map) {
          current = data.map((k, v) => MapEntry(k.toString(), v));
          continue;
        }
        break;
      }
    } catch (e) {
      print('⚠️ Unable to load branch logo: $e');
    }
    return '';
  }

  Future<Map<String, bool>?> getCachedPayMethods() async {
    final cached = await _cache.get('pay_methods');
    if (cached is Map) {
      try {
        return cached.map((k, v) => MapEntry(k.toString(), v == true));
      } catch (_) {}
    }
    return null;
  }

  Map<String, dynamic> _extractSettingsPayload(dynamic raw) {
    dynamic current = raw;
    for (var i = 0; i < 8; i++) {
      if (current is! Map) break;
      final map = current is Map<String, dynamic>
          ? current
          : current.map((key, value) => MapEntry(key.toString(), value));

      final hasSettingsKeys =
          map.containsKey('pay_methods') || map.containsKey('redirects');
      if (hasSettingsKeys) return Map<String, dynamic>.from(map);

      if (map['data'] != null) {
        current = map['data'];
        continue;
      }

      return Map<String, dynamic>.from(map);
    }
    return {};
  }

  /// Get enabled payment methods for the branch from backend configuration.
  Future<Map<String, bool>> getEnabledPayMethods() async {
    _lastPayMethodsNotice = null;
    try {
      // 1) Source of truth: dedicated payMethods endpoint used by POS Postman collection
      final typeCandidates = ['incomings', 'outgoings', 'online'];
      for (final type in typeCandidates) {
        try {
          final endpoint = '${ApiConstants.payMethodsEndpoint}?type=$type';
          final payMethodsResponse = await _client.get(endpoint);
          final fromPayMethodsApi = _parseEnabledPayMethods(payMethodsResponse);
          if (fromPayMethodsApi.isNotEmpty) {
            print(
                '✅ Payment methods loaded from payMethods endpoint (type=$type)');
            return fromPayMethodsApi;
          }
        } on ApiException catch (e) {
          if (e.statusCode == 422) {
            _lastPayMethodsNotice =
                'طرق الدفع غير مُعدّة لهذا الفرع. يرجى تفعيل طريقة دفع من لوحة التحكم.';
            return Map<String, bool>.from(_noEnabledPayMethods);
          }
          // Try next allowed type
        } catch (_) {
          // Try next allowed type
        }
      }

      // 2) Fallback: branch settings
      final settings = await getBranchSettings();
      if (settings.containsKey('pay_methods')) {
        final fromSettings = _parseEnabledPayMethods(settings['pay_methods']);
        if (fromSettings.isNotEmpty) {
          print('✅ Payment methods loaded from branch settings');
          return fromSettings;
        }
      }

      // Strict fallback: when backend methods are unavailable, don't
      // assume enabled methods to avoid sending invalid payment payloads.
      _lastPayMethodsNotice ??=
          'تعذر تحميل طرق الدفع المفعّلة. تحقق من إعدادات الفرع.';
      return Map<String, bool>.from(_noEnabledPayMethods);
    } on ApiException catch (e) {
      if (e.statusCode == 422) {
        _lastPayMethodsNotice =
            'طرق الدفع غير مُعدّة لهذا الفرع. يرجى تفعيل طريقة دفع من لوحة التحكم.';
        return Map<String, bool>.from(_noEnabledPayMethods);
      }
      print('Error getting enabled pay methods: $e');
      _lastPayMethodsNotice ??=
          'تعذر تحميل طرق الدفع المفعّلة. تحقق من إعدادات الفرع.';
      return Map<String, bool>.from(_noEnabledPayMethods);
    } catch (e) {
      print('Error getting enabled pay methods: $e');
      _lastPayMethodsNotice ??=
          'تعذر تحميل طرق الدفع المفعّلة. تحقق من إعدادات الفرع.';
      return Map<String, bool>.from(_noEnabledPayMethods);
    }
  }

  Map<String, bool> _parseEnabledPayMethods(dynamic raw) {
    final enabled = <String, bool>{
      'cash': false,
      'card': false,
      'mada': false,
      'visa': false,
      'benefit': false,
      'stc': false,
      'bank_transfer': false,
      'wallet': false,
      'cheque': false,
    };

    bool hasAnyMethod = false;

    void mark(dynamic key, dynamic value) {
      final normalized = _normalizePayMethodKey(key?.toString());
      if (normalized == null) return;
      final isEnabled = _toEnabled(value);
      enabled[normalized] = (enabled[normalized] ?? false) || isEnabled;
      hasAnyMethod = true;
    }

    dynamic payload = raw;
    if (payload is Map && payload['data'] != null) {
      payload = payload['data'];
    }

    if (payload is Map) {
      payload.forEach((key, value) {
        if (value is Map) {
          final keyFromValue = _firstNonEmptyString([
            value['pay_method'],
            value['method'],
            value['key'],
            value['value'],
            value['code'],
            value['slug'],
            value['id'],
            key,
          ]);
          mark(
              keyFromValue,
              value['enabled'] ??
                  value['is_active'] ??
                  value['active'] ??
                  value['status'] ??
                  true);
        } else {
          mark(key, value);
        }
      });
    } else if (payload is List) {
      for (final item in payload) {
        if (item is Map) {
          final key = _firstNonEmptyString([
            item['pay_method'],
            item['method'],
            item['key'],
            item['value'],
            item['code'],
            item['slug'],
            item['id'],
            item['name_en'],
            item['name'],
          ]);
          final value = item['enabled'] ??
              item['is_active'] ??
              item['active'] ??
              item['status'] ??
              true;
          mark(key, value);
        } else {
          mark(item, true);
        }
      }
    } else if (payload is String) {
      mark(payload, true);
    }

    if (!hasAnyMethod) return {};

    // Keep strict behavior: if everything is disabled, respect backend config.
    if (!enabled.containsValue(true)) {
      return Map<String, bool>.from(_noEnabledPayMethods);
    }

    return enabled;
  }

  bool _toEnabled(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      return v == '1' || v == 'true' || v == 'enabled' || v == 'active';
    }
    return value != null;
  }

  String? _normalizePayMethodKey(String? raw) {
    if (raw == null) return null;
    final key =
        raw.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    switch (key) {
      case 'cash':
      case 'cash_payment':
        return 'cash';
      case 'card':
      case 'credit_card':
      case 'debit_card':
        return 'card';
      case 'mada':
        return 'mada';
      case 'visa':
      case 'mastercard':
        return 'visa';
      case 'benefit':
        return 'benefit';
      case 'stc':
      case 'stc_pay':
        return 'stc';
      case 'bank':
      case 'transfer':
      case 'bank_transfer':
        return 'bank_transfer';
      case 'wallet':
      case 'e_wallet':
      case 'electronic_wallet':
        return 'wallet';
      case 'cheque':
      case 'check':
        return 'cheque';
      default:
        return null;
    }
  }

  String? _firstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      final str = value?.toString().trim();
      if (str != null && str.isNotEmpty && str != 'null') {
        return str;
      }
    }
    return null;
  }
}
