package p.cash.hermosaapp.com

import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Build
import android.util.Log
import android.view.Display
import java.io.File
import java.io.FileWriter
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Centralized diagnostic logger for the Sunmi / dual-screen bring-up.
 *
 * Writes every entry to:
 *   1. Android logcat (tag "Sunmi")  →  adb logcat -s Sunmi
 *   2. A text file on external storage  →
 *      /sdcard/Android/data/p.cash.hermosaapp.com/files/sunmi_log.txt
 *
 * The friend running the app can pull the file over USB or attach it
 * from a file manager — no adb required.
 *
 * Thread-safe: all disk writes are synchronized so concurrent calls from
 * the main thread, display listener and Flutter engine thread don't
 * interleave half-lines.
 */
object SunmiLog {
    private const val TAG = "Sunmi"
    private const val FILE_NAME = "sunmi_log.txt"
    private const val MAX_FILE_BYTES: Long = 2 * 1024 * 1024 // 2 MB rolling cap

    private val timeFmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
    private val writeLock = Any()

    @Volatile private var logFile: File? = null
    @Volatile private var initialized = false

    /**
     * Binds the logger to the app's external files dir and writes a
     * session-boundary banner plus a device-info snapshot. Safe to call
     * multiple times — only the first call actually initializes.
     */
    fun init(context: Context) {
        if (initialized) return
        synchronized(writeLock) {
            if (initialized) return
            try {
                val dir = context.getExternalFilesDir(null)
                    ?: context.filesDir
                if (!dir.exists()) dir.mkdirs()
                val f = File(dir, FILE_NAME)

                // Rotate if the file has ballooned across many sessions.
                if (f.exists() && f.length() > MAX_FILE_BYTES) {
                    val rolled = File(dir, "$FILE_NAME.old")
                    if (rolled.exists()) rolled.delete()
                    f.renameTo(rolled)
                }

                logFile = f
                initialized = true
            } catch (t: Throwable) {
                Log.e(TAG, "SunmiLog init failed: ${t.message}", t)
            }
        }

        logBanner()
        logDeviceSnapshot(context)
    }

    /** Returns the absolute path of the log file, or null if not ready. */
    fun path(): String? = logFile?.absolutePath

    fun d(msg: String) = write("D", msg, null)
    fun i(msg: String) = write("I", msg, null)
    fun w(msg: String) = write("W", msg, null)
    fun e(msg: String, t: Throwable? = null) = write("E", msg, t)

    /**
     * Dump every display Android knows about right now, with all flags
     * decoded. This is the single most useful call for diagnosing why
     * the CDS won't launch on real Sunmi hardware.
     */
    fun dumpAllDisplays(context: Context, reason: String) {
        try {
            val dm = context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
            val all = dm.displays
            val presentation =
                dm.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
            i("=== Display snapshot [$reason] ===")
            i("  total displays: ${all.size}")
            i("  presentation-category displays: ${presentation.size}")
            for (d in all) {
                describeDisplay(d, isPresentationCategory = presentation.any { it.displayId == d.displayId })
            }
            i("=== end display snapshot ===")
        } catch (t: Throwable) {
            e("dumpAllDisplays crashed", t)
        }
    }

    private fun describeDisplay(d: Display, isPresentationCategory: Boolean) {
        val flags = d.flags
        val flagNames = buildList {
            if (flags and Display.FLAG_PRIVATE != 0) add("PRIVATE")
            if (flags and Display.FLAG_PRESENTATION != 0) add("PRESENTATION")
            if (flags and Display.FLAG_SECURE != 0) add("SECURE")
            if (flags and Display.FLAG_SUPPORTS_PROTECTED_BUFFERS != 0) add("PROTECTED_BUFFERS")
            if (flags and Display.FLAG_ROUND != 0) add("ROUND")
        }
        val flagText = if (flagNames.isEmpty()) "<none>" else flagNames.joinToString("|")
        val state = when (d.state) {
            Display.STATE_OFF -> "OFF"
            Display.STATE_ON -> "ON"
            Display.STATE_DOZE -> "DOZE"
            Display.STATE_DOZE_SUSPEND -> "DOZE_SUSPEND"
            Display.STATE_VR -> "VR"
            Display.STATE_ON_SUSPEND -> "ON_SUSPEND"
            else -> "UNKNOWN(${d.state})"
        }
        val mode = d.mode
        i(
            "  display id=${d.displayId} name='${d.name}' " +
                "state=$state flags=0x${Integer.toHexString(flags)}[$flagText] " +
                "presentationCategory=$isPresentationCategory " +
                "mode=${mode.physicalWidth}x${mode.physicalHeight}@${mode.refreshRate} " +
                "rotation=${d.rotation}"
        )
    }

    private fun logBanner() {
        val divider = "━".repeat(60)
        i(divider)
        i("SunmiLog session start — ${timeFmt.format(Date())}")
        i("log file: ${logFile?.absolutePath ?: "<unavailable>"}")
        i(divider)
    }

    private fun logDeviceSnapshot(context: Context) {
        try {
            i("device.manufacturer = ${Build.MANUFACTURER}")
            i("device.brand        = ${Build.BRAND}")
            i("device.model        = ${Build.MODEL}")
            i("device.device       = ${Build.DEVICE}")
            i("device.product      = ${Build.PRODUCT}")
            i("device.hardware     = ${Build.HARDWARE}")
            i("device.fingerprint  = ${Build.FINGERPRINT}")
            i("android.sdk         = ${Build.VERSION.SDK_INT} (${Build.VERSION.RELEASE})")
            dumpAllDisplays(context, "initial")
        } catch (t: Throwable) {
            e("logDeviceSnapshot crashed", t)
        }
    }

    private fun write(level: String, msg: String, throwable: Throwable?) {
        // Logcat first — cheap, non-blocking, survives even if file write fails.
        when (level) {
            "D" -> Log.d(TAG, msg)
            "I" -> Log.i(TAG, msg)
            "W" -> Log.w(TAG, msg)
            "E" -> if (throwable != null) Log.e(TAG, msg, throwable) else Log.e(TAG, msg)
        }

        val file = logFile ?: return
        val line = buildString {
            append(timeFmt.format(Date()))
            append(' ')
            append(level)
            append(' ')
            append(msg)
            if (throwable != null) {
                append('\n')
                val sw = StringWriter()
                throwable.printStackTrace(PrintWriter(sw))
                append(sw.toString().trimEnd())
            }
            append('\n')
        }

        synchronized(writeLock) {
            try {
                FileWriter(file, true).use { it.append(line) }
            } catch (t: Throwable) {
                Log.e(TAG, "file write failed: ${t.message}", t)
            }
        }
    }
}
