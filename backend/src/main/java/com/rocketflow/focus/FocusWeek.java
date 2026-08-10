package com.rocketflow.focus;

import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.TemporalAdjusters;

record FocusWeek(LocalDate start, LocalDate endExclusive, Instant startsAt, Instant endsAt, String timezone) {
    static FocusWeek containing(Instant now, ZoneId zone) {
        LocalDate start = now.atZone(zone).toLocalDate()
                .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
        LocalDate end = start.plusWeeks(1);
        return new FocusWeek(
                start,
                end,
                start.atStartOfDay(zone).toInstant(),
                end.atStartOfDay(zone).toInstant(),
                zone.getId()
        );
    }
}
