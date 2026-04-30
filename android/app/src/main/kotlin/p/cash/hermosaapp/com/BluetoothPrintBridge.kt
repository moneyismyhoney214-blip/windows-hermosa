package p.cash.hermosaapp.com

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.InvocationTargetException
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/**
 * Robust Bluetooth print transport for thermal printers — including the
 * common Chinese 58mm/80mm receipt printers that ship with a PIN pairing
 * (0000 / 1234 / 8888).
 *
 * Why this exists: the upstream `flutter_bluetooth_printer` plugin only
 * tries a *secure* RFCOMM connect (`createRfcommSocketToServiceRecord`).
 * That fails for two real-world cases we hit on the floor:
 *
 *   1. The printer is visible in the OS Bluetooth list but not yet paired.
 *      The implicit pairing the secure connect triggers either races, gets
 *      hidden behind the Flutter window, or times out before the cashier
 *      types the PIN.
 *
 *   2. The printer is paired but its firmware refuses the secure SDP
 *      lookup and only accepts an *insecure* RFCOMM channel (port 1).
 *      That path is the de-facto Android workaround for cheap thermal
 *      printers — accessible only via reflection (`createRfcommSocket`).
 *
 * This bridge handles both: it forces a bond before connecting (waiting
 * synchronously on a BroadcastReceiver), then tries secure → insecure →
 * fallback-discovery cancel before sending bytes. Each `printBytes` call
 * opens a fresh socket and closes it, so a stuck socket from a previous
 * job never poisons the next one.
 */
class BluetoothPrintBridge(
    private val context: Context,
    messenger: BinaryMessenger
) {
    companion object {
        private const val CHANNEL = "com.hermosaapp.bluetooth_print"
        private val SPP_UUID: UUID =
            UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private const val BOND_TIMEOUT_MS = 30_000L
        private const val WRITE_CHUNK = 512
    }

    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor { r ->
        Thread(r, "bt-print-bridge").apply { isDaemon = true }
    }
    private val channel = MethodChannel(messenger, CHANNEL)
    private val adapter: BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)
            ?.adapter

    init {
        channel.setMethodCallHandler { call, result ->
            handle(call, result)
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        io.shutdownNow()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isBluetoothAvailable" -> result.success(adapter != null)
            "isBluetoothEnabled" -> result.success(adapter?.isEnabled == true)
            "isBonded" -> {
                val address = call.argument<String>("address")
                if (address.isNullOrBlank()) {
                    result.error("INVALID_ADDRESS", "address is required", null)
                    return
                }
                result.success(currentBondState(address) == BluetoothDevice.BOND_BONDED)
            }
            "getBondedDevices" -> {
                if (!hasConnectPermission()) {
                    result.error(
                        "PERMISSION_DENIED",
                        "BLUETOOTH_CONNECT permission not granted",
                        null
                    )
                    return
                }
                val a = adapter
                if (a == null) {
                    result.success(emptyList<Map<String, Any?>>())
                    return
                }
                val out = a.bondedDevices.map { dev ->
                    mapOf(
                        "name" to (dev.name ?: ""),
                        "address" to dev.address
                    )
                }
                result.success(out)
            }
            "bondDevice" -> {
                val address = call.argument<String>("address")
                if (address.isNullOrBlank()) {
                    result.error("INVALID_ADDRESS", "address is required", null)
                    return
                }
                io.execute {
                    try {
                        val ok = ensureBonded(address)
                        main.post { result.success(ok) }
                    } catch (t: Throwable) {
                        main.post {
                            result.error(
                                "BOND_FAILED",
                                t.message ?: "bond failed",
                                null
                            )
                        }
                    }
                }
            }
            "printBytes" -> {
                val address = call.argument<String>("address")
                val data = call.argument<ByteArray>("data")
                if (address.isNullOrBlank() || data == null) {
                    result.error(
                        "INVALID_ARGS",
                        "address and data are required",
                        null
                    )
                    return
                }
                io.execute {
                    try {
                        sendBytes(address, data)
                        main.post { result.success(true) }
                    } catch (t: Throwable) {
                        main.post {
                            result.error(
                                "PRINT_FAILED",
                                t.message ?: "print failed",
                                t.stackTraceToString()
                            )
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------
    //  Connection / send
    // -------------------------------------------------------------------

    private fun sendBytes(address: String, data: ByteArray) {
        val a = adapter ?: throw IllegalStateException("Bluetooth not available")
        if (!a.isEnabled) throw IllegalStateException("Bluetooth disabled")
        if (!hasConnectPermission()) {
            throw SecurityException("BLUETOOTH_CONNECT permission missing")
        }

        // Discovery wrecks RFCOMM throughput and frequently causes connect()
        // to time out on cheap printers. Cancel before any socket attempt.
        try { if (a.isDiscovering) a.cancelDiscovery() } catch (_: Throwable) {}

        // Make sure the device is paired before opening the RFCOMM socket.
        // For printers with a PIN this triggers the system pairing dialog.
        val bonded = ensureBonded(address)
        if (!bonded) {
            throw IllegalStateException(
                "Pairing not completed for $address — " +
                    "approve the system pairing prompt or pair manually in Bluetooth settings"
            )
        }

        val device = a.getRemoteDevice(address)

        var socket: BluetoothSocket? = null
        var lastError: Throwable? = null

        // Attempt 1: secure SPP via SDP lookup.
        try {
            socket = device.createRfcommSocketToServiceRecord(SPP_UUID)
            socket.connect()
        } catch (t: Throwable) {
            lastError = t
            safeClose(socket)
            socket = null
        }

        // Attempt 2: insecure SPP via SDP lookup.
        if (socket == null) {
            try {
                socket = device.createInsecureRfcommSocketToServiceRecord(SPP_UUID)
                socket.connect()
            } catch (t: Throwable) {
                lastError = t
                safeClose(socket)
                socket = null
            }
        }

        // Attempt 3: hidden reflection-based RFCOMM channel 1. This is the
        // path that finally works on printers whose firmware refuses SDP.
        if (socket == null) {
            try {
                val m = device.javaClass.getMethod(
                    "createRfcommSocket", Int::class.javaPrimitiveType
                )
                socket = m.invoke(device, 1) as BluetoothSocket
                socket.connect()
            } catch (t: Throwable) {
                lastError = unwrap(t)
                safeClose(socket)
                socket = null
            }
        }

        // Attempt 4: insecure variant of the reflection path.
        if (socket == null) {
            try {
                val m = device.javaClass.getMethod(
                    "createInsecureRfcommSocket", Int::class.javaPrimitiveType
                )
                socket = m.invoke(device, 1) as BluetoothSocket
                socket.connect()
            } catch (t: Throwable) {
                lastError = unwrap(t)
                safeClose(socket)
                socket = null
            }
        }

        if (socket == null) {
            throw IllegalStateException(
                "Failed to open RFCOMM to $address: ${lastError?.message}"
            )
        }

        try {
            val out = socket.outputStream
            val input = socket.inputStream

            // Drain any stale bytes the printer might have left in our
            // RX queue from a previous session before we start writing.
            // Without this, an old status reply could mix with ours and
            // confuse the drain step at the end.
            try {
                while (input.available() > 0) {
                    val skip = ByteArray(input.available())
                    input.read(skip)
                }
            } catch (_: Throwable) {}

            // Stream in small chunks — some printer firmwares choke when an
            // 8 KB raster blob arrives in a single write.
            var offset = 0
            while (offset < data.size) {
                val len = minOf(WRITE_CHUNK, data.size - offset)
                out.write(data, offset, len)
                out.flush()
                offset += len
            }

            // ── Trailer — the actual fix for "next app's print shows our
            //    receipt" ───────────────────────────────────────────────
            //
            // Cheap thermal printers keep an internal MCU job buffer that
            // survives a Bluetooth disconnect. If we close the socket while
            // ANY of our payload is still queued (raster bytes mid-stream,
            // a partial command waiting for parameters, or even just bytes
            // sitting in the OS RFCOMM TX queue), the printer holds onto
            // them — and the very next app that connects ends up printing
            // *our* leftover content before its own.
            //
            // This trailer guarantees a clean handoff. The sequence is
            // ordered carefully because of how ESC/POS parsers work:
            //
            //   1. 64 bytes of 0x00 — saturates any command still waiting
            //      for parameter bytes (e.g. an in-flight `GS v 0` raster
            //      whose declared height ran out before its data did). 64
            //      is well above any real-world parameter count.
            //   2. `ESC @` (0x1B 0x40) — once the parser is idle, this
            //      hard-resets it: clears any active modes (bold, double
            //      width, alignment, etc.) and goes back to default state.
            //   3. `DLE EOT 1` (0x10 0x04 0x01) — real-time status query.
            //      Per the ESC/POS spec, this is processed *immediately*
            //      regardless of buffer state, AND the printer's reply is
            //      held until prior buffered bytes have been processed.
            //      Round-tripping it = hard proof the entire payload has
            //      been consumed before we close the socket.
            //   4. Read until we see the reply, with a 3 s ceiling. We
            //      block on read() in 250 ms slices via available()-poll
            //      so the kernel is forced to actually retrieve the byte.
            //   5. Final 600 ms sleep so the cutter finishes its mechanical
            //      pass on long receipts before the link drops.
            try {
                val trailer = ByteArray(64) +                  // null padding first
                    byteArrayOf(0x1B, 0x40) +                  // ESC @ reset
                    byteArrayOf(0x10, 0x04, 0x01)              // DLE EOT 1
                out.write(trailer)
                out.flush()

                // Wait for the status byte. The reply arriving is proof
                // that everything before it has been parsed and acted on.
                val deadline = System.currentTimeMillis() + 3_000L
                var got = false
                while (System.currentTimeMillis() < deadline) {
                    val avail = try { input.available() } catch (_: Throwable) { 0 }
                    if (avail > 0) {
                        // Drain everything the printer sent — usually one
                        // status byte, but absorb more in case the firmware
                        // pushed multiple replies or buffered status frames.
                        try {
                            val buf = ByteArray(avail)
                            input.read(buf)
                            // Grab any trailing bytes that landed during read.
                            Thread.sleep(50)
                            val more = try { input.available() } catch (_: Throwable) { 0 }
                            if (more > 0) {
                                input.read(ByteArray(more))
                            }
                        } catch (_: Throwable) {}
                        got = true
                        break
                    }
                    try { Thread.sleep(50) } catch (_: InterruptedException) {}
                }

                // If the printer never replied (some clones ignore DLE EOT
                // entirely), still give the OS RFCOMM stack time to drain
                // its TX queue to the controller. 800 ms is the empirical
                // floor that survives the L2CAP retransmit window on the
                // worst BT chips we've seen on cheap printers.
                val postSleep = if (got) 600L else 800L
                try { Thread.sleep(postSleep) } catch (_: InterruptedException) {}
            } catch (_: Throwable) {
                // Trailer is best-effort — never fail the print over it.
                // The user's receipt already printed before this block runs.
            }
        } finally {
            safeClose(socket)
        }
    }

    // -------------------------------------------------------------------
    //  Bonding
    // -------------------------------------------------------------------

    private fun currentBondState(address: String): Int {
        val a = adapter ?: return BluetoothDevice.BOND_NONE
        return try {
            a.getRemoteDevice(address).bondState
        } catch (_: Throwable) {
            BluetoothDevice.BOND_NONE
        }
    }

    /**
     * Block the caller (already on the IO thread) until the device is
     * bonded or until [BOND_TIMEOUT_MS] elapses.  Returns whether the bond
     * was achieved.  Safe to call when the device is already bonded.
     */
    private fun ensureBonded(address: String): Boolean {
        val a = adapter ?: return false
        if (!hasConnectPermission()) {
            throw SecurityException("BLUETOOTH_CONNECT permission missing")
        }
        val device = a.getRemoteDevice(address)
        if (device.bondState == BluetoothDevice.BOND_BONDED) return true

        val lock = Object()
        val finalState = AtomicInteger(device.bondState)

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                if (intent.action != BluetoothDevice.ACTION_BOND_STATE_CHANGED) return
                val target: BluetoothDevice? = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(
                        BluetoothDevice.EXTRA_DEVICE,
                        BluetoothDevice::class.java
                    )
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                }
                if (target?.address != address) return
                val state = intent.getIntExtra(
                    BluetoothDevice.EXTRA_BOND_STATE,
                    BluetoothDevice.BOND_NONE
                )
                if (state == BluetoothDevice.BOND_BONDED ||
                    state == BluetoothDevice.BOND_NONE
                ) {
                    finalState.set(state)
                    synchronized(lock) { lock.notifyAll() }
                }
            }
        }

        val filter = IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        // RECEIVER_NOT_EXPORTED on API 34+; older paths use the legacy form.
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }

        try {
            // Kick off pairing. createBond() is async — the result arrives on
            // the BroadcastReceiver above. If it returns false the device is
            // already bonding/bonded or the request was rejected outright.
            if (device.bondState != BluetoothDevice.BOND_BONDING) {
                device.createBond()
            }

            val deadline = System.currentTimeMillis() + BOND_TIMEOUT_MS
            synchronized(lock) {
                while (finalState.get() != BluetoothDevice.BOND_BONDED &&
                    finalState.get() != BluetoothDevice.BOND_NONE
                ) {
                    val remaining = deadline - System.currentTimeMillis()
                    if (remaining <= 0) break
                    try { lock.wait(remaining) } catch (_: InterruptedException) { break }
                }
            }
        } finally {
            try { context.unregisterReceiver(receiver) } catch (_: Throwable) {}
        }

        return device.bondState == BluetoothDevice.BOND_BONDED
    }

    // -------------------------------------------------------------------
    //  Helpers
    // -------------------------------------------------------------------

    private fun hasConnectPermission(): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true
        return ContextCompat.checkSelfPermission(
            context, Manifest.permission.BLUETOOTH_CONNECT
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun safeClose(socket: BluetoothSocket?) {
        if (socket == null) return
        try { socket.close() } catch (_: Throwable) {}
    }

    private fun unwrap(t: Throwable): Throwable =
        if (t is InvocationTargetException) t.targetException ?: t else t
}
