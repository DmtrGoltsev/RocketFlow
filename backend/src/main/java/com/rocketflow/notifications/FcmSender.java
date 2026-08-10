package com.rocketflow.notifications;

import java.time.Duration;
import java.util.Map;

public interface FcmSender {

    SendResult send(DeviceRegistration deviceRegistration, NotificationPayload payload);

    default SendResult sendDataOnly(
            DeviceRegistration deviceRegistration,
            Map<String, String> data,
            String collapseKey,
            Duration ttl
    ) {
        return send(deviceRegistration, new NotificationPayload(null, null, data));
    }

    enum Outcome {
        SENT,
        RETRY,
        DEACTIVATE,
        CONFIG_FAILURE,
        PERMANENT_FAILURE
    }

    record SendResult(Outcome outcome, String providerResponse) {

        public boolean successful() {
            return outcome == Outcome.SENT;
        }

        public static SendResult sent(String providerResponse) {
            return new SendResult(Outcome.SENT, providerResponse);
        }

        public static SendResult failed(String providerResponse) {
            return retry(providerResponse);
        }

        public static SendResult retry(String providerResponse) {
            return new SendResult(Outcome.RETRY, providerResponse);
        }

        public static SendResult deactivate(String providerResponse) {
            return new SendResult(Outcome.DEACTIVATE, providerResponse);
        }

        public static SendResult configFailure(String providerResponse) {
            return new SendResult(Outcome.CONFIG_FAILURE, providerResponse);
        }

        public static SendResult permanentFailure(String providerResponse) {
            return new SendResult(Outcome.PERMANENT_FAILURE, providerResponse);
        }
    }
}
