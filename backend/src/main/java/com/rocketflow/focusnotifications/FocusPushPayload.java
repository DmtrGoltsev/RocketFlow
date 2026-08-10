package com.rocketflow.focusnotifications;

import java.util.UUID;

record FocusPushPayload(
        String type,
        UUID eventId,
        UUID periodId,
        String title,
        String body,
        String url
) {
    static FocusPushPayload reminder(UUID eventId, UUID periodId) {
        return new FocusPushPayload(
                "focus_reminder",
                eventId,
                periodId,
                "\u0424\u043e\u043a\u0443\u0441 \u043d\u0435\u0434\u0435\u043b\u0438",
                "\u0412 \u0444\u043e\u043a\u0443\u0441\u0435 \u0435\u0441\u0442\u044c \u043d\u0435\u0437\u0430\u0432\u0435\u0440\u0448\u0435\u043d\u043d\u044b\u0435 \u0437\u0430\u0434\u0430\u0447\u0438",
                "/rocket/app/focus"
        );
    }
}
