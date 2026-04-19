import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local, device-scoped settings for receipt / kitchen printer language.
///
/// This replaces the API-driven `BranchService.cachedInvoiceLanguage` so the
/// cashier can configure which language(s) appear on printed receipts
/// independently of what the server-side branch settings say.
///
/// Singleton + ChangeNotifier so widgets can rebuild when the user updates
/// the values. Persists under a single JSON blob in SharedPreferences.
class PrinterLanguageSettingsService extends ChangeNotifier {
  PrinterLanguageSettingsService._internal();
  static final PrinterLanguageSettingsService _instance =
      PrinterLanguageSettingsService._internal();
  factory PrinterLanguageSettingsService() => _instance;

  static const String _storageKey = 'printer_language_settings_v1';

  /// Language codes we support on printed receipts. Keep in sync with
  /// `SupportedLanguages` in `language_service.dart`.
  static const List<String> supportedCodes = <String>[
    'ar', 'en', 'es', 'hi', 'ur', 'tr',
  ];

  String _primary = 'ar';
  String _secondary = 'en';
  bool _allowSecondary = true;
  bool _initialized = false;

  String get primary => _primary;
  String get secondary => _secondary;
  bool get allowSecondary => _allowSecondary;
  bool get isInitialized => _initialized;

  /// Convenience accessor in the same shape the old call sites used.
  Map<String, dynamic> get asMap => <String, dynamic>{
        'primary': _primary,
        'secondary': _secondary,
        'allow_secondary': _allowSecondary,
      };

  /// Load persisted values from disk. Call once from `main()` before `runApp`.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _primary = _sanitizeCode(decoded['primary'], fallback: _primary);
          _secondary =
              _sanitizeCode(decoded['secondary'], fallback: _secondary);
          final allow = decoded['allow_secondary'];
          if (allow is bool) _allowSecondary = allow;
        }
      }
    } catch (e) {
      debugPrint('⚠️ PrinterLanguageSettingsService: failed to load: $e');
    }
    _initialized = true;
  }

  Future<void> setPrimary(String code) async {
    final next = _sanitizeCode(code, fallback: _primary);
    if (next == _primary) return;
    _primary = next;
    notifyListeners();
    await _persist();
  }

  Future<void> setSecondary(String code) async {
    final next = _sanitizeCode(code, fallback: _secondary);
    if (next == _secondary) return;
    _secondary = next;
    notifyListeners();
    await _persist();
  }

  Future<void> setAllowSecondary(bool value) async {
    if (_allowSecondary == value) return;
    _allowSecondary = value;
    notifyListeners();
    await _persist();
  }

  /// Update all three fields in one go — avoids multiple persist writes.
  Future<void> update({
    String? primary,
    String? secondary,
    bool? allowSecondary,
  }) async {
    var changed = false;
    if (primary != null) {
      final next = _sanitizeCode(primary, fallback: _primary);
      if (next != _primary) {
        _primary = next;
        changed = true;
      }
    }
    if (secondary != null) {
      final next = _sanitizeCode(secondary, fallback: _secondary);
      if (next != _secondary) {
        _secondary = next;
        changed = true;
      }
    }
    if (allowSecondary != null && allowSecondary != _allowSecondary) {
      _allowSecondary = allowSecondary;
      changed = true;
    }
    if (!changed) return;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(asMap));
    } catch (e) {
      debugPrint('⚠️ PrinterLanguageSettingsService: failed to persist: $e');
    }
  }

  String _sanitizeCode(dynamic raw, {required String fallback}) {
    if (raw is! String) return fallback;
    final trimmed = raw.trim().toLowerCase();
    if (trimmed.isEmpty) return fallback;
    return supportedCodes.contains(trimmed) ? trimmed : fallback;
  }
}

/// Global accessor — mirrors the `themeService` / `translationService` pattern.
final printerLanguageSettings = PrinterLanguageSettingsService();
