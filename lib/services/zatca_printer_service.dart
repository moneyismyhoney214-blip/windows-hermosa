import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';
import 'package:printing/printing.dart';
import 'package:image/image.dart' as img;
import 'package:hermosa_pos/locator.dart';
import 'package:hermosa_pos/services/printer_service.dart';
import 'package:hermosa_pos/utils/paper_width_utils.dart';
import '../models.dart';

class ZatcaPrinterService {
  final ScreenshotController _screenshotController = ScreenshotController();
  static const double _widgetCapturePixelRatio = 3.0;
  static const double _receiptPdfRasterDpi = 300;

  /// Captures a widget and prints it as an image
  Future<void> printWidget(DeviceConfig device, Widget widget) async {
    // Build a shrink-wrapped tree so the captured bitmap only contains the
    // receipt itself. Center/full-screen wrappers caused the printed receipt to
    // appear tiny because large blank margins were rasterized too.
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final mediaQuery = MediaQueryData.fromView(view);
    final wrappedWidget = MediaQuery(
      data: mediaQuery,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Material(
          color: Colors.white,
          child: Align(
            alignment: Alignment.topCenter,
            widthFactor: 1,
            heightFactor: 1,
            child: widget,
          ),
        ),
      ),
    );

    final Uint8List imageBytes = await _screenshotController.captureFromWidget(
      wrappedWidget,
      pixelRatio: _widgetCapturePixelRatio,
      delay: const Duration(milliseconds: 120), // Wait for fonts/images
    );

    await _printImageBytes(device, imageBytes);
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
    // 2. Decode and process image
    final img.Image? originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) throw Exception('فشل معالجة صورة الفاتورة');

    // 3. Prepare technical normalized image for thermal printing
    final normalizedPaperWidthMm = normalizePaperWidthMm(device.paperWidthMm);
    final thermalImage = _prepareThermalImage(
      originalImage,
      paperWidthMm: normalizedPaperWidthMm,
    );

    // 4. Encode back to Uint8List PNG for the new PrinterService
    final Uint8List processedBytes = Uint8List.fromList(img.encodePng(thermalImage));

    final printerService = getIt<PrinterService>();
    await printerService.printRawImage(device, processedBytes);
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
    // Heavy contrast + low gamma → pushes all text/lines to pure black
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
