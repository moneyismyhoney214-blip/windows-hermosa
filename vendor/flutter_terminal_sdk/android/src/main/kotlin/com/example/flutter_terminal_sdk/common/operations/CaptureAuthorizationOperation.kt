package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import com.google.gson.Gson
import io.nearpay.terminalsdk.data.dto.CaptureResponse
import io.nearpay.terminalsdk.listeners.CaptureAuthorizationListener
import io.nearpay.terminalsdk.listeners.failures.CaptureAuthorizationFailure
import timber.log.Timber

class CaptureAuthorizationOperation(provider: NearpayProvider) : BaseOperation(provider) {
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

        terminal?.captureAuthorization(
            amount = amount,
            uuid = uuid,
            authorizationUuid = authorizationUuid,
            captureAuthorizationListener = object : CaptureAuthorizationListener {

                override fun onCaptureAuthorizationCompleted(captureAuthorization: CaptureResponse) {
                    Timber.tag("CaptureAuthorizationOperation")
                        .d("onCaptureAuthorizationCompleted $captureAuthorization")
                    val jsonString = gson.toJson(captureAuthorization)
                    val map = gson.fromJson(jsonString, Map::class.java) as Map<*, *>
                    response(
                        ResponseHandler.success(
                            "Capture authorization completed successfully",
                            map
                        )
                    )
                }

                override fun onCaptureAuthorizationFailure(captureAuthorizationFailure: CaptureAuthorizationFailure) {

                    Timber.tag("CaptureAuthorizationOperation")
                        .d("onCaptureAuthorizationFailure $captureAuthorizationFailure")
                    response(
                        ResponseHandler.error(
                            "CAPTURE_AUTHORIZATION_FAILURE",
                            captureAuthorizationFailure.toString()
                        )
                    )
                }

            }
        )

    }


}