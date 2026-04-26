package com.rocketflow.notifications;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class LoggingFcmSender implements FcmSender {

    private static final Logger log = LoggerFactory.getLogger(LoggingFcmSender.class);

    private final boolean enabled;

    public LoggingFcmSender(@Value("${rocketflow.notifications.fcm.enabled:false}") boolean enabled) {
        this.enabled = enabled;
    }

    @Override
    public SendResult send(DeviceRegistration deviceRegistration, NotificationPayload payload) {
        if (!enabled) {
            return SendResult.failed("FCM delivery is disabled.");
        }

        log.info(
                "Stub FCM delivery deviceId={} platform={} type={} taskId={}",
                deviceRegistration.getId(),
                deviceRegistration.getPlatform(),
                payload.data().get("type"),
                payload.data().get("taskId")
        );
        return SendResult.sent("stubbed_fcm_sender");
    }
}
