import 'dart:async';

import '../models.dart';
import 'printer_role_registry.dart';
import 'printer_service.dart';

enum PrintJobPriority {
  low,
  normal,
  high,
  critical,
}

class PrintQueueSnapshot {
  final int queuedJobs;
  final int dueJobs;
  final int delayedJobs;
  final bool isProcessing;
  final DateTime updatedAt;

  const PrintQueueSnapshot({
    required this.queuedJobs,
    required this.dueJobs,
    required this.delayedJobs,
    required this.isProcessing,
    required this.updatedAt,
  });
}

class PrintDispatchResult {
  final bool success;
  final String? userMessage;
  final List<String> errors;
  final List<String> deliveredPrinterNames;

  const PrintDispatchResult({
    required this.success,
    this.userMessage,
    this.errors = const <String>[],
    this.deliveredPrinterNames = const <String>[],
  });
}

class _QueuedKitchenJob {
  final List<DeviceConfig> printers;
  final String orderNumber;
  final String orderType;
  final List<Map<String, dynamic>> items;
  final String? note;
  final String? invoiceNumber;
  final Map<String, dynamic>? templateMeta;
  final DateTime createdAt;
  final PrintJobPriority priority;
  final Completer<PrintDispatchResult> completer;
  final String? clientName;
  final String? clientPhone;
  final String? tableNumber;
  final String? carNumber;
  final String? cashierName;
  final String? printerName;
  final bool isRtl;

  int attempt;
  DateTime nextAttemptAt;

  _QueuedKitchenJob({
    required this.printers,
    required this.orderNumber,
    required this.orderType,
    required this.items,
    required this.note,
    required this.invoiceNumber,
    required this.templateMeta,
    required this.createdAt,
    required this.priority,
    required this.completer,
    this.clientName,
    this.clientPhone,
    this.tableNumber,
    this.carNumber,
    this.cashierName,
    this.printerName,
    this.isRtl = true,
    DateTime? nextAttemptAt,
  })  : attempt = 0,
        nextAttemptAt = nextAttemptAt ?? DateTime.now();
}

/// Enterprise print orchestrator:
/// - Priority queue
/// - Offline buffering + retry with backoff
/// - Multi-printer failover
/// - Live status snapshot for UI/monitoring
class PrintOrchestratorService {
  static const int _maxJobAttempts = 4;
  static const int _maxPrinterRetriesPerCopy = 3;
  static const Duration _workerTick = Duration(seconds: 2);

  final PrinterService _printerService;
  final PrinterRoleRegistry _roleRegistry;

  final List<_QueuedKitchenJob> _queue = <_QueuedKitchenJob>[];
  final Map<String, bool> _printerOnlineStatus = <String, bool>{};
  final StreamController<Map<String, bool>> _statusController =
      StreamController<Map<String, bool>>.broadcast();
  final StreamController<PrintQueueSnapshot> _queueController =
      StreamController<PrintQueueSnapshot>.broadcast();

  Timer? _worker;
  bool _isProcessing = false;

  PrintOrchestratorService(this._printerService, this._roleRegistry) {
    _worker = Timer.periodic(_workerTick, (_) {
      unawaited(_drainQueue());
    });
    _publishQueueSnapshot();
  }

  Stream<Map<String, bool>> get printerStatusStream => _statusController.stream;
  Stream<PrintQueueSnapshot> get queueSnapshotStream => _queueController.stream;

  PrintQueueSnapshot get currentQueueSnapshot {
    final now = DateTime.now();
    final dueJobs =
        _queue.where((job) => !job.nextAttemptAt.isAfter(now)).length;
    return PrintQueueSnapshot(
      queuedJobs: _queue.length,
      dueJobs: dueJobs,
      delayedJobs: _queue.length - dueJobs,
      isProcessing: _isProcessing,
      updatedAt: now,
    );
  }

  bool isPrinterOnline(String printerId) {
    return _printerOnlineStatus[printerId] ?? false;
  }

  void updatePrinterStatus(String printerId, bool isOnline) {
    final id = printerId.trim();
    if (id.isEmpty) return;
    _printerOnlineStatus[id] = isOnline;
    _publishStatus();
  }

  Future<PrintDispatchResult> enqueueKitchenPrint({
    required List<DeviceConfig> printers,
    required String orderNumber,
    required String orderType,
    required List<Map<String, dynamic>> items,
    String? note,
    String? invoiceNumber,
    Map<String, dynamic>? templateMeta,
    PrintJobPriority priority = PrintJobPriority.critical,
    String? clientName,
    String? clientPhone,
    String? tableNumber,
    String? carNumber,
    String? cashierName,
    String? printerName,
    bool isRtl = true,
  }) {
    if (printers.isEmpty) {
      return Future.value(const PrintDispatchResult(success: false, userMessage: 'No printers assigned'));
    }

    final completer = Completer<PrintDispatchResult>();
    final job = _QueuedKitchenJob(
      printers: printers,
      orderNumber: orderNumber,
      orderType: orderType,
      items: items,
      note: note,
      invoiceNumber: invoiceNumber,
      templateMeta: templateMeta,
      createdAt: DateTime.now(),
      priority: priority,
      completer: completer,
      clientName: clientName,
      clientPhone: clientPhone,
      tableNumber: tableNumber,
      carNumber: carNumber,
      cashierName: cashierName,
      printerName: printerName,
      isRtl: isRtl,
    );
    _queue.add(job);
    _queue.sort((a, b) => b.priority.index.compareTo(a.priority.index));
    unawaited(_drainQueue());
    return completer.future;
  }

  Future<void> _drainQueue() async {
    if (_isProcessing) return;
    if (_queue.isEmpty) {
      _publishQueueSnapshot();
      return;
    }

    _isProcessing = true;
    _publishQueueSnapshot();
    try {
      _sortQueue();
      final now = DateTime.now();
      final due = _queue
          .where((job) => !job.nextAttemptAt.isAfter(now))
          .toList(growable: false);
      await Future.wait(due.map((job) async {
        _queue.remove(job);
        final result = await _executeKitchenJob(job);
        if (result.success) {
          if (!job.completer.isCompleted) {
            job.completer.complete(result);
          }
          return;
        }

        job.attempt += 1;
        if (job.attempt >= _maxJobAttempts) {
          if (!job.completer.isCompleted) {
            job.completer.complete(result);
          }
          return;
        }

        final backoffSeconds = (1 << job.attempt).clamp(2, 30);
        job.nextAttemptAt = DateTime.now().add(
          Duration(seconds: backoffSeconds),
        );
        _queue.add(job);
        _publishQueueSnapshot();
      }));
    } finally {
      _isProcessing = false;
      _publishQueueSnapshot();
    }
  }

  Future<PrintDispatchResult> _executeKitchenJob(_QueuedKitchenJob job) async {
    final candidates = _resolveKitchenPrinters(job.printers);
    if (candidates.isEmpty) {
      return const PrintDispatchResult(
        success: false,
        userMessage:
            'لا توجد طابعة مطبخ مهيأة. عيّن دور الطابعة (Kitchen/KDS/Bar) من الإعدادات.',
      );
    }

    final delivered = <String>[];
    final errors = <String>[];

    // Execute each printer job CONCURRENTLY to prevent bottlenecks
    await Future.wait(candidates.map((printer) async {
      final copies = printer.copies <= 0 ? 1 : printer.copies;
      var printerSucceeded = false;

      for (var copy = 0; copy < copies; copy++) {
        final success = await _printWithRetry(
          printer: printer,
          orderNumber: job.orderNumber,
          orderType: job.orderType,
          items: job.items,
          note: job.note,
          invoiceNumber: job.invoiceNumber,
          templateMeta: job.templateMeta,
          createdAt: job.createdAt,
          clientName: job.clientName,
          clientPhone: job.clientPhone,
          tableNumber: job.tableNumber,
          carNumber: job.carNumber,
          cashierName: job.cashierName,
          printerName: job.printerName,
          isRtl: job.isRtl,
        );

        if (!success) {
          errors.add(
            'Printer ${printer.name} failed (copy ${copy + 1}/$copies)',
          );
          continue;
        }

        printerSucceeded = true;
      }

      _printerOnlineStatus[printer.id] = printerSucceeded;
      if (printerSucceeded) {
        delivered.add(printer.name);
      }
    }));

    _publishStatus();

    if (delivered.isEmpty) {
      return PrintDispatchResult(
        success: false,
        userMessage:
            'الطابعات غير متاحة حالياً. النظام سيحاول تلقائياً إعادة إرسال الطباعة.',
        errors: errors,
      );
    }

    if (errors.isNotEmpty) {
      return PrintDispatchResult(
        success: true,
        userMessage:
            'تمت الطباعة على ${delivered.join(', ')} مع بعض الإخفاقات الجزئية.',
        errors: errors,
        deliveredPrinterNames: delivered,
      );
    }

    return PrintDispatchResult(
      success: true,
      deliveredPrinterNames: delivered,
    );
  }

  Future<bool> _printWithRetry({
    required DeviceConfig printer,
    required String orderNumber,
    required String orderType,
    required List<Map<String, dynamic>> items,
    String? note,
    String? invoiceNumber,
    Map<String, dynamic>? templateMeta,
    DateTime? createdAt,
    String? clientName,
    String? clientPhone,
    String? tableNumber,
    String? carNumber,
    String? cashierName,
    String? printerName,
    bool isRtl = true,
  }) async {
    for (var attempt = 1; attempt <= _maxPrinterRetriesPerCopy; attempt++) {
      try {
        await _printerService.printKitchenReceipt(
          printer,
          orderNumber: orderNumber,
          orderType: orderType,
          items: items,
          note: note,
          invoiceNumber: invoiceNumber,
          templateMeta: templateMeta,
          createdAt: createdAt,
          clientName: clientName,
          clientPhone: clientPhone,
          tableNumber: tableNumber,
          carNumber: carNumber,
          cashierName: cashierName,
          printerName: printerName,
          isRtl: isRtl,
        );
        return true;
      } catch (e) {
        final isLast = attempt == _maxPrinterRetriesPerCopy;
        if (isLast) {
          // silenced: printer unavailable
          return false;
        }
        final delayMs = 300 * (1 << (attempt - 1));
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    return false;
  }

  List<DeviceConfig> _resolveKitchenPrinters(List<DeviceConfig> printers) {
    final physical =
        printers.where(_isUsablePrinter).toList(growable: false);
    if (physical.isEmpty) return const <DeviceConfig>[];

    final withRole = physical
        .map((printer) =>
            (printer: printer, role: _roleRegistry.resolveRole(printer)))
        .toList(growable: false);

    int roleRank(PrinterRole role) {
      switch (role) {
        case PrinterRole.kds:
          return 0;
        case PrinterRole.kitchen:
          return 1;
        case PrinterRole.bar:
          return 2;
        case PrinterRole.general:
          return 3;
        case PrinterRole.cashierReceipt:
          return 4;
      }
    }

    withRole.sort((a, b) {
      final rankDiff = roleRank(a.role).compareTo(roleRank(b.role));
      if (rankDiff != 0) return rankDiff;
      return a.printer.name
          .toLowerCase()
          .compareTo(b.printer.name.toLowerCase());
    });

    final designated = withRole
        .where((entry) =>
            entry.role == PrinterRole.kds ||
            entry.role == PrinterRole.kitchen ||
            entry.role == PrinterRole.bar)
        .map((entry) => entry.printer)
        .toList(growable: false);

    // ONLY return kitchen/kds/bar printers — never general or cashier
    if (designated.isEmpty) {
      return const <DeviceConfig>[];
    }
    return designated;
  }

  bool _isPhysicalPrinter(DeviceConfig device) {
    final normalized = device.type.trim().toLowerCase();
    if (device.id.startsWith('kitchen:')) return false;
    return normalized == 'printer';
  }

  bool _isUsablePrinter(DeviceConfig device) {
    if (!_isPhysicalPrinter(device)) return false;
    if (device.connectionType == PrinterConnectionType.bluetooth) {
      return device.bluetoothAddress?.trim().isNotEmpty == true;
    }
    return device.ip.trim().isNotEmpty;
  }

  void _sortQueue() {
    _queue.sort((a, b) {
      final priorityDiff = b.priority.index.compareTo(a.priority.index);
      if (priorityDiff != 0) return priorityDiff;
      return a.nextAttemptAt.compareTo(b.nextAttemptAt);
    });
  }

  void _publishStatus() {
    if (_statusController.isClosed) return;
    _statusController.add(Map<String, bool>.from(_printerOnlineStatus));
  }

  void _publishQueueSnapshot() {
    if (_queueController.isClosed) return;
    _queueController.add(currentQueueSnapshot);
  }

  void dispose() {
    _worker?.cancel();
    _worker = null;
    _statusController.close();
    _queueController.close();
  }
}
