package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import io.nearpay.softpos.utils.NearPayError
import io.nearpay.terminalsdk.Terminal
import io.nearpay.terminalsdk.data.dto.TerminalConfig
import io.nearpay.terminalsdk.listeners.GetTerminalConfigListener
import timber.log.Timber

class GetTerminalConfigOperation(provider: NearpayProvider) : BaseOperation(provider) {

    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {
        val terminalUUID = filter.getString("terminalUUID")
            ?: return response(ResponseHandler.error("MISSING_UUID", "Terminal uuid is required"))

        val activity = provider.activity
            ?: return response(ResponseHandler.error("NO_ACTIVITY", "Activity reference is null"))

        val terminal: Terminal =
            provider.terminalSdk?.getTerminal(activity, terminalUUID)
                ?: return response(
                    ResponseHandler.error(
                        "TERMINAL_NOT_FOUND",
                        "Terminal with uuid = $terminalUUID = not found"
                    )
                )
        Timber.d("Got Terminal successfully")
        try {
            terminal.getTerminalConfig(
                getTerminalConfigListener = object : GetTerminalConfigListener {
                    override fun onGetTerminalConfigSuccess(terminalConfig: TerminalConfig) {
                        response(
                            ResponseHandler.success(
                                "GetTerminalConfig Success",
                                terminalConfigToMap(terminalConfig)
                            )
                        )
                    }

                    override fun onGetTerminalConfigFailure(error: NearPayError) {
                        Timber.tag("onGetTerminalConfigFailure")
                            .d("GetTerminalConfig failed $error")
                        response(
                            ResponseHandler.error(
                                "GetTerminalConfig Failure",
                                error.toString()
                            )
                        )
                    }
                }
            )
        } catch (e: Exception) {
            response(ResponseHandler.error("GET_TERMINAL_CONFIG_FAILED", e.message ?: "Unknown error"))
        }
    }

    private fun terminalConfigToMap(config: TerminalConfig): Map<String, Any> {
        return mapOf(
            "currencyNumericCode" to config.currencyNumericCode,
            "currencyDefaultFractionDigits" to config.currencyDefaultFractionDigits,
            "schemes" to config.schemes.map { scheme ->
                mapOf(
                    "code" to scheme.code,
                    "allowedTransactionTypes" to scheme.allowedTransactionTypes
                )
            }
        )
    }
}
