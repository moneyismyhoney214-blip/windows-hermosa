package com.example.flutter_terminal_sdk.common.operations


import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import timber.log.Timber


class DismissReaderUiOperation(provider: NearpayProvider) : BaseOperation(provider) {
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {

        val terminalUUID = filter.getString("terminalUUID") ?: return response(
            ResponseHandler.error("MISSING_terminalUUID", "terminal uuid is required")
        )

        val terminal =
            provider.activity?.let { provider.terminalSdk?.getTerminal(it, terminalUUID) }
                ?: return response(
                    ResponseHandler.error(
                        "INVALID_TERMINAL",
                        "No terminal found for UUID: $terminalUUID"
                    )
                )

        Timber.tag("DismissReaderUiOperation")
            .d("DismissReaderUiOperation: $terminalUUID")

        terminal.dismissReaderUi()

        response(
            ResponseHandler.success(
                "Terminal readiness check",
                true,
            )
        )


    }
}