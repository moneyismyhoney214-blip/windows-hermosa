library language_service;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api/api_constants.dart';

part 'language_service_parts/ar_translations.dart';
part 'language_service_parts/en_translations.dart';
part 'language_service_parts/es_translations.dart';
part 'language_service_parts/hi_translations.dart';
part 'language_service_parts/ur_translations.dart';
part 'language_service_parts/tr_translations.dart';

/// Language model
class AppLanguage {
  final String code;
  final String name;
  final String nativeName;
  final Locale locale;

  const AppLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.locale,
  });
}

/// Supported languages
class SupportedLanguages {
  static const List<AppLanguage> all = [
    AppLanguage(
      code: 'ar',
      name: 'Arabic',
      nativeName: 'العربية',
      locale: Locale('ar'),
    ),
    AppLanguage(
      code: 'en',
      name: 'English',
      nativeName: 'English',
      locale: Locale('en'),
    ),
    AppLanguage(
      code: 'es',
      name: 'Spanish',
      nativeName: 'Español',
      locale: Locale('es'),
    ),
    AppLanguage(
      code: 'hi',
      name: 'Hindi',
      nativeName: 'हिंदी',
      locale: Locale('hi'),
    ),
    AppLanguage(
      code: 'ur',
      name: 'Urdu',
      nativeName: 'اردو',
      locale: Locale('ur'),
    ),
    AppLanguage(
      code: 'tr',
      name: 'Turkish',
      nativeName: 'Türkçe',
      locale: Locale('tr'),
    ),
  ];

  static AppLanguage getByCode(String code) {
    return all.firstWhere(
      (lang) => lang.code == code,
      orElse: () => all.first,
    );
  }
}

/// Translation service
class TranslationService {
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();

  Locale _currentLocale = const Locale('ar');
  Map<String, String> _translations = {};
  final List<VoidCallback> _listeners = [];

  Locale get currentLocale => _currentLocale;
  String get currentLanguageCode => _currentLocale.languageCode;
  bool get isRTL =>
      _currentLocale.languageCode == 'ar' ||
      _currentLocale.languageCode == 'ur';

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    Future.microtask(() {
      for (var listener in _listeners) {
        listener();
      }
    });
  }

  /// Initialize with saved language or default
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString('app_language') ?? 'ar';
    await setLanguage(savedLang);
  }

  /// Change language
  Future<void> setLanguage(String langCode) async {
    final supportedCode = SupportedLanguages.getByCode(langCode).code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', supportedCode);

    _currentLocale = SupportedLanguages.getByCode(supportedCode).locale;
    _translations = _buildEffectiveTranslations(supportedCode);
    ApiConstants.setAcceptLanguage(supportedCode);
    _notifyListeners();
  }

  /// Get translation
  String translate(String key, {Map<String, dynamic>? args}) {
    String text = _translations[key] ?? key;

    if (args != null) {
      args.forEach((key, value) {
        text = text.replaceAll('{$key}', value.toString());
      });
    }

    return text;
  }

  /// Short form for translate
  String t(String key, {Map<String, dynamic>? args}) =>
      translate(key, args: args);

  /// Load translations for a language
  Map<String, String> _loadTranslations(String langCode) {
    switch (langCode) {
      case 'en':
        return _enTranslations;
      case 'es':
        return _esTranslations;
      case 'hi':
        return _hiTranslations;
      case 'ur':
        return _urTranslations;
      case 'tr':
        return _trTranslations;
      case 'ar':
      default:
        return _arTranslations;
    }
  }

  Map<String, String> _buildEffectiveTranslations(String langCode) {
    if (langCode == 'ar') {
      return Map<String, String>.from(_arTranslations);
    }
    if (langCode == 'en') {
      return {
        ..._arTranslations,
        ..._enTranslations,
      };
    }
    return {
      ..._arTranslations,
      ..._enTranslations,
      ..._loadTranslations(langCode),
    };
  }

}

final translationService = TranslationService();
