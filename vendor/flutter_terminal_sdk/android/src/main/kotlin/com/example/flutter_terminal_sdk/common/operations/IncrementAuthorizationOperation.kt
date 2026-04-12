package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import com.google.gson.Gson
import io.nearpay.terminalsdk.data.dto.IncrementResponse
import io.nearpay.terminalsdk.listeners.IncrementAuthorizationListener
import io.nearpay.terminalsdk.listeners.failures.IncrementAuthorizationFailure
import timber.log.Timber

class IncrementAuthorizationOperation(provider: NearpayProvider) : BaseOperation(provider) {
    private val gson = Gson()
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {

        val terminalUUID = filter.getString("terminalUUID")
            ?: return response(ResponseHandler.error("MISSING_UUID", "Terminal uuid is required"))

        val amount = filter.getLong("amount")
            ?: return response(ResponseHandler.error("MISSING_AMOUNT", "Amount is required"))


        val uuid = filter.getString("uuid")
            ?: return response(ResponseHandler.error("MISSING_UUID", "UUID is required"))

        val authorizationUuid = filter.getString("authorizationUuid")
            ?: return response(
                ResponseHandler.error(
                    "MISSING_AUTHORIZATION_UUID",
                    "Authorization UUID is required"
                )
            )


        val terminal =
            provider.activity?.let { provider.terminalSdk?.getTerminal(it, terminalUUID) }

        terminal?.incrementAuthorization(
            amount = amount,
            uuid = uuid,
            authorizationUuid = authorizationUuid,
            incrementAuthorizationListener = object : IncrementAuthorizationListener {

                override fun onIncrementAuthorizationCompleted(incrementAuthorization: IncrementResponse) {
                    Timber.tag("IncrementAuthorizationOperation")
                        .d("onIncrementAuthorizationCompleted $incrementAuthorization")
                    val jsonString = gson.toJson(incrementAuthorization)
                    val map = gson.fromJson(jsonString, Map::class.java) as Map<*, *>
                    response(
                        ResponseHandler.success(
                            "Increment authorization completed successfully",
                            map
                        )
                    )
                }

                override fun onIncrementAuthorizationFailure(incrementAuthorizationFailure: IncrementAuthorizationFailure) {
                    Timber.tag("IncrementAuthorizationOperation")
                        .d("onIncrementAuthorizationFailure $incrementAuthorizationFailure")
                    response(
                        ResponseHandler.error(
                            "INVALID_INCREMENT_AUTHORIZATION",
                            incrementAuthorizationFailure.toString()
                        )
                    )
                }

            },
        )

    }


}