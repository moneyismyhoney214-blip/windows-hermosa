package com.example.flutter_terminal_sdk.common

import android.app.Activity
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import io.flutter.plugin.common.MethodChannel
import io.nearpay.softpos.reader_ui.UiDockPosition
import io.nearpay.softpos.reader_ui.utils.SupportSecondDisplay
import io.nearpay.terminalsdk.SdkEnvironment
import io.nearpay.terminalsdk.Terminal
import io.nearpay.terminalsdk.TerminalSDK
import io.nearpay.terminalsdk.data.dto.Country
import io.nearpay.terminalsdk.data.dto.PermissionStatus
import io.nearpay.terminalsdk.listeners.TerminalSDKInitializationListener
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import timber.log.Timber

class NearpayProvider(val methodChannel: MethodChannel) {
    var activity: Activity? = null
    private var isSdkInitialized = false
    var terminalSdk: TerminalSDK? = null
    /** Terminal returned by jwtLogin — use this for purchases instead of getTerminal() */
    var jwtTerminal: Terminal? = null

    suspend fun initializeSdk(filter: ArgsFilter) {
        if (isSdkInitialized && terminalSdk != null) {
            Timber.tag("TerminalSDKInit").d("Reusing existing TerminalSDK instance")
            return
        }
        val attachedActivity = requireAttachedActivity()

        // Extract parameters from ArgsFilter (with some default values if needed)
        val environment = filter.getString("environment") ?: "sandbox"
        val googleCloudProjectNumber = filter.getLong("googleCloudProjectNumber") ?: 0L
        val huaweiSafetyDetectApiKey = filter.getString("huaweiSafetyDetectApiKey") ?: ""
        val country = filter.getString("country") ?: "sa"
        val uiDockPositionString = filter.getString("uiDockPosition")
        val secondDisplayDockPosition = filter.getString("secondDisplayDockPosition")
        val supportSecondDisplay = filter.getString("supportSecondDisplay")

        Timber.d("Initializing TerminalSDK with uiDockPositionString: $uiDockPositionString")
        Timber.d("Initializing TerminalSDK with secondDisplayDockPosition: $secondDisplayDockPosition")
        Timber.d("Initializing TerminalSDK with UiDockPosition: ${UiDockPosition.toString()}")
        Timber.d("Initializing TerminalSDK with country: $country")
        Timber.d("Initializing TerminalSDK with supportSecondDisplay: $supportSecondDisplay")

        // Convert environment string to SdkEnvironment enum
        val sdkEnvironment = when (environment.uppercase()) {
            "PRODUCTION" -> SdkEnvironment.PRODUCTION
            "SANDBOX" -> SdkEnvironment.SANDBOX
            "INTERNAL" -> SdkEnvironment.INTERNAL
            else -> SdkEnvironment.SANDBOX // Fallback
        }

        // Convert country string to Country enum
        val sdkCountry = when (country.uppercase()) {
            "SA" -> Country.SA
            "TR" -> Country.TR
            "USA" -> Country.USA
            else -> Country.SA // Fallback
        }


        val uiDockPosition = when (uiDockPositionString?.uppercase()) {
            "TOP_LEFT" -> UiDockPosition.TOP_LEFT
            "TOP_RIGHT" -> UiDockPosition.TOP_RIGHT
            "BOTTOM_LEFT" -> UiDockPosition.BOTTOM_LEFT
            "BOTTOM_RIGHT" -> UiDockPosition.BOTTOM_RIGHT
            "CENTER_RIGHT" -> UiDockPosition.CENTER_RIGHT
            "CENTER_LEFT" -> UiDockPosition.CENTER_LEFT
            "ABSOLUTE_CENTER" -> UiDockPosition.ABSOLUTE_CENTER
            "TOP_CENTER" -> UiDockPosition.TOP_CENTER
            "BOTTOM_CENTER" -> UiDockPosition.BOTTOM_CENTER
            else -> null // Fallback to default if not provided
        }
        val secondDisplayDockPositionValue = when (secondDisplayDockPosition?.uppercase()) {
            "TOP_LEFT" -> UiDockPosition.TOP_LEFT
            "TOP_RIGHT" -> UiDockPosition.TOP_RIGHT
            "BOTTOM_LEFT" -> UiDockPosition.BOTTOM_LEFT
            "BOTTOM_RIGHT" -> UiDockPosition.BOTTOM_RIGHT
            "CENTER_RIGHT" -> UiDockPosition.CENTER_RIGHT
            "CENTER_LEFT" -> UiDockPosition.CENTER_LEFT
            "ABSOLUTE_CENTER" -> UiDockPosition.ABSOLUTE_CENTER
            "TOP_CENTER" -> UiDockPosition.TOP_CENTER
            "BOTTOM_CENTER" -> UiDockPosition.BOTTOM_CENTER
            else -> null // Fallback to default if not provided
        }

        val supportSecondDisplayValue = when (supportSecondDisplay?.uppercase()) {
            "ENABLE" -> SupportSecondDisplay.ENABLE
            "DISABLE" -> SupportSecondDisplay.DISABLE
            "INITIAL" -> SupportSecondDisplay.DEFAULT
            else -> SupportSecondDisplay.DEFAULT // Fallback
        }

        Timber.d("Initializing TerminalSDK with supportSecondDisplay: $supportSecondDisplayValue")
        Timber.d("Initializing TerminalSDK with secondDisplayDockPosition: $secondDisplayDockPositionValue")
        Timber.d("Initializing TerminalSDK with uiDockPosition: $uiDockPosition")
        Timber.d("Initializing TerminalSDK with sdkEnvironment: $sdkEnvironment")
        Timber.d("Initializing TerminalSDK with country: $sdkCountry")
        try {
            terminalSdk = TerminalSDK.Builder()
                .activity(attachedActivity)
                .environment(sdkEnvironment)
                .googleCloudProjectNumber(googleCloudProjectNumber)
                .huaweiSafetyDetectApiKey(huaweiSafetyDetectApiKey)
                .uiDockPosition(uiDockPosition) // Optional: set the location of the Tap to Pay modal
                .country(sdkCountry)
                .supportSecondDisplay(supportSecondDisplayValue)
                .secondDisplayDockPosition(secondDisplayDockPositionValue)
                .initializationListener(object : TerminalSDKInitializationListener {
                    override fun onInitializationFailure(throwable: Throwable) {
                        Timber.tag("TerminalSDKInit")
                            .e(throwable, "TerminalSDK initialization failed")
                        CoroutineScope(Dispatchers.IO).launch {
                            withContext(Dispatchers.Main) {
                                methodChannel.invokeMethod(
                                    "onSdkInitializationFailed",
                                    mapOf(
                                        "error" to throwable.message
                                    )
                                )
                            }
                        }


                    }

                    override fun onInitializationSuccess() {
                        Timber.tag("TerminalSDKInit").d("TerminalSDK initialized successfully")

                        CoroutineScope(Dispatchers.IO).launch {
                            withContext(Dispatchers.Main) {
                                methodChannel.invokeMethod("onSdkInitialized", null)
                            }
                        }

                    }
                })
                .build()


            isSdkInitialized = true
        } catch (e: Throwable) {
            Timber.tag("TerminalSDKInit").e(e, "Failed to initialize TerminalSDK")
            throw RuntimeException("Failed to initialize TerminalSDK: ${e.message}", e)
        }
    }

    fun isInitialized(): Boolean {
        return isSdkInitialized
    }

    fun attachActivity(currentActivity: Activity) {
        activity = currentActivity
    }

    fun detachActivity() {
        activity = null
    }

    fun dispose() {
        activity = null
        isSdkInitialized = false
        terminalSdk = null
    }

    fun requireAttachedActivity(): Activity {
        return activity ?: throw IllegalStateException(
            "Activity reference is null. Ensure plugin is attached to an Activity before calling NearPay SDK."
        )
    }

    fun retrieveTerminalSdk(): TerminalSDK {
        val sdk = terminalSdk
        if (!isSdkInitialized || sdk == null) {
            throw IllegalStateException("TerminalSDK is not initialized. Call initializeSdk() first.")
        }
        return sdk
    }

    fun checkRequiredPermissions(): List<PermissionStatus> {
        return retrieveTerminalSdk().checkRequiredPermissions()
    }

    fun isNfcEnabled(): Boolean {
        val attachedActivity = requireAttachedActivity()
        return retrieveTerminalSdk().isNfcEnabled(attachedActivity)
    }

    fun isWifiEnabled(): Boolean {
        val attachedActivity = requireAttachedActivity()
        return retrieveTerminalSdk().isWifiEnabled(attachedActivity)
    }
}
