package com.example.flutter_terminal_sdk.common.operations

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import io.nearpay.terminalsdk.data.dto.TransactionResponse
import io.nearpay.terminalsdk.utils.BitmapListener
import io.nearpay.terminalsdk.utils.toImage
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import timber.log.Timber
import java.io.ByteArrayOutputStream
import java.util.concurrent.atomic.AtomicBoolean

class ToImageOperation(provider: NearpayProvider) : BaseOperation(provider) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val mainHandler = Handler(Looper.getMainLooper())

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
        explicitNulls = false
    }

    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {
        val activity = provider.activity
        if (activity == null) {
            mainHandler.post {
                response(ResponseHandler.error("NO_ACTIVITY", "Activity is null"))
            }
            return
        }

        val receiptWidth = filter.getInt("receiptWidth")
        val fontSize = filter.getInt("fontSize")
        val receiptPayload = filter.getString("receiptPayload")
        if (receiptPayload.isNullOrBlank()) {
            mainHandler.post {
                response(ResponseHandler.error("MISSING_receiptPayload", "receiptPayload is required"))
            }
            return
        }

        // If your payload sometimes misses required fields (e.g., merchant.category_code),
        // you can uncomment this line to patch it before decoding.
        // val patchedPayload = patchMissingFields(receiptPayload)
        val patchedPayload = receiptPayload

        val receipt: TransactionResponse.Event.ReceiptData = try {
            json.decodeFromString(
                TransactionResponse.Event.ReceiptData.serializer(),
                patchedPayload
            ).also { Timber.d("Receipt Payload decoded") }
        } catch (t: Throwable) {
            Timber.e(t, "Failed to decode receipt payload")
            mainHandler.post {
                response(ResponseHandler.error("BAD_JSON", t.localizedMessage ?: "Invalid receipt payload"))
            }
            return
        }

        // Ensure we only ever reply once, even if the SDK calls the listener multiple times
        val replied = AtomicBoolean(false)
        fun replyOnce(map: Map<String, Any>) {
            if (replied.compareAndSet(false, true)) {
                mainHandler.post { response(map) }
            } else {
                Timber.w("Reply already sent; dropping extra callback")
            }
        }

        try {
            receipt.toImage(
                context = activity,
                receiptWidth = receiptWidth,
                fontSize = fontSize,
                listener = BitmapListener { bitmap ->
                    if (bitmap == null) {
                        replyOnce(ResponseHandler.error("BITMAP_NULL", "SDK returned null bitmap"))
                        return@BitmapListener
                    }

                    // Heavy work off main thread (PNG compression)
                    scope.launch {
                        try {
                            val pngBytes = bitmapToPng(bitmap)
                            Timber.d("Receipt Image generated. ${pngBytes.size} bytes")
                            replyOnce(
                                ResponseHandler.success(
                                    message = "Receipt Image generated.",
                                    data = pngBytes
                                )
                            )
                        } catch (t: Throwable) {
                            Timber.e(t, "PNG encoding failed")
                            replyOnce(ResponseHandler.error("PNG_ENCODE_FAILED", t.localizedMessage ?: "PNG encoding failed"))
                        }
                    }
                }
            )
        } catch (t: Throwable) {
            Timber.e(t, "toImage() call failed")
            replyOnce(ResponseHandler.error("TO_IMAGE_FAILED", t.localizedMessage ?: "toImage failed"))
        }
    }

    private fun bitmapToPng(bitmap: Bitmap): ByteArray {
        val stream = ByteArrayOutputStream()
        if (!bitmap.compress(Bitmap.CompressFormat.PNG, /*quality ignored*/100, stream)) {
            throw IllegalStateException("Bitmap.compress returned false")
        }
        return stream.toByteArray()
    }

    // Optional: patch JSON if backend sometimes omits required fields.
    // Adjust as needed for your schema.
    @Suppress("unused")
    private fun patchMissingFields(raw: String): String {
        val root = runCatching { json.parseToJsonElement(raw) as? JsonObject }.getOrNull() ?: return raw
        val patchedRoot = JsonObject(root + buildMap {
            val merchant = root["merchant"] as? JsonObject
            if (merchant != null && "category_code" !in merchant) {
                put("merchant", JsonObject(merchant + mapOf("category_code" to JsonPrimitive(""))))
            }
        })
        return json.encodeToString(JsonObject.serializer(), patchedRoot)
    }
}
