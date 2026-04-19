import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart' as fbp;
import '../models.dart';
import '../services/network_print_helper.dart';
import '../services/printer_language_settings_service.dart';
import '../services/printer_service.dart';
import '../widgets/invoice_print_widget.dart';
import '../locator.dart';

/// Listens for print requests and dispatches them to either the Bluetooth or
/// the network transport.
///
/// Both transports share the **same** pipeline:
///
///   1. Render [InvoicePrintWidget] offscreen inside a [RepaintBoundary].
///   2. After a short settle delay (for QR / network images), capture the
///      boundary as a PNG sized to the printer's thermal dot width.
///   3. Encode the PNG as ESC/POS raster via [NetworkPrintHelper].
///   4. Send the bytes — TCP socket for network printers, Bluetooth for BT.
///
/// Bluetooth previously went through the `fbp.Receipt` widget which has its
/// own rendering quirks (visible grey wrapper, different fonts, its own
/// internal RepaintBoundary, no timeout). That path is gone: BT now produces
/// byte-for-byte identical output to network printing.
class PrintListener extends StatefulWidget {
  final Widget child;

  const PrintListener({super.key, required this.child});

  @override
  State<PrintListener> createState() => _PrintListenerState();
}

class _PrintListenerState extends State<PrintListener> {
  final PrinterService _printerService = getIt<PrinterService>();

  static const Duration _settleDelay = Duration(milliseconds: 800);
  static const Duration _btTimeout = Duration(seconds: 15);

  static bool _isBluetoothDevice(DeviceConfig device) {
    return device.type == 'bluetooth' ||
        (device.bluetoothAddress?.isNotEmpty ?? false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<List<PrintRequest>>(
          valueListenable: _printerService.activeRequestsNotifier,
          builder: (context, requests, _) {
            if (requests.isEmpty) return const SizedBox.shrink();
            // Each active print request gets its own overlay so several
            // jobs can render and capture independently at the same time.
            return Stack(
              children: requests
                  .map((request) => _buildPrintOverlay(request))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPrintOverlay(PrintRequest request) {
    final device = request.device;
    final isBluetooth = _isBluetoothDevice(device);

    // Pre-rendered raw-image prints (daily closing report, PDF exports).
    // The PNG is already sized by the caller; skip the widget-render step
    // and dispatch the bytes straight to the correct transport.
    if (request.imageBytes != null) {
      if (!request.isCaptureStarted) {
        request.isCaptureStarted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          try {
            await _sendPngToPrinter(
              device: device,
              pngBytes: request.imageBytes!,
              isBluetooth: isBluetooth,
            );
            debugPrint('✅ Raw-image print completed: ${device.name}');
            request.complete();
          } catch (e) {
            debugPrint('❌ Raw-image print failed [${device.name}]: $e');
            request.completeError(e);
          } finally {
            _printerService.removePrintRequest(request);
          }
        });
      }
      return const SizedBox.shrink();
    }

    // Regular rendered receipt — BT and WiFi both use the same offscreen
    // RepaintBoundary. The boundary is positioned far off-screen so Flutter
    // lays it out and paints it without it ever being visible to the user.
    final int dotsWidth = (device.paperWidthMm >= 80) ? 576 : 360;

    return KeyedSubtree(
      key: ValueKey(request.id),
      child: Transform.translate(
        offset: const Offset(-5000, -5000),
        child: OverflowBox(
          alignment: Alignment.topLeft,
          maxHeight: double.infinity,
          child: RepaintBoundary(
            key: request.repaintKey,
            child: Container(
              color: Colors.white,
              child: SizedBox(
                width: dotsWidth.toDouble(),
                child: _buildReceiptContent(request, isBluetooth: isBluetooth),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReceiptContent(
    PrintRequest request, {
    required bool isBluetooth,
  }) {
    final paperWidth = request.device.paperWidthMm;

    if (!request.isCaptureStarted) {
      request.isCaptureStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          // Give QR widgets / network images time to decode before we
          // screenshot. Shorter waits produced receipts with a missing QR.
          await Future.delayed(_settleDelay);
          await Future.delayed(Duration.zero);

          final boundary = request.repaintKey.currentContext
              ?.findRenderObject() as RenderRepaintBoundary?;
          if (boundary == null) {
            throw StateError('RepaintBoundary not found');
          }

          final screenWidth = boundary.size.width;
          final int dotsWidth = (paperWidth >= 80) ? 576 : 360;
          final double pixelRatio = dotsWidth / screenWidth;

          final ui.Image image =
              await boundary.toImage(pixelRatio: pixelRatio);
          final byteData =
              await image.toByteData(format: ui.ImageByteFormat.png);
          if (byteData == null) {
            throw StateError('toByteData returned null');
          }
          final pngBytes = byteData.buffer.asUint8List();
          debugPrint(
              '📸 Captured ${pngBytes.length}B @ ${image.width}×${image.height} for ${request.device.name}');

          await _sendPngToPrinter(
            device: request.device,
            pngBytes: pngBytes,
            isBluetooth: isBluetooth,
          );

          debugPrint('✅ Print completed: ${request.device.name}');
          request.complete();
        } catch (e) {
          debugPrint('❌ Print Error [${request.device.name}]: $e');
          request.completeError(e);
        } finally {
          _printerService.removePrintRequest(request);
        }
      });
    }

    final lang = _resolveInvoiceLang(request);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InvoicePrintWidget(
          data: request.receiptData,
          kitchenData: request.kitchenData,
          isTest: request.isTest,
          isCreditNote: request.isCreditNote,
          isRtl: request.isRtl,
          paperWidthMm: paperWidth,
          primaryLang: lang.primary,
          secondaryLang: lang.secondary,
          allowSecondary: lang.allowSecondary,
        ),
        // Extra padding so the mechanical cutter leaves a clean margin.
        SizedBox(height: request.isTest ? 100 : 60),
      ],
    );
  }

  /// Resolve the invoice language trio for a print request.
  /// Priority: explicit request fields → kitchenData map → device-scoped
  /// printer language settings (the source the user configures in the UI).
  _InvoiceLang _resolveInvoiceLang(PrintRequest request) {
    String? primary = request.primaryLang;
    String? secondary = request.secondaryLang;
    bool? allow = request.allowSecondary;

    // Kitchen receipts stuff language into kitchenData map — honor it.
    final kd = request.kitchenData;
    if (kd != null) {
      primary ??= kd['primaryLang']?.toString();
      secondary ??= kd['secondaryLang']?.toString();
      final rawAllow = kd['allowSecondary'];
      if (allow == null && rawAllow is bool) allow = rawAllow;
    }

    primary = _normalizeLang(primary) ?? printerLanguageSettings.primary;
    secondary = _normalizeLang(secondary) ?? printerLanguageSettings.secondary;
    allow ??= printerLanguageSettings.allowSecondary;

    return _InvoiceLang(
      primary: primary,
      secondary: secondary,
      allowSecondary: allow,
    );
  }

  static String? _normalizeLang(String? raw) {
    if (raw == null) return null;
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    switch (s) {
      case 'ar':
      case 'en':
      case 'hi':
      case 'ur':
      case 'tr':
      case 'es':
        return s;
      default:
        return null;
    }
  }

  /// Unified transport: encodes [pngBytes] as ESC/POS raster and sends it
  /// over the correct wire — Bluetooth MAC or TCP socket. The encoded
  /// payload already contains init/feed/cut commands, so the caller never
  /// needs to send a separate cut command.
  Future<void> _sendPngToPrinter({
    required DeviceConfig device,
    required Uint8List pngBytes,
    required bool isBluetooth,
  }) async {
    if (isBluetooth) {
      final address = device.bluetoothAddress?.trim() ?? '';
      if (address.isEmpty) {
        throw StateError(
            'No bluetooth address configured for printer ${device.name}');
      }
      final escBytes = await NetworkPrintHelper.encodeImageToEscPos(
        imageBytes: pngBytes,
        paperWidthMm: device.paperWidthMm,
        addFeeds: 4,
      );
      await fbp.FlutterBluetoothPrinter.printBytes(
        address: address,
        data: escBytes,
        keepConnected: false,
      ).timeout(
        _btTimeout,
        onTimeout: () => throw TimeoutException(
            'BT print timed out', _btTimeout),
      );
      debugPrint(
          '📡 BT print sent: ${escBytes.length} bytes to $address (${device.name})');
    } else {
      if (device.ip.trim().isEmpty) {
        throw StateError('No IP configured for printer ${device.name}');
      }
      final port = int.tryParse(device.port) ?? 9100;
      await NetworkPrintHelper.printImage(
        imageBytes: pngBytes,
        ip: device.ip,
        port: port,
        paperWidthMm: device.paperWidthMm,
        addFeeds: 4,
      );
    }
  }
}

class _InvoiceLang {
  final String primary;
  final String secondary;
  final bool allowSecondary;
  const _InvoiceLang({
    required this.primary,
    required this.secondary,
    required this.allowSecondary,
  });
}
