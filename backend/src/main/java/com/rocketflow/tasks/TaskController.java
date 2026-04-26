package com.rocketflow.tasks;

import static com.rocketflow.tasks.TasksApi.*;

import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.rocketflow.accounts.CurrentUserService;
import com.rocketflow.calendar.TaskScheduleService;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api")
public class TaskController {

    private final TaskService taskService;
    private final TaskTagService taskTagService;
    private final TaskScheduleService taskScheduleService;
    private final CurrentUserService currentUserService;

    public TaskController(
            TaskService taskService,
            TaskTagService taskTagService,
            TaskScheduleService taskScheduleService,
            CurrentUserService currentUserService
    ) {
        this.taskService = taskService;
        this.taskTagService = taskTagService;
        this.taskScheduleService = taskScheduleService;
        this.currentUserService = currentUserService;
    }

    @GetMapping("/goals/{goalId}/tasks")
    public TaskListResponse list(@PathVariable String goalId) {
        return taskService.list(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(goalId));
    }

    @PostMapping("/goals/{goalId}/tasks")
    @ResponseStatus(HttpStatus.CREATED)
    public TaskDto create(@PathVariable String goalId, @Valid @RequestBody CreateTaskRequest request) {
        return taskService.create(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(goalId), request);
    }

    @GetMapping("/tasks/{taskId}")
    public TaskDto get(@PathVariable String taskId) {
        return taskService.get(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(taskId));
    }

    @PatchMapping("/tasks/{taskId}")
    public TaskDto update(@PathVariable String taskId, @Valid @RequestBody UpdateTaskRequest request) {
        return taskService.update(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(taskId), request);
    }

    @DeleteMapping("/tasks/{taskId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable String taskId) {
        taskService.softDelete(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(taskId));
    }

    @PutMapping("/tasks/{taskId}/recurrence")
    public TaskRecurrenceResponse upsertRecurrence(
            @PathVariable String taskId,
            @Valid @RequestBody UpsertRecurrenceRequest request
    ) {
        return taskService.upsertRecurrence(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(taskId), request);
    }

    @PutMapping("/tasks/{taskId}/reminders")
    public TaskRemindersResponse replaceReminders(
            @PathVariable String taskId,
            @Valid @RequestBody ReplaceRemindersRequest request
    ) {
        return taskService.replaceReminders(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(taskId), request);
    }

    @PostMapping("/tasks/{taskId}/move")
    public MoveTaskResponse moveTask(@PathVariable String taskId, @Valid @RequestBody MoveTaskRequest request) {
        return taskScheduleService.moveTask(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(taskId), request);
    }

    @PostMapping("/tasks/{taskId}/reschedule")
    public QuickRescheduleResponse quickReschedule(
            @PathVariable String taskId,
            @Valid @RequestBody QuickRescheduleRequest request
    ) {
        return taskScheduleService.quickReschedule(
                currentUserService.requireAuthenticatedUser().userId(),
                UUID.fromString(taskId),
                request
        );
    }

    @GetMapping("/tags")
    public TagListResponse listTags() {
        return taskTagService.list(currentUserService.requireAuthenticatedUser().userId());
    }

    @PostMapping("/tags")
    @ResponseStatus(HttpStatus.CREATED)
    public TagDto createTag(@Valid @RequestBody CreateTagRequest request) {
        return taskTagService.create(currentUserService.requireAuthenticatedUser().userId(), request);
    }
}
