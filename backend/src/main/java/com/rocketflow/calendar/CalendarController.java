package com.rocketflow.calendar;

import static com.rocketflow.calendar.CalendarApi.*;

import java.time.Instant;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.rocketflow.accounts.CurrentUserService;

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
    public CalendarResponse getCalendar(@RequestParam Instant from, @RequestParam Instant to) {
        return calendarService.getCalendar(currentUserService.requireAuthenticatedUser().userId(), from, to);
    }
}
