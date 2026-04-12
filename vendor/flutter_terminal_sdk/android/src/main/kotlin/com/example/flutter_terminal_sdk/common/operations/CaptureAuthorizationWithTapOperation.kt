package com.example.flutter_terminal_sdk.common.operations

import android.os.Handler
import android.os.Looper
import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import com.google.gson.Gson
import io.nearpay.terminalsdk.data.dto.CaptureResponse
import io.nearpay.terminalsdk.listeners.CaptureAuthorizationListener
import io.nearpay.terminalsdk.listeners.CaptureAuthorizationWithTapListener
import io.nearpay.terminalsdk.listeners.ReadCardListener
import io.nearpay.terminalsdk.listeners.failures.CaptureAuthorizationFailure
import io.nearpay.terminalsdk.listeners.failures.CaptureAuthorizationWithTapFailure
import io.nearpay.terminalsdk.listeners.failures.ReadCardFailure
import timber.log.Timber

class CaptureAuthorizationWithTapOperation(provider: NearpayProvider) : BaseOperation(provider) {
    private val gson = Gson()
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {

        val terminalUUID = filter.getString("terminalUUID")
            ?: return response(ResponseHandler.error("MISSING_UUID", "Terminal uuid is required"))

        val amount = filter.getLong("amount")
            ?: return response(ResponseHandler.error("MISSING_AMOUNT", "Amount is required"))


        val uuid = filter.getString("uuid")
            ?: return response(ResponseHandler.error("MISSING_UUID", "UUID is required"))

        val authorizationUuid = filter.getString("authorizationUuid")
            ?: return response(
                ResponseHandler.error(
                    "MISSING_AUTHORIZATION_UUID",
                    "Authorization UUID is required"
                )
            )


        val terminal =
            provider.activity?.let { provider.terminalSdk?.getTerminal(it, terminalUUID) }

        terminal?.captureAuthorizationWithTap(
            amount = amount,
            uuid = uuid,
            authorizationUuid = authorizationUuid,
            readCardListener = object : ReadCardListener {
                override fun onReaderClosed() {
                    Timber.tag("CaptureAuthorizationWithTapOperation").d("onReaderClosed")
                    sendCaptureAuthorizationWithTapEvent(uuid, "readerClosed", null, null)
                }

                override fun onReaderDismissed() {
                    Timber.tag("CaptureAuthorizationWithTapOperation").d("onReaderDismissed")
                    sendCaptureAuthorizationWithTapEvent(uuid, "readerDismissed", null, null)
                }

                override fun onReaderDisplayed() {
                    Timber.tag("CaptureAuthorizationWithTapOperation").d("onReaderDisplayed")
                    sendCaptureAuthorizationWithTapEvent(uuid, "readerDisplayed", null, null)
                }

                override fun onReadCardSuccess() {
                    Timber.tag("CaptureAuthorizationWithTapOperation").d("onReadCardSuccess")
                    sendCaptureAuthorizationWithTapEvent(
                        uuid,
                        "cardReadSuccess",
                        "Card read successfully",
                        null
                    )
                }

                override fun onReadCardFailure(readCardFailure: ReadCardFailure) {
                    Timber.tag("CaptureAuthorizationWithTapOperation")
                        .d("onReadCardFailure $readCardFailure")
                    sendCaptureAuthorizationWithTapEvent(
                        uuid,
                        "cardReadFailure",
                        readCardFailure.toString(),
                        null
                    )
                }

                override fun onReaderWaiting() {
                    Timber.tag("CaptureAuthorizationWithTapOperation").d("onReaderWaiting")
                    sendCaptureAuthorizationWithTapEvent(uuid, "readerWaiting", null, null)
                }

                override fun onReaderReading() {
                    Timber.tag("CaptureAuthorizationWithTapOperation").d("onReaderReading")
                    sendCaptureAuthorizationWithTapEvent(uuid, "readerReading", null, null)
                }

                override fun onReaderRetry() {
                    Timber.tag("CaptureAuthorizationWithTapOperation").d("onReaderRetry")
                    sendCaptureAuthorizationWithTapEvent(uuid, "readerRetry", null, null)
                }

                override fun onPinEntering() {
                    Timber.tag("CaptureAuthorizationWithTapOperation").d("onPinEntering")
                    sendCaptureAuthorizationWithTapEvent(uuid, "pinEntering", null, null)
                }

                override fun onReaderFinished() {
                    Timber.tag("CaptureAuthorizationWithTapOperation").d("onReaderFinished")
                    sendCaptureAuthorizationWithTapEvent(uuid, "readerFinished", null, null)
                }

                override fun onReaderError(error: String?) {
                    Timber.tag("CaptureAuthorizationWithTapOperation").d("onReaderError $error")
                    sendCaptureAuthorizationWithTapEvent(
                        uuid,
                        "readerError",
                        error ?: "Unknown reader error",
                        null
                    )
                }

                override fun onReadingStarted() {
                    Timber.tag("CaptureAuthorizationWithTapOperation").d("onReadingStarted")
                    sendCaptureAuthorizationWithTapEvent(uuid, "readingStarted", null, null)
                }
            },
            captureAuthorizationWithTapListener = object : CaptureAuthorizationWithTapListener {

                override fun onCaptureAuthorizationWithTapCompleted(captureAuthorization: CaptureResponse) {
                    Timber.tag("CaptureAuthorizationWithTapOperation")
                        .d("onCaptureAuthorizationWithTapCompleted $captureAuthorization")
                    val jsonString = gson.toJson(captureAuthorization)
                    val map = gson.fromJson(jsonString, Map::class.java) as Map<*, *>
                    sendCaptureAuthorizationWithTapEvent(
                        uuid,
                        "captureWithTapCompleted",
                        null,
                        map
                    )
                }

                override fun onCaptureAuthorizationWithTapFailure(captureAuthorizationFailure: CaptureAuthorizationWithTapFailure) {
                    Timber.tag("CaptureAuthorizationWithTapOperation")
                        .d("onCaptureAuthorizationWithTapFailure $captureAuthorizationFailure")

                    val captureAuthorizationFailure = when (captureAuthorizationFailure) {
                        is CaptureAuthorizationWithTapFailure.Failure -> {
                            captureAuthorizationFailure.message
                        }

                    }

                    sendCaptureAuthorizationWithTapEvent(
                        uuid,
                        "sendTransactionFailure",
                        captureAuthorizationFailure,
                        null
                    )
                }

            }
        )

    }

    private fun sendCaptureAuthorizationWithTapEvent(
        uuid: String,
        eventType: String,
        message: String?,
        data: Any?
    ) {
        val eventArgs = mutableMapOf<String, Any>(
            "uuid" to uuid,
            "type" to eventType
        )
        message?.let { eventArgs["message"] = it }
        data?.let { eventArgs["data"] = it }

        try {
            Handler(Looper.getMainLooper()).post {
                provider.methodChannel.invokeMethod("captureAuthorizationWithTapEvent", eventArgs)
            }

        } catch (e: Exception) {
            // Log the error but do not disrupt the purchase flow
            Timber.e(
                e,
                "Failed to send captureAuthorizationWithTap event: $eventType for uuid: $uuid with error: ${e.message}"
            )
            throw e
        }
    }


}