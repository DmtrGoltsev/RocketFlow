package com.rocketflow.focusnotifications;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.time.LocalTime;

import org.junit.jupiter.api.Test;

class QuietHoursTest {
    @Test
    void handlesQuietHoursCrossingMidnight() {
        LocalTime start = LocalTime.of(22, 0);
        LocalTime end = LocalTime.of(7, 0);

        assertThat(QuietHours.contains(Instant.parse("2026-08-09T20:30:00Z"), "Europe/Moscow", start, end)).isTrue();
        assertThat(QuietHours.contains(Instant.parse("2026-08-10T02:30:00Z"), "Europe/Moscow", start, end)).isTrue();
        assertThat(QuietHours.contains(Instant.parse("2026-08-10T09:00:00Z"), "Europe/Moscow", start, end)).isFalse();
    }

    @Test
    void evaluatesLocalTimeAfterDstJump() {
        assertThat(QuietHours.contains(
                Instant.parse("2026-03-29T01:30:00Z"),
                "Europe/Berlin",
                LocalTime.of(2, 0),
                LocalTime.of(4, 0)
        )).isTrue();
    }
}
