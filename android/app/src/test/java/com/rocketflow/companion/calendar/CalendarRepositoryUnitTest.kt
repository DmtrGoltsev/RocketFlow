package com.rocketflow.companion.calendar

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.rocketflow.companion.auth.AuthSession
import com.rocketflow.companion.auth.AuthTokens
import com.rocketflow.companion.auth.CurrentUser
import com.rocketflow.companion.auth.SessionBoundResult
import com.rocketflow.companion.focus.FocusLocalDataSource
import com.rocketflow.companion.network.ApiException
import com.rocketflow.companion.planning.PlanningLocalStore
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.IOException
import java.time.LocalDate

@RunWith(RobolectricTestRunner::class)
class CalendarRepositoryUnitTest {
    private lateinit var context: Context
    private lateinit var store: PlanningLocalStore
    private lateinit var local: FocusLocalDataSource
    private val session = AuthSession(
        CurrentUser("user-1", "user@example.com", "User", "Europe/Moscow", "ru"),
        AuthTokens("access", "refresh", "2026-09-01T00:00:00Z")
    )
    private val from = LocalDate.parse("2026-08-03")
    private val toExclusive = LocalDate.parse("2026-09-14")

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.deleteDatabase(DATABASE_NAME)
        store = PlanningLocalStore(context)
        local = FocusLocalDataSource(store)
    }

    @After
    fun tearDown() {
        store.close()
        context.deleteDatabase(DATABASE_NAME)
    }

    @Test
    fun unauthorizedIsPropagatedWithoutReturningOriginalSession() = runBlocking {
        val error = apiError(401, "unauthorized")
        val repository = CalendarRepository(FailingCalendarRemote(error), local)
        var returnedSession: AuthSession? = null

        try {
            returnedSession = repository.load(session, from, toExclusive).first
            fail("Expected terminal 401")
        } catch (thrown: ApiException) {
            assertSame(error, thrown)
        }

        assertNull(returnedSession)
        assertNull(local.loadCalendar(session.user.id, from, toExclusive))
    }

    @Test
    fun transientOfflineFailureReturnsCachedMonthAndOriginalSession() = runBlocking {
        val cached = cachedMonth()
        local.saveCalendar(session.user.id, cached)
        val repository = CalendarRepository(FailingCalendarRemote(IOException("offline")), local)

        val result = repository.load(session, from, toExclusive)

        assertSame(session, result.first)
        assertTrue(result.second.offline)
        assertEquals(cached.markers, result.second.markers)
        assertNull(result.second.error)
    }

    private fun cachedMonth() = CalendarMonth(
        timezone = session.user.timezone,
        from = from,
        toExclusive = toExclusive,
        markers = listOf(
            CalendarMarker(
                markerId = "marker-1",
                occurrenceId = "occurrence-1",
                taskId = "task-1",
                goalId = "goal-1",
                kind = CalendarMarkerKind.Planned,
                at = "2026-08-05T09:00:00+03:00",
                localDate = LocalDate.parse("2026-08-05"),
                title = "Cached task",
                status = "todo",
                effort = 2,
                recurring = false
            )
        )
    )

    private class FailingCalendarRemote(
        private val error: Exception
    ) : CalendarRemoteDataSource {
        override suspend fun get(session: AuthSession, path: String): SessionBoundResult<JSONObject> = throw error
    }

    companion object {
        private const val DATABASE_NAME = "rocketflow_planning.db"

        private fun apiError(status: Int, code: String) =
            ApiException(status, code, code, emptyMap(), null)
    }
}
