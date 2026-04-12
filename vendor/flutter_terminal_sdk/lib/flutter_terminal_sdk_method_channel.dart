import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_terminal_sdk_platform_interface.dart';

/// An implementation of [FlutterTerminalSdkPlatform] that uses method channels.
class MethodChannelFlutterTerminalSdk extends FlutterTerminalSdkPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_terminal_sdk');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
