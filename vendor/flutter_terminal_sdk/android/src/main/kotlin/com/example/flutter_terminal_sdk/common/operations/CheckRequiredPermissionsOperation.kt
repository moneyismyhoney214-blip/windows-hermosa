package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import timber.log.Timber

class CheckRequiredPermissionsOperation(provider: NearpayProvider) : BaseOperation(provider) {

    //gson
    private val gson = Gson()

    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {
        try {
            val listOfPermissions = provider.checkRequiredPermissions()
            Timber.d("Permissions fetched: $listOfPermissions")

            val jsonString = gson.toJson(listOfPermissions)
            val map: List<Any> =
                gson.fromJson(jsonString, object : TypeToken<List<Any?>?>() {}.type)

            response(ResponseHandler.success("Get permissions successfully", map))
        } catch (e: Throwable) {
            response(
                ResponseHandler.error(
                    "CHECK_PERMISSIONS_FAILED",
                    e.message ?: "Not able to check permissions",
                )
            )
        }

    }
}
