package com.rocketflow.companion.focus

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FocusDeepLinkCoordinatorUnitTest {
    @Test
    fun coldStartFocusDeepLinkLoadsExactlyOnceAfterSessionBootstrap() {
        val coordinator = FocusDeepLinkCoordinator()
        var loads = 0

        coordinator.markPending()
        assertFalse(coordinator.openIfReady(hasSession = false) { loads += 1 })
        assertTrue(coordinator.openIfReady(hasSession = true) { loads += 1 })
        assertFalse(coordinator.openIfReady(hasSession = true) { loads += 1 })

        assertEquals(1, loads)
    }

    @Test
    fun warmFocusDeepLinkOpensImmediatelyAndIsConsumedOnce() {
        val coordinator = FocusDeepLinkCoordinator()
        var loads = 0

        coordinator.markPending()
        assertTrue(coordinator.openIfReady(hasSession = true) { loads += 1 })
        assertFalse(coordinator.openIfReady(hasSession = true) { loads += 1 })

        assertEquals(1, loads)
    }
}
