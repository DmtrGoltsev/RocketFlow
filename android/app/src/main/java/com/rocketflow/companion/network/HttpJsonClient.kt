package com.rocketflow.companion.network

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets

class HttpJsonClient(private val baseUrl: String) {

    suspend fun get(path: String, accessToken: String? = null): JSONObject {
        return requestJson("GET", path, null, accessToken)
    }

    suspend fun post(path: String, body: JSONObject, accessToken: String? = null): JSONObject {
        return requestJson("POST", path, body, accessToken)
    }

    suspend fun delete(path: String, accessToken: String? = null): JSONObject {
        return requestJson("DELETE", path, null, accessToken)
    }

    private suspend fun requestJson(
        method: String,
        path: String,
        body: JSONObject?,
        accessToken: String?
    ): JSONObject = withContext(Dispatchers.IO) {
        val connection = (URL(baseUrl.trimEnd('/') + path).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 10_000
            readTimeout = 10_000
            doInput = true
            setRequestProperty("Accept", "application/json")

            if (accessToken != null) {
                setRequestProperty("Authorization", "Bearer $accessToken")
            }

            if (body != null) {
                doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                outputStream.use { output ->
                    output.write(body.toString().toByteArray(StandardCharsets.UTF_8))
                }
            }
        }

        try {
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val responseText = stream?.use { input ->
                BufferedReader(InputStreamReader(input, StandardCharsets.UTF_8)).readText()
            } ?: ""

            if (status !in 200..299) {
                throw parseApiException(status, responseText)
            }

            if (responseText.isBlank()) {
                return@withContext JSONObject()
            }

            return@withContext JSONObject(responseText)
        } finally {
            connection.disconnect()
        }
    }

    private fun parseApiException(status: Int, responseText: String): ApiException {
        return try {
            val payload = JSONObject(responseText).optJSONObject("error")
            ApiException(
                status = status,
                code = payload?.optString("code").orEmpty().ifBlank { "internal_error" },
                message = payload?.optString("message").orEmpty().ifBlank { "Request failed." },
                fieldErrors = payload?.optJSONArray("details").toFieldErrors(),
                traceId = payload?.optString("traceId")
            )
        } catch (_: Exception) {
            ApiException(
                status = status,
                code = "internal_error",
                message = "Request failed.",
                fieldErrors = emptyMap(),
                traceId = null
            )
        }
    }
}

class ApiException(
    val status: Int,
    val code: String,
    override val message: String,
    val fieldErrors: Map<String, String>,
    val traceId: String?
) : Exception(message)

private fun JSONArray?.toFieldErrors(): Map<String, String> {
    if (this == null) {
        return emptyMap()
    }

    val result = linkedMapOf<String, String>()
    for (index in 0 until length()) {
        val item = optJSONObject(index) ?: continue
        val field = item.optString("field")
        val message = item.optString("message")
        if (field.isNotBlank() && message.isNotBlank()) {
            result[field] = message
        }
    }
    return result
}
