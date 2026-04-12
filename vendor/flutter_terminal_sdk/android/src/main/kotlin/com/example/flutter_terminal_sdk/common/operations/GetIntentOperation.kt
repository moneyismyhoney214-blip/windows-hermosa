package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import com.google.gson.Gson
import io.nearpay.terminalsdk.data.dto.IntentDetails
import io.nearpay.terminalsdk.listeners.GetIntentListener
import io.nearpay.terminalsdk.listeners.failures.GetIntentFailure
import timber.log.Timber

class GetIntentOperation(provider: NearpayProvider) : BaseOperation(provider) {
    private val gson = Gson()
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {

        val terminalUUID = filter.getString("terminalUUID")
            ?: return response(ResponseHandler.error("MISSING_UUID", "Terminal uuid is required"))

        val intentUUID = filter.getString("intentUUID") ?: return response(
            ResponseHandler.error("MISSING_TRANSACTION_UUID", "Transaction UUID is required")
        )


        val terminal =
            provider.activity?.let { provider.terminalSdk?.getTerminal(it, terminalUUID) }

        terminal?.getIntent(uuid = intentUUID,
            getIntentListener = object : GetIntentListener {

                override fun onGetIntentFailure(error: GetIntentFailure) {
                    Timber.tag("handleReadCard").d("GetTransactionFailure failed $error")
                    response(
                        ResponseHandler.error(
                            "GET_TRANSACTION_FAILURE", error.toString()
                        )
                    )                }

                override fun onGetIntentSuccess(intent: IntentDetails) {
                    val jsonString = gson.toJson(intent)
                    val map = gson.fromJson(jsonString, Map::class.java) as Map<*, *>
                    Timber.tag("handleReadCard").d("GetTransactionSuccess transaction $intent")
                    response(
                        ResponseHandler.success(
                            "Transaction details fetched successfully",
                            map
                        )
                    )                }

            }

        )

    }

}