@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/observability/crash_reporter.dart';
import 'package:path/path.dart' as p;

/// Tests for [FileCrashReporter] — the default reporter that persists
/// crash events to disk so they survive a process crash and can be
/// retrieved later (via ADB or a debug screen).
///
/// We inject a temp directory via the reporter's testing constructor so
/// no platform plugin (path_provider) is needed.
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('crash_reporter_test_');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  FileCrashReporter newReporter({int maxBytes = 1024 * 1024}) {
    return FileCrashReporter(
      maxBytes: maxBytes,
      directoryFn: () async => tmp,
    );
  }

  Future<List<String>> readLog() async {
    final file = File(p.join(tmp.path, 'crash_reports', 'crashes.log'));
    if (!file.existsSync()) return const [];
    return await file.readAsLines();
  }

  Future<void> drain(FileCrashReporter r) async {
    // Internal write chain is single-flight; await it via a sentinel report.
    r.report(tag: 'drain', message: 'sentinel');
    // The chain is private — wait long enough for the OS to flush.
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final lines = await readLog();
      if (lines.any((l) => l.contains('sentinel'))) return;
    }
  }

  test('writes one JSON-line event per report', () async {
    final r = newReporter();
    r.report(tag: 'payment', message: 'card declined');
    await drain(r);

    final lines = await readLog();
    // Two lines: the payment event + the drain sentinel.
    expect(lines, hasLength(2));
    final payment = jsonDecode(lines.first) as Map<String, dynamic>;
    expect(payment['tag'], 'payment');
    expect(payment['message'], 'card declined');
    expect(payment['ts'], isA<String>(),
        reason: 'ts is an ISO8601 UTC string');
  });

  test('sanitizes the message before persisting', () async {
    final r = newReporter();
    // Log.sanitize redacts JWTs and bearer tokens — the file must
    // never carry the raw value to disk.
    r.report(
        tag: 'auth',
        message: 'login replied Bearer eyJabc.def.ghi for user@example.com');
    await drain(r);

    final lines = await readLog();
    final first = lines.first;
    expect(first, isNot(contains('eyJabc.def.ghi')));
    expect(first, isNot(contains('user@example.com')));
    expect(first, contains('Bearer ***'));
    expect(first, contains('***@***'));
  });

  test('includes error + stack when provided', () async {
    final r = newReporter();
    final st = StackTrace.fromString('#0 main');
    r.report(
      tag: 'boot',
      message: 'init failed',
      error: Exception('boom'),
      stackTrace: st,
    );
    await drain(r);

    final lines = await readLog();
    final payload = jsonDecode(lines.first) as Map<String, dynamic>;
    expect(payload['error'], contains('boom'));
    expect(payload['stack'], contains('main'));
  });

  test('rotates when the log exceeds maxBytes', () async {
    // Pick a tiny maxBytes so a couple of writes trigger the rollover.
    final r = newReporter(maxBytes: 200);
    for (var i = 0; i < 20; i++) {
      r.report(tag: 'rot', message: 'long message $i body padding to roll');
    }
    // Allow chained writes + rotation to flush.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    final crashDir = Directory(p.join(tmp.path, 'crash_reports'));
    final entries = crashDir.listSync().map((e) => p.basename(e.path)).toSet();
    expect(entries, contains('crashes.log'));
    expect(entries, contains('crashes.log.1'),
        reason: 'rotation must produce a .1 backup');
  });

  test('reporter never crashes the caller when directoryFn throws', () async {
    final r = FileCrashReporter(
      directoryFn: () async => throw const FileSystemException('no disk'),
    );
    expect(
      () => r.report(tag: 't', message: 'm'),
      returnsNormally,
      reason: 'a crash reporter that crashes is worse than no reporter',
    );
  });

  test('FileCrashReporter.recent returns parsed events newest-first',
      () async {
    final r = newReporter();
    CrashReporter.instance = r;
    r.report(tag: 'a', message: 'first');
    r.report(tag: 'b', message: 'second');
    r.report(tag: 'c', message: 'third');
    await drain(r);

    final recent = await FileCrashReporter.recent(max: 10);
    expect(recent, isNotEmpty);
    // drain() adds a sentinel event ('drain' tag) AFTER the three test
    // events. So the newest-first order is: drain, c, b, a.
    expect(recent.first['tag'], 'drain');
    expect(recent[1]['tag'], 'c');
    expect(recent[2]['tag'], 'b');
    expect(recent[3]['tag'], 'a');
  });
}
