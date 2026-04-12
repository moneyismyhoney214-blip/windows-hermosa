package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import com.google.gson.Gson
import io.nearpay.terminalsdk.data.dto.PurchaseResponse
import io.nearpay.terminalsdk.listeners.TipTransactionListener
import io.nearpay.terminalsdk.listeners.failures.TipTransactionFailure
import timber.log.Timber

class TipTransactionOperation(provider: NearpayProvider) : BaseOperation(provider) {
    private val gson = Gson()
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {

        val terminalUUID = filter.getString("terminalUUID")
            ?: return response(ResponseHandler.error("MISSING_UUID", "Terminal uuid is required"))

        val amount = filter.getLong("amount")
            ?: return response(ResponseHandler.error("MISSING_AMOUNT", "Amount is required"))


        val id = filter.getString("id")
            ?: return response(
                ResponseHandler.error(
                    "MISSING_id",
                    "id is required"
                )
            )

        Timber.tag("TipTransactionOperation").d("Starting tip transaction for terminal: $terminalUUID with amount: $amount and id: $id")

        val terminal =
            provider.activity?.let { provider.terminalSdk?.getTerminal(it, terminalUUID) }

        terminal?.tipTransaction(
            id = id,
            amount = amount,
            tipTransactionListener = object : TipTransactionListener {

                override fun onTipTransactionFailure(tipTransactionFailure: TipTransactionFailure) {
                    Timber.tag("TipTransactionOperation").d("Tip Transaction failed $tipTransactionFailure")
                    response(ResponseHandler.error("TIP_TRANSACTION_FAILURE", tipTransactionFailure.toString()))
                }

                override fun onTipTransactionSuccess(tipResponse: PurchaseResponse) {
                    val jsonString = gson.toJson(tipResponse)
                    val map =
                        gson.fromJson(jsonString, Map::class.java) as Map<*, *>
                    response(ResponseHandler.success("Tip Transaction Success", map))
                }

            }

        )

    }

}