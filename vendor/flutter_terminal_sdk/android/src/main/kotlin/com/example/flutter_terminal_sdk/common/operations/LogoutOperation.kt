package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler

class LogoutOperation(provider: NearpayProvider) : BaseOperation(provider) {
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {
        val userUUID = filter.getString("userUUID") ?: return response(
            ResponseHandler.error("MISSING_userUUID", "userUUID is required")
        )

        provider.terminalSdk?.logout(userUUID) ?: return response(
            ResponseHandler.error("INVALID_USER", "No user found for UUID: $userUUID")
        )


        response(ResponseHandler.success("User logout successfully", null))

    }
}
