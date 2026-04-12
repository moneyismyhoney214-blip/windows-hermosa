package com.example.flutter_terminal_sdk.common.operations

import android.app.Activity
import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import timber.log.Timber

class GetTerminalOperation(provider: NearpayProvider) : BaseOperation(provider) {
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {
        val terminalUUID = filter.getString("terminalUUID") ?: return response(
            ResponseHandler.error("MISSING_TERMINAL_UUID", "terminalUUID is required")
        )

        Timber.d("Fetching terminal with terminalUUID: $terminalUUID")

        val activity: Activity = provider.activity ?: return response(
            ResponseHandler.error(
                "NO_ACTIVITY", "Activity reference is null"
            )
        )


        try {

            val terminal =
                provider.terminalSdk?.getTerminal(activity = activity, uuid = terminalUUID)
                    ?: return response(
                        ResponseHandler.error("INVALID_TERMINAL", "No terminal found for terminalUUID: $terminalUUID")
                    )

            val resultData = mapOf(
                "tid" to terminal.tid,
                "isReady" to terminal.isTerminalReady(),
                "terminalUUID" to terminal.terminalUUID,
                "uuid" to terminal.terminalUUID,
                "name" to terminal.name,

                )
            response(ResponseHandler.success("Connected to terminal", resultData))


        } catch (e: Exception) {
            return response(
                ResponseHandler.error("ERROR", e.message ?: "An error occurred")
            )
        }


    }
}
