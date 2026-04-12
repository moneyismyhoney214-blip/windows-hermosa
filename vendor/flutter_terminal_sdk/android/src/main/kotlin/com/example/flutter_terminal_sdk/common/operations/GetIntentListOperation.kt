package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import com.google.gson.Gson
import io.nearpay.terminalsdk.data.dto.IntentsListResponse
import io.nearpay.terminalsdk.listeners.GetIntentsListListener
import io.nearpay.terminalsdk.listeners.failures.GetIntentsListFailure
import timber.log.Timber

class GetIntentListOperation(provider: NearpayProvider) : BaseOperation(provider) {
    private val gson = Gson()
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {

        val terminalUUID = filter.getString("terminalUUID")
            ?: return response(ResponseHandler.error("MISSING_UUID", "Terminal uuid is required"))

        val page = filter.getInt("page")
        val pageSize = filter.getInt("pageSize")
        val isReconciled = filter.getBoolean("isReconciled")
        val startDate = filter.getString("startDate")
        val endDate = filter.getString("endDate")
        val customerReferenceNumber = filter.getString("customerReferenceNumber")

        Timber.tag("GetTransactionListOperation").d(
            "terminalUUID: $terminalUUID, page: $page, pageSize: $pageSize, isReconciled: $isReconciled, startDate: $startDate, endDate: $endDate, customerReferenceNumber: $customerReferenceNumber"
        )

        val terminal =
            provider.activity?.let { provider.terminalSdk?.getTerminal(it, terminalUUID) }

        terminal?.getIntentsList(
            page = page,
            pageSize = pageSize,
            isReconciled = isReconciled,
            startDate = startDate,
            endDate = endDate,
            customerReferenceNumber = customerReferenceNumber,
            getIntentsListListener = object : GetIntentsListListener {

                override fun onGetIntentsListFailure(error: GetIntentsListFailure) {
                    Timber.tag("GetTransactionListOperation")
                        .d("GetTransactionListFailure failed $error")
                    response(
                        ResponseHandler.error(
                            "GET_TRANSACTION_LIST_FAILURE", error.toString()
                        )
                    )
                }

                override fun onGetIntentsListSuccess(intentsList: IntentsListResponse) {
                    val jsonString = gson.toJson(intentsList)
                    val map = gson.fromJson(jsonString, Map::class.java) as Map<*, *>

                    Timber.tag("GetTransactionListOperation")
                        .d("GetTransactionListSuccess map $map")
                    response(
                        ResponseHandler.success(
                            "Transaction list fetched successfully",
                            map
                        )
                    )
                }


            })
    }

}