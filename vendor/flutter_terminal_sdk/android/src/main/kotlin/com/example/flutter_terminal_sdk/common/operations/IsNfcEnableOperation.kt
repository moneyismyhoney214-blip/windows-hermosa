package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import timber.log.Timber

class IsNfcEnableOperation(provider: NearpayProvider) : BaseOperation(provider) {

    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {
        try {
            val isEnable = provider.isNfcEnabled()

            Timber.d("Nfc: $isEnable")

            response(ResponseHandler.success("Get NFC status successfully", isEnable))
        } catch (e: Throwable) {
            response(
                ResponseHandler.error(
                    "NFC_STATUS_FAILED",
                    e.message ?: "Unable to get NFC status",
                )
            )
        }

    }
}
