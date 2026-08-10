package com.rocketflow.notifications;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Optional;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;

@Configuration
public class FirebaseMessagingConfiguration {

    @Bean
    @ConditionalOnProperty(prefix = "rocketflow.notifications.fcm", name = "enabled", havingValue = "true")
    FirebaseMessaging firebaseMessaging(NotificationProperties properties) throws IOException {
        properties.getFcm().validateTransportTimeouts();
        String credentialsJson = properties.getFcm().getCredentialsJson();
        GoogleCredentials credentials;
        if (credentialsJson != null && !credentialsJson.trim().isEmpty()) {
            try (InputStream inputStream = new ByteArrayInputStream(credentialsJson.getBytes(StandardCharsets.UTF_8))) {
                credentials = loadCredentials(inputStream)
                        .createScoped("https://www.googleapis.com/auth/firebase.messaging");
            }
        } else {
            String credentialsPath = properties.getFcm().getCredentialsPath();
            if (credentialsPath == null || credentialsPath.trim().isEmpty()) {
                throw new IllegalStateException(
                        "FCM is enabled, but neither ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_JSON nor ROCKETFLOW_NOTIFICATIONS_FCM_CREDENTIALS_PATH is set."
                );
            }
            try (InputStream inputStream = Files.newInputStream(Path.of(credentialsPath.trim()))) {
                credentials = loadCredentials(inputStream)
                        .createScoped("https://www.googleapis.com/auth/firebase.messaging");
            }
        }

        FirebaseOptions.Builder options = firebaseOptions(credentials, properties);
        String projectId = properties.getFcm().getProjectId();
        if (projectId != null && !projectId.trim().isEmpty()) {
            options.setProjectId(projectId.trim());
        }

        FirebaseApp app = findExistingApp("rocketflow-fcm")
                .orElseGet(() -> FirebaseApp.initializeApp(options.build(), "rocketflow-fcm"));
        return FirebaseMessaging.getInstance(app);
    }

    private GoogleCredentials loadCredentials(InputStream inputStream) throws IOException {
        // google-auth-library 1.29 builds token-refresh requests without a request initializer.
        // FirebaseOptions timeouts therefore bound Firebase calls, not every credential refresh path;
        // the Focus delivery heartbeat is the lease-correctness guard for either transport.
        return GoogleCredentials.fromStream(inputStream);
    }

    FirebaseOptions.Builder firebaseOptions(GoogleCredentials credentials, NotificationProperties properties) {
        NotificationProperties.Fcm fcm = properties.getFcm();
        fcm.validateTransportTimeouts();
        return FirebaseOptions.builder()
                .setCredentials(credentials)
                .setConnectTimeout(fcm.getConnectTimeoutMs())
                .setReadTimeout(fcm.getReadTimeoutMs())
                .setWriteTimeout(fcm.getWriteTimeoutMs());
    }

    private Optional<FirebaseApp> findExistingApp(String name) {
        return FirebaseApp.getApps().stream()
                .filter(app -> name.equals(app.getName()))
                .findFirst();
    }
}
