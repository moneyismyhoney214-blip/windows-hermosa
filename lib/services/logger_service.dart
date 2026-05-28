import 'package:flutter/foundation.dart';

/// Centralized logger. Replaces raw `print()` across the codebase so we can:
///   1. Strip noisy debug logs from release builds at compile-time,
///   2. Sanitize sensitive payloads (tokens, login responses, cards) before
///      they hit logcat/syslog,
///   3. Route fatal errors to a single sink that future Sentry/Crashlytics
///      integration can subscribe to without touching call-sites.
///
/// Usage:
/// ```dart
/// Log.d('auth', 'restoring session');
/// Log.w('sync', 'queue grew past 500 — running cleanup');
/// Log.e('payment', 'tender failed', error: e, stackTrace: st);
/// ```
///
/// In release mode `Log.d`/`Log.i` are no-ops. `Log.w`/`Log.e` always run
/// because operational issues must reach the crash sink. None of the
/// methods ever return values containing sensitive data; callers may pass
/// secrets to [sanitize] explicitly.
class Log {
  Log._();

  /// Hook invoked for every error-level event. Defaults to console output
  /// in debug, no-op in release. Replace with a Crashlytics/Sentry callback
  /// at app boot:
  /// ```dart
  /// Log.onError = (tag, msg, err, st) => Sentry.captureException(err, stackTrace: st);
  /// ```
  static void Function(String tag, String message, Object? error,
      StackTrace? stackTrace)? onError;

  /// Debug-only chatter. Stripped from release builds entirely.
  static void d(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[$tag] $message');
    }
  }

  /// Informational. Stripped from release builds.
  static void i(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[$tag] ℹ $message');
    }
  }

  /// Warning — kept in release builds so operational signals survive,
  /// but routed through [debugPrint] which the engine drops if the host
  /// hasn't configured a print handler.
  static void w(String tag, String message, {Object? error}) {
    final suffix = error == null ? '' : ' :: $error';
    debugPrint('[$tag] ⚠ $message$suffix');
  }

  /// Error — always reported. Forwarded to [onError] if registered.
  static void e(
    String tag,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final cb = onError;
    if (cb != null) {
      cb(tag, message, error, stackTrace);
    }
    // Always echo to debugPrint so live dev sessions still see the message;
    // debugPrint is rate-limited and safe in release.
    final suffix = error == null ? '' : ' :: $error';
    debugPrint('[$tag] ✖ $message$suffix');
    if (stackTrace != null && kDebugMode) {
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// Best-effort sanitizer for strings that may contain bearer tokens, JWTs,
  /// card numbers, or e-mail addresses. Replaces with `***` so logs are safe
  /// to ship. Conservative — false-positive bias on purpose.
  ///
  /// This is a defense-in-depth helper; the primary rule remains "don't log
  /// secrets in the first place".
  static String sanitize(String input) {
    if (input.isEmpty) return input;
    var s = input;
    // JWTs: three base64url segments separated by dots.
    s = s.replaceAll(
        RegExp(r'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+'),
        '***JWT***');
    // `Authorization: Bearer <token>` and similar header forms. Dart
    // RegExp doesn't support inline `(?i)` so we pass
    // `caseSensitive: false` instead. The optional `bearer` group
    // inside the value lets us swallow the literal "Bearer " prefix
    // so the trailing token isn't left exposed.
    s = s.replaceAllMapped(
      RegExp(
        r'(authorization|token)\s*[:=]\s*(?:bearer\s+)?[A-Za-z0-9_\-\.]+',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}=***',
    );
    // Standalone "Bearer <token>" (no header key in front).
    s = s.replaceAll(
        RegExp(r'bearer\s+[A-Za-z0-9_\-\.]+', caseSensitive: false),
        'Bearer ***');
    // PANs: 13–19 digits (PCI-DSS scope).
    s = s.replaceAll(RegExp(r'\b\d{13,19}\b'), '****');
    // E-mail addresses.
    s = s.replaceAll(
        RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}'),
        '***@***');
    return s;
  }
}
