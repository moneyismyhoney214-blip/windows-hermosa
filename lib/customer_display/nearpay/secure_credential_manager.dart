import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Secure Credential Manager
/// Fetches terminal credentials from secure cloud storage instead of hardcoding
class SecureCredentialManager {
  static const String _credentialsEndpoint =
      'https://portal.hermosaapp.com/v1/terminal/credentials';
  static const Duration _cacheDuration = Duration(hours: 6);

  Map<String, dynamic>? _cachedCredentials;
  DateTime? _lastFetch;

  /// Fetch credentials from secure server
  /// CRITICAL FIX: Removes hardcoded credentials
  Future<Map<String, dynamic>> getCredentials(String authToken) async {
    // Check cache first
    if (_cachedCredentials != null && _lastFetch != null) {
      if (DateTime.now().difference(_lastFetch!) < _cacheDuration) {
        debugPrint('Using cached credentials');
        return _cachedCredentials!;
      }
    }

    try {
      final response = await http
          .get(
            Uri.parse(_credentialsEndpoint),
            headers: {
              'Authorization': 'Bearer $authToken',
              'Accept': 'application/json',
            },
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _cachedCredentials = data;
        _lastFetch = DateTime.now();
        debugPrint('Credentials fetched from secure server');
        return data;
      } else {
        throw Exception('Failed to fetch credentials: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching credentials: $e');
      // Fallback to cached if available
      if (_cachedCredentials != null) {
        return _cachedCredentials!;
      }
      throw Exception('No credentials available');
    }
  }

  /// Clear cached credentials
  void clearCache() {
    _cachedCredentials = null;
    _lastFetch = null;
    debugPrint('Credentials cache cleared');
  }
}

/// Singleton instance
final secureCredentialManager = SecureCredentialManager();
