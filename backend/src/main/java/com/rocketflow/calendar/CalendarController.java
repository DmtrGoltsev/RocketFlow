package com.rocketflow.calendar;

import static com.rocketflow.calendar.CalendarApi.*;

import java.time.Instant;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.rocketflow.accounts.CurrentUserService;
import com.rocketflow.common.ApiException;

@RestController
@RequestMapping("/api")
public class CalendarController {

    private final CalendarService calendarService;
    private final CurrentUserService currentUserService;

    public CalendarController(CalendarService calendarService, CurrentUserService currentUserService) {
        this.calendarService = calendarService;
        this.currentUserService = currentUserService;
    }

    @GetMapping("/calendar")
    public Object getCalendar(
            @RequestParam String from,
            @RequestParam(required = false) String to,
            @RequestParam(required = false) String toExclusive
    ) {
        var actor = currentUserService.requireAuthenticatedUser();
        if (toExclusive != null || isDateOnly(from)) {
            if (toExclusive == null) {
                throw validationError("Calendar date range requires from and toExclusive.");
            }
            return calendarService.getCalendarMarkers(actor.userId(), parseDate(from), parseDate(toExclusive));
        }
        if (to == null) {
            throw validationError("Legacy calendar range requires from and to.");
        }
        return calendarService.getCalendar(actor.userId(), parseInstant(from), parseInstant(to));
    }

    private boolean isDateOnly(String value) {
        return value != null && value.length() == 10;
    }

    private LocalDate parseDate(String value) {
        try {
            return LocalDate.parse(value);
        } catch (DateTimeParseException exception) {
            throw validationError("Calendar date must use YYYY-MM-DD.");
        }
    }

    private Instant parseInstant(String value) {
        try {
            return Instant.parse(value);
        } catch (DateTimeParseException exception) {
            throw validationError("Calendar instant is invalid.");
        }
    }

    private ApiException validationError(String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, "validation_error", message);
    }
}
