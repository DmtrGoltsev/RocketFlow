package com.rocketflow.focusnotifications;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.Base64;
import java.util.Locale;
import java.util.Map;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.interaso.webpush.WebPush;
import com.rocketflow.common.ApiException;

class JdkWebPushSender implements WebPushSender {
    private static final int MAX_PAYLOAD_BYTES = 3_000;
    private static final int TTL_SECONDS = 24 * 60 * 60;

    private final WebPush webPush;
    private final HttpClient httpClient;
    private final WebPushEndpointValidator endpointValidator;
    private final ObjectMapper objectMapper;

    JdkWebPushSender(
            WebPush webPush,
            HttpClient httpClient,
            WebPushEndpointValidator endpointValidator,
            ObjectMapper objectMapper
    ) {
        this.webPush = webPush;
        this.httpClient = httpClient;
        this.endpointValidator = endpointValidator;
        this.objectMapper = objectMapper;
    }

    @Override
    public Result send(WebPushSubscription subscription, FocusPushPayload payload) {
        URI endpoint;
        try {
            endpoint = endpointValidator.requirePublicHttps(subscription.getEndpoint());
        } catch (ApiException exception) {
            return Result.permanentFailure("The subscription endpoint is no longer valid.");
        }

        byte[] plaintext;
        try {
            plaintext = objectMapper.writeValueAsBytes(payload);
        } catch (JsonProcessingException exception) {
            return Result.permanentFailure("The Web Push payload could not be encoded.");
        }
        if (plaintext.length > MAX_PAYLOAD_BYTES) {
            return Result.permanentFailure("The Web Push payload exceeds 3000 UTF-8 bytes.");
        }

        byte[] body;
        Map<String, String> headers;
        try {
            body = webPush.getBody(
                    plaintext,
                    Base64.getUrlDecoder().decode(subscription.getP256dh()),
                    Base64.getUrlDecoder().decode(subscription.getAuth())
            );
            String topic = "focus-" + payload.periodId().toString().replace("-", "").substring(0, 20);
            headers = webPush.getHeaders(endpoint.toString(), TTL_SECONDS, topic, WebPush.Urgency.Normal);
        } catch (RuntimeException exception) {
            return Result.configFailure("The Web Push request could not be encrypted or signed.");
        }

        HttpRequest.Builder request = HttpRequest.newBuilder(endpoint)
                .timeout(FocusNotificationProperties.WEB_PUSH_REQUEST_TIMEOUT)
                .POST(HttpRequest.BodyPublishers.ofByteArray(body));
        headers.forEach(request::header);
        try {
            HttpResponse<byte[]> response = httpClient.send(request.build(), HttpResponse.BodyHandlers.ofByteArray());
            return classify(response);
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            return Result.retry("Web Push delivery was interrupted.", Duration.ofMinutes(1));
        } catch (IOException exception) {
            return Result.retry("Web Push provider was unavailable.", Duration.ofMinutes(1));
        }
    }

    private Result classify(HttpResponse<byte[]> response) {
        int status = response.statusCode();
        String detail = "HTTP " + status;
        if (status >= 200 && status < 300) {
            return Result.sent(detail);
        }
        if (status == 404 || status == 410) {
            return Result.deactivate(detail);
        }
        if (status == 429) {
            return Result.retry(detail, retryAfter(response));
        }
        if (status == 500 || status == 502 || status == 503 || status == 504) {
            return Result.retry(detail, retryAfter(response));
        }
        if (status == 400 || status == 401 || status == 403) {
            return Result.configFailure(detail);
        }
        if (status == 413) {
            return Result.permanentFailure(detail);
        }
        return Result.permanentFailure(detail);
    }

    private Duration retryAfter(HttpResponse<?> response) {
        String value = response.headers().firstValue("Retry-After").orElse(null);
        if (value == null || value.isBlank()) {
            return Duration.ofMinutes(1);
        }
        try {
            long seconds = Long.parseLong(value.strip());
            return Duration.ofSeconds(Math.max(1, seconds));
        } catch (NumberFormatException ignored) {
            try {
                Instant retryAt = ZonedDateTime.parse(value, DateTimeFormatter.RFC_1123_DATE_TIME.withLocale(Locale.US)).toInstant();
                long seconds = Duration.between(Instant.now(), retryAt).getSeconds();
                return Duration.ofSeconds(Math.max(1, seconds));
            } catch (DateTimeParseException exception) {
                return Duration.ofMinutes(1);
            }
        }
    }
}
