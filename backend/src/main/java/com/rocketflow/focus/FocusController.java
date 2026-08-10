package com.rocketflow.focus;

import static com.rocketflow.focus.FocusApi.*;

import java.util.UUID;

import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.rocketflow.accounts.CurrentUserService;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/focus")
public class FocusController {
    private final FocusService focusService;
    private final CurrentUserService currentUserService;

    public FocusController(FocusService focusService, CurrentUserService currentUserService) {
        this.focusService = focusService;
        this.currentUserService = currentUserService;
    }

    @GetMapping("/current")
    public PeriodDto current() {
        return focusService.current(userId());
    }

    @GetMapping("/candidates")
    public CandidateListResponse candidates(
            @RequestParam(required = false) String q,
            @RequestParam(required = false) UUID folderId,
            @RequestParam(required = false) UUID goalId,
            @RequestParam(required = false) String cursor,
            @RequestParam(defaultValue = "50") int limit
    ) {
        return focusService.candidates(userId(), q, folderId, goalId, cursor, limit);
    }

    @PutMapping("/current/items/{taskId}")
    public PeriodDto add(
            @PathVariable UUID taskId,
            @Valid @RequestBody(required = false) MutationRequest request
    ) {
        return focusService.add(userId(), taskId, request);
    }

    @DeleteMapping("/current/items/{taskId}")
    public PeriodDto remove(
            @PathVariable UUID taskId,
            @Valid @RequestBody(required = false) MutationRequest request
    ) {
        return focusService.remove(userId(), taskId, request);
    }

    @PatchMapping("/current/items/order")
    public PeriodDto reorder(@Valid @RequestBody ReorderRequest request) {
        return focusService.reorder(userId(), request);
    }

    @PostMapping("/rollovers/{sourcePeriodId}/resolve")
    public PeriodDto resolveRollover(
            @PathVariable UUID sourcePeriodId,
            @Valid @RequestBody ResolveRolloverRequest request
    ) {
        return focusService.resolveRollover(userId(), sourcePeriodId, request);
    }

    @GetMapping("/history")
    public HistoryResponse history() {
        return focusService.history(userId());
    }

    @GetMapping("/history/{periodId}")
    public PeriodDto historyPeriod(@PathVariable UUID periodId) {
        return focusService.historyPeriod(userId(), periodId);
    }

    @GetMapping("/notification-settings")
    public NotificationSettingsDto settings() {
        return focusService.settings(userId());
    }

    @PatchMapping("/notification-settings")
    public NotificationSettingsDto updateSettings(@Valid @RequestBody UpdateNotificationSettingsRequest request) {
        return focusService.updateSettings(userId(), request);
    }

    private UUID userId() {
        return currentUserService.requireAuthenticatedUser().userId();
    }
}
