import 'package:flutter/foundation.dart';
import 'package:hermosa_pos/models.dart';
import 'package:hermosa_pos/services/api/base_client.dart';
import 'package:hermosa_pos/services/api/api_constants.dart';
import 'package:hermosa_pos/services/cache_service.dart';
import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:hermosa_pos/services/offline/offline_pos_database.dart';
import 'package:hermosa_pos/services/offline/connectivity_service.dart';
import 'package:hermosa_pos/locator.dart';

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

  /// Fetch categories from API (offline-first)
  Future<List<CategoryModel>> getCategories({String? type}) async {
    if (_connectivity.isOffline) {
      return _getCategoriesFromLocal();
    }

    String endpoint = ApiConstants.categoriesEndpoint;

    // Add query params for filtering
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

        // Cache successful response
        await _cache.set('categories_$type', response['data'],
            expiry: const Duration(hours: 24));
        // Save to SQLite for offline
        await _offlineDb.saveCategories(
            (response['data'] as List).cast<Map<String, dynamic>>(),
            ApiConstants.branchId);
      }
      return categories;
    } catch (e) {
      // Return from local database on error
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
    } catch (_) {}
    // Try bundled POS database
    try {
      final posData = await _posDb.getCategories(ApiConstants.branchId);
      if (posData.isNotEmpty) {
        return posData.map((e) => CategoryModel.fromJson(e)).toList();
      }
    } catch (_) {}
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

    // Check if token is available first
    final token = _client.getToken();
    if (token == null || token.isEmpty) {
      print('⚠️ getMealCategories: No token available, returning empty list');
      return _getCategoriesFromLocal();
    }

    // Try multiple endpoints to get categories
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
            // Save to SQLite for offline
            await _offlineDb.saveCategories(
                data.cast<Map<String, dynamic>>(), ApiConstants.branchId);
            return categories;
          }
        }
      } on UnauthorizedException {
        rethrow;
      } catch (e) {
        print('Failed to fetch categories from $endpoint: $e');
        continue;
      }
    }

    // Fallback to local database then cache
    return _getCategoriesFromLocal();
  }

  /// Fetch categories with products/meals count
  Future<List<CategoryModel>> getCategoriesWithMeals() async {
    // Check if token is available first
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

    // PERF: in-memory cache per (category, page) with a 60s TTL. Before this
    // every category tap paid a full network round-trip even when the user
    // had just viewed the same page; now subsequent taps within the TTL are
    // served from memory instantly.
    final cacheKey = 'products_cat_${categoryId ?? "all"}_page_$page';
    final memCached = _memProductCache[cacheKey];
    if (memCached != null && !memCached.isExpired(_memProductTtl)) {
      return memCached.value;
    }
    // In-flight dedup: if a concurrent caller is already fetching the same
    // (category, page), piggy-back on its Future instead of firing a second
    // request. Prevents thrash when rapid scrolls trigger duplicate loads.
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
          final products =
              data.map((e) => Product.fromJson(e)).toList(growable: false);
          _memProductCache[cacheKey] = _CachedEntry(products);
          // Disk cache page 1 for offline resilience.
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
        _inFlightProducts.remove(cacheKey);
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
    } catch (_) {}
    // Try bundled POS database (meals table)
    try {
      final catId = categoryId != null ? int.tryParse(categoryId) : null;
      final posData =
          await _posDb.getMeals(ApiConstants.branchId, categoryId: catId);
      if (posData.isNotEmpty) {
        return posData.map((e) => Product.fromJson(e)).toList();
      }
    } catch (_) {}
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
      } catch (_) {}
    }
    return [];
  }

  Future<List<Product>> getCachedProducts(String? categoryId) async {
    final cached = await _cache.get('products_cat_${categoryId ?? "all"}');
    if (cached is List) {
      try {
        return cached.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
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
      // API doesn't support GET for single meal, fetch from list with filter
      final endpoint =
          '/seller/branches/${ApiConstants.branchId}/meals?meal_id=$mealId';
      final response = await _client.get(endpoint);

      if (response is Map && response['data'] != null) {
        final data = response['data'];
        if (data is List && data.isNotEmpty) {
          final mealData = data.first as Map<String, dynamic>;

          // Also try to fetch meal options/addons separately if not included
          if (mealData['extras'] == null &&
              mealData['add_ons'] == null &&
              mealData['options'] == null) {
            try {
              final optionsResponse = await _client.get(
                  '/seller/branches/${ApiConstants.branchId}/meals/$mealId/options');
              if (optionsResponse is Map && optionsResponse['data'] is List) {
                mealData['extras'] = optionsResponse['data'];
              }
            } catch (_) {
              // Options endpoint might not exist, continue without it
            }
          }

          return Product.fromJson(mealData);
        }
      }
      return null;
    } catch (e) {
      print('Error fetching meal details: $e');
      return null;
    }
  }

  /// Fetch add-ons for a specific meal
  Future<List<Extra>> getMealAddons(String mealId) async {
    try {
      final endpoint = ApiConstants.mealAddonsEndpoint(mealId);
      final response = await _client.get(endpoint);

      final addonEntries = _extractAddonEntries(response);
      return addonEntries
          .map((e) => Extra.fromJson(_normalizeExtraJson(e)))
          .toList();
    } catch (e) {
      print('Error fetching meal add-ons: $e');
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
          // Case: data is a Map { "Category1": [...], "Category2": [...] }
          data.forEach((key, value) {
            if (value is List) {
              groupedAddons[key.toString()] = value
                  .map((e) => Extra.fromJson(_normalizeExtraJson(e)))
                  .toList();
            }
          });
        } else if (data is List) {
          // Group by attribute/category name when available.
          for (final item in data) {
            final groupName = _extractAddonGroupName(item);
            final normalized = _normalizeExtraJson(item);
            final extra = Extra.fromJson(normalized);
            groupedAddons.putIfAbsent(groupName, () => <Extra>[]).add(extra);
          }
        }
      }
      // Refresh the presence cache — any non-empty group counts as "has
      // add-ons". Keeping it in sync with the grouped-fetch saves a second
      // round-trip when the customization dialog opens right after the tap.
      final hasAny = groupedAddons.values.any((g) => g.isNotEmpty);
      _addonPresenceCache[mealId] = hasAny;
      return groupedAddons;
    } catch (e) {
      print('Error fetching grouped meal add-ons: $e');
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
    // getMealAddonsGrouped already populates the cache, but set explicitly
    // so a caller that swallowed an exception still gets a deterministic
    // answer instead of re-fetching forever.
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

    // ID
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

    // Name
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

    // Price
    var priceVal = json['price'] ??
        json['operation_price'] ??
        json['attribute_price'] ??
        json['addon_price'] ??
        json['option_price'] ??
        json['extra_price'] ??
        0.0;
    priceVal = _parseApiPrice(priceVal);
    normalized['price'] = priceVal is num ? priceVal.toDouble() : 0.0;

    // Preserve translation maps so Extra.fromJson can fill `optionTranslations`
    // / `attributeTranslations`. Without this, the kitchen ticket would lose
    // the cashier's language on cart-side addons because _normalizeExtraJson
    // strips nested option/attribute objects before forwarding to the model.
    if (json['option'] is Map) normalized['option'] = json['option'];
    if (json['attribute'] is Map) normalized['attribute'] = json['attribute'];

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

    // Extract first numeric token to avoid currency dots like "ر.س".
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
