package com.example.flutter_terminal_sdk.common.operations

import android.app.Activity
import android.os.Looper
import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import io.flutter.plugin.common.MethodChannel
import io.nearpay.terminalsdk.Terminal
import io.nearpay.terminalsdk.TerminalConnection
import io.nearpay.terminalsdk.TerminalSDK
import io.nearpay.terminalsdk.User
import io.nearpay.terminalsdk.data.dto.JWTLoginData
import io.nearpay.terminalsdk.data.dto.PaymentScheme
import io.nearpay.terminalsdk.listeners.ConnectTerminalListener
import io.nearpay.terminalsdk.listeners.GetTerminalByIdListener
import io.nearpay.terminalsdk.listeners.JWTLoginListener
import io.nearpay.terminalsdk.listeners.ReadCardListener
import io.nearpay.terminalsdk.listeners.SendTransactionListener
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.any
import org.mockito.kotlin.argumentCaptor
import org.mockito.kotlin.atLeast
import org.mockito.kotlin.doAnswer
import org.mockito.kotlin.eq
import org.mockito.kotlin.mock
import org.mockito.kotlin.verify
import org.mockito.kotlin.whenever
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], manifest = Config.NONE)
class NearpayFullFlowRobolectricTest {

    @Test
    fun purchaseWhenActivityIsNotAttached_returnsNoActivityError() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val methodChannel = mock<MethodChannel>()
        val provider = NearpayProvider(methodChannel)
        provider.terminalSdk = mock<TerminalSDK>()

        val purchaseOperation = PurchaseOperation(provider)
        var purchaseResponse: Map<String, Any>? = null
        purchaseOperation.run(
            ArgsFilter(
                mapOf(
                    "uuid" to "terminal-uuid-001",
                    "amount" to 5000L,
                    "scheme" to "MADA",
                    "intentUUID" to "intent-uuid-001",
                ),
            ),
        ) {
            purchaseResponse = it
        }

        assertNotNull(purchaseResponse)
        assertEquals("error", purchaseResponse?.get("status"))
        assertEquals("NO_ACTIVITY", purchaseResponse?.get("code"))
    }

    @Test
    fun fullFlow_initializeJwtConnectPurchase_emitsExpectedEvents() {
        val activity = Robolectric.buildActivity(Activity::class.java).setup().get()
        val methodChannel = mock<MethodChannel>()
        val provider = NearpayProvider(methodChannel)
        provider.attachActivity(activity)

        val terminalSdk = mock<TerminalSDK>()
        val terminal = mock<Terminal>()
        val user = mock<User>()
        val terminalConnection = mock<TerminalConnection>()
        provider.terminalSdk = terminalSdk

        whenever(terminal.tid).thenReturn("0211920500119205")
        whenever(terminal.terminalUUID).thenReturn("terminal-uuid-001")
        whenever(terminal.name).thenReturn("POS 1")
        whenever(terminal.isTerminalReady()).thenReturn(true)
        whenever(terminalSdk.getUsers()).thenReturn(
            listOf(Pair("client-uuid-001", "NearPay Test User")),
        )

        val initializeOperation = InitializeOperation(provider)
        var initResponse: Map<String, Any>? = null
        initializeOperation.run(ArgsFilter(emptyMap<String, Any>())) {
            initResponse = it
        }
        assertEquals("success", initResponse?.get("status"))

        doAnswer { invocation ->
            val listener = invocation.arguments[1] as JWTLoginListener
            listener.onJWTLoginSuccess(terminal)
            null
        }.whenever(terminalSdk).jwtLogin(any<JWTLoginData>(), any<JWTLoginListener>())

        val jwtOperation = VerifyJWTOperation(provider)
        var jwtResponse: Map<String, Any>? = null
        jwtOperation.run(
            ArgsFilter(
                mapOf(
                    "jwt" to resolveLiveOrFallbackJwt(),
                ),
            ),
        ) {
            jwtResponse = it
        }

        assertNotNull(jwtResponse)
        assertEquals("success", jwtResponse?.get("status"))
        val jwtData = jwtResponse?.get("data") as Map<*, *>
        assertEquals("client-uuid-001", jwtData["client"])
        assertEquals("0211920500119205", jwtData["tid"])

        whenever(terminalSdk.getUserByUUID("client-uuid-001")).thenReturn(user)
        doAnswer { invocation ->
            val listener = invocation.arguments[1] as GetTerminalByIdListener
            listener.onGetTerminalSuccess(terminalConnection)
            null
        }.whenever(user).getTerminalById(eq("terminal-uuid-001"), any<GetTerminalByIdListener>())

        doAnswer { invocation ->
            val listener = invocation.arguments[1] as ConnectTerminalListener
            listener.onConnectTerminalSuccess(terminal)
            null
        }.whenever(terminalConnection).connect(any<Activity>(), any<ConnectTerminalListener>())

        val connectOperation = ConnectTerminalOperation(provider)
        var connectResponse: Map<String, Any>? = null
        connectOperation.run(
            ArgsFilter(
                mapOf(
                    "tid" to "0211920500119205",
                    "terminalUUID" to "terminal-uuid-001",
                    "userUUID" to "client-uuid-001",
                ),
            ),
        ) {
            connectResponse = it
        }

        assertNotNull(connectResponse)
        assertEquals("success", connectResponse?.get("status"))
        val connectData = connectResponse?.get("data") as Map<*, *>
        assertEquals("terminal-uuid-001", connectData["terminalUUID"])
        assertEquals("0211920500119205", connectData["tid"])

        whenever(terminalSdk.getTerminal(any<Activity>(), eq("terminal-uuid-001")))
            .thenReturn(terminal)

        doAnswer { invocation ->
            val readCardListener = invocation.arguments[4] as ReadCardListener
            val sendTransactionListener = invocation.arguments[5] as SendTransactionListener
            readCardListener.onReaderDisplayed()
            readCardListener.onReadingStarted()
            readCardListener.onReaderWaiting()
            sendTransactionListener.onSendTransactionFailure(
                mock(),
            )
            null
        }.whenever(terminal).purchase(
            eq(5000L),
            eq(PaymentScheme.MADA),
            eq("intent-uuid-001"),
            eq("INV-1001"),
            any<ReadCardListener>(),
            any<SendTransactionListener>(),
        )

        val purchaseOperation = PurchaseOperation(provider)
        purchaseOperation.run(
            ArgsFilter(
                mapOf(
                    "uuid" to "terminal-uuid-001",
                    "amount" to 5000L,
                    "scheme" to "MADA",
                    "intentUUID" to "intent-uuid-001",
                    "customerReferenceNumber" to "INV-1001",
                ),
            ),
        ) {
            // PurchaseOperation reports lifecycle via purchaseEvent callbacks.
            // Response callback is used only for immediate argument/terminal errors.
        }

        shadowOf(Looper.getMainLooper()).idle()

        val eventCaptor = argumentCaptor<Any>()
        verify(methodChannel, atLeast(3)).invokeMethod(
            eq("purchaseEvent"),
            eventCaptor.capture(),
        )

        val eventTypes = eventCaptor.allValues
            .filterIsInstance<Map<*, *>>()
            .mapNotNull { it["type"] as? String }

        assertTrue(eventTypes.contains("readerDisplayed"))
        assertTrue(eventTypes.contains("readingStarted"))
        assertTrue(eventTypes.contains("readerWaiting"))
        assertTrue(eventTypes.contains("sendTransactionFailure"))
    }

    private fun resolveLiveOrFallbackJwt(): String {
        val systemProperty = System.getProperty("nearpay.test.jwt")?.trim()
        if (!systemProperty.isNullOrEmpty()) {
            return systemProperty
        }
        val envValue = System.getenv("NEARPAY_TEST_JWT")?.trim()
        if (!envValue.isNullOrEmpty()) {
            return envValue
        }
        return "header.payload.signature"
    }
}
