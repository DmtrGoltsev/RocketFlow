package com.rocketflow.notifications;

public interface FcmSender {

    SendResult send(DeviceRegistration deviceRegistration, NotificationPayload payload);

    record SendResult(boolean successful, String providerResponse) {

        public static SendResult sent(String providerResponse) {
            return new SendResult(true, providerResponse);
        }

        public static SendResult failed(String providerResponse) {
            return new SendResult(false, providerResponse);
        }
    }
}
