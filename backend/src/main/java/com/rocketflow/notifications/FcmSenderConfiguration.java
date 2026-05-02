package com.rocketflow.notifications;

import org.springframework.beans.factory.ObjectProvider;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import com.google.firebase.messaging.FirebaseMessaging;

@Configuration
public class FcmSenderConfiguration {

    @Bean
    FcmSender fcmSender(
            NotificationProperties properties,
            ObjectProvider<FirebaseMessaging> firebaseMessagingProvider
    ) {
        FirebaseMessaging firebaseMessaging = firebaseMessagingProvider.getIfAvailable();
        if (firebaseMessaging != null) {
            return new FirebaseAdminFcmSender(firebaseMessaging);
        }
        return new LoggingFcmSender(properties);
    }
}
