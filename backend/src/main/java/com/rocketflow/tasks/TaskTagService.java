package com.rocketflow.tasks;

import static com.rocketflow.tasks.TasksApi.*;

import java.time.Instant;
import java.util.UUID;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class TaskTagService {

    private final TaskTagRepository taskTagRepository;

    public TaskTagService(TaskTagRepository taskTagRepository) {
        this.taskTagRepository = taskTagRepository;
    }

    @Transactional(readOnly = true)
    public TagListResponse list(UUID ownerUserId) {
        return new TagListResponse(taskTagRepository.findByOwnerUserIdOrderByNameAsc(ownerUserId)
                .stream()
                .map(tag -> new TagDto(tag.getId(), tag.getName(), tag.getColor()))
                .toList());
    }

    @Transactional
    public TagDto create(UUID ownerUserId, CreateTagRequest request) {
        Instant now = Instant.now();
        TaskTag tag = new TaskTag();
        tag.setId(UUID.randomUUID());
        tag.setOwnerUserId(ownerUserId);
        tag.setName(request.name().trim());
        tag.setColor(request.color());
        tag.setCreatedAt(now);
        tag.setUpdatedAt(now);
        TaskTag saved = taskTagRepository.save(tag);
        return new TagDto(saved.getId(), saved.getName(), saved.getColor());
    }
}
