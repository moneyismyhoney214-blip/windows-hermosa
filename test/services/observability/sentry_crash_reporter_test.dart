import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/observability/crash_reporter.dart';
import 'package:hermosa_pos/services/observability/sentry_crash_reporter.dart';

/// Tests for [SentryCrashReporter] — the opt-in Sentry adapter that
/// activates only when `--dart-define=SENTRY_DSN=...` is set.
///
/// Default test runs leave `SENTRY_DSN` empty so we can assert the
/// "feature off" contract: no installation, no SDK calls, no side
/// effects. The "feature on" path is exercised in CI builds where
/// the DSN is provided via the Codemagic env var.
void main() {
  group('isEnabled', () {
    test('defaults to false when no DSN is compiled in', () {
      // The dart-define key SENTRY_DSN is not provided in the test
      // runner — the value is the empty default string, so isEnabled
      // must be false. This is the contract callers rely on to skip
      // the SDK bootstrap entirely.
      expect(SentryCrashReporter.isEnabled, isFalse);
      expect(SentryCrashReporter.dsn, isEmpty);
    });

    test('environment falls back to "production" by default', () {
      expect(SentryCrashReporter.environment, 'production');
    });
  });

  group('bootstrap', () {
    test('returns null and leaves CrashReporter.instance untouched when '
        'no DSN is configured', () async {
      final original = CrashReporter.instance;
      final result = await SentryCrashReporter.bootstrap(
        existing: FileCrashReporter(),
      );

      expect(result, isNull,
          reason: 'no DSN → no Sentry → no composite swap');
      expect(CrashReporter.instance, same(original),
          reason: 'a no-op bootstrap must not change the global reporter');
    });
  });

  group('report', () {
    test('synchronous call does not throw even when SDK is dormant', () {
      // Sentry.captureException is documented to no-op when the SDK
      // hasn't been initialised. Our adapter forwards directly, so a
      // call against an empty DSN must still complete.
      expect(
        () => const SentryCrashReporter()
            .report(tag: 't', message: 'm', error: Exception('boom')),
        returnsNormally,
      );
    });
  });
}
