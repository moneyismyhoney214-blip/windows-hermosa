import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin Dart wrapper over the `com.hermosaapp.bluetooth_print` MethodChannel
/// implemented in `BluetoothPrintBridge.kt`.
///
/// Use this for any Bluetooth thermal printer — especially the ones that
/// require a PIN to pair. The upstream `flutter_bluetooth_printer` plugin
/// only attempts a secure SDP connect, which silently fails on PIN-protected
/// printers; this bridge:
///
///   • forces a system-level bond (with a 30s timeout) before connecting,
///   • cancels any in-flight discovery,
///   • tries secure → insecure → reflection RFCOMM channel 1 in order,
///   • streams the bytes in 512-byte chunks so cheap printer firmware
///     doesn't drop the cut command at the tail of the payload.
///
/// Channel methods are no-ops on non-Android platforms (returns sensible
/// defaults / throws UnsupportedError on `printBytes`).
class BluetoothPrintChannel {
  static const MethodChannel _channel =
      MethodChannel('com.hermosaapp.bluetooth_print');

  static bool get _isSupported => !kIsWeb && Platform.isAndroid;

  /// Whether the device exposes a Bluetooth adapter at all.
  static Future<bool> isBluetoothAvailable() async {
    if (!_isSupported) return false;
    final res = await _channel.invokeMethod<bool>('isBluetoothAvailable');
    return res ?? false;
  }

  /// Whether Bluetooth is currently turned on.
  static Future<bool> isBluetoothEnabled() async {
    if (!_isSupported) return false;
    final res = await _channel.invokeMethod<bool>('isBluetoothEnabled');
    return res ?? false;
  }

  /// Whether the given MAC address is already paired with the OS.
  static Future<bool> isBonded(String address) async {
    if (!_isSupported) return false;
    final res = await _channel.invokeMethod<bool>(
      'isBonded',
      {'address': address},
    );
    return res ?? false;
  }

  /// Returns OS-level paired devices as `[{name, address}, ...]`.
  static Future<List<({String name, String address})>>
      getBondedDevices() async {
    if (!_isSupported) return const [];
    final raw = await _channel.invokeMethod<List<dynamic>>('getBondedDevices');
    if (raw == null) return const [];
    return raw
        .whereType<Map>()
        .map((m) => (
              name: (m['name']?.toString() ?? '').trim(),
              address: (m['address']?.toString() ?? '').trim(),
            ))
        .where((d) => d.address.isNotEmpty)
        .toList(growable: false);
  }

  /// Triggers the system pairing flow for [address] (showing the PIN
  /// dialog if the printer requires one). Resolves to true once the device
  /// is bonded; false if the user cancelled or the request timed out.
  ///
  /// Safe to call when the device is already bonded — returns true
  /// immediately in that case.
  static Future<bool> bondDevice(String address) async {
    if (!_isSupported) return false;
    final res = await _channel.invokeMethod<bool>(
      'bondDevice',
      {'address': address},
    );
    return res ?? false;
  }

  /// Sends [data] to the printer at [address]. Bonds first if needed,
  /// opens a fresh socket per call, retries with insecure / reflection
  /// transports if the secure SDP connect fails, then closes the socket.
  ///
  /// Throws [PlatformException] with a human-readable message on failure.
  static Future<void> printBytes({
    required String address,
    required Uint8List data,
  }) async {
    if (!_isSupported) {
      throw UnsupportedError(
        'BluetoothPrintChannel is only available on Android',
      );
    }
    await _channel.invokeMethod<bool>(
      'printBytes',
      {'address': address, 'data': data},
    );
  }
}
