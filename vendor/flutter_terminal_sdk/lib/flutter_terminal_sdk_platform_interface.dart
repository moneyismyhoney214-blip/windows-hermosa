import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_terminal_sdk_method_channel.dart';

abstract class FlutterTerminalSdkPlatform extends PlatformInterface {
  /// Constructs a FlutterTerminalSdkPlatform.
  FlutterTerminalSdkPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterTerminalSdkPlatform _instance = MethodChannelFlutterTerminalSdk();

  /// The default instance of [FlutterTerminalSdkPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterTerminalSdk].
  static FlutterTerminalSdkPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterTerminalSdkPlatform] when
  /// they register themselves.
  static set instance(FlutterTerminalSdkPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
