package com.example.flutter_terminal_sdk

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.Test
import org.mockito.Mockito

/*
 * This demonstrates a simple unit test of the Kotlin portion of this plugin's implementation.
 *
 * Once you have built the plugin's example app, you can run these tests from the command
 * line by running `./gradlew testDebugUnitTest` in the `example/android/` directory, or
 * you can run them directly from IDEs that support JUnit such as Android Studio.
 */

internal class FlutterTerminalSdkPluginTest {
  @Test
  fun onMethodCall_initializeBeforeActivityAttached_returnsPluginNotAttachedError() {
    val plugin = FlutterTerminalSdkPlugin()

    val call = MethodCall("initialize", emptyMap<String, Any>())
    val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
    plugin.onMethodCall(call, mockResult)

    Mockito.verify(mockResult).error(
      Mockito.eq("PLUGIN_NOT_ATTACHED_TO_ACTIVITY"),
      Mockito.contains("requires an attached Activity"),
      Mockito.isNull(),
    )
  }

  @Test
  fun onMethodCall_beforeInitialization_returnsPluginNotInitializedError() {
    val plugin = FlutterTerminalSdkPlugin()

    val call = MethodCall("purchase", null)
    val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
    plugin.onMethodCall(call, mockResult)

    Mockito.verify(mockResult).error(
      Mockito.eq("PLUGIN_NOT_INITIALIZED"),
      Mockito.contains("Nearpay plugin not initialized properly"),
      Mockito.isNull(),
    )
  }
}
