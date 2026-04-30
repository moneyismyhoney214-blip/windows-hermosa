import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin Dart wrapper over the `com.hermosaapp.q7printer` MethodChannel
/// implemented in `CentermQ7PrintBridge.kt`.
///
/// The Q7 SDK is backed by the `com.pos.smartposservice` system service
/// that ships only on Centerm Q7 hardware. Every method short-circuits
/// to `false` / no-op on non-Android platforms and on devices where
/// that package is missing — which is the whole point: the rest of the
/// app's printer pipeline (Sunmi, Bluetooth, network) keeps working
/// untouched on every other device.
class Q7PrinterChannel {
  static const MethodChannel _channel =
      MethodChannel('com.hermosaapp.q7printer');

  /// Sentinel used in [DeviceConfig.id] for the auto-registered Q7
  /// built-in printer entry. Anything starting with this prefix is
  /// routed through the Q7 channel instead of the network/BT paths.
  static const String deviceIdPrefix = 'q7_builtin:';

  /// Sentinel device id for the singleton built-in Q7 printer.
  static const String builtInDeviceId = 'q7_builtin:cashier';

  /// Sentinel value used for `model` so the printer pipeline can
  /// recognise the entry independently of the connection-type enum.
  static const String builtInModel = 'q7_builtin';

  static bool get _isSupported => !kIsWeb && Platform.isAndroid;

  /// True only on Q7 hardware where the SDK service is installed AND
  /// the SDK successfully bound. Cached results are NOT used — the
  /// detection roundtrip is cheap and the answer can change if the
  /// service is installed/removed at runtime.
  static Future<bool> isAvailable() async {
    if (!_isSupported) return false;
    try {
      final res = await _channel.invokeMethod<bool>('isAvailable');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Forces an SDK bind. Usually unnecessary — `printBitmap` and the
  /// other methods bind lazily — but useful for "warm up" on app
  /// boot to surface a dead service early.
  static Future<bool> init() async {
    if (!_isSupported) return false;
    try {
      final res = await _channel.invokeMethod<bool>('init');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Reads the printer's current state code + message. Throws
  /// [PlatformException] if the bridge is not bound.
  static Future<({int code, String msg})> getStatus() async {
    if (!_isSupported) {
      throw UnsupportedError('Q7PrinterChannel only runs on Android');
    }
    final raw = await _channel.invokeMapMethod<String, dynamic>('getStatus');
    return (
      code: (raw?['code'] as int?) ?? -1,
      msg: (raw?['msg']?.toString() ?? '').trim(),
    );
  }

  /// Sends [data] (PNG bytes — usually the rasterised receipt image
  /// produced by `RepaintBoundary.toImage`) to the Q7 printer and
  /// auto-feeds [feedLines] paper at the end so the cut sits below
  /// the last printed row.
  ///
  /// Throws [PlatformException] with `Q7_UNAVAILABLE` on non-Q7
  /// devices and `Q7_PRINT_FAILED` on driver errors.
  static Future<void> printBitmap({
    required Uint8List data,
    int feedLines = 3,
  }) async {
    if (!_isSupported) {
      throw UnsupportedError('Q7PrinterChannel only runs on Android');
    }
    await _channel.invokeMethod<bool>('printBitmap', {
      'data': data,
      'feed': feedLines,
    });
  }

  /// Feeds blank lines (e.g. to push the last receipt past the cutter).
  static Future<void> feed(int lines) async {
    if (!_isSupported) return;
    await _channel.invokeMethod<bool>('feed', {'lines': lines});
  }
}
