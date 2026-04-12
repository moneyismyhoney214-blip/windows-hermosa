package com.example.flutter_terminal_sdk

import NearpayOperatorFactory
import android.app.Activity
import android.content.Context
import androidx.annotation.NonNull
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.example.flutter_terminal_sdk.common.NearpayProvider
import timber.log.Timber
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class FlutterTerminalSdkPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private var activity: Activity? = null
    private var provider: NearpayProvider? = null
    private var operatorFactory: NearpayOperatorFactory? = null
    private val pluginScope = CoroutineScope(Dispatchers.IO)


    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        Timber.uprootAll() // Remove any existing Timber logs
        context?.let { Timber.plant(NearpayFileLogTree(it)) }
        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree())
        }

        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "nearpay_plugin")
        channel.setMethodCallHandler(this)
        val providerRef = NearpayProvider(channel)
        provider = providerRef
        operatorFactory = NearpayOperatorFactory(providerRef)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        val providerRef = provider ?: NearpayProvider(channel).also {
            provider = it
            operatorFactory = NearpayOperatorFactory(it)
        }
        providerRef.attachActivity(binding.activity)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        provider?.dispose()
        operatorFactory = null
        provider = null
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
        provider?.detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val argsFilter = ArgsFilter(call.arguments())

        when (call.method) {
            "initialize" -> {
                val providerRef = provider
                if (providerRef == null) {
                    result.error(
                        "PLUGIN_NOT_ATTACHED_TO_ACTIVITY",
                        "Nearpay plugin requires an attached Activity before initialization. Ensure the app is in foreground.",
                        null
                    )
                    return
                }

                pluginScope.launch {
                    try {
                        if (!providerRef.isInitialized()) {
                            providerRef.initializeSdk(argsFilter)
                        }

                        if (operatorFactory == null) {
                            operatorFactory = NearpayOperatorFactory(providerRef)
                        }
                        Timber.d("Did initialize")
                        withContext(Dispatchers.Main) {
                            result.success("Initialization successful")
                        }
                    } catch (e: Throwable) {
                        withContext(Dispatchers.Main) {
                            result.error(
                                "INITIALIZATION_FAILED",
                                "Failed to initialize Nearpay plugin: ${e.message}",
                                e
                            )
                        }
                    }
                }
            }

            else -> {
                val operationFactory = operatorFactory
                if (operationFactory == null) {
                    result.error(
                        "PLUGIN_NOT_INITIALIZED",
                        "Nearpay plugin not initialized properly. Ensure you have called the initialize method first.",
                        null
                    )
                    return
                }

                val operation = operationFactory.getOperation(call.method)

                if (operation != null) {
                    operation.run(argsFilter) { response ->
                        result.success(response)
                    }
                } else {
                    result.notImplemented()
                }
            }
        }
    }
}
