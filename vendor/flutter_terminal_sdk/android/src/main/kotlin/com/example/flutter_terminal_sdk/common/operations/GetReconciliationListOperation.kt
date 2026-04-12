package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import com.google.gson.Gson
import io.nearpay.terminalsdk.data.dto.ReconciliationListResponse
import io.nearpay.terminalsdk.listeners.GetReconciliationListListener
import io.nearpay.terminalsdk.listeners.failures.GetReconciliationListFailure

class GetReconciliationListOperation(provider: NearpayProvider) : BaseOperation(provider) {

    private val gson = Gson()
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {

        val terminalUUID = filter.getString("terminalUUID")
            ?: return response(ResponseHandler.error("MISSING_UUID", "Terminal uuid is required"))

        val page = filter.getInt("page") ?: return response(
            ResponseHandler.error("MISSING_PAGE", "Page is required")
        )
        val pageSize = filter.getInt("pageSize") ?: return response(
            ResponseHandler.error("MISSING_PAGE_SIZE", "Page size is required")
        )
        val startDate = filter.getLong("startDate")
        val endDate = filter.getLong("endDate")


        val terminal =
            provider.activity?.let { provider.terminalSdk?.getTerminal(it, terminalUUID) }

        terminal?.getReconciliationList(
            page = page,
            pageSize = pageSize,
            startDate = startDate,
            endDate = endDate,
            getReconciliationListListener = object : GetReconciliationListListener {

                override fun onGetReconciliationListFailure(error: GetReconciliationListFailure) {
                    response(ResponseHandler.error("GetReconciliationList", error.toString()))

                }

                override fun onGetReconciliationListSuccess(reconciliationListResponse: ReconciliationListResponse) {
                    val jsonString = gson.toJson(reconciliationListResponse)
                    val map = gson.fromJson(jsonString, Map::class.java) as Map<*, *>
                    response(ResponseHandler.success("GetReconciliationList", map))
                }


            }
        )
    }
}