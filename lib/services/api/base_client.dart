import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'api_constants.dart';
import 'error_handler.dart';

// HTTP Client Configuration Constants
class _HttpConfig {
  static const Duration requestTimeout = Duration(seconds: 15);
  static const Duration connectionTimeout = Duration(seconds: 8);
  static const Duration idleTimeout = Duration(seconds: 30);
  static const int maxConnectionsPerHost = 6;
  static const int maxRetries = 1;
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? userMessage;
  final dynamic responseBody;
  final String? requestUrl;

  ApiException(
    this.message, {
    this.statusCode,
    this.userMessage,
    this.responseBody,
    this.requestUrl,
  });

  @override
  String toString() =>
      'ApiException: $message (Status: $statusCode, Url: $requestUrl)';
}

class UnauthorizedException extends ApiException {
  UnauthorizedException(
    super.message, {
    super.userMessage,
    super.requestUrl,
  }) : super(statusCode: 401);
}

class BaseClient {
  http.Client? _client;
  HttpClient? _httpClient;

  // Singleton pattern
  static final BaseClient _instance = BaseClient._internal();
  factory BaseClient() => _instance;
  BaseClient._internal() {
    _initClient();
  }

  /// Initialize HTTP client with proper configuration
  void _initClient() {
    _httpClient = HttpClient()
      ..connectionTimeout = _HttpConfig.connectionTimeout
      ..idleTimeout = _HttpConfig.idleTimeout
      ..maxConnectionsPerHost = _HttpConfig.maxConnectionsPerHost;

    _client = IOClient(_httpClient);
    if (kDebugMode) debugPrint('🔧 BaseClient initialized with connection pooling');
  }

  /// Get or recreate the HTTP client
  http.Client get _safeClient {
    if (_client == null) {
      _initClient();
    }
    return _client!;
  }

  /// Recreate client if connection issues occur
  void _recreateClient() {
    if (kDebugMode) debugPrint('🔄 Recreating HTTP client due to connection issue');
    try {
      _client?.close();
    } catch (e) {
      // Ignore close errors
    }
    _initClient();
  }

  /// Execute request with retry logic for connection issues
  Future<dynamic> _executeWithRetry(
    Future<dynamic> Function() request, {
    required String endpoint,
    required String method,
    int attempt = 0,
  }) async {
    try {
      return await request();
    } catch (e) {
      final errorString = e.toString().toLowerCase();
      final isConnectionClosedError =
          errorString.contains('connection closed') ||
              errorString.contains('connection closed before full header');

      if (isConnectionClosedError && attempt < _HttpConfig.maxRetries) {
        if (kDebugMode) debugPrint(
            '⚠️ Connection closed error detected, retrying... (attempt ${attempt + 1})');
        _recreateClient();
        await Future.delayed(const Duration(milliseconds: 500));
        return _executeWithRetry(
          request,
          endpoint: endpoint,
          method: method,
          attempt: attempt + 1,
        );
      }
      rethrow;
    }
  }

  /// Visible for testing to inject mock client
  void setClientForTesting(http.Client client) {
    _client = client;
    _httpClient = null; // Not using custom HttpClient in test mode
  }

  /// Callback for handling 401 unauthorized errors
  static Future<void> Function()? onUnauthorized;
  static bool _isHandlingUnauthorized = false;

  String? _authToken;

  void setToken(String token) {
    _authToken = token;
    if (kDebugMode) debugPrint('🔑 BaseClient token set');
  }

  String? getToken() {
    return _authToken;
  }

  /// Visible for testing to verify headers
  Map<String, String> getHeadersForTesting() => _headers;

  void clearToken() {
    _authToken = null;
  }

  Uri _getUri(String endpoint, {String? customBaseUrl}) {
    if (endpoint.startsWith('http')) return Uri.parse(endpoint);
    return Uri.parse('${customBaseUrl ?? ApiConstants.baseUrl}$endpoint');
  }

  Future<dynamic> get(String endpoint,
      {String? customBaseUrl,
      bool skipGlobalAuth = false,
      Map<String, String>? headers}) async {
    return _executeWithRetry(
      () => _getInternal(endpoint,
          customBaseUrl: customBaseUrl,
          skipGlobalAuth: skipGlobalAuth,
          headers: headers),
      endpoint: endpoint,
      method: 'GET',
    );
  }

  Future<dynamic> _getInternal(String endpoint,
      {String? customBaseUrl,
      bool skipGlobalAuth = false,
      Map<String, String>? headers}) async {
    final uri = _getUri(endpoint, customBaseUrl: customBaseUrl);
    try {
      // Per-request header overrides (e.g. forcing Accept-Language for a
      // printed report) layer on top of the base auth/accept headers.
      final effectiveHeaders = {..._headers, ...?headers};
      final response = await _safeClient
          .get(uri, headers: effectiveHeaders)
          .timeout(_HttpConfig.requestTimeout);
      return await _processResponse(response,
          skipGlobalAuth: skipGlobalAuth, requestUrl: uri.toString());
    } on TimeoutException catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'GET $endpoint',
      );
    } on SocketException catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'GET $endpoint',
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'GET $endpoint',
      );
    }
  }

  Future<dynamic> post(String endpoint, dynamic payload,
      {String? customBaseUrl,
      bool skipGlobalAuth = false,
      Map<String, String>? headers}) async {
    return _executeWithRetry(
      () => _postInternal(endpoint, payload,
          customBaseUrl: customBaseUrl,
          skipGlobalAuth: skipGlobalAuth,
          headers: headers),
      endpoint: endpoint,
      method: 'POST',
    );
  }

  Future<dynamic> _postInternal(String endpoint, dynamic payload,
      {String? customBaseUrl,
      bool skipGlobalAuth = false,
      Map<String, String>? headers}) async {
    final uri = _getUri(endpoint, customBaseUrl: customBaseUrl);
    try {
      final combinedHeaders = {..._headers, ...?headers};
      final response = await _safeClient
          .post(
            uri,
            headers: combinedHeaders,
            body: jsonEncode(payload),
          )
          .timeout(_HttpConfig.requestTimeout);
      return await _processResponse(response,
          skipGlobalAuth: skipGlobalAuth, requestUrl: uri.toString());
    } on TimeoutException catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'POST $endpoint',
      );
    } on SocketException catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'POST $endpoint',
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'POST $endpoint',
      );
    }
  }

  Future<dynamic> postMultipart(String endpoint, Map<String, String> fields,
      {Map<String, String>? files,
      String? customBaseUrl,
      bool skipGlobalAuth = false}) async {
    final uri = _getUri(endpoint, customBaseUrl: customBaseUrl);
    try {
      var request = http.MultipartRequest('POST', uri);
      request.fields.addAll(fields);

      if (files != null) {
        for (var entry in files.entries) {
          if (await File(entry.value).exists()) {
            request.files
                .add(await http.MultipartFile.fromPath(entry.key, entry.value));
          }
        }
      }

      // Let MultipartRequest own the content-type/boundary header.
      final multipartHeaders = Map<String, String>.from(_headers)
        ..remove('Content-Type');
      request.headers.addAll(multipartHeaders);

      final streamedResponse =
          await _safeClient.send(request).timeout(_HttpConfig.requestTimeout);
      final response = await http.Response.fromStream(streamedResponse)
          .timeout(_HttpConfig.requestTimeout);
      return await _processResponse(response,
          skipGlobalAuth: skipGlobalAuth, requestUrl: uri.toString());
    } on TimeoutException catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'POST-MULTIPART $endpoint',
      );
    } on SocketException catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'POST-MULTIPART $endpoint',
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'POST-MULTIPART $endpoint',
      );
    }
  }

  /// POST with application/x-www-form-urlencoded body.
  /// Accepts a raw body string, supporting duplicate keys (e.g. refund[]=1&refund[]=2).
  Future<dynamic> postFormEncoded(String endpoint, String body,
      {String? customBaseUrl, bool skipGlobalAuth = false}) async {
    final uri = _getUri(endpoint, customBaseUrl: customBaseUrl);
    try {
      final headers = Map<String, String>.from(_headers);
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
      final response = await _safeClient
          .post(uri, headers: headers, body: body)
          .timeout(_HttpConfig.requestTimeout);
      return await _processResponse(response,
          skipGlobalAuth: skipGlobalAuth, requestUrl: uri.toString());
    } on TimeoutException catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'POST-FORM $endpoint',
      );
    } on SocketException catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'POST-FORM $endpoint',
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'POST-FORM $endpoint',
      );
    }
  }

  Future<dynamic> patchMultipart(String endpoint, Map<String, String> fields,
      {Map<String, String>? files,
      String? customBaseUrl,
      bool skipGlobalAuth = false}) async {
    final uri = _getUri(endpoint, customBaseUrl: customBaseUrl);
    try {
      var request = http.MultipartRequest('PATCH', uri);
      request.fields.addAll(fields);

      if (files != null) {
        for (var entry in files.entries) {
          if (await File(entry.value).exists()) {
            request.files
                .add(await http.MultipartFile.fromPath(entry.key, entry.value));
          }
        }
      }

      // Let MultipartRequest own the content-type/boundary header.
      final multipartHeaders = Map<String, String>.from(_headers)
        ..remove('Content-Type');
      request.headers.addAll(multipartHeaders);

      final streamedResponse =
          await _safeClient.send(request).timeout(_HttpConfig.requestTimeout);
      final response = await http.Response.fromStream(streamedResponse)
          .timeout(_HttpConfig.requestTimeout);
      return await _processResponse(response,
          skipGlobalAuth: skipGlobalAuth, requestUrl: uri.toString());
    } on TimeoutException catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'PATCH-MULTIPART $endpoint',
      );
    } on SocketException catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'PATCH-MULTIPART $endpoint',
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'PATCH-MULTIPART $endpoint',
      );
    }
  }

  Future<dynamic> put(String endpoint, dynamic payload,
      {String? customBaseUrl, bool skipGlobalAuth = false}) async {
    return _executeWithRetry(
      () => _putInternal(endpoint, payload,
          customBaseUrl: customBaseUrl, skipGlobalAuth: skipGlobalAuth),
      endpoint: endpoint,
      method: 'PUT',
    );
  }

  Future<dynamic> _putInternal(String endpoint, dynamic payload,
      {String? customBaseUrl, bool skipGlobalAuth = false}) async {
    final uri = _getUri(endpoint, customBaseUrl: customBaseUrl);
    try {
      final response = await _safeClient
          .put(
            uri,
            headers: _headers,
            body: jsonEncode(payload),
          )
          .timeout(_HttpConfig.requestTimeout);
      return await _processResponse(response,
          skipGlobalAuth: skipGlobalAuth, requestUrl: uri.toString());
    } on TimeoutException catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'PUT $endpoint',
      );
    } on SocketException catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'PUT $endpoint',
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'PUT $endpoint',
      );
    }
  }

  Future<dynamic> patch(String endpoint, dynamic payload,
      {String? customBaseUrl, bool skipGlobalAuth = false}) async {
    return _executeWithRetry(
      () => _patchInternal(endpoint, payload,
          customBaseUrl: customBaseUrl, skipGlobalAuth: skipGlobalAuth),
      endpoint: endpoint,
      method: 'PATCH',
    );
  }

  Future<dynamic> _patchInternal(String endpoint, dynamic payload,
      {String? customBaseUrl, bool skipGlobalAuth = false}) async {
    final uri = _getUri(endpoint, customBaseUrl: customBaseUrl);
    try {
      final encodedBody = jsonEncode(payload);
      if (kDebugMode) {
        debugPrint('🌐 PATCH Request: $uri');
      }

      final response = await _safeClient
          .patch(
            uri,
            headers: _headers,
            body: encodedBody,
          )
          .timeout(_HttpConfig.requestTimeout);

      if (kDebugMode) {
        debugPrint('🌐 PATCH Response: ${response.statusCode}');
      }

      return await _processResponse(response,
          skipGlobalAuth: skipGlobalAuth, requestUrl: uri.toString());
    } on TimeoutException catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'PATCH $endpoint',
      );
    } on SocketException catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'PATCH $endpoint',
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'PATCH $endpoint',
      );
    }
  }

  Future<dynamic> delete(String endpoint,
      {String? customBaseUrl, bool skipGlobalAuth = false}) async {
    return _executeWithRetry(
      () => _deleteInternal(endpoint,
          customBaseUrl: customBaseUrl, skipGlobalAuth: skipGlobalAuth),
      endpoint: endpoint,
      method: 'DELETE',
    );
  }

  Future<dynamic> _deleteInternal(String endpoint,
      {String? customBaseUrl, bool skipGlobalAuth = false}) async {
    final uri = _getUri(endpoint, customBaseUrl: customBaseUrl);
    try {
      final response = await _safeClient
          .delete(uri, headers: _headers)
          .timeout(_HttpConfig.requestTimeout);
      return await _processResponse(response,
          skipGlobalAuth: skipGlobalAuth, requestUrl: uri.toString());
    } on TimeoutException catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'DELETE $endpoint',
      );
    } on SocketException catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'DELETE $endpoint',
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ErrorHandler.fromException(
        e,
        requestUrl: uri.toString(),
        operation: 'DELETE $endpoint',
      );
    }
  }

  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
      ...ApiConstants.defaultHeaders,
    };
    if (_authToken != null && _authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_authToken';
      if (kDebugMode) debugPrint('🔒 Adding auth header');
    } else {
      if (kDebugMode) debugPrint('⚠️ No auth token available for request');
    }
    return headers;
  }

  dynamic _processResponse(http.Response response,
      {bool skipGlobalAuth = false, String? requestUrl}) async {
    // Handle redirects (301, 302, 307, 308)
    if (response.statusCode == 301 ||
        response.statusCode == 302 ||
        response.statusCode == 307 ||
        response.statusCode == 308) {
      final location = response.headers['location'];
      if (location != null) {
        throw ApiException(
          'Redirect required to: $location',
          statusCode: response.statusCode,
          userMessage: 'تم تحويل الطلب بشكل غير متوقع. حاول مرة أخرى.',
          requestUrl: requestUrl,
        );
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      try {
        return jsonDecode(response.body);
      } on FormatException {
        throw ErrorHandler.jsonParsingFailure(
          requestUrl: requestUrl ?? 'unknown',
          rawBody: response.body,
        );
      }
    } else if (response.statusCode == 401) {
      if (kDebugMode) debugPrint('🚫 401 Unauthorized from: ${requestUrl ?? 'unknown'}');
      // Trigger unauthorized callback (with guard to prevent multiple triggers)
      if (!skipGlobalAuth && !_isHandlingUnauthorized) {
        _isHandlingUnauthorized = true;
        if (kDebugMode) debugPrint('🚫 401 Unauthorized - triggering logout callback');
        try {
          await onUnauthorized?.call();
        } finally {
          // Keep guard active for 2 seconds to prevent cascading 401s
          Future.delayed(const Duration(seconds: 2), () {
            _isHandlingUnauthorized = false;
          });
        }
      }
      throw UnauthorizedException(
        'UNAUTHENTICATED',
        userMessage: 'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.',
        requestUrl: requestUrl,
      );
    } else {
      throw ErrorHandler.fromHttpResponse(
        response,
        requestUrl: requestUrl,
      );
    }
  }
}
