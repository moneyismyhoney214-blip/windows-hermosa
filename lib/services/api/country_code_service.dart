import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_constants.dart';

/// One country row from `portal.hermosaapp.com/countries/cities`.
///
/// We keep the same shape the backend uses (`label`, `value`, `area_code`)
/// so the picker can match the active branch via [ApiConstants.branchCountryId].
class CountryOption {
  final int value;
  final String label;
  final String areaCode;

  const CountryOption({
    required this.value,
    required this.label,
    required this.areaCode,
  });

  factory CountryOption.fromJson(Map<String, dynamic> json) {
    final raw = json['area_code']?.toString().trim() ?? '';
    final normalized = raw.startsWith('+') ? raw : '+$raw';
    final value = json['value'];
    return CountryOption(
      value: value is num ? value.toInt() : int.tryParse('$value') ?? 0,
      label: json['label']?.toString() ?? '',
      areaCode: normalized,
    );
  }

  Map<String, dynamic> toJson() => {
        'value': value,
        'label': label,
        'area_code': areaCode,
      };

  /// `+966` → `966`. The WhatsApp normalizer wants digits-only.
  String get digits => areaCode.replaceAll(RegExp(r'[^0-9]'), '');
}

/// Loads + caches the country list. The list is small (≈250 rows) so we
/// hold it in memory for the whole session and persist a single copy in
/// prefs as a warm-start cache — first launch on an offline device falls
/// back to a hard-coded Saudi-only entry so the picker still renders.
class CountryCodeService {
  static final CountryCodeService _instance = CountryCodeService._internal();
  factory CountryCodeService() => _instance;
  CountryCodeService._internal();

  static const String _prefsKey = 'country_options_cache_v1';
  static const String _endpoint =
      'https://portal.hermosaapp.com/countries/cities';

  static const CountryOption _saudiFallback = CountryOption(
    value: 1,
    label: 'Saudi Arabia',
    areaCode: '+966',
  );

  List<CountryOption> _options = const [];
  Future<List<CountryOption>>? _inflight;

  /// Cached snapshot. Empty until [load] resolves at least once.
  List<CountryOption> get options => List.unmodifiable(_options);

  /// Lookup by the `value` field — that's what `branch.country_id`
  /// matches. Returns Saudi as a final fallback so the picker always
  /// has *something* to show on a fresh install.
  CountryOption byValue(int value) {
    for (final c in _options) {
      if (c.value == value) return c;
    }
    return _options.isNotEmpty ? _options.first : _saudiFallback;
  }

  /// Default for the active branch. Use this when initializing a phone
  /// field — it picks the branch's country, falling back to Saudi.
  CountryOption defaultForBranch() => byValue(ApiConstants.branchCountryId);

  /// Idempotent load. Returns the in-memory cache when it's already
  /// populated. Otherwise hydrates from prefs first (so the UI has
  /// *something* to render immediately) and then refreshes from the
  /// network in the background.
  Future<List<CountryOption>> load({bool forceRefresh = false}) {
    if (!forceRefresh && _options.isNotEmpty) {
      return Future.value(_options);
    }
    return _inflight ??= _loadInternal(forceRefresh: forceRefresh)
        .whenComplete(() => _inflight = null);
  }

  Future<List<CountryOption>> _loadInternal({required bool forceRefresh}) async {
    if (!forceRefresh) {
      final cached = await _readPrefs();
      if (cached.isNotEmpty) {
        _options = cached;
      }
    }

    try {
      final res = await http
          .get(Uri.parse(_endpoint))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final list = body is List
            ? body
            : (body is Map && body['data'] is List ? body['data'] as List : const []);
        final parsed = list
            .whereType<Map<String, dynamic>>()
            .map(CountryOption.fromJson)
            .where((c) => c.value > 0 && c.areaCode.length > 1)
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));
        if (parsed.isNotEmpty) {
          _options = parsed;
          await _writePrefs(parsed);
        }
      }
    } catch (e, st) {
      developer.log(
        'CountryCodeService: fetch failed — using cached/fallback list',
        error: e,
        stackTrace: st,
      );
    }

    if (_options.isEmpty) {
      _options = const [_saudiFallback];
    }
    return _options;
  }

  Future<List<CountryOption>> _readPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(CountryOption.fromJson)
          .where((c) => c.value > 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writePrefs(List<CountryOption> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(list.map((c) => c.toJson()).toList()),
      );
    } catch (_) {/* prefs failures shouldn't break the picker */}
  }
}

final countryCodeService = CountryCodeService();
