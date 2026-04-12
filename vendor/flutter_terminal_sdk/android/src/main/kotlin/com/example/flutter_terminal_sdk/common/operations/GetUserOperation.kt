package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import timber.log.Timber

class GetUserOperation(provider: NearpayProvider) : BaseOperation(provider) {
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {
        val uuid = filter.getString("uuid") ?: return response(
            ResponseHandler.error("MISSING_UUID", "UUID is required")
        )

        Timber.d("GetUserOperation: $uuid")


        val user =
            try {
                provider.terminalSdk?.getUserByUUID(uuid)
                    ?: return response(
                        ResponseHandler.error("INVALID_USER", "No user found for UUID: $uuid")
                    )
            } catch (e: Throwable) {
                return response(
                    ResponseHandler.error("INVALID_USER", "${e.message}")
                )
            }

        val simpleUser = mapOf(
            "name" to user.name,
            "email" to user.email,
            "mobile" to user.mobile,
            "userUUID" to user.userUUID
        )

        response(ResponseHandler.success("User fetched successfully: ${user.name}", simpleUser))

    }
}
