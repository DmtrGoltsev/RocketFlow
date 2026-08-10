package com.rocketflow.focusnotifications;

import java.net.http.HttpClient;
import java.time.Clock;
import java.time.Duration;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.interaso.webpush.VapidKeys;
import com.interaso.webpush.WebPush;
import com.rocketflow.notifications.NotificationProperties;

@Configuration
@EnableConfigurationProperties(FocusNotificationProperties.class)
public class FocusNotificationConfiguration {
    @Bean
    Clock focusNotificationClock() {
        return Clock.systemUTC();
    }

    @Bean
    WebPushSender webPushSender(
            FocusNotificationProperties properties,
            NotificationProperties notificationProperties,
            WebPushEndpointValidator endpointValidator,
            ObjectMapper objectMapper
    ) {
        properties.validate(notificationProperties);
        if (!properties.getWebPush().isEnabled()) {
            return (subscription, payload) -> WebPushSender.Result.configFailure("Web Push delivery is disabled.");
        }
        VapidKeys keys = VapidKeys.fromUncompressedBytes(
                properties.getWebPush().getVapidPublicKey(),
                properties.getWebPush().getVapidPrivateKey()
        );
        WebPush webPush = new WebPush(properties.getWebPush().getVapidSubject(), keys);
        HttpClient client = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(5))
                .followRedirects(HttpClient.Redirect.NEVER)
                .build();
        return new JdkWebPushSender(webPush, client, endpointValidator, objectMapper);
    }
}
