package com.rocketflow.notifications;

import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.Test;

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
}
