import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:path_provider/path_provider.dart';

import '../logger_service.dart';

/// Thin adapter sitting between [Log.onError] and a real crash backend.
///
/// **Default**: [FileCrashReporter] persists JSON-line crash events to
/// `<app-documents>/crash_reports/crashes.log` with size-based rotation
/// (1MB → rolled to `crashes.log.1`, kept for one cycle). That gives us
/// a real, queryable crash trail in production immediately, without
/// committing to Sentry / Crashlytics / Datadog as the backend.
///
/// **To swap in Sentry later** (no call-site changes required):
/// ```dart
/// CrashReporter.instance = SentryCrashReporter();
/// CrashReporter.wireUp();
/// ```
/// where `SentryCrashReporter implements CrashReporter` and forwards
/// to `Sentry.captureException`.
abstract class CrashReporter {
  /// Active reporter. Defaults to [FileCrashReporter] so crashes are
  /// persisted on first boot without explicit configuration. Tests can
  /// swap in a fake before `wireUp`.
  ///
  /// To fan out to MULTIPLE sinks (e.g. local file AND Sentry), wrap
  /// them in [CompositeCrashReporter] before assigning:
  /// ```dart
  /// CrashReporter.instance = CompositeCrashReporter([
  ///   FileCrashReporter(),
  ///   SentryCrashReporter(),  // implement against sentry_flutter
  /// ]);
  /// CrashReporter.wireUp();
  /// ```
  static CrashReporter instance = FileCrashReporter();

  /// Installs [instance] as the [Log.onError] sink. Idempotent —
  /// calling twice replaces the previous hook.
  static void wireUp() {
    Log.onError = (tag, message, error, stackTrace) {
      try {
        instance.report(
          tag: tag,
          message: message,
          error: error,
          stackTrace: stackTrace,
        );
      } catch (_) {
        // Crash reporter must never crash the app.
      }
    };
  }

  /// Forward an error event. Implementations should be non-blocking —
  /// reporting failures must not propagate.
  void report({
    required String tag,
    required String message,
    Object? error,
    StackTrace? stackTrace,
  });
}

/// Append-only JSON-line crash log on the device. Each crash is one
/// line so the file can be tailed and parsed without a deserializer.
///
/// Failure modes are intentionally silent — if path_provider isn't
/// available (e.g. in a unit test that hasn't initialised the binding)
/// or the disk is full, the report is dropped rather than escalated.
/// Crash reporters that crash are worse than no reporter at all.
class FileCrashReporter implements CrashReporter {
  FileCrashReporter({
    int maxBytes = 1 * 1024 * 1024,
    Future<Directory> Function()? directoryFn,
  })  : _maxBytes = maxBytes,
        _directoryFn = directoryFn ?? getApplicationDocumentsDirectory;

  final int _maxBytes;
  final Future<Directory> Function() _directoryFn;
  File? _resolvedFile;

  // Single-flight lock so concurrent Log.e calls don't interleave JSON lines.
  Future<void> _writeChain = Future<void>.value();

  Future<File> _file() async {
    final cached = _resolvedFile;
    if (cached != null) return cached;
    final docs = await _directoryFn();
    final dir = Directory('${docs.path}/crash_reports');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}/crashes.log');
    if (!file.existsSync()) {
      file.createSync();
    }
    _resolvedFile = file;
    return file;
  }

  @override
  void report({
    required String tag,
    required String message,
    Object? error,
    StackTrace? stackTrace,
  }) {
    // Serialize up-front and chain disk writes so concurrent reports can't tear JSON.
    final line = _encode(
      tag: tag,
      message: message,
      error: error,
      stackTrace: stackTrace,
    );
    _writeChain = _writeChain.then((_) => _write(line)).catchError((_) {
      // Double-catch keeps the chain alive even if the previous link rejected.
    });

    if (kDebugMode) {
      // ignore: avoid_print
      print('[crash] $line');
    }
  }

  Future<void> _write(String line) async {
    try {
      final file = await _file();
      await file.writeAsString(
        '$line\n',
        mode: FileMode.append,
        flush: false,
      );
      final stat = await file.stat();
      if (stat.size > _maxBytes) {
        await _rotate(file);
      }
    } catch (_) {
      // Silently drop — see class docstring.
    }
  }

  Future<void> _rotate(File current) async {
    try {
      final rolled = File('${current.path}.1');
      if (rolled.existsSync()) {
        await rolled.delete();
      }
      await current.rename(rolled.path);
      _resolvedFile = null; // force re-open on next write
    } catch (_) {
      // Let the file keep growing — losing a crash report is worse than failing a rotation.
    }
  }

  /// Read the last N crash events for diagnostics screens. Returns
  /// most-recent first. Cheap enough to call from a debug UI; never
  /// throws.
  static Future<List<Map<String, Object?>>> recent({int max = 50}) async {
    try {
      final reporter = CrashReporter.instance;
      if (reporter is! FileCrashReporter) return const [];
      final file = await reporter._file();
      if (!file.existsSync()) return const [];
      final lines = await file.readAsLines();
      final tail = lines.length > max ? lines.sublist(lines.length - max) : lines;
      final parsed = <Map<String, Object?>>[];
      for (final line in tail) {
        if (line.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map<String, dynamic>) {
            parsed.add(decoded);
          }
        } catch (_) {
        }
      }
      return parsed.reversed.toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static String _encode({
    required String tag,
    required String message,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final payload = <String, Object?>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'tag': tag,
      'message': Log.sanitize(message),
      if (error != null) 'error': Log.sanitize(error.toString()),
      if (stackTrace != null) 'stack': _truncate(stackTrace.toString(), 4000),
    };
    return jsonEncode(payload);
  }

  static String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}\n…[truncated ${s.length - max} chars]';
  }
}

/// Fan-out reporter — forwards each event to every wrapped reporter.
/// One failing reporter doesn't block the others (each is invoked
/// inside a try/catch).
///
/// Typical use: keep [FileCrashReporter] as the always-on local log,
/// and add a remote reporter (Sentry, Crashlytics, custom HTTP sink)
/// when one becomes available.
class CompositeCrashReporter implements CrashReporter {
  CompositeCrashReporter(this._sinks);

  final List<CrashReporter> _sinks;

  @override
  void report({
    required String tag,
    required String message,
    Object? error,
    StackTrace? stackTrace,
  }) {
    for (final sink in _sinks) {
      try {
        sink.report(
          tag: tag,
          message: message,
          error: error,
          stackTrace: stackTrace,
        );
      } catch (_) {
        // A misbehaving sink must not block the others.
      }
    }
  }
}

/// HTTP-uploader reporter — POSTs each event as a JSON body to a
/// configurable endpoint. Provided as a starting point for teams that
/// want crash telemetry but haven't picked a vendor SDK yet.
///
/// Failures are silent by design (the network may be down at the
/// exact moment we want to report a crash).
///
/// Usage:
/// ```dart
/// CrashReporter.instance = CompositeCrashReporter([
///   FileCrashReporter(),
///   HttpCrashReporter(uri: Uri.parse('https://telemetry.example.com/v1/events')),
/// ]);
/// ```
class HttpCrashReporter implements CrashReporter {
  HttpCrashReporter({
    required this.uri,
    this.headers = const {'content-type': 'application/json'},
    Future<void> Function(Uri uri, Map<String, String> headers, String body)?
        post,
  }) : _post = post ?? _defaultPost;

  final Uri uri;
  final Map<String, String> headers;
  final Future<void> Function(Uri, Map<String, String>, String) _post;

  @override
  void report({
    required String tag,
    required String message,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final body = jsonEncode({
      'ts': DateTime.now().toUtc().toIso8601String(),
      'tag': tag,
      'message': Log.sanitize(message),
      if (error != null) 'error': Log.sanitize(error.toString()),
      if (stackTrace != null)
        'stack': stackTrace.toString().substring(
              0,
              stackTrace.toString().length.clamp(0, 4000),
            ),
    });
    // Fire-and-forget; never await, never throw.
    () async {
      try {
        await _post(uri, headers, body);
      } catch (_) {/* see class docstring */}
    }();
  }

  static Future<void> _defaultPost(
      Uri uri, Map<String, String> headers, String body) async {
    // Fresh HttpClient so telemetry never starves user-facing requests.
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(uri);
      headers.forEach(request.headers.add);
      request.add(utf8.encode(body));
      final response = await request.close();
      await response.drain();
    } finally {
      client.close(force: true);
    }
  }
}
