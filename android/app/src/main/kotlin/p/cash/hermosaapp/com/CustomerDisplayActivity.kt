package p.cash.hermosaapp.com

import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngineCache

/**
 * Plain Activity (NOT FlutterActivity) that renders a FlutterView on the
 * secondary display of dual-screen devices (Sunmi D2s).
 *
 * Using a plain Activity avoids the FlutterActivity plugin-attachment
 * pipeline, which crashes on secondary displays because plugins like
 * NfcManagerPlugin try to register broadcast receivers that are not
 * valid on non-default displays.
 */
class CustomerDisplayActivity : Activity() {

    companion object {
        private const val TAG = "CustomerDisplay"
        const val ENGINE_ID = "customer_display_engine"
    }

    private var flutterView: FlutterView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Full-screen, no focus stealing from main display
        window.setFlags(
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        )
        window.setLayout(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT
        )

        val engine = FlutterEngineCache.getInstance().get(ENGINE_ID)
        if (engine == null) {
            Log.e(TAG, "No cached FlutterEngine found for '$ENGINE_ID'")
            finish()
            return
        }

        val container = FrameLayout(this)
        setContentView(container)

        flutterView = FlutterView(this).apply {
            attachToFlutterEngine(engine)
        }
        container.addView(
            flutterView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )

        Log.d(TAG, "FlutterView attached on secondary display")
    }

    override fun onResume() {
        super.onResume()
        val engine = FlutterEngineCache.getInstance().get(ENGINE_ID)
        engine?.lifecycleChannel?.appIsResumed()
    }

    override fun onPause() {
        val engine = FlutterEngineCache.getInstance().get(ENGINE_ID)
        engine?.lifecycleChannel?.appIsInactive()
        super.onPause()
    }

    override fun onDestroy() {
        flutterView?.detachFromFlutterEngine()
        flutterView = null
        // Don't destroy the engine — MainActivity owns it
        super.onDestroy()
    }
}
