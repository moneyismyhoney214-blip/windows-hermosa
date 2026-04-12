package com.example.flutter_terminal_sdk

import android.content.Context
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Writes NearPay SDK logs to:
 * /storage/emulated/0/Android/data/<appId>/files/logs/nearpay_sdk_YYYYMMDD.log
 */
class NearpayFileLogTree(
    private val context: Context,
) : timber.log.Timber.Tree() {

    private val lock = Any()

    override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
        val level = when (priority) {
            Log.VERBOSE -> "V"
            Log.DEBUG -> "D"
            Log.INFO -> "I"
            Log.WARN -> "W"
            Log.ERROR -> "E"
            Log.ASSERT -> "A"
            else -> "?"
        }

        val timestamp = TS_FORMAT.format(Date())
        val safeTag = tag ?: "NearPaySDK"
        val builder = StringBuilder()
            .append(timestamp)
            .append(" [")
            .append(level)
            .append("/")
            .append(safeTag)
            .append("] ")
            .append(message)

        if (t != null) {
            builder.append('\n').append(Log.getStackTraceString(t))
        }

        writeLine(builder.toString())
    }

    private fun writeLine(line: String) {
        synchronized(lock) {
            try {
                val baseDir = context.getExternalFilesDir(null) ?: return
                val logsDir = File(baseDir, "logs")
                if (!logsDir.exists()) {
                    logsDir.mkdirs()
                }

                cleanupOldLogs(logsDir)

                val fileName = "nearpay_sdk_${DATE_STAMP.format(Date())}.log"
                val file = File(logsDir, fileName)
                file.appendText(line + "\n")
            } catch (_: Throwable) {
                // Silent by design
            }
        }
    }

    private fun cleanupOldLogs(logsDir: File) {
        val today = DATE_ONLY.format(Date())
        if (lastCleanupDay == today) return
        lastCleanupDay = today

        val cutoff = System.currentTimeMillis() - DAYS_7_MS
        val files = logsDir.listFiles() ?: return
        for (file in files) {
            val match = FILE_REGEX.matchEntire(file.name) ?: continue
            val y = match.groupValues[1].toIntOrNull() ?: continue
            val m = match.groupValues[2].toIntOrNull() ?: continue
            val d = match.groupValues[3].toIntOrNull() ?: continue
            val dateMillis = SimpleDateFormat("yyyyMMdd", Locale.US)
                .parse(String.format(Locale.US, "%04d%02d%02d", y, m, d))?.time
                ?: continue
            if (dateMillis < cutoff) {
                try {
                    file.delete()
                } catch (_: Throwable) {
                    // Silent by design
                }
            }
        }
    }

    private companion object {
        private val TS_FORMAT = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
        private val DATE_STAMP = SimpleDateFormat("yyyyMMdd", Locale.US)
        private val DATE_ONLY = SimpleDateFormat("yyyyMMdd", Locale.US)
        private val FILE_REGEX = Regex("""^nearpay_sdk_(\d{4})(\d{2})(\d{2})\.log$""")
        private const val DAYS_7_MS = 7L * 24 * 60 * 60 * 1000
        private var lastCleanupDay: String? = null
    }
}
