package com.rocketflow.goals;

import static com.rocketflow.goals.GoalsApi.*;

import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.rocketflow.accounts.CurrentUserService;

import jakarta.validation.Valid;

@RestController
public class GoalController {

    private final GoalService goalService;
    private final CurrentUserService currentUserService;

    public GoalController(GoalService goalService, CurrentUserService currentUserService) {
        this.goalService = goalService;
        this.currentUserService = currentUserService;
    }

    @GetMapping("/api/folders/{folderId}/goals")
    public GoalListResponse list(@PathVariable String folderId) {
        return goalService.list(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(folderId));
    }

    @PostMapping("/api/folders/{folderId}/goals")
    @ResponseStatus(HttpStatus.CREATED)
    public GoalDto create(@PathVariable String folderId, @Valid @RequestBody CreateGoalRequest request) {
        return goalService.create(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(folderId), request);
    }

    @GetMapping("/api/goals/{goalId}")
    public GoalDto get(@PathVariable String goalId) {
        return goalService.get(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(goalId));
    }

    @PatchMapping("/api/goals/{goalId}")
    public GoalDto update(@PathVariable String goalId, @Valid @RequestBody UpdateGoalRequest request) {
        return goalService.update(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(goalId), request);
    }

    @DeleteMapping("/api/goals/{goalId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable String goalId) {
        goalService.softDelete(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(goalId));
    }
}
