package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import io.nearpay.terminalsdk.data.dto.PaymentScheme
import io.nearpay.terminalsdk.data.dto.RefundResponse
import io.nearpay.terminalsdk.listeners.OpenRefundListener
import io.nearpay.terminalsdk.listeners.ReadCardListener
import io.nearpay.terminalsdk.listeners.failures.OpenRefundFailure
import io.nearpay.terminalsdk.listeners.failures.ReadCardFailure
import timber.log.Timber

class OpenRefundOperation(provider: NearpayProvider) : BaseOperation(provider) {
    private val gson = Gson()
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {

        val terminalUUID = filter.getString("terminalUUID")
            ?: return response(ResponseHandler.error("MISSING_UUID", "Terminal uuid is required"))

        val intentUUID = filter.getString("intentUUID") ?: return response(
            ResponseHandler.error("MISSING_TRANSACTION_UUID", "Transaction UUID is required")
        )

        val amount = filter.getLong("amount") ?: return response(
            ResponseHandler.error("MISSING_AMOUNT", "Amount is required")
        )

        val customerReferenceNumber = filter.getString("customerReferenceNumber")

        val schemeString = filter.getString("scheme")
        val scheme = schemeString?.uppercase()?.let { PaymentScheme.valueOf(it) }

        val terminal =
            provider.activity?.let { provider.terminalSdk?.getTerminal(it, terminalUUID) }

        terminal?.openRefund(
            amount = amount,
            intentUUID = intentUUID,
            scheme = scheme,
            customerReferenceNumber = customerReferenceNumber,
            readCardListener = object : ReadCardListener {
                override fun onReaderClosed() {
                    Timber.tag("OpenRefundOperation").d("onReaderClosed")
                    sendOpenRefundEvent(intentUUID, "readerClosed", null, null)
                }

                override fun onReaderDismissed() {
                    Timber.tag("OpenRefundOperation").d("onReaderDismissed")
                    sendOpenRefundEvent(intentUUID, "readerDismissed", null, null)
                }

                override fun onReaderDisplayed() {
                    Timber.tag("OpenRefundOperation").d("onReaderDisplayed")
                    sendOpenRefundEvent(intentUUID, "readerDisplayed", null, null)
                }

                override fun onReadCardSuccess() {
                    Timber.tag("OpenRefundOperation").d("onReadCardSuccess")
                    sendOpenRefundEvent(
                        intentUUID,
                        "cardReadSuccess",
                        "Card read successfully",
                        null
                    )
                }

                override fun onReadCardFailure(readCardFailure: ReadCardFailure) {
                    Timber.tag("OpenRefundOperation").d("onReadCardFailure $readCardFailure")
                    sendOpenRefundEvent(
                        intentUUID,
                        "cardReadFailure",
                        readCardFailure.toString(),
                        null
                    )

                }

                override fun onReaderWaiting() {
                    Timber.tag("OpenRefundOperation").d("onReaderWaiting")
                    sendOpenRefundEvent(intentUUID, "readerWaiting", null, null)
                }

                override fun onReaderReading() {
                    Timber.tag("OpenRefundOperation").d("onReaderReading")
                    sendOpenRefundEvent(intentUUID, "readerReading", null, null)
                }

                override fun onReaderRetry() {
                    Timber.tag("OpenRefundOperation").d("onReaderRetry")
                    sendOpenRefundEvent(intentUUID, "readerRetry", null, null)
                }

                override fun onPinEntering() {
                    Timber.tag("OpenRefundOperation").d("onPinEntering")
                    sendOpenRefundEvent(intentUUID, "pinEntering", null, null)
                }

                override fun onReaderFinished() {
                    Timber.tag("OpenRefundOperation").d("onReaderFinished")
                    sendOpenRefundEvent(intentUUID, "readerFinished", null, null)
                }

                override fun onReaderError(error: String?) {
                    Timber.tag("OpenRefundOperation").d("onReaderError $error")
                    sendOpenRefundEvent(
                        intentUUID,
                        "readerError",
                        error ?: "Unknown reader error",
                        null
                    )
                }

                override fun onReadingStarted() {
                    Timber.tag("OpenRefundOperation").d("onReadingStarted")
                    sendOpenRefundEvent(intentUUID, "readingStarted", null, null)
                }
            },
            openRefundListener = object :
                OpenRefundListener {

                override fun onOpenRefundCompleted(refundResponse: RefundResponse) {
                    Timber.tag("OpenRefundOperation")
                        .d("onOpenRefundCompleted $refundResponse")
                    val jsonString = gson.toJson(refundResponse)
                    val map: Map<String, Any> =
                        gson.fromJson(jsonString, object : TypeToken<Map<String, Any>>() {}.type)
                    sendOpenRefundEvent(intentUUID, "sendOpenRefundTransactionCompleted", null, map)
                }

                override fun onOpenRefundFailure(openRefundFailure: OpenRefundFailure) {
                    Timber.tag("OpenRefundOperation")
                        .d("onOpenRefundFailure $openRefundFailure")
                    sendOpenRefundEvent(
                        intentUUID,
                        "sendTransactionFailure",
                        openRefundFailure.toString(),
                        null
                    )
                }


            })
    }

    private fun sendOpenRefundEvent(
        intentUUID: String,
        eventType: String,
        message: String?,
        data: Any?
    ) {
        val eventArgs = mutableMapOf<String, Any>(
            "intentUUID" to intentUUID,
            "type" to eventType
        )
        message?.let { eventArgs["message"] = it }
        data?.let { eventArgs["data"] = it }

        try {
            provider.methodChannel.invokeMethod("openRefundEvent", eventArgs)
        } catch (e: Exception) {
            // Log the error but do not disrupt the refund flow
            Timber.e(
                e,
                "Failed to send refund event: $eventType for intentUUID: $intentUUID"
            )
        }
    }
}