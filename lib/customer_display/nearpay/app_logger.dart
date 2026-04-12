import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class AppLogger {
  static final Queue<_LogEntry> _queue = Queue<_LogEntry>();
  static bool _isDraining = false;
  static DateTime? _lastCleanupDay;
  static final RegExp _logFilePattern =
      RegExp(r'^nearpay_(\d{4})(\d{2})(\d{2})\\.log$');

  static void logNearPay(String message) {
    _enqueue(_LogEntry('NearPay', message, DateTime.now()));
  }

  static void _enqueue(_LogEntry entry) {
    _queue.add(entry);
    if (_isDraining) return;
    _isDraining = true;
    unawaited(_drain());
  }

  static Future<void> _drain() async {
    while (_queue.isNotEmpty) {
      final entry = _queue.removeFirst();
      await _writeEntry(entry);
    }
    _isDraining = false;
  }

  static Future<void> _writeEntry(_LogEntry entry) async {
    try {
      final baseDir = await getExternalStorageDirectory();
      if (baseDir == null) return;

      final logsDir = Directory('${baseDir.path}/logs');
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      await _cleanupOldLogs(logsDir, entry.timestamp);

      final filePath =
          '${logsDir.path}/nearpay_${_dateStamp(entry.timestamp)}.log';
      final logFile = File(filePath);
      final ts = _timeStamp(entry.timestamp);
      final line = '$ts [${entry.tag}] ${entry.message}\n';
      // flush: true ensures logs are written immediately to disk (important for error tracking)
      await logFile.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (_) {
      // Silent by design.
    }
  }

  static Future<void> _cleanupOldLogs(
    Directory logsDir,
    DateTime now,
  ) async {
    final today = DateTime(now.year, now.month, now.day);
    if (_lastCleanupDay == today) return;
    _lastCleanupDay = today;

    final cutoff = today.subtract(const Duration(days: 7));
    await for (final entity in logsDir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isNotEmpty
          ? entity.uri.pathSegments.last
          : '';
      final match = _logFilePattern.firstMatch(name);
      if (match == null) continue;
      final year = int.tryParse(match.group(1) ?? '');
      final month = int.tryParse(match.group(2) ?? '');
      final day = int.tryParse(match.group(3) ?? '');
      if (year == null || month == null || day == null) continue;
      final fileDate = DateTime(year, month, day);
      if (fileDate.isBefore(cutoff)) {
        try {
          await entity.delete();
        } catch (_) {
          // Silent by design.
        }
      }
    }
  }

  static String _dateStamp(DateTime time) {
    return '${time.year.toString().padLeft(4, '0')}'
        '${time.month.toString().padLeft(2, '0')}'
        '${time.day.toString().padLeft(2, '0')}';
  }

  static String _timeStamp(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final mo = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final mi = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    final ms = time.millisecond.toString().padLeft(3, '0');
    return '$y-$mo-$d $h:$mi:$s.$ms';
  }

}

class _LogEntry {
  final String tag;
  final String message;
  final DateTime timestamp;

  _LogEntry(this.tag, this.message, this.timestamp);
}
