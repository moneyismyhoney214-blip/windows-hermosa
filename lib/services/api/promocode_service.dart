import 'api_constants.dart';
import 'base_client.dart';
import '../../models.dart';
import 'package:hermosa_pos/services/offline/offline_database_service.dart';
import 'package:hermosa_pos/services/offline/connectivity_service.dart';

class PromoCodeService {
  final BaseClient _client = BaseClient();
  final OfflineDatabaseService _offlineDb = OfflineDatabaseService();
  final ConnectivityService _connectivity = ConnectivityService();

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  String _normalizeCode(String code) => code.trim().toLowerCase();

  String _extractCode(Map<String, dynamic> record) {
    final raw = record['code'] ??
        record['promocode'] ??
        record['promocodeValue'] ??
        record['promocode_name'] ??
        record['name'];
    if (raw is Map) {
      final ar = raw['ar']?.toString().trim();
      if (ar != null && ar.isNotEmpty) return ar;
      final en = raw['en']?.toString().trim();
      if (en != null && en.isNotEmpty) return en;
      for (final candidate in raw.values) {
        final text = candidate?.toString().trim();
        if (text != null && text.isNotEmpty) return text;
      }
      return '';
    }
    return raw?.toString().trim() ?? '';
  }

  bool _toBool(dynamic value, {bool defaultValue = true}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized.isEmpty) return defaultValue;
    if (normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes' ||
        normalized == 'active') {
      return true;
    }
    if (normalized == 'false' ||
        normalized == '0' ||
        normalized == 'no' ||
        normalized == 'inactive') {
      return false;
    }
    return defaultValue;
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed;
    if (raw.length >= 10) {
      return DateTime.tryParse(raw.substring(0, 10));
    }
    return null;
  }

  bool _isPromoActive(Map<String, dynamic> record) {
    final now = DateTime.now();
    final isActive = _toBool(
      record['is_active'] ?? record['active'] ?? record['status'],
      defaultValue: true,
    );
    if (!isActive) return false;

    final startsAt = _parseDate(record['start_date'] ?? record['start_at']);
    final endsAt = _parseDate(record['end_date'] ?? record['expire_at']);

    if (startsAt != null && now.isBefore(startsAt)) return false;
    if (endsAt != null) {
      final inclusiveEnd = DateTime(
        endsAt.year,
        endsAt.month,
        endsAt.day,
        23,
        59,
        59,
        999,
      );
      if (now.isAfter(inclusiveEnd)) return false;
    }

    final maxUses = _toInt(record['max_uses']);
    final used = _toInt(
      record['used_count'] ?? record['uses_count'] ?? record['used'],
    );
    if (maxUses > 0 && used >= maxUses) return false;

    return true;
  }

  bool _looksLikePromoRecord(Map<String, dynamic> map) {
    return map.containsKey('code') ||
        map.containsKey('promocode') ||
        map.containsKey('discount') ||
        map.containsKey('discount_value') ||
        map.containsKey('discount_type');
  }

  List<Map<String, dynamic>> _extractPromoRecords(dynamic response) {
    final queue = <dynamic>[response];
    final records = <Map<String, dynamic>>[];
    final seenKeys = <String>{};

    while (queue.isNotEmpty) {
      final node = queue.removeLast();
      if (node == null) continue;

      if (node is List) {
        for (final item in node) {
          queue.add(item);
        }
        continue;
      }

      final map = _asMap(node);
      if (map == null) continue;

      if (_looksLikePromoRecord(map)) {
        final code = _extractCode(map);
        final id = map['id']?.toString() ?? '';
        final key = '${id.trim()}:${code.trim().toLowerCase()}';
        if (seenKeys.add(key)) {
          records.add(map);
        }
      }

      for (final key in const [
        'data',
        'promocode',
        'promo_code',
        'promocodes',
        'results',
        'result',
        'items',
        'list',
      ]) {
        if (map.containsKey(key)) {
          queue.add(map[key]);
        }
      }

      // Some payloads are wrapped under non-standard keys.
      for (final value in map.values) {
        if (value is Map || value is List) {
          queue.add(value);
        }
      }
    }

    return records;
  }

  PromoCode? _promoFromRecord(
    Map<String, dynamic> record, {
    String? fallbackCode,
  }) {
    final normalized = Map<String, dynamic>.from(record);
    if ((normalized['code']?.toString().trim().isEmpty ?? true) &&
        fallbackCode != null &&
        fallbackCode.isNotEmpty) {
      normalized['code'] = fallbackCode;
    }
    try {
      final promo = PromoCode.fromJson(normalized);
      if (promo.id.trim().isEmpty || promo.code.trim().isEmpty) {
        return null;
      }
      return promo;
    } catch (_) {
      return null;
    }
  }

  PromoCode? _findPromoByCode(
    dynamic response,
    String normalizedCode, {
    bool allowSingleRecordFallback = false,
  }) {
    final records = _extractPromoRecords(response);
    for (final record in records) {
      final recordCode = _normalizeCode(_extractCode(record));
      if (recordCode != normalizedCode) continue;
      if (!_isPromoActive(record)) continue;
      final promo = _promoFromRecord(record);
      if (promo != null) return promo;
    }

    if (allowSingleRecordFallback && records.length == 1) {
      final record = records.first;
      if (!_isPromoActive(record)) return null;
      return _promoFromRecord(record, fallbackCode: normalizedCode);
    }

    return null;
  }

  List<PromoCode> _promosFromResponse(dynamic response) {
    final records = _extractPromoRecords(response);
    final promos = <PromoCode>[];
    final seen = <String>{};

    for (final record in records) {
      if (!_isPromoActive(record)) continue;
      final promo = _promoFromRecord(record);
      if (promo == null) continue;
      final key = '${promo.id}:${_normalizeCode(promo.code)}';
      if (seen.add(key)) {
        promos.add(promo);
      }
    }
    return promos;
  }

  bool _isNotFoundOrValidation(Object error) {
    return error is ApiException &&
        (error.statusCode == 404 || error.statusCode == 422);
  }

  /// Get all promo codes for the branch
  Future<List<PromoCode>> getAllPromoCodes() async {
    return getPromoCodes();
  }

  Future<List<PromoCode>> getPromoCodes() async {
    // OFFLINE MODE
    if (_connectivity.isOffline) {
      return _getPromoCodesOffline();
    }

    final responses = <dynamic>[];
    try {
      responses.add(await _client.get(ApiConstants.promocodesEndpoint));
    } catch (_) {}
    try {
      responses
          .add(await _client.get(ApiConstants.allPromocodesFilterEndpoint));
    } catch (_) {}

    final merged = <PromoCode>[];
    final seen = <String>{};
    for (final response in responses) {
      for (final promo in _promosFromResponse(response)) {
        final key = '${promo.id}:${_normalizeCode(promo.code)}';
        if (seen.add(key)) {
          merged.add(promo);
        }
      }
    }

    // Save to SQLite for offline
    if (merged.isNotEmpty) {
      await _offlineDb.savePromoCodes(
        merged.map((p) => p.toJson()).toList(),
        ApiConstants.branchId,
      );
    }

    return merged;
  }

  Future<List<PromoCode>> _getPromoCodesOffline() async {
    try {
      final local = await _offlineDb.getPromoCodes(ApiConstants.branchId);
      return local.map((e) => PromoCode.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get promo code details by its code
  Future<PromoCode?> getPromoCodeByCode(String code) async {
    final normalizedCode = _normalizeCode(code);
    if (normalizedCode.isEmpty) return null;
    final encodedCode = Uri.encodeQueryComponent(code.trim());

    final endpoints = <({String endpoint, bool allowSingleFallback})>[
      (
        endpoint: ApiConstants.getPromoCodeEndpoint(encodedCode),
        allowSingleFallback: true,
      ),
      (
        endpoint:
            '${ApiConstants.allPromocodesFilterEndpoint}?code=$encodedCode',
        allowSingleFallback: false,
      ),
      (
        endpoint: ApiConstants.allPromocodesFilterEndpoint,
        allowSingleFallback: false,
      ),
      (
        endpoint: ApiConstants.promocodesEndpoint,
        allowSingleFallback: false,
      ),
    ];

    for (final candidate in endpoints) {
      try {
        final response = await _client.get(candidate.endpoint);
        final promo = _findPromoByCode(
          response,
          normalizedCode,
          allowSingleRecordFallback: candidate.allowSingleFallback,
        );
        if (promo != null) return promo;
      } catch (e) {
        if (_isNotFoundOrValidation(e)) {
          continue;
        }
        print('Error fetching promo code from ${candidate.endpoint}: $e');
      }
    }

    return null;
  }
}
