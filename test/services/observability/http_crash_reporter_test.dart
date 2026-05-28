@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/services/observability/crash_reporter.dart';

/// Verifies [HttpCrashReporter]:
///   1. POSTs each event as a JSON body to the configured URI;
///   2. Sanitizes secrets in the message + error before serializing;
///   3. Is fire-and-forget — never throws to the caller, even when
///      the network call fails;
///   4. Sends the optional headers from the constructor.
void main() {
  test('POSTs JSON body with the event metadata to the configured URI',
      () async {
    Uri? capturedUri;
    Map<String, String>? capturedHeaders;
    String? capturedBody;
    final completer = Completer<void>();

    final reporter = HttpCrashReporter(
      uri: Uri.parse('https://telemetry.example.com/v1/events'),
      headers: const {
        'content-type': 'application/json',
        'x-app': 'hermosa-pos',
      },
      post: (uri, headers, body) async {
        capturedUri = uri;
        capturedHeaders = headers;
        capturedBody = body;
        completer.complete();
      },
    );

    reporter.report(tag: 'auth', message: 'logout', error: Exception('boom'));
    await completer.future;

    expect(capturedUri.toString(), 'https://telemetry.example.com/v1/events');
    expect(capturedHeaders!['content-type'], 'application/json');
    expect(capturedHeaders!['x-app'], 'hermosa-pos');

    final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
    expect(body['tag'], 'auth');
    expect(body['message'], 'logout');
    expect(body['error'], contains('boom'));
    expect(body['ts'], isA<String>());
  });

  test('sanitizes message + error before serializing', () async {
    String? capturedBody;
    final done = Completer<void>();

    final reporter = HttpCrashReporter(
      uri: Uri.parse('https://example.com/x'),
      post: (uri, headers, body) async {
        capturedBody = body;
        done.complete();
      },
    );

    reporter.report(
      tag: 'auth',
      message: 'session for alice@example.com expired',
      error: Exception('token Bearer eyJabc.def.ghi rejected'),
    );
    await done.future;

    // The JWT shape is redacted, plus the email gets ***@***.
    expect(capturedBody, isNot(contains('eyJabc.def.ghi')));
    expect(capturedBody, isNot(contains('alice@example.com')));
    expect(capturedBody, contains('***JWT***'));
    expect(capturedBody, contains('***@***'));
  });

  test('a thrown post never propagates to the caller', () {
    final reporter = HttpCrashReporter(
      uri: Uri.parse('https://example.com/x'),
      post: (uri, headers, body) async {
        throw StateError('network is on fire');
      },
    );

    // The whole point of HttpCrashReporter: telemetry must never
    // crash the app reporting the crash. The call returns synchronously
    // and never observes the rejection.
    expect(
      () => reporter.report(tag: 'x', message: 'y'),
      returnsNormally,
    );
  });

  test('stack trace is included (and truncated) when provided', () async {
    String? capturedBody;
    final done = Completer<void>();

    final reporter = HttpCrashReporter(
      uri: Uri.parse('https://example.com/x'),
      post: (uri, headers, body) async {
        capturedBody = body;
        done.complete();
      },
    );

    // A pathologically long stack trace must be truncated so the
    // crash-report POST body stays bounded.
    final hugeStack = StackTrace.fromString('#0 ${'X' * 10000}');

    reporter.report(
      tag: 't',
      message: 'm',
      error: Exception('boom'),
      stackTrace: hugeStack,
    );
    await done.future;

    final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
    final stack = body['stack'] as String;
    expect(stack.length, lessThanOrEqualTo(4001),
        reason: 'stack should be truncated to ~4000 chars');
  });

  test('omits error + stack when neither is provided', () async {
    String? capturedBody;
    final done = Completer<void>();

    final reporter = HttpCrashReporter(
      uri: Uri.parse('https://example.com/x'),
      post: (uri, headers, body) async {
        capturedBody = body;
        done.complete();
      },
    );

    reporter.report(tag: 't', message: 'just a heads-up, no error');
    await done.future;

    final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
    expect(body.containsKey('error'), isFalse);
    expect(body.containsKey('stack'), isFalse);
  });
}
