import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart' as esc;
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart' as fbp;
import 'package:image/image.dart' as img;
import 'package:hermosa_pos/utils/paper_width_utils.dart';
import '../models.dart';
import '../models/receipt_data.dart';
import 'network_print_helper.dart';

class PrintRequest {
  final DeviceConfig device;
  final OrderReceiptData? receiptData;
  final Map<String, dynamic>? kitchenData;
  final Uint8List? imageBytes;
  final bool isTest;
  final bool isCreditNote;
  final bool isRtl;
  final String? primaryLang;
  final String? secondaryLang;
  final bool? allowSecondary;
  final String id;

  /// Completer that signals when this print job is fully done
  /// (image captured + bytes sent to printer). This allows the
  /// orchestrator to wait for each job before starting the next one.
  final Completer<void> _completer = Completer<void>();

  /// Unique key for the RepaintBoundary so multiple requests can render concurrently
  final GlobalKey repaintKey = GlobalKey();

  /// Tracks if the snapshot capture has started to prevent multiple triggers
  bool isCaptureStarted = false;

  PrintRequest({
    required this.device,
    this.receiptData,
    this.kitchenData,
    this.imageBytes,
    this.isTest = false,
    this.isCreditNote = false,
    this.isRtl = true,
    this.primaryLang,
    this.secondaryLang,
    this.allowSecondary,
  }) : id = DateTime.now().microsecondsSinceEpoch.toString();

  /// Future that completes when the print job finishes.
  Future<void> get done => _completer.future;

  /// Call when the print job completes successfully.
  void complete() {
    if (!_completer.isCompleted) _completer.complete();
  }

  /// Call when the print job fails.
  void completeError(Object error) {
    if (!_completer.isCompleted) {
      _completer.complete(); // Complete normally — errors are logged, not thrown
    }
  }
}

class PrinterService {
  /// Notifier to trigger UI-based printing for MULTIPLE concurrent jobs
  final ValueNotifier<List<PrintRequest>> activeRequestsNotifier = ValueNotifier([]);

  void _addPrintRequest(PrintRequest request) {
    activeRequestsNotifier.value = List.of(activeRequestsNotifier.value)..add(request);
  }

  void removePrintRequest(PrintRequest request) {
    activeRequestsNotifier.value = activeRequestsNotifier.value
        .where((r) => r.id != request.id)
        .toList();
  }

  esc.PaperSize _paperSizeFor(DeviceConfig device) {
    return escPosPaperSizeForWidth(device.paperWidthMm);
  }

  bool _isBluetoothPrinter(DeviceConfig device) {
    return device.connectionType == PrinterConnectionType.bluetooth;
  }

  bool _isDisplayDevice(DeviceConfig device) {
    final type = device.type.trim().toLowerCase();
    return type == 'kds' ||
        type == 'kitchen_screen' ||
        type == 'order_viewer' ||
        type == 'cds' ||
        type == 'customer_display' ||
        device.id.startsWith('kitchen:');
  }

  void _assertPrinterDevice(DeviceConfig device) {
    if (_isDisplayDevice(device)) {
      throw Exception(
        'هذا الجهاز شاشة عرض (CDS/KDS) وليس طابعة. يرجى استخدام جهاز طابعة فقط.',
      );
    }
  }

  Future<esc.CapabilityProfile> _getProfile(String model) async {
    return await esc.CapabilityProfile.load();
  }

  Future<PosPrintResult> _connectWithRetry(
    NetworkPrinter printer,
    String ip,
    int port,
  ) async {
    PosPrintResult res = await printer.connect(
      ip,
      port: port,
      timeout: const Duration(seconds: 5),
    );
    if (res == PosPrintResult.success) return res;
    await Future.delayed(const Duration(milliseconds: 200));
    res = await printer.connect(
      ip,
      port: port,
      timeout: const Duration(seconds: 5),
    );
    return res;
  }

  Future<bool> testConnection(DeviceConfig device) async {
    _assertPrinterDevice(device);

    if (_isBluetoothPrinter(device)) {
      final mac = device.bluetoothAddress?.trim() ?? '';
      if (mac.isEmpty) throw Exception('عنوان البلوتوث غير محدد');

      // For Bluetooth, we just check if it's reachable via the new package
      // or simply return true since the package handles connection lazily.
      return true;
    }

    if (device.ip.isEmpty) return false;

    final port = int.tryParse(device.port) ?? 9100;
    final paper = _paperSizeFor(device);
    final profile = await _getProfile(device.model);
    final printer = NetworkPrinter(paper, profile);

    try {
      final PosPrintResult res = await _connectWithRetry(printer, device.ip, port);
      if (res == PosPrintResult.success) {
        printer.disconnect();
        return true;
      }
      return false;
    } catch (e) {
      developer.log('PrinterService Connection Error: $e');
      return false;
    }
  }

  /// Triggers a print job.
  /// For Bluetooth: Notifies the UI to use flutter_bluetooth_printer's Receipt widget.
  /// For Network: Handled via the same flow where UI captures image and passes it back (or service captures it).
  Future<void> printReceipt(
    DeviceConfig device,
    OrderReceiptData data, {
    String jobType = 'receipt',
    bool isTest = false,
    bool isCreditNote = false,
    bool isRtl = true,
    String? primaryLang,
    String? secondaryLang,
    bool? allowSecondary,
  }) async {
    _assertPrinterDevice(device);
    final request = PrintRequest(
      device: device,
      receiptData: data,
      isTest: isTest,
      isCreditNote: isCreditNote,
      isRtl: isRtl,
      primaryLang: primaryLang,
      secondaryLang: secondaryLang,
      allowSecondary: allowSecondary,
    );
    _addPrintRequest(request);
    await request.done;
  }

  Future<void> printTicket(
    DeviceConfig device, {
    bool isTest = false,
    String? jobType,
    bool isRtl = true,
  }) async {
    _assertPrinterDevice(device);
    final request = PrintRequest(
      device: device,
      isTest: isTest,
      isRtl: isRtl,
    );
    _addPrintRequest(request);
    await request.done;
  }

  Future<void> printKitchenReceipt(
    DeviceConfig device, {
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
    String? primaryLang,
    String? secondaryLang,
    bool? allowSecondary,
  }) async {
    _assertPrinterDevice(device);
    final request = PrintRequest(
      device: device,
      kitchenData: {
        'orderNumber': orderNumber,
        'orderType': orderType,
        'items': items,
        'note': note,
        'invoiceNumber': invoiceNumber,
        'templateMeta': templateMeta,
        'createdAt': createdAt,
        'clientName': clientName,
        'clientPhone': clientPhone,
        'tableNumber': tableNumber,
        'carNumber': carNumber,
        'cashierName': cashierName,
        'printerName': printerName,
        if (primaryLang != null) 'primaryLang': primaryLang,
        if (secondaryLang != null) 'secondaryLang': secondaryLang,
        if (allowSecondary != null) 'allowSecondary': allowSecondary,
      },
      isRtl: isRtl,
    );
    _addPrintRequest(request);
    await request.done;
  }

  /// Triggers a print job for a raw image.
  /// Used for pre-rendered receipts like ZATCA PDFs.
  Future<void> printRawImage(
    DeviceConfig device,
    Uint8List imageBytes,
  ) async {
    _assertPrinterDevice(device);
    final request = PrintRequest(
      device: device,
      imageBytes: imageBytes,
    );
    _addPrintRequest(request);
    await request.done;
  }

  /// Step 2: Once the UI captures the widget as an image, it calls this to complete the print
  Future<void> finalizePrintJob(PrintRequest request, Uint8List imageBytes) async {
    final device = request.device;

    if (_isBluetoothPrinter(device)) {
      // Encode the PNG through the same ESC/POS pipeline network printing uses,
      // then stream the bytes over the Bluetooth transport. Previously this
      // method returned early, so raw-image BT jobs (e.g. the closing report)
      // silently did nothing on Bluetooth printers.
      final address = device.bluetoothAddress?.trim() ?? '';
      if (address.isEmpty) {
        throw Exception('عنوان البلوتوث غير محدد للطابعة ${device.name}');
      }
      final escBytes = await NetworkPrintHelper.encodeImageToEscPos(
        imageBytes: imageBytes,
        paperWidthMm: device.paperWidthMm,
        addFeeds: 4,
      );
      try {
        await fbp.FlutterBluetoothPrinter.printBytes(
          address: address,
          data: escBytes,
          keepConnected: false,
        );
      } catch (e) {
        debugPrint('❌ BT raw-image print failed [${device.name}]: $e');
        rethrow;
      }
      return;
    }

    // Network Printer Logic: Send image bytes
    final img.Image? originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) throw Exception('فشل معالجة صورة الفاتورة');

    final normalizedPaperWidthMm = normalizePaperWidthMm(device.paperWidthMm);
    final profile = await _getProfile(device.model);
    final paper = escPosPaperSizeForWidth(normalizedPaperWidthMm);
    final printer = NetworkPrinter(paper, profile);

    final port = int.tryParse(device.port) ?? 9100;
    final PosPrintResult res = await _connectWithRetry(printer, device.ip, port);

    if (res != PosPrintResult.success) {
      throw Exception('تعذر الاتصال بالطابعة: ${res.msg}');
    }

    try {
      final thermalImage = _prepareThermalImage(
        originalImage,
        paperWidthMm: normalizedPaperWidthMm,
      );
      printer.image(thermalImage);
      printer.feed(2);
      printer.cut();
    } finally {
      printer.disconnect();
    }
  }

  img.Image _prepareThermalImage(
    img.Image source, {
    required int paperWidthMm,
  }) {
    final normalizedPaperWidthMm = normalizePaperWidthMm(paperWidthMm);
    final targetWidth = thermalRasterWidthForPaper(normalizedPaperWidthMm);
    final resized = img.copyResize(
      source,
      width: targetWidth,
      interpolation: img.Interpolation.average,
    );
    final grayscale = img.grayscale(resized);
    final enhanced = img.adjustColor(
      grayscale,
      contrast: 3.0,
      brightness: 0.95,
      gamma: 0.5,
    );

    return _binarizeForThermal(
      enhanced,
      threshold: thermalThresholdForPaper(normalizedPaperWidthMm),
    );
  }

  img.Image _binarizeForThermal(
    img.Image source, {
    required int threshold,
  }) {
    final output = source.clone();
    for (var y = 0; y < output.height; y++) {
      for (var x = 0; x < output.width; x++) {
        final pixel = output.getPixel(x, y);
        final luminance =
            (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114).round();
        final value = luminance < threshold ? 0 : 255;
        output.setPixelRgb(x, y, value, value, value);
      }
    }
    return output;
  }
}
