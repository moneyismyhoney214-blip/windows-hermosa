import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

const List<int> supportedPaperWidthsMm = <int>[58, 80, 88];

int normalizePaperWidthMm(dynamic value, {int fallback = 58}) {
  final parsed = _parsePaperWidthMm(value);
  if (parsed == null) {
    return _normalizeSupportedPaperWidth(fallback);
  }
  return _normalizeSupportedPaperWidth(parsed);
}

PaperSize escPosPaperSizeForWidth(int paperWidthMm) {
  final normalized = normalizePaperWidthMm(paperWidthMm);
  return normalized == 58 ? PaperSize.mm58 : PaperSize.mm80;
}

int thermalRasterWidthForPaper(int paperWidthMm) {
  switch (normalizePaperWidthMm(paperWidthMm)) {
    case 58:
      return 384;
    case 80:
      return 576;
    case 88:
      return 640;
    default:
      return 384;
  }
}

int thermalThresholdForPaper(int paperWidthMm) {
  // High threshold = more pixels become black = darker thermal print.
  // Combined with contrast:3.0 + gamma:0.5 for maximum darkness.
  switch (normalizePaperWidthMm(paperWidthMm)) {
    case 58:
      return 240;
    case 80:
      return 245;
    case 88:
      return 245;
    default:
      return 240;
  }
}

double invoiceWidgetWidthForPaper(int paperWidthMm) {
  switch (normalizePaperWidthMm(paperWidthMm)) {
    case 58:
      return 302.0;
    case 80:
      return 400.0;
    case 88:
      return 380.0;
    default:
      return 302.0;
  }
}

double invoicePreviewMaxWidthForPaper(int paperWidthMm) {
  switch (normalizePaperWidthMm(paperWidthMm)) {
    case 58:
      return 350.0;
    case 80:
      return 550.0;
    case 88:
      return 500.0;
    default:
      return 350.0;
  }
}

String paperWidthCss(int paperWidthMm) {
  return '${normalizePaperWidthMm(paperWidthMm)}mm';
}

int? _parsePaperWidthMm(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();

  final text = value.toString().trim();
  if (text.isEmpty) return null;

  final direct = int.tryParse(text);
  if (direct != null) return direct;

  final digits = RegExp(r'(\d{2,3})').firstMatch(text)?.group(1);
  return digits == null ? null : int.tryParse(digits);
}

int _normalizeSupportedPaperWidth(int value) {
  if (value >= 84) return 88;
  if (value >= 69) return 80;
  return 58;
}
