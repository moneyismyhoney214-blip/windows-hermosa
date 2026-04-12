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
import io.nearpay.terminalsdk.listeners.SendTransactionListener
import io.nearpay.terminalsdk.listeners.failures.ReadCardFailure
import io.nearpay.terminalsdk.listeners.failures.SendTransactionFailure
import timber.log.Timber

class PurchaseOperation(provider: NearpayProvider) : BaseOperation(provider) {
    private val gson = Gson()

    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {
        // Extract required arguments
        val uuid = filter.getString("uuid")
            ?: return response(ResponseHandler.error("MISSING_UUID", "Terminal uuid is required"))

        val amount = filter.getLong("amount")
            ?: return response(ResponseHandler.error("MISSING_AMOUNT", "Amount is required"))

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

        // Prefer the terminal cached from jwtLogin (it is already provisioned
        // and ready).  Fall back to getTerminal() for non-JWT flows.
        val jwtCached = provider.jwtTerminal
        val terminal: Terminal = if (jwtCached != null && jwtCached.terminalUUID == uuid) {
            Timber.d("Using cached jwtTerminal (UUID=$uuid)")
            jwtCached
        } else {
            Timber.d("jwtTerminal miss (cached=${jwtCached?.terminalUUID}, requested=$uuid) — falling back to getTerminal()")
            provider.terminalSdk?.getTerminal(activity, uuid)
                ?: return response(
                    ResponseHandler.error(
                        "TERMINAL_NOT_FOUND",
                        "Terminal with uuid = $uuid = not found"
                    )
                )
        }

        Timber.d("Got Terminal successfully (isReady=${terminal.isTerminalReady()})")
        try {
            // Initiate the purchase process
            terminal.purchase(
                amount = amount,
                scheme = scheme,
                intentUUID = intentUUID,
                customerReferenceNumber = customerReferenceNumber,
                readCardListener = object : ReadCardListener {
                    override fun onReaderClosed() {
                        Timber.tag("PurchaseOperation").d("onReaderClosed")
                        sendPurchaseEvent(intentUUID, "readerClosed", null, null)
                    }

                    override fun onReaderDismissed() {
                        Timber.tag("PurchaseOperation").d("onReaderDismissed")
                        sendPurchaseEvent(intentUUID, "readerDismissed", null, null)
                    }

                    override fun onReaderDisplayed() {
                        Timber.tag("PurchaseOperation").d("onReaderDisplayed")
                        sendPurchaseEvent(intentUUID, "readerDisplayed", null, null)
                    }

                    override fun onReadCardSuccess() {
                        Timber.tag("PurchaseOperation").d("onReadCardSuccess")
                        sendPurchaseEvent(
                            intentUUID,
                            "cardReadSuccess",
                            "Card read successfully",
                            null
                        )
                    }

                    override fun onReadCardFailure(readCardFailure: ReadCardFailure) {
                        Timber.tag("PurchaseOperation").d("onReadCardFailure $readCardFailure")
                        sendPurchaseEvent(
                            intentUUID,
                            "cardReadFailure",
                            readCardFailure.toString(),
                            null
                        )
                    }

                    override fun onReaderWaiting() {
                        Timber.tag("PurchaseOperation").d("onReaderWaiting")
                        sendPurchaseEvent(intentUUID, "readerWaiting", null, null)
                    }

                    override fun onReaderReading() {
                        Timber.tag("PurchaseOperation").d("onReaderReading")
                        sendPurchaseEvent(intentUUID, "readerReading", null, null)
                    }

                    override fun onReaderRetry() {
                        Timber.tag("PurchaseOperation").d("onReaderRetry")
                        sendPurchaseEvent(intentUUID, "readerRetry", null, null)
                    }

                    override fun onPinEntering() {
                        Timber.tag("PurchaseOperation").d("onPinEntering")
                        sendPurchaseEvent(intentUUID, "pinEntering", null, null)
                    }

                    override fun onReaderFinished() {
                        Timber.tag("PurchaseOperation").d("onReaderFinished")
                        sendPurchaseEvent(intentUUID, "readerFinished", null, null)
                    }

                    override fun onReaderError(error: String?) {
                        Timber.tag("PurchaseOperation").d("onReaderError $error")
                        sendPurchaseEvent(
                            intentUUID,
                            "readerError",
                            error ?: "Unknown reader error",
                            null
                        )
                    }

                    override fun onReadingStarted() {
                        Timber.tag("PurchaseOperation").d("onReadingStarted")
                        sendPurchaseEvent(intentUUID, "readingStarted", null, null)
                    }
                },
                sendTransactionListener = object : SendTransactionListener {

                    override fun onSendTransactionCompleted(transactionResponse: PurchaseResponse) {

                        Timber.tag("PurchaseOperation")
                            .d("intentId ${transactionResponse.details.intentId}")

                        Timber.tag("PurchaseOperation")
                            .d("intentUUID $intentUUID")

                        Timber.tag("PurchaseOperation")
                            .d("sendTransactionCompleted $transactionResponse")

                        val jsonString = gson.toJson(transactionResponse)
                        val map = gson.fromJson(jsonString, Map::class.java) as Map<*, *>
                        sendPurchaseEvent(
                            intentUUID,
                            "sendPurchaseTransactionCompleted",
                            null,
                            map
                        )
                    }


                    override fun onSendTransactionFailure(sendTransactionFailure: SendTransactionFailure) {
                        sendPurchaseEvent(
                            intentUUID,
                            "sendTransactionFailure",
                            sendTransactionFailure.toString(),
                            null
                        )
                    }
                }
            )
            // terminal.purchase() registers async listeners and returns immediately.
            // Unblock the Dart await so the purchase event callbacks can flow.
            Timber.tag("PurchaseOperation").d("purchase() registered — unblocking Dart channel")
            response(ResponseHandler.success("Purchase started", mapOf("intentUUID" to intentUUID)))
        } catch (e: Exception) {
            Timber.tag("PurchaseOperation").e(e, "Purchase operation failed")
            response(ResponseHandler.error("PURCHASE_FAILED", "Purchase failed: ${e.message}"))
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
            Handler(Looper.getMainLooper()).post {
                provider.methodChannel.invokeMethod("purchaseEvent", eventArgs)
            }

        } catch (e: Exception) {
            // Log the error but do not disrupt the purchase flow
            Timber.e(
                e,
                "Failed to send purchase event: $eventType for intentUUID: $intentUUID with error: ${e.message}"
            )
            throw e;
        }
    }
}
