import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hermosa_pos/locator.dart';
import 'package:hermosa_pos/services/cache_service.dart';
import 'package:hermosa_pos/services/logger_service.dart';
import 'package:hermosa_pos/services/offline/connectivity_service.dart';
import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:hermosa_pos/services/offline/offline_pos_database.dart';
import 'package:hermosa_pos/services/whatsapp_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_constants.dart';
import 'auth_service.dart';
import 'base_client.dart';

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
  DateTime? _branchReceiptInfoCacheTime;

  /// Receipt cache TTL — beyond this we re-fetch the canonical data so
  /// a branch logo / name update doesn't show stale on the printed
  /// receipt for the rest of the session. 30 minutes is short enough
  /// for an admin-initiated change to propagate within one shift.
  static const int _branchReceiptInfoTtlMinutes = 30;

  /// Synchronous access to cached branch receipt info. Returns null
  /// once the cache is older than [_branchReceiptInfoTtlMinutes] so
  /// callers transparently re-fetch via [fetchAndCacheBranchReceiptInfo]
  /// instead of printing a 6-month-old logo.
  Map<String, dynamic>? get cachedBranchReceiptInfo {
    if (_cachedBranchReceiptInfo == null) return null;
    final ts = _branchReceiptInfoCacheTime;
    if (ts == null) return _cachedBranchReceiptInfo;
    final age = DateTime.now().difference(ts).inMinutes;
    if (age > _branchReceiptInfoTtlMinutes) return null;
    return _cachedBranchReceiptInfo;
  }

  /// Wipe every per-session cache. Called on logout / branch switch so
  /// the next user/branch starts cold instead of inheriting the prior
  /// shift's pay methods, branch settings, receipt logo, or tax notice.
  /// Without this, a Sunmi tablet handed off between cashiers in
  /// different branches would print receipts with the wrong logo or
  /// gate NearPay against the wrong branch's settings.
  void clearSessionCaches() {
    _cachedPayMethods = null;
    _payMethodsCacheTime = null;
    _cachedBranchSettings = null;
    _branchSettingsCacheTime = null;
    _cachedBranchReceiptInfo = null;
    _branchReceiptInfoCacheTime = null;
    _lastPayMethodsNotice = null;
    debugPrint('🧹 BranchService session caches cleared');
  }

  /// Fetch and cache full branch info for receipts.
  /// Call once at startup; subsequent access via [cachedBranchReceiptInfo].
  Future<Map<String, dynamic>> fetchAndCacheBranchReceiptInfo() async {
    if (_cachedBranchReceiptInfo != null) {
      // Invalidate cache from older builds missing `branch_logo_url`.
      final hasLogoInfo =
          _cachedBranchReceiptInfo!.containsKey('branch_logo_url') ||
              _cachedBranchReceiptInfo!.containsKey('profile_branch_name');
      if (!hasLogoInfo) {
        _cachedBranchReceiptInfo = null;
      } else {
        // Re-mirror on cache hits so out-of-band CDS prefs wipes are refreshed.
        unawaited(
          _ensureProfileNameThenMirror(_cachedBranchReceiptInfo!),
        );
        return _cachedBranchReceiptInfo!;
      }
    }
    if (ApiConstants.branchId <= 0) return {};

    // Parallel: /seller/get_branches/<id> 500s on some accounts and must not block /seller/branches.
    final arInfoFuture = () async {
      try {
        return _unwrapBranchData(
          await getBranchInfo(ApiConstants.branchId),
        );
      } catch (e) {
        debugPrint('⚠️ getBranchInfo failed: $e');
        return <String, dynamic>{};
      }
    }();
    final branchSummaryFuture =
        _fetchBranchSummary(ApiConstants.branchId);

    final arInfo = await arInfoFuture;
    final summary = await branchSummaryFuture;
    final profileName = summary['name'] ?? '';
    final logoUrl = summary['logo'] ?? '';

    final receiptInfo = <String, dynamic>{
      'branch': arInfo,
    };

    // Extract English from bilingual fields (e.g. "تكانة | Takana").
    final sellerName = arInfo['seller_name']?.toString() ?? '';
    if (sellerName.contains('|')) {
      receiptInfo['seller_name_en'] = sellerName.split('|').last.trim();
    } else if (sellerName.contains(' - ')) {
      receiptInfo['seller_name_en'] = sellerName.split(' - ').last.trim();
    }

    // /seller/branches returns canonical restaurant name + logo (CDS header).
    if (profileName.isNotEmpty) {
      receiptInfo['profile_branch_name'] = profileName;
    }
    if (logoUrl.isNotEmpty) {
      receiptInfo['branch_logo_url'] = logoUrl;
    }

    _cachedBranchReceiptInfo = receiptInfo;
    _branchReceiptInfoCacheTime = DateTime.now();

    // Mirror to SharedPreferences so CDS secondary engine can read without MethodChannel.
    unawaited(_mirrorSellerNameToPrefs(arInfo, receiptInfo));

    debugPrint(
      '✅ Branch receipt info cached (name="$profileName", logo="$logoUrl")',
    );
    return receiptInfo;
  }

  Future<void> _ensureProfileNameThenMirror(
    Map<String, dynamic> receiptInfo,
  ) async {
    try {
      final hasName =
          (receiptInfo['profile_branch_name']?.toString().trim() ?? '').isNotEmpty;
      final hasLogo =
          (receiptInfo['branch_logo_url']?.toString().trim() ?? '').isNotEmpty;
      if (!hasName || !hasLogo) {
        final summary = await _fetchBranchSummary(ApiConstants.branchId);
        if (!hasName && (summary['name'] ?? '').isNotEmpty) {
          receiptInfo['profile_branch_name'] = summary['name'];
        }
        if (!hasLogo && (summary['logo'] ?? '').isNotEmpty) {
          receiptInfo['branch_logo_url'] = summary['logo'];
        }
      }
      final branch = receiptInfo['branch'];
      if (branch is Map<String, dynamic>) {
        await _mirrorSellerNameToPrefs(branch, receiptInfo);
      } else {
        await _mirrorSellerNameToPrefs(<String, dynamic>{}, receiptInfo);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ re-mirror seller name failed: $e');
    }
  }

  /// Fetch the canonical restaurant name + uploaded logo from
  /// `/seller/branches` for the given [branchId]. Returns
  /// `{'name': '<restaurant name>', 'logo': '<absolute url>'}` — either
  /// value may be empty if the entry is missing or the call fails.
  Future<Map<String, String>> _fetchBranchSummary(int branchId) async {
    try {
      // WAITER role 401s on /seller/branches; official frontend uses /seller/profile/branches.
      final endpoint = _isWaiter()
          ? ApiConstants.profileBranchesEndpoint
          : ApiConstants.branchesEndpoint;
      final response = await _client.get(endpoint);
      final list = _coerceBranchList(response);
      debugPrint(
          '🏷️ /seller/branches → ${list.length} entries, looking for id=$branchId');
      Map<String, dynamic>? match;
      for (final item in list) {
        final id = item['id'];
        final isMatch = id is num
            ? id.toInt() == branchId
            : int.tryParse(id?.toString() ?? '') == branchId;
        if (isMatch) {
          match = item;
          break;
        }
      }
      match ??= list.isNotEmpty ? list.first : null;
      if (match == null) return const {'name': '', 'logo': ''};
      final name = match['name']?.toString().trim() ?? '';
      final logo = match['logo']?.toString().trim() ?? '';
      debugPrint('🏷️ /seller/branches match: name="$name" logo="$logo"');
      return {'name': name, 'logo': logo};
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ /seller/branches fetch failed: $e');
    }
    return const {'name': '', 'logo': ''};
  }

  /// Normalise a `/seller/profile/branches` response into a flat list of
  /// branch maps regardless of the wrapper shape the API returns.
  List<Map<String, dynamic>> _coerceBranchList(dynamic raw) {
    if (raw is List) {
      final out = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is Map) {
          out.add(item.map((k, v) => MapEntry(k.toString(), v)));
        }
      }
      return out;
    }
    if (raw is Map) {
      final map = raw.map((k, v) => MapEntry(k.toString(), v));
      for (final key in const ['data', 'branches', 'items', 'results']) {
        final nested = _coerceBranchList(map[key]);
        if (nested.isNotEmpty) return nested;
      }
      if (map['id'] != null) return [map];
    }
    return const [];
  }

  Future<void> _mirrorSellerNameToPrefs(
    Map<String, dynamic> arInfo,
    Map<String, dynamic> receiptInfo,
  ) async {
    try {
      // Prefer /seller/profile/branches name — canonical branch display name.
      final profileName =
          receiptInfo['profile_branch_name']?.toString().trim() ?? '';

      final rawName = arInfo['seller_name']?.toString().trim() ?? '';
      String ar = profileName.isNotEmpty ? profileName : rawName;
      String en = receiptInfo['seller_name_en']?.toString().trim() ?? '';
      if (profileName.isEmpty) {
        if (rawName.contains('|')) {
          final parts = rawName.split('|');
          ar = parts.first.trim();
          if (en.isEmpty) en = parts.last.trim();
        } else if (rawName.contains(' - ')) {
          final parts = rawName.split(' - ');
          ar = parts.first.trim();
          if (en.isEmpty) en = parts.last.trim();
        }
      }
      final logoUrl =
          receiptInfo['branch_logo_url']?.toString().trim() ?? '';
      final prefs = await SharedPreferences.getInstance();
      // Never clobber populated values with empty — a failed fetch would blank CDS until cold restart.
      if (ar.isNotEmpty) {
        await prefs.setString('cds_seller_name_ar', ar);
      }
      if (en.isNotEmpty) {
        await prefs.setString('cds_seller_name_en', en);
      }
      if (logoUrl.isNotEmpty) {
        await prefs.setString('cds_seller_logo_url', logoUrl);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ mirror seller name to prefs failed: $e');
    }
  }

  Map<String, dynamic> _unwrapBranchData(Map<String, dynamic> response) {
    dynamic current = response;
    for (var i = 0; i < 6; i++) {
      if (current is! Map) break;
      final map = current is Map<String, dynamic>
          ? current
          : (current).map((k, v) => MapEntry(k.toString(), v));
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
      _seedWhatsAppCredsFromSettings(_cachedBranchSettings!);
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
      _seedWhatsAppCredsFromSettings(offline);
      return offline;
    }

    final token = _client.getToken();
    if (token == null || token.isEmpty) {
      if (kDebugMode) debugPrint('⚠️ Skip branch settings: no auth token');
      final offline = await _getBranchSettingsOffline();
      _cachedBranchSettings = offline;
      _branchSettingsCacheTime = DateTime.now();
      _seedWhatsAppCredsFromSettings(offline);
      return offline;
    }

    // Race endpoints in parallel; WAITER role skips legacy fallbacks (404 noise).
    final endpoints = _isWaiter()
        ? <String>['/seller/branches/${ApiConstants.branchId}/settings']
        : <String>[
            '/seller/branches/${ApiConstants.branchId}/settings',
            '/seller/branch-settings/${ApiConstants.branchId}',
            '/seller/branch/setting/${ApiConstants.branchId}',
            ApiConstants.branchSettingEndpoint,
          ];

    final completer = Completer<Map<String, dynamic>>();
    var failCount = 0;

    for (final endpoint in endpoints) {
      unawaited(_client
          .get(endpoint, skipGlobalAuth: true)
          .timeout(const Duration(seconds: 8))
          .then((response) {
        final extracted = _extractSettingsPayload(response);
        if (extracted.isNotEmpty && !completer.isCompleted) {
          if (kDebugMode) debugPrint('✅ Branch settings loaded from: $endpoint');
          _cachedBranchSettings = extracted;
          _branchSettingsCacheTime = DateTime.now();
          _seedWhatsAppCredsFromSettings(extracted);
          completer.complete(extracted);
          _offlineDb.saveBranchSettings(ApiConstants.branchId, extracted);
        } else {
          failCount++;
          if (failCount >= endpoints.length && !completer.isCompleted) {
            _getBranchSettingsOffline().then((offline) {
              _cachedBranchSettings = offline;
              _branchSettingsCacheTime = DateTime.now();
              _seedWhatsAppCredsFromSettings(offline);
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
      }));
    }

    return completer.future;
  }

  /// Pull `whatsapp.{instance_id, instance_token}` out of a settings
  /// payload and seed `WhatsAppService` so the WAWP API call uses the
  /// branch-owned credentials. When the new branch has no WhatsApp
  /// configuration we explicitly clear the in-memory creds so the
  /// previous branch's tokens don't leak through. User-tuned fields
  /// (country code + message template) are preserved either way.
  void _seedWhatsAppCredsFromSettings(Map<String, dynamic> settings) {
    final raw = settings['whatsapp'];
    if (raw is! Map) {
      whatsAppService.clearBackendCredentials();
      return;
    }
    final wa = raw.map((k, v) => MapEntry(k.toString(), v));
    final instanceId = wa['instance_id']?.toString().trim() ?? '';
    final accessToken =
        (wa['instance_token'] ?? wa['access_token'])?.toString().trim() ?? '';
    if (instanceId.isEmpty || accessToken.isEmpty) {
      whatsAppService.clearBackendCredentials();
      return;
    }
    whatsAppService.applyBackendCredentials(
      instanceId: instanceId,
      accessToken: accessToken,
    );
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
  /// Authoritative source is `ApiConstants.hasTax`, populated at login and
  /// refreshed via `/seller/filters/branches/{id}/getTax`. The cached
  /// settings/receipt-info payloads remain a fallback for older sessions
  /// that haven't hydrated the global yet.
  bool get cachedHasTax {
    final flag = _findHasTax(_cachedBranchSettings) ??
        _findHasTax(_cachedBranchReceiptInfo);
    return flag ?? ApiConstants.hasTax;
  }

  /// Tax rate in the `0.0 – 1.0` range. Returns `0.0` when the branch has
  /// tax disabled. Authoritative value is `ApiConstants.effectiveTaxRate`;
  /// cached payloads only matter when the global hasn't been hydrated.
  double get cachedTaxRate {
    if (!cachedHasTax) return 0.0;
    final rate = _findTaxRate(_cachedBranchSettings) ??
        _findTaxRate(_cachedBranchReceiptInfo);
    if (rate != null) return rate.clamp(0.0, 1.0).toDouble();
    return ApiConstants.effectiveTaxRate;
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
    } catch (e) {
      Log.w('branch', 'offline DB branch-settings read failed', error: e);
    }
    try {
      final posBranch = await _posDb.getBranch(ApiConstants.branchId);
      if (posBranch != null && posBranch.isNotEmpty) return posBranch;
    } catch (e) {
      Log.w('branch', 'POS DB branch read failed', error: e);
    }
    return {};
  }

  /// True when the signed-in user has the WAITER role. Several
  /// cashier-flow endpoints (`/seller/get_branches/{id}`,
  /// `/seller/branches/{id}/settings`, `/seller/filters/branches/{id}/getTax`,
  /// `/seller/branches`) are not available to a WAITER — the official
  /// frontend skips them and relies on the login payload + the
  /// `/seller/profile/branches` endpoint instead. We mirror that here.
  bool _isWaiter() {
    try {
      return AuthService().isWaiter();
    } catch (e) {
      Log.d('branch', 'AuthService.isWaiter() failed, defaulting to false (non-fatal): $e');
      return false;
    }
  }

  /// Fetch a single branch entry from `/seller/profile/branches` —
  /// the WAITER-safe replacement for `/seller/get_branches/{id}` and
  /// `/seller/branches`. Returns the branch map (with seller-ish fields
  /// the receipt-info builder cares about) or an empty map if the entry
  /// isn't in the response.
  Future<Map<String, dynamic>> _fetchProfileBranchEntry(int branchId) async {
    final response =
        await _client.get(ApiConstants.profileBranchesEndpoint);
    final list = _coerceBranchList(response);
    for (final item in list) {
      final id = item['id'];
      final isMatch = id is num
          ? id.toInt() == branchId
          : int.tryParse(id?.toString() ?? '') == branchId;
      if (isMatch) return item;
    }
    return list.isNotEmpty ? list.first : const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getBranchInfo(int branchId) async {
    // WAITER role: /seller/get_branches/{id} 500s — fall back to /seller/profile/branches.
    if (_isWaiter()) {
      try {
        final summary = await _fetchProfileBranchEntry(branchId);
        return summary;
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ getBranchInfo (waiter fallback) failed: $e');
        return const {};
      }
    }
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

  /// Hit `/seller/filters/branches/{id}/getTax` to refresh the global
  /// tax config (`hasTax`, `taxPercentage`, `taxRate`, `digitsNumber`,
  /// `currency`) from the authoritative server-side source. Best-effort:
  /// returns the parsed payload on success or null on any failure — the
  /// in-memory ApiConstants stay on whatever was loaded from login or
  /// SharedPreferences when the call fails.
  Future<Map<String, dynamic>?> refreshTaxConfig({int? branchId}) async {
    final id = branchId ?? ApiConstants.branchId;
    if (id <= 0) return null;
    // WAITER role: skip — tax already hydrated from login's taxObject (avoids 401 risk).
    if (_isWaiter()) return null;
    try {
      final response =
          await _client.get(ApiConstants.getBranchTaxEndpoint(id));
      final data = response is Map ? response['data'] : null;
      if (data is Map) {
        final tax = data.map((k, v) => MapEntry(k.toString(), v));
        _applyTaxToApiConstants(tax);
        await _persistTaxToPrefs();
        if (kDebugMode) {
          debugPrint(
              '🏷️ Tax refreshed via getTax → hasTax=${ApiConstants.hasTax}, '
              'percentage=${ApiConstants.taxPercentage}%, '
              'currency=${ApiConstants.currency}');
        }
        return tax;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ refreshTaxConfig failed: $e');
    }
    return null;
  }

  void _applyTaxToApiConstants(Map<String, dynamic> tax) {
    final hasTaxRaw = tax['has_tax'] ?? tax['hasTax'];
    if (hasTaxRaw is bool) {
      ApiConstants.hasTax = hasTaxRaw;
    } else if (hasTaxRaw is num) {
      ApiConstants.hasTax = hasTaxRaw != 0;
    } else if (hasTaxRaw is String) {
      final s = hasTaxRaw.trim().toLowerCase();
      if (['1', 'true', 'yes', 'on', 'active'].contains(s)) {
        ApiConstants.hasTax = true;
      } else if (['0', 'false', 'no', 'off', 'inactive'].contains(s)) {
        ApiConstants.hasTax = false;
      }
    }

    final pctRaw = tax['tax_percentage'] ?? tax['taxPercentage'];
    final pct = pctRaw is num
        ? pctRaw.toDouble()
        : double.tryParse(pctRaw?.toString() ?? '');
    if (pct != null) {
      final percent = pct > 1.0 ? pct : pct * 100.0;
      ApiConstants.taxPercentage = percent.round();
      ApiConstants.taxRate = (percent / 100.0).clamp(0.0, 1.0).toDouble();
    }

    final digitsRaw = tax['digits_number'] ?? tax['digitsNumber'];
    final digits = digitsRaw is num
        ? digitsRaw.toInt()
        : int.tryParse(digitsRaw?.toString() ?? '');
    if (digits != null) {
      ApiConstants.digitsNumber = digits;
    }

    final currency = tax['currency']?.toString().trim();
    if (currency != null && currency.isNotEmpty) {
      ApiConstants.currency = currency;
    }
  }

  Future<void> _persistTaxToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_tax', ApiConstants.hasTax);
    await prefs.setInt('tax_percentage', ApiConstants.taxPercentage);
    await prefs.setInt('digits_number', ApiConstants.digitsNumber);
    await prefs.setString('currency', ApiConstants.currency);
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
      } catch (e) {
        Log.w('branch', 'pay-methods cache had unexpected shape', error: e);
      }
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

    // 5-min TTL.
    if (!forceRefresh &&
        _cachedPayMethods != null &&
        _payMethodsCacheTime != null &&
        DateTime.now().difference(_payMethodsCacheTime!).inMinutes < 5) {
      return _cachedPayMethods!;
    }

    try {
      // 1) Source of truth: dedicated payMethods endpoint.
      final typeCandidates = ['incomings', 'outgoings', 'online'];
      for (final type in typeCandidates) {
        try {
          final endpoint = '${ApiConstants.payMethodsEndpoint}?type=$type';
          final payMethodsResponse = await _client.get(endpoint);
          final fromPayMethodsApi = _parseEnabledPayMethods(payMethodsResponse);
          if (fromPayMethodsApi.isNotEmpty) {
            if (kDebugMode) {
              debugPrint(
                '✅ Payment methods loaded from payMethods endpoint (type=$type)');
            }
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
        } catch (e) {
          Log.d('branch', 'pay-method lookup attempt failed, trying next (non-fatal): $e');
        }
      }

      // 2) Fallback: branch settings.
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

      // Don't assume methods when backend is unavailable — would send invalid payloads.
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

    // Strict: respect backend "all disabled" config.
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
