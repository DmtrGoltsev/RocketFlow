package com.rocketflow.companion.notifications

import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
class FocusNotificationUnitTest {
    @Test
    fun focusDeepLinkIsRecognized() {
        val intent = Intent().apply { data = NotificationIntents.focusDeepLink() }

        assertTrue(NotificationIntents.isFocusIntent(intent))
        assertFalse(NotificationIntents.isFocusIntent(Intent().apply { data = NotificationIntents.taskDeepLink("task-1") }))
    }

    @Test
    fun eventIdIsAcceptedOnce() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.getSharedPreferences("rocketflow_focus_notification_events", Context.MODE_PRIVATE).edit().clear().commit()
        val store = FocusNotificationEventStore(context)
        val eventId = UUID.randomUUID().toString()

        assertTrue(store.markIfNew(eventId))
        assertFalse(store.markIfNew(eventId))
    }

    @Test
    fun blankEventIdAndNotificationPayloadAreRejected() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        assertFalse(FocusNotificationEventStore(context).markIfNew("  "))
        val data = mapOf("type" to "focus_reminder", "periodId" to "period-1", "eventId" to "event-1")
        assertTrue(focusPushPayload(data, hasNotificationPayload = false) != null)
        assertTrue(focusPushPayload(data, hasNotificationPayload = true) == null)
        assertTrue(focusPushPayload(data - "eventId", hasNotificationPayload = false) == null)
    }

    @Test
    fun dedupeIsProcessWideAndExpiresAfterFourteenDays() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.getSharedPreferences("rocketflow_focus_notification_events", Context.MODE_PRIVATE).edit().clear().commit()
        var now = 1_000_000L
        val first = FocusNotificationEventStore(context) { now }
        val second = FocusNotificationEventStore(context) { now }

        assertTrue(first.markIfNew("event-1"))
        assertFalse(second.markIfNew("event-1"))
        now += FocusNotificationEventStore.RETENTION_MILLIS + 1
        assertTrue(second.markIfNew("event-1"))
    }
}
