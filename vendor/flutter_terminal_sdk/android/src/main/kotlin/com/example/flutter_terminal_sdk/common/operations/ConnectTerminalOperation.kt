package com.example.flutter_terminal_sdk.common.operations

import android.app.Activity
import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import io.nearpay.terminalsdk.Terminal
import io.nearpay.terminalsdk.TerminalConnection
import io.nearpay.terminalsdk.listeners.ConnectTerminalListener
import io.nearpay.terminalsdk.listeners.GetTerminalByIdListener
import io.nearpay.terminalsdk.listeners.failures.ConnectTerminalFailure
import io.nearpay.terminalsdk.listeners.failures.GetTerminalByIdFailure
import timber.log.Timber

class ConnectTerminalOperation(provider: NearpayProvider) : BaseOperation(provider) {
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {

        val tid = filter.getString("tid")
            ?: return response(ResponseHandler.error("MISSING_TID", "Terminal TID is required"))

        val terminalUUID = filter.getString("terminalUUID")
            ?: return response(ResponseHandler.error("MISSING_TID", "Terminal TID is required"))

        val userUUID = filter.getString("userUUID")
            ?: return response(ResponseHandler.error("MISSING_USER_UUID", "User UUID is required"))

        Timber.tag("ConnectTerminalOperation").d("═══════════════════════════════════════")
        Timber.tag("ConnectTerminalOperation").d("connectTerminal called")
        Timber.tag("ConnectTerminalOperation").d("  tid: $tid")
        Timber.tag("ConnectTerminalOperation").d("  terminalUUID: $terminalUUID")
        Timber.tag("ConnectTerminalOperation").d("  userUUID: $userUUID")

        // Log all available users BEFORE attempting getUserByUUID
        try {
            val allUsers = provider.terminalSdk?.getUsers()
            Timber.tag("ConnectTerminalOperation").d("═══ SDK Users State ═══")
            Timber.tag("ConnectTerminalOperation").d("  total users in SDK: ${allUsers?.size ?: "null (SDK is null)"}")
            if (!allUsers.isNullOrEmpty()) {
                for ((index, user) in allUsers.withIndex()) {
                    Timber.tag("ConnectTerminalOperation").d("  user[$index]: uuid=${user.first}, name=${user.second}")
                }
            } else {
                Timber.tag("ConnectTerminalOperation").w("  ⚠️ NO USERS registered in SDK — getUserByUUID will ALWAYS fail")
                Timber.tag("ConnectTerminalOperation").w("  This means jwtLogin did not create a user entry")
            }
        } catch (e: Throwable) {
            Timber.tag("ConnectTerminalOperation").e("  getUsers() failed: ${e.message}")
        }

        Timber.tag("ConnectTerminalOperation").d("═══ getUserByUUID($userUUID) ═══")
        val user =
            try {
                provider.terminalSdk?.getUserByUUID(userUUID)
                    ?: run {
                        Timber.tag("ConnectTerminalOperation").e("  getUserByUUID returned NULL for: $userUUID")
                        return response(
                            ResponseHandler.error("INVALID_USER", "No user found for UUID: $userUUID")
                        )
                    }
            } catch (e: Throwable) {
                Timber.tag("ConnectTerminalOperation").e("═══ getUserByUUID FAILED ═══")
                Timber.tag("ConnectTerminalOperation").e("  userUUID: $userUUID")
                Timber.tag("ConnectTerminalOperation").e("  error_class: ${e::class.simpleName}")
                Timber.tag("ConnectTerminalOperation").e("  error_message: ${e.message}")
                Timber.tag("ConnectTerminalOperation").e("  stackTrace: ${e.stackTraceToString().take(500)}")
                return response(
                    ResponseHandler.error(
                        "GET_USER_BY_UUID_FAILURE",
                        e.message ?: "Unknown error"
                    )
                )
            }

        Timber.tag("ConnectTerminalOperation").d("  ✅ getUserByUUID SUCCESS")
        Timber.tag("ConnectTerminalOperation").d("  user object: $user")
        try {
            Timber.tag("ConnectTerminalOperation").d("  user.name: ${user.name}")
            Timber.tag("ConnectTerminalOperation").d("  user.email: ${user.email}")
            Timber.tag("ConnectTerminalOperation").d("  user.mobile: ${user.mobile}")
            Timber.tag("ConnectTerminalOperation").d("  user.userUUID: ${user.userUUID}")
        } catch (e: Throwable) {
            Timber.tag("ConnectTerminalOperation").d("  user field access error: ${e.message}")
        }

        val activity: Activity = provider.activity
            ?: return response(ResponseHandler.error("NO_ACTIVITY", "Activity reference is null"))

        Timber.tag("ConnectTerminalOperation").d("═══ getTerminalById($terminalUUID) ═══")

        user.getTerminalById(terminalUUID, object : GetTerminalByIdListener {
            override fun onGetTerminalSuccess(terminalConnection: TerminalConnection) {
                Timber.tag("ConnectTerminalOperation").d("  ✅ getTerminalById SUCCESS")
                Timber.tag("ConnectTerminalOperation").d("  terminalConnection: $terminalConnection")
                Timber.tag("ConnectTerminalOperation").d("═══ connect(activity) ═══")

                terminalConnection.connect(activity, object : ConnectTerminalListener {
                    override fun onConnectTerminalSuccess(terminal: Terminal) {
                        Timber.tag("ConnectTerminalOperation").d("═══ CONNECT SUCCESS ═══")
                        Timber.tag("ConnectTerminalOperation").d("  tid: ${terminal.tid}")
                        Timber.tag("ConnectTerminalOperation").d("  terminalUUID: ${terminal.terminalUUID}")
                        Timber.tag("ConnectTerminalOperation").d("  name: ${terminal.name}")
                        Timber.tag("ConnectTerminalOperation").d("  isReady: ${terminal.isTerminalReady()}")

                        val resultData = mapOf(
                            "tid" to terminal.tid,
                            "isReady" to terminal.isTerminalReady(),
                            "terminalUUID" to terminal.terminalUUID,
                            "uuid" to terminalUUID,
                            "name" to terminal.name,
                        )
                        response(
                            ResponseHandler.success(
                                "Connected to terminal",
                                resultData
                            )
                        )
                    }

                    override fun onConnectTerminalFailure(connectTerminalFailure: ConnectTerminalFailure) {
                        Timber.tag("ConnectTerminalOperation").e("═══ CONNECT FAILED ═══")
                        Timber.tag("ConnectTerminalOperation").e("  failure: $connectTerminalFailure")
                        Timber.tag("ConnectTerminalOperation").e("  failure_class: ${connectTerminalFailure::class.simpleName}")
                        response(
                            ResponseHandler.error(
                                "CONNECT_FAILURE",
                                connectTerminalFailure.toString()
                            )
                        )
                    }
                })
            }

            override fun onGetTerminalFailure(getTerminalByIdFailure: GetTerminalByIdFailure) {
                Timber.tag("ConnectTerminalOperation").e("═══ getTerminalById FAILED ═══")
                Timber.tag("ConnectTerminalOperation").e("  terminalUUID: $terminalUUID")
                Timber.tag("ConnectTerminalOperation").e("  failure: $getTerminalByIdFailure")
                Timber.tag("ConnectTerminalOperation").e("  failure_class: ${getTerminalByIdFailure::class.simpleName}")
                response(
                    ResponseHandler.error(
                        "GET_TERMINAL_BY_ID_FAILURE",
                        getTerminalByIdFailure.toString()
                    )
                )
            }
        })
    }
}
