package com.example.flutter_terminal_sdk.common.operations

import com.example.flutter_terminal_sdk.common.NearpayProvider
import com.example.flutter_terminal_sdk.common.filter.ArgsFilter

abstract class BaseOperation(protected val provider: NearpayProvider) {
    abstract fun run(filter: ArgsFilter, response: (Map<String, Any>) -> Unit)
}