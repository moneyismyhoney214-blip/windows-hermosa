import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/logger_service.dart';
import 'package:hermosa_pos/services/observability/crash_reporter.dart';

/// The CrashReporter adapter is what we'll swap in for Sentry/Crashlytics
/// at boot. These tests cover the contract the rest of the codebase
/// depends on:
///   1. [wireUp] installs a [Log.onError] hook that delegates to the
///      currently registered [CrashReporter.instance].
///   2. A failing reporter never propagates — Log.e must remain safe.
///   3. Replacing the instance after [wireUp] is honoured.
class _RecordingReporter implements CrashReporter {
  final List<Map<String, Object?>> events = [];
  @override
  void report({
    required String tag,
    required String message,
    Object? error,
    StackTrace? stackTrace,
  }) {
    events.add({
      'tag': tag,
      'message': message,
      'error': error,
      'stackTrace': stackTrace,
    });
  }
}

class _ThrowingReporter implements CrashReporter {
  @override
  void report({
    required String tag,
    required String message,
    Object? error,
    StackTrace? stackTrace,
  }) {
    throw StateError('reporter blew up');
  }
}

void main() {
  setUp(() {
    Log.onError = null;
  });

  test('wireUp routes Log.e through the registered reporter', () {
    final r = _RecordingReporter();
    CrashReporter.instance = r;
    CrashReporter.wireUp();

    Log.e('payment', 'tender failed', error: Exception('boom'));

    expect(r.events, hasLength(1));
    expect(r.events.single['tag'], 'payment');
    expect(r.events.single['message'], 'tender failed');
    expect(r.events.single['error'], isA<Exception>());
  });

  test('replacing instance after wireUp is honoured', () {
    final a = _RecordingReporter();
    final b = _RecordingReporter();
    CrashReporter.instance = a;
    CrashReporter.wireUp();
    CrashReporter.instance = b;

    Log.e('sync', 'queue drain failed');

    expect(a.events, isEmpty,
        reason: 'after swap, the old reporter must not be called');
    expect(b.events, hasLength(1));
  });

  test('reporter exceptions are swallowed — Log.e never throws', () {
    CrashReporter.instance = _ThrowingReporter();
    CrashReporter.wireUp();

    expect(
      () => Log.e('boot', 'cascade failure', error: Exception('x')),
      returnsNormally,
    );
  });
}
