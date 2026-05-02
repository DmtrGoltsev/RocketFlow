package com.rocketflow.notifications;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

import com.google.firebase.messaging.FirebaseMessaging;

class FcmSenderConfigurationTest {

    private final ApplicationContextRunner contextRunner = new ApplicationContextRunner()
            .withUserConfiguration(FcmSenderConfiguration.class)
            .withBean(NotificationProperties.class);

    @Test
    void registersFirebaseAdminSenderWhenFirebaseMessagingBeanExists() {
        contextRunner
                .withBean(FirebaseMessaging.class, () -> org.mockito.Mockito.mock(FirebaseMessaging.class))
                .run(context -> {
                    assertThat(context).hasSingleBean(FcmSender.class);
                    assertThat(context.getBean(FcmSender.class)).isInstanceOf(FirebaseAdminFcmSender.class);
                });
    }

    @Test
    void fallsBackToLoggingSenderWhenFirebaseMessagingBeanIsMissing() {
        contextRunner.run(context -> {
            assertThat(context).hasSingleBean(FcmSender.class);
            assertThat(context.getBean(FcmSender.class)).isInstanceOf(LoggingFcmSender.class);
        });
    }
}
