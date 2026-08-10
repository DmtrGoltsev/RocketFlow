package com.rocketflow.focusnotifications;

import java.time.Instant;
import java.time.LocalTime;
import java.time.ZoneId;

final class QuietHours {
    private QuietHours() {
    }

    static boolean contains(Instant instant, String timezone, LocalTime start, LocalTime end) {
        if (start == null || end == null) {
            return false;
        }
        LocalTime local = instant.atZone(ZoneId.of(timezone)).toLocalTime();
        if (start.equals(end)) {
            return true;
        }
        if (start.isBefore(end)) {
            return !local.isBefore(start) && local.isBefore(end);
        }
        return !local.isBefore(start) || local.isBefore(end);
    }
}
