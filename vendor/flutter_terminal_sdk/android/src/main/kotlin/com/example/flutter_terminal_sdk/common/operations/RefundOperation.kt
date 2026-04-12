package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import io.nearpay.terminalsdk.data.dto.PaymentScheme
import io.nearpay.terminalsdk.data.dto.RefundResponse
import io.nearpay.terminalsdk.listeners.ReadCardListener
import io.nearpay.terminalsdk.listeners.RefundTransactionListener
import io.nearpay.terminalsdk.listeners.failures.ReadCardFailure
import io.nearpay.terminalsdk.listeners.failures.RefundTransactionFailure
import timber.log.Timber

class RefundOperation(provider: NearpayProvider) : BaseOperation(provider) {
    private val gson = Gson()
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {

        val terminalUUID = filter.getString("terminalUUID")
            ?: return response(ResponseHandler.error("MISSING_UUID", "Terminal uuid is required"))

        val intentUUID = filter.getString("intentUUID") ?: return response(
            ResponseHandler.error("MISSING_TRANSACTION_UUID", "Transaction UUID is required")
        )
        val refundUUID = filter.getString("refundUuid") ?: return response(
            ResponseHandler.error("MISSING_REFUND_UUID", "Refund UUID is required")
        )
        val amount = filter.getLong("amount") ?: return response(
            ResponseHandler.error("MISSING_AMOUNT", "Amount is required")
        )

        val customerReferenceNumber = filter.getString("customerReferenceNumber")

        val schemeString = filter.getString("scheme")
        val scheme = schemeString?.uppercase()?.let { PaymentScheme.valueOf(it) }

        val terminal =
            provider.activity?.let { provider.terminalSdk?.getTerminal(it, terminalUUID) }

        terminal?.refund(
            amount = amount,
            intentUUID = intentUUID,
            refundUUID = refundUUID,
            scheme = scheme,
            customerReferenceNumber = customerReferenceNumber,
            readCardListener = object : ReadCardListener {
                override fun onReaderClosed() {
                    Timber.tag("RefundOperation").d("onReaderClosed")
                    sendRefundEvent(refundUUID, "readerClosed", null, null)
                }

                override fun onReaderDismissed() {
                    Timber.tag("RefundOperation").d("onReaderDismissed")
                    sendRefundEvent(refundUUID, "readerDismissed", null, null)
                }

                override fun onReaderDisplayed() {
                    Timber.tag("RefundOperation").d("onReaderDisplayed")
                    sendRefundEvent(refundUUID, "readerDisplayed", null, null)
                }

                override fun onReadCardSuccess() {
                    Timber.tag("RefundTurkishOperation").d("onReadCardSuccess")
                    sendRefundEvent(
                        intentUUID,
                        "cardReadSuccess",
                        "Card read successfully",
                        null
                    )
                }

                override fun onReadCardFailure(readCardFailure: ReadCardFailure) {
                    Timber.tag("RefundTurkishOperation").d("onReadCardFailure $readCardFailure")
                    sendRefundEvent(
                        intentUUID,
                        "cardReadFailure",
                        readCardFailure.toString(),
                        null
                    )

                }

                override fun onReaderWaiting() {
                    Timber.tag("RefundTurkishOperation").d("onReaderWaiting")
                    sendRefundEvent(intentUUID, "readerWaiting", null, null)
                }

                override fun onReaderReading() {
                    Timber.tag("RefundTurkishOperation").d("onReaderReading")
                    sendRefundEvent(intentUUID, "readerReading", null, null)
                }

                override fun onReaderRetry() {
                    Timber.tag("RefundTurkishOperation").d("onReaderRetry")
                    sendRefundEvent(intentUUID, "readerRetry", null, null)
                }

                override fun onPinEntering() {
                    Timber.tag("RefundTurkishOperation").d("onPinEntering")
                    sendRefundEvent(intentUUID, "pinEntering", null, null)
                }

                override fun onReaderFinished() {
                    Timber.tag("RefundTurkishOperation").d("onReaderFinished")
                    sendRefundEvent(intentUUID, "readerFinished", null, null)
                }

                override fun onReaderError(error: String?) {
                    Timber.tag("RefundTurkishOperation").d("onReaderError $error")
                    sendRefundEvent(
                        intentUUID,
                        "readerError",
                        error ?: "Unknown reader error",
                        null
                    )
                }

                override fun onReadingStarted() {
                    Timber.tag("RefundTurkishOperation").d("onReadingStarted")
                    sendRefundEvent(intentUUID, "readingStarted", null, null)
                }
            },
            refundTransactionListener = object :
                RefundTransactionListener {
                override fun onRefundTransactionCompleted(refundResponse: RefundResponse) {
                    Timber.tag("RefundTurkishOperation")
                        .d("onRefundTransactionSuccess $refundResponse")
                    val jsonString = gson.toJson(refundResponse)
                    val map: Map<String, Any> =
                        gson.fromJson(jsonString, object : TypeToken<Map<String, Any>>() {}.type)
                    sendRefundEvent(intentUUID, "sendRefundTransactionCompleted", null, map)

                }

                override fun onRefundTransactionFailure(refundTransactionFailure: RefundTransactionFailure) {
                    Timber.tag("RefundTurkishOperation")
                        .d("onRefundTransactionFailure $refundTransactionFailure")
                    sendRefundEvent(
                        intentUUID,
                        "sendTransactionFailure",
                        refundTransactionFailure.toString(),
                        null
                    )

                }


            })
    }

    private fun sendRefundEvent(
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
            provider.methodChannel.invokeMethod("refundEvent", eventArgs)
        } catch (e: Exception) {
            // Log the error but do not disrupt the refund flow
            Timber.e(
                e,
                "Failed to send refund event: $eventType for intentUUID: $intentUUID"
            )
        }
    }
}