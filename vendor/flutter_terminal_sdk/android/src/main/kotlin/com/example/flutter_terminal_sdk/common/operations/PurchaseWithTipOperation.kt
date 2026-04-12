package com.example.flutter_terminal_sdk.common.operations

import android.os.Handler
import android.os.Looper
import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import com.google.gson.Gson
import io.nearpay.terminalsdk.Terminal
import io.nearpay.terminalsdk.data.dto.PaymentScheme
import io.nearpay.terminalsdk.data.dto.PurchaseResponse
import io.nearpay.terminalsdk.listeners.ReadCardListener
import io.nearpay.terminalsdk.listeners.SendPurchaseWithTipListener
import io.nearpay.terminalsdk.listeners.failures.ReadCardFailure
import io.nearpay.terminalsdk.listeners.failures.SendTransactionFailure
import timber.log.Timber

class PurchaseWithTipOperation(provider: NearpayProvider) : BaseOperation(provider) {
    private val gson = Gson()

    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {
        // Extract required arguments
        val uuid = filter.getString("uuid")
            ?: return response(ResponseHandler.error("MISSING_UUID", "Terminal uuid is required"))

        val amount = filter.getLong("amount")
            ?: return response(ResponseHandler.error("MISSING_AMOUNT", "Amount is required"))
        
        //amountOther
        val amountOther = filter.getLong("amountOther")
            ?: return response(ResponseHandler.error("MISSING_AMOUNT_OTHER", "Amount Other is required"))

        val customerReferenceNumber = filter.getString("customerReferenceNumber")


        val intentUUID = filter.getString("intentUUID")
            ?: return response(
                ResponseHandler.error(
                    "MISSING_INTENT_UUID",
                    "intent UUID is required"
                )
            )
        val schemeString = filter.getString("scheme")
        val scheme = schemeString?.uppercase()?.let { PaymentScheme.valueOf(it) }

        val activity = provider.activity
            ?: return response(ResponseHandler.error("NO_ACTIVITY", "Activity reference is null"))

        // Retrieve the TerminalSDK instance
        val terminal: Terminal = provider.terminalSdk?.getTerminal(activity, uuid)
            ?: return response(
                ResponseHandler.error(
                    "TERMINAL_NOT_FOUND",
                    "Terminal with uuid = $uuid = not found"
                )
            )

        Timber.d("Got Terminal successfully")
        try {
            // Initiate the purchase process
            terminal.purchaseWithTip(
                amount = amount,
                amountOther = amountOther,
                scheme = scheme,
                intentUUID = intentUUID,
                customerReferenceNumber = customerReferenceNumber,
                readCardListener = object : ReadCardListener {
                    override fun onReaderClosed() {
                        Timber.tag("PurchaseWithTipOperation").d("onReaderClosed")
                        sendPurchaseWithTipEvent(intentUUID, "readerClosed", null, null)
                    }

                    override fun onReaderDismissed() {
                        Timber.tag("PurchaseWithTipOperation").d("onReaderDismissed")
                        sendPurchaseWithTipEvent(intentUUID, "readerDismissed", null, null)
                    }

                    override fun onReaderDisplayed() {
                        Timber.tag("PurchaseWithTipOperation").d("onReaderDisplayed")
                        sendPurchaseWithTipEvent(intentUUID, "readerDisplayed", null, null)
                    }

                    override fun onReadCardSuccess() {
                        Timber.tag("PurchaseWithTipOperation").d("onReadCardSuccess")
                        sendPurchaseWithTipEvent(
                            intentUUID,
                            "cardReadSuccess",
                            "Card read successfully",
                            null
                        )
                    }

                    override fun onReadCardFailure(readCardFailure: ReadCardFailure) {
                        Timber.tag("PurchaseWithTipOperation").d("onReadCardFailure $readCardFailure")
                        sendPurchaseWithTipEvent(
                            intentUUID,
                            "cardReadFailure",
                            readCardFailure.toString(),
                            null
                        )
                    }

                    override fun onReaderWaiting() {
                        Timber.tag("PurchaseWithTipOperation").d("onReaderWaiting")
                        sendPurchaseWithTipEvent(intentUUID, "readerWaiting", null, null)
                    }

                    override fun onReaderReading() {
                        Timber.tag("PurchaseWithTipOperation").d("onReaderReading")
                        sendPurchaseWithTipEvent(intentUUID, "readerReading", null, null)
                    }

                    override fun onReaderRetry() {
                        Timber.tag("PurchaseWithTipOperation").d("onReaderRetry")
                        sendPurchaseWithTipEvent(intentUUID, "readerRetry", null, null)
                    }

                    override fun onPinEntering() {
                        Timber.tag("PurchaseWithTipOperation").d("onPinEntering")
                        sendPurchaseWithTipEvent(intentUUID, "pinEntering", null, null)
                    }

                    override fun onReaderFinished() {
                        Timber.tag("PurchaseWithTipOperation").d("onReaderFinished")
                        sendPurchaseWithTipEvent(intentUUID, "readerFinished", null, null)
                    }

                    override fun onReaderError(error: String?) {
                        Timber.tag("PurchaseWithTipOperation").d("onReaderError $error")
                        sendPurchaseWithTipEvent(
                            intentUUID,
                            "readerError",
                            error ?: "Unknown reader error",
                            null
                        )
                    }

                    override fun onReadingStarted() {
                        Timber.tag("PurchaseWithTipOperation").d("onReadingStarted")
                        sendPurchaseWithTipEvent(intentUUID, "readingStarted", null, null)
                    }
                },
                sendPurchaseWithTipListener = object : SendPurchaseWithTipListener {

                    override fun onSendTransactionCompleted(transactionResponse: PurchaseResponse) {

                        Timber.tag("PurchaseWithTipOperation")
                            .d("intentId ${transactionResponse.details.intentId}")

                        Timber.tag("PurchaseWithTipOperation")
                            .d("intentUUID $intentUUID")

                        Timber.tag("PurchaseWithTipOperation")
                            .d("sendTransactionCompleted $transactionResponse")

                        val jsonString = gson.toJson(transactionResponse)
                        val map = gson.fromJson(jsonString, Map::class.java) as Map<*, *>
                        sendPurchaseWithTipEvent(
                            intentUUID,
                            "sendPurchaseWithTipTransactionCompleted",
                            null,
                            map
                        )
                    }


                    override fun onSendTransactionFailure(sendTransactionFailure: SendTransactionFailure) {
                        sendPurchaseWithTipEvent(
                            intentUUID,
                            "sendTransactionFailure",
                            sendTransactionFailure.toString(),
                            null
                        )
                    }
                }
            )
        } catch (e: Exception) {
            Timber.tag("PurchaseWithTipOperation").e(e, "Purchase operation failed")
            response(ResponseHandler.error("PURCHASE_FAILED", "Purchase failed: ${e.message}"))
        }
    }

    private fun sendPurchaseWithTipEvent(
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
            Handler(Looper.getMainLooper()).post {
                provider.methodChannel.invokeMethod("purchaseWithTipEvent", eventArgs)
            }

        } catch (e: Exception) {
            // Log the error but do not disrupt the purchase flow
            Timber.e(
                e,
                "Failed to send purchaseWithTipEvent event: $eventType for intentUUID: $intentUUID with error: ${e.message}"
            )
            throw e;
        }
    }
}
