package com.rocketflow.companion.auth

import com.rocketflow.companion.network.ApiException
import com.rocketflow.companion.network.HttpJsonClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.ServerSocket
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

class AuthRepositoryRefreshRaceUnitTest {

    private var server: TestHttpServer? = null

    @After
    fun tearDown() {
        server?.close()
    }

    @Test
    fun concurrentRefreshAcrossRepositoryInstancesIsSingleFlight() = runBlocking {
        val initial = session("expired-access", "refresh-old")
        val storage = InMemorySessionStorage(initial)
        val refreshCalls = AtomicInteger(0)
        val clearedCallbacks = AtomicInteger(0)
        server = TestHttpServer { request ->
            when {
                request.method == "GET" && request.path == "/api/protected" ->
                    protectedResponse(request.accessToken)
                request.method == "GET" && request.path == "/api/me" ->
                    currentUserResponse(request.accessToken)
                request.method == "POST" && request.path == "/api/auth/refresh" -> {
                    refreshCalls.incrementAndGet()
                    Thread.sleep(150)
                    TestResponse.ok(tokensBody("access-new", "refresh-new"))
                }
                else -> TestResponse.notFound()
            }
        }.also { it.start() }

        val firstRepository = repository(storage)
        val secondRepository = repository(storage)
        firstRepository.setOnSessionClearedListener { clearedCallbacks.incrementAndGet() }
        secondRepository.setOnSessionClearedListener { clearedCallbacks.incrementAndGet() }

        val first = async { firstRepository.authorizedGet(initial, "/protected") }
        val second = async { secondRepository.authorizedGet(initial, "/protected") }

        assertEquals("refresh-new", first.await().session.tokens.refreshToken)
        assertEquals("refresh-new", second.await().session.tokens.refreshToken)
        assertEquals("refresh-new", storage.readSession()?.tokens?.refreshToken)
        assertEquals(1, refreshCalls.get())
        assertEquals(0, clearedCallbacks.get())
    }

    @Test
    fun staleRefresh401UsesNewerStoredSessionInsteadOfClearing() = runBlocking {
        val initial = session("expired-access", "refresh-old")
        val newer = session("access-new", "refresh-new")
        val storage = InMemorySessionStorage(initial)
        val refreshStarted = CountDownLatch(1)
        val releaseRefresh = CountDownLatch(1)
        val clearedCallbacks = AtomicInteger(0)
        server = TestHttpServer { request ->
            when {
                request.method == "GET" && request.path == "/api/protected" ->
                    protectedResponse(request.accessToken)
                request.method == "POST" && request.path == "/api/auth/refresh" -> {
                    refreshStarted.countDown()
                    assertTrue(releaseRefresh.await(2, TimeUnit.SECONDS))
                    TestResponse.unauthorized()
                }
                else -> TestResponse.notFound()
            }
        }.also { it.start() }

        val authRepository = repository(storage)
        authRepository.setOnSessionClearedListener { clearedCallbacks.incrementAndGet() }
        val result = async(Dispatchers.Default) { authRepository.authorizedGet(initial, "/protected") }

        assertTrue(refreshStarted.await(2, TimeUnit.SECONDS))
        storage.writeSession(newer)
        releaseRefresh.countDown()

        assertEquals("refresh-new", result.await().session.tokens.refreshToken)
        assertEquals("refresh-new", storage.readSession()?.tokens?.refreshToken)
        assertEquals(0, clearedCallbacks.get())
    }

    @Test
    fun clearedStoreDuringDelayedSuccessfulRefreshDoesNotResurrectSession() = runBlocking {
        val initial = session("expired-access", "refresh-old")
        val storage = InMemorySessionStorage(initial)
        val refreshStarted = CountDownLatch(1)
        val releaseRefresh = CountDownLatch(1)
        server = TestHttpServer { request ->
            when {
                request.method == "GET" && request.path == "/api/protected" ->
                    protectedResponse(request.accessToken)
                request.method == "POST" && request.path == "/api/auth/refresh" -> {
                    refreshStarted.countDown()
                    assertTrue(releaseRefresh.await(2, TimeUnit.SECONDS))
                    TestResponse.ok(tokensBody("access-rotated-old", "refresh-rotated-old"))
                }
                else -> TestResponse.notFound()
            }
        }.also { it.start() }

        val authRepository = repository(storage)
        val result = async(Dispatchers.Default) {
            try {
                authRepository.authorizedGet(initial, "/protected")
                fail("Expected cleared store to terminate stale refresh")
            } catch (error: ApiException) {
                assertEquals(401, error.status)
            }
        }

        assertTrue(refreshStarted.await(2, TimeUnit.SECONDS))
        storage.clear()
        releaseRefresh.countDown()

        result.await()
        assertEquals(null, storage.readSession())
    }

    @Test
    fun newerStoredSessionDuringDelayedSuccessfulRefreshIsNotOverwritten() = runBlocking {
        val initial = session("expired-access", "refresh-old")
        val newer = session("access-newer", "refresh-newer")
        val storage = InMemorySessionStorage(initial)
        val refreshStarted = CountDownLatch(1)
        val releaseRefresh = CountDownLatch(1)
        server = TestHttpServer { request ->
            when {
                request.method == "GET" && request.path == "/api/protected" ->
                    if (request.accessToken == "access-newer") {
                        TestResponse.ok("""{"ok":true}""")
                    } else {
                        TestResponse.unauthorized()
                    }
                request.method == "GET" && request.path == "/api/me" ->
                    if (request.accessToken == "access-rotated-old") {
                        TestResponse.ok(currentUserBody())
                    } else {
                        TestResponse.unauthorized()
                    }
                request.method == "POST" && request.path == "/api/auth/refresh" -> {
                    refreshStarted.countDown()
                    assertTrue(releaseRefresh.await(2, TimeUnit.SECONDS))
                    TestResponse.ok(tokensBody("access-rotated-old", "refresh-rotated-old"))
                }
                else -> TestResponse.notFound()
            }
        }.also { it.start() }

        val authRepository = repository(storage)
        val result = async(Dispatchers.Default) { authRepository.authorizedGet(initial, "/protected") }

        assertTrue(refreshStarted.await(2, TimeUnit.SECONDS))
        storage.writeSession(newer)
        releaseRefresh.countDown()

        assertEquals("refresh-newer", result.await().session.tokens.refreshToken)
        assertEquals("refresh-newer", storage.readSession()?.tokens?.refreshToken)
    }

    @Test
    fun loginAfterFinalRefreshGuardIsNotOverwrittenByStaleRefresh() = runBlocking {
        val initial = session("expired-access", "refresh-old")
        val storage = InMemorySessionStorage(initial)
        val finalGuardRead = CountDownLatch(1)
        val loginEndpointServed = CountDownLatch(1)
        val loginWriteStarted = CountDownLatch(1)
        val hookArmed = AtomicBoolean(true)
        storage.onReadSession = { stored ->
            if (stored?.tokens?.refreshToken == "refresh-rotated-old" &&
                hookArmed.compareAndSet(true, false)
            ) {
                finalGuardRead.countDown()
                assertTrue(loginEndpointServed.await(2, TimeUnit.SECONDS))
                loginWriteStarted.await(250, TimeUnit.MILLISECONDS)
            }
        }
        storage.onWriteSession = { stored ->
            if (stored.tokens.refreshToken == "refresh-login") {
                loginWriteStarted.countDown()
            }
        }
        server = TestHttpServer { request ->
            when {
                request.method == "GET" && request.path == "/api/protected" ->
                    if (request.accessToken == "access-rotated-old" || request.accessToken == "access-login") {
                        TestResponse.ok("""{"ok":true}""")
                    } else {
                        TestResponse.unauthorized()
                    }
                request.method == "GET" && request.path == "/api/me" ->
                    if (request.accessToken == "access-rotated-old") {
                        TestResponse.ok(currentUserBody())
                    } else {
                        TestResponse.unauthorized()
                    }
                request.method == "POST" && request.path == "/api/auth/refresh" ->
                    TestResponse.ok(tokensBody("access-rotated-old", "refresh-rotated-old"))
                request.method == "POST" && request.path == "/api/auth/login" -> {
                    loginEndpointServed.countDown()
                    TestResponse.ok(authSessionBody("access-login", "refresh-login"))
                }
                else -> TestResponse.notFound()
            }
        }.also { it.start() }

        val refreshRepository = repository(storage)
        val loginRepository = repository(storage)
        val refresh = async(Dispatchers.Default) { refreshRepository.authorizedGet(initial, "/protected") }
        val login = async(Dispatchers.Default) {
            assertTrue(finalGuardRead.await(2, TimeUnit.SECONDS))
            loginRepository.login("user@example.test", "password")
        }

        refresh.await()
        login.await()

        assertEquals("refresh-login", storage.readSession()?.tokens?.refreshToken)
    }

    @Test
    fun invalidRefreshStillClearsCurrentStoredSession() = runBlocking {
        val initial = session("expired-access", "refresh-old")
        val storage = InMemorySessionStorage(initial)
        val clearedCallbacks = AtomicInteger(0)
        server = TestHttpServer { request ->
            when {
                request.method == "GET" && request.path == "/api/protected" ->
                    protectedResponse(request.accessToken)
                request.method == "POST" && request.path == "/api/auth/refresh" ->
                    TestResponse.unauthorized()
                else -> TestResponse.notFound()
            }
        }.also { it.start() }

        val authRepository = repository(storage)
        authRepository.setOnSessionClearedListener { clearedCallbacks.incrementAndGet() }

        try {
            authRepository.authorizedGet(initial, "/protected")
            fail("Expected invalid refresh to throw 401")
        } catch (error: ApiException) {
            assertEquals(401, error.status)
        }

        assertEquals(null, storage.readSession())
        assertEquals(1, clearedCallbacks.get())
    }

    private fun repository(sessionStorage: AuthSessionStorage): AuthRepository {
        val baseUrl = requireNotNull(server).baseUrl
        return AuthRepository(HttpJsonClient(baseUrl), sessionStorage)
    }

    private fun protectedResponse(accessToken: String?): TestResponse {
        return if (accessToken == "access-new") {
            TestResponse.ok("""{"ok":true}""")
        } else {
            TestResponse.unauthorized()
        }
    }

    private fun currentUserResponse(accessToken: String?): TestResponse {
        return if (accessToken == "access-new") {
            TestResponse.ok(currentUserBody())
        } else {
            TestResponse.unauthorized()
        }
    }

    private fun session(accessToken: String, refreshToken: String): AuthSession {
        return AuthSession(
            user = CurrentUser(
                id = "user-id",
                email = "user@example.test",
                displayName = "User",
                timezone = "Europe/Moscow",
                language = "ru"
            ),
            tokens = AuthTokens(
                accessToken = accessToken,
                refreshToken = refreshToken,
                expiresAt = "2026-05-09T00:00:00Z"
            )
        )
    }

    private fun tokensBody(accessToken: String, refreshToken: String): String {
        return """
            {
                "tokens": {
                    "accessToken": "$accessToken",
                    "refreshToken": "$refreshToken",
                    "expiresAt": "2026-05-09T01:00:00Z"
                }
            }
        """.trimIndent()
    }

    private fun authSessionBody(accessToken: String, refreshToken: String): String {
        return """
            {
                "user": ${currentUserBody()},
                "tokens": {
                    "accessToken": "$accessToken",
                    "refreshToken": "$refreshToken",
                    "expiresAt": "2026-05-09T01:00:00Z"
                }
            }
        """.trimIndent()
    }

    private fun currentUserBody(): String {
        return """
            {
                "id":"user-id",
                "email":"user@example.test",
                "displayName":"User",
                "timezone":"Europe/Moscow",
                "language":"ru"
            }
        """.trimIndent()
    }

    private class InMemorySessionStorage(
        initialSession: AuthSession?
    ) : AuthSessionStorage {
        private val lock = Any()
        private var session: AuthSession? = initialSession
        var onReadSession: ((AuthSession?) -> Unit)? = null
        var onWriteSession: ((AuthSession) -> Unit)? = null

        override fun readSession(): AuthSession? {
            val current = synchronized(lock) { session }
            onReadSession?.invoke(current)
            return current
        }

        override fun writeSession(session: AuthSession) {
            onWriteSession?.invoke(session)
            synchronized(lock) {
                this.session = session
            }
        }

        override fun clear() {
            synchronized(lock) {
                session = null
            }
        }
    }

    private data class TestRequest(
        val method: String,
        val path: String,
        val accessToken: String?
    )

    private data class TestResponse(
        val status: Int,
        val body: String
    ) {
        companion object {
            fun ok(body: String): TestResponse = TestResponse(200, body)

            fun unauthorized(): TestResponse = TestResponse(
                401,
                """{"error":{"code":"unauthorized","message":"Unauthorized."}}"""
            )

            fun notFound(): TestResponse = TestResponse(
                404,
                """{"error":{"code":"not_found","message":"Not found."}}"""
            )
        }
    }

    private class TestHttpServer(
        private val handler: (TestRequest) -> TestResponse
    ) : AutoCloseable {
        private val serverSocket = ServerSocket(0)
        private var running = true
        val baseUrl: String = "http://127.0.0.1:${serverSocket.localPort}/api"

        fun start() {
            thread(start = true, isDaemon = true) {
                while (running) {
                    try {
                        val socket = serverSocket.accept()
                        thread(start = true, isDaemon = true) {
                            socket.use { handle(it) }
                        }
                    } catch (_: Exception) {
                        if (running) {
                            throw AssertionError("Test HTTP server stopped unexpectedly")
                        }
                    }
                }
            }
        }

        override fun close() {
            running = false
            serverSocket.close()
        }

        private fun handle(socket: Socket) {
            socket.soTimeout = 5_000
            val reader = BufferedReader(InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8))
            val requestLine = reader.readLine() ?: return
            val parts = requestLine.split(" ")
            val method = parts.getOrNull(0).orEmpty()
            val path = parts.getOrNull(1).orEmpty()
            var authorization: String? = null
            while (true) {
                val line = reader.readLine() ?: return
                if (line.isEmpty()) {
                    break
                }
                val separator = line.indexOf(":")
                if (separator > 0 && line.substring(0, separator).equals("Authorization", ignoreCase = true)) {
                    authorization = line.substring(separator + 1).trim()
                }
            }

            val accessToken = authorization?.removePrefix("Bearer ")
            val response = handler(TestRequest(method, path, accessToken))
            writeResponse(socket, response)
        }

        private fun writeResponse(socket: Socket, response: TestResponse) {
            val bodyBytes = response.body.toByteArray(StandardCharsets.UTF_8)
            val reason = if (response.status in 200..299) "OK" else "Error"
            val headers = "HTTP/1.1 ${response.status} $reason\r\n" +
                "Content-Type: application/json; charset=utf-8\r\n" +
                "Content-Length: ${bodyBytes.size}\r\n" +
                "Connection: close\r\n\r\n"
            socket.getOutputStream().use { output ->
                output.write(headers.toByteArray(StandardCharsets.UTF_8))
                output.write(bodyBytes)
                output.flush()
            }
        }
    }
}
