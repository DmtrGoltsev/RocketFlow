package com.rocketflow.focusnotifications;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Base64;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.api.Test;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.interaso.webpush.WebPush;

class JdkWebPushSenderTest {
    @Test
    @SuppressWarnings({"rawtypes", "unchecked"})
    void preservesProviderRetryAfterAsMinimum() throws Exception {
        WebPush webPush = org.mockito.Mockito.mock(WebPush.class);
        HttpClient client = org.mockito.Mockito.mock(HttpClient.class);
        WebPushEndpointValidator validator = org.mockito.Mockito.mock(WebPushEndpointValidator.class);
        HttpResponse<byte[]> response = org.mockito.Mockito.mock(HttpResponse.class);
        when(validator.requirePublicHttps(anyString())).thenReturn(URI.create("https://push.example.test/subscription"));
        when(webPush.getBody(any(), any(), any())).thenReturn(new byte[]{1, 2, 3});
        when(webPush.getHeaders(anyString(), anyInt(), anyString(), any())).thenReturn(Map.of());
        when(response.statusCode()).thenReturn(429);
        when(response.headers()).thenReturn(java.net.http.HttpHeaders.of(
                Map.of("Retry-After", java.util.List.of("7200")),
                (a, b) -> true
        ));
        when(client.send(any(HttpRequest.class), any(HttpResponse.BodyHandler.class))).thenReturn(response);

        WebPushSender.Result result = new JdkWebPushSender(webPush, client, validator, new ObjectMapper())
                .send(subscription(), FocusPushPayload.reminder(UUID.randomUUID(), UUID.randomUUID()));

        assertThat(result.retryAfter()).isEqualTo(Duration.ofHours(2));
    }

    @ParameterizedTest
    @CsvSource({
            "201,SENT",
            "404,DEACTIVATE",
            "410,DEACTIVATE",
            "429,RETRY",
            "503,RETRY",
            "400,CONFIG_FAILURE",
            "401,CONFIG_FAILURE",
            "403,CONFIG_FAILURE",
            "413,PERMANENT_FAILURE"
    })
    @SuppressWarnings({"rawtypes", "unchecked"})
    void classifiesProviderStatusWithoutExposingResponseBody(int status, WebPushSender.Outcome expected) throws Exception {
        WebPush webPush = org.mockito.Mockito.mock(WebPush.class);
        HttpClient client = org.mockito.Mockito.mock(HttpClient.class);
        WebPushEndpointValidator validator = org.mockito.Mockito.mock(WebPushEndpointValidator.class);
        HttpResponse<byte[]> response = org.mockito.Mockito.mock(HttpResponse.class);
        when(validator.requirePublicHttps(anyString())).thenReturn(URI.create("https://push.example.test/subscription"));
        when(webPush.getBody(any(), any(), any())).thenReturn(new byte[]{1, 2, 3});
        when(webPush.getHeaders(anyString(), anyInt(), anyString(), any())).thenReturn(Map.of(
                "Content-Encoding", "aes128gcm",
                "Content-Type", "application/octet-stream"
        ));
        when(response.statusCode()).thenReturn(status);
        when(response.headers()).thenReturn(java.net.http.HttpHeaders.of(Map.of(), (a, b) -> true));
        when(client.send(any(HttpRequest.class), any(HttpResponse.BodyHandler.class))).thenReturn(response);
        JdkWebPushSender sender = new JdkWebPushSender(webPush, client, validator, new ObjectMapper());

        WebPushSender.Result result = sender.send(subscription(), FocusPushPayload.reminder(UUID.randomUUID(), UUID.randomUUID()));

        assertThat(result.outcome()).isEqualTo(expected);
        assertThat(result.providerResponse()).doesNotContain("secret");
    }

    private WebPushSubscription subscription() {
        WebPushSubscription subscription = new WebPushSubscription();
        subscription.setEndpoint("https://push.example.test/secret-endpoint");
        subscription.setP256dh(Base64.getUrlEncoder().withoutPadding().encodeToString(new byte[65]));
        subscription.setAuth(Base64.getUrlEncoder().withoutPadding().encodeToString(new byte[16]));
        return subscription;
    }
}
