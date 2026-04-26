package com.rocketflow.notifications;

import java.util.Map;

public record NotificationPayload(String title, String body, Map<String, String> data) {
}
