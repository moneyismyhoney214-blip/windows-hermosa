import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CacheService {
  static const String _prefix = 'cache_';

  /// Cached SharedPreferences instance to avoid repeated async lookups
  static SharedPreferences? _prefs;

  Future<SharedPreferences> get _instance async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Save data to cache with expiration
  Future<void> set(String key, dynamic data, {Duration? expiry}) async {
    final prefs = await _instance;
    final cacheData = {
      'data': data,
      'expiry': expiry != null
          ? DateTime.now().add(expiry).toIso8601String()
          : null,
    };
    await prefs.setString('$_prefix$key', jsonEncode(cacheData));
  }

  /// Get data from cache, returns null if expired or not found
  Future<dynamic> get(String key) async {
    final prefs = await _instance;
    final cachedString = prefs.getString('$_prefix$key');

    if (cachedString == null) return null;

    try {
      final cacheData = jsonDecode(cachedString);
      final expiryStr = cacheData['expiry'];

      if (expiryStr != null) {
        final expiry = DateTime.parse(expiryStr);
        if (DateTime.now().isAfter(expiry)) {
          await prefs.remove('$_prefix$key');
          return null;
        }
      }

      return cacheData['data'];
    } catch (e) {
      return null;
    }
  }

  Future<void> clear(String key) async {
    final prefs = await _instance;
    await prefs.remove('$_prefix$key');
  }

  /// Return cache keys (without the internal prefix) whose name starts with
  /// [prefix]. Useful for invalidating or rewriting a family of related
  /// cache entries (e.g. all `bookings_<today>_*` filters).
  Future<List<String>> keysWithPrefix(String prefix) async {
    final prefs = await _instance;
    final allKeys = prefs.getKeys();
    final fullPrefix = '$_prefix$prefix';
    return allKeys
        .where((k) => k.startsWith(fullPrefix))
        .map((k) => k.substring(_prefix.length))
        .toList(growable: false);
  }
}
