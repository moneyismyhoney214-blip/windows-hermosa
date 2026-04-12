package com.example.flutter_terminal_sdk.common.operations

import android.os.Handler
import android.os.Looper
import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import com.google.gson.Gson
import io.nearpay.terminalsdk.data.dto.AuthorizeResponse
import io.nearpay.terminalsdk.data.dto.PaymentScheme
import io.nearpay.terminalsdk.listeners.ReadCardListener
import io.nearpay.terminalsdk.listeners.failures.AuthorizeFailure
import io.nearpay.terminalsdk.listeners.failures.ReadCardFailure
import timber.log.Timber

class AuthorizeOperation(provider: NearpayProvider) : BaseOperation(provider) {
    private val gson = Gson()
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {

        val terminalUUID = filter.getString("terminalUUID")
            ?: return response(ResponseHandler.error("MISSING_UUID", "Terminal uuid is required"))

        val amount = filter.getLong("amount") ?: return response(
            ResponseHandler.error(
                "MISSING_AMOUNT", "Amount is required"
            )
        )

        val schemeString = filter.getString("scheme")
        val scheme = schemeString?.uppercase()?.let { PaymentScheme.valueOf(it) }


        val customerReferenceNumber = filter.getString("customerReferenceNumber")


        val uuid = filter.getString("uuid") ?: return response(
            ResponseHandler.error(
                "MISSING_UUID", "Uuid is required"
            )
        )

        val terminal =
            provider.activity?.let { provider.terminalSdk?.getTerminal(it, terminalUUID) }

        terminal?.authorize(
            amount = amount,
            scheme = scheme,
            uuid = uuid,
            customerReferenceNumber = customerReferenceNumber,
            readCardListener = object : ReadCardListener {
                override fun onReaderClosed() {
                    Timber.tag("AuthorizeOperation").d("onReaderClosed")
                    sendAuthorizeEvent(uuid, "readerClosed", null, null)
                }

                override fun onReaderDismissed() {
                    Timber.tag("AuthorizeOperation").d("onReaderDismissed")
                    sendAuthorizeEvent(uuid, "readerDismissed", null, null)
                }

                override fun onReaderDisplayed() {
                    Timber.tag("AuthorizeOperation").d("onReaderDisplayed")
                    sendAuthorizeEvent(uuid, "readerDisplayed", null, null)
                }

                override fun onReadCardSuccess() {
                    Timber.tag("AuthorizeOperation").d("onReadCardSuccess")
                    sendAuthorizeEvent(
                        uuid, "cardReadSuccess", "Card read successfully", null
                    )
                }

                override fun onReadCardFailure(readCardFailure: ReadCardFailure) {
                    Timber.tag("AuthorizeOperation").d("onReadCardFailure $readCardFailure")
                    sendAuthorizeEvent(
                        uuid, "cardReadFailure", readCardFailure.toString(), null
                    )
                }

                override fun onReaderWaiting() {
                    Timber.tag("AuthorizeOperation").d("onReaderWaiting")
                    sendAuthorizeEvent(uuid, "readerWaiting", null, null)
                }

                override fun onReaderReading() {
                    Timber.tag("AuthorizeOperation").d("onReaderReading")
                    sendAuthorizeEvent(uuid, "readerReading", null, null)
                }

                override fun onReaderRetry() {
                    Timber.tag("AuthorizeOperation").d("onReaderRetry")
                    sendAuthorizeEvent(uuid, "readerRetry", null, null)
                }

                override fun onPinEntering() {
                    Timber.tag("AuthorizeOperation").d("onPinEntering")
                    sendAuthorizeEvent(uuid, "pinEntering", null, null)
                }

                override fun onReaderFinished() {
                    Timber.tag("AuthorizeOperation").d("onReaderFinished")
                    sendAuthorizeEvent(uuid, "readerFinished", null, null)
                }

                override fun onReaderError(error: String?) {
                    Timber.tag("AuthorizeOperation").d("onReaderError $error")
                    sendAuthorizeEvent(
                        uuid, "readerError", error ?: "Unknown reader error", null
                    )
                }

                override fun onReadingStarted() {
                    Timber.tag("AuthorizeOperation").d("onReadingStarted")
                    sendAuthorizeEvent(uuid, "readingStarted", null, null)
                }
            },
            authorizeListener = object : io.nearpay.terminalsdk.listeners.AuthorizeListener {
                override fun onAuthorizeCompleted(response: AuthorizeResponse) {
                    Timber.tag("AuthorizeOperation").d("onAuthorizeCompleted $response")
                    val jsonString = gson.toJson(response)
                    val map = gson.fromJson(jsonString, Map::class.java) as Map<*, *>
                    sendAuthorizeEvent(
                        uuid, "authorizeCompleted", "Authorization completed successfully", map
                    )
                }

                override fun onAuthorizeFailure(authorizeFailure: AuthorizeFailure) {
                    Timber.tag("AuthorizeOperation").d("onAuthorizeFailure $authorizeFailure")
                    sendAuthorizeEvent(
                        uuid, "authorizeFailure", authorizeFailure.toString(), null
                    )

                }
            })

    }

    private fun sendAuthorizeEvent(
        intentUUID: String, eventType: String, message: String?, data: Any?,
    ) {
        val eventArgs = mutableMapOf<String, Any>(
            "intentUUID" to intentUUID, "type" to eventType
        )
        message?.let { eventArgs["message"] = it }
        data?.let { eventArgs["data"] = it }

        try {
            Handler(Looper.getMainLooper()).post {
                provider.methodChannel.invokeMethod("authorizeEvent", eventArgs)
            }

        } catch (e: Exception) {
            // Log the error but do not disrupt the purchase flow
            Timber.e(
                e,
                "Failed to send authorize event: $eventType for intentUUID: $intentUUID with error: ${e.message}"
            )
            throw e
        }
    }

}