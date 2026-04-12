package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import io.nearpay.terminalsdk.User
import io.nearpay.terminalsdk.data.dto.LoginData
import io.nearpay.terminalsdk.listeners.VerifyEmailListener
import io.nearpay.terminalsdk.listeners.failures.VerifyEmailFailure
import timber.log.Timber


class VerifyEmailOtpOperation(provider: NearpayProvider) : BaseOperation(provider) {
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {

        val email = filter.getString("email") ?: return response(
            ResponseHandler.error("MISSING_EMAIL", "Email is required")
        )
        val code = filter.getString("code") ?: return response(
            ResponseHandler.error("MISSING_CODE", "OTP code is required")
        )

        val loginData = LoginData(
            email = email,
            mobile = "",
            code = code,
        )
        try {


        provider.terminalSdk?.verify(loginData, object : VerifyEmailListener {

            override fun onVerifyEmailSuccess(user: User) {
                val simpleUser = mapOf(
                    "name" to user.name,
                    "email" to user.email,
                    "mobile" to user.mobile,
                    "userUUID" to user.userUUID
                )

                response(ResponseHandler.success("Login successful: ${user.name}", simpleUser))
            }

            override fun onVerifyEmailFailure(verifyEmailFailure: VerifyEmailFailure) {
                val errorMessage = verifyEmailFailure.toString()
                Timber.tag("verify").d("%s", verifyEmailFailure.toString())
                response(ResponseHandler.error("VERIFY_FAILURE", errorMessage))
            }
        })
        } catch (e: Throwable) {
            Timber.tag("verify").d("%s", e.message)
            response(ResponseHandler.error("VERIFY_FAILURE", e.message ?: "Unknown error"))
        }
    }
}