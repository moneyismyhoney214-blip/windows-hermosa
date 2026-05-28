import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:hermosa_pos/locator.dart';
import 'package:hermosa_pos/services/printer_service.dart';
import 'package:hermosa_pos/utils/paper_width_utils.dart';
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';
import 'package:screenshot/screenshot.dart';

import '../models.dart';

/// Arguments bundle passed to the [_thermalizeOnIsolate] worker. Plain
/// data only — closures and native handles aren't transferable across
/// isolates.
class _ThermalizeArgs {
  final Uint8List imageBytes;
  final int paperWidthMm;
  final int targetWidth;
  final int threshold;
  const _ThermalizeArgs({
    required this.imageBytes,
    required this.paperWidthMm,
    required this.targetWidth,
    required this.threshold,
  });
}

/// Heavy image-processing entry-point that runs on a background isolate
/// via [compute]. Decodes the input PNG, resizes to the target raster
/// width, applies thermal-printer-friendly contrast/grayscale, then
/// binarizes per pixel. The per-pixel loop alone used to drop frames on
/// 2019-era iPads — moving it off the UI thread keeps the cashier
/// responsive while receipts are being printed.
Uint8List _thermalizeOnIsolate(_ThermalizeArgs a) {
  final source = img.decodeImage(a.imageBytes);
  if (source == null) {
    throw Exception('فشل معالجة صورة الفاتورة');
  }
  final resized = img.copyResize(
    source,
    width: a.targetWidth,
    interpolation: img.Interpolation.average,
  );
  final grayscale = img.grayscale(resized);
  final enhanced = img.adjustColor(
    grayscale,
    contrast: 3.0,
    brightness: 0.95,
    gamma: 0.5,
  );
  // Binarize in-place — copying first would double the peak memory.
  for (var y = 0; y < enhanced.height; y++) {
    for (var x = 0; x < enhanced.width; x++) {
      final pixel = enhanced.getPixel(x, y);
      final luminance =
          (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114).round();
      final value = luminance < a.threshold ? 0 : 255;
      enhanced.setPixelRgb(x, y, value, value, value);
    }
  }
  return Uint8List.fromList(img.encodePng(enhanced));
}

class ZatcaPrinterService {
  final ScreenshotController _screenshotController = ScreenshotController();
  static const double _receiptPdfRasterDpi = 300;

  /// Captures a widget and prints it as an image
  Future<void> printWidget(DeviceConfig device, Widget widget) async {
    // Use the same logical width as InvoicePrintWidget so text fills
    // the receipt paper at a readable size.
    final normalizedPaperWidthMm = normalizePaperWidthMm(device.paperWidthMm);
    final double receiptWidth = invoiceWidgetWidthForPaper(normalizedPaperWidthMm);

    final wrappedWidget = Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: Colors.white,
        child: SizedBox(
          width: receiptWidth,
          child: widget,
        ),
      ),
    );

    // Capture at high pixel ratio for crisp text
    final int dotsWidth = thermalRasterWidthForPaper(normalizedPaperWidthMm);
    final double captureRatio = dotsWidth / receiptWidth;

    final Uint8List imageBytes = await _screenshotController.captureFromWidget(
      wrappedWidget,
      pixelRatio: captureRatio,
      delay: const Duration(milliseconds: 120),
    );

    // Send raw PNG directly to printer — NetworkPrintHelper / print_listener
    // will handle the final thermal processing (resize + binarize).
    // Skipping _printImageBytes avoids double-processing that destroys clarity.
    final printerService = getIt<PrinterService>();
    await printerService.printRawImage(device, imageBytes);
  }

  Future<void> printZatcaReceipt(
    DeviceConfig device,
    ScreenshotController screenshotController,
  ) async {
    // 1. Capture the widget as an image
    final Uint8List? imageBytes = await screenshotController.capture(
      pixelRatio: 3.0,
    );

    if (imageBytes == null) throw Exception('فشل التقاط صورة الفاتورة');

    await _printImageBytes(device, imageBytes);
  }

  /// Conerts PDF bytes to images and prints them
  Future<void> printPdfBytes(DeviceConfig device, Uint8List pdfBytes) async {
    // 1. Convert PDF pages to images
    // We use a high DPI (e.g. 200 or 300) to ensure text remains crisp
    final pages =
        Printing.raster(pdfBytes, pages: [0], dpi: _receiptPdfRasterDpi);

    await for (final page in pages) {
      // Convert the PdfRaster to Uint8List PNG/JPG/Raw bytes
      // The image package can decode PNG bytes
      final Uint8List imageBytes = await page.toPng();
      await _printImageBytes(device, imageBytes);
    }
  }

  Future<void> _printImageBytes(
      DeviceConfig device, Uint8List imageBytes) async {
    // 2. Process image on a background isolate so the per-pixel
    // binarize loop doesn't stall the UI thread during checkout. The
    // worker decodes the PNG, resizes, grayscales, contrast-boosts and
    // binarizes — then returns finished PNG bytes ready to ship.
    final normalizedPaperWidthMm = normalizePaperWidthMm(device.paperWidthMm);
    final processedBytes = await compute(
      _thermalizeOnIsolate,
      _ThermalizeArgs(
        imageBytes: imageBytes,
        paperWidthMm: normalizedPaperWidthMm,
        targetWidth: thermalRasterWidthForPaper(normalizedPaperWidthMm),
        threshold: thermalThresholdForPaper(normalizedPaperWidthMm),
      ),
    );

    final printerService = getIt<PrinterService>();
    await printerService.printRawImage(device, processedBytes);
  }
}
