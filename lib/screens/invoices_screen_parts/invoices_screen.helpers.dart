// ignore_for_file: invalid_use_of_protected_member, unused_element, unused_element_parameter, dead_code, dead_null_aware_expression, unnecessary_cast
part of '../invoices_screen.dart';

extension InvoicesScreenHelpers on _InvoicesScreenState {
  String get _langCode =>
      translationService.currentLanguageCode.trim().toLowerCase();
  bool get _useArabicUi =>
      _langCode.startsWith('ar') || _langCode.startsWith('ur');
  String _tr(String ar, String nonArabic) => _useArabicUi ? ar : nonArabic;

  String _todayForApi() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  String _normalizeSearchToken(String value) {
    return value
        .toString()
        .toLowerCase()
        .replaceAll('#', '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
  }

  bool _hasLetters(String value) {
    return RegExp(r'[A-Za-z]').hasMatch(value);
  }

  String? _resolveApiSearchQuery() {
    final query = _searchQuery.trim();
    if (query.isEmpty) return null;
    return _hasLetters(query) ? query : null;
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  double _parseNum(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    final text =
        value.toString().replaceAll(RegExp(r'[^0-9.\\-]'), '').trim();
    return double.tryParse(text) ?? 0.0;
  }

  String _cleanText(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '';
    return raw.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').trim();
  }

  String? _firstNonEmptyText(
    List<dynamic> values, {
    bool allowZero = true,
  }) {
    for (final raw in values) {
      final text = _cleanText(raw);
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        if (!allowZero && (text == '0' || text == '#0')) continue;
        return text;
      }
    }
    return null;
  }

}
