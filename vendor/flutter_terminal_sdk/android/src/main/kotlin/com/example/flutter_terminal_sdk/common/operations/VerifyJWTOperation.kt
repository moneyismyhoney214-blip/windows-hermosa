package com.example.flutter_terminal_sdk.common.operations


import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import com.example.flutter_terminal_sdk.common.status.ResponseHandler
import io.nearpay.terminalsdk.Terminal
import io.nearpay.terminalsdk.data.dto.JWTLoginData
import io.nearpay.terminalsdk.listeners.JWTLoginListener
import io.nearpay.terminalsdk.listeners.failures.JWTLoginFailure
import timber.log.Timber


class VerifyJWTOperation(provider: NearpayProvider) : BaseOperation(provider) {
    override fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit) {

        val jwt = filter.getString("jwt") ?: return response(
            ResponseHandler.error("MISSING_JWT", "jwt is required")
        )

        Timber.tag("NearPay-JWT").d("═══════════════════════════════════════")
        Timber.tag("NearPay-JWT").d("jwtLogin called")
        Timber.tag("NearPay-JWT").d("  jwt_length: ${jwt.length}")
        Timber.tag("NearPay-JWT").d("  jwt_parts: ${jwt.split(".").size}")
        Timber.tag("NearPay-JWT").d("  jwt_preview: ${jwt.take(15)}...${jwt.takeLast(15)}")
        Timber.tag("NearPay-JWT").d("  sdk_instance: ${provider.terminalSdk != null}")
        Timber.tag("NearPay-JWT").d("═══════════════════════════════════════")

        val loginData = JWTLoginData(
            jwt = jwt,
        )

        if (provider.terminalSdk == null) {
            Timber.tag("NearPay-JWT").e("SDK is NULL! Cannot call jwtLogin")
            return response(ResponseHandler.error("SDK_NULL", "TerminalSDK is not initialized"))
        }

        provider.terminalSdk?.jwtLogin(loginData, object : JWTLoginListener {

            override fun onJWTLoginSuccess(terminal: Terminal) {
                // Cache the terminal so PurchaseOperation can use it directly
                provider.jwtTerminal = terminal

                Timber.tag("NearPay-JWT").d("✅ jwtLogin SUCCESS!")
                Timber.tag("NearPay-JWT").d("═══ Terminal Object Fields ═══")
                Timber.tag("NearPay-JWT").d("  tid: ${terminal.tid}")
                Timber.tag("NearPay-JWT").d("  terminalUUID: ${terminal.terminalUUID}")
                Timber.tag("NearPay-JWT").d("  name: ${terminal.name}")
                Timber.tag("NearPay-JWT").d("  isReady: ${terminal.isTerminalReady()}")

                // Log all accessible fields/methods of Terminal via reflection
                try {
                    val terminalClass = terminal::class.java
                    Timber.tag("NearPay-JWT").d("═══ Terminal Class Info ═══")
                    Timber.tag("NearPay-JWT").d("  class: ${terminalClass.name}")
                    Timber.tag("NearPay-JWT").d("  superclass: ${terminalClass.superclass?.name}")
                    for (field in terminalClass.declaredFields) {
                        field.isAccessible = true
                        try {
                            val value = field.get(terminal)
                            Timber.tag("NearPay-JWT").d("  field[${field.name}]: $value")
                        } catch (e: Throwable) {
                            Timber.tag("NearPay-JWT").d("  field[${field.name}]: <error: ${e.message}>")
                        }
                    }
                    for (method in terminalClass.declaredMethods) {
                        if (method.parameterCount == 0 && method.name.startsWith("get")) {
                            Timber.tag("NearPay-JWT").d("  method: ${method.name}()")
                        }
                    }
                } catch (e: Throwable) {
                    Timber.tag("NearPay-JWT").w("  reflection failed: ${e.message}")
                }

                // Resolve user UUID via getUsers()
                var clientUuid: String? = null
                Timber.tag("NearPay-JWT").d("═══ getUsers() Probe ═══")
                try {
                    val users = provider.terminalSdk?.getUsers()
                    Timber.tag("NearPay-JWT").d("  getUsers() returned: ${users?.size ?: "null"} entries")
                    if (!users.isNullOrEmpty()) {
                        for ((index, user) in users.withIndex()) {
                            Timber.tag("NearPay-JWT").d("  user[$index]: first=${user.first}, second=${user.second}")
                        }
                        clientUuid = users.first().first
                        Timber.tag("NearPay-JWT").d("  → selected clientUuid: $clientUuid")
                    } else {
                        Timber.tag("NearPay-JWT").w("  getUsers returned EMPTY — client will be null")
                        Timber.tag("NearPay-JWT").w("  This means jwtLogin did NOT register a user in the SDK")
                        Timber.tag("NearPay-JWT").w("  connectTerminal will fail with 'User not found' for ANY UUID")
                    }
                } catch (e: Throwable) {
                    Timber.tag("NearPay-JWT").e("  getUsers EXCEPTION: ${e::class.simpleName}: ${e.message}")
                    Timber.tag("NearPay-JWT").e("  stackTrace: ${e.stackTraceToString().take(500)}")
                }

                // Also try getUserByUUID with the JWT's client_uuid if available
                Timber.tag("NearPay-JWT").d("═══ getUserByUUID Probe ═══")
                try {
                    // Decode JWT payload to extract client_uuid
                    val parts = jwt.split(".")
                    if (parts.size >= 2) {
                        val payload = String(android.util.Base64.decode(parts[1], android.util.Base64.URL_SAFE or android.util.Base64.NO_PADDING))
                        Timber.tag("NearPay-JWT").d("  JWT payload: $payload")
                        val jsonPayload = org.json.JSONObject(payload)
                        val dataObj = if (jsonPayload.has("data")) jsonPayload.getJSONObject("data") else jsonPayload
                        val jwtClientUuid = if (dataObj.has("client_uuid")) dataObj.getString("client_uuid") else null
                        Timber.tag("NearPay-JWT").d("  JWT client_uuid: $jwtClientUuid")

                        if (jwtClientUuid != null) {
                            try {
                                val user = provider.terminalSdk?.getUserByUUID(jwtClientUuid)
                                Timber.tag("NearPay-JWT").d("  getUserByUUID($jwtClientUuid): SUCCESS → $user")
                                if (clientUuid == null) {
                                    clientUuid = jwtClientUuid
                                    Timber.tag("NearPay-JWT").d("  → using JWT client_uuid as clientUuid since getUsers was empty")
                                }
                            } catch (e: Throwable) {
                                Timber.tag("NearPay-JWT").w("  getUserByUUID($jwtClientUuid): FAILED → ${e.message}")
                            }
                        }
                    }
                } catch (e: Throwable) {
                    Timber.tag("NearPay-JWT").w("  JWT decode/getUserByUUID probe failed: ${e.message}")
                }

                fun buildResultData(): Map<String, Any?> = mapOf(
                    "tid" to terminal.tid,
                    "isReady" to terminal.isTerminalReady(),
                    "terminalUUID" to terminal.terminalUUID,
                    "uuid" to terminal.terminalUUID,
                    "name" to terminal.name,
                    "client" to clientUuid,
                )

                // Wait for the terminal to finish provisioning (key loading,
                // server handshake, etc.).  First-time provisioning on a new
                // device can take 10-30 seconds.
                Timber.tag("jwtLoginSuccess").d("Terminal is ready: ${terminal.isTerminalReady()}")

                if (terminal.isTerminalReady()) {
                    Timber.tag("jwtLoginSuccess").d("Terminal is already ready")
                    response(
                        ResponseHandler.success(
                            "Login successful: ${terminal.terminalUUID}",
                            buildResultData()
                        )
                    )
                } else {
                    Timber.tag("jwtLoginSuccess").d("Terminal is not ready — polling up to 60s...")
                    val handler = android.os.Handler(android.os.Looper.getMainLooper())
                    val maxAttempts = 30          // 30 × 2s = 60s max
                    var attempt = 0
                    val pollRunnable = object : Runnable {
                        override fun run() {
                            attempt++
                            val ready = terminal.isTerminalReady()
                            Timber.tag("jwtLoginSuccess")
                                .d("  poll #$attempt/${maxAttempts}: isReady=$ready")
                            if (ready) {
                                Timber.tag("jwtLoginSuccess")
                                    .d("✅ Terminal became ready after ${attempt * 2}s")
                                response(
                                    ResponseHandler.success(
                                        "Login successful: ${terminal.terminalUUID}",
                                        buildResultData()
                                    )
                                )
                            } else if (attempt >= maxAttempts) {
                                Timber.tag("jwtLoginSuccess")
                                    .w("⚠️ Terminal still not ready after 60s — returning anyway")
                                response(
                                    ResponseHandler.success(
                                        "Login successful but terminal may not be ready: ${terminal.terminalUUID}",
                                        buildResultData()
                                    )
                                )
                            } else {
                                handler.postDelayed(this, 2000)
                            }
                        }
                    }
                    handler.postDelayed(pollRunnable, 2000)
                }
            }

            override fun onJWTLoginFailure(jwtLoginFailure: JWTLoginFailure) {
                Timber.tag("NearPay-JWT").e("═══════════════════════════════════════")
                Timber.tag("NearPay-JWT").e("❌ jwtLogin FAILED!")
                Timber.tag("NearPay-JWT").e("  failure_class: ${jwtLoginFailure::class.simpleName}")
                Timber.tag("NearPay-JWT").e("  failure_type: ${jwtLoginFailure::class.java.name}")

                val errorMessage = try {
                    (jwtLoginFailure as JWTLoginFailure.LoginFailure).message
                } catch (e: Exception) {
                    Timber.tag("NearPay-JWT").e("  cast_error: ${e.message}")
                    "Unknown failure: ${jwtLoginFailure::class.simpleName}"
                }

                Timber.tag("NearPay-JWT").e("  error_message: $errorMessage")
                Timber.tag("NearPay-JWT").e("  full_toString: $jwtLoginFailure")
                Timber.tag("NearPay-JWT").e("═══════════════════════════════════════")

                response(ResponseHandler.error("VERIFY_FAILURE", errorMessage.toString()))
            }
        })
    }
}