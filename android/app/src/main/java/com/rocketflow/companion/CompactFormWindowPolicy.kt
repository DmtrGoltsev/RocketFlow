package com.rocketflow.companion

internal data class FormWindowInsets(
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int
)

internal object CompactFormWindowPolicy {
    private const val COMPACT_LANDSCAPE_MAX_HEIGHT_DP = 599

    fun shouldUseCompactLayout(isLandscape: Boolean, screenHeightDp: Int): Boolean {
        return isLandscape && screenHeightDp in 1..COMPACT_LANDSCAPE_MAX_HEIGHT_DP
    }

    fun resolvePadding(
        systemBars: FormWindowInsets,
        ime: FormWindowInsets,
        usesExplicitImeInsets: Boolean
    ): FormWindowInsets {
        return FormWindowInsets(
            left = maxOf(systemBars.left, if (usesExplicitImeInsets) ime.left else 0),
            top = systemBars.top,
            right = maxOf(systemBars.right, if (usesExplicitImeInsets) ime.right else 0),
            bottom = maxOf(systemBars.bottom, if (usesExplicitImeInsets) ime.bottom else 0)
        )
    }
}
