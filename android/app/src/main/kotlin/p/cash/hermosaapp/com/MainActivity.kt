package p.cash.hermosaapp.com

import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.view.Display
import androidx.annotation.NonNull
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val PRESENTATION_CHANNEL = "com.hermosaapp.presentation"
        private const val SECONDARY_ENGINE_ID = "customer_display_engine"
    }

    private var secondaryEngine: FlutterEngine? = null
    private var presentationChannel: MethodChannel? = null
    private var secondaryChannel: MethodChannel? = null
    private var presentation: CustomerDisplayPresentation? = null
    private var isPresentationShowing = false
    private var secondaryDisplayId: Int = -1

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SunmiLog.init(applicationContext)
        SunmiLog.i("MainActivity.configureFlutterEngine — primary engine wired")

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
            "isSecondaryEngine" -> result.success(false)

            "hasSecondaryDisplay" -> {
                val display = findSecondaryDisplay()
                SunmiLog.i("MC hasSecondaryDisplay -> ${display != null}")
                result.success(display != null)
            }
            "getSecondaryDisplayInfo" -> {
                val display = findSecondaryDisplay()
                if (display != null) {
                    val info = mapOf(
                        "id" to display.displayId,
                        "name" to display.name,
                        "width" to display.mode.physicalWidth,
                        "height" to display.mode.physicalHeight
                    )
                    SunmiLog.i("MC getSecondaryDisplayInfo -> $info")
                    result.success(info)
                } else {
                    SunmiLog.w("MC getSecondaryDisplayInfo -> null (no display)")
                    result.success(null)
                }
            }
            "showPresentation" -> {
                SunmiLog.i("MC showPresentation requested by Dart")
                showOnSecondaryDisplay(result)
            }
            "dismissPresentation" -> {
                SunmiLog.i("MC dismissPresentation requested by Dart")
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
                    SunmiLog.w("MC sendToSecondaryDisplay called with null data (type=$type)")
                    result.error("INVALID_DATA", "Data is null", null)
                }
            }
            "isPresentationShowing" -> result.success(isPresentationShowing)

            "logSunmi" -> {
                val level = call.argument<String>("level") ?: "I"
                val message = call.argument<String>("message") ?: ""
                when (level.uppercase()) {
                    "D" -> SunmiLog.d("[dart] $message")
                    "W" -> SunmiLog.w("[dart] $message")
                    "E" -> SunmiLog.e("[dart] $message")
                    else -> SunmiLog.i("[dart] $message")
                }
                result.success(true)
            }
            "getSunmiLogPath" -> result.success(SunmiLog.path())
            "dumpDisplays" -> {
                SunmiLog.dumpAllDisplays(applicationContext, "dart-request")
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Locates the secondary display, preferring Sunmi's own selection
     * criteria (from their Secondary Display API doc):
     *   FLAG_PRESENTATION + FLAG_SECURE + FLAG_SUPPORTS_PROTECTED_BUFFERS.
     *
     * Falls back to any display advertised in `DISPLAY_CATEGORY_PRESENTATION`,
     * and finally to any non-default display. Private displays are allowed —
     * the `Presentation` API can draw on them even though
     * `ActivityOptions.launchDisplayId` cannot.
     */
    private fun findSecondaryDisplay(): Display? {
        SunmiLog.dumpAllDisplays(applicationContext, "findSecondaryDisplay")
        val dm = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val all = dm.displays

        // Tier 1 — Sunmi-official criteria.
        for (d in all) {
            val f = d.flags
            val matches =
                (f and Display.FLAG_PRESENTATION) != 0 &&
                    (f and Display.FLAG_SECURE) != 0 &&
                    (f and Display.FLAG_SUPPORTS_PROTECTED_BUFFERS) != 0
            if (matches) {
                SunmiLog.i(
                    "findSecondaryDisplay: TIER 1 hit (Sunmi criteria " +
                        "PRESENTATION+SECURE+PROTECTED_BUFFERS) — " +
                        "id=${d.displayId} name='${d.name}'"
                )
                return d
            }
        }

        // Tier 2 — standard Android PRESENTATION category (covers emulator
        // and most non-Sunmi external displays).
        val presentationDisplays =
            dm.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
        if (presentationDisplays.isNotEmpty()) {
            val d = presentationDisplays[0]
            SunmiLog.i(
                "findSecondaryDisplay: TIER 2 hit (DISPLAY_CATEGORY_PRESENTATION) — " +
                    "id=${d.displayId} name='${d.name}'"
            )
            return d
        }

        // Tier 3 — any non-default display. Private is OK here because the
        // Presentation API can draw on it.
        for (d in all) {
            if (d.displayId == Display.DEFAULT_DISPLAY) continue
            SunmiLog.i(
                "findSecondaryDisplay: TIER 3 hit (non-default fallback) — " +
                    "id=${d.displayId} name='${d.name}' " +
                    "flags=0x${Integer.toHexString(d.flags)}"
            )
            return d
        }

        SunmiLog.e(
            "findSecondaryDisplay: NO display found — total displays=${all.size}. " +
                "Device likely has only one physical panel."
        )
        return null
    }

    private fun showOnSecondaryDisplay(result: MethodChannel.Result) {
        val display = findSecondaryDisplay()
        if (display == null) {
            SunmiLog.e("showOnSecondaryDisplay: aborting — no secondary display available")
            result.error("NO_DISPLAY", "No secondary display available", null)
            return
        }

        SunmiLog.i(
            "showOnSecondaryDisplay: target display id=${display.displayId} " +
                "name='${display.name}' flags=0x${Integer.toHexString(display.flags)}"
        )

        try {
            dismissSecondaryDisplay()
            secondaryDisplayId = display.displayId

            // Create the engine WITHOUT running Dart yet — we need the
            // method-channel handler registered before the entry point
            // starts executing so the first `logSunmi` call is captured
            // (otherwise a race eats those early messages and we can't
            // tell whether the Dart side booted at all).
            SunmiLog.i("showOnSecondaryDisplay: creating FlutterEngine (no auto-run)")
            val engine = FlutterEngine(this)
            secondaryEngine = engine
            FlutterEngineCache.getInstance().put(SECONDARY_ENGINE_ID, engine)
            SunmiLog.i("showOnSecondaryDisplay: secondary engine cached as '$SECONDARY_ENGINE_ID'")

            secondaryChannel = MethodChannel(
                engine.dartExecutor.binaryMessenger,
                PRESENTATION_CHANNEL
            )
            secondaryChannel!!.setMethodCallHandler { call, secondaryResult ->
                when (call.method) {
                    "isSecondaryEngine" -> secondaryResult.success(true)
                    "secondaryDisplayReady" -> {
                        SunmiLog.i("secondary engine reported READY (Flutter side booted)")
                        runOnUiThread {
                            presentationChannel?.invokeMethod("onSecondaryDisplayReady", null)
                        }
                        secondaryResult.success(true)
                    }
                    "onMealAvailabilityToggle" -> {
                        val data = call.arguments as? Map<*, *>
                        SunmiLog.d("secondary -> primary: onMealAvailabilityToggle $data")
                        runOnUiThread {
                            presentationChannel?.invokeMethod("onMealAvailabilityToggle", data)
                        }
                        secondaryResult.success(true)
                    }
                    "logSunmi" -> {
                        val level = call.argument<String>("level") ?: "I"
                        val message = call.argument<String>("message") ?: ""
                        when (level.uppercase()) {
                            "D" -> SunmiLog.d("[dart-secondary] $message")
                            "W" -> SunmiLog.w("[dart-secondary] $message")
                            "E" -> SunmiLog.e("[dart-secondary] $message")
                            else -> SunmiLog.i("[dart-secondary] $message")
                        }
                        secondaryResult.success(true)
                    }
                    "getSunmiLogPath" -> secondaryResult.success(SunmiLog.path())
                    "hasSecondaryDisplay" -> secondaryResult.success(false)
                    "showPresentation" -> secondaryResult.success(false)
                    "isPresentationShowing" -> secondaryResult.success(false)
                    else -> secondaryResult.notImplemented()
                }
            }

            // Now run the dedicated entry point. The 3-arg DartEntrypoint
            // form is required here — the 2-arg form looks up the function
            // in the default library (main.dart), which does NOT contain
            // `customerDisplayMain`. Without the explicit library URI the
            // entry point silently fails to resolve and the isolate stays
            // idle (no logs, no rendering — just a mirror of the cashier).
            val dartEntrypoint = DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "package:hermosa_pos/customer_display/customer_display_main.dart",
                "customerDisplayMain"
            )
            SunmiLog.i(
                "showOnSecondaryDisplay: executing Dart entrypoint " +
                    "library='${dartEntrypoint.dartEntrypointLibrary}' " +
                    "function='${dartEntrypoint.dartEntrypointFunctionName}'"
            )
            engine.dartExecutor.executeDartEntrypoint(dartEntrypoint)
            SunmiLog.i("showOnSecondaryDisplay: executeDartEntrypoint returned")

            // Sunmi-official way: android.app.Presentation. Works on their
            // FLAG_PRIVATE OEM secondary display, unlike launchDisplayId.
            val p = CustomerDisplayPresentation(this, display)
            p.setOnDismissListener {
                SunmiLog.i("Presentation dismissed")
                isPresentationShowing = false
                presentation = null
            }

            SunmiLog.i(
                "showOnSecondaryDisplay: calling Presentation.show() for " +
                    "display ${display.displayId}"
            )
            p.show()
            presentation = p
            isPresentationShowing = true

            SunmiLog.i("showOnSecondaryDisplay: Presentation.show() returned OK")
            result.success(true)
        } catch (e: Exception) {
            SunmiLog.e("showOnSecondaryDisplay: FAILED — ${e.message}", e)
            // Clean up any half-built engine so we can retry cleanly later.
            dismissSecondaryDisplay()
            result.error("LAUNCH_ERROR", e.message, null)
        }
    }

    private fun dismissSecondaryDisplay() {
        try {
            presentation?.let {
                SunmiLog.i("dismissSecondaryDisplay: dismissing active Presentation")
                try { it.dismiss() } catch (t: Throwable) {
                    SunmiLog.w("dismissSecondaryDisplay: dismiss() threw: ${t.message}")
                }
            }
            presentation = null
            isPresentationShowing = false
            secondaryChannel = null
            secondaryDisplayId = -1

            secondaryEngine?.let {
                FlutterEngineCache.getInstance().remove(SECONDARY_ENGINE_ID)
                it.destroy()
            }
            secondaryEngine = null
        } catch (e: Exception) {
            SunmiLog.e("dismissSecondaryDisplay failed", e)
        }
    }

    private fun sendDataToSecondary(type: String, data: Map<String, Any?>) {
        val channel = secondaryChannel
        if (channel == null) {
            SunmiLog.w("sendDataToSecondary($type): no secondary channel — dropping")
            return
        }
        runOnUiThread {
            try {
                channel.invokeMethod("onDataFromMain", mapOf(
                    "type" to type,
                    "data" to data
                ))
            } catch (e: Exception) {
                SunmiLog.e("sendDataToSecondary($type) failed", e)
            }
        }
    }

    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) {
            SunmiLog.i("DisplayListener.onDisplayAdded id=$displayId")
            SunmiLog.dumpAllDisplays(applicationContext, "onDisplayAdded")
            runOnUiThread {
                presentationChannel?.invokeMethod("onDisplayAdded", mapOf("displayId" to displayId))
            }
        }
        override fun onDisplayRemoved(displayId: Int) {
            SunmiLog.i("DisplayListener.onDisplayRemoved id=$displayId")
            if (displayId == secondaryDisplayId) dismissSecondaryDisplay()
            runOnUiThread {
                presentationChannel?.invokeMethod("onDisplayRemoved", mapOf("displayId" to displayId))
            }
        }
        override fun onDisplayChanged(displayId: Int) {
            SunmiLog.d("DisplayListener.onDisplayChanged id=$displayId")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        SunmiLog.init(applicationContext)
        SunmiLog.i("MainActivity.onCreate")
        val dm = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        dm.registerDisplayListener(displayListener, null)
    }

    override fun onResume() {
        super.onResume()
        SunmiLog.d("MainActivity.onResume")
    }

    override fun onPause() {
        SunmiLog.d("MainActivity.onPause")
        super.onPause()
    }

    override fun onDestroy() {
        SunmiLog.i("MainActivity.onDestroy")
        val dm = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        dm.unregisterDisplayListener(displayListener)
        dismissSecondaryDisplay()
        super.onDestroy()
    }
}
