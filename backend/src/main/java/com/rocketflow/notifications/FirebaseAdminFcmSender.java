package com.rocketflow.notifications;

import java.time.Duration;
import java.util.Map;

import com.google.firebase.ErrorCode;
import com.google.firebase.messaging.AndroidConfig;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.MessagingErrorCode;
import com.google.firebase.messaging.Notification;

public class FirebaseAdminFcmSender implements FcmSender {
    private static final Duration DEFAULT_DATA_TTL = Duration.ofMinutes(15);
    private static final Duration MIN_DATA_TTL = Duration.ofSeconds(1);
    private static final Duration MAX_DATA_TTL = Duration.ofHours(24);

    private final FirebaseMessaging firebaseMessaging;

    public FirebaseAdminFcmSender(FirebaseMessaging firebaseMessaging) {
        this.firebaseMessaging = firebaseMessaging;
    }

    @Override
    public SendResult send(DeviceRegistration deviceRegistration, NotificationPayload payload) {
        Message.Builder messageBuilder = Message.builder()
                .setToken(deviceRegistration.getPushToken())
                .putAllData(payload.data());

        if (payload.title() != null || payload.body() != null) {
            messageBuilder.setNotification(Notification.builder()
                    .setTitle(payload.title())
                    .setBody(payload.body())
                    .build());
        }

        return deliverLegacy(messageBuilder.build());
    }

    @Override
    public SendResult sendDataOnly(
            DeviceRegistration deviceRegistration,
            Map<String, String> data,
            String collapseKey,
            Duration ttl
    ) {
        AndroidConfig.Builder androidConfig = AndroidConfig.builder()
                .setPriority(AndroidConfig.Priority.HIGH)
                .setTtl(boundedTtl(ttl).toMillis());
        if (collapseKey != null && !collapseKey.isBlank()) {
            androidConfig.setCollapseKey(collapseKey);
        }

        Message message = Message.builder()
                .setToken(deviceRegistration.getPushToken())
                .putAllData(data)
                .setAndroidConfig(androidConfig.build())
                .build();
        return deliverFocus(message);
    }

    private Duration boundedTtl(Duration ttl) {
        Duration value = ttl == null ? DEFAULT_DATA_TTL : ttl;
        if (value.compareTo(MIN_DATA_TTL) < 0) {
            return MIN_DATA_TTL;
        }
        if (value.compareTo(MAX_DATA_TTL) > 0) {
            return MAX_DATA_TTL;
        }
        return value;
    }

    private SendResult deliverLegacy(Message message) {
        try {
            String messageId = firebaseMessaging.send(message);
            return SendResult.sent(messageId);
        } catch (FirebaseMessagingException exception) {
            return SendResult.failed(response(exception));
        }
    }

    private SendResult deliverFocus(Message message) {
        try {
            String messageId = firebaseMessaging.send(message);
            return SendResult.sent(messageId);
        } catch (FirebaseMessagingException exception) {
            String response = response(exception);
            MessagingErrorCode errorCode = exception.getMessagingErrorCode();
            if (errorCode == null) {
                return classifyBaseError(exception.getErrorCode(), response);
            }
            return switch (errorCode) {
                case UNREGISTERED, SENDER_ID_MISMATCH, INVALID_ARGUMENT -> SendResult.deactivate(response);
                case QUOTA_EXCEEDED, UNAVAILABLE, INTERNAL -> SendResult.retry(response);
                case THIRD_PARTY_AUTH_ERROR -> SendResult.configFailure(response);
            };
        }
    }

    private SendResult classifyBaseError(ErrorCode errorCode, String response) {
        if (errorCode == null) {
            return SendResult.retry(response);
        }
        return switch (errorCode) {
            case ABORTED, CANCELLED, DEADLINE_EXCEEDED, INTERNAL, RESOURCE_EXHAUSTED,
                    UNAVAILABLE, UNKNOWN -> SendResult.retry(response);
            case UNAUTHENTICATED, PERMISSION_DENIED -> SendResult.configFailure(response);
            case INVALID_ARGUMENT, FAILED_PRECONDITION, OUT_OF_RANGE, NOT_FOUND, CONFLICT,
                    ALREADY_EXISTS, DATA_LOSS -> SendResult.permanentFailure(response);
        };
    }

    private String response(FirebaseMessagingException exception) {
        String messagingCode = exception.getMessagingErrorCode() == null
                ? "unknown"
                : exception.getMessagingErrorCode().name();
        String baseCode = exception.getErrorCode() == null ? "unknown" : exception.getErrorCode().name();
        return "messaging=" + messagingCode + ";firebase=" + baseCode + ":" + exception.getMessage();
    }
}
