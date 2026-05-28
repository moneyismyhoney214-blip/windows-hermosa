import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'crash_reporter.dart';

/// [CrashReporter] adapter that forwards events to Sentry.
///
/// **Activation**: the adapter is only installed when the binary is
/// built with `--dart-define=SENTRY_DSN=https://...@sentry.io/...`.
/// Without a DSN, [bootstrap] is a no-op and [FileCrashReporter]
/// remains the sole sink. This means adding `sentry_flutter` to
/// `pubspec.yaml` does not change default-build behaviour at all —
/// you flip the feature on at release time by passing the DSN.
///
/// **Wiring** — call [bootstrap] from `main.dart` before
/// `runApp(...)`. It does the SDK init, swaps the global reporter
/// instance to a [CompositeCrashReporter] of file + Sentry, and
/// re-runs [CrashReporter.wireUp] so the new instance is the active
/// sink for `Log.e`.
///
/// **Sanitization** — Sentry receives the original [Object?] error and
/// stack trace (so its grouping heuristics work); the message has
/// already been routed through `Log.sanitize` by [CrashReporter] /
/// [FileCrashReporter] callers.
class SentryCrashReporter implements CrashReporter {
  const SentryCrashReporter();

  /// DSN injected at build time. Empty string means "feature off".
  static const String _dsn = String.fromEnvironment('SENTRY_DSN');

  /// Optional release tag — set via `--dart-define=SENTRY_RELEASE=...`
  /// so each TestFlight / Play upload is tagged with its build number.
  /// Codemagic populates this from `$PROJECT_BUILD_NUMBER`.
  static const String _release = String.fromEnvironment('SENTRY_RELEASE');

  /// Optional environment tag (`production` / `staging` / `dev`).
  static const String _environment = String.fromEnvironment(
    'SENTRY_ENVIRONMENT',
    defaultValue: 'production',
  );

  /// True when a non-empty DSN was compiled in. Lets `main.dart` skip
  /// the bootstrap path entirely on builds where Sentry is intended to
  /// stay dormant.
  static bool get isEnabled => _dsn.isNotEmpty;

  /// Initialize Sentry and install this adapter as the active reporter
  /// (fanning out alongside [FileCrashReporter]). Returns the
  /// composite reporter on success; returns null and leaves the
  /// existing reporter untouched when the DSN is empty.
  ///
  /// Idempotent — calling twice rewires the composite but doesn't
  /// re-init the SDK (Sentry.init guards against that).
  ///
  /// Callers typically wrap their `runApp` in [SentryFlutter.init]'s
  /// `appRunner` so Sentry's zone catches every uncaught exception:
  /// ```dart
  /// final composite = await SentryCrashReporter.bootstrap(
  ///   existing: FileCrashReporter(),
  /// );
  /// if (composite != null) {
  ///   await SentryFlutter.init((o) => o
  ///     ..dsn = SentryCrashReporter.dsn
  ///     ..release = SentryCrashReporter.release
  ///     ..environment = SentryCrashReporter.environment,
  ///     appRunner: () => runApp(const HermosaPosApp(isAuthenticated: false)),
  ///   );
  /// } else {
  ///   runApp(const HermosaPosApp(isAuthenticated: false));
  /// }
  /// ```
  static Future<CrashReporter?> bootstrap({
    required CrashReporter existing,
  }) async {
    if (!isEnabled) return null;

    // Sentry init is the caller's responsibility (it controls
    // `appRunner` for zone-based capture). Here we just install the
    // adapter so synchronous Log.e calls reach Sentry too.
    final composite = CompositeCrashReporter([
      existing,
      const SentryCrashReporter(),
    ]);
    CrashReporter.instance = composite;
    CrashReporter.wireUp();
    if (kDebugMode) {
      // ignore: avoid_print
      print('[sentry] SentryCrashReporter installed (DSN provided)');
    }
    return composite;
  }

  /// Expose the compile-time DSN so `main.dart` can pass it into
  /// `SentryFlutter.init` without re-reading the env var.
  static String get dsn => _dsn;
  static String get release => _release;
  static String get environment => _environment;

  @override
  void report({
    required String tag,
    required String message,
    Object? error,
    StackTrace? stackTrace,
  }) {
    // Fire-and-forget — Sentry's SDK queues internally so capture
    // doesn't block the caller. Wrap in unawaited() so a future
    // failure doesn't bubble out of the synchronous Log.e callsite.
    // If the SDK isn't initialised (DSN empty), captureException is
    // a documented no-op.
    Sentry.captureException(
      error ?? Exception(message),
      stackTrace: stackTrace,
      withScope: (scope) {
        scope.setTag('tag', tag);
        scope.setContexts('hermosa', {'message': message});
      },
    );
  }
}
