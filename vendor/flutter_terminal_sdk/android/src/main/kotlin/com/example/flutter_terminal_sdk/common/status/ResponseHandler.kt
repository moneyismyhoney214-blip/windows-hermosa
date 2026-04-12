package com.example.flutter_terminal_sdk.common.status
object ResponseHandler {
    fun success(message: String, data: Any? = null): Map<String, Any> {
        return mapOf("status" to "success", "message" to message, "data" to (data ?: mapOf<String, Any>()))
    }

    fun error(code: String, message: String): Map<String, Any> {
        return mapOf("status" to "error", "code" to code, "message" to message)
    }
}


