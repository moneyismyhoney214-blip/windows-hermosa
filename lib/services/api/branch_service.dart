import 'dart:async';
import 'package:flutter/foundation.dart';
import 'base_client.dart';
import 'api_constants.dart';
import 'package:hermosa_pos/services/cache_service.dart';
import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:hermosa_pos/services/offline/offline_pos_database.dart';
import 'package:hermosa_pos/services/offline/connectivity_service.dart';
import 'package:hermosa_pos/locator.dart';

/// Service for branch-specific operations and settings
class BranchService {
  final BaseClient _client = BaseClient();
  final CacheService _cache = getIt<CacheService>();
  final OfflineDatabaseService _offlineDb = OfflineDatabaseService();
  final OfflinePosDatabase _posDb = OfflinePosDatabase();
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

  /// Cached pay methods result to avoid redundant API calls
  Map<String, bool>? _cachedPayMethods;
  DateTime? _payMethodsCacheTime;

  /// Cached branch settings (invoice_language, etc.) — 10 min TTL
  Map<String, dynamic>? _cachedBranchSettings;
  DateTime? _branchSettingsCacheTime;
  static const int _branchSettingsTtlMinutes = 10;

  /// Synchronous access to the full cached branch settings map.
  Map<String, dynamic>? get cachedBranchSettings => _cachedBranchSettings;

  /// Cached branch receipt info (seller, address, logo — both AR and EN)
  Map<String, dynamic>? _cachedBranchReceiptInfo;

  /// Synchronous access to cached branch receipt info.
  Map<String, dynamic>? get cachedBranchReceiptInfo => _cachedBranchReceiptInfo;

  /// Fetch and cache full branch info for receipts.
  /// Call once at startup; subsequent access via [cachedBranchReceiptInfo].
  Future<Map<String, dynamic>> fetchAndCacheBranchReceiptInfo() async {
    if (_cachedBranchReceiptInfo != null) return _cachedBranchReceiptInfo!;
    if (ApiConstants.branchId <= 0) return {};

    try {
      // Fetch Arabic only — NEVER change global Accept-Language
      final arInfo = _unwrapBranchData(await getBranchInfo(ApiConstants.branchId));

      final receiptInfo = <String, dynamic>{
        'branch': arInfo,
      };

      // Extract English from bilingual fields (e.g. "تكانة | Takana")
      final sellerName = arInfo['seller_name']?.toString() ?? '';
      if (sellerName.contains('|')) {
        receiptInfo['seller_name_en'] = sellerName.split('|').last.trim();
      } else if (sellerName.contains(' - ')) {
        receiptInfo['seller_name_en'] = sellerName.split(' - ').last.trim();
      }

      _cachedBranchReceiptInfo = receiptInfo;
      debugPrint('✅ Branch receipt info cached');
      return receiptInfo;
    } catch (e) {
      debugPrint('⚠️ Failed to fetch branch receipt info: $e');
      return _cachedBranchReceiptInfo ?? {};
    }
  }

  Map<String, dynamic> _unwrapBranchData(Map<String, dynamic> response) {
    dynamic current = response;
    for (var i = 0; i < 6; i++) {
      if (current is! Map) break;
      final map = current is Map<String, dynamic>
          ? current
          : (current as Map<dynamic, dynamic>).map((k, v) => MapEntry(k.toString(), v));
      if (map.containsKey('seller') || map.containsKey('address') || map.containsKey('mobile')) {
        return Map<String, dynamic>.from(map);
      }
      if (map['data'] != null) {
        current = map['data'];
        continue;
      }
      return Map<String, dynamic>.from(map);
    }
    return {};
  }

  /// Get branch settings (pay methods, required fields, etc.) - offline-first
  /// Results are cached in memory for [_branchSettingsTtlMinutes] minutes.
  Future<Map<String, dynamic>> getBranchSettings({bool forceRefresh = false}) async {
    // Return cached result if fresh
    if (!forceRefresh &&
        _cachedBranchSettings != null &&
        _branchSettingsCacheTime != null &&
        DateTime.now().difference(_branchSettingsCacheTime!).inMinutes <
            _branchSettingsTtlMinutes) {
      return _cachedBranchSettings!;
    }

    if (ApiConstants.branchId <= 0) {
      if (kDebugMode) debugPrint('⚠️ Skip branch settings: branchId is 0');
      return {};
    }

    if (_connectivity.isOffline) {
      final offline = await _getBranchSettingsOffline();
      _cachedBranchSettings = offline;
      _branchSettingsCacheTime = DateTime.now();
      return offline;
    }

    final token = _client.getToken();
    if (token == null || token.isEmpty) {
      if (kDebugMode) debugPrint('⚠️ Skip branch settings: no auth token');
      final offline = await _getBranchSettingsOffline();
      _cachedBranchSettings = offline;
      _branchSettingsCacheTime = DateTime.now();
      return offline;
    }

    // Race all endpoints in parallel — first successful response wins
    final endpoints = [
      '/seller/branches/${ApiConstants.branchId}/settings',
      '/seller/branch-settings/${ApiConstants.branchId}',
      '/seller/branch/setting/${ApiConstants.branchId}',
      ApiConstants.branchSettingEndpoint,
    ];

    final completer = Completer<Map<String, dynamic>>();
    var failCount = 0;

    for (final endpoint in endpoints) {
      _client
          .get(endpoint, skipGlobalAuth: true)
          .timeout(const Duration(seconds: 8))
          .then((response) {
        final extracted = _extractSettingsPayload(response);
        if (extracted.isNotEmpty && !completer.isCompleted) {
          if (kDebugMode) debugPrint('✅ Branch settings loaded from: $endpoint');
          _cachedBranchSettings = extracted;
          _branchSettingsCacheTime = DateTime.now();
          completer.complete(extracted);
          // Save to SQLite for offline (fire-and-forget)
          _offlineDb.saveBranchSettings(ApiConstants.branchId, extracted);
        } else {
          failCount++;
          if (failCount >= endpoints.length && !completer.isCompleted) {
            _getBranchSettingsOffline().then((offline) {
              _cachedBranchSettings = offline;
              _branchSettingsCacheTime = DateTime.now();
              if (!completer.isCompleted) completer.complete(offline);
            });
          }
        }
      }).catchError((_) {
        failCount++;
        if (failCount >= endpoints.length && !completer.isCompleted) {
          _getBranchSettingsOffline().then((offline) {
            _cachedBranchSettings = offline;
            _branchSettingsCacheTime = DateTime.now();
            if (!completer.isCompleted) completer.complete(offline);
          });
        }
      });
    }

    return completer.future;
  }

  /// Get invoice language settings from cached branch settings (async).
  /// Returns {primary: 'ar', secondary: 'en', allow_secondary: true} or empty.
  Future<Map<String, dynamic>> getInvoiceLanguageSettings() async {
    final settings = await getBranchSettings();
    final lang = settings['invoice_language'];
    if (lang is Map) {
      return lang.map((k, v) => MapEntry(k.toString(), v));
    }
    return const {};
  }

  /// Synchronous access to cached invoice language (for widgets that can't await).
  /// Returns empty map if not yet cached.
  Map<String, dynamic> get cachedInvoiceLanguage {
    final lang = _cachedBranchSettings?['invoice_language'];
    if (lang is Map) {
      return lang.map((k, v) => MapEntry(k.toString(), v));
    }
    return const {};
  }

  /// Whether the active branch has VAT/tax enabled. Synchronous — reads the
  /// cached branch settings + receipt info populated at session start. Used
  /// by callers that need to decide whether to add tax to a total without
  /// waiting for an API round-trip (e.g. Orders screen grand-total).
  ///
  /// Defaults to `true` to stay backwards-compatible if the cache hasn't
  /// hydrated yet; callers that care about correctness when offline should
  /// gate their logic behind an explicit `await getBranchSettings()`.
  bool get cachedHasTax {
    final flag = _findHasTax(_cachedBranchSettings) ??
        _findHasTax(_cachedBranchReceiptInfo);
    return flag ?? true;
  }

  /// Tax rate in the `0.0 – 1.0` range. Returns `0.0` when the branch has
  /// tax disabled. Reads from the same cached payload as [cachedHasTax].
  double get cachedTaxRate {
    if (!cachedHasTax) return 0.0;
    final rate = _findTaxRate(_cachedBranchSettings) ??
        _findTaxRate(_cachedBranchReceiptInfo);
    if (rate == null) return 0.15; // legacy default
    return rate.clamp(0.0, 1.0).toDouble();
  }

  bool? _findHasTax(dynamic payload) {
    if (payload is! Map) return null;
    for (final key in const [
      'has_tax',
      'hasTax',
      'tax_enabled',
      'is_tax_enabled',
    ]) {
      if (payload.containsKey(key)) {
        final v = payload[key];
        if (v is bool) return v;
        if (v is num) return v != 0;
        if (v is String) {
          final s = v.trim().toLowerCase();
          if (['1', 'true', 'yes', 'on', 'active'].contains(s)) return true;
          if (['0', 'false', 'no', 'off', 'inactive'].contains(s)) return false;
        }
      }
    }
    for (final nested in const [
      'tax',
      'taxObject',
      'tax_object',
      'branch',
      'data',
      'settings',
    ]) {
      final inner = _findHasTax(payload[nested]);
      if (inner != null) return inner;
    }
    return null;
  }

  double? _findTaxRate(dynamic payload) {
    if (payload is! Map) return null;
    for (final key in const [
      'tax_percentage',
      'taxPercentage',
      'tax_rate',
      'taxRate',
      'tax',
    ]) {
      if (payload.containsKey(key)) {
        final v = payload[key];
        if (v is num) {
          final d = v.toDouble();
          return d > 1.0 ? d / 100.0 : d;
        }
        if (v is String) {
          final parsed = double.tryParse(v.trim());
          if (parsed != null) {
            return parsed > 1.0 ? parsed / 100.0 : parsed;
          }
        }
      }
    }
    for (final nested in const [
      'taxObject',
      'tax_object',
      'branch',
      'data',
      'settings',
    ]) {
      final inner = _findTaxRate(payload[nested]);
      if (inner != null) return inner;
    }
    return null;
  }

  Future<Map<String, dynamic>> _getBranchSettingsOffline() async {
    try {
      final local = await _offlineDb.getBranchSettings(ApiConstants.branchId);
      if (local != null && local.isNotEmpty) return local;
    } catch (_) {}
    // Try bundled POS database
    try {
      final posBranch = await _posDb.getBranch(ApiConstants.branchId);
      if (posBranch != null && posBranch.isNotEmpty) return posBranch;
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
      if (kDebugMode) debugPrint('⚠️ Unable to load branch logo: $e');
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
  Future<Map<String, bool>> getEnabledPayMethods({bool forceRefresh = false}) async {
    _lastPayMethodsNotice = null;

    // Return cached result if fresh (5 minutes TTL)
    if (!forceRefresh &&
        _cachedPayMethods != null &&
        _payMethodsCacheTime != null &&
        DateTime.now().difference(_payMethodsCacheTime!).inMinutes < 5) {
      return _cachedPayMethods!;
    }

    try {
      // 1) Source of truth: dedicated payMethods endpoint used by POS Postman collection
      final typeCandidates = ['incomings', 'outgoings', 'online'];
      for (final type in typeCandidates) {
        try {
          final endpoint = '${ApiConstants.payMethodsEndpoint}?type=$type';
          final payMethodsResponse = await _client.get(endpoint);
          final fromPayMethodsApi = _parseEnabledPayMethods(payMethodsResponse);
          if (fromPayMethodsApi.isNotEmpty) {
            if (kDebugMode) debugPrint(
                '✅ Payment methods loaded from payMethods endpoint (type=$type)');
            _cachedPayMethods = fromPayMethodsApi;
            _payMethodsCacheTime = DateTime.now();
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
          if (kDebugMode) debugPrint('✅ Payment methods loaded from branch settings');
          _cachedPayMethods = fromSettings;
          _payMethodsCacheTime = DateTime.now();
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
      if (kDebugMode) debugPrint('Error getting enabled pay methods: $e');
      _lastPayMethodsNotice ??=
          'تعذر تحميل طرق الدفع المفعّلة. تحقق من إعدادات الفرع.';
      return Map<String, bool>.from(_noEnabledPayMethods);
    } catch (e) {
      if (kDebugMode) debugPrint('Error getting enabled pay methods: $e');
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
      'petty_cash': false,
      'pay_later': false,
      'tabby': false,
      'tamara': false,
      'keeta': false,
      'my_fatoorah': false,
      'jahez': false,
      'talabat': false,
      'hunger_station': false,
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
      case 'petty_cash':
      case 'pettycash':
        return 'petty_cash';
      case 'pay_later':
      case 'deferred':
      case 'pay_later_payment':
        return 'pay_later';
      case 'tabby':
      case 'taby':
      case 'tabby_payment':
        return 'tabby';
      case 'tamara':
      case 'tamara_payment':
        return 'tamara';
      case 'keeta':
      case 'kita':
      case 'keeta_payment':
        return 'keeta';
      case 'my_fatoorah':
      case 'myfatoora':
      case 'myfatoorah':
      case 'my_fatoora':
        return 'my_fatoorah';
      case 'jahez':
      case 'gahez':
        return 'jahez';
      case 'talabat':
        return 'talabat';
      case 'hunger_station':
      case 'hungerstation':
      case 'hunger':
        return 'hunger_station';
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
