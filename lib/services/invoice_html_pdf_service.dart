import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html_to_pdf_plus/flutter_html_to_pdf_plus.dart';
import 'package:hermosa_pos/utils/paper_width_utils.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';

import '../models.dart';
import '../models/receipt_data.dart';
import '../widgets/invoice_print_widget.dart';
import '../locator.dart';
import 'api/api_constants.dart';
import 'api/branch_service.dart';
import 'api/device_service.dart';
import 'api/order_service.dart';
import 'language_service.dart';
import 'printer_language_settings_service.dart';
import 'printer_role_registry.dart';
import 'receipt_addon_extractor.dart';

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
        // ignore: avoid_print
        print('⚠️ _dartNativePdfFromModel threw: $e\n$st');
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
      final captureWidth = 450.0;
      // Canvas height is intentionally generous — any single invoice
      // fits within ~3000px even with addons + many items. Empty
      // bottom whitespace is trimmed visually because the PDF page
      // size is computed from the same height; the customer just sees
      // a tall thermal-receipt-style PDF.
      final captureHeight = 3500.0;
      final captureSize = Size(captureWidth, captureHeight);

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
          data: MediaQueryData(
            size: captureSize,
            devicePixelRatio: 1.0,
            textScaler: const TextScaler.linear(1.0),
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
      final pdfWidthPt = captureWidth * 0.75;
      final pdfHeightPt = captureHeight * 0.75;
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(pdfWidthPt, pdfHeightPt),
          margin: pw.EdgeInsets.zero,
          build: (context) => pw.Image(image, fit: pw.BoxFit.fitWidth),
        ),
      );

      final pdfPath = '$outputDirPath/$fileName.pdf';
      final outFile = File(pdfPath);
      await outFile.writeAsBytes(await pdf.save(), flush: true);
      return pdfPath;
    } catch (e, st) {
      // ignore: avoid_print
      print('⚠️ _tryHtmlScreenshotPdf threw: $e\n$st');
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

    var totalInclVat = rawGrand;
    if (totalInclVat <= 0) {
      // Some legacy routes shove the grand total into `total`. Trust
      // it when it exceeds the items sum (i.e. it has tax baked in).
      if (rawTotal > itemsSum + 0.01) {
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

      return ReceiptItem(
        nameAr: pickStr(item, ['service_name', 'meal_name', 'name', 'item_name']),
        nameEn: pickStr(item, ['meal_name_en', 'name_en']),
        quantity: pickNum(item, ['quantity', 'qty', 'count']),
        unitPrice: pickNum(item, ['unit_price', 'meal_price', 'price']),
        total: pickNum(item, ['total', 'amount', 'price_after_tax']),
        addons: addons.isEmpty ? null : addons,
        discountAmount: pickNum(item, ['discount_amount', 'discount']) > 0
            ? pickNum(item, ['discount_amount', 'discount'])
            : null,
        discountPercentage: pickNum(item, ['discount_percentage']) > 0
            ? pickNum(item, ['discount_percentage'])
            : null,
        discountName: pickStr(item, ['discount_name']).isEmpty
            ? null
            : pickStr(item, ['discount_name']),
      );
    }).toList(growable: false);

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

    final qrImage = model.qrImage.startsWith('data:')
        ? model.qrImage.split(',').last
        : model.qrImage;

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
      zatcaQrImage: pickStr(invoice, ['zatca_qr_image']).isEmpty
          ? null
          : pickStr(invoice, ['zatca_qr_image']),
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
      // ignore: avoid_print
      print('⚠️ Failed to load bundled Arabic font ($assetPath): $e');
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
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
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
      print('⚠️ Logo cache failed: $e');
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

  String _renderDocument(
    _PrintInvoiceModel model, {
    required int paperWidthMm,
  }) {
    final b = StringBuffer();

    b.writeln('<!DOCTYPE html>');
    b.writeln('<html lang="ar" dir="rtl">');
    b.writeln('<head>');
    b.writeln('<meta charset="UTF-8"/>');
    b.writeln(
        '<meta name="viewport" content="width=device-width, initial-scale=1.0"/>');
    b.writeln(
        '<link href="https://fonts.googleapis.com/css2?family=Tajawal:wght@400;500;700&display=swap" rel="stylesheet">');
    b.writeln('<style>');
    b.writeln(_buildStyleSheet(paperWidthMm));
    b.writeln('</style>');
    b.writeln('</head>');
    b.writeln('<body>');
    b.writeln('<div class="hidden">');
    b.writeln('<div class="bill bill-container size-5cm">');
    b.writeln(_renderHeader(model));
    b.writeln(_renderBody(model));
    b.writeln(_renderFooter(model));
    b.writeln('</div>');
    b.writeln('</div>');
    b.writeln('</body>');
    b.writeln('</html>');

    return b.toString();
  }

  /// Renders the <header> block — exact replica of PrintInvoice.vue lines 6-188.
  String _renderHeader(_PrintInvoiceModel model) {
    final b = StringBuffer();

    // --- data ---
    final logoUrl = _firstNonEmptyString([
          _pick(model.branch, const ['logo']),
          _pickPath(model.branch, 'seller.logo'),
          _pick(model.seller, const ['logo']),
        ]) ??
        '';
    final sellerName = _firstNonEmptyString([
          _pick(model.branch, const ['seller_name']),
          _pick(model.seller, const ['name', 'seller_name']),
        ]) ??
        '';
    final address = _firstNonEmptyString([
          _pick(model.branch, const ['branch_address', 'address', 'location']),
          _pick(model.seller, const ['address', 'seller_address']),
          _pick(model.invoice, const ['branch_address', 'address']),
        ]) ??
        '';
    final mobile = _firstNonEmptyString([
          _pick(model.branch, const [
            'branch_mobile',
            'branch_phone',
            'mobile',
            'phone',
            'telephone',
            'mobile_number'
          ]),
          _pick(model.seller, const ['mobile', 'phone', 'telephone']),
          _pick(model.invoice, const ['branch_mobile', 'branch_phone', 'mobile']),
        ]) ??
        '';
    final telephone = _firstNonEmptyString([
          _pick(model.branch,
              const ['telephone', 'landline', 'second_mobile', 'phone']),
        ]) ??
        '';
    final taxNumber = _firstNonEmptyString([
          _pick(model.seller, const ['tax_number', 'vat_number']),
          _pick(model.branch, const ['tax_number', 'vat_number']),
          _pick(model.invoice, const ['tax_number', 'vat_number']),
        ]) ??
        '';
    final commercialNumber = _firstNonEmptyString([
          _pick(model.branch, const [
            'commercial_register_number',
            'commercial_register',
            'commercial_number',
            'cr_number'
          ]),
          _pick(model.seller, const [
            'commercial_register_number',
            'commercial_register',
            'commercial_number',
            'cr_number'
          ]),
          _pick(model.invoice, const [
            'commercial_register_number',
            'commercial_register',
            'commercial_number',
            'cr_number'
          ]),
        ]) ??
        '';
    final cashier = _asMap(_pick(model.invoice, const ['cashier']));
    final cashierName = _firstNonEmptyString([
          _pick(cashier, const ['fullname', 'name'])
        ]) ??
        '';
    final parentInvoice =
        _asMap(_pick(model.invoice, const ['parent_invoice']));
    final parentInvoiceNumber = _firstNonEmptyString([
          _pick(parentInvoice, const ['invoice_number'])
        ]) ??
        '';
    final bookingTypeExtra = _asMap(_pick(model.booking, const ['type_extra']));
    final tableName = _firstNonEmptyString([
          _pick(bookingTypeExtra, const ['table_name'])
        ]) ??
        '';
    final carNumber = _firstNonEmptyString([
          _pick(bookingTypeExtra, const ['car_number'])
        ]) ??
        '';
    final originalInvoiceNumber = _firstNonEmptyString([
          _pick(model.invoice, const ['original_invoice_number'])
        ]) ??
        '';

    // --- HTML (mirrors Vue template exactly) ---
    b.writeln('<header>');
    b.writeln('<div class="seller-info">');

    // Logo
    b.writeln('<div class="logo-container flex justify-center mb-4">');
    if (logoUrl.isNotEmpty) {
      b.writeln(
          '<img src="${_escapeHtml(logoUrl)}" alt="" class="w-24 h-24 object-contain"/>');
    }
    b.writeln('</div>');

    // Info
    b.writeln('<div class="info">');
    b.writeln('<p class="title font-bold">${_escapeHtml(sellerName)}</p>');
    b.writeln('<p>${_escapeHtml(address)}</p>');
    if (mobile.isNotEmpty) {
      b.writeln('<p class="mobile">${_escapeHtml(mobile)}</p>');
    }
    if (telephone.isNotEmpty) {
      b.writeln('<p class="mobile">${_escapeHtml(telephone)}</p>');
    }
    b.writeln('</div>');

    // Info-bottom
    b.writeln('<div class="info-bottom">');

    // Order number box
    b.writeln('<div class="flex justify-center my-2">');
    final orderBoxNumber = model.dailyOrderNumber.isNotEmpty
        ? model.dailyOrderNumber
        : model.orderNumber;
    if (model.type.isNotEmpty && orderBoxNumber.isNotEmpty) {
      b.writeln(
          '<div class="border-2 border-black px-4 py-1 text-lg font-bold">Order# ${_escapeHtml(orderBoxNumber)}</div>');
    }
    b.writeln('</div>');

    // Invoice number box
    b.writeln('<div class="flex justify-center my-2">');
    final rawInvoiceNumber = model.invoiceNumber.replaceAll('#', '').trim();
    final invoiceDisplay = rawInvoiceNumber.isNotEmpty &&
            !rawInvoiceNumber.toUpperCase().startsWith('IN-')
        ? 'IN-$rawInvoiceNumber'
        : rawInvoiceNumber;
    b.writeln(
        '<div class="border-2 border-black px-4 py-1 text-lg font-bold">${_escapeHtml(invoiceDisplay)}</div>');
    b.writeln('</div>');

    // Cashier
    if (cashierName.isNotEmpty) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'الكاشير', en: 'Cashier', hi: 'कैशियर', ur: 'کیشیئر', es: 'Cajero', tr: 'Kasiyer')}</p>');
      b.writeln('<p>${_escapeHtml(cashierName)}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'الكاشير', en: 'Cashier', hi: 'कैशियर', ur: 'کیشیئر', es: 'Cajero', tr: 'Kasiyer'))}</p>');
      b.writeln('</div>');
    }

    // Tax number
    b.writeln('<div class="info-bottom-item">');
    b.writeln('<p>${_mainLbl(model.language, ar: 'الرقم الضريبي', en: 'Tax Number', hi: 'कर संख्या', ur: 'ٹیکس نمبر', es: 'Número de Impuesto', tr: 'Vergi Numarası')}</p>');
    b.writeln('<p>${_escapeHtml(taxNumber)}</p>');
    b.writeln(
        '<p>${_escapeHtml(_altLabel(model.language, ar: 'الرقم الضريبي', en: 'Tax Number', hi: 'कर संख्या', ur: 'ٹیکس نمبر', es: 'Número de Impuesto', tr: 'Vergi Numarası'))}</p>');
    b.writeln('</div>');

    // Commercial number
    if (commercialNumber.isNotEmpty) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'رقم السجل التجاري', en: 'Commercial Register Number', hi: 'व्यावसायिक रजिस्टर संख्या', ur: 'تجارتی رجسٹر نمبر', tr: 'Ticari Sicil Numarası', es: 'Número de Registro Comercial')}</p>');
      b.writeln('<p>${_escapeHtml(commercialNumber)}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'رقم السجل التجاري', en: 'Commercial Register Number', hi: 'व्यावसायिक रजिस्टर संख्या', ur: 'تجارتی رجسٹر نمبر', tr: 'Ticari Sicil Numarası', es: 'Número de Registro Comercial'))}</p>');
      b.writeln('</div>');
    }

    // Date
    b.writeln('<div class="info-bottom-item">');
    b.writeln('<p>${_mainLbl(model.language, ar: 'التاريخ', en: 'Date', hi: 'दिनांक', ur: 'تاریخ', es: 'Fecha', tr: 'Tarih')}</p>');
    b.writeln('<p>${_escapeHtml(model.date)}</p>');
    b.writeln(
        '<p>${_escapeHtml(_altLabel(model.language, ar: 'التاريخ', en: 'Date', hi: 'दिनांक', ur: 'تاریخ', es: 'Fecha', tr: 'Tarih'))}</p>');
    b.writeln('</div>');

    // Time
    b.writeln('<div class="info-bottom-item">');
    b.writeln('<p>${_mainLbl(model.language, ar: 'الوقت', en: 'Time', hi: 'समय', ur: 'وقت', es: 'Hora', tr: 'Saat')}</p>');
    b.writeln('<p class="force-ltr">${_escapeHtml(model.time)}</p>');
    b.writeln(
        '<p>${_escapeHtml(_altLabel(model.language, ar: 'الوقت', en: 'Time', hi: 'समय', ur: 'وقت', es: 'Hora', tr: 'Saat'))}</p>');
    b.writeln('</div>');

    // Order number (restaurant only)
    if (model.type.isNotEmpty && model.type.contains('restaurant')) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'رقم الطلب', en: 'Order Number', hi: 'ऑर्डर संख्या', ur: 'آرڈر نمبر', es: 'Número de Pedido', tr: 'Sipariş Numarası')}</p>');
      b.writeln('<p class="force-ltr">${_escapeHtml(_firstNonEmptyString([
                _pick(model.booking, const ['daily_order_number']),
                model.dailyOrderNumber
              ]) ?? '')}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'رقم الطلب', en: 'Order Number', hi: 'ऑर्डर संख्या', ur: 'آرڈر نمبر', es: 'Número de Pedido', tr: 'Sipariş Numarası'))}</p>');
      b.writeln('</div>');
    }

    // Parent invoice
    if (parentInvoiceNumber.isNotEmpty) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'الفاتورة الأب', en: 'Parent Invoice', hi: 'पेरेंट इनवॉइस', ur: 'پیرنٹ انوائس', es: 'Factura Principal', tr: 'Ana Fatura')}</p>');
      b.writeln('<p class="force-ltr">${_escapeHtml(parentInvoiceNumber)}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'الفاتورة الأب', en: 'Parent Invoice', hi: 'पेरेंट इनवॉइस', ur: 'پیرنٹ انوائس', es: 'Factura Principal', tr: 'Ana Fatura'))}</p>');
      b.writeln('</div>');
    }

    // Order type
    if (model.type.isNotEmpty) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'نوع الطلب', en: 'Order Type', hi: 'ऑर्डर प्रकार', ur: 'آرڈر کی قسم', es: 'Tipo de Pedido', tr: 'Sipariş Türü')}</p>');
      b.writeln('<p>${_escapeHtml(_resolveOrderTypeLabel(model.type, model.language.primary))}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'نوع الطلب', en: 'Order Type', hi: 'ऑर्डर प्रकार', ur: 'آرڈر کی قسم', es: 'Tipo de Pedido', tr: 'Sipariş Türü'))}</p>');
      b.writeln('</div>');
    }

    // Table number (restaurant_internal)
    if (model.type == 'restaurant_internal' && tableName.isNotEmpty) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'رقم الطاوله', en: 'Table Number', hi: 'टेबल संख्या', ur: 'ٹیبل نمبر', es: 'Número de Mesa', tr: 'Masa Numarası')}</p>');
      b.writeln('<p>${_escapeHtml(tableName)}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'رقم الطاوله', en: 'Table Number', hi: 'टेबल संख्या', ur: 'ٹیبل نمبر', es: 'Número de Mesa', tr: 'Masa Numarası'))}</p>');
      b.writeln('</div>');
    }

    // Car number (restaurant_parking)
    if (model.type == 'restaurant_parking' && carNumber.isNotEmpty) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'رقم السياره', en: 'Car Number', hi: 'कार संख्या', ur: 'کار نمبر', es: 'Número de Auto', tr: 'Araç Numarası')}</p>');
      b.writeln('<p>${_escapeHtml(carNumber)}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'رقم السياره', en: 'Car Number', hi: 'कार संख्या', ur: 'کار نمبر', es: 'Número de Auto', tr: 'Araç Numarası'))}</p>');
      b.writeln('</div>');
    }

    // Original invoice number (refund)
    if (originalInvoiceNumber.isNotEmpty) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'رقم فاتورة الاسترجاع', en: 'Refund Invoice ID', hi: 'रिफंड इनवॉइस आईडी', ur: 'ریفنڈ انوائس آئی ڈی', es: 'ID de Factura de Reembolso', tr: 'İade Fatura Kimliği')}</p>');
      b.writeln(
          '<p class="force-ltr">${_escapeHtml(originalInvoiceNumber)}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'رقم فاتورة الاسترجاع', en: 'Refund Invoice ID', hi: 'रिफंड इनवॉइस आईडी', ur: 'ریفنڈ انوائس آئی ڈی', es: 'ID de Factura de Reembolso', tr: 'İade Fatura Kimliği'))}</p>');
      b.writeln('</div>');
    }

    // Booking date
    if (model.bookingDate.isNotEmpty) {
      b.writeln('<div class="info-bottom-item">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'تاريخ الحجز', en: 'Booking Date', hi: 'बुकिंग दिनांक', ur: 'بکنگ تاریخ', es: 'Fecha de Reserva', tr: 'Rezervasyon Tarihi')}</p>');
      b.writeln('<p>${_escapeHtml(model.bookingDate)}</p>');
      b.writeln(
          '<p>${_escapeHtml(_altLabel(model.language, ar: 'تاريخ الحجز', en: 'Booking Date', hi: 'बुकिंग दिनांक', ur: 'بکنگ تاریخ', es: 'Fecha de Reserva', tr: 'Rezervasyon Tarihi'))}</p>');
      b.writeln('</div>');
    }

    b.writeln('</div>'); // info-bottom
    b.writeln('</div>'); // seller-info
    b.writeln('</header>');

    return b.toString();
  }

  String _renderBody(_PrintInvoiceModel model) {
    final b = StringBuffer();

    b.writeln('<section>');

    b.writeln('<div class="invoice-title">');
    b.writeln('<p>${_escapeHtml(model.title.text)}</p>');
    b.writeln('<p>${_escapeHtml(model.title.textAlt)}</p>');
    b.writeln('</div>');

    b.writeln(_renderClientSection(model));
    b.writeln(_renderCarInfoSection(model));
    b.writeln(_renderItemsSection(model));
    b.writeln(_renderInvoiceDetailsSection(model));

    b.writeln('</section>');

    return b.toString();
  }

  String _renderClientSection(_PrintInvoiceModel model) {
    if (model.client.isEmpty) return '';

    final clientName = _firstNonEmptyString([
          _pick(model.client, const ['name'])
        ]) ??
        '';
    final clientMobile = _firstNonEmptyString([
          _pick(model.client, const ['mobile', 'phone']),
        ]) ??
        '';
    final clientTax = _firstNonEmptyString([
          _pick(model.client, const ['tax_number']),
        ]) ??
        '';
    final clientCommercial = _firstNonEmptyString([
          _pick(model.client, const ['commercial_register']),
        ]) ??
        '';

    final b = StringBuffer();

    b.writeln('<div>');
    b.writeln('<div class="client-info">');
    b.writeln('<div class="client-info-item">');
    b.writeln('<p class="font-bold">${_mainLbl(model.language, ar: 'اسم العميل', en: 'Client Name', hi: 'ग्राहक का नाम', ur: 'کلائنٹ کا نام', es: 'Nombre del Cliente', tr: 'Müşteri Adı')}</p>');
    b.writeln(
      '<p class="font-bold">${_escapeHtml(_altLabel(model.language, ar: 'اسم العميل', en: 'Client Name', hi: 'ग्राहक का नाम', ur: 'کلائنٹ کا نام', es: 'Nombre del Cliente', tr: 'Müşteri Adı'))}</p>',
    );
    b.writeln('<p>${_escapeHtml(clientName)}</p>');
    b.writeln('</div>');

    b.writeln('<div class="client-info-item">');
    b.writeln('<p class="font-bold">${_mainLbl(model.language, ar: 'جوال العميل', en: 'Client Phone', hi: 'ग्राहक फोन', ur: 'کلائنٹ فون', es: 'Teléfono del Cliente', tr: 'Müşteri Telefonu')}</p>');
    b.writeln(
      '<p class="font-bold">${_escapeHtml(_altLabel(model.language, ar: 'جوال العميل', en: 'Client Phone', hi: 'ग्राहक फोन', ur: 'کلائنٹ فون', es: 'Teléfono del Cliente', tr: 'Müşteri Telefonu'))}</p>',
    );
    b.writeln('<p style="direction: ltr">${_escapeHtml(clientMobile)}</p>');
    b.writeln('</div>');
    b.writeln('</div>');

    b.writeln('<div class="client-info mt-2">');

    if (clientTax.isNotEmpty) {
      b.writeln('<div class="client-info-item">');
      b.writeln('<p class="font-bold">${_mainLbl(model.language, ar: 'الرقم الضريبي', en: 'Tax number', hi: 'कर संख्या', ur: 'ٹیکس نمبر', es: 'Número de Impuesto', tr: 'Vergi Numarası')}</p>');
      b.writeln(
        '<p class="font-bold">${_escapeHtml(_altLabel(model.language, ar: 'الرقم الضريبي', en: 'Tax number', hi: 'कर संख्या', ur: 'ٹیکس نمبر', es: 'Número de Impuesto', tr: 'Vergi Numarası'))}</p>',
      );
      b.writeln('<p>${_escapeHtml(clientTax)}</p>');
      b.writeln('</div>');
    }

    if (clientCommercial.isNotEmpty) {
      b.writeln('<div class="client-info-item">');
      b.writeln('<p class="font-bold">${_mainLbl(model.language, ar: 'السجل التجاري', en: 'Commercial register', hi: 'व्यावसायिक रजिस्टर', ur: 'تجارتی رجسٹر', es: 'Registro Comercial', tr: 'Ticari Sicil')}</p>');
      b.writeln(
        '<p class="font-bold">${_escapeHtml(_altLabel(model.language, ar: 'السجل التجاري', en: 'Commercial register', hi: 'व्यावसायिक रजيس्टर', ur: 'تجارتی رجسٹر', es: 'Registro Comercial', tr: 'Ticari Sicil'))}</p>',
      );
      b.writeln(
          '<p style="direction: ltr">${_escapeHtml(clientCommercial)}</p>');
      b.writeln('</div>');
    }

    b.writeln('</div>');
    b.writeln('</div>');

    return b.toString();
  }

  String _renderCarInfoSection(_PrintInvoiceModel model) {
    if (!_isCarCare(model) || model.carInfo.isEmpty) return '';

    final b = StringBuffer();

    b.writeln('<div class="mt-2">');
    b.writeln(
      '<table class="car-info-table w-full border-collapse border border-gray-300 text-xs">',
    );
    b.writeln('<thead><tr>');
    b.writeln(
      '<th colspan="2" class="border border-gray-300 px-2 py-1 bg-gray-50 text-center font-bold text-sm">',
    );
    b.writeln(
        '${_mainLbl(model.language, ar: 'معلومات السيارة', en: 'Car Information', hi: 'कार की जानकारी', ur: 'کار کی معلومات', es: 'Información del Vehículo', tr: 'Araç Bilgileri')} ${_escapeHtml(_altLabel(model.language, ar: 'معلومات السيارة', en: 'Car Information', hi: 'कार की जानकारी', ur: 'کار کی معلومات', es: 'Información del Vehículo', tr: 'Araç Bilgileri'))}');
    b.writeln('</th></tr></thead>');

    b.writeln('<tbody>');
    b.writeln(_carInfoRow(
      model,
      ar: _mainLbl(model.language, ar: 'الماركة', en: 'Brand', hi: 'ब्रांड', ur: 'برانڈ', es: 'Marca', tr: 'Marka'),
      alt: _altLabel(
        model.language,
        ar: 'الماركة',
        hi: 'ब्रांड',
        ur: 'برانڈ',
        tr: 'Marka',
        en: 'Brand',
        es: 'Marca',
      ),
      value: _firstNonEmptyString([
            _pick(model.carInfo, const ['brand'])
          ]) ??
          '',
    ));
    b.writeln(_carInfoRow(
      model,
      ar: _mainLbl(model.language, ar: 'الموديل', en: 'Model', hi: 'मॉडल', ur: 'ماڈل', es: 'Modelo', tr: 'Model'),
      alt: _altLabel(
        model.language,
        ar: 'الموديل',
        hi: 'मॉडल',
        ur: 'ماڈل',
        tr: 'Model',
        en: 'Model',
        es: 'Modelo',
      ),
      value: _firstNonEmptyString([
            _pick(model.carInfo, const ['model'])
          ]) ??
          '',
    ));
    b.writeln(_carInfoRow(
      model,
      ar: _mainLbl(model.language, ar: 'رقم اللوحة', en: 'Plate Number', hi: 'प्लेट नंबर', ur: 'پلیٹ نمبر', es: 'Número de Placa', tr: 'Plaka Numarası'),
      alt: _altLabel(
        model.language,
        ar: 'رقم اللوحة',
        hi: 'प्लेट नंबर',
        ur: 'پلیٹ نمبر',
        tr: 'Plaka Numarası',
        en: 'Plate Number',
        es: 'Número de Placa',
      ),
      value: _firstNonEmptyString([
            _pick(model.carInfo, const ['plate'])
          ]) ??
          '',
    ));

    final year = _firstNonEmptyString([
          _pick(model.carInfo, const ['year'])
        ]) ??
        '';
    if (year.isNotEmpty) {
      b.writeln(_carInfoRow(
        model,
        ar: _mainLbl(model.language, ar: 'السنة', en: 'Year', hi: 'साल', ur: 'سال', es: 'Año', tr: 'Yıl'),
        alt: _altLabel(
          model.language,
          ar: 'السنة',
          hi: 'साल',
          ur: 'سال',
          tr: 'Yıl',
          en: 'Year',
          es: 'Año',
        ),
        value: year,
      ));
    }

    b.writeln('</tbody></table></div>');

    return b.toString();
  }

  String _carInfoRow(
    _PrintInvoiceModel model, {
    required String ar,
    required String alt,
    required String value,
  }) {
    return '''
<tr>
  <td class="border border-gray-300 px-2 py-1 font-bold text-sm">${_escapeHtml(ar)} ${_escapeHtml(alt)}</td>
  <td class="border border-gray-300 px-2 py-1 text-sm">${_escapeHtml(value)}</td>
</tr>
''';
  }

  String _renderItemsSection(_PrintInvoiceModel model) {
    if (model.items.isEmpty) return '';

    final showItemName = _isValidAttribute('item_name', model.fields);
    final showCode = _isValidAttribute('code', model.fields);
    final showExpiry = _isValidAttribute('expiry', model.fields);
    final showService = _isValidAttribute('service_name', model.fields) ||
        _isValidAttribute('meal_name', model.fields);
    final showEmployee = _isValidAttribute('employee_name', model.fields);
    final showQuantity = _isValidAttribute('quantity', model.fields);
    final showDiscount = _isValidAttribute('discount', model.fields);
    final showTotal = _isValidAttribute('total', model.fields);
    final showDate = _isValidAttribute('date', model.fields);
    final showTime = _isValidAttribute('time', model.fields);
    final showOrder =
        _isValidAttribute('order', model.fields) && model.hasOrders;

    final b = StringBuffer();

    b.writeln('<div class="invoice-items">');
    b.writeln('<table>');

    b.writeln('<thead><tr>');
    if (showItemName) b.writeln('<th>${_mainLbl(model.language, ar: 'الصنف', en: 'Item', hi: 'वस्तु', ur: 'آئٹم', es: 'Artículo', tr: 'Ürün')}</th>');
    if (showCode) b.writeln('<th>${_mainLbl(model.language, ar: 'كود الهدية', en: 'Gift Card Code', hi: 'गिफ्ट कार्ड कोड', ur: 'گفٹ کارڈ کوڈ', es: 'Código de Tarjeta Regalo', tr: 'Hediye Kartı Kodu')}</th>');
    if (showExpiry) b.writeln('<th>${_mainLbl(model.language, ar: 'تاريخ الانتهاء', en: 'Expiry Date', hi: 'समाप्ति तिथि', ur: 'ختم ہونے کی تاریخ', es: 'Fecha de Vencimiento', tr: 'Son Kullanma Tarihi')}</th>');
    if (showService) b.writeln('<th>${_mainLbl(model.language, ar: 'الخدمة', en: 'Service', hi: 'सेवा', ur: 'سروس', es: 'Servicio', tr: 'Hizmet')}</th>');
    if (showEmployee) b.writeln('<th>${_mainLbl(model.language, ar: 'الموظف/ة', en: 'Employee', hi: 'कर्मचारी', ur: 'ملازم', es: 'Empleado', tr: 'Çalışan')}</th>');
    if (showQuantity) b.writeln('<th>${_mainLbl(model.language, ar: 'الكمية', en: 'Quantity', hi: 'मात्रा', ur: 'مقدار', es: 'Cantidad', tr: 'Miktar')}</th>');
    if (showDiscount) b.writeln('<th>${_mainLbl(model.language, ar: 'الخصم', en: 'Discount', hi: 'छूट', ur: 'ڈسکاؤنٹ', es: 'Descuento', tr: 'İndirim')}</th>');
    if (showTotal) b.writeln('<th>${_mainLbl(model.language, ar: 'الاجمالي', en: 'Price', hi: 'कुल', ur: 'کل', es: 'Precio', tr: 'Toplam')}</th>');
    if (showDate) b.writeln('<th>${_mainLbl(model.language, ar: 'التاريخ', en: 'Date', hi: 'दिनांक', ur: 'تاریخ', es: 'Fecha', tr: 'Tarih')}</th>');
    if (showTime) b.writeln('<th>${_mainLbl(model.language, ar: 'الوقت', en: 'Time', hi: 'समय', ur: 'وقت', es: 'Hora', tr: 'Saat')}</th>');
    if (showOrder) b.writeln('<th>${_mainLbl(model.language, ar: 'الدور', en: 'Order', hi: 'क्रम', ur: 'آرڈر', es: 'Orden', tr: 'Sıra')}</th>');
    b.writeln('</tr></thead>');

    b.writeln('<thead><tr>');
    if (showItemName) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'الصنف', hi: 'वस्तु', ur: 'آئٹم', tr: 'Ürün', en: 'Item', es: 'Artículo'))}</th>',
      );
    }
    if (showCode) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'كود الهدية', hi: 'गिफ्ट कार्ड कोड', ur: 'گفٹ کارڈ کوڈ', tr: 'Hediye Kartı Kodu', en: 'Gift Card Code', es: 'Código de Tarjeta Regalo'))}</th>',
      );
    }
    if (showExpiry) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'تاريخ الانتهاء', hi: 'समाप्ति तिथि', ur: 'ختم ہونے کی تاریخ', tr: 'Son Kullanma Tarihi', en: 'Expiry Date', es: 'Fecha de Vencimiento'))}</th>',
      );
    }
    if (showService) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'الخدمة', hi: 'सेवा', ur: 'سروس', tr: 'Hizmet', en: 'Service', es: 'Servicio'))}</th>',
      );
    }
    if (showEmployee) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'الموظف/ة', hi: 'कर्मचारी', ur: 'ملازم', tr: 'Çalışan', en: 'Employee', es: 'Empleado'))}</th>',
      );
    }
    if (showQuantity) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'الكمية', hi: 'मात्रा', ur: 'مقدار', tr: 'Miktar', en: 'Quantity', es: 'Cantidad'))}</th>',
      );
    }
    if (showDiscount) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'الخصم', hi: 'छूट', ur: 'ڈسکاؤنٹ', tr: 'İndirim', en: 'Discount', es: 'Descuento'))}</th>',
      );
    }
    if (showTotal) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'الاجمالي', hi: 'कुल', ur: 'کل', tr: 'Toplam', en: 'Price', es: 'Precio'))}</th>',
      );
    }
    if (showDate) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'التاريخ', hi: 'दिनांक', ur: 'تاریخ', tr: 'Tarih', en: 'Date', es: 'Fecha'))}</th>',
      );
    }
    if (showTime) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'الوقت', hi: 'समय', ur: 'وقت', tr: 'Saat', en: 'Time', es: 'Hora'))}</th>',
      );
    }
    if (showOrder) {
      b.writeln(
        '<th>${_escapeHtml(_altLabel(model.language, ar: 'الدور', hi: 'क्रम', ur: 'آرڈر', tr: 'Sıra', en: 'Order', es: 'Orden'))}</th>',
      );
    }
    b.writeln('</tr></thead>');

    b.writeln('<tbody>');

    for (var index = 0; index < model.items.length; index++) {
      final item = model.items[index];
      final row = StringBuffer();

      for (final entry in item.entries) {
        final key = entry.key.toString();
        if (!_isValidAttribute(key, model.fields)) continue;
        if ((key == 'order' || key == 'addons') && !model.hasOrders) continue;

        final classes = <String>[];
        if (const ['quantity', 'total', 'order'].contains(key)) {
          classes.add('text-center');
        }
        if (const ['date', 'time', 'order', 'code', 'expiry'].contains(key)) {
          classes.addAll(const ['whitespace-nowrap', 'force-ltr']);
        }

        row.write('<td');
        if (classes.isNotEmpty) {
          row.write(' class="${classes.join(' ')}"');
        }
        row.write('>');

        final addons = _extractItemAddonsForRender(item);
        final combos = _asMapList(item['combos']);
        final canRenderAddons = _isRestaurant(model) &&
            key == 'item_name' &&
            (addons.isNotEmpty || combos.isNotEmpty);

        if (canRenderAddons) {
          row.write('<table class="addons-table">');
          row.write('<tr><td>');
          row.write('<div class="flex justify-between">');
          row.write('<p>${_escapeHtml(_displayValue(entry.value))}</p>');
          row.write('<p>${_escapeHtml(_displayValue(_pick(item, const [
                'meal_price'
              ])))}</p>');
          row.write('</div>');

          for (final combo in combos) {
            final comboQty = _displayValue(_pick(combo, const ['quantity']));
            final comboName = _displayValue(_pick(combo, const ['name']));
            row.write(
              '<p class="addon-size">${_escapeHtml(comboQty)} X ${_escapeHtml(comboName)}</p>',
            );
          }

          row.write('</td></tr>');

          for (final addon in addons) {
            // `attribute` and `option` are language-keyed maps (e.g.
            // `{ar: "نوع الطهي", en: "Cooking type"}`). Resolve them through
            // the invoice language picker so the PDF/HTML invoice matches
            // the cashier's chosen primary/secondary language.
            final attributePrimary = _localizedValue(
                _pick(addon, const ['attribute']), model.language.primary);
            final optionPrimary = _localizedValue(
                _pick(addon, const ['option']), model.language.primary);
            final attributeSecondary = model.language.allowSecondary &&
                    model.language.secondary != model.language.primary
                ? _localizedValue(
                    _pick(addon, const ['attribute']), model.language.secondary)
                : '';
            final optionSecondary = model.language.allowSecondary &&
                    model.language.secondary != model.language.primary
                ? _localizedValue(
                    _pick(addon, const ['option']), model.language.secondary)
                : '';
            final total = _displayValue(_pick(addon, const ['total']));
            final primaryLabel = '$attributePrimary $optionPrimary'.trim();
            final secondaryLabel = '$attributeSecondary $optionSecondary'.trim();
            row.write('<tr>');
            row.write(
                '<td class="addon-item addon-size">${_escapeHtml(primaryLabel)}');
            if (secondaryLabel.isNotEmpty && secondaryLabel != primaryLabel) {
              row.write(
                  '<br><span class="addon-size-alt">${_escapeHtml(secondaryLabel)}</span>');
            }
            row.write('</td>');
            row.write(
                '<td class="addon-size text-center">${_escapeHtml(total)}</td>');
            row.write('</tr>');
          }

          row.write('</table>');
        } else {
          final value = _resolveItemTableValue(key, item, entry.value);
          row.write('<p>${_escapeHtml(value)}</p>');
        }

        row.write('</td>');
      }

      if (row.isNotEmpty) {
        b.writeln('<tr>${row.toString()}</tr>');
      }
    }

    b.writeln('</tbody>');
    b.writeln('</table>');
    b.writeln('</div>');

    return b.toString();
  }

  String _resolveItemTableValue(
    String key,
    Map<String, dynamic> item,
    dynamic fallback,
  ) {
    dynamic value;
    if (key == 'total') {
      value = _pick(item, const ['total', 'total_tax']);
      value ??= 0;
    } else if (key == 'price') {
      value = _pick(item, const ['price', 'total']);
      value ??= fallback;
    } else if (key == 'service_name' || key == 'meal_name') {
      value = _pick(item, const ['meal_name', 'service_name']);
      value ??= fallback;
    } else {
      value = fallback;
    }

    return _displayValue(value);
  }

  String _renderInvoiceDetailsSection(_PrintInvoiceModel model) {
    final invoice = model.invoice;
    final b = StringBuffer();

    b.writeln('<div class="invoice-details">');

    if (_truthy(_pick(invoice, const ['pre_paid']))) {
      b.writeln(_invoiceAmountRow(
        model,
        value: _displayValue(_pick(invoice, const ['pre_paid'])),
        titleAr: _mainLbl(model.language, ar: 'الدفع المسبق', en: 'Pre Paid Amount', hi: 'पूर्व भुगतान राशि', ur: 'پری پیڈ رقم', es: 'Monto Prepagado', tr: 'Ön Ödeme Tutarı'),
        titleAlt: _altLabel(
          model.language,
          ar: 'الدفع المسبق',
          hi: 'पूर्व भुगतान राशि',
          ur: 'پری پیڈ رقم',
          tr: 'Ön Ödeme Tutarı',
          en: 'Pre Paid Amount',
          es: 'Monto Prepagado',
        ),
      ));
    }

    if (_truthy(_pick(invoice, const ['price']))) {
      b.writeln(_invoiceAmountRow(
        model,
        value: model.calculatedPriceBeforeTax,
        titleAr: _mainLbl(model.language, ar: 'الاجمالي قبل الضريبة', en: 'Total Before Tax', hi: 'कर से पहले कुल', ur: 'ٹیکس سے پہلے کل', es: 'Total antes de Impuesto', tr: 'Vergi Öncesi Toplam'),
        titleAlt: _altLabel(
          model.language,
          ar: 'الاجمالي قبل الضريبة',
          hi: 'कर से पहले कुल',
          ur: 'ٹیکس سے پہلے کل',
          tr: 'Vergi Öncesi Toplam',
          en: 'Total Before Tax',
          es: 'Total antes de Impuesto',
        ),
      ));
    }

    if (_truthy(_pick(invoice, const ['discount']))) {
      b.writeln(_invoiceAmountRow(
        model,
        value: _displayValue(_pick(invoice, const ['discount'])),
        titleAr: _mainLbl(model.language, ar: 'قيمة الخصم', en: 'Discount Amount', hi: 'छूट राशि', ur: 'ڈسکاؤنٹ رقم', es: 'Monto de Descuento', tr: 'İndirim Tutarı'),
        titleAlt: _altLabel(
          model.language,
          ar: 'قيمة الخصم',
          hi: 'छूट राशि',
          ur: 'ڈسکاؤنٹ رقم',
          tr: 'İndirim Tutarı',
          en: 'Discount Amount',
          es: 'Monto de Descuento',
        ),
      ));
    }

    if (!_truthy(_pick(invoice, const ['discount'])) &&
        _truthy(_pick(invoice, const ['total_items_discount']))) {
      b.writeln(_invoiceAmountRow(
        model,
        value: _displayValue(_pick(invoice, const ['total_items_discount'])),
        titleAr: _mainLbl(model.language, ar: 'إجمالي خصم الأصناف', en: 'Total Items Discount', hi: 'कुल आइटम छूट', ur: 'کل آئٹم ڈسکاؤنٹ', es: 'Descuento Total de Artículos', tr: 'Toplam Ürün İndirimi'),
        titleAlt: _altLabel(
          model.language,
          ar: 'إجمالي خصم الأصناف',
          hi: 'कुल आइटम छूट',
          ur: 'کل آئٹم ڈسکاؤنٹ',
          tr: 'Toplam Ürün İndirimi',
          en: 'Total Items Discount',
          es: 'Descuento Total de Artículos',
        ),
      ));
    }

    if (_truthy(_pick(invoice, const ['price_after_discount']))) {
      b.writeln(_invoiceAmountRow(
        model,
        value: _displayValue(_pick(invoice, const ['price_after_discount'])),
        titleAr: _mainLbl(model.language, ar: 'الاجمالي بعد الخصم', en: 'Total After Discount', hi: 'छूट के बाद कुल', ur: 'ڈسکاؤنٹ کے بعد کل', es: 'Total después del Descuento', tr: 'İndirim Sonrası Toplam'),
        titleAlt: _altLabel(
          model.language,
          ar: 'الاجمالي بعد الخصم',
          hi: 'छूट के बाद कुल',
          ur: 'ڈسکاؤنٹ کے بعد کل',
          tr: 'İndirim Sonrası Toplam',
          en: 'Total After Discount',
          es: 'Total después del Descuento',
        ),
      ));
    }

    if (_truthy(_pick(invoice, const ['tax']))) {
      b.writeln(_invoiceAmountRow(
        model,
        value: _displayValue(_pick(invoice, const ['tax'])),
        titleAr: _mainLbl(model.language, ar: 'قيمة الضريبة', en: 'Tax Amount', hi: 'कर राशि', ur: 'ٹیکس رقم', es: 'Monto de Impuesto', tr: 'Vergi Tutarı'),
        titleAlt: _altLabel(
          model.language,
          ar: 'قيمة الضريبة',
          hi: 'कर राशि',
          ur: 'ٹیکس رقم',
          tr: 'Vergi Tutarı',
          en: 'Tax Amount',
          es: 'Monto de Impuesto',
        ),
      ));
    }

    if (_truthy(_pick(invoice, const ['total']))) {
      b.writeln(_invoiceAmountRow(
        model,
        value: _displayValue(_pick(invoice, const ['total'])),
        titleAr: _mainLbl(model.language, ar: 'الاجمالي بعد الضريبة', en: 'Total After Tax', hi: 'कर के बाद कुल', ur: 'ٹیکس کے بعد کل', es: 'Total con Impuesto', tr: 'Vergi Sonrası Toplam'),
        titleAlt: _altLabel(
          model.language,
          ar: 'الاجمالي بعد الضريبة',
          hi: 'कर के बाद कुल',
          ur: 'ٹیکس کے بعد کل',
          tr: 'Vergi Sonrası Toplam',
          en: 'Total After Tax',
          es: 'Total con Impuesto',
        ),
      ));
    }

    if (_truthy(model.paymentMethods)) {
      b.writeln(
          '<div class="invoice-details-item flex justify-between items-center">');
      b.writeln('<div class="w-7/12">');
      b.writeln('<p class="price">${_escapeHtml(model.paymentMethods)}</p>');
      b.writeln('</div>');
      b.writeln('<div class="invoice-item-title text-left">');
      b.writeln('<p>${_mainLbl(model.language, ar: 'طرق الدفع', en: 'Payment Methods', hi: 'भुगतान विधियां', ur: 'ادائیگی کے طریقے', es: 'Métodos de Pago', tr: 'Ödeme Yöntemleri')}</p>');
      b.writeln(
        '<p>${_escapeHtml(_altLabel(model.language, ar: 'طرق الدفع', hi: 'भुगतान विधियां', ur: 'ادائیگی کے طریقے', tr: 'Ödeme Yöntemleri', en: 'Payment Methods', es: 'Métodos de Pago'))}</p>',
      );
      b.writeln('</div>');
      b.writeln('</div>');
    }

    b.writeln('</div>');
    return b.toString();
  }

  String _invoiceAmountRow(
    _PrintInvoiceModel model, {
    required dynamic value,
    required String titleAr,
    required String titleAlt,
  }) {
    return '''
<div class="invoice-details-item flex justify-between items-center">
  <div class="flex items-center text-right">
    <div class="currency-area">
      <p>${_escapeHtml(model.currencyAr)}</p>
      <p>${_escapeHtml(model.currencyEn)}</p>
    </div>
    <p class="price">${_escapeHtml(_displayValue(value))}</p>
  </div>
  <div class="invoice-item-title text-left">
    <p>${_escapeHtml(titleAr)}</p>
    <p>${_escapeHtml(titleAlt)}</p>
  </div>
</div>
''';
  }

  String _renderFooter(_PrintInvoiceModel model) {
    final b = StringBuffer();

    b.writeln('<footer class="invoice-details">');
    b.writeln('<div class="flex justify-center">');
    if (model.qrImage.isNotEmpty) {
      b.writeln('<img src="${_escapeHtml(model.qrImage)}"/>');
    }
    b.writeln('</div>');

    b.writeln('<div class="invoice-details-item">');
    b.writeln(
        '<p class="invoice-title" style="border-bottom: 0">سياسة الاسترجاع</p>');
    b.writeln(
      '<div style="white-space: pre-wrap" class="pb-2">${_renderPolicyHtml(model.policy)}</div>',
    );
    b.writeln('</div>');

    b.writeln('<div class="mt-2">');
    b.writeln('<p>${_mainLbl(model.language, ar: 'شكرا لثقتكم بنا', en: 'Thank you for trusting us', hi: 'हम पर विश्वास करने के लिए धन्यवाद', ur: 'ہم پر اعتماد کرنے کا شکریہ', es: 'Gracias por confiar en nosotros', tr: 'Bize güveniniz için teşekkür ederiz')}</p>');
    b.writeln(
      '<p>${_escapeHtml(_altLabel(model.language, ar: 'شكرا لثقتكم بنا', hi: 'हम पर विश्वास करने के लिए धन्यवाद', ur: 'ہم پر اعتماد کرنے کا شکریہ', tr: 'Bize güveniniz için teşekkür ederiz', en: 'Thank you for trusting us', es: 'Gracias por confiar en nosotros'))}</p>',
    );

    b.writeln('<p>${_mainLbl(model.language, ar: 'برنامج هيرموسا المحاسبي المتكامل', en: 'Integrated Accounting Program Hermosa', hi: 'एकीकृत लेखांकन कार्यक्रम हर्मोसा', ur: 'ہرموسا انٹیگریٹڈ اکاؤنٹنگ پروگرام', es: 'Programa de Contabilidad Integrada Hermosa', tr: 'Entegre Muhasebe Programı Hermosa')}</p>');
    b.writeln(
      '<p>${_escapeHtml(_altLabel(model.language, ar: 'برنامج هيرموسا المحاسبي المتكامل', hi: 'एकीकृत लेखांकन कार्यक्रम हर्मोसा', ur: 'ہرموسا انٹیگریٹڈ اکاؤنٹنگ پروگرام', tr: 'Entegre Muhasebe Programı Hermosa', en: 'Integrated Accounting Program Hermosa', es: 'Programa de Contabilidad Integrada Hermosa'))}</p>',
    );

    b.writeln('<p>${_escapeHtml(model.websiteUrl)}</p>');
    b.writeln('</div>');

    b.writeln('</footer>');

    return b.toString();
  }

  String _renderPolicyHtml(String policy) {
    final trimmed = policy.trim();
    if (trimmed.isEmpty) return '';

    final likelyHtml = trimmed.contains('<') && trimmed.contains('>');
    if (likelyHtml) return trimmed;

    return _escapeHtml(trimmed).replaceAll('\n', '<br/>');
  }

  String _resolveOrderTypeLabel(String type, String primaryLang) {
    final normalized = type.trim().toLowerCase();
    final pri = primaryLang.trim().toLowerCase();
    String pick({required String ar, required String en, String? hi, String? ur, String? es, String? tr}) {
      switch (pri) {
        case 'en': return en;
        case 'hi': return hi ?? en;
        case 'ur': return ur ?? en;
        case 'es': return es ?? en;
        case 'tr': return tr ?? en;
        default: return ar;
      }
    }
    switch (normalized == 'services' ? 'restaurant_services' : normalized) {
      case 'restaurant_services':
      case 'service':
        return pick(ar: 'محلي', en: 'Local', hi: 'स्थानीय', ur: 'مقامی', es: 'Local', tr: 'Yerel');
      case 'restaurant_internal':
      case 'restaurant_table':
      case 'table':
        return pick(ar: 'داخل المطعم', en: 'Dine In', hi: 'डाइन इन', ur: 'اندرونی', es: 'Comer Aquí', tr: 'İçeride');
      case 'restaurant_delivery':
      case 'delivery':
      case 'home_delivery':
        return pick(ar: 'توصيل', en: 'Delivery', hi: 'डिलीवरी', ur: 'ڈیلیوری', es: 'Entrega', tr: 'Teslimat');
      case 'restaurant_pickup':
      case 'pickup':
      case 'takeaway':
        return pick(ar: 'استلام من الفرع', en: 'Pickup', hi: 'पिकअप', ur: 'پک اپ', es: 'Recogida', tr: 'Teslim Alma');
      case 'restaurant_parking':
      case 'cars':
      case 'car':
        return pick(ar: 'سيارة', en: 'Drive-through', hi: 'ड्राइव-थ्रू', ur: 'ڈرائیو تھرو', es: 'Auto-servicio', tr: 'Araç Servisi');
      case 'hungerstation_delivery':
      case 'hunger_station_delivery':
        return pick(ar: 'هنقر ستيشن (توصيل)', en: 'HungerStation (Delivery)', hi: 'हंगरस्टेशन (डिलीवरी)', ur: 'ہنگر سٹیشن (ڈیلیوری)', es: 'HungerStation (Entrega)', tr: 'HungerStation (Teslimat)');
      case 'hungerstation_pickup':
      case 'hunger_station_pickup':
        return pick(ar: 'هنقر ستيشن (استلام)', en: 'HungerStation (Pickup)', hi: 'हंगरस्टेशन (पिकअप)', ur: 'ہنگر سٹیشن (پک اپ)', es: 'HungerStation (Recogida)', tr: 'HungerStation (Teslim Alma)');
      case 'talabat_delivery':
        return pick(ar: 'طلبات (توصيل)', en: 'Talabat (Delivery)', hi: 'तलबात (डिलीवरी)', ur: 'طلبات (ڈیلیوری)', es: 'Talabat (Entrega)', tr: 'Talabat (Teslimat)');
      case 'talabat_pickup':
        return pick(ar: 'طلبات (استلام)', en: 'Talabat (Pickup)', hi: 'तलबात (पिकअप)', ur: 'طلبات (پک اپ)', es: 'Talabat (Recogida)', tr: 'Talabat (Teslim Alma)');
      case 'jahez_delivery':
      case 'gahez_delivery':
        return pick(ar: 'جاهز (توصيل)', en: 'Jahez (Delivery)', hi: 'जाहेज़ (डिलीवरी)', ur: 'جاہز (ڈیلیوری)', es: 'Jahez (Entrega)', tr: 'Jahez (Teslimat)');
      case 'jahez_pickup':
      case 'gahez_pickup':
        return pick(ar: 'جاهز (استلام)', en: 'Jahez (Pickup)', hi: 'जाहेज़ (पिकअप)', ur: 'جاہز (پک اپ)', es: 'Jahez (Recogida)', tr: 'Jahez (Teslim Alma)');
      default:
        return normalized.isEmpty ? '' : normalized;
    }
  }

  /// Resolves the invoice title into `(text, textAlt)` — `text` is the
  /// localized primary-language title, `textAlt` is the universally
  /// recognizable Arabic subtitle kept on every receipt for regulatory
  /// consistency.
  ///
  /// Every kind now resolves across all six supported languages
  /// (ar/en/es/tr/hi/ur) through a single lookup table so adding a new
  /// language or invoice kind stays a one-line change instead of another
  /// copy-pasted `switch` arm.
  _InvoiceTitle _resolveTitle(String kind, String primaryLanguage) {
    final primary = primaryLanguage.trim().toLowerCase();

    String pickTitle({
      required String ar,
      required String en,
      String? hi,
      String? ur,
      String? tr,
      String? es,
    }) {
      switch (primary) {
        case 'ar':
          return ar;
        case 'hi':
          return hi ?? en;
        case 'ur':
          return ur ?? en;
        case 'tr':
          return tr ?? en;
        case 'es':
          return es ?? en;
        case 'en':
        default:
          return en;
      }
    }

    switch (kind) {
      case 'simplified':
      case 'simplified_b2b':
        return _InvoiceTitle(
          text: pickTitle(
            ar: 'فاتورة ضريبية مبسطة',
            en: 'Simplified Tax Invoice',
            hi: kind == 'simplified' ? 'सरलीकृत कर इनवॉइस' : 'सरल कर इनवॉइस',
            ur: 'سادہ ٹیکس انوائس',
            tr: 'Basitleştirilmiş Vergi Faturası',
            es: 'Factura Fiscal Simplificada',
          ),
          textAlt: primary == 'ar'
              ? 'Simplified Tax Invoice'
              : 'فاتورة ضريبية مبسطة',
        );

      case 'refundSalesInvoice':
        return _InvoiceTitle(
          text: pickTitle(
            ar: 'إشعار دائن',
            en: 'Credit Note',
            hi: 'क्रेडिट नोट',
            ur: 'کریڈٹ نوٹ',
            tr: 'Alacak Dekontu',
            es: 'Nota de Crédito',
          ),
          textAlt: primary == 'ar' ? 'Credit Note' : 'إشعار دائن',
        );

      case 'debitNote':
      case 'debitNote_b2b':
        return _InvoiceTitle(
          text: pickTitle(
            ar: 'إشعار مدين',
            en: 'Debit Note',
            hi: 'डेबिट नोट',
            ur: 'ڈیبٹ نوٹ',
            tr: 'Borç Dekontu',
            es: 'Nota de Débito',
          ),
          textAlt: primary == 'ar' ? 'Debit Note' : 'إشعار مدين',
        );

      case 'deposit':
        return _InvoiceTitle(
          text: pickTitle(
            ar: 'فاتورة العربون',
            en: 'Deposit Invoice',
            hi: 'जमा चालान',
            ur: 'ڈپازٹ انوائس',
            tr: 'Depozito Faturası',
            es: 'Factura de Depósito',
          ),
          textAlt: primary == 'ar' ? 'Deposit Invoice' : 'فاتورة العربون',
        );

      case 'depositRefund':
        return _InvoiceTitle(
          text: pickTitle(
            ar: 'إشعار دائن - عربون',
            en: 'Deposit Credit Note',
            hi: 'जमा क्रेडिट नोट',
            ur: 'ڈپازٹ کریڈٹ نوٹ',
            tr: 'Depozito Alacak Dekontu',
            es: 'Nota de Crédito - Depósito',
          ),
          textAlt: primary == 'ar'
              ? 'Deposit Credit Note'
              : 'إشعار دائن - عربون',
        );

      case 'usedProducts':
        return _InvoiceTitle(
          text: pickTitle(
            ar: 'فاتورة استخدام منتجات',
            en: 'Used Products Invoice',
            hi: 'उपयोग किए गए उत्पाद इनवॉइस',
            ur: 'استعمال شدہ مصنوعات انوائس',
            tr: 'Kullanılmış Ürünler Faturası',
            es: 'Factura de Productos Usados',
          ),
          textAlt: primary == 'ar'
              ? 'Used Products Invoice'
              : 'فاتورة استخدام منتجات',
        );

      case 'sessions':
        return _InvoiceTitle(
          text: pickTitle(
            ar: 'حجوزات الجلسات',
            en: 'Sessions Bookings',
            hi: 'सत्र बुकिंग',
            ur: 'سیشن بکنگ',
            tr: 'Oturum Rezervasyonları',
            es: 'Reservas de Sesiones',
          ),
          textAlt: primary == 'ar'
              ? 'Sessions Bookings'
              : 'حجوزات الجلسات',
        );

      default:
        return _InvoiceTitle(
          text: pickTitle(
            ar: 'فاتورة ضريبية مبسطة',
            en: 'Simplified Tax Invoice',
            hi: 'सरलीकृत कर इनवॉइस',
            ur: 'سادہ ٹیکس انوائس',
            tr: 'Basitleştirilmiş Vergi Faturası',
            es: 'Factura Fiscal Simplificada',
          ),
          textAlt: primary == 'ar'
              ? 'Simplified Tax Invoice'
              : 'الفاتورة الضريبية المبسطة',
        );
    }
  }

  String _resolveKind({
    required String? forcedKind,
    required Map<String, dynamic> envelope,
    required Map<String, dynamic> invoice,
  }) {
    const allowed = <String>{
      'simplified',
      'debitNote',
      'simplified_b2b',
      'debitNote_b2b',
      'refundSalesInvoice',
      'deposit',
      'depositRefund',
      'usedProducts',
      'sessions',
    };

    final candidate = _firstNonEmptyString([
      forcedKind,
      _pick(invoice, const ['kind', 'invoice_kind']),
      _pick(envelope, const ['kind', 'invoice_kind']),
    ]);

    if (candidate != null && allowed.contains(candidate)) {
      return candidate;
    }

    final hasOriginalInvoice = _firstNonEmptyString([
          _pick(invoice, const ['original_invoice_number']),
        ]) !=
        null;

    if (hasOriginalInvoice) {
      return 'refundSalesInvoice';
    }

    return 'simplified';
  }

  bool _isValidAttribute(String key, List<String> fields) {
    if (key == 'addons') return false;
    return fields.contains(key);
  }

  bool _isRestaurant(_PrintInvoiceModel model) {
    final module = model.module.trim().toLowerCase();
    final type = model.type.trim().toLowerCase();

    if (module.contains('restaurant')) return true;
    if (type.contains('restaurant')) return true;
    return false;
  }

  bool _isCarCare(_PrintInvoiceModel model) {
    if (model.carInfo.isEmpty) return false;
    final module = model.module.trim().toLowerCase();
    if (module.contains('car')) return true;
    final envelopeCarInfo = _asMap(_pick(model.envelope, const ['car_info']));
    if (envelopeCarInfo.isNotEmpty) return true;
    final invoiceCarInfo = _asMap(_pick(model.invoice, const ['car_info']));
    return invoiceCarInfo.isNotEmpty;
  }

  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> invoice) {
    final candidates = [
      invoice['items'],
      invoice['sales_meals'],
      invoice['booking_products'],
      invoice['products'],
      invoice['meals'],
    ];

    for (final candidate in candidates) {
      final items = _asMapList(candidate);
      if (items.isNotEmpty) {
        return items;
      }
    }

    return const [];
  }

  List<String> _extractFields(
    Map<String, dynamic> invoice,
    List<Map<String, dynamic>> items,
  ) {
    final raw = invoice['fields'];
    if (raw is List) {
      final seen = <String>{};
      final result = <String>[];
      for (final field in raw) {
        final key = field.toString().trim();
        if (key.isEmpty || seen.contains(key)) continue;
        seen.add(key);
        result.add(key);
      }
      if (result.isNotEmpty) {
        return result;
      }
    }

    final derived = <String>[];
    final seen = <String>{};
    for (final item in items) {
      for (final key in item.keys) {
        final k = key.toString().trim();
        if (k.isEmpty || seen.contains(k)) continue;
        seen.add(k);
        derived.add(k);
      }
    }

    if (derived.isNotEmpty) {
      return derived;
    }

    return const ['item_name', 'quantity', 'total'];
  }

  String _resolvePaymentMethods(Map<String, dynamic> invoice) {
    final methods = invoice['payment_methods'];

    if (methods is String && methods.trim().isNotEmpty) {
      return methods.trim();
    }

    if (methods is List) {
      final labels = methods
          .map((entry) {
            final map = _asMap(entry);
            return _firstNonEmptyString([
                  _pick(map, const ['name_ar', 'name', 'pay_method', 'method']),
                ]) ??
                '';
          })
          .where((label) => label.isNotEmpty)
          .toList();
      if (labels.isNotEmpty) {
        return labels.join(' - ');
      }
    }

    final pays = invoice['pays'];
    if (pays is List && pays.length > 1) {
      // Split payment: show each method with its amount
      final parts = <String>[];
      for (final entry in pays) {
        final map = _asMap(entry);
        if (map == null) continue;
        final label = _firstNonEmptyString([
              _pick(map, const ['name_ar', 'name', 'pay_method', 'method']),
            ]) ??
            '';
        if (label.isEmpty) continue;
        final amount = map['amount'];
        if (amount != null) {
          final amountStr = (amount is num)
              ? amount.toStringAsFixed(ApiConstants.digitsNumber)
              : (double.tryParse(amount.toString()) ?? 0).toStringAsFixed(ApiConstants.digitsNumber);
          parts.add('$label ($amountStr)');
        } else {
          parts.add(label);
        }
      }
      if (parts.isNotEmpty) {
        return parts.join(' - ');
      }
    } else if (pays is List && pays.isNotEmpty) {
      // Single payment method
      final map = _asMap(pays.first);
      final label = _firstNonEmptyString([
            _pick(map, const ['name_ar', 'name', 'pay_method', 'method']),
          ]) ??
          '';
      if (label.isNotEmpty) return label;
    }

    return '';
  }

  /// Resolve the SECONDARY label based on invoice language settings.
  String _altLabel(
    _InvoiceLanguage language, {
    String ar = '',
    required String en,
    String? hi,
    String? ur,
    String? tr,
    String? es,
  }) {
    return language.secLabel(
        ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);
  }

  /// Resolve the PRIMARY label based on invoice language settings.
  String _mainLbl(
    _InvoiceLanguage language, {
    required String ar,
    required String en,
    String? hi,
    String? ur,
    String? tr,
    String? es,
  }) {
    return language.mainLabel(
        ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);
  }

  String? _normalizeLanguageCode(String? raw) {
    if (raw == null) return null;
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    switch (normalized) {
      case 'ar':
      case 'en':
      case 'hi':
      case 'ur':
      case 'tr':
      case 'es':
        return normalized;
      default:
        return null;
    }
  }

  double _calculatePriceBeforeTax({
    required Map<String, dynamic> invoice,
    required List<Map<String, dynamic>> items,
  }) {
    if (items.isEmpty) {
      return _toDouble(_pick(invoice, const ['price']));
    }

    final firstItem = items.first;
    if (!firstItem.containsKey('total')) {
      return _toDouble(_pick(invoice, const ['price']));
    }

    var total = 0.0;
    for (final item in items) {
      total += _toDouble(_pick(item, const ['price', 'total']));
    }

    return double.parse(total.toStringAsFixed(ApiConstants.digitsNumber));
  }

  bool _truthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.trim().isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  String _displayValue(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is num) {
      if (value % 1 == 0) {
        return value.toStringAsFixed(0);
      }
      return value.toStringAsFixed(ApiConstants.digitsNumber);
    }
    return value.toString();
  }

  /// Pick the string for [languageCode] out of a language-keyed translation
  /// map (e.g. `{ar: "...", en: "..."}`). Falls back through English →
  /// Arabic → any non-empty value → `_displayValue` so the caller always
  /// receives a sensible string even when the requested language is missing.
  String _localizedValue(dynamic value, String languageCode) {
    if (value is Map) {
      final code = languageCode.trim().toLowerCase();
      final direct = value[code]?.toString().trim();
      if (direct != null && direct.isNotEmpty) return direct;
      final en = value['en']?.toString().trim();
      if (en != null && en.isNotEmpty) return en;
      final ar = value['ar']?.toString().trim();
      if (ar != null && ar.isNotEmpty) return ar;
      for (final v in value.values) {
        final text = v?.toString().trim();
        if (text != null && text.isNotEmpty) return text;
      }
      return '';
    }
    return _displayValue(value);
  }

  String _extractDate(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return '';

    final parsed = DateTime.tryParse(trimmed);
    if (parsed != null) {
      return DateFormat('yyyy-MM-dd').format(parsed);
    }

    if (trimmed.contains(' ')) {
      return trimmed.split(' ').first;
    }
    if (trimmed.contains('T')) {
      return trimmed.split('T').first;
    }

    return trimmed;
  }

  String _extractTime(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return '';

    final parsed = DateTime.tryParse(trimmed);
    if (parsed != null) {
      return DateFormat('HH:mm:ss').format(parsed);
    }

    if (trimmed.contains(' ')) {
      return trimmed.split(' ').last;
    }
    if (trimmed.contains('T')) {
      return trimmed.split('T').last;
    }

    return '';
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((entry) => _asMap(entry))
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  /// Locate an item's addon list across the same key variants probed by
  /// [extractReceiptAddonsFromItem]. The HTML preview previously read only
  /// `item['addons']`, so payloads that nested the list under
  /// `meal_addons` / `extras` / `meal.addons` rendered the meal without its
  /// addons even though the printer (which uses the extractor) showed them.
  List<Map<String, dynamic>> _extractItemAddonsForRender(
    Map<String, dynamic> item,
  ) {
    List<dynamic>? probe(List<String> keys) {
      for (final source in <Map<String, dynamic>>[item, _asMap(item['meal'])]) {
        if (source.isEmpty) continue;
        for (final key in keys) {
          final value = source[key];
          if (value is List && value.isNotEmpty) return value;
        }
      }
      return null;
    }

    final raw = probe(const [
      'addons',
      'meal_addons',
      'extras',
      'selected_addons',
      'addon_options',
    ]);
    if (raw == null) return const [];

    final translations = probe(const [
      'addons_translations',
      'meal_addons_translations',
      'extras_translations',
    ]);

    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is Map) {
        final m = _asMap(entry);
        if (translations != null && i < translations.length) {
          final t = _asMap(translations[i]);
          if (t.isNotEmpty) {
            m.putIfAbsent('attribute', () => t['attribute'] ?? t);
            m.putIfAbsent('option', () => t['option'] ?? t);
          }
        }
        if (m.isNotEmpty) result.add(m);
      } else if (entry is String) {
        final display = entry.trim();
        if (display.isEmpty) continue;
        // Saved-invoice endpoint sometimes returns addons as plain strings
        // ("Cooking type - Medium"). Synthesize the map shape the renderer
        // expects so the addon still surfaces in the preview.
        result.add(<String, dynamic>{
          'attribute': display,
          'option': '',
          'total': '',
        });
      }
    }
    return result;
  }

  dynamic _pick(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null) return value;
    }
    return null;
  }

  dynamic _pickPath(Map<String, dynamic> map, String path) {
    dynamic current = map;
    for (final segment in path.split('.')) {
      if (current is Map && current.containsKey(segment)) {
        current = current[segment];
      } else {
        return null;
      }
    }
    return current;
  }

  String? _firstNonEmptyString(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }
    return null;
  }

  String? _firstNonEmptyNonZeroString(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
        continue;
      }

      final normalized = text.startsWith('#') ? text.substring(1) : text;
      final parsed = int.tryParse(normalized);
      if (parsed != null && parsed == 0) {
        continue;
      }

      return text;
    }
    return null;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    final text = value.toString().trim();
    if (text.isEmpty) return 0;
    return double.tryParse(text.replaceAll(',', '.')) ?? 0;
  }

  int _normalizePaperWidthMm(dynamic value) {
    return normalizePaperWidthMm(value);
  }

  String _escapeHtml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  String _buildStyleSheet(int paperWidthMm) {
    final widthMm = _normalizePaperWidthMm(paperWidthMm);
    final widthCss = paperWidthCss(widthMm);

    return '''
@page {
  size: $widthCss auto;
  margin: 2mm;
}
* {
  box-sizing: border-box;
}
body {
  margin: 0;
  padding: 8px 0;
  background: #e5e7eb;
  color: #111827;
  font-family: 'Tajawal', Arial, Tahoma, sans-serif;
  font-size: 14px;
  line-height: 1.4;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}
p {
  margin: 2px 0;
}

/* ========== Layout utilities (Tailwind-compatible) ========== */
.hidden {
  display: flex !important;
  justify-content: center;
}
.flex {
  display: flex;
}
.justify-center {
  justify-content: center;
}
.justify-between {
  justify-content: space-between;
}
.items-center {
  align-items: center;
}
.text-left {
  text-align: left;
}
.text-right {
  text-align: right;
}
.text-center {
  text-align: center;
}
.font-bold {
  font-weight: 700;
}
.force-ltr {
  direction: ltr;
  text-align: left;
}
.whitespace-nowrap {
  white-space: nowrap;
}

/* ========== Spacing utilities ========== */
.mt-2 { margin-top: 8px; }
.mb-4 { margin-bottom: 16px; }
.my-2 { margin-top: 8px; margin-bottom: 8px; }
.px-2 { padding-right: 8px; padding-left: 8px; }
.px-4 { padding-right: 16px; padding-left: 16px; }
.py-1 { padding-top: 4px; padding-bottom: 4px; }
.pb-2 { padding-bottom: 8px; }

/* ========== Sizing utilities ========== */
.w-full { width: 100%; }
.w-24 { width: 96px; }
.h-24 { height: 96px; }
.w-1\\/3 { width: 33.333%; }
.w-7\\/12 { width: 58.333%; }
.object-contain { object-fit: contain; }

/* ========== Border utilities ========== */
.border { border: 1px solid; }
.border-2 { border: 2px solid #000; }
.border-black { border-color: #000; }
.border-gray-300 { border-color: #d1d5db; }
.border-collapse { border-collapse: collapse; }

/* ========== Background utilities ========== */
.bg-gray-50 { background-color: #f9fafb; }

/* ========== Typography utilities ========== */
.text-xs { font-size: 12px; }
.text-sm { font-size: 14px; }
.text-lg { font-size: 18px; }

/* ========== Receipt container ========== */
.bill {
  width: var(--receipt-width, $widthCss);
}
.bill-container {
  width: var(--receipt-width, $widthCss);
  max-width: calc(100vw - 12px);
  background: #fff;
  padding: 8px;
  box-sizing: border-box;
}
.size-5cm {
  --receipt-width: $widthCss;
}
.size-8cm {
  --receipt-width: 80mm;
}
.size-9cm {
  --receipt-width: 88mm;
}

/* ========== Seller info / header ========== */
.seller-info {
  text-align: center;
}
.logo-container {
  margin-bottom: 12px;
}
.logo-container img,
footer img {
  max-width: 96px;
  max-height: 96px;
  object-fit: contain;
}
.info {
  margin-bottom: 8px;
}
.title {
  margin: 0;
  font-size: 18px;
  font-weight: 700;
}
.mobile {
  direction: ltr;
}
.info-bottom {
  margin-bottom: 8px;
}
.info-bottom-item {
  margin-bottom: 6px;
  border-bottom: 1px dashed #d1d5db;
  padding-bottom: 4px;
}

/* ========== Invoice title (فاتورة ضريبية مبسطة) ========== */
.invoice-title {
  text-align: center;
  border-bottom: 1px dashed #9ca3af;
  border-top: 1px dashed #9ca3af;
  padding: 6px 0;
  margin: 10px 0;
  font-weight: 700;
}

/* ========== Client info ========== */
.client-info {
  margin-bottom: 8px;
}
.client-info-item {
  margin-bottom: 6px;
  border-bottom: 1px dashed #d1d5db;
  padding-bottom: 4px;
}

/* ========== Items table ========== */
.invoice-items table,
.car-info-table,
.addons-table {
  width: 100%;
  border-collapse: collapse;
}
.invoice-items th,
.invoice-items td,
.car-info-table th,
.car-info-table td,
.addons-table td,
.addons-table th {
  border: 1px solid #d1d5db;
  padding: 4px;
  vertical-align: top;
}
.addon-size {
  font-size: 11px;
}
.addon-item {
  font-size: 11px;
}

/* ========== Invoice details (totals) ========== */
.invoice-details {
  margin-bottom: 8px;
}
.invoice-details-item {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  border-bottom: 1px dashed #e5e7eb;
  padding: 6px 0;
}
.invoice-item-title {
  width: 52%;
}
.currency-area {
  margin-left: 4px;
  font-size: 11px;
  color: #6b7280;
}
.price {
  font-weight: 700;
}

/* ========== Footer ========== */
footer {
  text-align: center;
}
footer .invoice-details-item {
  display: block;
  text-align: center;
}

/* ==========================================================
   Scoped overrides from PrintOrdertokitchen.vue
   These scale font sizes UP for thermal-printer readability.
   ========================================================== */
.seller-info .info p,
.seller-info .info-bottom .info-bottom-item p {
  font-size: 18px !important;
  line-height: 1.5 !important;
}
.seller-info .border-2 {
  font-size: 20px !important;
  font-weight: bold !important;
}
.client-info .client-info-item p {
  font-size: 18px !important;
  line-height: 1.4 !important;
}
.invoice-items table thead th {
  font-size: 20px !important;
  font-weight: bold !important;
  padding: 6px !important;
}
.invoice-items table tbody td p {
  font-size: 18px !important;
  line-height: 1.4 !important;
}
.addons-table td {
  font-size: 16px !important;
  padding: 4px !important;
}
.addon-item {
  font-size: 16px !important;
}
.invoice-title p {
  font-size: 22px !important;
  font-weight: bold !important;
}
.invoice-details-item p,
.invoice-details-item .price {
  font-size: 18px !important;
}
.invoice-details-item .currency-area p {
  font-size: 14px !important;
}
.invoice-item-title p {
  font-size: 18px !important;
}
footer p {
  font-size: 16px !important;
}

/* ========== Print media ========== */
@media print {
  @page {
    size: $widthCss auto;
    margin: 2mm;
  }
  body {
    background: #fff;
    padding: 0;
    margin: 0;
  }
  .hidden {
    justify-content: flex-start;
  }
  .bill-container {
    width: $widthCss !important;
    max-width: $widthCss !important;
    box-shadow: none;
    margin: 0;
    padding: 0;
  }
}
''';
  }
}

/// Reconciled totals for a single invoice. Produced by
/// [InvoiceHtmlPdfService._resolveInvoiceTotals] so the WhatsApp PDF
/// path always feeds [OrderReceiptData] non-zero, internally consistent
/// values regardless of which invoice route the backend used.
class _InvoiceTotals {
  final double totalExclVat;
  final double vatAmount;
  final double totalInclVat;

  const _InvoiceTotals({
    required this.totalExclVat,
    required this.vatAmount,
    required this.totalInclVat,
  });
}

class _PrintInvoiceModel {
  final Map<String, dynamic> envelope;
  final Map<String, dynamic> invoice;
  final Map<String, dynamic> branch;
  final Map<String, dynamic> seller;
  final Map<String, dynamic> booking;
  final Map<String, dynamic> client;
  final Map<String, dynamic> carInfo;
  final _InvoiceLanguage language;
  final List<Map<String, dynamic>> items;
  final List<String> fields;
  final String type;
  final String module;
  final String kind;
  final _InvoiceTitle title;
  final String orderNumber;
  final String dailyOrderNumber;
  final String bookingDate;
  final String date;
  final String time;
  final String invoiceNumber;
  final String currencyAr;
  final String currencyEn;
  final String paymentMethods;
  final String policy;
  final String qrImage;
  final bool hasOrders;
  final double calculatedPriceBeforeTax;
  final String websiteUrl;

  _PrintInvoiceModel({
    required this.envelope,
    required this.invoice,
    required this.branch,
    required this.seller,
    required this.booking,
    required this.client,
    required this.carInfo,
    required this.language,
    required this.items,
    required this.fields,
    required this.type,
    required this.module,
    required this.kind,
    required this.title,
    required this.orderNumber,
    required this.dailyOrderNumber,
    required this.bookingDate,
    required this.date,
    required this.time,
    required this.invoiceNumber,
    required this.currencyAr,
    required this.currencyEn,
    required this.paymentMethods,
    required this.policy,
    required this.qrImage,
    required this.hasOrders,
    required this.calculatedPriceBeforeTax,
    required this.websiteUrl,
  });
}

class _InvoiceLanguage {
  final String primary;
  final String secondary;
  final bool allowSecondary;

  const _InvoiceLanguage({
    required this.primary,
    required this.secondary,
    required this.allowSecondary,
  });

  bool get showHindi =>
      primary == 'hi' || (allowSecondary && secondary == 'hi');

  bool get showUrdu => primary == 'ur' || (allowSecondary && secondary == 'ur');

  bool get showTurkish =>
      primary == 'tr' || (allowSecondary && secondary == 'tr');

  bool get showSpanish =>
      primary == 'es' || (allowSecondary && secondary == 'es');

  /// Resolve a label for a given language code.
  String _resolve(
    String code, {
    required String ar,
    required String en,
    String? hi,
    String? ur,
    String? tr,
    String? es,
  }) {
    switch (code) {
      case 'ar':
        return ar;
      case 'hi':
        return hi ?? en;
      case 'ur':
        return ur ?? en;
      case 'tr':
        return tr ?? en;
      case 'es':
        return es ?? en;
      case 'en':
      default:
        return en;
    }
  }

  /// The main (primary) label for the invoice.
  String mainLabel({
    required String ar,
    required String en,
    String? hi,
    String? ur,
    String? tr,
    String? es,
  }) =>
      _resolve(primary, ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);

  /// The secondary label shown below the primary. Empty if not allowed.
  String secLabel({
    required String ar,
    required String en,
    String? hi,
    String? ur,
    String? tr,
    String? es,
  }) {
    if (!allowSecondary) return '';
    if (secondary == primary) return '';
    return _resolve(secondary, ar: ar, en: en, hi: hi, ur: ur, tr: tr, es: es);
  }
}

class _InvoiceTitle {
  final String text;
  final String textAlt;

  const _InvoiceTitle({
    required this.text,
    required this.textAlt,
  });
}
