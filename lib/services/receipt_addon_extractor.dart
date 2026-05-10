import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/receipt_data.dart';

/// Extract [ReceiptAddon]s from a single API invoice-line item map.
///
/// Different backend routes (and the local cart's pre-save shape) put
/// the addon list under different keys, which used to surface as
/// "addons print on the printer but vanish from the preview". The
/// printer was reading from the local cart's `extras`, while the
/// preview was reading the API response's `addons` — and some
/// endpoints reply with `meal_addons` instead, or nest the array under
/// `meal.addons`. We probe every known location here so both paths see
/// the same set.
///
/// `addons_translations` (or its `meal.addons_translations` mirror)
/// holds per-language strings keyed by index alongside the addon list.
/// When present, we lift them into each [ReceiptAddon.localizedNames]
/// so the print widget can render the addon in the host's chosen
/// invoice language without a separate lookup.
List<ReceiptAddon> extractReceiptAddonsFromItem(Map<dynamic, dynamic> item) {
  Map<String, dynamic>? asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return null;
  }

  List<dynamic>? pickList(List<String> keys) {
    for (final source in <Map<dynamic, dynamic>?>[
      item,
      asMap(item['meal']),
    ]) {
      if (source == null) continue;
      for (final key in keys) {
        final value = source[key];
        if (value is List && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  final rawAddons = pickList(const [
    'addons',
    'meal_addons',
    'extras',
    'selected_addons',
    'addon_options',
  ]);
  if (rawAddons == null) {
    if (kDebugMode) {
      final keys = item.keys.map((k) => k.toString()).toList();
      debugPrint(
          '[addon-extractor] no addon list found. item keys: $keys');
    }
    return const [];
  }
  if (kDebugMode) {
    debugPrint(
        '[addon-extractor] raw=${rawAddons.length} firstType=${rawAddons.isEmpty ? "n/a" : rawAddons.first.runtimeType} first=${rawAddons.isEmpty ? "n/a" : rawAddons.first.toString().substring(0, rawAddons.first.toString().length > 200 ? 200 : rawAddons.first.toString().length)}');
  }

  final translations = pickList(const [
    'addons_translations',
    'meal_addons_translations',
    'extras_translations',
  ]);

  String pickStr(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final v = map[key]?.toString().trim();
      if (v != null && v.isNotEmpty && v.toLowerCase() != 'null') return v;
    }
    return '';
  }

  double parsePrice(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0.0;
    return 0.0;
  }

  final result = <ReceiptAddon>[];
  for (var i = 0; i < rawAddons.length; i++) {
    final raw = rawAddons[i];

    // Saved-invoice endpoint shape: addons come back as plain strings
    // (e.g. "AttributeName - OptionName") with no per-language split or
    // price. Treat the string itself as the display name so the addon
    // still surfaces in the preview — same content the printer renders.
    if (raw is String) {
      final display = raw.trim();
      if (display.isEmpty) continue;
      result.add(ReceiptAddon(
        nameAr: display,
        nameEn: display,
        price: 0.0,
      ));
      continue;
    }

    final addonMap = asMap(raw);
    if (addonMap == null) continue;

    final localized = <String, String>{};
    Map<String, dynamic>? optionMap;
    final embedded = asMap(addonMap['translations']);
    if (embedded != null) {
      optionMap = asMap(embedded['option']) ?? embedded;
    }
    if (optionMap == null && translations != null && i < translations.length) {
      final translation = asMap(translations[i]);
      if (translation != null) {
        optionMap = asMap(translation['option']) ?? translation;
      }
    }
    // The richer booking-create shape stores `option.name` /
    // `attribute.name` as a JSON-encoded `{"ar": "...", "en": "..."}`
    // string. Decode it lazily so the localized map gets populated even
    // when no parallel `addons_translations` array is provided.
    if (optionMap == null) {
      final optionNode = asMap(addonMap['option']);
      if (optionNode != null) {
        final rawName = optionNode['name'];
        if (rawName is String) {
          final decoded = _tryDecodeJsonMap(rawName);
          if (decoded != null) optionMap = decoded;
        } else if (rawName is Map) {
          optionMap = asMap(rawName);
        }
      }
    }
    if (optionMap != null) {
      for (final entry in optionMap.entries) {
        final v = entry.value?.toString().trim() ?? '';
        if (v.isEmpty) continue;
        localized[entry.key.toString().trim().toLowerCase()] = v;
      }
    }

    final fallback = pickStr(addonMap, const [
      'name_ar',
      'name',
      'title',
      'option',
      'option_name',
    ]);
    final fallbackEn = pickStr(addonMap, const [
      'name_en',
      'option_en',
    ]);
    final price = parsePrice(addonMap['price'] ?? addonMap['amount']);

    final displayAr =
        localized['ar']?.isNotEmpty == true ? localized['ar']! : fallback;
    final displayEn = localized['en']?.isNotEmpty == true
        ? localized['en']!
        : (fallbackEn.isEmpty ? fallback : fallbackEn);

    if (displayAr.isEmpty && displayEn.isEmpty && localized.isEmpty) continue;

    result.add(ReceiptAddon(
      nameAr: displayAr,
      nameEn: displayEn,
      price: price,
      localizedNames: localized,
    ));
  }
  if (kDebugMode) {
    debugPrint(
        '[addon-extractor] produced ${result.length} addons: ${result.map((a) => a.nameAr).toList()}');
  }
  return result;
}

Map<String, dynamic>? _tryDecodeJsonMap(String s) {
  final trimmed = s.trim();
  if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
  } catch (_) {}
  return null;
}
