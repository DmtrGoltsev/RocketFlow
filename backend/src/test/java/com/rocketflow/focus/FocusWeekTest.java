package com.rocketflow.focus;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;

import org.junit.jupiter.api.Test;

class FocusWeekTest {
    @Test
    void usesMondayBoundariesInUserTimezoneAcrossDst() {
        FocusWeek week = FocusWeek.containing(
                Instant.parse("2026-03-04T12:00:00Z"),
                ZoneId.of("America/New_York")
        );

        assertEquals(LocalDate.of(2026, 3, 2), week.start());
        assertEquals(LocalDate.of(2026, 3, 9), week.endExclusive());
        assertEquals(Instant.parse("2026-03-02T05:00:00Z"), week.startsAt());
        assertEquals(Instant.parse("2026-03-09T04:00:00Z"), week.endsAt());
        assertEquals(Duration.ofHours(167), Duration.between(week.startsAt(), week.endsAt()));
    }

    @Test
    void normalizesMissingOrZeroEffortToOne() {
        assertEquals(1, FocusService.effectiveWeight(null));
        assertEquals(1, FocusService.effectiveWeight(0));
        assertEquals(1, FocusService.effectiveWeight(-2));
        assertEquals(8, FocusService.effectiveWeight(8));
    }
}
