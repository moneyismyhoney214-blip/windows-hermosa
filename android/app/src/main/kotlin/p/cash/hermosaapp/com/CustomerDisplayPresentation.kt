package p.cash.hermosaapp.com

import android.app.Presentation
import android.content.Context
import android.os.Bundle
import android.view.Display
import android.view.WindowManager
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngineCache

/**
 * Customer-facing display rendered via Android's [Presentation] API on the
 * secondary screen.
 *
 * This replaces the older `CustomerDisplayActivity + launchDisplayId`
 * approach. Sunmi D2s / T2 / T2 Lite secondary displays are flagged
 * FLAG_PRIVATE (owned by the OEM), which causes `ActivityOptions.launchDisplayId`
 * to silently fall back to mirroring. Sunmi's official docs
 * (https://developer.android.com/reference/android/app/Presentation and
 * Sunmi's own Secondary Display API guide) require the [Presentation] API,
 * which is allowed to draw onto those private displays.
 *
 * Hosts a [FlutterView] attached to the secondary [io.flutter.embedding.engine.FlutterEngine]
 * cached under [ENGINE_ID].
 */
class CustomerDisplayPresentation(
    outerContext: Context,
    display: Display,
) : Presentation(outerContext, display) {

    companion object {
        const val ENGINE_ID = "customer_display_engine"
    }

    private var flutterView: FlutterView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        SunmiLog.init(context.applicationContext)
        SunmiLog.i(
            "CustomerDisplayPresentation.onCreate — hosted on display " +
                "id=${display.displayId} name='${display.name}' " +
                "flags=0x${Integer.toHexString(display.flags)}"
        )

        // Keep the Sunmi secondary panel awake and don't steal focus from
        // the cashier. Fullscreen so there's no status bar on the CDS.
        window?.apply {
            addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                    or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                    or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                    or WindowManager.LayoutParams.FLAG_FULLSCREEN
            )
            setLayout(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT
            )
        }

        val engine = FlutterEngineCache.getInstance().get(ENGINE_ID)
        if (engine == null) {
            SunmiLog.e(
                "CustomerDisplayPresentation: NO cached FlutterEngine for " +
                    "id='$ENGINE_ID' — dismissing"
            )
            dismiss()
            return
        }

        val container = FrameLayout(context)
        setContentView(container)

        flutterView = FlutterView(context).apply {
            attachToFlutterEngine(engine)
        }
        container.addView(
            flutterView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        engine.lifecycleChannel.appIsResumed()
        SunmiLog.i("CustomerDisplayPresentation.onCreate: FlutterView attached to engine")
    }

    override fun onStart() {
        super.onStart()
        SunmiLog.d("CustomerDisplayPresentation.onStart")
    }

    override fun onDisplayChanged() {
        super.onDisplayChanged()
        SunmiLog.d("CustomerDisplayPresentation.onDisplayChanged")
    }

    override fun onDisplayRemoved() {
        super.onDisplayRemoved()
        SunmiLog.w("CustomerDisplayPresentation.onDisplayRemoved — host display gone")
    }

    override fun onStop() {
        SunmiLog.i("CustomerDisplayPresentation.onStop — detaching FlutterView")
        val engine = FlutterEngineCache.getInstance().get(ENGINE_ID)
        engine?.lifecycleChannel?.appIsInactive()
        flutterView?.detachFromFlutterEngine()
        flutterView = null
        // Don't destroy the engine — MainActivity owns it.
        super.onStop()
    }
}
