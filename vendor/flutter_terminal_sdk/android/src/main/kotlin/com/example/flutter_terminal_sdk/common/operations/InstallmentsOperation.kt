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
import io.nearpay.terminalsdk.listeners.InstallmentsListener
import io.nearpay.terminalsdk.listeners.ReadCardListener
import io.nearpay.terminalsdk.listeners.failures.ReadCardFailure
import io.nearpay.terminalsdk.listeners.failures.SendTransactionFailure
import timber.log.Timber

class InstallmentsOperation(provider: NearpayProvider) : BaseOperation(provider) {
    private val gson = Gson()

    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {
        // Extract required arguments
        val uuid = filter.getString("uuid")
            ?: return response(ResponseHandler.error("MISSING_UUID", "Terminal uuid is required"))

        val amount = filter.getLong("amount")
            ?: return response(ResponseHandler.error("MISSING_AMOUNT", "Amount is required"))

        val numberOfInstallments = filter.getInt("numberOfInstallments")
            ?: return response(
                ResponseHandler.error(
                    "MISSING_NUMBER_OF_INSTALLMENTS",
                    "Number of installments is required"
                )
            )

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
            terminal.installments(
                amount = amount,
                scheme = scheme,
                intentUUID = intentUUID,
                numberOfInstallments = numberOfInstallments,
                customerReferenceNumber = customerReferenceNumber,
                readCardListener = object : ReadCardListener {
                    override fun onReaderClosed() {
                        Timber.tag("InstallmentsOperation").d("onReaderClosed")
                        sendPurchaseEvent(intentUUID, "readerClosed", null, null)
                    }

                    override fun onReaderDismissed() {
                        Timber.tag("InstallmentsOperation").d("onReaderDismissed")
                        sendPurchaseEvent(intentUUID, "readerDismissed", null, null)
                    }

                    override fun onReaderDisplayed() {
                        Timber.tag("InstallmentsOperation").d("onReaderDisplayed")
                        sendPurchaseEvent(intentUUID, "readerDisplayed", null, null)
                    }

                    override fun onReadCardSuccess() {
                        Timber.tag("InstallmentsOperation").d("onReadCardSuccess")
                        sendPurchaseEvent(
                            intentUUID,
                            "cardReadSuccess",
                            "Card read successfully",
                            null
                        )
                    }

                    override fun onReadCardFailure(readCardFailure: ReadCardFailure) {
                        Timber.tag("InstallmentsOperation").d("onReadCardFailure $readCardFailure")
                        sendPurchaseEvent(
                            intentUUID,
                            "cardReadFailure",
                            readCardFailure.toString(),
                            null
                        )
                    }

                    override fun onReaderWaiting() {
                        Timber.tag("InstallmentsOperation").d("onReaderWaiting")
                        sendPurchaseEvent(intentUUID, "readerWaiting", null, null)
                    }

                    override fun onReaderReading() {
                        Timber.tag("InstallmentsOperation").d("onReaderReading")
                        sendPurchaseEvent(intentUUID, "readerReading", null, null)
                    }

                    override fun onReaderRetry() {
                        Timber.tag("InstallmentsOperation").d("onReaderRetry")
                        sendPurchaseEvent(intentUUID, "readerRetry", null, null)
                    }

                    override fun onPinEntering() {
                        Timber.tag("InstallmentsOperation").d("onPinEntering")
                        sendPurchaseEvent(intentUUID, "pinEntering", null, null)
                    }

                    override fun onReaderFinished() {
                        Timber.tag("InstallmentsOperation").d("onReaderFinished")
                        sendPurchaseEvent(intentUUID, "readerFinished", null, null)
                    }

                    override fun onReaderError(error: String?) {
                        Timber.tag("InstallmentsOperation").d("onReaderError $error")
                        sendPurchaseEvent(
                            intentUUID,
                            "readerError",
                            error ?: "Unknown reader error",
                            null
                        )
                    }

                    override fun onReadingStarted() {
                        Timber.tag("InstallmentsOperation").d("onReadingStarted")
                        sendPurchaseEvent(intentUUID, "readingStarted", null, null)
                    }
                },
                installmentsListener = object : InstallmentsListener {

                    override fun onInstallmentsCompleted(transactionResponse: PurchaseResponse) {

                        Timber.tag("InstallmentsOperation")
                            .d("intentId ${transactionResponse.details.intentId}")

                        Timber.tag("InstallmentsOperation")
                            .d("intentUUID $intentUUID")

                        Timber.tag("InstallmentsOperation")
                            .d("sendTransactionCompleted $transactionResponse")

                        val jsonString = gson.toJson(transactionResponse)
                        val map = gson.fromJson(jsonString, Map::class.java) as Map<*, *>
                        sendPurchaseEvent(
                            intentUUID,
                            "sendInstallmentsTransactionCompleted",
                            null,
                            map
                        )
                    }


                    override fun onInstallmentsFailure(sendTransactionFailure: SendTransactionFailure) {
                        sendPurchaseEvent(
                            intentUUID,
                            "sendTransactionFailure",
                            sendTransactionFailure.toString(),
                            null
                        )
                    }

                }
            )
        } catch (e: Exception) {
            Timber.tag("InstallmentsOperation").e(e, "Installments operation failed")
            response(ResponseHandler.error("PURCHASE_FAILED", "Installments failed: ${e.message}"))
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
                provider.methodChannel.invokeMethod("installmentsEvent", eventArgs)
            }

        } catch (e: Exception) {
            // Log the error but do not disrupt the purchase flow
            Timber.e(
                e,
                "Failed to send Installments event: $eventType for intentUUID: $intentUUID with error: ${e.message}"
            )
            throw e;
        }
    }
}
