package com.example.flutter_terminal_sdk.common.operations


import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import io.nearpay.terminalsdk.User
import io.nearpay.terminalsdk.data.dto.LoginData
import io.nearpay.terminalsdk.listeners.VerifyMobileListener
import io.nearpay.terminalsdk.listeners.failures.VerifyMobileFailure
import timber.log.Timber


class VerifyMobileOtpOperation(provider: NearpayProvider) : BaseOperation(provider) {
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {

        val mobile = filter.getString("mobileNumber") ?: return response(
            ResponseHandler.error("MISSING_MOBILE", "Mobile number is required")
        )
        val code = filter.getString("code") ?: return response(
            ResponseHandler.error("MISSING_CODE", "OTP code is required")
        )

        val loginData = LoginData(
            mobile = mobile,
            code = code,
        )

        provider.terminalSdk?.verify(loginData, object : VerifyMobileListener {

            override fun onVerifyMobileSuccess(user: User) {
                val simpleUser = mapOf(
                    "name" to user.name,
                    "email" to user.email,
                    "mobile" to user.mobile,
                    "userUUID" to user.userUUID
                )

                response(ResponseHandler.success("Login successful: ${user.name}", simpleUser))
            }

            override fun onVerifyMobileFailure(verifyMobileFailure: VerifyMobileFailure) {
                val errorMessage = verifyMobileFailure.toString()
                Timber.tag("asdf").d("%s", verifyMobileFailure.toString())
                response(ResponseHandler.error("VERIFY_FAILURE", errorMessage))
            }
        })
    }
}