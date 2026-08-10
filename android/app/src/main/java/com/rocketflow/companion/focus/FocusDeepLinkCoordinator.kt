package com.rocketflow.companion.focus

internal class FocusDeepLinkCoordinator {
    private var pending = false

    fun markPending() {
        pending = true
    }

    fun openIfReady(hasSession: Boolean, open: () -> Unit): Boolean {
        if (!pending || !hasSession) return false
        pending = false
        open()
        return true
    }
}
