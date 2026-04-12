import 'callbacks.dart';

class TerminalSDKInitializationListener {
  final StringCallback? onInitializationFailure;
  final InitializationCallback? onInitializationSuccess;

  TerminalSDKInitializationListener({
    this.onInitializationFailure,
    this.onInitializationSuccess,
  });
}