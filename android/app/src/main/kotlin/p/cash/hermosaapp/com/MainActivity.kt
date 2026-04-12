package p.cash.hermosaapp.com

import android.app.ActivityOptions
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.util.Log
import android.view.Display
import androidx.annotation.NonNull
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "Presentation"
        private const val PRESENTATION_CHANNEL = "com.hermosaapp.presentation"
        private const val SECONDARY_ENGINE_ID = "customer_display_engine"
    }

    private var engineGroup: FlutterEngineGroup? = null
    private var secondaryEngine: FlutterEngine? = null
    private var presentationChannel: MethodChannel? = null
    private var secondaryChannel: MethodChannel? = null
    private var isSecondaryActivityLaunched = false
    private var secondaryDisplayId: Int = -1

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        presentationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PRESENTATION_CHANNEL
        )
        presentationChannel!!.setMethodCallHandler { call, result ->
            handlePresentationCall(call, result)
        }
    }

    private fun handlePresentationCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Primary engine asks "am I secondary?" — answer: no.
            "isSecondaryEngine" -> {
                result.success(false)
            }
            "hasSecondaryDisplay" -> {
                val display = findSecondaryDisplay()
                result.success(display != null)
            }
            "getSecondaryDisplayInfo" -> {
                val display = findSecondaryDisplay()
                if (display != null) {
                    result.success(mapOf(
                        "id" to display.displayId,
                        "name" to display.name,
                        "width" to display.mode.physicalWidth,
                        "height" to display.mode.physicalHeight
                    ))
                } else {
                    result.success(null)
                }
            }
            "showPresentation" -> {
                showOnSecondaryDisplay(result)
            }
            "dismissPresentation" -> {
                dismissSecondaryDisplay()
                result.success(true)
            }
            "sendToSecondaryDisplay" -> {
                val data = call.argument<Map<String, Any?>>("data")
                val type = call.argument<String>("type") ?: "update"
                if (data != null) {
                    sendDataToSecondary(type, data)
                    result.success(true)
                } else {
                    result.error("INVALID_DATA", "Data is null", null)
                }
            }
            "isPresentationShowing" -> {
                result.success(isSecondaryActivityLaunched)
            }
            else -> result.notImplemented()
        }
    }

    private fun findSecondaryDisplay(): Display? {
        val displayManager = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager

        // 1. Try DISPLAY_CATEGORY_PRESENTATION first
        val presentationDisplays = displayManager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
        if (presentationDisplays.isNotEmpty()) {
            val d = presentationDisplays[0]
            Log.d(TAG, "Found presentation display: ${d.name} (id=${d.displayId})")
            return d
        }

        // 2. Check ALL displays for non-default ones (Sunmi D2s, etc.)
        val allDisplays = displayManager.displays
        for (display in allDisplays) {
            if (display.displayId != Display.DEFAULT_DISPLAY) {
                Log.d(TAG, "Found secondary display: ${display.name} (id=${display.displayId})")
                return display
            }
        }

        return null
    }

    private fun showOnSecondaryDisplay(result: MethodChannel.Result) {
        val display = findSecondaryDisplay()
        if (display == null) {
            result.error("NO_DISPLAY", "No secondary display available", null)
            return
        }

        try {
            dismissSecondaryDisplay()
            secondaryDisplayId = display.displayId

            if (engineGroup == null) {
                engineGroup = FlutterEngineGroup(this)
            }

            // Use the DEFAULT main() entry point — the Dart side detects
            // it's the secondary engine via the isSecondaryEngine method call.
            val dartEntrypoint = DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "main"
            )

            secondaryEngine = engineGroup!!.createAndRunEngine(this, dartEntrypoint)
            FlutterEngineCache.getInstance().put(SECONDARY_ENGINE_ID, secondaryEngine!!)

            // Setup MethodChannel on secondary engine
            secondaryChannel = MethodChannel(
                secondaryEngine!!.dartExecutor.binaryMessenger,
                PRESENTATION_CHANNEL
            )

            // Handle calls FROM the secondary engine
            secondaryChannel!!.setMethodCallHandler { call, secondaryResult ->
                when (call.method) {
                    // Secondary engine asks "am I secondary?" — answer: YES.
                    "isSecondaryEngine" -> {
                        secondaryResult.success(true)
                    }
                    "secondaryDisplayReady" -> {
                        Log.d(TAG, "Secondary display Flutter engine ready")
                        runOnUiThread {
                            presentationChannel?.invokeMethod("onSecondaryDisplayReady", null)
                        }
                        secondaryResult.success(true)
                    }
                    "onMealAvailabilityToggle" -> {
                        val data = call.arguments as? Map<*, *>
                        runOnUiThread {
                            presentationChannel?.invokeMethod("onMealAvailabilityToggle", data)
                        }
                        secondaryResult.success(true)
                    }
                    // Secondary engine doesn't need these — just return defaults
                    "hasSecondaryDisplay" -> secondaryResult.success(false)
                    "showPresentation" -> secondaryResult.success(false)
                    "isPresentationShowing" -> secondaryResult.success(false)
                    else -> secondaryResult.notImplemented()
                }
            }

            // Launch the Activity on the secondary display
            val intent = Intent(this, CustomerDisplayActivity::class.java)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)

            val options = ActivityOptions.makeBasic()
            options.launchDisplayId = display.displayId

            startActivity(intent, options.toBundle())
            isSecondaryActivityLaunched = true

            Log.d(TAG, "CustomerDisplayActivity launched on display ${display.displayId}")
            result.success(true)

        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch on secondary display: ${e.message}", e)
            result.error("LAUNCH_ERROR", e.message, null)
        }
    }

    private fun dismissSecondaryDisplay() {
        try {
            isSecondaryActivityLaunched = false
            secondaryChannel = null
            secondaryDisplayId = -1

            secondaryEngine?.let {
                FlutterEngineCache.getInstance().remove(SECONDARY_ENGINE_ID)
                it.destroy()
            }
            secondaryEngine = null
        } catch (e: Exception) {
            Log.e(TAG, "Error dismissing secondary display: ${e.message}", e)
        }
    }

    private fun sendDataToSecondary(type: String, data: Map<String, Any?>) {
        val channel = secondaryChannel ?: return
        runOnUiThread {
            try {
                channel.invokeMethod("onDataFromMain", mapOf(
                    "type" to type,
                    "data" to data
                ))
            } catch (e: Exception) {
                Log.e(TAG, "Error sending to secondary: ${e.message}", e)
            }
        }
    }

    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) {
            Log.d(TAG, "Display added: $displayId")
            runOnUiThread {
                presentationChannel?.invokeMethod("onDisplayAdded", mapOf("displayId" to displayId))
            }
        }
        override fun onDisplayRemoved(displayId: Int) {
            Log.d(TAG, "Display removed: $displayId")
            if (displayId == secondaryDisplayId) dismissSecondaryDisplay()
            runOnUiThread {
                presentationChannel?.invokeMethod("onDisplayRemoved", mapOf("displayId" to displayId))
            }
        }
        override fun onDisplayChanged(displayId: Int) {}
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val dm = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        dm.registerDisplayListener(displayListener, null)
    }

    override fun onDestroy() {
        val dm = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        dm.unregisterDisplayListener(displayListener)
        dismissSecondaryDisplay()
        engineGroup = null
        super.onDestroy()
    }
}
