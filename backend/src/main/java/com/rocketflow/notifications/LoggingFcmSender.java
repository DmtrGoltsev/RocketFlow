package com.rocketflow.notifications;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class LoggingFcmSender implements FcmSender {

    private static final Logger log = LoggerFactory.getLogger(LoggingFcmSender.class);

    private final NotificationProperties properties;
    private final boolean enabled;

    public LoggingFcmSender(NotificationProperties properties) {
        this.properties = properties;
        this.enabled = properties.getFcm().isEnabled();
    }

    @Override
    public SendResult send(DeviceRegistration deviceRegistration, NotificationPayload payload) {
        if (!enabled) {
            return SendResult.failed("FCM delivery is disabled.");
        }

        log.info(
                "Fallback stub FCM delivery deviceId={} platform={} type={} taskId={} projectId={}",
                deviceRegistration.getId(),
                deviceRegistration.getPlatform(),
                payload.data().get("type"),
                payload.data().get("taskId"),
                properties.getFcm().getProjectId()
        );
        return SendResult.failed("FCM is enabled, but no real Firebase sender is configured.");
    }
}
