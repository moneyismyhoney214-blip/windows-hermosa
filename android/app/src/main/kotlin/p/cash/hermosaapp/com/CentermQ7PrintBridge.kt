package p.cash.hermosaapp.com

import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.RemoteException
import android.os.SystemClock
import com.pos.sdk.DeviceManager
import com.pos.sdk.DevicesFactory
import com.pos.sdk.callback.ResultCallback
import com.pos.sdk.printer.InnerResultCallback
import com.pos.sdk.printer.PrinterDevice
import com.pos.sdk.printer.PrinterStatus
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/**
 * MethodChannel bridge for the Centerm Q7 built-in thermal printer.
 *
 * The Q7 SDK is backed by the `com.pos.smartposservice` system service
 * which only exists on Centerm Q7 hardware. Every method probes for
 * that package first; on non-Q7 devices `isAvailable` returns false and
 * everything else throws `Q7_UNAVAILABLE`. That keeps the existing
 * Sunmi / Bluetooth code paths in [BluetoothPrintBridge] and the
 * upstream Flutter plugins completely untouched.
 *
 * Channel: `com.hermosaapp.q7printer`
 *
 * Methods:
 *   - `isAvailable` → bool (service package present AND SDK bind ok)
 *   - `init` → bool (forces a bind; usually done lazily)
 *   - `getStatus` → {code: int, msg: string, ready: bool}
 *   - `printBitmap` ({data: ByteArray PNG, feed: int}) → bool
 *   - `feed` ({lines: int}) → bool
 *
 * Concurrency: every print job runs on a dedicated single-thread
 * [HandlerThread] so two cashier receipts fired back-to-back can't
 * trample one another inside the SDK's binder pipeline. The MethodChannel
 * caller still gets an immediate ack via the invoked-on-main `Result`.
 *
 * Resource hygiene: every decoded [Bitmap] is `recycle()`d once both
 * the bitmap-print and trailing line-feed complete (or fail) — long
 * running shifts otherwise leak ~1 MB per receipt.
 */
class CentermQ7PrintBridge(
    private val appContext: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL = "com.hermosaapp.q7printer"
        private const val SERVICE_PKG = "com.pos.smartposservice"
        private const val TAG_LOG = "Q7Print"

        // After two consecutive bind failures, suppress further bind
        // attempts for this long. Without a circuit-breaker the bridge
        // hammers DevicesFactory.create on every isAvailable() call.
        private const val BIND_BACKOFF_MS = 30_000L

        // Q7 hardware is 58 mm only (sample SDK clamps paperWidth to
        // 30..58). At 8 dots/mm that's 464 px max raster, but the
        // service draws best at 384 px (the documented "thermal width"
        // for ESC/POS-class 58 mm heads). Bitmaps wider than this are
        // resampled on the way in so the SDK can't crop them silently.
        private const val MAX_RASTER_PX = 384
    }

    private val channel = MethodChannel(messenger, CHANNEL).also {
        it.setMethodCallHandler(this)
    }
    private val main = Handler(Looper.getMainLooper())

    // Single-thread serialiser. Print jobs queue here so concurrent
    // calls can't interleave inside the SDK.
    private val workerThread = HandlerThread("Q7PrintWorker").apply { start() }
    private val worker = Handler(workerThread.looper)

    @Volatile private var deviceManager: DeviceManager? = null
    @Volatile private var printer: PrinterDevice? = null
    private val binding = AtomicBoolean(false)

    @Volatile private var bindFailures = 0
    @Volatile private var nextBindAttemptAt = 0L

    // Cache the package-installed answer for a few seconds. Each call
    // would otherwise hit PackageManager which is comparatively slow.
    @Volatile private var lastServiceCheckAt = 0L
    @Volatile private var lastServiceInstalled = false

    private fun isServiceInstalled(): Boolean {
        val now = SystemClock.elapsedRealtime()
        if (now - lastServiceCheckAt < 5_000L) return lastServiceInstalled
        val present = try {
            appContext.packageManager.getPackageInfo(SERVICE_PKG, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        } catch (_: Throwable) {
            false
        }
        lastServiceInstalled = present
        lastServiceCheckAt = now
        return present
    }

    /**
     * Lazily binds the SDK. The callback is always invoked on the main
     * thread. Idempotent — concurrent callers all wait on the same
     * bind and short-circuit once we already have a printer.
     *
     * Implements a tiny circuit breaker so a permanently-broken service
     * (e.g. com.pos.smartposservice not the right build) doesn't make
     * every `isAvailable` call hammer the binder.
     */
    private fun ensureBound(onReady: (PrinterDevice?) -> Unit) {
        printer?.let { main.post { onReady(it) }; return }

        if (!isServiceInstalled()) {
            main.post { onReady(null) }
            return
        }

        val now = SystemClock.elapsedRealtime()
        if (now < nextBindAttemptAt) {
            // Still in the cooldown after a previous bind failure.
            main.post { onReady(null) }
            return
        }

        if (!binding.compareAndSet(false, true)) {
            // Another bind is already in flight — poll the field briefly.
            main.postDelayed({ ensureBound(onReady) }, 100)
            return
        }

        try {
            DevicesFactory.create(appContext, object : ResultCallback<DeviceManager> {
                override fun onFinish(dm: DeviceManager) {
                    deviceManager = dm
                    val p = try {
                        dm.printerDevice
                    } catch (t: Throwable) {
                        SunmiLog.e("$TAG_LOG: getPrinterDevice failed: ${t.message}", t)
                        null
                    }
                    printer = p
                    if (p != null) {
                        bindFailures = 0
                        nextBindAttemptAt = 0L
                        SunmiLog.i("$TAG_LOG: SDK bound; printer ready")
                    } else {
                        bindFailures += 1
                        nextBindAttemptAt = SystemClock.elapsedRealtime() +
                            BIND_BACKOFF_MS * minOf(bindFailures, 4)
                    }
                    binding.set(false)
                    main.post { onReady(p) }
                }

                override fun onError(code: Int, msg: String?) {
                    bindFailures += 1
                    nextBindAttemptAt = SystemClock.elapsedRealtime() +
                        BIND_BACKOFF_MS * minOf(bindFailures, 4)
                    binding.set(false)
                    SunmiLog.e(
                        "$TAG_LOG: SDK bind failed code=$code msg=$msg " +
                            "(failures=$bindFailures, next=${BIND_BACKOFF_MS}ms+)"
                    )
                    main.post { onReady(null) }
                }
            })
        } catch (t: Throwable) {
            bindFailures += 1
            nextBindAttemptAt = SystemClock.elapsedRealtime() + BIND_BACKOFF_MS
            binding.set(false)
            SunmiLog.e("$TAG_LOG: bind threw: ${t.message}", t)
            main.post { onReady(null) }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> {
                if (!isServiceInstalled()) {
                    result.success(false)
                    return
                }
                ensureBound { p -> result.success(p != null) }
            }

            "init" -> ensureBound { p -> result.success(p != null) }

            "getStatus" -> ensureBound { p ->
                if (p == null) {
                    result.error("Q7_UNAVAILABLE", "Q7 printer unavailable", null)
                    return@ensureBound
                }
                try {
                    val s: PrinterStatus = p.printerStatus
                    val code = s.stateCode
                    result.success(
                        mapOf(
                            "code" to code,
                            "msg" to (s.stateMsg ?: ""),
                            "ready" to (code == 0)
                        )
                    )
                } catch (t: Throwable) {
                    result.error("Q7_STATUS_FAILED", t.message, null)
                }
            }

            "printBitmap" -> {
                val data = call.argument<ByteArray>("data")
                val feed = call.argument<Int>("feed") ?: 3
                if (data == null || data.isEmpty()) {
                    result.error("BAD_ARGS", "data is null/empty", null)
                    return
                }
                ensureBound { p ->
                    if (p == null) {
                        result.error("Q7_UNAVAILABLE", "Q7 printer unavailable", null)
                        return@ensureBound
                    }
                    // Hand off to the worker thread so concurrent prints
                    // serialise. The MethodChannel result is fulfilled
                    // from the worker too.
                    worker.post { runPrintBitmap(p, data, feed, result) }
                }
            }

            "feed" -> {
                val lines = call.argument<Int>("lines") ?: 3
                ensureBound { p ->
                    if (p == null) {
                        result.error("Q7_UNAVAILABLE", "Q7 printer unavailable", null)
                        return@ensureBound
                    }
                    worker.post { runFeed(p, lines, result) }
                }
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Runs on [worker]. Decodes the PNG, downsamples to ≤
     * [MAX_RASTER_PX] wide if needed (the Q7 head is 58 mm = 384 dots),
     * sends it through the SDK, then issues the trailing line feed in
     * the same callback so the cut sits below the last printed row.
     * The decoded bitmap is recycled once everything completes.
     */
    private fun runPrintBitmap(
        p: PrinterDevice,
        data: ByteArray,
        feed: Int,
        result: MethodChannel.Result,
    ) {
        val decoded: Bitmap? = try {
            BitmapFactory.decodeByteArray(data, 0, data.size)
        } catch (t: Throwable) {
            SunmiLog.e("$TAG_LOG: decode bitmap failed: ${t.message}", t)
            null
        }
        if (decoded == null) {
            main.post { result.error("BAD_BITMAP", "could not decode PNG", null) }
            return
        }

        val toPrint: Bitmap = if (decoded.width > MAX_RASTER_PX) {
            val ratio = MAX_RASTER_PX.toFloat() / decoded.width
            val newH = (decoded.height * ratio).toInt().coerceAtLeast(1)
            val scaled = Bitmap.createScaledBitmap(
                decoded, MAX_RASTER_PX, newH, true
            )
            if (scaled !== decoded) decoded.recycle()
            scaled
        } else {
            decoded
        }

        // Latch so we recycle the bitmap exactly once even if both
        // the print callback and the feed callback fire (success path)
        // or only the print exception fires (error path).
        var done = false
        fun finish(successResult: Boolean?, errCode: String?, errMsg: String?) {
            if (done) return
            done = true
            try { toPrint.recycle() } catch (_: Throwable) {}
            main.post {
                if (errCode != null) {
                    result.error(errCode, errMsg, null)
                } else {
                    result.success(successResult ?: false)
                }
            }
        }

        try {
            p.setAlign(PrinterDevice.AlignType.CENTER)
            p.printBitmap(toPrint, object : InnerResultCallback.Stub() {
                @Throws(RemoteException::class)
                override fun onRunResult(b: Boolean) {
                    if (!b) {
                        finish(false, null, null)
                        return
                    }
                    if (feed <= 0) {
                        finish(true, null, null)
                        return
                    }
                    try {
                        p.printLines(feed, object : InnerResultCallback.Stub() {
                            override fun onRunResult(b2: Boolean) {
                                finish(b2, null, null)
                            }
                            override fun onReturnString(s: String?) {}
                            override fun onRaiseException(c: Int, s: String?) {
                                // Bitmap printed OK — surface success even
                                // if the trailing feed failed.
                                SunmiLog.w("$TAG_LOG: feed after print failed: $c $s")
                                finish(true, null, null)
                            }
                        })
                    } catch (t: Throwable) {
                        SunmiLog.w("$TAG_LOG: feed after print threw: ${t.message}")
                        finish(true, null, null)
                    }
                }

                override fun onReturnString(s: String?) {}

                @Throws(RemoteException::class)
                override fun onRaiseException(code: Int, msg: String?) {
                    SunmiLog.e("$TAG_LOG: printBitmap exception code=$code msg=$msg")
                    finish(null, "Q7_PRINT_FAILED", "code=$code msg=$msg")
                }
            })
        } catch (t: Throwable) {
            SunmiLog.e("$TAG_LOG: printBitmap threw: ${t.message}", t)
            finish(null, "Q7_PRINT_FAILED", t.message)
        }
    }

    private fun runFeed(p: PrinterDevice, lines: Int, result: MethodChannel.Result) {
        try {
            p.printLines(lines, object : InnerResultCallback.Stub() {
                override fun onRunResult(b: Boolean) {
                    main.post { result.success(b) }
                }
                override fun onReturnString(s: String?) {}
                override fun onRaiseException(code: Int, msg: String?) {
                    main.post {
                        result.error("Q7_FEED_FAILED", "code=$code msg=$msg", null)
                    }
                }
            })
        } catch (t: Throwable) {
            main.post { result.error("Q7_FEED_FAILED", t.message, null) }
        }
    }

    fun dispose() {
        try {
            channel.setMethodCallHandler(null)
        } catch (_: Throwable) {
        }
        try {
            workerThread.quitSafely()
        } catch (_: Throwable) {
        }
        printer = null
        deviceManager = null
    }
}
