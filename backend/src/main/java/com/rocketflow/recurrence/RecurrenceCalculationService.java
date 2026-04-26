package com.rocketflow.recurrence;

import java.time.DayOfWeek;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.YearMonth;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.temporal.ChronoUnit;
import java.time.temporal.TemporalAdjusters;
import java.util.List;
import java.util.Optional;

import org.springframework.stereotype.Service;

@Service
public class RecurrenceCalculationService {

    public Optional<Instant> nextOccurrence(TaskRecurrenceRule rule, ZoneId ownerZone, Instant after) {
        if (!rule.isActive()) {
            return Optional.empty();
        }

        return switch (rule.getMode()) {
            case "daily" -> nextDaily(rule, ownerZone, after);
            case "weekly" -> nextWeekly(rule, ownerZone, after);
            case "monthly" -> nextMonthly(rule, ownerZone, after);
            default -> Optional.empty();
        };
    }

    private Optional<Instant> nextDaily(TaskRecurrenceRule rule, ZoneId ownerZone, Instant after) {
        ZonedDateTime start = rule.getStartAt().atZone(ownerZone);
        ZonedDateTime candidate = start;
        while (!candidate.toInstant().isAfter(after)) {
            candidate = candidate.plusDays(rule.getIntervalValue());
        }
        return withinEnd(rule, candidate.toInstant());
    }

    private Optional<Instant> nextWeekly(TaskRecurrenceRule rule, ZoneId ownerZone, Instant after) {
        ZonedDateTime start = rule.getStartAt().atZone(ownerZone);
        ZonedDateTime afterZoned = after.atZone(ownerZone);
        LocalTime startTime = start.toLocalTime();
        LocalDate startDate = start.toLocalDate();
        LocalDate cycleStart = startDate.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
        LocalDate searchDate = startDate.isAfter(afterZoned.toLocalDate()) ? startDate : afterZoned.toLocalDate();
        List<DayOfWeek> daysOfWeek = RecurrenceService.parseDaysOfWeek(rule.getDaysOfWeek());

        for (int offset = 0; offset < 3660; offset++) {
            LocalDate candidateDate = searchDate.plusDays(offset);
            if (!daysOfWeek.contains(candidateDate.getDayOfWeek())) {
                continue;
            }
            LocalDate candidateCycle = candidateDate.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
            long weeksBetween = ChronoUnit.WEEKS.between(cycleStart, candidateCycle);
            if (weeksBetween < 0 || weeksBetween % rule.getIntervalValue() != 0) {
                continue;
            }
            ZonedDateTime candidate = candidateDate.atTime(startTime).atZone(ownerZone);
            if (candidate.toInstant().isBefore(rule.getStartAt()) || !candidate.toInstant().isAfter(after)) {
                continue;
            }
            return withinEnd(rule, candidate.toInstant());
        }

        return Optional.empty();
    }

    private Optional<Instant> nextMonthly(TaskRecurrenceRule rule, ZoneId ownerZone, Instant after) {
        ZonedDateTime start = rule.getStartAt().atZone(ownerZone);
        ZonedDateTime afterZoned = after.atZone(ownerZone);
        LocalTime startTime = start.toLocalTime();
        YearMonth startMonth = YearMonth.from(start);
        YearMonth searchMonth = startMonth.isAfter(YearMonth.from(afterZoned)) ? startMonth : YearMonth.from(afterZoned);

        for (int offset = 0; offset < 240; offset++) {
            YearMonth candidateMonth = searchMonth.plusMonths(offset);
            long monthsBetween = ChronoUnit.MONTHS.between(startMonth, candidateMonth);
            if (monthsBetween < 0 || monthsBetween % rule.getIntervalValue() != 0) {
                continue;
            }
            if (rule.getDayOfMonth() > candidateMonth.lengthOfMonth()) {
                continue;
            }
            ZonedDateTime candidate = candidateMonth.atDay(rule.getDayOfMonth()).atTime(startTime).atZone(ownerZone);
            if (candidate.toInstant().isBefore(rule.getStartAt()) || !candidate.toInstant().isAfter(after)) {
                continue;
            }
            return withinEnd(rule, candidate.toInstant());
        }

        return Optional.empty();
    }

    private Optional<Instant> withinEnd(TaskRecurrenceRule rule, Instant candidate) {
        if (rule.getEndAt() != null && candidate.isAfter(rule.getEndAt())) {
            return Optional.empty();
        }
        return Optional.of(candidate);
    }
}
