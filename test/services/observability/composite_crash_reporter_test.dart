import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/observability/crash_reporter.dart';

/// Verifies the fan-out semantics of [CompositeCrashReporter]:
///   1. every wrapped sink sees every event;
///   2. one throwing sink doesn't block the others;
///   3. event metadata (tag, message, error, stack) is preserved.
class _Recording implements CrashReporter {
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

class _Throwing implements CrashReporter {
  @override
  void report({
    required String tag,
    required String message,
    Object? error,
    StackTrace? stackTrace,
  }) {
    throw StateError('intentional sink failure');
  }
}

void main() {
  test('fans out every event to every sink', () {
    final a = _Recording();
    final b = _Recording();
    final composite = CompositeCrashReporter([a, b]);

    composite.report(tag: 'pay', message: 'declined');
    composite.report(tag: 'sync', message: 'queue grew');

    expect(a.events, hasLength(2));
    expect(b.events, hasLength(2));
    expect(a.events.first['tag'], 'pay');
    expect(b.events.last['message'], 'queue grew');
  });

  test('a throwing sink does not prevent later sinks from receiving the event',
      () {
    final ok = _Recording();
    final composite = CompositeCrashReporter([_Throwing(), ok, _Throwing()]);

    composite.report(tag: 'boot', message: 'cascade');

    expect(ok.events, hasLength(1),
        reason: 'sinks after a failing one must still get the event');
    expect(
      () => composite.report(tag: 'x', message: 'y'),
      returnsNormally,
      reason: 'CompositeCrashReporter must never throw to the caller',
    );
  });

  test('preserves tag, message, error, and stack across the fan-out', () {
    final r = _Recording();
    final composite = CompositeCrashReporter([r]);
    final err = Exception('boom');
    final st = StackTrace.fromString('#0 main');

    composite.report(
      tag: 'auth',
      message: 'session lost',
      error: err,
      stackTrace: st,
    );

    expect(r.events.single['tag'], 'auth');
    expect(r.events.single['message'], 'session lost');
    expect(r.events.single['error'], err);
    expect(r.events.single['stackTrace'], st);
  });

  test('empty sink list is a valid no-op composite', () {
    final composite = CompositeCrashReporter(const []);
    expect(() => composite.report(tag: 't', message: 'm'), returnsNormally);
  });
}
