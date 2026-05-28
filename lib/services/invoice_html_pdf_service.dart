import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html_to_pdf_plus/flutter_html_to_pdf_plus.dart';
import 'package:hermosa_pos/utils/paper_width_utils.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';

import '../locator.dart';
import '../models.dart';
import '../models/receipt_data.dart';
import '../widgets/invoice_print_widget.dart';
import 'api/api_constants.dart';
import 'api/branch_service.dart';
import 'api/device_service.dart';
import 'api/order_service.dart';
import 'language_service.dart';
import 'logger_service.dart';
import 'printer_language_settings_service.dart';
import 'printer_role_registry.dart';
import 'receipt_addon_extractor.dart';

part 'invoice_html_pdf_service_parts/invoice_html_pdf_service.models.dart';
part 'invoice_html_pdf_service_parts/invoice_html_pdf_service.styles.dart';
part 'invoice_html_pdf_service_parts/invoice_html_pdf_service.rendering.dart';
part 'invoice_html_pdf_service_parts/invoice_html_pdf_service.helpers.dart';

class InvoiceHtmlPdfService {
  final OrderService _orderService = getIt<OrderService>();
  final BranchService _branchService = getIt<BranchService>();
  final DeviceService _deviceService = getIt<DeviceService>();
  final PrinterRoleRegistry _printerRoleRegistry = getIt<PrinterRoleRegistry>();

  Future<String> generatePdfFromInvoice(
    String invoiceId, {
    String? kind,
    int? paperWidthMm,
  }) async {
    final model = await _buildModel(invoiceId, forcedKind: kind);
    final resolvedPaperWidthMm = paperWidthMm == null
        ? await _resolvePreferredPaperWidthMm()
        : _normalizePaperWidthMm(paperWidthMm);
    final html = _renderDocument(
      model,
      paperWidthMm: resolvedPaperWidthMm,
    );

    final outputDir = await getTemporaryDirectory();
    final fileName =
        'invoice_${invoiceId}_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final file = await FlutterHtmlToPdf.convertFromHtmlContent(
        content: html,
        configuration: PrintPdfConfiguration(
          targetDirectory: outputDir.path,
          targetName: fileName,
        ),
      );
      return file.path;
    } on MissingPluginException {
      // flutter_html_to_pdf_plus ships native code only for Android/iOS,
      // so on Linux/macOS/Windows desktop we fall through to: (1) headless
      // Chromium for pixel-perfect output, then (2) a dart-native
      // [pw.Document] built directly from the structured model so the
      // pipeline stays self-contained — no system browser needed. HTML
      // is kept as the last-resort path only because the print preview
      // screen still works with it; callers like the WhatsApp dispatcher
      // reject HTML output via a `%PDF-` magic check.
      return _desktopPdfFallback(
        outputDirPath: outputDir.path,
        fileName: fileName,
        html: html,
        model: model,
        paperWidthMm: resolvedPaperWidthMm,
      );
    } catch (e) {
      final lower = e.toString().toLowerCase();
      if (lower.contains('missingpluginexception') ||
          lower.contains(
              'no implementation found for method converthtmltopdf')) {
        return _desktopPdfFallback(
          outputDirPath: outputDir.path,
          fileName: fileName,
          html: html,
          model: model,
          paperWidthMm: resolvedPaperWidthMm,
        );
      }
      rethrow;
    }
  }

  /// Generate a content-tight PDF specifically for the WhatsApp
  /// dispatcher: renders [InvoicePrintWidget] off-screen, captures the
  /// PNG, trims the trailing blank rows, then wraps the cropped image in
  /// a single-page [pw.Document] whose page dimensions match the content
  /// exactly.
  ///
  /// Why this exists: the Android HTML→PDF plugin paginates against an
  /// ISO_A4 media size, so a 58/80mm thermal receipt ends up sitting in
  /// the top-left of an A4 page (or spilling onto a second page with the
  /// invoice on page 1 and white space on page 2). Both forms are
  /// embarrassing to send a customer. The print-preview path is fine
  /// because a thermal printer cuts at the end of the content; only the
  /// WhatsApp PDF needs page sizing.
  ///
  /// Returns `null` when the screenshot pipeline fails (offscreen
  /// captures on some Android WebViews) so the caller can fall back to
  /// the standard [generatePdfFromInvoice] path.
  Future<Uint8List?> generateTightPdfBytesForWhatsApp(
    String invoiceId, {
    String? kind,
    int? paperWidthMm,
  }) async {
    try {
      final model = await _buildModel(invoiceId, forcedKind: kind);
      final widthMm = paperWidthMm == null
          ? await _resolvePreferredPaperWidthMm()
          : _normalizePaperWidthMm(paperWidthMm);
      return await _renderTightPdfBytes(model: model, paperWidthMm: widthMm);
    } catch (e, st) {
      Log.e('pdf', 'generateTightPdfBytesForWhatsApp threw',
          error: e, stackTrace: st);
      return null;
    }
  }

  Future<Uint8List?> _renderTightPdfBytes({
    required _PrintInvoiceModel model,
    required int paperWidthMm,
  }) async {
    final receiptData = _mapModelToReceiptData(model);
    // Match the cashier preview: 450 logical px at 80mm so font sizes,
    // wrapping, and column widths render exactly like what the user sees
    // on-screen before sending. 3500px tall is a generous upper bound;
    // we trim it back to the actual content below.
    const captureWidth = 450.0;
    const captureHeight = 3500.0;
    const captureSize = Size(captureWidth, captureHeight);

    final pri = printerLanguageSettings.primary;
    final sec = printerLanguageSettings.secondary;
    final allow = printerLanguageSettings.allowSecondary;

    final controller = ScreenshotController();
    final pngBytes = await controller.captureFromWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: captureSize,
          devicePixelRatio: 1.0,
          textScaler: TextScaler.linear(1.0),
        ),
        child: Directionality(
          textDirection: ui.TextDirection.rtl,
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontFamily: 'Roboto',
              decoration: TextDecoration.none,
            ),
            child: Theme(
              data: ThemeData(
                scaffoldBackgroundColor: Colors.white,
                fontFamily: 'Roboto',
              ),
              child: Material(
                color: Colors.white,
                child: Align(
                  alignment: Alignment.topRight,
                  child: SizedBox(
                    width: captureWidth,
                    child: InvoicePrintWidget(
                      data: receiptData,
                      paperWidthMm: paperWidthMm,
                      primaryLang: pri,
                      secondaryLang: sec,
                      allowSecondary: allow,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      pixelRatio: 2.0,
      // Long-enough delay for an Image.network ZATCA QR to finish loading
      // before the canvas is rasterised. 80ms (the print-preview default)
      // was missing the QR on slow networks; bumping to 700ms covers a
      // local backend round-trip on a typical store wifi without making
      // the WhatsApp send feel sluggish.
      delay: const Duration(milliseconds: 700),
      targetSize: captureSize,
    );

    if (pngBytes.isEmpty) return null;

    final cropped = _cropPngToContent(pngBytes);
    final tight = cropped ?? pngBytes;
    // Final image dimensions in canvas-logical px (recover from the PNG
    // header so we keep aspect even after trimming).
    final decoded = img.decodePng(tight);
    final finalLogicalWidth = decoded == null
        ? captureWidth
        : decoded.width / 2.0; // pixelRatio: 2.0 → logical px = px / 2.
    final finalLogicalHeight = decoded == null
        ? captureHeight
        : decoded.height / 2.0;

    final pdf = pw.Document();
    final image = pw.MemoryImage(tight);
    // 1 logical px ≈ 0.75 PDF points (PDF uses 72dpi vs Flutter's 96dpi).
    final pdfWidthPt = finalLogicalWidth * 0.75;
    final pdfHeightPt = finalLogicalHeight * 0.75;
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(pdfWidthPt, pdfHeightPt),
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.Image(image, fit: pw.BoxFit.fitWidth),
      ),
    );
    return Uint8List.fromList(await pdf.save());
  }

  /// Trim trailing all-white rows from a PNG so the resulting PDF page
  /// has no awkward blank tail. Returns `null` (caller keeps the
  /// original bytes) when the decode fails or the image is already
  /// tight.
  ///
  /// Threshold of 245/255 catches anti-aliased text edges that aren't
  /// pure white but are still empty enough to be considered background.
  /// A 16-row bottom padding is kept so the very last text line has a
  /// small margin underneath instead of being kissed by the page edge.
  Uint8List? _cropPngToContent(Uint8List pngBytes) {
    try {
      final decoded = img.decodePng(pngBytes);
      if (decoded == null) return null;
      const whiteThreshold = 245;
      const bottomPaddingPx = 16;

      int lastContentRow = -1;
      for (var y = decoded.height - 1; y >= 0; y--) {
        var hasContent = false;
        for (var x = 0; x < decoded.width; x++) {
          final p = decoded.getPixel(x, y);
          if (p.r < whiteThreshold ||
              p.g < whiteThreshold ||
              p.b < whiteThreshold) {
            hasContent = true;
            break;
          }
        }
        if (hasContent) {
          lastContentRow = y;
          break;
        }
      }

      if (lastContentRow < 0) return null;
      final cropHeight =
          (lastContentRow + 1 + bottomPaddingPx).clamp(1, decoded.height);
      if (cropHeight >= decoded.height) return null; // Already tight.

      final cropped = img.copyCrop(
        decoded,
        x: 0,
        y: 0,
        width: decoded.width,
        height: cropHeight,
      );
      return Uint8List.fromList(img.encodePng(cropped));
    } catch (e) {
      Log.w('pdf', '_cropPngToContent failed — using uncropped image',
          error: e);
      return null;
    }
  }

  /// Headless-Chromium fallback for desktop hosts where the html→pdf
  /// plugin is unavailable. Tries common binary names; on success returns
  /// the generated `.pdf` path so callers (notably the WhatsApp
  /// dispatcher) see real PDF bytes.
  ///
  /// When Chromium isn't available the chain falls through to a
  /// dart-native [pw.Document] built from the [_PrintInvoiceModel] (no
  /// external binaries required — works on every desktop platform out
  /// of the box). The HTML path is kept as the absolute last resort so
  /// the print preview screen still renders, but callers like the
  /// WhatsApp dispatcher reject HTML output via a `%PDF-` magic check.
  Future<String> _desktopPdfFallback({
    required String outputDirPath,
    required String fileName,
    required String html,
    _PrintInvoiceModel? model,
    int? paperWidthMm,
  }) async {
    final chromiumPath = await _tryChromiumHtmlToPdf(
      outputDirPath: outputDirPath,
      fileName: fileName,
      html: html,
    );
    if (chromiumPath != null) return chromiumPath;

    // First desktop-PDF tier: render the HTML through `HtmlWidget` and
    // capture it via `ScreenshotController`, then wrap the PNG in a
    // pw.Document. We feed [InvoicePrintWidget] (the same widget the
    // cashier preview uses) so the WhatsApp PDF matches the preview
    // pixel-for-pixel. Works on Linux/Windows/macOS without any system
    // browser.
    final capturedPath = await _tryHtmlScreenshotPdf(
      outputDirPath: outputDirPath,
      fileName: fileName,
      html: html,
      paperWidthMm: paperWidthMm,
      model: model,
    );
    if (capturedPath != null) return capturedPath;

    // Second tier: a fully dart-native pw.Document built from the
    // structured model. Lighter visual fidelity, but it works even when
    // the screenshot pipeline trips over an unsupported HTML feature.
    if (model != null) {
      try {
        return await _dartNativePdfFromModel(
          model: model,
          outputDirPath: outputDirPath,
          fileName: fileName,
          paperWidthMm: paperWidthMm,
        );
      } catch (e, st) {
        // Surface the error so it shows up in flutter logs alongside the
        // dispatcher's own trace, but keep the HTML fallback going so
        // print preview never hard-fails.
        Log.e('pdf', '_dartNativePdfFromModel threw',
            error: e, stackTrace: st);
      }
    }
    return _writeHtmlFallback(
      outputDirPath: outputDirPath,
      fileName: fileName,
      html: html,
    );
  }

  /// Renders [InvoicePrintWidget] off-screen against the same
  /// [OrderReceiptData] the cashier preview consumes, captures it as a
  /// PNG via [ScreenshotController.captureFromWidget], and wraps the
  /// PNG in a single-page pw.Document. Returns the saved `.pdf` path on
  /// success or `null` so the caller can fall through to the next
  /// desktop tier.
  ///
  /// Using `InvoicePrintWidget` (rather than `HtmlWidget(html)`) keeps
  /// the WhatsApp PDF visually identical to what the cashier sees in
  /// `_BillPreview` / `InvoiceDetailsDialog` — those screens render the
  /// same widget tree from the same data.
  Future<String?> _tryHtmlScreenshotPdf({
    required String outputDirPath,
    required String fileName,
    required String html,
    int? paperWidthMm,
    _PrintInvoiceModel? model,
  }) async {
    try {
      final widthMm =
          (paperWidthMm == null || paperWidthMm <= 0) ? 80 : paperWidthMm;
      // The on-screen preview clamps to 450 logical px at 80mm. Match
      // that width so the rendered widget lays out exactly like the
      // preview (font sizes, line wrap, table column widths all derive
      // from the SizedBox width).
      const captureWidth = 450.0;
      // Canvas height is intentionally generous — any single invoice
      // fits within ~3000px even with addons + many items. Empty
      // bottom whitespace is trimmed visually because the PDF page
      // size is computed from the same height; the customer just sees
      // a tall thermal-receipt-style PDF.
      const captureHeight = 3500.0;
      const captureSize = Size(captureWidth, captureHeight);

      final receiptData =
          model != null ? _mapModelToReceiptData(model) : null;
      if (receiptData == null) return null;

      final pri = printerLanguageSettings.primary;
      final sec = printerLanguageSettings.secondary;
      final allow = printerLanguageSettings.allowSecondary;

      final controller = ScreenshotController();
      // captureFromWidget renders off-screen WITHOUT a host View, so a
      // bare MaterialApp explodes on `No MediaQuery widget ancestor`.
      // Provide every InheritedWidget the print widget tree depends on
      // (MediaQuery / Directionality / DefaultTextStyle / Theme) and
      // skip Scaffold/MaterialApp entirely.
      final pngBytes = await controller.captureFromWidget(
        MediaQuery(
          // Match the canvas size so RenderPositionedBox aligns the
          // widget against the top-left without center-cropping when
          // the invoice is taller than the default screen.
          data: const MediaQueryData(
            size: captureSize,
            devicePixelRatio: 1.0,
            textScaler: TextScaler.linear(1.0),
          ),
          child: Directionality(
            textDirection: ui.TextDirection.rtl,
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontFamily: 'Roboto',
                decoration: TextDecoration.none,
              ),
              child: Theme(
                data: ThemeData(
                  scaffoldBackgroundColor: Colors.white,
                  fontFamily: 'Roboto',
                ),
                child: Material(
                  color: Colors.white,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: SizedBox(
                      width: captureWidth,
                      child: InvoicePrintWidget(
                        data: receiptData,
                        paperWidthMm: widthMm,
                        primaryLang: pri,
                        secondaryLang: sec,
                        allowSecondary: allow,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        pixelRatio: 2.0,
        delay: const Duration(milliseconds: 80),
        targetSize: captureSize,
      );

      if (pngBytes.isEmpty) return null;

      // Wrap the captured PNG in a tall single-page PDF whose aspect
      // matches the canvas. 1 logical px ≈ 0.75 PDF points (PDF uses
      // 72dpi vs Flutter's 96dpi).
      final pdf = pw.Document();
      final image = pw.MemoryImage(pngBytes);
      const pdfWidthPt = captureWidth * 0.75;
      const pdfHeightPt = captureHeight * 0.75;
      pdf.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(pdfWidthPt, pdfHeightPt),
          margin: pw.EdgeInsets.zero,
          build: (context) => pw.Image(image, fit: pw.BoxFit.fitWidth),
        ),
      );

      final pdfPath = '$outputDirPath/$fileName.pdf';
      final outFile = File(pdfPath);
      await outFile.writeAsBytes(await pdf.save(), flush: true);
      return pdfPath;
    } catch (e, st) {
      Log.e('pdf', '_tryHtmlScreenshotPdf threw',
          error: e, stackTrace: st);
      return null;
    }
  }

  /// Reconcile the invoice totals using a mix of backend fields,
  /// branch tax settings, and the items sum. Different invoice
  /// endpoints populate different field names — some fill `total` with
  /// the grand total and leave `grand_total` empty, others use
  /// `total` for the pre-tax subtotal and `grand_total` for the
  /// inclusive total. Without normalisation, `InvoicePrintWidget` can
  /// end up showing "Total After Tax: 0" with a bogus
  /// "Total Items Discount: -<items_sum>" line. The logic here:
  ///
  ///   1. Read the candidate fields directly.
  ///   2. Take items_sum as ground truth for the line subtotal.
  ///   3. If `grand_total` is missing, use whichever of `total` /
  ///      `final_total` looks larger than the items_sum (= already
  ///      includes tax) before falling back to `items_sum + tax`.
  ///   4. If `subtotal` is missing, derive it from
  ///      `grand - tax` when both are known, otherwise items_sum.
  ///   5. If `tax` is missing but the difference between grand and
  ///      subtotal is non-trivial, use that.
  _InvoiceTotals _resolveInvoiceTotals(
    Map<String, dynamic> invoice,
    List<ReceiptItem> items,
  ) {
    double pickNum(List<String> keys) {
      for (final key in keys) {
        final v = invoice[key];
        if (v is num) return v.toDouble();
        if (v is String) {
          final parsed = double.tryParse(v);
          if (parsed != null) return parsed;
        }
      }
      return 0;
    }

    final itemsSum = items.fold<double>(0.0, (s, item) => s + item.total);
    final rawTotal = pickNum(['total']);
    final rawGrand =
        pickNum(['grand_total', 'total_incl_tax', 'final_total']);
    final rawSubtotal =
        pickNum(['total_excl_tax', 'subtotal', 'price_before_tax']);
    final rawTax = pickNum(['tax', 'vat', 'tax_value']);

    // `price_after_discount` is the *only* total field the booking-route
    // invoice payload always populates (grand_total/total stay null on
    // free or discounted orders). Trust it when it parses to a real
    // number — this is what makes the FREE ORDER banner fire for orders
    // discounted to zero, where every other total candidate above is
    // null and the items_sum fallback would report the pre-discount
    // baseline.
    final rawPadValue = invoice['price_after_discount'];
    final hasExplicitPriceAfterDiscount = rawPadValue is num ||
        (rawPadValue is String && double.tryParse(rawPadValue) != null);
    final rawPriceAfterDiscount = hasExplicitPriceAfterDiscount
        ? (rawPadValue is num
            ? rawPadValue.toDouble()
            : double.parse(rawPadValue as String))
        : 0.0;

    var totalInclVat = rawGrand;
    if (totalInclVat <= 0) {
      if (hasExplicitPriceAfterDiscount) {
        // Explicit post-discount amount from backend. Add tax separately
        // — backends typically expose `price_after_discount` pre-tax.
        // For a fully-free order both are 0 so the math collapses to 0.
        totalInclVat = rawPriceAfterDiscount + rawTax;
      } else if (rawTotal > itemsSum + 0.01) {
        // Some legacy routes shove the grand total into `total`. Trust
        // it when it exceeds the items sum (i.e. it has tax baked in).
        totalInclVat = rawTotal;
      } else if (rawTotal > 0) {
        totalInclVat = rawTotal + rawTax;
      } else {
        totalInclVat = itemsSum + rawTax;
      }
    }

    var totalExclVat = rawSubtotal;
    if (totalExclVat <= 0) {
      if (rawTotal > 0 && rawTotal <= itemsSum + 0.01) {
        // `total` looks like the pre-tax line total.
        totalExclVat = rawTotal;
      } else if (totalInclVat > 0 && rawTax > 0 &&
          (totalInclVat - rawTax) > 0) {
        totalExclVat = totalInclVat - rawTax;
      } else {
        totalExclVat = itemsSum;
      }
    }

    var vatAmount = rawTax;
    if (vatAmount <= 0 && totalInclVat > totalExclVat) {
      vatAmount = totalInclVat - totalExclVat;
    }

    return _InvoiceTotals(
      totalExclVat: totalExclVat,
      vatAmount: vatAmount,
      totalInclVat: totalInclVat,
    );
  }

  /// Adapt the structured [_PrintInvoiceModel] into an
  /// [OrderReceiptData] so we can hand it straight to
  /// [InvoicePrintWidget] — the same widget tree the in-app preview
  /// uses. The mapping mirrors `_mapToOrderReceiptData` in
  /// `invoice_details_dialog.build_widgets.dart` but works against the
  /// already-parsed model so we don't refetch.
  OrderReceiptData _mapModelToReceiptData(_PrintInvoiceModel model) {
    String pickStr(Map<dynamic, dynamic>? map, List<String> keys) {
      if (map == null) return '';
      for (final key in keys) {
        final v = map[key]?.toString().trim();
        if (v != null && v.isNotEmpty && v.toLowerCase() != 'null') return v;
      }
      return '';
    }

    double pickNum(Map<dynamic, dynamic>? map, List<String> keys) {
      if (map == null) return 0;
      for (final key in keys) {
        final v = map[key];
        if (v is num) return v.toDouble();
        if (v is String) {
          final parsed = double.tryParse(v);
          if (parsed != null) return parsed;
        }
      }
      return 0;
    }

    Map<String, dynamic>? asMap(dynamic v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
      return null;
    }

    final invoice = model.invoice;
    final branch = model.branch;
    final seller = model.seller;
    final envelope = model.envelope;
    final booking = model.booking;
    // The client record can live under several keys depending on which
    // backend route returned the invoice (booking flow vs salons vs
    // salons-with-bookings). Pick the first non-empty match — same
    // pattern the dispatcher's `_fetchCustomerFromBackend` uses.
    Map<String, dynamic> firstNonEmpty(List<Map<String, dynamic>> maps) {
      for (final m in maps) {
        if (m.isNotEmpty) return m;
      }
      return const <String, dynamic>{};
    }

    final client = firstNonEmpty([
      model.client,
      asMap(invoice['customer']) ?? const <String, dynamic>{},
      asMap(booking['customer']) ?? const <String, dynamic>{},
      asMap(envelope['customer']) ?? const <String, dynamic>{},
      asMap(invoice['client']) ?? const <String, dynamic>{},
    ]);

    final receiptItems = model.items.map((item) {
      final addons = extractReceiptAddonsFromItem(item);

      final qty = pickNum(item, ['quantity', 'qty', 'count']);
      final unitPrice =
          pickNum(item, ['unit_price', 'meal_price', 'price', 'price_pure']);
      final rawTotal = pickNum(item, ['total', 'amount', 'price_after_tax']);
      var lineDiscount = pickNum(item, ['discount_amount', 'discount']);
      final explicitOriginal =
          pickNum(item, ['original_total', 'price_before_discount']);

      // Detect which convention this backend uses for the `total` field.
      // Some routes (e.g. salons free-order from `bookings/{id}`) report
      // `total` as the PRE-discount list price and a separate `discount`,
      // so the actually-paid line total is `total - discount`. Others
      // store `total` already POST-discount and use `discount` as
      // informational. We use `unit_price * quantity` as the anchor:
      //   * If it matches `total` (and a discount is present), `total`
      //     is the pre-discount list price.
      //   * If it matches `total + discount`, `total` is post-discount.
      //   * Otherwise default to post-discount (the safer assumption —
      //     it never causes silently-wrong negative balances).
      double originalPrice;
      double actualLineTotal;
      if (explicitOriginal > 0) {
        // Backend handed us the pre-discount baseline directly.
        originalPrice = explicitOriginal;
        actualLineTotal = (explicitOriginal - lineDiscount)
            .clamp(0.0, explicitOriginal)
            .toDouble();
      } else if (unitPrice > 0 && qty > 0 && lineDiscount > 0) {
        final baseline = unitPrice * qty;
        final preDiscountFit = (rawTotal - baseline).abs() < 0.01;
        final postDiscountFit =
            (rawTotal + lineDiscount - baseline).abs() < 0.01;
        if (preDiscountFit && !postDiscountFit) {
          originalPrice = rawTotal;
          actualLineTotal =
              (rawTotal - lineDiscount).clamp(0.0, rawTotal).toDouble();
        } else {
          originalPrice = rawTotal + lineDiscount;
          actualLineTotal = rawTotal;
        }
      } else if (lineDiscount > 0) {
        // Discount present but no unit-price anchor — default to the
        // post-discount convention (matches the cashier-side snapshot).
        originalPrice = rawTotal + lineDiscount;
        actualLineTotal = rawTotal;
      } else {
        // No discount info at all — fall back to `unit_price * quantity`
        // for originalPrice so the "free" math below still has something
        // to compare against on sparse legacy payloads.
        originalPrice = (unitPrice > 0 && qty > 0) ? unitPrice * qty : 0;
        actualLineTotal = rawTotal;
      }

      // Recover discount when missing but the originalPrice/actual delta
      // implies one (so the row still prints "(خصم -X)" instead of going
      // silent).
      if (lineDiscount <= 0 && originalPrice > actualLineTotal + 0.01) {
        lineDiscount = originalPrice - actualLineTotal;
      }

      // Backend doesn't persist an `is_free` flag — both the cashier's
      // "Free" toggle AND a 100%-discount slider serialise identically
      // (total == discount, total_tax == 0). Verified against IN-831
      // line 3 (شاي ليمون بارد): total=13.91 / discount=13.91 /
      // total_tax=0 with no `is_free` field. Since we can't recover
      // the cashier's original intent from backend, we treat ANY math-
      // fully-discounted line as "مجاناً" — the friendlier default for
      // the common case. The cashier-side direct print path stays
      // truthful via `ReceiptBuilderService` (which DOES see the
      // `is_free` cart flag and only sets the label when set).
      final isExplicitFree = item['is_free'] == true || item['isFree'] == true;
      final isMathFullyDiscounted = originalPrice > 0 &&
          actualLineTotal <= 0.001 &&
          lineDiscount > 0;
      final treatAsFree = isExplicitFree || isMathFullyDiscounted;
      final explicitDiscountPct = pickNum(item, ['discount_percentage']);

      return ReceiptItem(
        nameAr: pickStr(item, ['service_name', 'meal_name', 'name', 'item_name']),
        nameEn: pickStr(item, ['meal_name_en', 'name_en']),
        quantity: qty,
        unitPrice: unitPrice,
        total: actualLineTotal,
        addons: addons.isEmpty ? null : addons,
        discountAmount: lineDiscount > 0 ? lineDiscount : null,
        discountPercentage:
            explicitDiscountPct > 0 ? explicitDiscountPct : null,
        discountName: treatAsFree
            ? 'مجاناً'
            : (pickStr(item, ['discount_name']).isEmpty
                ? null
                : pickStr(item, ['discount_name'])),
        originalPrice: originalPrice > 0 ? originalPrice : null,
      );
    }).toList(growable: false);

    // Order-level discount fields. CRITICAL: the backend's `discount`
    // field is the *total* order discount (per-item sum + any coupon),
    // not the coupon alone — verified IN-831 where `discount=36.17`
    // exactly equals `total_items_discount=36.17` despite no coupon
    // being applied. Subtract the per-item portion so the DISCOUNT
    // banner only fires for a TRUE order-level coupon/manual discount
    // (matching the user's requirement that per-item discounts must
    // surface inline next to their item, not as a banner).
    final orderDiscountTotal =
        pickNum(invoice, ['discount', 'discount_amount', 'order_discount']);
    final itemsDiscountSum = pickNum(invoice, ['total_items_discount']);
    final orderDiscountRaw =
        (orderDiscountTotal - itemsDiscountSum > 0.01)
            ? orderDiscountTotal - itemsDiscountSum
            : 0.0;
    final orderDiscountPctRaw =
        pickNum(invoice, ['discount_percentage', 'order_discount_percentage']);
    final orderDiscountNameRaw =
        pickStr(invoice, ['discount_name', 'discount_code', 'coupon_code']);

    final paysList = (invoice['pays'] as List? ?? const [])
        .map(asMap)
        .where((m) => m != null)
        .cast<Map<String, dynamic>>()
        .map((p) {
      final method = pickStr(p, ['pay_method', 'method', 'name']).toLowerCase();
      final amount = pickNum(p, ['amount', 'value', 'paid', 'total']);
      String label;
      switch (method) {
        case 'cash':
        case 'نقدي':
        case 'كاش':
          label = 'نقدي';
          break;
        case 'card':
        case 'mada':
        case 'visa':
        case 'بطاقة':
          label = 'بطاقة';
          break;
        case 'stc':
        case 'stc_pay':
          label = 'STC Pay';
          break;
        case 'bank_transfer':
        case 'bank':
          label = 'تحويل بنكي';
          break;
        case 'wallet':
          label = 'محفظة';
          break;
        case 'pay_later':
        case 'postpaid':
        case 'deferred':
          label = 'الدفع بالآجل';
          break;
        default:
          label = method.isEmpty ? 'نقدي' : method;
      }
      return ReceiptPayment(methodLabel: label, amount: amount);
    }).toList(growable: false);

    final paymentMethodLabel = paysList.isNotEmpty
        ? paysList.map((p) => p.methodLabel).toSet().join(' - ')
        : pickStr(invoice, ['pay_method', 'pays']);

    final issueDateTime = pickStr(invoice, ['date', 'created_at']).isEmpty
        ? '${model.date} ${model.time}'.trim()
        : pickStr(invoice, ['date', 'created_at']);

    // ZATCA QR resolution — match the dialog mapper's lookup so the
    // WhatsApp/print PDF gets the same TLV the on-screen preview shows.
    // Different invoice endpoints populate different keys:
    //   * `qr_image` / `qr`     — base64-TLV string the widget renders synchronously.
    //   * `zatca_qr`            — same payload under a different name (salons).
    //   * `zatca_qr_image`      — pre-rendered image URL (async fallback).
    // We try the TLV-capable keys first; if all of those are empty we leave
    // [OrderReceiptData.qrCodeBase64] blank and let the widget fall through
    // to `zatcaQrImage` (URL).
    String resolvedQrTlv = model.qrImage;
    if (resolvedQrTlv.isEmpty) {
      resolvedQrTlv = pickStr(invoice, ['qr_image', 'qr', 'zatca_qr']);
    }
    if (resolvedQrTlv.isEmpty) {
      resolvedQrTlv = pickStr(envelope, ['qr_image', 'qr', 'zatca_qr']);
    }
    // Preserve `data:image/...` prefixes verbatim — the print widget has a
    // dedicated `Image.memory` branch for them; stripping the prefix here
    // caused the bytes to be misread as TLV and emit a garbage QR.
    final qrImage = resolvedQrTlv;
    final zatcaQrImageUrlFromInvoice =
        pickStr(invoice, ['zatca_qr_image']).isEmpty
            ? pickStr(envelope, ['zatca_qr_image'])
            : pickStr(invoice, ['zatca_qr_image']);

    final totals = _resolveInvoiceTotals(invoice, receiptItems);

    return OrderReceiptData(
      invoiceNumber: model.invoiceNumber.replaceAll('#', '').trim(),
      issueDateTime: issueDateTime,
      sellerNameAr:
          pickStr(seller, ['name', 'seller_name']).isNotEmpty
              ? pickStr(seller, ['name', 'seller_name'])
              : pickStr(branch, ['name']),
      sellerNameEn: pickStr(seller, ['name_en', 'seller_name_en']),
      vatNumber: pickStr(seller, ['vat_number', 'tax_number']).isNotEmpty
          ? pickStr(seller, ['vat_number', 'tax_number'])
          : pickStr(branch, ['vat_number', 'tax_number']),
      branchName: pickStr(branch, ['name', 'branch_name']),
      items: receiptItems,
      totalExclVat: totals.totalExclVat,
      vatAmount: totals.vatAmount,
      totalInclVat: totals.totalInclVat,
      paymentMethod: paymentMethodLabel,
      payments: paysList,
      qrCodeBase64: qrImage,
      zatcaQrImage: zatcaQrImageUrlFromInvoice.isEmpty
          ? null
          : zatcaQrImageUrlFromInvoice,
      sellerLogo: pickStr(branch, ['logo', 'seller_logo']).isEmpty
          ? pickStr(seller, ['logo'])
          : pickStr(branch, ['logo', 'seller_logo']),
      branchAddress: pickStr(branch, ['address']),
      branchMobile: pickStr(branch, ['mobile', 'phone']),
      cashierName: pickStr(invoice, ['cashier_name']).isEmpty
          ? pickStr(envelope, ['cashier_name'])
          : pickStr(invoice, ['cashier_name']),
      orderType: pickStr(invoice, ['order_type']).isEmpty
          ? null
          : pickStr(invoice, ['order_type']),
      orderNumber: model.orderNumber.isEmpty ? null : model.orderNumber,
      // Customer name / phone can be either inside the resolved client
      // map or flattened on the invoice/booking root, so try both.
      clientName: () {
        final fromClient = pickStr(client, ['name', 'customer_name']);
        if (fromClient.isNotEmpty) return fromClient;
        final fromInvoice =
            pickStr(invoice, ['customer_name', 'client_name', 'client']);
        if (fromInvoice.isNotEmpty) return fromInvoice;
        final fromBooking = pickStr(booking, ['customer_name', 'client_name']);
        return fromBooking.isEmpty ? null : fromBooking;
      }(),
      clientPhone: () {
        final fromClient =
            pickStr(client, ['mobile', 'phone', 'phone_number']);
        if (fromClient.isNotEmpty) return fromClient;
        final fromInvoice =
            pickStr(invoice, ['customer_phone', 'client_phone', 'phone']);
        if (fromInvoice.isNotEmpty) return fromInvoice;
        final fromBooking = pickStr(booking, ['customer_phone', 'client_phone']);
        return fromBooking.isEmpty ? null : fromBooking;
      }(),
      tableNumber: pickStr(invoice, ['table_number', 'table']).isEmpty
          ? null
          : pickStr(invoice, ['table_number', 'table']),
      carNumber: pickStr(invoice, ['car_number']),
      commercialRegisterNumber:
          pickStr(seller, ['commercial_register']).isEmpty
              ? pickStr(branch, ['commercial_register'])
              : pickStr(seller, ['commercial_register']),
      orderDiscountAmount: orderDiscountRaw > 0 ? orderDiscountRaw : null,
      orderDiscountPercentage:
          orderDiscountPctRaw > 0 ? orderDiscountPctRaw : null,
      orderDiscountName:
          orderDiscountNameRaw.isEmpty ? null : orderDiscountNameRaw,
    );
  }

  Future<String?> _tryChromiumHtmlToPdf({
    required String outputDirPath,
    required String fileName,
    required String html,
  }) async {
    if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
      return null;
    }
    final candidates = Platform.isWindows
        ? const [
            'chrome.exe',
            'chromium.exe',
            'msedge.exe',
          ]
        : const [
            'chromium',
            'chromium-browser',
            'google-chrome',
            'google-chrome-stable',
            'chrome',
            'microsoft-edge',
          ];
    String? binary;
    for (final name in candidates) {
      final found = await _which(name);
      if (found != null) {
        binary = found;
        break;
      }
    }
    if (binary == null) return null;

    final htmlPath = '$outputDirPath/$fileName.html';
    final pdfPath = '$outputDirPath/$fileName.pdf';
    final htmlFile = File(htmlPath);
    await htmlFile.writeAsString(html, flush: true);

    try {
      final result = await Process.run(binary, [
        '--headless',
        '--disable-gpu',
        '--no-sandbox',
        '--no-pdf-header-footer',
        '--print-to-pdf=$pdfPath',
        Uri.file(htmlPath).toString(),
      ]).timeout(const Duration(seconds: 30));
      // Best-effort cleanup of the source HTML — the PDF is what we keep.
      unawaited(htmlFile.delete().catchError((_) => htmlFile));
      final pdfFile = File(pdfPath);
      if (!await pdfFile.exists()) return null;
      final size = await pdfFile.length();
      if (size <= 0) {
        await pdfFile.delete().catchError((_) => pdfFile);
        return null;
      }
      if (result.exitCode != 0) {
        // Some Chromium builds exit non-zero even on success when DevTools
        // chatter shows up on stderr — only fail when the PDF is missing.
        // Fall through.
      }
      return pdfPath;
    } catch (_) {
      // Cleanup on any failure so we don't leak temp files.
      unawaited(htmlFile.delete().catchError((_) => htmlFile));
      unawaited(File(pdfPath).delete().catchError((_) => File(pdfPath)));
      return null;
    }
  }

  Future<String?> _which(String binary) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('where', [binary]);
        if (result.exitCode != 0) return null;
        final out = (result.stdout as String).trim();
        if (out.isEmpty) return null;
        return out.split('\n').first.trim();
      }
      final result = await Process.run('which', [binary]);
      if (result.exitCode != 0) return null;
      final out = (result.stdout as String).trim();
      if (out.isEmpty) return null;
      return out.split('\n').first.trim();
    } catch (_) {
      return null;
    }
  }

  Future<String> generatePreviewHtmlFromInvoice(
    String invoiceId, {
    String? kind,
    int? paperWidthMm,
  }) async {
    final model = await _buildModel(invoiceId, forcedKind: kind);
    final resolvedPaperWidthMm = paperWidthMm == null
        ? await _resolvePreferredPaperWidthMm()
        : _normalizePaperWidthMm(paperWidthMm);
    final html = _renderDocument(
      model,
      paperWidthMm: resolvedPaperWidthMm,
    );

    final outputDir = await getTemporaryDirectory();
    final fileName =
        'invoice_preview_${invoiceId}_${DateTime.now().millisecondsSinceEpoch}';
    final file = File('${outputDir.path}/$fileName.html');
    await file.writeAsString(html, flush: true);
    return file.path;
  }

  Future<String> _writeHtmlFallback({
    required String outputDirPath,
    required String fileName,
    required String html,
  }) async {
    final file = File('$outputDirPath/$fileName.html');
    await file.writeAsString(html, flush: true);
    return file.path;
  }

  // ───────────────────────────────────────────────────────────────────
  // Dart-native PDF fallback
  //
  // Builds a pw.Document directly from [_PrintInvoiceModel] using the
  // pure-Dart `pdf` package. This path runs on Linux / Windows / macOS
  // with no external binaries — every glyph is rendered by `pdf` against
  // the bundled Arabic OTF, so it works on a fresh CI box exactly the
  // same way it works on a developer laptop.
  //
  // The layout is intentionally simple (header / customer / items table /
  // totals / QR) — pixel parity with the thermal-receipt HTML isn't
  // required for the WhatsApp use case. The customer just needs a
  // legible PDF copy of their invoice.
  // ───────────────────────────────────────────────────────────────────

  /// Bundled Noto Naskh Arabic TTFs. The `pdf` package's `pw.Font.ttf`
  /// requires a TTF with a Unicode cmap to render Arabic glyphs — the
  /// previously-shipped Alkhalil OTF threw `Cannot decode the string to
  /// Latin1` for any Arabic text on the dart-native fallback path.
  static const String _kArabicFontAssetRegular =
      'assets/NotoNaskhArabic-Regular.ttf';
  static const String _kArabicFontAssetBold =
      'assets/NotoNaskhArabic-Bold.ttf';

  /// Memoized so we don't decode the TTFs every time the WhatsApp
  /// dispatcher runs.
  pw.Font? _cachedArabicFont;
  pw.Font? _cachedArabicBoldFont;

  Future<pw.Font?> _loadArabicFont({bool bold = false}) async {
    final cached = bold ? _cachedArabicBoldFont : _cachedArabicFont;
    if (cached != null) return cached;
    final assetPath = bold ? _kArabicFontAssetBold : _kArabicFontAssetRegular;
    try {
      final data = await rootBundle.load(assetPath);
      final font = pw.Font.ttf(data);
      if (bold) {
        _cachedArabicBoldFont = font;
      } else {
        _cachedArabicFont = font;
      }
      return font;
    } catch (e) {
      Log.w('pdf', 'failed to load bundled Arabic font ($assetPath)', error: e);
      return null;
    }
  }

  Future<String> _dartNativePdfFromModel({
    required _PrintInvoiceModel model,
    required String outputDirPath,
    required String fileName,
    int? paperWidthMm,
  }) async {
    final regular = await _loadArabicFont();
    final bold = await _loadArabicFont(bold: true);
    final theme = (regular != null)
        ? pw.ThemeData.withFont(
            base: regular,
            bold: bold ?? regular,
            italic: regular,
            boldItalic: bold ?? regular,
          )
        : pw.ThemeData();

    final pdf = pw.Document(theme: theme);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        textDirection: pw.TextDirection.rtl,
        build: (context) => _buildNativePdfBody(model),
      ),
    );

    final bytes = await pdf.save();
    final pdfPath = '$outputDirPath/$fileName.pdf';
    final outFile = File(pdfPath);
    await outFile.writeAsBytes(bytes, flush: true);
    return pdfPath;
  }

  List<pw.Widget> _buildNativePdfBody(_PrintInvoiceModel model) {
    String pickStr(Map<dynamic, dynamic>? map, List<String> keys) {
      if (map == null) return '';
      for (final key in keys) {
        final v = map[key]?.toString().trim();
        if (v != null && v.isNotEmpty && v.toLowerCase() != 'null') {
          return v;
        }
      }
      return '';
    }

    final sellerName = pickStr(model.seller, ['name', 'seller_name']);
    final branchName = pickStr(model.branch, ['name', 'branch_name']);
    final headerName = sellerName.isNotEmpty ? sellerName : branchName;
    final vatNumber = pickStr(model.seller, ['vat_number', 'tax_number']);
    final branchPhone = pickStr(model.branch, ['mobile', 'phone']);
    final branchAddress = pickStr(model.branch, ['address']);
    final clientName = pickStr(model.client, ['name']);
    final clientPhone = pickStr(model.client, ['mobile', 'phone', 'phone_number']);
    final dateLine = [model.date, model.time].where((s) => s.isNotEmpty).join(' ');

    return <pw.Widget>[
      pw.Center(
        child: pw.Text(
          headerName.isEmpty ? 'فاتورة' : headerName,
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
        ),
      ),
      if (vatNumber.isNotEmpty)
        pw.Center(
          child: pw.Text('الرقم الضريبي: $vatNumber',
              style: const pw.TextStyle(fontSize: 11)),
        ),
      if (branchPhone.isNotEmpty)
        pw.Center(
          child: pw.Text('الهاتف: $branchPhone',
              style: const pw.TextStyle(fontSize: 11)),
        ),
      if (branchAddress.isNotEmpty)
        pw.Center(
          child: pw.Text(branchAddress,
              style: const pw.TextStyle(fontSize: 11)),
        ),
      pw.SizedBox(height: 8),
      pw.Divider(thickness: 1),
      pw.SizedBox(height: 6),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('رقم الفاتورة: ${model.invoiceNumber}',
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold)),
          if (dateLine.isNotEmpty)
            pw.Text(dateLine, style: const pw.TextStyle(fontSize: 12)),
        ],
      ),
      if (clientName.isNotEmpty || clientPhone.isNotEmpty) ...[
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            if (clientName.isNotEmpty)
              pw.Text('العميل: $clientName',
                  style: const pw.TextStyle(fontSize: 12)),
            if (clientPhone.isNotEmpty)
              pw.Text(clientPhone,
                  style: const pw.TextStyle(fontSize: 12)),
          ],
        ),
      ],
      pw.SizedBox(height: 12),
      _buildNativeItemsTable(model),
      pw.SizedBox(height: 12),
      _buildNativeTotals(model),
      if (model.qrImage.isNotEmpty) ...[
        pw.SizedBox(height: 16),
        pw.Center(child: _buildNativeQrImage(model.qrImage) ?? pw.SizedBox()),
      ],
      if (model.policy.isNotEmpty) ...[
        pw.SizedBox(height: 16),
        pw.Divider(),
        pw.Text(model.policy,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      ],
    ];
  }

  pw.Widget _buildNativeItemsTable(_PrintInvoiceModel model) {
    String pickStr(Map<dynamic, dynamic> item, List<String> keys) {
      for (final key in keys) {
        final v = item[key]?.toString().trim();
        if (v != null && v.isNotEmpty && v.toLowerCase() != 'null') return v;
      }
      return '';
    }

    final headerCells = ['الصنف', 'الكمية', 'السعر', 'الإجمالي'];

    return pw.Table(
      border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(3.5),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1.4),
        3: pw.FlexColumnWidth(1.4),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: headerCells
              .map((label) => _nativeTableCell(label, bold: true))
              .toList(growable: false),
        ),
        ...model.items.map((rawItem) {
          final item = rawItem;
          final name = pickStr(item, ['item_name', 'name', 'meal_name']);
          final qty = pickStr(item, ['quantity', 'qty', 'count']);
          final price = pickStr(
              item, ['meal_price', 'unit_price', 'price', 'after_offer_price']);
          final total = pickStr(item, ['total', 'price_after_tax']);
          return pw.TableRow(
            children: [
              _nativeTableCell(name),
              _nativeTableCell(qty.isEmpty ? '1' : qty, center: true),
              _nativeTableCell(price, center: true),
              _nativeTableCell(total, center: true),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _nativeTableCell(String text, {bool bold = false, bool center = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.start,
      ),
    );
  }

  pw.Widget _buildNativeTotals(_PrintInvoiceModel model) {
    String pickStr(Map<dynamic, dynamic> map, List<String> keys) {
      for (final key in keys) {
        final v = map[key]?.toString().trim();
        if (v != null && v.isNotEmpty && v.toLowerCase() != 'null') return v;
      }
      return '';
    }

    final invoice = model.invoice;
    final currency = model.currencyAr.isNotEmpty
        ? model.currencyAr
        : (model.currencyEn.isNotEmpty ? model.currencyEn : '');

    final subtotal = pickStr(invoice,
        ['total_excl_tax', 'subtotal', 'price_before_tax', 'before_tax']);
    final tax = pickStr(invoice, ['tax', 'vat', 'tax_value']);
    final discount = pickStr(invoice, ['discount']);
    final grand = pickStr(invoice,
        ['grand_total', 'total_incl_tax', 'final_total', 'total']);

    pw.Widget row(String label, String value, {bool emphasis = false}) {
      final style = pw.TextStyle(
        fontSize: emphasis ? 14 : 12,
        fontWeight: emphasis ? pw.FontWeight.bold : pw.FontWeight.normal,
      );
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label, style: style),
            pw.Text(
              currency.isEmpty ? value : '$value $currency',
              style: style,
            ),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (subtotal.isNotEmpty) row('الإجمالي قبل الضريبة:', subtotal),
        if (discount.isNotEmpty) row('الخصم:', discount),
        if (tax.isNotEmpty) row('الضريبة:', tax),
        pw.Divider(thickness: 1),
        if (grand.isNotEmpty) row('الإجمالي النهائي:', grand, emphasis: true),
      ],
    );
  }

  pw.Widget? _buildNativeQrImage(String qrImage) {
    if (qrImage.isEmpty) return null;
    Uint8List? bytes;
    try {
      if (qrImage.startsWith('data:')) {
        final commaIdx = qrImage.indexOf(',');
        if (commaIdx <= 0) return null;
        bytes = base64Decode(qrImage.substring(commaIdx + 1));
      } else if (qrImage.startsWith('/') || qrImage.contains(':\\')) {
        final file = File(qrImage);
        if (file.existsSync()) bytes = file.readAsBytesSync();
      } else {
        // Assume bare base64 (some payloads strip the data URL prefix).
        bytes = base64Decode(qrImage);
      }
    } catch (_) {
      return null;
    }
    if (bytes == null || bytes.isEmpty) return null;
    return pw.Image(pw.MemoryImage(bytes), width: 130, height: 130);
  }

  /// Returns the raw HTML string for an invoice (no file I/O).
  /// Used by the preview screen to render the invoice natively.
  Future<String> generateHtmlString(
    String invoiceId, {
    String? kind,
    int? paperWidthMm,
  }) async {
    final model = await _buildModel(invoiceId, forcedKind: kind);
    final resolvedPaperWidthMm = paperWidthMm == null
        ? await _resolvePreferredPaperWidthMm()
        : _normalizePaperWidthMm(paperWidthMm);
    return _renderDocument(
      model,
      paperWidthMm: resolvedPaperWidthMm,
    );
  }

  /// Generates a credit note (فاتورة دائن) PDF for refunded items only.
  /// [refundedItems] is the list of items that were refunded, each with
  /// keys: name, quantity, total (and optionally unit_price, addons).
  Future<String> generateCreditNotePdf(
    String invoiceId, {
    required List<Map<String, dynamic>> refundedItems,
    required double refundTotal,
    int? paperWidthMm,
  }) async {
    final model =
        await _buildModel(invoiceId, forcedKind: 'refundSalesInvoice');

    // Replace items with only the refunded items. The fallback name picks
    // the primary invoice language so an unnamed line never shows stray
    // Arabic on a Spanish/English/etc. receipt.
    final fallbackItemName = _mainLbl(
      model.language,
      ar: 'عنصر',
      en: 'Item',
      hi: 'आइटम',
      ur: 'آئٹم',
      es: 'Artículo',
      tr: 'Ürün',
    );
    final creditItems = refundedItems.map((item) {
      return <String, dynamic>{
        'name': item['name'] ?? fallbackItemName,
        'quantity': item['quantity'] ?? 1,
        'price': item['unit_price'] ?? item['total'] ?? 0,
        'total': item['total'] ?? 0,
        'addons': item['addons'],
      };
    }).toList();

    // Compute tax using the branch's configured rate — credit notes for
    // tax-free branches should not synthesize a 15% VAT split.
    final creditTaxRate =
        _branchService.cachedHasTax ? _branchService.cachedTaxRate : 0.0;
    final creditTaxMultiplier = 1.0 + creditTaxRate;
    final totalBeforeTax = creditTaxMultiplier > 0
        ? refundTotal / creditTaxMultiplier
        : refundTotal;
    final taxAmount = refundTotal - totalBeforeTax;

    final creditModel = _PrintInvoiceModel(
      envelope: model.envelope,
      invoice: <String, dynamic>{
        ...model.invoice,
        'items': creditItems,
        'grand_total': refundTotal,
        'total': totalBeforeTax,
        'tax': taxAmount,
        'vat': taxAmount,
        'price_before_tax': totalBeforeTax,
      },
      branch: model.branch,
      seller: model.seller,
      booking: model.booking,
      client: model.client,
      carInfo: model.carInfo,
      language: model.language,
      items: creditItems,
      fields:
          _extractFields(<String, dynamic>{'items': creditItems}, creditItems),
      type: model.type,
      module: model.module,
      kind: 'refundSalesInvoice',
      // Title follows the invoice language like every other title in the
      // template — _resolveTitle returns primary + Arabic regulatory alt.
      title: _resolveTitle('refundSalesInvoice', model.language.primary),
      orderNumber: model.orderNumber,
      dailyOrderNumber: model.dailyOrderNumber,
      bookingDate: model.bookingDate,
      date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      time: DateFormat('HH:mm:ss').format(DateTime.now()),
      invoiceNumber: model.invoiceNumber,
      currencyAr: model.currencyAr,
      currencyEn: model.currencyEn,
      paymentMethods: model.paymentMethods,
      policy: model.policy,
      qrImage: model.qrImage,
      hasOrders: false,
      calculatedPriceBeforeTax: totalBeforeTax,
      websiteUrl: model.websiteUrl,
    );

    final resolvedPaperWidthMm = paperWidthMm == null
        ? await _resolvePreferredPaperWidthMm()
        : _normalizePaperWidthMm(paperWidthMm);
    final html = _renderDocument(
      creditModel,
      paperWidthMm: resolvedPaperWidthMm,
    );

    final outputDir = await getTemporaryDirectory();
    final fileName =
        'credit_note_${invoiceId}_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final file = await FlutterHtmlToPdf.convertFromHtmlContent(
        content: html,
        configuration: PrintPdfConfiguration(
          targetDirectory: outputDir.path,
          targetName: fileName,
        ),
      );
      return file.path;
    } on MissingPluginException {
      return _writeHtmlFallback(
        outputDirPath: outputDir.path,
        fileName: fileName,
        html: html,
      );
    } catch (e) {
      final lower = e.toString().toLowerCase();
      if (lower.contains('missingpluginexception') ||
          lower.contains(
              'no implementation found for method converthtmltopdf')) {
        return _writeHtmlFallback(
          outputDirPath: outputDir.path,
          fileName: fileName,
          html: html,
        );
      }
      rethrow;
    }
  }

  Future<_PrintInvoiceModel> _buildModel(
    String invoiceId, {
    String? forcedKind,
  }) async {
    final invoiceResponse = await _loadInvoiceResponse(invoiceId);

    final envelope = _asMap(invoiceResponse['data']).isNotEmpty
        ? _asMap(invoiceResponse['data'])
        : _asMap(invoiceResponse);
    final invoice = _asMap(envelope['invoice']).isNotEmpty
        ? _asMap(envelope['invoice'])
        : envelope;

    final branch = _asMap(envelope['branch']).isNotEmpty
        ? _asMap(envelope['branch'])
        : _asMap(invoice['branch']);

    final seller = _asMap(branch['seller']).isNotEmpty
        ? _asMap(branch['seller'])
        : _asMap(envelope['seller']);

    final mutableBranch = Map<String, dynamic>.from(branch);
    final mutableSeller = Map<String, dynamic>.from(seller);

    final branchId = _asInt(mutableBranch['id']) ?? ApiConstants.branchId;

    final resolvedLogoUrl =
        await _resolveBranchLogoUrl(branchId, mutableBranch, mutableSeller);
    if (resolvedLogoUrl.isNotEmpty) {
      mutableBranch['logo'] = resolvedLogoUrl;
    }

    var client = _asMap(invoice['client']).isNotEmpty
        ? _asMap(invoice['client'])
        : _asMap(envelope['client']);

    var booking = _asMap(envelope['booking']).isNotEmpty
        ? _asMap(envelope['booking'])
        : _asMap(invoice['booking']);
    var order = _asMap(envelope['order']).isNotEmpty
        ? _asMap(envelope['order'])
        : _asMap(invoice['order']).isNotEmpty
            ? _asMap(invoice['order'])
            : _asMap(booking['order']);

    final bookingId = _firstNonEmptyString([
      _pick(booking, const ['id', 'booking_id']),
      _pick(invoice, const ['booking_id']),
      _pick(envelope, const ['booking_id']),
      _pick(order, const ['booking_id']),
      _pick(invoice, const ['order_id']),
      _pick(envelope, const ['order_id']),
      _pick(order, const ['order_id']),
    ]);

    // Backend bug workaround: the invoice serializer sometimes returns
    // `client.name="عميل عام"` and an empty mobile even when the booking
    // has a real customer attached. The booking endpoint exposes that
    // customer under `data.user.{name,mobile}`, so we always fetch the
    // booking when (a) we don't have it yet, or (b) the invoice client
    // looks like the placeholder. Mirrors `InvoiceWhatsAppDispatcher`.
    bool clientLooksPlaceholder() {
      if (client.isEmpty) return true;
      final name = _firstNonEmptyString([_pick(client, const ['name'])]) ?? '';
      final mobile = _firstNonEmptyString([
            _pick(client, const ['mobile', 'phone', 'phone_number']),
          ]) ??
          '';
      return name.isEmpty || name.trim() == 'عميل عام' || mobile.isEmpty;
    }

    final shouldFetchBooking = (booking.isEmpty || clientLooksPlaceholder()) &&
        bookingId != null &&
        bookingId.isNotEmpty;
    if (shouldFetchBooking) {
      try {
        final bookingResponse =
            await _orderService.getBookingDetails(bookingId);
        booking = _asMap(bookingResponse['data']).isNotEmpty
            ? _asMap(bookingResponse['data'])
            : _asMap(bookingResponse);
        if (order.isEmpty) {
          order = _asMap(booking['order']);
        }
      } catch (_) {
        // Keep invoice-only shape when booking details are not available.
      }
    }

    // After the booking is loaded, lift its real customer onto `client`
    // when the invoice payload only carried the "عميل عام" placeholder.
    if (clientLooksPlaceholder() && booking.isNotEmpty) {
      final bookingUser = _asMap(booking['user']).isNotEmpty
          ? _asMap(booking['user'])
          : _asMap(booking['customer']).isNotEmpty
              ? _asMap(booking['customer'])
              : _asMap(booking['userable']);
      if (bookingUser.isNotEmpty) {
        final resolved = <String, dynamic>{
          ...client,
          if ((_pick(bookingUser, const ['name', 'fullname']) ?? '')
              .toString()
              .trim()
              .isNotEmpty)
            'name': _pick(bookingUser, const ['name', 'fullname']),
          if ((_pick(bookingUser, const ['mobile', 'mobile_display', 'phone', 'phone_number']) ?? '')
              .toString()
              .trim()
              .isNotEmpty)
            'mobile': _pick(bookingUser, const ['mobile', 'mobile_display', 'phone', 'phone_number']),
        };
        client = resolved;
      }
    }

    final language = await _loadInvoiceLanguage();

    final type = _firstNonEmptyString([
          _pick(envelope, const ['type']),
          _pick(booking, const ['type']),
          _pick(invoice, const ['type']),
        ]) ??
        '';

    final module = _firstNonEmptyString([
          _pick(envelope, const ['module']),
          _pick(branch, const ['module']),
          _pick(invoice, const ['module']),
        ]) ??
        '';

    final items = _extractItems(invoice);
    final fields = _extractFields(invoice, items);
    final hasOrders =
        fields.contains('order') && items.any((item) => _truthy(item['order']));

    final kind = _resolveKind(
      forcedKind: forcedKind,
      envelope: envelope,
      invoice: invoice,
    );

    final resolvedTitle = _resolveTitle(kind, language.primary);
    final invoiceTitle = _asMap(envelope['invoice_title']).isNotEmpty
        ? _asMap(envelope['invoice_title'])
        : _asMap(invoice['invoice_title']);

    final rawDateTime = _firstNonEmptyString([
          _pick(invoice, const ['date', 'created_at']),
          _pick(envelope, const ['date', 'created_at']),
        ]) ??
        '';

    final date = _firstNonEmptyString([
          _pick(invoice, const ['date']),
        ]) ??
        _extractDate(rawDateTime);

    final time = _firstNonEmptyString([
          _pick(invoice, const ['time']),
        ]) ??
        _extractTime(rawDateTime);

    final bookingDate = _firstNonEmptyString([
          _pick(invoice, const ['booking_date']),
          _pick(booking, const ['date']),
        ]) ??
        '';

    final invoiceNumber = _firstNonEmptyString([
          _pick(invoice, const ['invoice_number']),
          _pick(invoice, const ['id']),
          invoiceId,
        ]) ??
        invoiceId;

    final orderId = _firstNonEmptyNonZeroString([
          _pick(order, const ['id', 'order_id']),
          _pick(invoice, const ['order_id']),
          _pick(envelope, const ['order_id']),
          _pick(booking, const ['order_id']),
        ]) ??
        '';

    final dailyOrderNumber = _firstNonEmptyNonZeroString([
          _pick(booking, const ['daily_order_number']),
          _pick(order, const ['order_number', 'daily_order_number']),
          _pick(envelope, const ['order_number']),
          _pick(invoice, const ['order_number']),
        ]) ??
        '';

    final orderNumber = _firstNonEmptyNonZeroString([
          orderId,
          _pick(envelope, const ['order_number']),
          _pick(order, const ['id']),
          _pick(invoice, const ['order_id']),
          _pick(booking, const ['order_id']),
        ]) ??
        '';

    final branchCurrency = _asMap(branch['currency']).isNotEmpty
        ? _asMap(branch['currency'])
        : _asMap(invoice['currency']);

    final currencyAr = _firstNonEmptyString([
          _pickPath(branchCurrency, 'ar'),
          _pick(branch, const ['currency_ar']),
          ApiConstants.currency,
        ]) ??
        ApiConstants.currency;

    final currencyEn = _firstNonEmptyString([
          _pickPath(branchCurrency, 'en'),
          _pick(branch, const ['currency_en']),
          ApiConstants.currency,
        ]) ??
        ApiConstants.currency;

    final paymentMethods = _resolvePaymentMethods(invoice);

    final carInfo = _asMap(envelope['car_info']).isNotEmpty
        ? _asMap(envelope['car_info'])
        : _asMap(invoice['car_info']);

    final policy = _firstNonEmptyString([
          _pick(envelope, const ['policy']),
          _pick(invoice, const ['policy']),
          _pick(branch, const ['policy']),
        ]) ??
        '';

    final qrImage = _firstNonEmptyString([
          _pick(envelope, const ['qr_image']),
          _pick(invoice, const ['qr_image', 'qr']),
        ]) ??
        '';

    final calculatedPriceBeforeTax = _calculatePriceBeforeTax(
      invoice: invoice,
      items: items,
    );

    const websiteUrl = ApiConstants.baseUrl;

    return _PrintInvoiceModel(
      envelope: envelope,
      invoice: invoice,
      branch: mutableBranch,
      seller: mutableSeller,
      booking: booking,
      client: client,
      carInfo: carInfo,
      language: language,
      items: items,
      fields: fields,
      type: type,
      module: module,
      kind: kind,
      title: invoiceTitle.isNotEmpty
          ? _InvoiceTitle(
              text: _firstNonEmptyString([invoiceTitle['text']]) ??
                  resolvedTitle.text,
              textAlt: _firstNonEmptyString([invoiceTitle['textAlt']]) ??
                  resolvedTitle.textAlt,
            )
          : resolvedTitle,
      orderNumber: orderNumber,
      dailyOrderNumber: dailyOrderNumber,
      bookingDate: bookingDate,
      date: date,
      time: time,
      invoiceNumber: invoiceNumber,
      currencyAr: currencyAr,
      currencyEn: currencyEn,
      paymentMethods: paymentMethods,
      policy: policy,
      qrImage: qrImage,
      hasOrders: hasOrders,
      calculatedPriceBeforeTax: calculatedPriceBeforeTax,
      websiteUrl: websiteUrl,
    );
  }

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  Future<String> _resolveBranchLogoUrl(
    int branchId,
    Map<String, dynamic> branch,
    Map<String, dynamic> seller,
  ) async {
    var logoUrl = _firstNonEmptyString([
          _pick(branch, const ['logo']),
          _pickPath(branch, 'seller.logo'),
          _pick(seller, const ['logo']),
        ]) ??
        '';
    if (logoUrl.isEmpty && branchId > 0) {
      logoUrl = await _branchService.getBranchLogoUrl(branchId);
    }
    if (logoUrl.isEmpty) return '';
    return _cacheLogoFile(logoUrl, branchId);
  }

  Future<String> _cacheLogoFile(String logoUrl, int branchId) async {
    try {
      final uri = Uri.tryParse(logoUrl);
      if (uri == null) return logoUrl;
      final dir = await getApplicationDocumentsDirectory();
      final extMatch =
          RegExp(r'\.(png|jpg|jpeg|webp|gif)$', caseSensitive: false)
              .firstMatch(uri.path);
      final ext = extMatch != null ? extMatch.group(0) : '.png';
      final file = File('${dir.path}/branch_logo_$branchId$ext');
      if (await file.exists()) {
        final length = await file.length();
        if (length > 0) return file.uri.toString();
      }
      final client = HttpClient();
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode == 200) {
        final bytes = await response.fold<List<int>>(
          <int>[],
          (prev, element) => prev..addAll(element),
        );
        await file.writeAsBytes(bytes, flush: true);
        return file.uri.toString();
      }
    } catch (e) {
      Log.w('pdf', 'logo cache failed', error: e);
    }
    return logoUrl;
  }

  Future<Map<String, dynamic>> _loadInvoiceResponse(String invoiceId) async {
    try {
      return await _orderService.getInvoice(invoiceId);
    } catch (_) {
      return await _orderService.getInvoiceHelper(invoiceId);
    }
  }

  Future<_InvoiceLanguage> _loadInvoiceLanguage() async {
    var primary = translationService.currentLanguageCode.trim().toLowerCase();
    var secondary = 'en';
    var allowSecondary = true;

    if (primary.isEmpty) {
      primary = 'ar';
    }

    try {
      final settings = await _branchService.getBranchSettings();
      final invoiceLanguage = _asMap(settings['invoice_language']).isNotEmpty
          ? _asMap(settings['invoice_language'])
          : _asMap(_pickPath(settings, 'data.invoice_language'));

      if (invoiceLanguage.isNotEmpty) {
        final apiPrimary = _normalizeLanguageCode(
            _firstNonEmptyString([invoiceLanguage['primary']]));
        final apiSecondary = _normalizeLanguageCode(
          _firstNonEmptyString([invoiceLanguage['secondary']]),
        );

        final allowRaw = invoiceLanguage['allow_secondary'];

        if (apiPrimary != null) {
          primary = apiPrimary;
        }
        if (apiSecondary != null) {
          secondary = apiSecondary;
        }
        if (allowRaw is bool) {
          allowSecondary = allowRaw;
        } else if (allowRaw != null) {
          final normalized = allowRaw.toString().trim().toLowerCase();
          allowSecondary =
              normalized == '1' || normalized == 'true' || normalized == 'yes';
        }
      }
    } catch (_) {
      // Keep locale fallback.
    }

    return _InvoiceLanguage(
      primary: _normalizeLanguageCode(primary) ?? 'ar',
      secondary: _normalizeLanguageCode(secondary) ?? 'en',
      allowSecondary: allowSecondary,
    );
  }

  Future<int> _resolvePreferredPaperWidthMm() async {
    try {
      await _printerRoleRegistry.initialize();
      final devices = await _deviceService.getDevices();

      DeviceConfig? selected;

      for (final device in devices) {
        if (!_isPhysicalPrinterDevice(device)) continue;
        final role = _printerRoleRegistry.resolveRole(device);
        if (role == PrinterRole.cashierReceipt) {
          selected = device;
          break;
        }
      }

      if (selected == null) {
        for (final device in devices) {
          if (_isPhysicalPrinterDevice(device)) {
            selected = device;
            break;
          }
        }
      }

      return _normalizePaperWidthMm(selected?.paperWidthMm);
    } catch (_) {
      return 58;
    }
  }

  bool _isPhysicalPrinterDevice(DeviceConfig device) {
    final type = device.type.trim().toLowerCase();
    return type == 'printer' && !device.id.startsWith('kitchen:');
  }



}
