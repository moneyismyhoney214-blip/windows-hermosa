package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import io.nearpay.terminalsdk.TerminalConnection
import io.nearpay.terminalsdk.listeners.GetTerminalsListener
import io.nearpay.terminalsdk.listeners.failures.GetTerminalsFailure
import timber.log.Timber

class GetTerminalListOperation(provider: NearpayProvider) : BaseOperation(provider) {
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {
        val uuid = filter.getString("uuid") ?: return response(
            ResponseHandler.error("MISSING_UUID", "UUID is required")
        )
        val page = filter.getInt("page") ?: 1
        val pageSize = filter.getInt("pageSize") ?: 10
        val terminalFilter = filter.getString("filter")
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

        Timber.d("Fetching terminals for user with UUID: $uuid")
        // Flag to ensure only one response is sent
        var isResponseSent = false


        user.listTerminals(
            page = page,
            pageSize = pageSize,
            filter = terminalFilter,
            listener = object : GetTerminalsListener {
                override fun onGetTerminalsSuccess(terminalsConnection: List<TerminalConnection>, pagination: io.nearpay.terminalsdk.data.dto.Pagination) {
                    if (isResponseSent) return
                    Timber.d("Terminals fetched: ${terminalsConnection.size} terminals found")
                    isResponseSent = true
                    if (terminalsConnection.isEmpty()) {
                        response(
                            ResponseHandler.error(
                                "NO_TERMINALS",
                                "No terminals found for user with UUID: $uuid"
                            )
                        )
                    } else {
                        val mappedTerminals = terminalsConnection.map { t ->
                            mapOf(
                                "name" to t.terminalConnectionData.name,
                                "tid" to t.terminalConnectionData.tid,
                                "uuid" to t.terminalConnectionData.uuid,
                                "busy" to t.terminalConnectionData.busy,
                                "mode" to t.terminalConnectionData.mode,
                                "isLocked" to t.terminalConnectionData.isLocked,
                                "hasProfile" to t.terminalConnectionData.hasProfile,
                                "userUUID" to t.terminalConnectionData.userUUID,
                                "client" to t.terminalConnectionData.client,
                                "merchant" to t.terminalConnectionData.merchant?.let { m ->

                                    mapOf(
                                        "name" to m.name?.let { name ->
                                            mapOf(
                                                "arabic" to name.arabic,
                                                "english" to name.english
                                            )
                                        },
                                        "createdAt" to m.createdAt,
                                        "id" to m.id,
                                    )
                                }
                            )
                        }
                        response(
                            ResponseHandler.success(
                                "Terminals fetched",
                                mapOf("terminals" to mappedTerminals)
                            )
                        )
                    }
                }

                override fun onGetTerminalsFailure(getTerminalsFailure: GetTerminalsFailure) {
                    if (isResponseSent) return
                    Timber.e("Failed to fetch terminals: $getTerminalsFailure")
                    isResponseSent = true
                    response(
                        ResponseHandler.error(
                            "GET_TERMINALS_FAILURE",
                            getTerminalsFailure.toString()
                        )
                    )
                }
            }
        )
    }
}
