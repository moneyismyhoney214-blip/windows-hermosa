import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/api/base_client.dart';
import 'package:hermosa_pos/services/api/error_handler.dart';
import 'package:http/http.dart' as http;

/// Tests for [ErrorHandler] — every API call funnels its error through
/// here to get a translated Arabic `userMessage`. A regression in the
/// status-code mapping or the backend-message normalizer leaks raw
/// English server errors into the cashier UI, which historically has
/// produced support tickets within hours.
void main() {
  group('fromHttpResponse', () {
    test('401 → "session expired" Arabic message', () {
      final ex = ErrorHandler.fromHttpResponse(
        http.Response('{"message":"unauthenticated"}', 401),
        requestUrl: '/seller/profile',
      );
      expect(ex.statusCode, 401);
      expect(ex.userMessage, contains('انتهت الجلسة'));
    });

    test('404 → "item not found" Arabic message', () {
      final ex = ErrorHandler.fromHttpResponse(
        http.Response('', 404),
        requestUrl: '/seller/x',
      );
      expect(ex.userMessage, contains('غير موجود'));
    });

    test('429 → "too many requests" Arabic message', () {
      final ex = ErrorHandler.fromHttpResponse(
        http.Response('', 429),
        requestUrl: '/seller/x',
      );
      expect(ex.userMessage, contains('كثيرة'));
    });

    test('500 with backend message prefers a normalized translation', () {
      final ex = ErrorHandler.fromHttpResponse(
        http.Response(
          '{"message":"sended to kitchen in the past"}',
          500,
        ),
      );
      expect(ex.userMessage, contains('تم إرسال الطلب إلى المطبخ مسبقًا'));
    });

    test('backend message extraction also reads errors[]', () {
      final ex = ErrorHandler.fromHttpResponse(
        http.Response(
          '{"errors":["first complaint","second"]}',
          422,
        ),
      );
      // The message field is missing — first item in errors[] is used.
      expect(ex.message, 'first complaint');
    });

    test('backend message extraction reads errors{} field-keyed', () {
      final ex = ErrorHandler.fromHttpResponse(
        http.Response(
          '{"errors":{"email":["the email is invalid"]}}',
          422,
        ),
      );
      expect(ex.message, contains('the email is invalid'));
    });

    test('non-JSON body falls back to truncated body as message', () {
      final ex = ErrorHandler.fromHttpResponse(
        http.Response('upstream gateway exploded', 502),
      );
      expect(ex.message, 'upstream gateway exploded');
    });
  });

  group('fromException', () {
    test('TimeoutException → Arabic "timed out" message', () {
      final ex = ErrorHandler.fromException(
        TimeoutException('timeout'),
        requestUrl: '/x',
      );
      expect(ex.userMessage, contains('انتهت مهلة'));
    });

    test('SocketException to hermosaapp host → Hermosa-specific message',
        () {
      final ex = ErrorHandler.fromException(
        const SocketException('refused'),
        requestUrl: 'https://portal.hermosaapp.com/seller/profile',
      );
      expect(ex.userMessage, contains('Hermosa'));
    });

    test('SocketException to other host → generic network message', () {
      final ex = ErrorHandler.fromException(
        const SocketException('no route'),
        requestUrl: 'https://other.example.com/x',
      );
      expect(ex.userMessage, contains('الإنترنت'));
    });

    test('FormatException → "could not read server data" message', () {
      final ex = ErrorHandler.fromException(
        const FormatException('bad json'),
      );
      expect(ex.userMessage, contains('قراءة'));
    });

    test('unknown error type → generic "unexpected error" fallback', () {
      final ex = ErrorHandler.fromException(StateError('weird'));
      expect(ex.userMessage, contains('غير متوقع'));
    });
  });

  group('toUserMessage', () {
    test('prefers the ApiException.userMessage when present', () {
      final ex = ApiException('raw', userMessage: 'arabic-friendly');
      expect(ErrorHandler.toUserMessage(ex), 'arabic-friendly');
    });

    test('falls back to normalizing the message when no userMessage', () {
      final ex = ApiException('UNAUTHENTICATED');
      expect(ErrorHandler.toUserMessage(ex), contains('انتهت الجلسة'));
    });

    test('strips "Exception:" / "ApiException:" prefixes', () {
      expect(
        ErrorHandler.toUserMessage(Exception('boom'), fallback: 'fb'),
        'boom',
      );
    });

    test('empty input → fallback', () {
      expect(ErrorHandler.toUserMessage('', fallback: 'fb'), 'fb');
    });
  });

  group('normalizeBackendMessage', () {
    test('unauthenticated synonym maps to session-expired Arabic', () {
      expect(
        ErrorHandler.normalizeBackendMessage('UNAUTHENTICATED'),
        contains('انتهت الجلسة'),
      );
    });

    test('paymethod-missing maps to fallback-to-cash Arabic', () {
      expect(
        ErrorHandler.normalizeBackendMessage('No paymethod configured'),
        contains('طرق الدفع'),
      );
    });

    test('arabic input passes through unchanged when no rule matches', () {
      const msg = 'رسالة مخصصة من الخادم';
      expect(ErrorHandler.normalizeBackendMessage(msg), msg);
    });

    test('null/empty falls back to status-code defaults', () {
      expect(
        ErrorHandler.normalizeBackendMessage(null, statusCode: 403),
        contains('صلاحية'),
      );
      expect(
        ErrorHandler.normalizeBackendMessage('', statusCode: 500),
        contains('مؤقتة'),
      );
    });
  });

  group('websocketErrorMessage', () {
    test('TimeoutException → display-timeout message', () {
      expect(
        ErrorHandler.websocketErrorMessage(TimeoutException('x')),
        contains('انتهت مهلة'),
      );
    });

    test('SocketException → display-unreachable message', () {
      expect(
        ErrorHandler.websocketErrorMessage(const SocketException('x')),
        contains('شاشة العرض'),
      );
    });

    test('other error → generic display-error message', () {
      expect(
        ErrorHandler.websocketErrorMessage('unknown'),
        contains('شاشة العرض'),
      );
    });
  });

  group('jsonParsingFailure', () {
    test('returns ApiException with Arabic user-facing message', () {
      final ex = ErrorHandler.jsonParsingFailure(
        requestUrl: '/x',
        rawBody: 'this is not json',
      );
      expect(ex.userMessage, contains('غير مفهومة'));
      expect(ex.responseBody, 'this is not json');
    });
  });
}
