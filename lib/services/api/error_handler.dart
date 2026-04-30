import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'base_client.dart';

class ErrorHandler {
  static ApiException fromHttpResponse(
    http.Response response, {
    String? requestUrl,
    String? operation,
  }) {
    final status = response.statusCode;
    final backendMessage = _extractBackendMessage(response.body);
    final userMessage = _mapStatusToArabic(status, backendMessage);

    _logError(
      tag: 'HTTP_ERROR',
      operation: operation,
      requestUrl: requestUrl,
      statusCode: status,
      responseBody: response.body,
      backendMessage: backendMessage,
      userMessage: userMessage,
    );

    return ApiException(
      backendMessage ?? 'HTTP error',
      statusCode: status,
      userMessage: userMessage,
      responseBody: response.body,
      requestUrl: requestUrl,
    );
  }

  static ApiException fromException(
    Object error, {
    String? requestUrl,
    String? operation,
  }) {
    String userMessage;
    if (error is TimeoutException) {
      userMessage = 'انتهت مهلة الاتصال بالخادم. حاول مرة أخرى.';
    } else if (error is SocketException) {
      final url = requestUrl?.toLowerCase() ?? '';
      if (url.contains('portal.hermosaapp.com')) {
        userMessage =
            'تعذر الوصول إلى خادم Hermosa. تحقق من الشبكة/الجدار الناري أو جرّب شبكة أخرى.';
      } else {
        userMessage = 'تعذر الاتصال بالإنترنت أو بالخادم. تحقق من الشبكة.';
      }
    } else if (error is FormatException) {
      userMessage = 'تعذر قراءة بيانات الخادم. حاول لاحقًا.';
    } else {
      userMessage = 'حدث خطأ غير متوقع. حاول مرة أخرى.';
    }

    _logError(
      tag: 'TRANSPORT_ERROR',
      operation: operation,
      requestUrl: requestUrl,
      backendMessage: error.toString(),
      userMessage: userMessage,
    );

    return ApiException(
      error.toString(),
      userMessage: userMessage,
      requestUrl: requestUrl,
    );
  }

  static ApiException jsonParsingFailure({
    required String requestUrl,
    required String rawBody,
  }) {
    const userMessage = 'تم استلام استجابة غير مفهومة من الخادم.';
    _logError(
      tag: 'JSON_PARSE_ERROR',
      requestUrl: requestUrl,
      responseBody: rawBody,
      userMessage: userMessage,
    );
    return ApiException(
      'Invalid JSON response',
      userMessage: userMessage,
      responseBody: rawBody,
      requestUrl: requestUrl,
    );
  }

  static String toUserMessage(Object error, {String fallback = 'حدث خطأ.'}) {
    if (error is ApiException) {
      final direct = (error.userMessage ?? '').trim();
      if (direct.isNotEmpty) return direct;
      final normalized = normalizeBackendMessage(
        error.message,
        statusCode: error.statusCode,
        defaultMessage: fallback,
      );
      return normalized.trim().isNotEmpty ? normalized : fallback;
    }
    final raw = error.toString().trim();
    if (raw.isEmpty) return fallback;

    final cleaned = raw
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^Error:\s*'), '')
        .replaceFirst(RegExp(r'^ApiException:\s*'), '')
        .trim();

    if (cleaned.isEmpty) return fallback;

    final normalized = normalizeBackendMessage(
      cleaned,
      defaultMessage: fallback,
    );
    return normalized.trim().isNotEmpty ? normalized : fallback;
  }

  static String websocketErrorMessage(Object error) {
    if (error is TimeoutException) {
      return 'انتهت مهلة الاتصال بشاشة العرض.';
    }
    if (error is SocketException) {
      return 'تعذر الوصول إلى شاشة العرض. تحقق من الشبكة وعنوان الجهاز.';
    }
    return 'حدث خطأ في الاتصال بشاشة العرض.';
  }

  static String normalizeBackendMessage(
    String? backendMessage, {
    int? statusCode,
    String? defaultMessage,
  }) {
    final msg = (backendMessage ?? '').trim();
    if (msg.isEmpty) {
      return defaultMessage ?? _mapStatusToArabic(statusCode, null);
    }
    final lower = msg.toLowerCase();
    if (lower.contains('route_not_found')) {
      return 'الخدمة المطلوبة غير متاحة حاليًا.';
    }
    if (lower.contains('unauthenticated')) {
      return 'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.';
    }
    if (lower.contains('sended to kitchen in the past')) {
      return 'تم إرسال الطلب إلى المطبخ مسبقًا.';
    }
    if (lower.contains('طرق الدفع') &&
        lower.contains('غير') &&
        lower.contains('معد')) {
      return 'طرق الدفع غير مُعدّة — تم استخدام الدفع النقدي تلقائيًا';
    }
    if (lower.contains('paymethod') || lower.contains('pay method')) {
      return 'طرق الدفع غير مُعدّة — تم استخدام الدفع النقدي تلقائيًا';
    }
    if (lower.contains('booking_items') &&
        (lower.contains('does not exist') || lower.contains("doesn't exist"))) {
      return 'تعذر جلب تفاصيل الطلب الآن بسبب مشكلة مؤقتة في الخادم، وتم متابعة العمل بالبيانات المتاحة.';
    }
    if (lower.contains('branch_id') && lower.contains('null')) {
      return 'تعذر تجهيز إيصال المطبخ حاليًا، وتم حفظ الطلب بنجاح.';
    }
    if (lower.contains('undefined array key') && lower.contains('client')) {
      return 'تعذر توليد PDF من الخادم لهذه الفاتورة بسبب نقص بيانات العميل. يمكنك فتح تفاصيل الفاتورة.';
    }
    if (lower.contains('unhandled match case null')) {
      return 'الخادم أعاد قيمة فارغة غير مدعومة أثناء إنشاء الطلب. تم تطبيق قيم افتراضية آمنة ويمكنك إعادة المحاولة.';
    }
    if (lower.contains('trying to access array offset on value of type null')) {
      return 'الخدمة من الخادم غير مستقرة حالياً. حاول مرة أخرى بعد قليل.';
    }
    if ((lower.contains('booking') || lower.contains('order')) &&
        lower.contains('required')) {
      if (lower.contains('booking_id')) {
        return 'الحقل رقم الحجز (booking_id) مطلوب للدفع.';
      }
      if (lower.contains('order_id')) {
        return 'الحقل رقم الطلب (order_id) مطلوب للدفع.';
      }
      return 'الحقل رقم الطلب مطلوب.';
    }
    return msg;
  }

  static String _mapStatusToArabic(int? statusCode, String? backendMessage) {
    final normalized = normalizeBackendMessage(
      backendMessage,
      statusCode: statusCode,
      defaultMessage: '',
    );
    if (normalized.isNotEmpty && normalized != backendMessage) {
      return normalized;
    }
    switch (statusCode) {
      case 400:
        return 'البيانات المرسلة غير صحيحة.';
      case 401:
        return 'انتهت الجلسة. يرجى تسجيل الدخول مرة أخرى.';
      case 403:
        return 'ليس لديك صلاحية لتنفيذ هذا الإجراء.';
      case 404:
        return 'العنصر المطلوب غير موجود.';
      case 422:
        return normalized.isNotEmpty
            ? normalized
            : 'تعذر التحقق من بعض البيانات، وتم تطبيق أفضل بديل متاح تلقائيًا.';
      case 429:
        return 'الطلبات كثيرة جدًا. يرجى الانتظار ثم المحاولة مجددًا.';
      case 500:
        return normalized.isNotEmpty
            ? normalized
            : 'الخادم يواجه مشكلة مؤقتة. يمكنك إعادة المحاولة.';
      default:
        return normalized.isNotEmpty
            ? normalized
            : 'تعذر إكمال الطلب حاليًا. حاول مرة أخرى.';
    }
  }

  static String? _extractBackendMessage(String body) {
    if (body.isEmpty) return null;
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) {
        final message = parsed['message']?.toString();
        if (message != null && message.trim().isNotEmpty) {
          return message.trim();
        }
        final errors = parsed['errors'];
        if (errors is List && errors.isNotEmpty) {
          return errors.first.toString();
        }
        if (errors is Map && errors.isNotEmpty) {
          final first = errors.values.first;
          if (first is List && first.isNotEmpty) {
            return first.first.toString();
          }
          return first.toString();
        }
      }
    } catch (_) {
      // Not JSON
    }
    return body.length > 300 ? body.substring(0, 300) : body;
  }

  static void _logError({
    required String tag,
    String? operation,
    String? requestUrl,
    int? statusCode,
    String? backendMessage,
    String? responseBody,
    String? userMessage,
  }) {
    // تجاهل أخطاء kitchen receipts 404 (No meals found)
    final normalizedUrl = requestUrl?.toLowerCase() ?? '';
    final normalizedBackend = backendMessage?.toLowerCase() ?? '';
    
    if (normalizedUrl.contains('kitchen-receipts/generate-by-booking') &&
        statusCode == 404 &&
        normalizedBackend.contains('no meals found')) {
      // هذا خطأ متوقع - لا نطبعه
      return;
    }
    
    // Keep complete technical details in logs for production diagnostics.
    // Hook Sentry/Crashlytics here if available.
    // ignore: avoid_print
    print(
      '[$tag] op=${operation ?? '-'} url=${requestUrl ?? '-'} '
      'status=${statusCode ?? '-'} backend="${backendMessage ?? '-'}" '
      'user="$userMessage"',
    );
    
    final shouldSuppressVerboseBody =
        normalizedUrl.contains('/bookings/create') &&
            normalizedBackend.contains('unhandled match case null');

    if (shouldSuppressVerboseBody) {
      // ignore: avoid_print
      print('[$tag] response=<suppressed known backend trace noise>');
      return;
    }

    if (responseBody != null && responseBody.isNotEmpty) {
      final compactBody = responseBody.trim();
      const maxLen = 1200;
      final printable = compactBody.length > maxLen
          ? '${compactBody.substring(0, maxLen)}...<truncated>'
          : compactBody;
      // ignore: avoid_print
      print('[$tag] response=$printable');
    }
  }
}
