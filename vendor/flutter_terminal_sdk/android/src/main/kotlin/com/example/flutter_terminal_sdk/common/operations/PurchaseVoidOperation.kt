package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import com.google.gson.Gson
import io.nearpay.terminalsdk.Terminal
import io.nearpay.terminalsdk.data.dto.IntentResponseTurkey
import io.nearpay.terminalsdk.data.dto.PaymentScheme
import io.nearpay.terminalsdk.listeners.ReadCardListener
import io.nearpay.terminalsdk.listeners.SendPurchaseVoidListener
import io.nearpay.terminalsdk.listeners.failures.ReadCardFailure
import io.nearpay.terminalsdk.listeners.failures.SendTransactionFailure
import timber.log.Timber

class PurchaseVoidOperation(provider: NearpayProvider) : BaseOperation(provider) {
    private val gson = Gson()

    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {
        // Extract required arguments
        val uuid = filter.getString("uuid")
            ?: return response(ResponseHandler.error("MISSING_UUID", "Terminal uuid is required"))

        val amount = filter.getLong("amount")
            ?: return response(ResponseHandler.error("MISSING_AMOUNT", "Amount is required"))


        val intentUUID = filter.getString("intentUUID")
            ?: return response(
                ResponseHandler.error(
                    "MISSING_TRANSACTION_UUID",
                    "Transaction UUID is required"
                )
            )

        val customerReferenceNumber = filter.getString("customerReferenceNumber")

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
            terminal.purchaseVoid(
                amount = amount,
                scheme = scheme,
                customerReferenceNumber = customerReferenceNumber,
                intentUUID = intentUUID,
                readCardListener = object : ReadCardListener {
                    override fun onReaderClosed() {
                        Timber.tag("PurchaseVoidOperation").d("onReaderClosed")
                        sendPurchaseEvent(intentUUID, "readerClosed", null, null)
                    }

                    override fun onReaderDismissed() {
                        Timber.tag("PurchaseVoidOperation").d("onReaderDismissed")
                        sendPurchaseEvent(intentUUID, "readerDismissed", null, null)
                    }

                    override fun onReaderDisplayed() {
                        Timber.tag("PurchaseVoidOperation").d("onReaderDisplayed")
                        sendPurchaseEvent(intentUUID, "readerDisplayed", null, null)
                    }

                    override fun onReadCardSuccess() {
                        sendPurchaseEvent(
                            intentUUID,
                            "cardReadSuccess",
                            "Card read successfully",
                            null
                        )
                    }

                    override fun onReadCardFailure(readCardFailure: ReadCardFailure) {
                        sendPurchaseEvent(
                            intentUUID,
                            "cardReadFailure",
                            readCardFailure.toString(),
                            null
                        )
                    }

                    override fun onReaderWaiting() {
                        sendPurchaseEvent(intentUUID, "readerWaiting", null, null)
                    }

                    override fun onReaderReading() {
                        sendPurchaseEvent(intentUUID, "readerReading", null, null)
                    }

                    override fun onReaderRetry() {
                        sendPurchaseEvent(intentUUID, "readerRetry", null, null)
                    }

                    override fun onPinEntering() {
                        sendPurchaseEvent(intentUUID, "pinEntering", null, null)
                    }

                    override fun onReaderFinished() {
                        sendPurchaseEvent(intentUUID, "readerFinished", null, null)
                    }

                    override fun onReaderError(error: String?) {
                        sendPurchaseEvent(
                            intentUUID,
                            "readerError",
                            error ?: "Unknown reader error",
                            null
                        )
                    }

                    override fun onReadingStarted() {
                        sendPurchaseEvent(intentUUID, "readingStarted", null, null)
                    }
                },
                sendPurchaseVoidListener = object : SendPurchaseVoidListener {


                    override fun onSendPurchaseVoidCompleted(purchaseVoidResponse: IntentResponseTurkey) {
                        val jsonString = gson.toJson(purchaseVoidResponse)
                        val map = gson.fromJson(jsonString, Map::class.java) as Map<*, *>
                        sendPurchaseEvent(
                            intentUUID,
                            "sendTransactionVoidCompleted",
                            null,
                            map
                        )

                    }


                    override fun onSendPurchaseVoidFailure(sendPurchaseVoidFailure: SendTransactionFailure) {
                        sendPurchaseEvent(
                            intentUUID,
                            "sendTransactionFailure",
                            sendPurchaseVoidFailure.toString(),
                            null
                        )
                    }
                },
            )
        } catch (e: Exception) {
            // Handle any unexpected exceptions during purchase
            response(
                ResponseHandler.error(
                    "PURCHASE_VOID_FAILED",
                    "Purchase void failed: ${e.message}"
                )
            )
        }
    }

    private fun sendPurchaseEvent(
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
            provider.methodChannel.invokeMethod("purchaseVoidEvent", eventArgs)
        } catch (e: Exception) {
            // Log the error but do not disrupt the purchase flow
            Timber.e(
                e,
                "Failed to send purchase void event: $eventType for intentUUID: $intentUUID"
            )
        }
    }
}
