import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart' as fbp;
import '../services/network_print_helper.dart';
import '../services/printer_service.dart';
import '../widgets/invoice_print_widget.dart';
import '../locator.dart';

class PrintListener extends StatefulWidget {
  final Widget child;

  const PrintListener({super.key, required this.child});

  @override
  State<PrintListener> createState() => _PrintListenerState();
}

class _PrintListenerState extends State<PrintListener> {
  final PrinterService _printerService = getIt<PrinterService>();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<List<PrintRequest>>(
          valueListenable: _printerService.activeRequestsNotifier,
          builder: (context, requests, _) {
            if (requests.isEmpty) return const SizedBox.shrink();

            // Map all active requests into a Stack so they can all render
            // and capture simultaneously without blocking each other.
            return Stack(
              children: requests.map((request) => _buildPrintOverlay(request)).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPrintOverlay(PrintRequest request) {
    final device = request.device;
    final isBluetooth = device.type == 'bluetooth' || (device.bluetoothAddress?.isNotEmpty ?? false);

    if (isBluetooth) {
      // Bluetooth printing using the package's Receipt widget
      return KeyedSubtree(
        key: ValueKey(request.id),
        child: fbp.Receipt(
          builder: (context) => _buildReceiptContent(request),
        onInitialized: (controller) async {
          if (request.device.bluetoothAddress != null) {
            // Wait slightly for images and QR to load before printing
            await Future.delayed(const Duration(milliseconds: 600));

            controller.paperSize = (request.device.paperWidthMm >= 80)
                ? fbp.PaperSize.mm80
                : fbp.PaperSize.mm58;

            controller.print(
              address: request.device.bluetoothAddress!,
              keepConnected: true,
              addFeeds: 4,
            ).then((success) async {
              if (success) {
                // Wait for printer to finish feeding
                await Future.delayed(const Duration(milliseconds: 500));

                // Hardware Cut Command: [GS V 65 0] -> Select cut mode and cut paper
                try {
                  await fbp.FlutterBluetoothPrinter.printBytes(
                    address: request.device.bluetoothAddress!,
                    data: Uint8List.fromList([29, 86, 65, 0]),
                    keepConnected: true,
                  );
                } catch (e) {
                  debugPrint('⚠️ Cut command failed: $e');
                }
              }

              if (success) {
                debugPrint('✅ Bluetooth Print Success: ${request.device.name}');
              } else {
                debugPrint('❌ Bluetooth Print Failed: ${request.device.name}');
              }

              request.complete();
              _printerService.removePrintRequest(request);
            }).catchError((e) {
              debugPrint('❌ Bluetooth Print Exception [${request.device.name}]: $e');
              request.completeError(e);
              _printerService.removePrintRequest(request);
            });
          } else {
            request.completeError('No bluetooth address');
            _printerService.removePrintRequest(request);
          }
        },
      ),
    );
    } else {
      // ═══════════════════════════════════════════════════════════════════
      // LAN / Network printing
      // ═══════════════════════════════════════════════════════════════════

      final int dotsWidth = (request.device.paperWidthMm >= 80) ? 576 : 360;

      return KeyedSubtree(
        key: ValueKey(request.id),
        child: Transform.translate(
          offset: const Offset(-5000, -5000),
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxHeight: double.infinity,
            child: RepaintBoundary(
              key: request.repaintKey, // Use unique key per request
              child: Container(
                color: Colors.white,
                child: SizedBox(
                  width: dotsWidth.toDouble(),
                  child: _buildReceiptContent(request),
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildReceiptContent(PrintRequest request) {
    if (request.imageBytes != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.memory(
            request.imageBytes!,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            filterQuality: FilterQuality.none,
            isAntiAlias: false,
            gaplessPlayback: true,
          ),
          const SizedBox(height: 48),
        ],
      );
    }

    final paperWidth = request.device.paperWidthMm;

    // Trigger network print after layout — ONLY for network printers
    if (request.device.type != 'bluetooth' && (request.device.bluetoothAddress?.isEmpty ?? true)) {
       // Check if this request is already processing so we don't trigger it twice
       if (!request.isCaptureStarted) {
         request.isCaptureStarted = true;

         WidgetsBinding.instance.addPostFrameCallback((_) async {
           try {
             // Allow time for QR codes and network images to fully render
             await Future.delayed(const Duration(milliseconds: 800));

             await Future.delayed(Duration.zero);

             // Capture using THIS request's unique RepaintBoundary
             final boundary = request.repaintKey.currentContext
                 ?.findRenderObject() as RenderRepaintBoundary?;

             if (boundary == null) {
               debugPrint('❌ Network print [${request.device.name}]: RepaintBoundary not found');
               request.completeError('RepaintBoundary not found');
               _printerService.removePrintRequest(request);
               return;
             }

             final screenWidth = boundary.size.width;
             final int dotsWidth = (request.device.paperWidthMm >= 80) ? 576 : 360;
             final double pixelRatio = dotsWidth / screenWidth;

             final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
             final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
             if (byteData == null) {
               debugPrint('❌ Network print [${request.device.name}]: toByteData returned null');
               request.completeError('toByteData returned null');
               _printerService.removePrintRequest(request);
               return;
             }

             final pngBytes = byteData.buffer.asUint8List();
             debugPrint('✅ Network screenshot captured [${request.device.name}]: ${pngBytes.length} bytes (${image.width}x${image.height})');

             // Send to printer via TCP using the same raster pipeline
             final port = int.tryParse(request.device.port) ?? 9100;
             await NetworkPrintHelper.printImage(
               imageBytes: pngBytes,
               ip: request.device.ip,
               port: port,
               paperWidthMm: request.device.paperWidthMm,
               addFeeds: 4,
             );

             debugPrint('✅ Network print completed successfully: ${request.device.name}');
             request.complete();
           } catch (e) {
             debugPrint('❌ Network Print Error [${request.device.name}]: $e');
             request.completeError(e);
           } finally {
             _printerService.removePrintRequest(request);
           }
         });
       }
    }

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
          ),
          // Extra padding for mechanical cutting margin
          SizedBox(height: request.isTest ? 100 : 60),
        ],
    );
  }
}
