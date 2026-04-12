import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermosa_pos/utils/paper_width_utils.dart';

void main() {
  test('normalizePaperWidthMm keeps supported widths and normalizes text', () {
    expect(normalizePaperWidthMm(58), 58);
    expect(normalizePaperWidthMm(80), 80);
    expect(normalizePaperWidthMm(88), 88);
    expect(normalizePaperWidthMm('80mm'), 80);
    expect(normalizePaperWidthMm(' 88 mm '), 88);
  });

  test('normalizePaperWidthMm snaps nearby widths to supported values', () {
    expect(normalizePaperWidthMm(60), 58);
    expect(normalizePaperWidthMm(82), 80);
    expect(normalizePaperWidthMm(90), 88);
  });

  test('paper helpers map 88mm safely for ESC/POS and raster sizing', () {
    expect(escPosPaperSizeForWidth(88), PaperSize.mm80);
    expect(thermalRasterWidthForPaper(88), 640);
    expect(thermalThresholdForPaper(88), 245);
    expect(invoiceWidgetWidthForPaper(88), 462.0);
    expect(invoicePreviewMaxWidthForPaper(88), 500.0);
    expect(paperWidthCss(88), '88mm');
  });
}
