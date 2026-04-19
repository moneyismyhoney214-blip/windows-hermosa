import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Standalone TCP-based network printing helper.
///
/// Replicates the **exact** image processing pipeline used by
/// `flutter_bluetooth_printer`'s Receipt widget so that LAN prints
/// are indistinguishable in quality from Bluetooth prints.
///
/// Flow:
/// 1. Receive a PNG screenshot of the receipt widget
/// 2. Decode → resize to thermal dots width → grayscale → rasterize
/// 3. Wrap the raster data in standard ESC/POS commands
/// 4. Open a TCP socket to the printer and send the bytes
class NetworkPrintHelper {
  NetworkPrintHelper._();

  // ───────── ESC/POS constants ─────────
  static const _esc = 0x1B;
  static const _gs = 0x1D;
  static const _init = [_esc, 0x40]; // ESC @
  static const _lineFeed = [0x0A];
  static const _cutPaper = [_gs, 0x56, 0x41, 0x00]; // GS V 65 0

  /// Dots per line for each supported paper width
  static int dotsPerLine(int paperWidthMm) {
    if (paperWidthMm >= 80) return 576;
    return 360; // 58mm — same as flutter_bluetooth_printer PaperSize.mm58
  }

  // ──────────────────────────────────────────────────────────────────────
  //  PUBLIC API
  // ──────────────────────────────────────────────────────────────────────

  /// Processes a PNG [imageBytes] captured from a RepaintBoundary and sends
  /// the resulting ESC/POS raster data to [ip]:[port] via TCP.
  ///
  /// [paperWidthMm] determines the target raster width.
  /// [addFeeds] adds blank lines after the image (before the cut).
  static Future<void> printImage({
    required Uint8List imageBytes,
    required String ip,
    required int port,
    required int paperWidthMm,
    int addFeeds = 4,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final dots = dotsPerLine(paperWidthMm);

    // Encode in a background isolate so the UI thread stays smooth
    final escPosBytes = await compute(_encodePayload, {
      'bytes': imageBytes,
      'dotsPerLine': dots,
      'addFeeds': addFeeds,
    });

    // Open TCP socket and send
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: timeout);

      // Send in chunks to avoid overwhelming printer buffer
      const chunkSize = 4096;
      for (var offset = 0; offset < escPosBytes.length; offset += chunkSize) {
        final end = (offset + chunkSize).clamp(0, escPosBytes.length);
        socket.add(escPosBytes.sublist(offset, end));
        await socket.flush();
        // Small delay between chunks to let the printer process
        if (end < escPosBytes.length) {
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }

      // Wait a moment for the printer to finish processing
      await Future.delayed(const Duration(milliseconds: 300));

      debugPrint('✅ Network print sent: ${escPosBytes.length} bytes to $ip:$port');
    } finally {
      await socket?.close();
    }
  }

  /// Encodes a PNG [imageBytes] as ESC/POS raster bytes ready for any
  /// transport (TCP or Bluetooth). Exposed so Bluetooth printing can reuse the
  /// exact same thermal pipeline that network printing uses.
  static Future<Uint8List> encodeImageToEscPos({
    required Uint8List imageBytes,
    required int paperWidthMm,
    int addFeeds = 4,
  }) async {
    final dots = dotsPerLine(paperWidthMm);
    final bytes = await compute(_encodePayload, {
      'bytes': imageBytes,
      'dotsPerLine': dots,
      'addFeeds': addFeeds,
    });
    return bytes;
  }

  /// Tests connectivity to a network printer.
  static Future<bool> testConnection(String ip, int port, {Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: timeout);
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  //  ISOLATE-SAFE IMAGE PROCESSING
  //  (identical pipeline to flutter_bluetooth_printer's Generator)
  // ──────────────────────────────────────────────────────────────────────

  /// Runs in a background isolate via [compute].
  static Uint8List _encodePayload(Map<String, dynamic> args) {
    final Uint8List pngBytes = args['bytes'];
    final int dotsPerLine = args['dotsPerLine'];
    final int addFeeds = args['addFeeds'];

    // ── Step 1: Decode PNG, convert to JPG (matches BT package behaviour) ──
    final decoded = img.decodePng(pngBytes);
    if (decoded == null) throw Exception('Failed to decode PNG');
    final jpgBytes = img.encodeJpg(decoded);
    img.Image src = img.decodeJpg(jpgBytes)!;

    // ── Step 2: Resize to target dots per line (same as BT package) ──
    src = img.copyResize(
      src,
      width: dotsPerLine,
      maintainAspect: true,
      backgroundColor: img.ColorRgba8(255, 255, 255, 255),
      interpolation: img.Interpolation.cubic,
    );

    // ── Step 3: Convert to grayscale ──
    src = img.grayscale(src);

    // ── Step 4: Rasterize (identical to Generator._toRasterFormat) ──
    final rasterBytes = _toRasterFormat(src);
    final widthPx = src.width;
    final heightPx = src.height;
    final widthBytes = widthPx ~/ 8;

    // ── Step 5: Build ESC/POS payload ──
    final payload = <int>[];

    // Initialize printer
    payload.addAll(_init);

    // GS v 0  — raster bit image command
    // Format: GS v 0 m xL xH yL yH d1..dk
    payload.addAll([_gs, 0x76, 0x30, 0x00]); // GS v 0 (density=0)
    payload.addAll(_intLowHigh(widthBytes, 2)); // xL xH
    payload.addAll(_intLowHigh(heightPx, 2));   // yL yH
    payload.addAll(rasterBytes);

    // Feed lines
    for (var i = 0; i < addFeeds; i++) {
      payload.addAll(_lineFeed);
    }

    // Cut
    payload.addAll(_cutPaper);

    return Uint8List.fromList(payload);
  }

  /// Converts a grayscale image to ESC/POS raster format.
  /// This is **the same logic** as `Generator._toRasterFormat` in
  /// `flutter_bluetooth_printer`.
  static List<int> _toRasterFormat(img.Image imgSrc) {
    final image = img.Image.from(imgSrc);
    final widthPx = image.width;
    final heightPx = image.height;

    img.grayscale(image);
    img.invert(image);

    // Extract single-channel bytes
    final oneChannelBytes = <int>[];
    final buffer = image.getBytes(order: img.ChannelOrder.rgba);
    for (int i = 0; i < buffer.length; i += 4) {
      oneChannelBytes.add(buffer[i]);
    }

    // Pad width to be divisible by 8
    if (widthPx % 8 != 0) {
      final targetWidth = (widthPx + 8) - (widthPx % 8);
      final missingPx = targetWidth - widthPx;
      final extra = Uint8List(missingPx);
      for (int i = 0; i < heightPx; i++) {
        final pos = (i * widthPx + widthPx) + i * missingPx;
        oneChannelBytes.insertAll(pos, extra);
      }
    }

    return _packBitsIntoBytes(oneChannelBytes);
  }

  /// Packs 8 greyscale values into one byte (same as Generator._packBitsIntoBytes)
  static List<int> _packBitsIntoBytes(List<int> bytes) {
    const pxPerLine = 8;
    final res = <int>[];
    const threshold = 256 * 0.5;
    for (int i = 0; i < bytes.length; i += pxPerLine) {
      int newVal = 0;
      for (int j = 0; j < pxPerLine; j++) {
        newVal = _transformUint32Bool(
          newVal,
          pxPerLine - j,
          bytes[i + j] > threshold,
        );
      }
      res.add(newVal ~/ 2);
    }
    return res;
  }

  static int _transformUint32Bool(int uint32, int shift, bool newValue) {
    return ((0xFFFFFFFF ^ (0x1 << shift)) & uint32) |
        ((newValue ? 1 : 0) << shift);
  }

  static List<int> _intLowHigh(int value, int bytesNb) {
    final res = <int>[];
    int buf = value;
    for (int i = 0; i < bytesNb; i++) {
      res.add(buf % 256);
      buf = buf ~/ 256;
    }
    return res;
  }
}
