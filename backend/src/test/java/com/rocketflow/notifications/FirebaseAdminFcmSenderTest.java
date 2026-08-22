package com.rocketflow.notifications;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.lang.reflect.Field;
import java.time.Duration;
import java.util.Map;
import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import com.google.firebase.ErrorCode;
import com.google.firebase.messaging.AndroidConfig;
import com.google.firebase.messaging.ApnsConfig;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.MessagingErrorCode;

class FirebaseAdminFcmSenderTest {

    @Test
    void sendsFocusPayloadAsHighPriorityDataOnlyMessage() throws Exception {
        FirebaseMessaging firebaseMessaging = org.mockito.Mockito.mock(FirebaseMessaging.class);
        when(firebaseMessaging.send(any(Message.class))).thenReturn("message-id");
        FirebaseAdminFcmSender sender = new FirebaseAdminFcmSender(firebaseMessaging);
        DeviceRegistration device = device("push-token");
        Map<String, String> data = Map.of(
                "type", "focus_reminder",
                "eventId", UUID.randomUUID().toString(),
                "periodId", UUID.randomUUID().toString(),
                "route", "focus",
                "title", "Focus",
                "body", "Open your focus"
        );

        FcmSender.SendResult result = sender.sendDataOnly(
                device, data, "focus-8f3696e7-56fd-47ee-8676-e5f781d8a36f", Duration.ofMinutes(15)
        );

        assertThat(result.successful()).isTrue();
        ArgumentCaptor<Message> messageCaptor = ArgumentCaptor.forClass(Message.class);
        verify(firebaseMessaging).send(messageCaptor.capture());
        Message message = messageCaptor.getValue();
        assertThat((Object) field(message, "notification")).isNull();
        assertThat((Object) field(message, "data")).isEqualTo(data);
        assertThat((Object) field(message, "token")).isEqualTo("push-token");

        AndroidConfig androidConfig = field(message, "androidConfig");
        assertThat((Object) field(androidConfig, "priority")).isEqualTo("high");
        assertThat((Object) field(androidConfig, "collapseKey"))
                .isEqualTo("focus-8f3696e7-56fd-47ee-8676-e5f781d8a36f");
        assertThat((Object) field(androidConfig, "ttl")).isEqualTo("900s");
    }

    @Test
    void boundsDataOnlyTtlToOneDay() throws Exception {
        FirebaseMessaging firebaseMessaging = org.mockito.Mockito.mock(FirebaseMessaging.class);
        when(firebaseMessaging.send(any(Message.class))).thenReturn("message-id");
        FirebaseAdminFcmSender sender = new FirebaseAdminFcmSender(firebaseMessaging);

        sender.sendDataOnly(device("push-token"), Map.of("type", "focus_reminder"), "focus-period",
                Duration.ofDays(7));

        ArgumentCaptor<Message> messageCaptor = ArgumentCaptor.forClass(Message.class);
        verify(firebaseMessaging).send(messageCaptor.capture());
        AndroidConfig androidConfig = field(messageCaptor.getValue(), "androidConfig");
        assertThat((Object) field(androidConfig, "ttl")).isEqualTo("86400s");
    }

    @Test
    void sendsIosFocusPayloadThroughFcmWithBackgroundApnsContract() throws Exception {
        FirebaseMessaging firebaseMessaging = org.mockito.Mockito.mock(FirebaseMessaging.class);
        when(firebaseMessaging.send(any(Message.class))).thenReturn("message-id");
        FirebaseAdminFcmSender sender = new FirebaseAdminFcmSender(firebaseMessaging);
        DeviceRegistration iosDevice = device("ios-token");
        iosDevice.setPlatform("ios");
        Map<String, String> data = Map.of(
                "type", "focus_reminder",
                "periodId", UUID.randomUUID().toString(),
                "eventId", UUID.randomUUID().toString(),
                "route", "focus"
        );

        FcmSender.SendResult result = sender.sendDataOnly(
                iosDevice, data, "focus-period", Duration.ofMinutes(15)
        );

        assertThat(result.successful()).isTrue();
        ArgumentCaptor<Message> messageCaptor = ArgumentCaptor.forClass(Message.class);
        verify(firebaseMessaging).send(messageCaptor.capture());
        Message message = messageCaptor.getValue();
        assertThat((Object) field(message, "token")).isEqualTo("ios-token");
        assertThat((Object) field(message, "data")).isEqualTo(data);
        assertThat((Object) field(message, "androidConfig")).isNull();

        ApnsConfig apnsConfig = field(message, "apnsConfig");
        Map<String, String> headers = field(apnsConfig, "headers");
        assertThat(headers).containsEntry("apns-priority", "5")
                .containsEntry("apns-push-type", "background")
                .containsEntry("apns-collapse-id", "focus-period");
        assertThat(Long.parseLong(headers.get("apns-expiration"))).isPositive();
        Map<String, Object> payload = field(apnsConfig, "payload");
        assertThat(payload.get("aps")).isInstanceOfSatisfying(Map.class,
                aps -> assertThat(aps.get("content-available")).isEqualTo(1));
    }

    @Test
    void keepsLegacyDeepLinkDataPlatformNeutralForIos() throws Exception {
        FirebaseMessaging firebaseMessaging = org.mockito.Mockito.mock(FirebaseMessaging.class);
        when(firebaseMessaging.send(any(Message.class))).thenReturn("message-id");
        FirebaseAdminFcmSender sender = new FirebaseAdminFcmSender(firebaseMessaging);
        DeviceRegistration iosDevice = device("ios-token");
        iosDevice.setPlatform("ios");
        Map<String, String> data = Map.of("type", "task_reminder", "taskId", UUID.randomUUID().toString());

        FcmSender.SendResult result = sender.send(
                iosDevice, new NotificationPayload("Title", "Body", data)
        );

        assertThat(result.successful()).isTrue();
        ArgumentCaptor<Message> messageCaptor = ArgumentCaptor.forClass(Message.class);
        verify(firebaseMessaging).send(messageCaptor.capture());
        assertThat((Object) field(messageCaptor.getValue(), "data")).isEqualTo(data);
        assertThat((Object) field(messageCaptor.getValue(), "token")).isEqualTo("ios-token");
    }

    @Test
    void classifiesDataOnlyMessagingFailures() throws Exception {
        assertDataOnlyOutcome(MessagingErrorCode.UNREGISTERED, FcmSender.Outcome.DEACTIVATE);
        assertDataOnlyOutcome(MessagingErrorCode.SENDER_ID_MISMATCH, FcmSender.Outcome.DEACTIVATE);
        assertDataOnlyOutcome(MessagingErrorCode.QUOTA_EXCEEDED, FcmSender.Outcome.RETRY);
        assertDataOnlyOutcome(MessagingErrorCode.UNAVAILABLE, FcmSender.Outcome.RETRY);
        assertDataOnlyOutcome(MessagingErrorCode.INTERNAL, FcmSender.Outcome.RETRY);
        assertDataOnlyOutcome(MessagingErrorCode.THIRD_PARTY_AUTH_ERROR, FcmSender.Outcome.CONFIG_FAILURE);
        assertDataOnlyOutcome(MessagingErrorCode.INVALID_ARGUMENT, FcmSender.Outcome.DEACTIVATE);
    }

    @Test
    void classifiesBaseFirebaseFailuresWhenMessagingCodeIsMissing() throws Exception {
        assertBaseOutcome(ErrorCode.UNAVAILABLE, FcmSender.Outcome.RETRY);
        assertBaseOutcome(ErrorCode.DEADLINE_EXCEEDED, FcmSender.Outcome.RETRY);
        assertBaseOutcome(ErrorCode.RESOURCE_EXHAUSTED, FcmSender.Outcome.RETRY);
        assertBaseOutcome(ErrorCode.ABORTED, FcmSender.Outcome.RETRY);
        assertBaseOutcome(ErrorCode.INTERNAL, FcmSender.Outcome.RETRY);
        assertBaseOutcome(ErrorCode.UNKNOWN, FcmSender.Outcome.RETRY);
        assertBaseOutcome(ErrorCode.CANCELLED, FcmSender.Outcome.RETRY);
        assertBaseOutcome(ErrorCode.UNAUTHENTICATED, FcmSender.Outcome.CONFIG_FAILURE);
        assertBaseOutcome(ErrorCode.PERMISSION_DENIED, FcmSender.Outcome.CONFIG_FAILURE);
        assertBaseOutcome(ErrorCode.INVALID_ARGUMENT, FcmSender.Outcome.PERMANENT_FAILURE);
        assertBaseOutcome(ErrorCode.FAILED_PRECONDITION, FcmSender.Outcome.PERMANENT_FAILURE);
        assertBaseOutcome(ErrorCode.OUT_OF_RANGE, FcmSender.Outcome.PERMANENT_FAILURE);
        assertBaseOutcome(ErrorCode.NOT_FOUND, FcmSender.Outcome.PERMANENT_FAILURE);
        assertBaseOutcome(ErrorCode.CONFLICT, FcmSender.Outcome.PERMANENT_FAILURE);
        assertBaseOutcome(ErrorCode.ALREADY_EXISTS, FcmSender.Outcome.PERMANENT_FAILURE);
        assertBaseOutcome(ErrorCode.DATA_LOSS, FcmSender.Outcome.PERMANENT_FAILURE);
    }

    @Test
    void legacyNotificationFailureRemainsAnUnsuccessfulLegacyResult() throws Exception {
        FirebaseMessaging firebaseMessaging = org.mockito.Mockito.mock(FirebaseMessaging.class);
        FirebaseMessagingException failure = failure(MessagingErrorCode.UNREGISTERED);
        when(firebaseMessaging.send(any(Message.class))).thenThrow(failure);
        FirebaseAdminFcmSender sender = new FirebaseAdminFcmSender(firebaseMessaging);

        FcmSender.SendResult result = sender.send(
                device("push-token"),
                new NotificationPayload("Title", "Body", Map.of("type", "task_reminder"))
        );

        assertThat(result.successful()).isFalse();
        assertThat(result.outcome()).isEqualTo(FcmSender.Outcome.RETRY);
    }

    private void assertDataOnlyOutcome(MessagingErrorCode errorCode, FcmSender.Outcome expected) throws Exception {
        FirebaseMessaging firebaseMessaging = org.mockito.Mockito.mock(FirebaseMessaging.class);
        FirebaseMessagingException failure = failure(errorCode);
        when(firebaseMessaging.send(any(Message.class))).thenThrow(failure);
        FirebaseAdminFcmSender sender = new FirebaseAdminFcmSender(firebaseMessaging);

        FcmSender.SendResult result = sender.sendDataOnly(
                device("push-token"), Map.of("type", "focus_reminder"), "focus-period", Duration.ofMinutes(15)
        );

        assertThat(result.outcome()).isEqualTo(expected);
    }

    private void assertBaseOutcome(ErrorCode errorCode, FcmSender.Outcome expected) throws Exception {
        FirebaseMessaging firebaseMessaging = org.mockito.Mockito.mock(FirebaseMessaging.class);
        FirebaseMessagingException failure = failure(null, errorCode);
        when(firebaseMessaging.send(any(Message.class))).thenThrow(failure);
        FirebaseAdminFcmSender sender = new FirebaseAdminFcmSender(firebaseMessaging);

        FcmSender.SendResult result = sender.sendDataOnly(
                device("push-token"), Map.of("type", "focus_reminder"), "focus-period", Duration.ofMinutes(15)
        );

        assertThat(result.outcome()).isEqualTo(expected);
        assertThat(result.providerResponse()).contains("firebase=" + errorCode.name());
    }

    private FirebaseMessagingException failure(MessagingErrorCode errorCode) {
        return failure(errorCode, null);
    }

    private FirebaseMessagingException failure(MessagingErrorCode errorCode, ErrorCode baseCode) {
        FirebaseMessagingException exception = org.mockito.Mockito.mock(FirebaseMessagingException.class);
        when(exception.getMessagingErrorCode()).thenReturn(errorCode);
        when(exception.getErrorCode()).thenReturn(baseCode);
        when(exception.getMessage()).thenReturn("provider failure");
        return exception;
    }

    private DeviceRegistration device(String token) {
        DeviceRegistration device = new DeviceRegistration();
        device.setPushToken(token);
        device.setPlatform("android");
        return device;
    }

    @SuppressWarnings("unchecked")
    private <T> T field(Object target, String name) throws ReflectiveOperationException {
        Field field = target.getClass().getDeclaredField(name);
        field.setAccessible(true);
        return (T) field.get(target);
    }
}
