import 'dart:async';

import 'package:flutter/foundation.dart';

class AppErrorHandler {
  static void log({
    required String page,
    required String action,
    required Object error,
    StackTrace? stackTrace,
  }) {
    debugPrint('[ERROR][$page][$action] $error');
    if (stackTrace != null) {
      debugPrint(stackTrace.toString());
    }
  }

  static Future<T?> guardAsync<T>({
    required String page,
    required String action,
    required Future<T> Function() run,
    FutureOr<void> Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    try {
      return await run();
    } catch (error, stackTrace) {
      log(page: page, action: action, error: error, stackTrace: stackTrace);
      await onError?.call(error, stackTrace);
      return null;
    }
  }

  static T? guardSync<T>({
    required String page,
    required String action,
    required T Function() run,
    FutureOr<void> Function(Object error, StackTrace stackTrace)? onError,
  }) {
    try {
      return run();
    } catch (error, stackTrace) {
      log(page: page, action: action, error: error, stackTrace: stackTrace);
      onError?.call(error, stackTrace);
      return null;
    }
  }
}
