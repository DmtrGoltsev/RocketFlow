package com.rocketflow.companion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CompactFormWindowPolicyUnitTest {
    @Test
    fun compactLandscapeUsesDedicatedFormLayout() {
        assertTrue(CompactFormWindowPolicy.shouldUseCompactLayout(isLandscape = true, screenHeightDp = 360))
        assertFalse(CompactFormWindowPolicy.shouldUseCompactLayout(isLandscape = false, screenHeightDp = 360))
        assertFalse(CompactFormWindowPolicy.shouldUseCompactLayout(isLandscape = true, screenHeightDp = 720))
    }

    @Test
    fun explicitImeInsetsKeepTheDialogAboveTheKeyboard() {
        val resolved = CompactFormWindowPolicy.resolvePadding(
            systemBars = FormWindowInsets(left = 0, top = 48, right = 0, bottom = 24),
            ime = FormWindowInsets(left = 0, top = 0, right = 0, bottom = 478),
            usesExplicitImeInsets = true
        )

        assertEquals(FormWindowInsets(left = 0, top = 48, right = 0, bottom = 478), resolved)
    }

    @Test
    fun resizedLegacyWindowDoesNotApplyImePaddingTwice() {
        val resolved = CompactFormWindowPolicy.resolvePadding(
            systemBars = FormWindowInsets(left = 12, top = 24, right = 16, bottom = 20),
            ime = FormWindowInsets(left = 0, top = 0, right = 0, bottom = 300),
            usesExplicitImeInsets = false
        )

        assertEquals(FormWindowInsets(left = 12, top = 24, right = 16, bottom = 20), resolved)
    }
}
