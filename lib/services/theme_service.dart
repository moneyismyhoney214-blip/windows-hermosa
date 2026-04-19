import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent theme manager.
///
/// Singleton. Exposes the current [ThemeMode] and notifies listeners whenever
/// the user picks a new mode. Persists the choice in SharedPreferences under
/// the key [_storageKey].
class ThemeService extends ChangeNotifier {
  ThemeService._internal();
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;

  static const String _storageKey = 'app_theme_mode_v1';

  ThemeMode _mode = ThemeMode.light;
  bool _initialized = false;

  ThemeMode get themeMode => _mode;
  bool get isDark => _mode == ThemeMode.dark;
  bool get isLight => _mode == ThemeMode.light;
  bool get isSystem => _mode == ThemeMode.system;

  /// Load the persisted preference. Call once from `main()` before `runApp`.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      _mode = _parseMode(raw);
    } catch (e) {
      debugPrint('⚠️ ThemeService: failed to load preference: $e');
      _mode = ThemeMode.light;
    }
    _initialized = true;
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, _serializeMode(mode));
    } catch (e) {
      debugPrint('⚠️ ThemeService: failed to persist preference: $e');
    }
  }

  /// Flip between light and dark (ignores system).
  Future<void> toggle() async {
    final next = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setMode(next);
  }

  ThemeMode _parseMode(String? raw) {
    switch (raw) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      case 'light':
      default:
        return ThemeMode.light;
    }
  }

  String _serializeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
      case ThemeMode.light:
        return 'light';
    }
  }
}

/// Global accessor — mirrors the [translationService] pattern used elsewhere.
final themeService = ThemeService();
