package com.example.flutter_terminal_sdk.common.operations
import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import io.nearpay.terminalsdk.data.dto.MobileLogin
import io.nearpay.terminalsdk.data.dto.OtpResponse
import io.nearpay.terminalsdk.listeners.SendOTPMobileListener
import io.nearpay.terminalsdk.listeners.failures.OTPMobileFailure

class SendMobileOtpOperation(provider: NearpayProvider) : BaseOperation(provider) {
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {
        val mobile = filter.getString("mobileNumber") ?: return response(
            ResponseHandler.error("MISSING_MOBILE", "Mobile number is required")
        )

        provider.terminalSdk?.sendOTP(MobileLogin(mobile), object : SendOTPMobileListener {
            override fun onSendOTPMobileSuccess(otpResponse: OtpResponse) {
                response(ResponseHandler.success("OTP sent successfully"))

            }

            override fun onSendOTPMobileFailure(otpMobileFailure: OTPMobileFailure) {
                response(ResponseHandler.error("OTP_FAILURE", otpMobileFailure.toString() ))
            }
        })
    }
}
