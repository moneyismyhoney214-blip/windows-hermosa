package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import timber.log.Timber

class GetUsersOperation(provider: NearpayProvider) : BaseOperation(provider) {
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {


        val userList = provider.terminalSdk?.getUsers() ?: return response(
            ResponseHandler.error("INVALID_USERS", "No users found")
        )

        val mMap =
            mutableMapOf<String, Map<String, String?>>()  // Correct mutable map initialization

        for (user in userList) {
            Timber.d("first loop user uuid: ${user.first}")
            Timber.d("first loop user name: ${user.second}")

            val simpleUser = mapOf(
                // Use mapOf to create a map
                "userUUID" to user.first,  // Correct the key-value pairing
                "name" to user.second, // Correct the key-value pairing
            )

            mMap[user.first ?: "unknown"] = simpleUser  // Add the map entry to mMap
        }

        response(ResponseHandler.success("Users fetched successfully: $userList", mMap))


    }
}
