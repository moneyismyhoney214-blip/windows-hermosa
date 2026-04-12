import 'package:flutter/foundation.dart';
import '../api/base_client.dart';
import '../api/api_constants.dart';

/// NearPay Service — fetches a JWT from the backend and caches it until expiry.
class NearPayService {
  // Singleton — shared cache so repeated calls never re-fetch unnecessarily
  static final NearPayService _instance = NearPayService._internal();
  factory NearPayService() => _instance;
  NearPayService._internal();

  String? _cachedJwt;
  DateTime? _jwtExpiry;
  // Prevent parallel in-flight fetches
  Future<String>? _inflight;

  /// Fetch (or return cached) NearPay JWT token.
  /// Calls POST {baseUrl}/nearpay/auth/token with {"branch_id": branchId}.
  /// Response: {"success": true, "data": {"token": "...", "expires_at": 1773086541, "expires_in": 3600}}
  Future<String> generateJwt() {
    // Return cached token if still valid (with 60 s safety margin)
    if (_cachedJwt != null && _jwtExpiry != null) {
      if (DateTime.now().add(const Duration(seconds: 60)).isBefore(_jwtExpiry!)) {
        return Future.value(_cachedJwt!);
      }
    }

    // Deduplicate: if a fetch is already in progress return the same Future
    if (_inflight != null) return _inflight!;

    _inflight = _fetchFromApi().whenComplete(() => _inflight = null);
    return _inflight!;
  }

  Future<String> _fetchFromApi() async {
    try {
      final response = await BaseClient().post(
        ApiConstants.nearPayAuthTokenEndpoint,
        {'branch_id': ApiConstants.branchId},
      );

      final data = response?['data'];
      final token = data?['token']?.toString();
      if (token == null || token.isEmpty) {
        throw Exception('NearPay auth token missing in response');
      }

      // Cache with expiry from server if available, otherwise 55 minutes
      final expiresAt = data?['expires_at'];
      if (expiresAt is int && expiresAt > 0) {
        _jwtExpiry = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
      } else {
        final expiresIn = data?['expires_in'];
        final seconds = (expiresIn is int && expiresIn > 0) ? expiresIn : 3600;
        _jwtExpiry = DateTime.now().add(Duration(seconds: seconds));
      }
      _cachedJwt = token;

      debugPrint('✅ NearPay JWT fetched successfully (expires: $_jwtExpiry)');
      return token;
    } catch (e) {
      debugPrint('❌ Error fetching NearPay JWT: $e');
      rethrow;
    }
  }

  /// Returns the cached JWT only if it is still valid, otherwise null.
  String? get cachedToken {
    if (_cachedJwt != null && _jwtExpiry != null) {
      if (DateTime.now().add(const Duration(seconds: 60)).isBefore(_jwtExpiry!)) {
        return _cachedJwt;
      }
    }
    return null;
  }

  /// Clear cached JWT (useful for logout or forced refresh)
  void clearCache() {
    _cachedJwt = null;
    _jwtExpiry = null;
    _inflight = null;
    debugPrint('NearPay JWT cache cleared');
  }
}
