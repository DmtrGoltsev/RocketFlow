package com.rocketflow.sharing;

import static com.rocketflow.goals.GoalsApi.*;
import static com.rocketflow.sharing.SharingApi.*;
import static com.rocketflow.sharing.SharingValues.*;
import static com.rocketflow.tasks.TasksApi.*;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.accounts.User;
import com.rocketflow.accounts.UserRepository;
import com.rocketflow.common.ApiException;
import com.rocketflow.sharing.SharingAccessService.GoalAccess;
import com.rocketflow.sharing.SharingAccessService.TaskAccess;
import com.rocketflow.tasks.Task;
import com.rocketflow.tasks.TaskRepository;
import com.rocketflow.tasks.TaskTag;
import com.rocketflow.tasks.TaskTagLink;
import com.rocketflow.tasks.TaskTagLinkRepository;
import com.rocketflow.tasks.TaskTagRepository;

@Service
public class SharingService {

    private final ShareInvitationRepository shareInvitationRepository;
    private final GoalShareRepository goalShareRepository;
    private final TaskShareRepository taskShareRepository;
    private final SharingAccessService sharingAccessService;
    private final UserRepository userRepository;
    private final TaskRepository taskRepository;
    private final TaskTagRepository taskTagRepository;
    private final TaskTagLinkRepository taskTagLinkRepository;

    public SharingService(
            ShareInvitationRepository shareInvitationRepository,
            GoalShareRepository goalShareRepository,
            TaskShareRepository taskShareRepository,
            SharingAccessService sharingAccessService,
            UserRepository userRepository,
            TaskRepository taskRepository,
            TaskTagRepository taskTagRepository,
            TaskTagLinkRepository taskTagLinkRepository
    ) {
        this.shareInvitationRepository = shareInvitationRepository;
        this.goalShareRepository = goalShareRepository;
        this.taskShareRepository = taskShareRepository;
        this.sharingAccessService = sharingAccessService;
        this.userRepository = userRepository;
        this.taskRepository = taskRepository;
        this.taskTagRepository = taskTagRepository;
        this.taskTagLinkRepository = taskTagLinkRepository;
    }

    @Transactional
    public ShareInvitationDto createGoalInvitation(UUID actorUserId, UUID goalId, ShareRequest request) {
        GoalAccess goalAccess = sharingAccessService.requireGoalOwner(goalId, actorUserId);
        return createInvitation(actorUserId, goalAccess.goal().getOwnerUserId(), TARGET_GOAL, goalId, request.email());
    }

    @Transactional
    public ShareInvitationDto createTaskInvitation(UUID actorUserId, UUID taskId, ShareRequest request) {
        TaskAccess taskAccess = sharingAccessService.requireTaskOwner(taskId, actorUserId);
        return createInvitation(actorUserId, taskAccess.task().getOwnerUserId(), TARGET_TASK, taskId, request.email());
    }

    @Transactional
    public ShareInvitationListResponse listInvitations(UUID actorUserId) {
        refreshExpiredInvitations();
        User actor = requireUser(actorUserId);
        return new ShareInvitationListResponse(shareInvitationRepository.findVisibleToUser(actorUserId, actor.getEmail())
                .stream()
                .map(this::toDto)
                .toList());
    }

    @Transactional
    public ShareInvitationActionResponse acceptInvitation(UUID actorUserId, UUID invitationId) {
        refreshExpiredInvitations();
        User actor = requireUser(actorUserId);
        ShareInvitation invitation = shareInvitationRepository.findById(invitationId)
                .orElseThrow(() -> notFound("Invitation"));

        ensureInvitationTarget(invitation, actor);
        ensurePendingInvitation(invitation);

        Instant now = Instant.now();
        if (TARGET_GOAL.equals(invitation.getTargetType())) {
            GoalAccess goalAccess = sharingAccessService.requireGoalOwner(invitation.getTargetId(), invitation.getInviterUserId());
            if (goalShareRepository.existsByGoalIdAndCollaboratorUserIdAndStatus(
                    invitation.getTargetId(),
                    actorUserId,
                    SHARE_ACTIVE
            )) {
                throw new ApiException(HttpStatus.CONFLICT, "conflict", "Access already exists for this goal.");
            }

            GoalShare share = new GoalShare();
            share.setId(UUID.randomUUID());
            share.setGoalId(goalAccess.goal().getId());
            share.setOwnerUserId(goalAccess.goal().getOwnerUserId());
            share.setCollaboratorUserId(actorUserId);
            share.setInvitationId(invitation.getId());
            share.setStatus(SHARE_ACTIVE);
            share.setCreatedAt(now);
            share.setUpdatedAt(now);
            goalShareRepository.save(share);
        } else {
            TaskAccess taskAccess = sharingAccessService.requireTaskOwner(invitation.getTargetId(), invitation.getInviterUserId());
            if (taskShareRepository.existsByTaskIdAndCollaboratorUserIdAndStatus(
                    invitation.getTargetId(),
                    actorUserId,
                    SHARE_ACTIVE
            )) {
                throw new ApiException(HttpStatus.CONFLICT, "conflict", "Access already exists for this task.");
            }

            TaskShare share = new TaskShare();
            share.setId(UUID.randomUUID());
            share.setTaskId(taskAccess.task().getId());
            share.setOwnerUserId(taskAccess.task().getOwnerUserId());
            share.setCollaboratorUserId(actorUserId);
            share.setInvitationId(invitation.getId());
            share.setStatus(SHARE_ACTIVE);
            share.setCreatedAt(now);
            share.setUpdatedAt(now);
            taskShareRepository.save(share);
        }

        markInvitationResolved(invitation, INVITATION_ACCEPTED, actorUserId, now);
        return new ShareInvitationActionResponse(invitation.getId(), invitation.getStatus());
    }

    @Transactional
    public ShareInvitationActionResponse declineInvitation(UUID actorUserId, UUID invitationId) {
        refreshExpiredInvitations();
        User actor = requireUser(actorUserId);
        ShareInvitation invitation = shareInvitationRepository.findById(invitationId)
                .orElseThrow(() -> notFound("Invitation"));

        ensureInvitationTarget(invitation, actor);
        ensurePendingInvitation(invitation);

        markInvitationResolved(invitation, INVITATION_DECLINED, actorUserId, Instant.now());
        return new ShareInvitationActionResponse(invitation.getId(), invitation.getStatus());
    }

    @Transactional
    public ShareInvitationActionResponse revokeInvitation(UUID actorUserId, UUID invitationId) {
        refreshExpiredInvitations();
        ShareInvitation invitation = shareInvitationRepository.findById(invitationId)
                .orElseThrow(() -> notFound("Invitation"));

        if (!invitation.getInviterUserId().equals(actorUserId)) {
            throw notFound("Invitation");
        }
        if (INVITATION_DECLINED.equals(invitation.getStatus())
                || INVITATION_REVOKED.equals(invitation.getStatus())
                || INVITATION_EXPIRED.equals(invitation.getStatus())) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", "Invitation can no longer be revoked.");
        }

        Instant now = Instant.now();
        goalShareRepository.findByInvitationId(invitationId).ifPresent(share -> revokeGoalShare(share, now));
        taskShareRepository.findByInvitationId(invitationId).ifPresent(share -> revokeTaskShare(share, now));
        markInvitationResolved(invitation, INVITATION_REVOKED, actorUserId, now);
        return new ShareInvitationActionResponse(invitation.getId(), invitation.getStatus());
    }

    @Transactional
    public SharedResourcesResponse listSharedResources(UUID actorUserId) {
        List<GoalShare> goalShares = goalShareRepository.findByCollaboratorUserIdAndStatusOrderByCreatedAtAsc(actorUserId, SHARE_ACTIVE);
        List<TaskShare> taskShares = taskShareRepository.findByCollaboratorUserIdAndStatusOrderByCreatedAtAsc(actorUserId, SHARE_ACTIVE);

        Map<UUID, GoalDto> goalsById = goalShares.stream()
                .map(GoalShare::getGoalId)
                .distinct()
                .map(goalId -> sharingAccessService.requireGoalAccess(goalId, actorUserId).goal())
                .sorted(Comparator.comparing(goal -> goal.getCreatedAt()))
                .collect(Collectors.toMap(
                        goal -> goal.getId(),
                        goal -> toGoalDto(goal, true),
                        (left, right) -> left,
                        LinkedHashMap::new
                ));

        Map<UUID, Task> tasksById = new LinkedHashMap<>();
        for (GoalShare goalShare : goalShares) {
            sharingAccessService.requireGoalAccess(goalShare.getGoalId(), actorUserId);
            taskRepository.findByGoalIdAndOwnerUserIdOrderByCreatedAtAsc(goalShare.getGoalId(), goalShare.getOwnerUserId())
                    .forEach(task -> tasksById.put(task.getId(), task));
        }
        for (TaskShare taskShare : taskShares) {
            Task task = sharingAccessService.requireTaskAccess(taskShare.getTaskId(), actorUserId).task();
            tasksById.put(task.getId(), task);
        }

        List<TaskDto> taskDtos = new ArrayList<>();
        for (Task task : tasksById.values().stream().sorted(Comparator.comparing(Task::getCreatedAt)).toList()) {
            taskDtos.add(toTaskDto(task, true));
        }

        return new SharedResourcesResponse(new ArrayList<>(goalsById.values()), taskDtos);
    }

    private ShareInvitationDto createInvitation(
            UUID actorUserId,
            UUID ownerUserId,
            String targetType,
            UUID targetId,
            String email
    ) {
        refreshExpiredInvitations();
        User actor = requireUser(actorUserId);
        String normalizedEmail = normalizeEmail(email);

        if (actor.getEmail().equalsIgnoreCase(normalizedEmail) || ownerUserId.equals(actorUserId)) {
            if (actor.getEmail().equalsIgnoreCase(normalizedEmail)) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "You cannot invite yourself.");
            }
        }

        if (shareInvitationRepository.existsByTargetTypeAndTargetIdAndStatusAndTargetEmailIgnoreCase(
                targetType,
                targetId,
                INVITATION_PENDING,
                normalizedEmail
        )) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", "An active invitation already exists.");
        }

        userRepository.findByEmailIgnoreCase(normalizedEmail).ifPresent(collaborator -> {
            if (collaborator.getId().equals(actorUserId)) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "You cannot invite yourself.");
            }
            if (TARGET_GOAL.equals(targetType)
                    && goalShareRepository.existsByGoalIdAndCollaboratorUserIdAndStatus(targetId, collaborator.getId(), SHARE_ACTIVE)) {
                throw new ApiException(HttpStatus.CONFLICT, "conflict", "Access already exists for this goal.");
            }
            if (TARGET_TASK.equals(targetType)
                    && taskShareRepository.existsByTaskIdAndCollaboratorUserIdAndStatus(targetId, collaborator.getId(), SHARE_ACTIVE)) {
                throw new ApiException(HttpStatus.CONFLICT, "conflict", "Access already exists for this task.");
            }
        });

        Instant now = Instant.now();
        ShareInvitation invitation = new ShareInvitation();
        invitation.setId(UUID.randomUUID());
        invitation.setInviterUserId(actorUserId);
        invitation.setTargetType(targetType);
        invitation.setTargetId(targetId);
        invitation.setTargetEmail(normalizedEmail);
        invitation.setStatus(INVITATION_PENDING);
        invitation.setCreatedAt(now);
        invitation.setUpdatedAt(now);
        invitation.setExpiresAt(now.plus(INVITATION_TTL));
        return toDto(shareInvitationRepository.save(invitation));
    }

    private void refreshExpiredInvitations() {
        Instant now = Instant.now();
        shareInvitationRepository.findByStatusAndExpiresAtBefore(INVITATION_PENDING, now)
                .forEach(invitation -> {
                    invitation.setStatus(INVITATION_EXPIRED);
                    invitation.setUpdatedAt(now);
                    invitation.setResolvedAt(now);
                    shareInvitationRepository.save(invitation);
                });
    }

    private void ensureInvitationTarget(ShareInvitation invitation, User actor) {
        if (!actor.getEmail().equalsIgnoreCase(invitation.getTargetEmail())) {
            throw new ApiException(HttpStatus.FORBIDDEN, "forbidden", "Invitation is not available for this account.");
        }
    }

    private void ensurePendingInvitation(ShareInvitation invitation) {
        if (!INVITATION_PENDING.equals(invitation.getStatus())) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", "Invitation is no longer pending.");
        }
    }

    private void markInvitationResolved(ShareInvitation invitation, String status, UUID actorUserId, Instant now) {
        invitation.setStatus(status);
        invitation.setUpdatedAt(now);
        invitation.setResolvedAt(now);
        invitation.setResolvedByUserId(actorUserId);
        shareInvitationRepository.save(invitation);
    }

    private void revokeGoalShare(GoalShare share, Instant now) {
        if (!SHARE_REVOKED.equals(share.getStatus())) {
            share.setStatus(SHARE_REVOKED);
            share.setUpdatedAt(now);
            share.setRevokedAt(now);
            goalShareRepository.save(share);
        }
    }

    private void revokeTaskShare(TaskShare share, Instant now) {
        if (!SHARE_REVOKED.equals(share.getStatus())) {
            share.setStatus(SHARE_REVOKED);
            share.setUpdatedAt(now);
            share.setRevokedAt(now);
            taskShareRepository.save(share);
        }
    }

    private User requireUser(UUID userId) {
        return userRepository.findById(userId)
                .orElseThrow(() -> notFound("User"));
    }

    private ShareInvitationDto toDto(ShareInvitation invitation) {
        return new ShareInvitationDto(
                invitation.getId(),
                invitation.getTargetType(),
                invitation.getTargetId(),
                invitation.getTargetEmail(),
                invitation.getStatus(),
                invitation.getCreatedAt(),
                invitation.getExpiresAt()
        );
    }

    private GoalDto toGoalDto(com.rocketflow.goals.Goal goal, boolean shared) {
        return new GoalDto(
                goal.getId(),
                goal.getFolderId(),
                goal.getName(),
                goal.getDescription(),
                goal.isArchived(),
                shared,
                goal.getVersion(),
                goal.getCreatedAt(),
                goal.getUpdatedAt()
        );
    }

    private TaskDto toTaskDto(Task task, boolean shared) {
        return new TaskDto(
                task.getId(),
                task.getGoalId(),
                task.getTitle(),
                task.getDescription(),
                task.getType(),
                task.getPriority(),
                task.getStatus(),
                task.getPlannedTime(),
                task.getDueTime(),
                task.isArchived(),
                shared,
                task.getVersion(),
                resolveTags(task.getId()),
                null,
                List.of(),
                task.getCreatedAt(),
                task.getUpdatedAt()
        );
    }

    private List<TagDto> resolveTags(UUID taskId) {
        List<TaskTagLink> links = taskTagLinkRepository.findByTaskId(taskId);
        if (links.isEmpty()) {
            return List.of();
        }
        Map<UUID, TaskTag> tagsById = taskTagRepository.findAllById(links.stream().map(TaskTagLink::getTagId).toList())
                .stream()
                .collect(Collectors.toMap(TaskTag::getId, Function.identity()));

        return links.stream()
                .map(link -> tagsById.get(link.getTagId()))
                .filter(tag -> tag != null)
                .map(tag -> new TagDto(tag.getId(), tag.getName(), tag.getColor()))
                .toList();
    }

    private String normalizeEmail(String email) {
        return email.trim().toLowerCase();
    }

    private ApiException notFound(String entityName) {
        return new ApiException(HttpStatus.NOT_FOUND, "not_found", entityName + " was not found.");
    }
}
