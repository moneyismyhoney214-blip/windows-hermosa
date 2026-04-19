import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// NearPay Backend Service
/// Handles communication with the backend API for NearPay
class NearPayBackendService {
  final String baseUrl;
  final String authToken;
  final int branchId;
  final http.Client _httpClient;

  NearPayBackendService({
    required this.baseUrl,
    required this.authToken,
    required this.branchId,
    http.Client? client,
  }) : _httpClient = client ?? http.Client();

  static const _timeout = Duration(seconds: 30);

  Uri _buildUri(String path) {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$trimmed$normalizedPath');
  }

  Map<String, dynamic> _decodeJson(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw Exception(
        'استجابة غير صالحة من السيرفر (status ${response.statusCode})',
      );
    }
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  String? _toNonEmptyString(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  /// Fetch JWT Token from backend
  /// POST {{base_url}}/seller/nearpay/auth/token
  /// Body: {"branch_id": ..., "terminal_tid": ..., "terminal_id": ...}
  Future<NearPayJwtPayload> fetchJwtToken({
    String? terminalTid,
    String? terminalId,
  }) async {
    final url = _buildUri('/seller/nearpay/auth/token');

    try {
      final body = <String, dynamic>{'branch_id': branchId};
      if (terminalTid != null) body['terminal_tid'] = terminalTid;
      if (terminalId != null) body['terminal_id'] = terminalId;

      debugPrint('[NearPay-API] POST $url');
      debugPrint('[NearPay-API]   body: ${jsonEncode(body)}');
      debugPrint(
        '[NearPay-API]   auth: Bearer ${authToken.length > 10 ? '${authToken.substring(0, 10)}...' : authToken}',
      );

      final response = await _httpClient
          .post(
            url,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      debugPrint('[NearPay-API]   status: ${response.statusCode}');
      debugPrint(
        '[NearPay-API]   response_body: ${response.body.length > 500 ? '${response.body.substring(0, 500)}...' : response.body}',
      );

      final responseData = _decodeJson(response);

      if (response.statusCode != 200 || responseData['success'] != true) {
        final message = responseData['message'] ?? 'فشل الحصول على JWT Token';
        debugPrint('[NearPay-API]   ERROR: $message');
        throw Exception(message);
      }

      final data = responseData['data'];
      if (data is! Map<String, dynamic>) {
        debugPrint(
          '[NearPay-API]   ERROR: data is ${data.runtimeType}, not Map',
        );
        throw Exception('استجابة غير صالحة: بيانات JWT مفقودة');
      }

      final token = _toNonEmptyString(data['token']);
      if (token == null) {
        debugPrint('[NearPay-API]   ERROR: token missing in response payload');
        throw Exception('استجابة غير صالحة: رمز JWT مفقود');
      }
      debugPrint('[NearPay-API]   token_length: ${token.length}');
      debugPrint('[NearPay-API]   expires_at: ${data['expires_at']}');
      debugPrint('[NearPay-API]   expires_in: ${data['expires_in']}');
      debugPrint('[NearPay-API]   data_keys: ${data.keys.toList()}');

      String? jwtClientUuid;
      String? jwtTerminalIdInToken;

      // Decode JWT payload for debugging and extracting stable metadata.
      try {
        final parts = token.split('.');
        if (parts.length == 3) {
          final payloadB64 = base64Url.normalize(parts[1]);
          final payloadJson = utf8.decode(base64Url.decode(payloadB64));
          final payload = jsonDecode(payloadJson);
          if (payload is Map) {
            debugPrint(
              '[NearPay-API]   jwt_payload_keys: ${payload.keys.toList()}',
            );
            if (payload['data'] is Map) {
              final jwtData = payload['data'] as Map;
              debugPrint('[NearPay-API]   jwt_data.ops: ${jwtData['ops']}');
              debugPrint(
                '[NearPay-API]   jwt_data.terminal_id: ${jwtData['terminal_id']}',
              );
              debugPrint(
                '[NearPay-API]   jwt_data.client_uuid: ${jwtData['client_uuid']}',
              );
              jwtClientUuid = _toNonEmptyString(
                jwtData['client_uuid'] ?? jwtData['clientUUID'] ?? jwtData['merchant_uuid'],
              );
              jwtTerminalIdInToken = _toNonEmptyString(
                jwtData['terminal_id'] ?? jwtData['terminal_tid'],
              );
            }
          }
        }
      } catch (_) {
        debugPrint('[NearPay-API]   jwt_decode: failed (not critical)');
      }

      return NearPayJwtPayload(
        token: token,
        expiresAt: _toInt(data['expires_at']),
        expiresIn: _toInt(data['expires_in']),
        clientUuid: jwtClientUuid,
        terminalIdInToken: jwtTerminalIdInToken,
      );
    } on TimeoutException {
      debugPrint('[NearPay-API]   TIMEOUT after ${_timeout.inSeconds}s');
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (e) {
      debugPrint('[NearPay-API]   EXCEPTION: $e');
      if (e is Exception) rethrow;
      throw Exception('خطأ في الاتصال: $e');
    }
  }

  /// Fetch terminal config for this branch
  /// GET {{base_url}}/seller/nearpay/terminal/config?branch_id={{branch_id}}
  Future<NearPayTerminalConfig> fetchTerminalConfig() async {
    final url = _buildUri('/seller/nearpay/terminal/config');
    final uri = url.replace(
      queryParameters: {'branch_id': branchId.toString()},
    );

    try {
      debugPrint('[NearPay-API] ═══ fetchTerminalConfig ═══');
      debugPrint('[NearPay-API] GET $uri');
      debugPrint('[NearPay-API]   branch_id: $branchId');
      debugPrint(
        '[NearPay-API]   auth: Bearer ${authToken.length > 10 ? '${authToken.substring(0, 10)}...' : authToken}',
      );

      final stopwatch = Stopwatch()..start();
      final response = await _httpClient
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
          )
          .timeout(_timeout);
      stopwatch.stop();

      debugPrint('[NearPay-API]   status: ${response.statusCode}');
      debugPrint(
        '[NearPay-API]   duration_ms: ${stopwatch.elapsedMilliseconds}',
      );
      debugPrint(
        '[NearPay-API]   response_body: ${response.body.length > 500 ? '${response.body.substring(0, 500)}...' : response.body}',
      );

      final responseData = _decodeJson(response);

      if (response.statusCode != 200 || responseData['success'] != true) {
        final message =
            responseData['message'] ?? 'فشل الحصول على بيانات التيرمينال';
        debugPrint('[NearPay-API]   ERROR: $message');
        throw Exception(message);
      }

      final data = responseData['data'];
      if (data is! Map<String, dynamic>) {
        debugPrint(
          '[NearPay-API]   ERROR: data is ${data.runtimeType}, not Map',
        );
        throw Exception('استجابة غير صالحة: بيانات التيرمينال مفقودة');
      }

      debugPrint('[NearPay-API]   data_keys: ${data.keys.toList()}');
      debugPrint('[NearPay-API]   terminal_tid: ${data['terminal_tid']}');
      debugPrint('[NearPay-API]   terminal_id: ${data['terminal_id']}');
      debugPrint('[NearPay-API]   expires_in: ${data['expires_in']}');
      debugPrint('[NearPay-API]   expires_at: ${data['expires_at']}');

      final terminalTid = _toNonEmptyString(data['terminal_tid']);
      final terminalId = _toNonEmptyString(data['terminal_id']);
      if (terminalTid == null || terminalId == null) {
        throw Exception('استجابة غير صالحة: terminal_tid أو terminal_id مفقود');
      }

      return NearPayTerminalConfig(
        terminalTid: terminalTid,
        terminalId: terminalId,
        expiresIn: _toInt(data['expires_in']),
        expiresAt: _toNonEmptyString(data['expires_at']),
      );
    } on TimeoutException {
      debugPrint('[NearPay-API]   TIMEOUT after ${_timeout.inSeconds}s');
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (e) {
      debugPrint('[NearPay-API]   EXCEPTION: $e');
      if (e is Exception) rethrow;
      throw Exception('خطأ في الاتصال: $e');
    }
  }

  /// Fetch the SDK-facing user/client UUID from terminals list endpoint.
  ///
  /// GET {{base_url}}/seller/nearpay/terminals
  /// Matches by `id` (terminal UUID) or `tid`.
  ///
  /// Important:
  /// Some payloads include a nested `user.id`, but that value is not the same
  /// identifier expected by NearPay Terminal SDK `getUserByUUID(...)`.
  /// We only accept explicit SDK identifiers such as `user_uuid` or
  /// `client_uuid`.
  Future<String?> fetchTerminalUserUuid({
    required String terminalId,
    String? terminalTid,
  }) async {
    final url = _buildUri('/seller/nearpay/terminals');

    try {
      debugPrint('[NearPay-API] ═══ fetchTerminalUserUuid ═══');
      debugPrint('[NearPay-API] GET $url');
      debugPrint('[NearPay-API]   terminal_id: $terminalId');
      debugPrint('[NearPay-API]   terminal_tid: $terminalTid');

      final response = await _httpClient
          .get(
            url,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
          )
          .timeout(_timeout);

      final responseData = _decodeJson(response);
      if (response.statusCode != 200 || responseData['success'] != true) {
        final message =
            responseData['message'] ?? 'فشل الحصول على قائمة التيرمينالات';
        throw Exception(message);
      }

      final data = responseData['data'];
      final terminals = data is Map ? data['terminals'] : null;
      if (terminals is! List) {
        return null;
      }

      for (final item in terminals) {
        if (item is! Map) continue;
        final itemId = _toNonEmptyString(item['id']);
        final itemTid = _toNonEmptyString(item['tid']);
        final idMatches = itemId == terminalId;
        final tidMatches = terminalTid != null && terminalTid.isNotEmpty
            ? itemTid == terminalTid
            : false;
        if (!idMatches && !tidMatches) continue;

        final terminalUserUuid = _toNonEmptyString(
          item['user_uuid'] ?? item['client_uuid'] ?? item['merchant_uuid'],
        );
        if (terminalUserUuid != null) {
          debugPrint('[NearPay-API]   terminal_user_uuid: $terminalUserUuid');
          return terminalUserUuid;
        }

        // Check merchant.id as the UUID (NearPay merchant UUID)
        final merchant = item['merchant'];
        if (merchant is Map) {
          final merchantUuid = _toNonEmptyString(
            merchant['uuid'] ?? merchant['merchant_uuid'] ?? merchant['id'],
          );
          if (merchantUuid != null) {
            debugPrint('[NearPay-API]   merchant_uuid: $merchantUuid');
            return merchantUuid;
          }
        }

        final user = item['user'];
        if (user is Map) {
          final nestedSdkUserUuid = _toNonEmptyString(
            user['user_uuid'] ?? user['client_uuid'] ?? user['merchant_uuid'],
          );
          if (nestedSdkUserUuid != null) {
            debugPrint(
              '[NearPay-API]   nested_terminal_user_uuid: $nestedSdkUserUuid',
            );
            return nestedSdkUserUuid;
          }

          // Use user.id as last resort
          final nestedUserId = _toNonEmptyString(user['id']);
          if (nestedUserId != null) {
            debugPrint(
              '[NearPay-API]   using user.id as fallback uuid: $nestedUserId',
            );
            return nestedUserId;
          }
        }
      }

      return null;
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('خطأ في الاتصال: $e');
    }
  }

  /// Create purchase session
  /// POST {{base_url}}/seller/nearpay/session/purchase
  /// Body: {"branch_id": {{branch_id}}, "amount": 50.00, "reference_id": "INV-001"}
  Future<NearPayPurchaseSession> createPurchaseSession({
    required int amountInHalalas,
    required String referenceId,
  }) async {
    final url = _buildUri('/seller/nearpay/session/purchase');

    try {
      final body = {
        'branch_id': branchId,
        'amount': amountInHalalas,
        'reference_id': referenceId,
      };

      debugPrint('[NearPay-API] ═══ createPurchaseSession ═══');
      debugPrint('[NearPay-API] POST $url');
      debugPrint('[NearPay-API]   body: ${jsonEncode(body)}');
      debugPrint(
        '[NearPay-API]   amount_halalas: $amountInHalalas (SAR ${(amountInHalalas / 100).toStringAsFixed(2)})',
      );
      debugPrint('[NearPay-API]   reference_id: $referenceId');

      final stopwatch = Stopwatch()..start();
      final response = await _httpClient
          .post(
            url,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      stopwatch.stop();

      debugPrint('[NearPay-API]   status: ${response.statusCode}');
      debugPrint(
        '[NearPay-API]   duration_ms: ${stopwatch.elapsedMilliseconds}',
      );
      debugPrint(
        '[NearPay-API]   response_body: ${response.body.length > 500 ? '${response.body.substring(0, 500)}...' : response.body}',
      );

      final responseData = _decodeJson(response);

      if (response.statusCode != 200 || responseData['success'] != true) {
        final message = responseData['message'] ?? 'فشل إنشاء جلسة الدفع';
        debugPrint('[NearPay-API]   ERROR: $message');
        throw Exception(message);
      }

      final data = responseData['data'];
      if (data is! Map<String, dynamic>) {
        debugPrint(
          '[NearPay-API]   ERROR: data is ${data.runtimeType}, not Map',
        );
        throw Exception('استجابة غير صالحة: بيانات الجلسة مفقودة');
      }
      // Backend returns session fields directly in `data`; some versions
      // nest them under `data.session` — support both shapes.
      final sessionData =
          (data['session'] is Map<String, dynamic> ? data['session'] : data)
              as Map<String, dynamic>;

      debugPrint('[NearPay-API]   session_id: ${sessionData['session_id']}');
      debugPrint('[NearPay-API]   session_status: ${sessionData['status']}');
      debugPrint('[NearPay-API]   session_type: ${sessionData['type']}');
      debugPrint('[NearPay-API]   terminal_id: ${sessionData['terminal_id']}');

      return NearPayPurchaseSession.fromJson(sessionData);
    } on TimeoutException {
      debugPrint('[NearPay-API]   TIMEOUT after ${_timeout.inSeconds}s');
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (e) {
      debugPrint('[NearPay-API]   EXCEPTION: $e');
      if (e is Exception) rethrow;
      throw Exception('خطأ في الاتصال: $e');
    }
  }

  /// Get session status
  /// GET {{base_url}}/seller/nearpay/session/{session_id}
  Future<Map<String, dynamic>> getSessionStatus({
    required String terminalId,
    required String sessionId,
  }) async {
    var url = _buildUri('/seller/nearpay/session/$sessionId');
    if (terminalId.isNotEmpty) {
      url = url.replace(
        queryParameters: {...url.queryParameters, 'terminal_id': terminalId},
      );
    }

    try {
      debugPrint('[NearPay-API] ═══ getSessionStatus ═══');
      debugPrint('[NearPay-API] GET $url');
      debugPrint('[NearPay-API]   session_id: $sessionId');
      debugPrint('[NearPay-API]   terminal_id: $terminalId');

      final stopwatch = Stopwatch()..start();
      final response = await _httpClient
          .get(
            url,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
          )
          .timeout(_timeout);
      stopwatch.stop();

      debugPrint('[NearPay-API]   status: ${response.statusCode}');
      debugPrint(
        '[NearPay-API]   duration_ms: ${stopwatch.elapsedMilliseconds}',
      );
      debugPrint(
        '[NearPay-API]   response_body: ${response.body.length > 300 ? '${response.body.substring(0, 300)}...' : response.body}',
      );

      final responseData = _decodeJson(response);

      if (response.statusCode != 200 || responseData['success'] != true) {
        final message = responseData['message'] ?? 'فشل الحصول على حالة الجلسة';
        debugPrint('[NearPay-API]   ERROR: $message');
        throw Exception(message);
      }

      final data = responseData['data'];
      if (data is! Map<String, dynamic>) {
        debugPrint(
          '[NearPay-API]   ERROR: data is ${data.runtimeType}, not Map',
        );
        throw Exception('استجابة غير صالحة: بيانات الجلسة مفقودة');
      }
      debugPrint('[NearPay-API]   session_status: ${data['status']}');
      debugPrint('[NearPay-API]   transaction_id: ${data['transaction_id']}');
      return data;
    } on TimeoutException {
      debugPrint('[NearPay-API]   TIMEOUT after ${_timeout.inSeconds}s');
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (e) {
      debugPrint('[NearPay-API]   EXCEPTION: $e');
      if (e is Exception) rethrow;
      throw Exception('خطأ في الاتصال: $e');
    }
  }

  /// Assign terminal to branch
  /// POST {{base_url}}/seller/nearpay/terminal/assign
  /// Body: {"branch_id": {{branch_id}}, "terminal_id": "{{terminal_id}}"}
  Future<Map<String, dynamic>> assignTerminalToBranch({
    required String terminalId,
  }) async {
    final url = _buildUri('/seller/nearpay/terminal/assign');

    try {
      final body = {'branch_id': branchId, 'terminal_id': terminalId};
      debugPrint('[NearPay-API] ═══ assignTerminalToBranch ═══');
      debugPrint('[NearPay-API] POST $url');
      debugPrint('[NearPay-API]   body: ${jsonEncode(body)}');

      final stopwatch = Stopwatch()..start();
      final response = await _httpClient
          .post(
            url,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      stopwatch.stop();

      debugPrint('[NearPay-API]   status: ${response.statusCode}');
      debugPrint(
        '[NearPay-API]   duration_ms: ${stopwatch.elapsedMilliseconds}',
      );
      debugPrint(
        '[NearPay-API]   response_body: ${response.body.length > 300 ? '${response.body.substring(0, 300)}...' : response.body}',
      );

      final responseData = _decodeJson(response);

      if (response.statusCode != 200 || responseData['success'] != true) {
        final message = responseData['message'] ?? 'فشل ربط التيرمينال بالفرع';
        debugPrint('[NearPay-API]   ERROR: $message');
        throw Exception(message);
      }

      final data = responseData['data'];
      if (data is! Map<String, dynamic>) {
        throw Exception('استجابة غير صالحة');
      }
      debugPrint('[NearPay-API]   assign_result: ${data.keys.toList()}');
      return data;
    } on TimeoutException {
      debugPrint('[NearPay-API]   TIMEOUT after ${_timeout.inSeconds}s');
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (e) {
      debugPrint('[NearPay-API]   EXCEPTION: $e');
      if (e is Exception) rethrow;
      throw Exception('خطأ في الاتصال: $e');
    }
  }

  /// Get terminal details
  /// GET {{base_url}}/seller/nearpay/terminals/{{terminal_id}}
  Future<NearPayTerminalDetails> getTerminalDetails({
    required String terminalId,
  }) async {
    final url = _buildUri('/seller/nearpay/terminals/$terminalId');

    try {
      final response = await _httpClient
          .get(
            url,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
          )
          .timeout(_timeout);

      final responseData = _decodeJson(response);

      if (response.statusCode != 200 || responseData['success'] != true) {
        final message =
            responseData['message'] ?? 'فشل الحصول على تفاصيل التيرمينال';
        throw Exception(message);
      }

      final data = responseData['data'];
      if (data is! Map<String, dynamic>) {
        throw Exception('استجابة غير صالحة: بيانات التيرمينال مفقودة');
      }
      return NearPayTerminalDetails.fromJson(data);
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('خطأ في الاتصال: $e');
    }
  }

  /// Check session status
  /// GET {{base_url}}/seller/nearpay/session/{{session_id}}
  Future<NearPaySessionStatus> checkSessionStatus({
    required String sessionId,
  }) async {
    final url = _buildUri('/seller/nearpay/session/$sessionId');

    try {
      final response = await _httpClient
          .get(
            url,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
          )
          .timeout(_timeout);

      final responseData = _decodeJson(response);

      if (response.statusCode != 200 || responseData['success'] != true) {
        final message = responseData['message'] ?? 'فشل الحصول على حالة الجلسة';
        throw Exception(message);
      }

      final data = responseData['data'];
      if (data is! Map<String, dynamic>) {
        throw Exception('استجابة غير صالحة: بيانات الجلسة مفقودة');
      }
      return NearPaySessionStatus.fromJson(data);
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('خطأ في الاتصال: $e');
    }
  }

  /// Reconcile transactions (End of Day Settlement)
  /// POST {{base_url}}/seller/nearpay/reconcile
  /// Body: {"branch_id": {{branch_id}}, "terminal_id": "{{terminal_id}}"}
  Future<NearPayReconcileResult> reconcile({required String terminalId}) async {
    final url = _buildUri('/seller/nearpay/reconcile');

    try {
      final response = await _httpClient
          .post(
            url,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: jsonEncode({
              'branch_id': branchId,
              'terminal_id': terminalId,
            }),
          )
          .timeout(_timeout);

      final responseData = _decodeJson(response);

      if (response.statusCode != 200 || responseData['success'] != true) {
        final message = responseData['message'] ?? 'فشل المصالحة';
        throw Exception(message);
      }

      final data = responseData['data'];
      if (data is! Map<String, dynamic>) {
        throw Exception('استجابة غير صالحة: بيانات المصالحة مفقودة');
      }
      return NearPayReconcileResult.fromJson(data);
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('خطأ في الاتصال: $e');
    }
  }

  /// Get reconcile report
  /// GET {{base_url}}/seller/nearpay/reconcile/{{reconcile_id}}
  Future<Map<String, dynamic>> getReconcileReport({
    required String reconcileId,
  }) async {
    final url = _buildUri('/seller/nearpay/reconcile/$reconcileId');

    try {
      final response = await _httpClient
          .get(
            url,
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
          )
          .timeout(_timeout);

      final responseData = _decodeJson(response);

      if (response.statusCode != 200 || responseData['success'] != true) {
        final message =
            responseData['message'] ?? 'فشل الحصول على تقرير المصالحة';
        throw Exception(message);
      }

      final data = responseData['data'];
      if (data is! Map<String, dynamic>) {
        throw Exception('استجابة غير صالحة: بيانات التقرير مفقودة');
      }
      return data;
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('خطأ في الاتصال: $e');
    }
  }
}

/// JWT Token Payload
class NearPayJwtPayload {
  final String token;
  final int? expiresAt;
  final int? expiresIn;
  final String? clientUuid;
  final String? terminalIdInToken;

  NearPayJwtPayload({
    required this.token,
    this.expiresAt,
    this.expiresIn,
    this.clientUuid,
    this.terminalIdInToken,
  });
}

/// NearPay Terminal Config (from /seller/nearpay/terminal/config)
class NearPayTerminalConfig {
  final String terminalTid;
  final String terminalId;
  final int? expiresIn;
  final String? expiresAt;

  NearPayTerminalConfig({
    required this.terminalTid,
    required this.terminalId,
    this.expiresIn,
    this.expiresAt,
  });
}

/// NearPay Terminal
class NearPayTerminal {
  final String terminalUuid;
  final String tid;
  final String? name;
  final bool isAssignedToUser;
  final String? userUuid;

  NearPayTerminal({
    required this.terminalUuid,
    required this.tid,
    this.name,
    this.isAssignedToUser = false,
    this.userUuid,
  });
}

/// NearPay Purchase Session
class NearPayPurchaseSession {
  final String sessionId;
  final String terminalId;
  final int amount; // in halalas
  final String referenceId;
  final String status;
  final String type;
  final int? expiresAt;
  final String? clientId;

  NearPayPurchaseSession({
    required this.sessionId,
    required this.terminalId,
    required this.amount,
    required this.referenceId,
    required this.status,
    required this.type,
    this.expiresAt,
    this.clientId,
  });

  factory NearPayPurchaseSession.fromJson(Map<String, dynamic> json) {
    int? toInt(dynamic value) {
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value.trim());
      return null;
    }

    String? toText(dynamic value) {
      final text = value?.toString().trim();
      if (text == null || text.isEmpty) return null;
      return text;
    }

    final nestedTerminal = json['terminal'];
    final terminalId =
        toText(json['terminal_id']) ??
        (nestedTerminal is Map ? toText(nestedTerminal['id']) : null) ??
        '';
    final sessionId = toText(json['session_id']);
    final amount = toInt(json['amount']);
    final referenceId = toText(json['reference_id']);
    final status = toText(json['status']);
    final type = toText(json['type']);

    if (sessionId == null ||
        amount == null ||
        referenceId == null ||
        status == null ||
        type == null) {
      throw FormatException('Invalid NearPay purchase session payload: $json');
    }

    return NearPayPurchaseSession(
      sessionId: sessionId,
      terminalId: terminalId,
      amount: amount,
      referenceId: referenceId,
      status: status,
      type: type,
      expiresAt: toInt(json['expired_at'] ?? json['expires_at']),
      clientId: toText(json['client_id']),
    );
  }
}

/// NearPay Terminal Details with Merchant Info
class NearPayTerminalDetails {
  final String terminalUuid;
  final String tid;
  final String? name;
  final String? nameAr;
  final bool isAssignedToUser;
  final String? userUuid;
  final String? merchantId;
  final String? merchantName;
  final String? merchantNameAr;

  NearPayTerminalDetails({
    required this.terminalUuid,
    required this.tid,
    this.name,
    this.nameAr,
    this.isAssignedToUser = false,
    this.userUuid,
    this.merchantId,
    this.merchantName,
    this.merchantNameAr,
  });

  factory NearPayTerminalDetails.fromJson(Map<String, dynamic> json) {
    final merchant = json['merchant'] as Map<String, dynamic>?;
    return NearPayTerminalDetails(
      terminalUuid: json['id'] as String,
      tid: json['tid'] as String,
      name: json['name'] as String?,
      nameAr: json['name_ar'] as String?,
      isAssignedToUser: json['is_assigned'] as bool? ?? false,
      userUuid: (json['user_uuid'] ?? json['client_uuid'] ?? json['merchant_uuid']) as String?,
      merchantId: merchant?['id'] as String?,
      merchantName: merchant?['name'] as String?,
      merchantNameAr: merchant?['name_ar'] as String?,
    );
  }
}

/// NearPay Session Status
class NearPaySessionStatus {
  final String sessionId;
  final String status; // new, processing, completed, failed, expired
  final String type; // purchase, refund, void
  final int amount;
  final String referenceId;
  final String? transactionId;
  final String? terminalId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? expiresAt;

  NearPaySessionStatus({
    required this.sessionId,
    required this.status,
    required this.type,
    required this.amount,
    required this.referenceId,
    this.transactionId,
    this.terminalId,
    this.createdAt,
    this.updatedAt,
    this.expiresAt,
  });

  factory NearPaySessionStatus.fromJson(Map<String, dynamic> json) {
    return NearPaySessionStatus(
      sessionId: json['session_id'] as String,
      status: json['status'] as String,
      type: json['type'] as String,
      amount: json['amount'] as int,
      referenceId: json['reference_id'] as String,
      transactionId: json['transaction_id'] as String?,
      terminalId: json['terminal_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
    );
  }

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isExpired => status == 'expired';
  bool get isPending => status == 'new' || status == 'processing';
}

/// NearPay Reconcile Result (End of Day Settlement)
class NearPayReconcileResult {
  final String reconcileId;
  final String branchId;
  final String terminalId;
  final int totalTransactions;
  final int totalAmount;
  final int successCount;
  final int failedCount;
  final String status; // pending, processing, completed
  final DateTime? createdAt;

  NearPayReconcileResult({
    required this.reconcileId,
    required this.branchId,
    required this.terminalId,
    required this.totalTransactions,
    required this.totalAmount,
    required this.successCount,
    required this.failedCount,
    required this.status,
    this.createdAt,
  });

  factory NearPayReconcileResult.fromJson(Map<String, dynamic> json) {
    return NearPayReconcileResult(
      reconcileId: json['reconcile_id'] as String,
      branchId: json['branch_id'] as String,
      terminalId: json['terminal_id'] as String,
      totalTransactions: json['total_transactions'] as int,
      totalAmount: json['total_amount'] as int,
      successCount: json['success_count'] as int,
      failedCount: json['failed_count'] as int,
      status: json['status'] as String,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}
