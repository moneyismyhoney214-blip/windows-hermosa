// ignore_for_file: avoid_dynamic_calls
// JSON wire-boundary layer — dynamic accesses accepted pending typed-model refactor.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hermosa_pos/locator.dart';
import 'package:hermosa_pos/models.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';
import 'package:hermosa_pos/services/api/base_client.dart';
import 'package:hermosa_pos/services/cache_service.dart';
import 'package:hermosa_pos/services/logger_service.dart';
import 'package:hermosa_pos/services/offline/connectivity_service.dart';
import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:hermosa_pos/services/offline/offline_pos_database.dart';

class ProductService {
  final BaseClient _client = BaseClient();
  final CacheService _cache = getIt<CacheService>();
  final OfflineDatabaseService _offlineDb = OfflineDatabaseService();
  final OfflinePosDatabase _posDb = OfflinePosDatabase();
  final ConnectivityService _connectivity = ConnectivityService();
  DateTime? _mainCategoriesRetryAfter;
  static const String _mainCategoriesUnauthorizedCacheKey =
      'main_categories_unauthorized_retry';

  static const Duration _memProductTtl = Duration(seconds: 60);
  final Map<String, _CachedEntry<List<Product>>> _memProductCache = {};
  final Map<String, Future<List<Product>>> _inFlightProducts = {};

  /// Per-language cache of meal names, keyed first by language code then by
  /// meal id. Populated via parallel fetches with `Accept-Language: <code>`
  /// so the CDS can render the name in whichever language(s) the cashier
  /// picked for receipts — even when the API only serves the active UI
  /// language per request.
  static final Map<String, Map<String, String>> _namesByLangById =
      <String, Map<String, String>>{};
  static final Set<String> _fetchedLangPages = <String>{};

  /// Languages we're willing to pre-fetch in the background for the CDS.
  /// Callers can extend this by invoking [primeLanguages] — the set is
  /// additive so newly needed languages (e.g. the printer primary/secondary)
  /// kick off a fetch the next time [getProducts] runs.
  static final Set<String> _primedLanguages = <String>{'en'};

  /// Every (page, categoryId) combo that has been fetched in the active
  /// language. Used by [primeLanguages] to retroactively fetch a newly
  /// added language on the same pages without waiting for the user to
  /// navigate back to each category.
  static final Set<String> _fetchedPageKeys = <String>{};

  /// Callbacks notified whenever new translations land — wakes up the
  /// cashier cart sync so the CDS payload refreshes with richer names.
  static final Set<VoidCallback> _cacheListeners = <VoidCallback>{};

  /// Addon option-name cache, structured like [_namesByLangById] but keyed
  /// by the option id returned under `option.id` on the mealAddons endpoint.
  /// Populated by fetching mealAddons in parallel per primed language.
  static final Map<String, Map<String, String>> _addonNamesByLangById =
      <String, Map<String, String>>{};
  static final Set<String> _fetchedAddonMealLangs = <String>{};

  /// Every mealId whose addons have been fetched at least once in the
  /// active language. Used by [primeLanguages] to back-fill a newly added
  /// language on every meal the cashier has already used — otherwise
  /// existing cart addons would be stuck in the old language until the
  /// user reopens each addon dialog.
  static final Set<String> _addonFetchedMeals = <String>{};

  /// Returns all cached translations for the given addon option id, or an
  /// empty map when we haven't fetched that option yet.
  static Map<String, String> cachedOptionNamesFor(String? optionId) {
    if (optionId == null || optionId.isEmpty) return const {};
    final out = <String, String>{};
    _addonNamesByLangById.forEach((lang, byId) {
      final v = byId[optionId];
      if (v != null && v.isNotEmpty) out[lang] = v;
    });
    return out;
  }

  /// Subscribe to translation-cache updates. Each time a background fetch
  /// harvests a new meal name (or a new language entirely), registered
  /// callbacks fire so the caller can re-push the CDS payload.
  static void addCacheListener(VoidCallback listener) {
    _cacheListeners.add(listener);
  }

  static void removeCacheListener(VoidCallback listener) {
    _cacheListeners.remove(listener);
  }

  static void _notifyCacheListeners() {
    for (final cb in List<VoidCallback>.from(_cacheListeners)) {
      try {
        cb();
      } catch (e) {
        Log.w('products', 'cache listener threw', error: e);
      }
    }
  }

  /// Returns the cached English meal name for [mealId], or null if none.
  static String? englishNameFor(String? mealId) =>
      nameForLangAndMeal('en', mealId);

  /// Returns the cached meal name in [lang] for [mealId], or null if we
  /// haven't successfully fetched that language yet.
  static String? nameForLangAndMeal(String lang, String? mealId) {
    if (mealId == null || mealId.isEmpty) return null;
    final code = lang.trim().toLowerCase();
    if (code.isEmpty) return null;
    final byLang = _namesByLangById[code];
    if (byLang == null) return null;
    final v = byLang[mealId];
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Returns all cached translations for [mealId] — useful when building a
  /// payload that should carry every available language.
  static Map<String, String> cachedNamesFor(String? mealId) {
    if (mealId == null || mealId.isEmpty) return const {};
    final out = <String, String>{};
    _namesByLangById.forEach((lang, byId) {
      final v = byId[mealId];
      if (v != null && v.isNotEmpty) out[lang] = v;
    });
    return out;
  }

  /// Register [langs] as languages that should be pre-fetched for the CDS.
  /// Fires fetches for any (language × page) combo we haven't hit yet —
  /// existing good cache entries are kept, so the CDS never goes through a
  /// "blank" window while new translations arrive.
  void primeLanguages(Iterable<String> langs) {
    final normalized = <String>{};
    for (final raw in langs) {
      final code = raw.trim().toLowerCase();
      if (code.isEmpty) continue;
      normalized.add(code);
      _primedLanguages.add(code);
    }
    if (normalized.isEmpty) return;

    final seen = _fetchedPageKeys.isNotEmpty
        ? _fetchedPageKeys.toList()
        : <String>['all|1'];
    for (final key in seen) {
      final parts = key.split('|');
      if (parts.length != 2) continue;
      final categoryId = parts[0];
      final page = int.tryParse(parts[1]) ?? 1;
      unawaited(_ensureNamesForPage(page, categoryId: categoryId));
    }

    // Re-prime addon translations so existing cart items flip language within seconds.
    for (final mealId in _addonFetchedMeals.toList()) {
      unawaited(_ensureAddonNamesForMeal(mealId));
    }
  }

  /// Force a fresh parallel fetch for every primed non-active language
  /// across every page we've already visited — wipes the in-memory
  /// translations cache first so pollution from an earlier build can't
  /// survive. Expensive; call sparingly (e.g. on app boot).
  void invalidateTranslationsCache() {
    final activeLang = ApiConstants.acceptLanguage.toLowerCase();
    for (final lang in _primedLanguages.toList()) {
      if (lang == activeLang || activeLang.startsWith(lang)) continue;
      _namesByLangById.remove(lang);
      _fetchedLangPages.removeWhere((k) => k.startsWith('${lang}_'));
      _addonNamesByLangById.remove(lang);
      _fetchedAddonMealLangs.removeWhere((k) => k.endsWith('__$lang'));
    }
  }

  /// Fetch the meals page once per (language × page × category) combo and
  /// harvest meal names into [_namesByLangById]. Best-effort — never
  /// throws. Language fetches run in **parallel** so picking a new primary
  /// + secondary pair doesn't stretch wait time by 2×.
  Future<void> _ensureNamesForPage(int page, {String? categoryId}) async {
    if (_connectivity.isOffline) return;
    final token = _client.getToken();
    if (token == null || token.isEmpty) return;

    final activeLang = ApiConstants.acceptLanguage.toLowerCase();
    final int? catId = (categoryId != null && categoryId != 'all')
        ? int.tryParse(categoryId)
        : null;
    final endpoint = ApiConstants.mealsPaginatedEndpoint(page, categoryId: catId);

    final pending = <Future<bool>>[];
    for (final lang in _primedLanguages) {
      if (lang == activeLang || activeLang.startsWith(lang)) continue;
      final pageKey = '${lang}_page_${categoryId ?? "all"}_$page';
      if (_fetchedLangPages.contains(pageKey)) continue;
      _fetchedLangPages.add(pageKey);
      pending.add(_fetchOneLangPage(lang, endpoint, pageKey));
    }
    if (pending.isEmpty) return;
    final results = await Future.wait(pending);
    if (results.any((harvested) => harvested)) _notifyCacheListeners();
  }

  Future<bool> _fetchOneLangPage(
    String lang,
    String endpoint,
    String pageKey,
  ) async {
    try {
      final response = await _client.get(
        endpoint,
        headers: {'Accept-Language': lang},
      );
      if (response is! Map || response['data'] is! List) return false;
      final bucket =
          _namesByLangById.putIfAbsent(lang, () => <String, String>{});
      var harvested = false;
      for (final raw in response['data'] as List) {
        if (raw is! Map) continue;
        final id = (raw['id'] ?? raw['meal_id'] ?? raw['product_id'])
            ?.toString();
        if (id == null || id.isEmpty) continue;
        final name = _pickNameForLang(
          Map<String, dynamic>.from(raw),
          lang,
          rawNameMatchesLang: true,
        );
        if (name.isNotEmpty) {
          bucket[id] = name;
          harvested = true;
        }
      }
      return harvested;
    } catch (e) {
      _fetchedLangPages.remove(pageKey);
      debugPrint('⚠️ [ProductService] "$lang" name fetch failed: $e');
      return false;
    }
  }

  /// Harvest names from the primary-language response so the active-language
  /// bucket stays in sync without a duplicate request.
  ///
  /// [rawNameMatchesLang] must be `true` only when the API response was
  /// actually served in [lang] — otherwise we'd pollute the bucket by
  /// storing the response's raw `name` string under the wrong language (the
  /// #1 symptom: picking English surfaces Arabic text).
  void _harvestNamesFromPrimary(
    List<dynamic> data, {
    required String lang,
    required bool rawNameMatchesLang,
  }) {
    final normalized = lang.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final bucket =
        _namesByLangById.putIfAbsent(normalized, () => <String, String>{});
    for (final raw in data) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final id =
          (map['id'] ?? map['meal_id'] ?? map['product_id'])?.toString();
      if (id == null || id.isEmpty) continue;
      final name = _pickNameForLang(
        map,
        normalized,
        rawNameMatchesLang: rawNameMatchesLang,
      );
      if (name.isNotEmpty) bucket[id] = name;
    }
  }

  /// Flatten a `{category: [...addons]}` response into a single list so the
  /// addon harvest can iterate uniformly regardless of whether the API
  /// returned a grouped Map or a flat List.
  List<dynamic> _flattenAddonMap(Map data) {
    final out = <dynamic>[];
    for (final entry in data.values) {
      if (entry is List) out.addAll(entry);
    }
    return out;
  }

  /// Harvest option-name translations from a mealAddons response into the
  /// per-language bucket. `_normalizeExtraJson` prefers the top-level
  /// `addon entry id` (e.g. 834) for `Extra.id` but falls back to
  /// `option.id` (e.g. 72) when the entry id is missing — so we cache the
  /// translation under BOTH identifiers, guaranteeing the cashier's
  /// `cachedOptionNamesFor(Extra.id)` lookup hits no matter which branch
  /// `_normalizeExtraJson` took.
  void _harvestAddonNamesFromPrimary(
    List<dynamic> data, {
    required String lang,
  }) {
    final code = lang.trim().toLowerCase();
    if (code.isEmpty) return;
    final bucket =
        _addonNamesByLangById.putIfAbsent(code, () => <String, String>{});
    var harvested = false;
    for (final raw in data) {
      if (raw is! Map) continue;
      final opt = raw['option'];
      if (opt is! Map) continue;
      final name = opt['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final entryId = raw['id']?.toString();
      final optionId = (opt['id'] ?? opt['option_id'])?.toString();
      for (final key in <String?>[entryId, optionId]) {
        if (key == null || key.isEmpty) continue;
        bucket[key] = name;
        harvested = true;
      }
    }
    if (harvested) _notifyCacheListeners();
  }

  /// Fetch the mealAddons endpoint in every primed non-active language so
  /// addon option names can be resolved in any invoice-language pair.
  /// Dedup per (mealId × language) to avoid thrashing.
  Future<void> _ensureAddonNamesForMeal(String mealId) async {
    if (mealId.isEmpty) return;
    if (_connectivity.isOffline) return;
    final token = _client.getToken();
    if (token == null || token.isEmpty) return;

    final activeLang = ApiConstants.acceptLanguage.toLowerCase();
    final endpoint = ApiConstants.mealAddonsEndpoint(mealId);

    final pending = <Future<bool>>[];
    for (final lang in _primedLanguages) {
      if (lang == activeLang || activeLang.startsWith(lang)) continue;
      final dedupKey = '${mealId}__$lang';
      if (_fetchedAddonMealLangs.contains(dedupKey)) continue;
      _fetchedAddonMealLangs.add(dedupKey);
      pending.add(_fetchOneLangAddons(lang, endpoint, dedupKey));
    }
    if (pending.isEmpty) return;
    final results = await Future.wait(pending);
    if (results.any((harvested) => harvested)) _notifyCacheListeners();
  }

  Future<bool> _fetchOneLangAddons(
    String lang,
    String endpoint,
    String dedupKey,
  ) async {
    try {
      final response = await _client.get(
        endpoint,
        headers: {'Accept-Language': lang},
      );
      if (response is! Map || response['data'] == null) return false;
      final data = response['data'];
      final items = data is List ? data : (data is Map ? _flattenAddonMap(data) : const []);
      if (items.isEmpty) return false;
      final bucket =
          _addonNamesByLangById.putIfAbsent(lang, () => <String, String>{});
      var harvested = false;
      for (final raw in items) {
        if (raw is! Map) continue;
        final opt = raw['option'];
        if (opt is! Map) continue;
        final name = opt['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        // Cache under both entry id and option.id so any Extra.id form hits.
        final entryId = raw['id']?.toString();
        final optionId = (opt['id'] ?? opt['option_id'])?.toString();
        for (final key in <String?>[entryId, optionId]) {
          if (key == null || key.isEmpty) continue;
          bucket[key] = name;
          harvested = true;
        }
      }
      return harvested;
    } catch (e) {
      _fetchedAddonMealLangs.remove(dedupKey);
      debugPrint('⚠️ [ProductService] addon "$lang" fetch failed: $e');
      return false;
    }
  }

  /// Extract the meal name for [lang] from a raw API entry, preferring
  /// explicit per-language fields and translation maps. Only falls back to
  /// the bare `name` string when the caller confirms the response was
  /// fetched in [lang] via [rawNameMatchesLang].
  String _pickNameForLang(
    Map<String, dynamic> raw,
    String lang, {
    bool rawNameMatchesLang = false,
  }) {
    final code = lang.trim().toLowerCase();
    if (code.isEmpty) return '';
    for (final key in <String>[
      'name_$code',
      'name_display_$code',
      'title_$code',
      'meal_name_$code',
      'item_name_$code',
    ]) {
      final v = raw[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    for (final key in const [
      'names',
      'meal_name_translations',
      'name_translations',
      'translations',
      'name_locales',
      'localized_names',
      'localizedNames',
    ]) {
      final mt = raw[key];
      if (mt is Map) {
        final v = mt[code]?.toString().trim();
        if (v != null && v.isNotEmpty) return v;
      }
    }
    final rawName = raw['name'];
    if (rawName is Map) {
      final v = rawName[code]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    } else if (rawNameMatchesLang && rawName is String) {
      final v = rawName.trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  /// Fetch categories from API (offline-first)
  Future<List<CategoryModel>> getCategories({String? type}) async {
    if (_connectivity.isOffline) {
      return _getCategoriesFromLocal();
    }

    String endpoint = ApiConstants.categoriesEndpoint;

    final params = <String>[];
    if (type != null) {
      params.add('type=$type');
      params.add('category=$type');
    }
    params.add('all=true');

    if (params.isNotEmpty) {
      endpoint = '$endpoint?${params.join('&')}';
    }

    try {
      final response = await _client.get(endpoint);
      List<CategoryModel> categories = [];

      if (response is Map && response['data'] is List) {
        categories = (response['data'] as List)
            .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
            .toList();

        await _cache.set('categories_$type', response['data'],
            expiry: const Duration(hours: 24));
        await _offlineDb.saveCategories(
            (response['data'] as List).cast<Map<String, dynamic>>(),
            ApiConstants.branchId);
      }
      return categories;
    } catch (e) {
      final local = await _getCategoriesFromLocal();
      if (local.isNotEmpty) return local;
      rethrow;
    }
  }

  Future<List<CategoryModel>> _getCategoriesFromLocal() async {
    try {
      final localData = await _offlineDb.getCategories(ApiConstants.branchId);
      if (localData.isNotEmpty) {
        return localData.map((e) => CategoryModel.fromJson(e)).toList();
      }
    } catch (e) {
      Log.w('products', 'offline DB categories read failed', error: e);
    }
    try {
      final posData = await _posDb.getCategories(ApiConstants.branchId);
      if (posData.isNotEmpty) {
        return posData.map((e) => CategoryModel.fromJson(e)).toList();
      }
    } catch (e) {
      Log.w('products', 'POS DB categories read failed', error: e);
    }
    final cached = await _cache.get('categories_null');
    if (cached is List) {
      return cached.map((e) => CategoryModel.fromJson(e)).toList();
    }
    return [];
  }

  /// Fetch meal categories specifically (offline-first)
  Future<List<CategoryModel>> getMealCategories() async {
    if (_connectivity.isOffline) {
      return _getCategoriesFromLocal();
    }

    final token = _client.getToken();
    if (token == null || token.isEmpty) {
      Log.w('product', 'getMealCategories called with no token — local fallback');
      return _getCategoriesFromLocal();
    }

    final possibleEndpoints = [
      ApiConstants.mealCategoriesEndpoint,
      ApiConstants.categoriesWithMealsEndpoint,
      '${ApiConstants.categoriesEndpoint}?type=meals&all=true',
    ];

    for (final endpoint in possibleEndpoints) {
      try {
        final response = await _client.get(endpoint);

        if (response is Map && response['data'] is List) {
          final List<dynamic> data = response['data'];
          if (data.isNotEmpty) {
            final categories = data
                .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
                .where((cat) => cat.name.isNotEmpty && cat.id.isNotEmpty)
                .toList();

            // Cache successful result
            await _cache.set('meal_categories', data,
                expiry: const Duration(hours: 24));
            await _offlineDb.saveCategories(
                data.cast<Map<String, dynamic>>(), ApiConstants.branchId);
            return categories;
          }
        }
      } on UnauthorizedException {
        rethrow;
      } catch (e) {
        Log.w('product', 'fetch categories failed at $endpoint', error: e);
        continue;
      }
    }

    return _getCategoriesFromLocal();
  }

  /// Fetch categories with products/meals count
  Future<List<CategoryModel>> getCategoriesWithMeals() async {
    final token = _client.getToken();
    if (token == null || token.isEmpty) {
      return [];
    }

    try {
      final response =
          await _client.get(ApiConstants.categoriesWithMealsEndpoint);

      if (response is Map && response['data'] is List) {
        final data = response['data'] as List;
        await _cache.set('categories_with_meals', data,
            expiry: const Duration(hours: 24));
        return data
            .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
            .where((cat) => cat.name.isNotEmpty && cat.id.isNotEmpty)
            .toList();
      }
    } catch (e) {
      final cached = await _cache.get('categories_with_meals');
      if (cached is List) {
        return cached.map((e) => CategoryModel.fromJson(e)).toList();
      }
    }

    return getMealCategories();
  }

  /// Fetch main categories
  Future<List<CategoryModel>> getMainCategories() async {
    final token = _client.getToken();
    if (token == null || token.isEmpty) {
      return [];
    }

    final unauthorizedRetryFlag =
        await _cache.get(_mainCategoriesUnauthorizedCacheKey);
    if (unauthorizedRetryFlag == true) {
      final cached = await _cache.get('main_categories');
      if (cached is List) {
        return cached.map((e) => CategoryModel.fromJson(e)).toList();
      }
      return [];
    }

    final now = DateTime.now();
    final retryAfter = _mainCategoriesRetryAfter;
    if (retryAfter != null && now.isBefore(retryAfter)) {
      final cached = await _cache.get('main_categories');
      if (cached is List) {
        return cached.map((e) => CategoryModel.fromJson(e)).toList();
      }
      return [];
    }

    try {
      final response = await _client.get(
        ApiConstants.mainCategoriesEndpoint,
        skipGlobalAuth: true,
      );
      _mainCategoriesRetryAfter = null;
      if (response is Map && response['data'] is List) {
        final data = response['data'] as List;
        await _cache.set('main_categories', data,
            expiry: const Duration(hours: 24));
        return data.map((e) => CategoryModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      if (e is UnauthorizedException ||
          (e is ApiException && (e.statusCode ?? 0) == 401)) {
        _mainCategoriesRetryAfter = now.add(const Duration(minutes: 10));
        await _cache.set(
          _mainCategoriesUnauthorizedCacheKey,
          true,
          expiry: const Duration(hours: 6),
        );
      }
      final cached = await _cache.get('main_categories');
      if (cached is List) {
        return cached.map((e) => CategoryModel.fromJson(e)).toList();
      }
      return [];
    }
  }

  /// Fetch products/meals from API with pagination (offline-first)
  Future<List<Product>> getProducts({String? categoryId, int page = 1}) async {
    if (_connectivity.isOffline) {
      return _getProductsFromLocal(categoryId);
    }

    final token = _client.getToken();
    if (token == null || token.isEmpty) {
      return _getProductsFromLocal(categoryId);
    }

    // PERF: 60s in-memory cache per (category, page) to skip repeat round-trips.
    final cacheKey = 'products_cat_${categoryId ?? "all"}_page_$page';
    final memCached = _memProductCache[cacheKey];
    if (memCached != null && !memCached.isExpired(_memProductTtl)) {
      return memCached.value;
    }
    // In-flight dedup: piggy-back on concurrent fetch for same (category, page).
    final pending = _inFlightProducts[cacheKey];
    if (pending != null) return pending;

    final int? catId = (categoryId != null && categoryId != 'all')
        ? int.tryParse(categoryId)
        : null;
    final endpoint =
        ApiConstants.mealsPaginatedEndpoint(page, categoryId: catId);

    Future<dynamic> fetchProductsResponse() => _client.get(endpoint);

    final future = () async {
      try {
        dynamic response;
        try {
          response = await fetchProductsResponse();
        } catch (e) {
          final message = e.toString().toLowerCase();
          final isTransientHeaderClose =
              message.contains('connection closed before full header');
          if (!isTransientHeaderClose) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 350));
          response = await fetchProductsResponse();
        }

        if (response is Map && response['data'] is List) {
          final data = response['data'] as List;
          // Hide meals the merchant toggled off — they must never reach
          // ordering/sale/KDS surfaces. Re-enable from portal/admin only.
          final products = data
              .map((e) => Product.fromJson(e))
              .where((p) => p.isActive)
              .toList(growable: false);
          // Track (category, page) so primeLanguages can back-fill new languages.
          _fetchedPageKeys.add('${categoryId ?? "all"}|$page');
          final activeLang = ApiConstants.acceptLanguage.toLowerCase();
          _harvestNamesFromPrimary(
            data,
            lang: activeLang,
            rawNameMatchesLang: true,
          );
          if (!activeLang.startsWith('en')) {
            // Pull English only from translation fields — raw `name` is active-language.
            _harvestNamesFromPrimary(
              data,
              lang: 'en',
              rawNameMatchesLang: false,
            );
          }
          _notifyCacheListeners();
          // Fire-and-forget parallel fetches for other primed languages (CDS).
          unawaited(_ensureNamesForPage(page, categoryId: categoryId));
          _memProductCache[cacheKey] = _CachedEntry(products);
          if (page == 1) {
            await _cache.set('products_cat_${categoryId ?? "all"}', data,
                expiry: const Duration(hours: 1));
            await _offlineDb.saveProducts(
                data.cast<Map<String, dynamic>>(), ApiConstants.branchId,
                categoryId: categoryId);
          }
          return products;
        }
        return <Product>[];
      } catch (e) {
        return _getProductsFromLocal(categoryId);
      } finally {
        unawaited(_inFlightProducts.remove(cacheKey));
      }
    }();
    _inFlightProducts[cacheKey] = future;
    return future;
  }

  /// Purge the in-memory product pagination cache. Call this after mutations
  /// (create/update/delete meal, toggle availability) so stale pages don't
  /// linger.
  void invalidateProductCache() {
    _memProductCache.clear();
  }

  Future<List<Product>> _getProductsFromLocal(String? categoryId) async {
    try {
      final localData = await _offlineDb.getProducts(ApiConstants.branchId,
          categoryId: categoryId);
      if (localData.isNotEmpty) {
        return localData.map((e) => Product.fromJson(e)).toList();
      }
    } catch (e) {
      Log.w('products', 'offline DB products read failed', error: e);
    }
    try {
      final catId = categoryId != null ? int.tryParse(categoryId) : null;
      final posData =
          await _posDb.getMeals(ApiConstants.branchId, categoryId: catId);
      if (posData.isNotEmpty) {
        return posData.map((e) => Product.fromJson(e)).toList();
      }
    } catch (e) {
      Log.w('products', 'POS DB meals read failed', error: e);
    }
    final cached = await _cache.get('products_cat_${categoryId ?? "all"}');
    if (cached is List) {
      return cached.map((e) => Product.fromJson(e)).toList();
    }
    return [];
  }

  Future<List<CategoryModel>> getCachedMealCategories() async {
    final cached = await _cache.get('meal_categories');
    if (cached is List) {
      try {
        return cached.map((e) => CategoryModel.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        // Log stale-cache parse failures so they don't silently empty the panel.
        Log.w('products', 'meal-categories cache parse failed', error: e);
      }
    }
    return [];
  }

  Future<List<Product>> getCachedProducts(String? categoryId) async {
    final cached = await _cache.get('products_cat_${categoryId ?? "all"}');
    if (cached is List) {
      try {
        return cached.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
      } catch (e) {
        Log.w('products', 'products cache parse failed', error: e);
      }
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getMenuLists() async {
    final endpoint = ApiConstants.menuListsEndpoint;
    debugPrint('🌐 [ProductService] GET $endpoint');
    final response = await _client.get(endpoint);
    debugPrint('🌐 [ProductService] menuLists response keys: ${response.keys.toList()}');
    final data = response['data'];
    debugPrint('🌐 [ProductService] data type=${data.runtimeType} '
        'value=${data is List ? "List(len=${data.length})" : data}');
    if (data is List) {
      return data
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> getMenuListDetails(int menuId) async {
    final endpoint = ApiConstants.menuListDetailsEndpoint(menuId);
    final response = await _client.get(endpoint);
    final data = response['data'];
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), v));
    }
    return <String, dynamic>{};
  }

  /// Fetch meal details with all add-ons/options
  /// Use this when you need complete meal information including add-ons
  /// Note: The API doesn't support GET /meals/{id}, so we filter from list
  Future<Product?> getMealWithDetails(String mealId) async {
    try {
      final endpoint =
          '/seller/branches/${ApiConstants.branchId}/meals?meal_id=$mealId';
      final response = await _client.get(endpoint);

      if (response is Map && response['data'] != null) {
        final data = response['data'];
        if (data is List && data.isNotEmpty) {
          final mealData = data.first as Map<String, dynamic>;

          if (mealData['extras'] == null &&
              mealData['add_ons'] == null &&
              mealData['options'] == null) {
            try {
              final optionsResponse = await _client.get(
                  '/seller/branches/${ApiConstants.branchId}/meals/$mealId/options');
              if (optionsResponse is Map && optionsResponse['data'] is List) {
                mealData['extras'] = optionsResponse['data'];
              }
            } catch (e) {
              Log.d('product', 'options endpoint unavailable for meal=$mealId (non-fatal): $e');
            }
          }

          return Product.fromJson(mealData);
        }
      }
      return null;
    } catch (e) {
      Log.w('product', 'fetch meal details failed', error: e);
      return null;
    }
  }

  /// Fetch add-ons for a specific meal
  Future<List<Extra>> getMealAddons(String mealId) async {
    try {
      final endpoint = ApiConstants.mealAddonsEndpoint(mealId);
      final response = await _client.get(endpoint);

      final addonEntries = _extractAddonEntries(response);
      // Seed active-language bucket + fire background fetches for primed langs (CDS).
      final activeLang = ApiConstants.acceptLanguage.toLowerCase();
      _harvestAddonNamesFromPrimary(addonEntries, lang: activeLang);
      _addonFetchedMeals.add(mealId);
      unawaited(_ensureAddonNamesForMeal(mealId));
      return addonEntries
          .map((e) => Extra.fromJson(_normalizeExtraJson(e)))
          .toList();
    } catch (e) {
      Log.w('product', 'fetch meal add-ons failed', error: e);
      return [];
    }
  }

  /// Memoized addon-presence flag per meal id. The cashier taps a meal
  /// dozens of times per shift; after the first check we keep the answer
  /// around so subsequent taps skip the network hop.
  final Map<String, bool> _addonPresenceCache = {};

  /// Fetch add-ons grouped by category (Key-Value)
  Future<Map<String, List<Extra>>> getMealAddonsGrouped(String mealId) async {
    try {
      final endpoint = ApiConstants.mealAddonsEndpoint(mealId);
      final response = await _client.get(endpoint);

      final Map<String, List<Extra>> groupedAddons = {};

      if (response is Map && response['data'] != null) {
        final data = response['data'];

        if (data is Map) {
          data.forEach((key, value) {
            if (value is List) {
              groupedAddons[key.toString()] = value
                  .map((e) => Extra.fromJson(_normalizeExtraJson(e)))
                  .toList();
            }
          });
        } else if (data is List) {
          for (final item in data) {
            final groupName = _extractAddonGroupName(item);
            final normalized = _normalizeExtraJson(item);
            final extra = Extra.fromJson(normalized);
            groupedAddons.putIfAbsent(groupName, () => <Extra>[]).add(extra);
          }
        }

        // Seed active-language + fire parallel fetches for primed langs.
        final activeLang = ApiConstants.acceptLanguage.toLowerCase();
        _harvestAddonNamesFromPrimary(
          data is List ? data : _flattenAddonMap(data as Map),
          lang: activeLang,
        );
        _addonFetchedMeals.add(mealId);
        unawaited(_ensureAddonNamesForMeal(mealId));
      }
      // Refresh presence cache to skip round-trip when customization dialog opens.
      final hasAny = groupedAddons.values.any((g) => g.isNotEmpty);
      _addonPresenceCache[mealId] = hasAny;
      return groupedAddons;
    } catch (e) {
      Log.w('product', 'fetch grouped meal add-ons failed', error: e);
      return {};
    }
  }

  /// Returns whether the meal actually has any add-ons on the backend.
  /// Uses a memoized answer once the meal has been checked; the first call
  /// for a meal costs one API round-trip, subsequent calls are synchronous.
  /// `null` never leaks out — callers get a clean bool they can branch on.
  Future<bool> mealHasAddons(String mealId) async {
    if (mealId.isEmpty) return false;
    final cached = _addonPresenceCache[mealId];
    if (cached != null) return cached;
    final grouped = await getMealAddonsGrouped(mealId);
    // Explicit set in case caller swallowed exception — avoids re-fetch loop.
    final hasAny = grouped.values.any((g) => g.isNotEmpty);
    _addonPresenceCache[mealId] = hasAny;
    return hasAny;
  }

  List<dynamic> _extractAddonEntries(dynamic response) {
    if (response is! Map) return const [];
    final data = response['data'];
    if (data is List) return data;
    if (data is Map) {
      if (data['add_ons'] is List) return data['add_ons'] as List;
      if (data['extras'] is List) return data['extras'] as List;
      if (data['modifiers'] is List) return data['modifiers'] as List;
      if (data['cooking_type'] is List) return data['cooking_type'] as List;
      if (data['meal_attributes'] is List) {
        return data['meal_attributes'] as List;
      }
      if (data['operations'] is List) return data['operations'] as List;
      if (data['attributes'] is List) return data['attributes'] as List;
      if (data['options'] is List) return data['options'] as List;

      final flattened = <dynamic>[];
      for (final value in data.values) {
        if (value is List) {
          flattened.addAll(value);
        } else if (value is Map) {
          if (value['operations'] is List) {
            flattened.addAll(value['operations'] as List);
          } else if (value['items'] is List) {
            flattened.addAll(value['items'] as List);
          }
        }
      }
      if (flattened.isNotEmpty) return flattened;
    }

    if (response['add_ons'] is List) return response['add_ons'] as List;
    if (response['extras'] is List) return response['extras'] as List;
    if (response['modifiers'] is List) return response['modifiers'] as List;
    if (response['cooking_type'] is List) {
      return response['cooking_type'] as List;
    }
    if (response['meal_attributes'] is List) {
      return response['meal_attributes'] as List;
    }
    if (response['operations'] is List) return response['operations'] as List;
    return const [];
  }

  Map<String, dynamic> _normalizeExtraJson(dynamic payload) {
    final json = payload is Map<String, dynamic>
        ? payload
        : payload is Map
            ? payload.map((key, value) => MapEntry(key.toString(), value))
            : <String, dynamic>{'id': payload};
    final normalized = <String, dynamic>{};

    if (json['id'] != null) {
      normalized['id'] = json['id'].toString();
    } else if (json['option'] is Map &&
        (json['option']['id'] != null || json['option']['option_id'] != null)) {
      normalized['id'] =
          (json['option']['id'] ?? json['option']['option_id']).toString();
    } else if (json['attribute_id'] != null) {
      normalized['id'] = json['attribute_id'].toString();
    } else if (json['operation_id'] != null) {
      normalized['id'] = json['operation_id'].toString();
    } else if (json['addon_id'] != null) {
      normalized['id'] = json['addon_id'].toString();
    } else if (json['option_id'] != null) {
      normalized['id'] = json['option_id'].toString();
    } else {
      normalized['id'] = DateTime.now().millisecondsSinceEpoch.toString();
    }

    if (json['name'] != null) {
      normalized['name'] = _readLocalizedText(json['name']);
    } else if (json['option'] is Map && json['option']['name'] != null) {
      normalized['name'] = _readLocalizedText(json['option']['name']);
    } else if (json['attribute'] is Map && json['attribute']['name'] != null) {
      normalized['name'] = _readLocalizedText(json['attribute']['name']);
    } else if (json['attribute_name'] != null) {
      normalized['name'] = _readLocalizedText(json['attribute_name']);
    } else if (json['operation_name'] != null) {
      normalized['name'] = _readLocalizedText(json['operation_name']);
    } else if (json['addon_name'] != null) {
      normalized['name'] = _readLocalizedText(json['addon_name']);
    } else if (json['option_name'] != null) {
      normalized['name'] = _readLocalizedText(json['option_name']);
    } else if (json['title'] != null) {
      normalized['name'] = _readLocalizedText(json['title']);
    } else if (json['label'] != null) {
      normalized['name'] = _readLocalizedText(json['label']);
    } else {
      normalized['name'] = 'Extra';
    }

    var priceVal = json['price'] ??
        json['operation_price'] ??
        json['attribute_price'] ??
        json['addon_price'] ??
        json['option_price'] ??
        json['extra_price'] ??
        0.0;
    priceVal = _parseApiPrice(priceVal);
    normalized['price'] = priceVal is num ? priceVal.toDouble() : 0.0;

    // Preserve translation maps so Extra.fromJson can fill optionTranslations/attributeTranslations.
    if (json['option'] is Map) normalized['option'] = json['option'];
    if (json['attribute'] is Map) normalized['attribute'] = json['attribute'];
    for (final key in const [
      'names',
      'name_translations',
      'translations',
      'optionTranslations',
      'attributeTranslations',
      'attribute_names',
    ]) {
      final v = json[key];
      if (v != null) normalized[key] = v;
    }

    return normalized;
  }

  String _extractAddonGroupName(dynamic payload) {
    if (payload is Map) {
      final map = payload.map((k, v) => MapEntry(k.toString(), v));
      if (map['attribute'] is Map && map['attribute']['name'] != null) {
        return _readLocalizedText(map['attribute']['name']);
      }
      if (map['attribute_name'] != null) {
        return _readLocalizedText(map['attribute_name']);
      }
      if (map['group_name'] != null) {
        return _readLocalizedText(map['group_name']);
      }
    }
    return 'الإضافات';
  }

  String _readLocalizedText(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Map) {
      final ar = value['ar']?.toString().trim();
      if (ar != null && ar.isNotEmpty) return ar;
      final en = value['en']?.toString().trim();
      if (en != null && en.isNotEmpty) return en;
      for (final v in value.values) {
        final text = v?.toString().trim();
        if (text != null && text.isNotEmpty) return text;
      }
    }
    return value.toString();
  }

  double _parseApiPrice(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();

    var text = value.toString().trim();
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    const persianDigits = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      text = text.replaceAll(arabicDigits[i], i.toString());
      text = text.replaceAll(persianDigits[i], i.toString());
    }

    text = text.replaceAll('٫', '.').replaceAll('٬', ',');

    // Extract first numeric token to skip currency dots like "ر.س".
    final match = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(text);
    if (match == null) return 0.0;

    var number = match.group(0) ?? '';
    if (number.contains(',') && !number.contains('.')) {
      number = number.replaceAll(',', '.');
    } else {
      number = number.replaceAll(',', '');
    }

    return double.tryParse(number) ?? 0.0;
  }

  /// Get meal details for editing
  Future<Map<String, dynamic>> getMealForEdit(String mealId) async {
    final endpoint =
        '/seller/branches/${ApiConstants.branchId}/meals/$mealId/edit';
    return await _client.get(endpoint);
  }

  /// Update a meal
  Future<Map<String, dynamic>> updateMeal(
      String mealId, Map<String, String> mealData) async {
    final endpoint = '/seller/branches/${ApiConstants.branchId}/meals/$mealId';
    return await _client.postMultipart(endpoint, mealData);
  }

  /// Update product/meal status
  Future<void> updateMealStatus(String mealId, bool isActive) async {
    await _client.post(
      '/seller/status/branches/${ApiConstants.branchId}/meals/$mealId',
      {'is_active': isActive},
    );
  }

  /// Delete a product
  Future<void> deleteProduct(String productId) async {
    await _client.delete('${ApiConstants.productsEndpoint}/$productId');
  }

  /// Delete a meal
  Future<void> deleteMeal(String mealId) async {
    await _client
        .delete('/seller/branches/${ApiConstants.branchId}/meals/$mealId');
  }
}

class _CachedEntry<T> {
  final T value;
  final DateTime cachedAt;
  _CachedEntry(this.value) : cachedAt = DateTime.now();

  bool isExpired(Duration ttl) =>
      DateTime.now().difference(cachedAt) > ttl;
}
