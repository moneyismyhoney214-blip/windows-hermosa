// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression
part of '../main_screen.dart';

extension MainScreenLocalization on _MainScreenState {
  String get _normalizedLanguageCode {
    final raw = translationService.currentLanguageCode.trim().toLowerCase();
    if (raw.isEmpty) return 'ar';
    final segments = raw.split(RegExp(r'[-_]'));
    return segments.isNotEmpty ? segments.first : raw;
  }

  bool get _useArabicUi {
    final code = _normalizedLanguageCode;
    return code == 'ar' || code == 'ur';
  }

  String _trUi(String ar, String nonArabic) => _useArabicUi ? ar : nonArabic;

  bool _containsArabicChars(String value) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(value);
  }

  String _stripWrappingQuotes(String value) {
    var text = value.trim();
    if (text.length >= 2) {
      final startsWithSingle = text.startsWith("'");
      final endsWithSingle = text.endsWith("'");
      final startsWithDouble = text.startsWith('"');
      final endsWithDouble = text.endsWith('"');
      if ((startsWithSingle && endsWithSingle) ||
          (startsWithDouble && endsWithDouble)) {
        text = text.substring(1, text.length - 1).trim();
      }
    }
    return text;
  }

  String? _extractLegacyLocalizedFromString(String raw) {
    String? findByCode(String code) {
      final match =
          RegExp("['\\\"]?$code['\\\"]?\\s*:\\s*([^,}\\]]+)").firstMatch(raw);
      if (match == null) return null;
      final extracted = _stripWrappingQuotes(match.group(1) ?? '');
      if (extracted.isEmpty || extracted.toLowerCase() == 'null') return null;
      return extracted;
    }

    final orderedCodes =
        _useArabicUi ? const <String>['ar', 'en'] : const <String>['en', 'ar'];
    for (final code in orderedCodes) {
      final found = findByCode(code);
      if (found != null && found.isNotEmpty) return found;
    }
    return null;
  }

  String? _extractFirstMeaningfulFromListString(String raw) {
    if (!(raw.startsWith('[') && raw.endsWith(']'))) return null;
    final content = raw.substring(1, raw.length - 1).trim();
    if (content.isEmpty) return null;

    final localized = _extractLegacyLocalizedFromString(content);
    if (localized != null && localized.isNotEmpty) return localized;

    for (final part in content.split(',')) {
      final token = _stripWrappingQuotes(part);
      if (token.isEmpty || token.toLowerCase() == 'null') continue;
      if (token.contains(':')) {
        final tokenLocalized = _extractLegacyLocalizedFromString(token);
        if (tokenLocalized != null && tokenLocalized.isNotEmpty) {
          return tokenLocalized;
        }
      }
      return token;
    }
    return null;
  }
}
