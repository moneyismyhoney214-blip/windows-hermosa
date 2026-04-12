package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import io.nearpay.terminalsdk.data.dto.EmailLogin
import io.nearpay.terminalsdk.data.dto.OtpResponse
import io.nearpay.terminalsdk.listeners.SendOTPEmailListener
import io.nearpay.terminalsdk.listeners.failures.OTPEmailFailure
import timber.log.Timber

class SendEmailOtpOperation(provider: NearpayProvider) : BaseOperation(provider) {
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {
        val email = filter.getString("email") ?: return response(
            ResponseHandler.error("MISSING_EMAIL", "Email is required")
        )

        provider.terminalSdk?.sendOTP(EmailLogin(email), object : SendOTPEmailListener {
            override fun onSendOTPEmailSuccess(otpResponse: OtpResponse) {
                Timber.d("OTP sent successfully: $otpResponse")
                response(ResponseHandler.success("OTP sent successfully"))
            }

            override fun onSendOTPEmailFailure(otpEmailFailure: OTPEmailFailure) {
                Timber.e("OTP email failure: $otpEmailFailure")
                response(ResponseHandler.error("OTP_FAILURE", otpEmailFailure.toString()))
            }
        })
    }
}
