import 'package:flutter/foundation.dart';

class PrintAuditEntry {
  final String printerIp;
  final String jobType;
  final DateTime timestamp;
  final bool success;
  final String? error;

  const PrintAuditEntry({
    required this.printerIp,
    required this.jobType,
    required this.timestamp,
    required this.success,
    this.error,
  });
}

class PrintAuditService {
  final List<PrintAuditEntry> _entries = <PrintAuditEntry>[];

  void logAttempt({
    required String printerIp,
    required String jobType,
    required bool success,
    String? error,
  }) {
    final entry = PrintAuditEntry(
      printerIp: printerIp,
      jobType: jobType,
      timestamp: DateTime.now(),
      success: success,
      error: error,
    );
    _entries.add(entry);
    debugPrint(
      '🖨️ Print [$jobType] ${entry.printerIp} @ ${entry.timestamp.toIso8601String()} '
      '=> ${entry.success ? "SUCCESS" : "FAIL"}${entry.error != null ? " | ${entry.error}" : ""}',
    );
  }

  List<PrintAuditEntry> get entries =>
      List<PrintAuditEntry>.unmodifiable(_entries);
}

final PrintAuditService printAuditService = PrintAuditService();
