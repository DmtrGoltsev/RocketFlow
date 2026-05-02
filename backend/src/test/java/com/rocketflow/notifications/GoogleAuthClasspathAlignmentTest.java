package com.rocketflow.notifications;

import static org.assertj.core.api.Assertions.assertThatCode;

import org.junit.jupiter.api.Test;

import com.google.auth.oauth2.GoogleCredentials;

class GoogleAuthClasspathAlignmentTest {

    @Test
    void loadsCredentialMetricsTypeFromGoogleCredentialsClasspath() {
        ClassLoader classLoader = GoogleCredentials.class.getClassLoader();

        assertThatCode(() -> classLoader.loadClass("com.google.auth.CredentialTypeForMetrics"))
                .doesNotThrowAnyException();
    }
}
