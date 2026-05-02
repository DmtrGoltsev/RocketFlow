package com.rocketflow.notifications;

import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.Notification;

public class FirebaseAdminFcmSender implements FcmSender {

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

        try {
            String messageId = firebaseMessaging.send(messageBuilder.build());
            return SendResult.sent(messageId);
        } catch (FirebaseMessagingException exception) {
            return SendResult.failed(exception.getErrorCode() + ":" + exception.getMessage());
        }
    }
}
