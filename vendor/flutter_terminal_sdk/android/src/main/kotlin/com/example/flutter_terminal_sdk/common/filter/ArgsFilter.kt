package com.example.flutter_terminal_sdk.common.filter

class ArgsFilter(private val args: Map<*, *>?) {
    fun getString(key: String): String? = args?.get(key) as? String
    fun getLong(key: String): Long? = (args?.get(key) as? Number)?.toLong()
    fun getInt(key: String): Int? = (args?.get(key) as? Number)?.toInt()
    fun getBoolean(key: String): Boolean? = args?.get(key) as? Boolean
    fun getDouble(key: String): Double? = args?.get(key) as? Double
}