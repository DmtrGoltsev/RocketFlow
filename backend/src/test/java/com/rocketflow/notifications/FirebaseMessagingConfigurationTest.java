package com.rocketflow.notifications;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.util.Date;

import org.junit.jupiter.api.Test;

import com.google.auth.oauth2.AccessToken;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseOptions;

class FirebaseMessagingConfigurationTest {

    private final FirebaseMessagingConfiguration configuration = new FirebaseMessagingConfiguration();

    @Test
    void throwsWhenEnabledWithoutCredentialsJsonOrPath() {
        NotificationProperties properties = new NotificationProperties();
        properties.getFcm().setEnabled(true);
        properties.getFcm().setProjectId("rocketflow-staging");

        assertThrows(
                IllegalStateException.class,
                () -> configuration.firebaseMessaging(properties)
        );
    }

    @Test
    void appliesBoundedTransportTimeoutsThroughFirebaseOptions() {
        NotificationProperties properties = new NotificationProperties();
        properties.getFcm().setConnectTimeoutMs(3_000);
        properties.getFcm().setReadTimeoutMs(7_000);
        properties.getFcm().setWriteTimeoutMs(4_000);
        GoogleCredentials credentials = GoogleCredentials.create(
                new AccessToken("test-token", new Date(System.currentTimeMillis() + 60_000))
        );

        FirebaseOptions options = configuration.firebaseOptions(credentials, properties).build();

        assertThat(options.getConnectTimeout()).isEqualTo(3_000);
        assertThat(options.getReadTimeout()).isEqualTo(7_000);
        assertThat(options.getWriteTimeout()).isEqualTo(4_000);
    }

    @Test
    void rejectsInfiniteOrExcessiveTransportTimeouts() {
        NotificationProperties properties = new NotificationProperties();
        properties.getFcm().setReadTimeoutMs(0);

        assertThrows(IllegalStateException.class, properties.getFcm()::validateTransportTimeouts);

        properties.getFcm().setReadTimeoutMs(60_001);
        assertThrows(IllegalStateException.class, properties.getFcm()::validateTransportTimeouts);
    }
}
