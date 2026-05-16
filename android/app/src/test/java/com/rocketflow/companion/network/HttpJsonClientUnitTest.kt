package com.rocketflow.companion.network

import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test
import java.io.BufferedReader
import java.io.Closeable
import java.io.InputStreamReader
import java.net.ServerSocket
import java.net.Socket
import java.nio.charset.StandardCharsets
import kotlin.concurrent.thread

class HttpJsonClientUnitTest {

    private var server: TestHttpServer? = null

    @After
    fun tearDown() {
        server?.close()
    }

    @Test
    fun parsesApiErrorDetails() = runBlocking {
        val responseBody = """
            {
              "error": {
                "code": "validation_error",
                "message": "The request contains invalid fields.",
                "details": [
                  { "field": "password", "message": "size must be between 8 and 200" }
                ],
                "traceId": null
              }
            }
        """.trimIndent()
        server = TestHttpServer(status = 400, responseBody = responseBody).also { it.start() }

        val client = HttpJsonClient(server!!.baseUrl)

        try {
            client.post("/auth/register", JSONObject().put("password", "short"))
            fail("Expected ApiException")
        } catch (error: ApiException) {
            assertEquals(400, error.status)
            assertEquals("validation_error", error.code)
            assertEquals("The request contains invalid fields.", error.message)
            assertEquals("size must be between 8 and 200", error.fieldErrors["password"])
        }
    }

    private class TestHttpServer(
        private val status: Int,
        private val responseBody: String
    ) : Closeable {
        private val serverSocket = ServerSocket(0)
        private var worker: Thread? = null

        val baseUrl: String = "http://127.0.0.1:${serverSocket.localPort}/api"

        fun start() {
            worker = thread(start = true) {
                while (!serverSocket.isClosed) {
                    try {
                        handle(serverSocket.accept())
                    } catch (_: Exception) {
                        break
                    }
                }
            }
        }

        private fun handle(socket: Socket) {
            socket.use { client ->
                val input = BufferedReader(InputStreamReader(client.getInputStream(), StandardCharsets.UTF_8))
                var contentLength = 0
                var line = input.readLine()
                while (line != null && line.isNotBlank()) {
                    val separator = line.indexOf(':')
                    if (separator > 0 && line.substring(0, separator).equals("Content-Length", ignoreCase = true)) {
                        contentLength = line.substring(separator + 1).trim().toIntOrNull() ?: 0
                    }
                    line = input.readLine()
                }
                if (contentLength > 0) {
                    repeat(contentLength) { input.read() }
                }

                val bytes = responseBody.toByteArray(StandardCharsets.UTF_8)
                val headers = buildString {
                    append("HTTP/1.1 $status Error\r\n")
                    append("Content-Type: application/json\r\n")
                    append("Content-Length: ${bytes.size}\r\n")
                    append("Connection: close\r\n")
                    append("\r\n")
                }.toByteArray(StandardCharsets.UTF_8)
                val output = client.getOutputStream()
                output.write(headers)
                output.write(bytes)
                output.flush()
            }
        }

        override fun close() {
            serverSocket.close()
            worker?.join(1_000)
        }
    }
}
