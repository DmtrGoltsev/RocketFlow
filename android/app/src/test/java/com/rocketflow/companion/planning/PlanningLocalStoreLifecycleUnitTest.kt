package com.rocketflow.companion.planning

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class PlanningLocalStoreLifecycleUnitTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(DATABASE_NAME)
    }

    @After
    fun tearDown() {
        context.deleteDatabase(DATABASE_NAME)
    }

    @Test
    fun closeReleasesDatabaseAndASecondHelperCanOpenIt() {
        val firstStore = PlanningLocalStore(context)
        val firstDatabase = firstStore.writableDatabase
        assertTrue(firstDatabase.isOpen)

        firstStore.close()
        assertFalse(firstDatabase.isOpen)

        val secondStore = PlanningLocalStore(context)
        try {
            assertTrue(secondStore.readableDatabase.isOpen)
        } finally {
            secondStore.close()
        }
    }

    private companion object {
        const val DATABASE_NAME = "rocketflow_planning.db"
    }
}
