package com.rocketflow.sharing;

import static com.rocketflow.goals.GoalsApi.*;
import static com.rocketflow.folders.FoldersApi.*;
import static com.rocketflow.sharing.SharingApi.*;
import static com.rocketflow.sharing.SharingValues.*;
import static com.rocketflow.tasks.TasksApi.*;

import java.security.SecureRandom;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.accounts.User;
import com.rocketflow.accounts.UserRepository;
import com.rocketflow.auth.TokenHasher;
import com.rocketflow.common.ApiException;
import com.rocketflow.folders.Folder;
import com.rocketflow.goals.Goal;
import com.rocketflow.goals.GoalRepository;
import com.rocketflow.recurrence.RecurrenceService;
import com.rocketflow.reminders.ReminderService;
import com.rocketflow.sharing.SharingAccessService.FolderAccess;
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

    private static final SecureRandom SHARE_LINK_RANDOM = new SecureRandom();
    private static final int SHARE_LINK_TOKEN_BYTES = 32;

    private final ShareInvitationRepository shareInvitationRepository;
    private final ShareLinkRepository shareLinkRepository;
    private final FolderShareRepository folderShareRepository;
    private final GoalShareRepository goalShareRepository;
    private final TaskShareRepository taskShareRepository;
    private final SharingAccessService sharingAccessService;
    private final UserRepository userRepository;
    private final GoalRepository goalRepository;
    private final TaskRepository taskRepository;
    private final TaskTagRepository taskTagRepository;
    private final TaskTagLinkRepository taskTagLinkRepository;
    private final RecurrenceService recurrenceService;
    private final ReminderService reminderService;
    private final TokenHasher tokenHasher;

    public SharingService(
            ShareInvitationRepository shareInvitationRepository,
            ShareLinkRepository shareLinkRepository,
            FolderShareRepository folderShareRepository,
            GoalShareRepository goalShareRepository,
            TaskShareRepository taskShareRepository,
            SharingAccessService sharingAccessService,
            UserRepository userRepository,
            GoalRepository goalRepository,
            TaskRepository taskRepository,
            TaskTagRepository taskTagRepository,
            TaskTagLinkRepository taskTagLinkRepository,
            RecurrenceService recurrenceService,
            ReminderService reminderService,
            TokenHasher tokenHasher
    ) {
        this.shareInvitationRepository = shareInvitationRepository;
        this.shareLinkRepository = shareLinkRepository;
        this.folderShareRepository = folderShareRepository;
        this.goalShareRepository = goalShareRepository;
        this.taskShareRepository = taskShareRepository;
        this.sharingAccessService = sharingAccessService;
        this.userRepository = userRepository;
        this.goalRepository = goalRepository;
        this.taskRepository = taskRepository;
        this.taskTagRepository = taskTagRepository;
        this.taskTagLinkRepository = taskTagLinkRepository;
        this.recurrenceService = recurrenceService;
        this.reminderService = reminderService;
        this.tokenHasher = tokenHasher;
    }

    @Transactional
    public ShareInvitationDto createFolderInvitation(UUID actorUserId, UUID folderId, ShareRequest request) {
        FolderAccess folderAccess = sharingAccessService.requireFolderOwner(folderId, actorUserId);
        return createInvitation(actorUserId, folderAccess.folder().getOwnerUserId(), TARGET_FOLDER, folderId, request);
    }

    @Transactional
    public ShareInvitationDto createGoalInvitation(UUID actorUserId, UUID goalId, ShareRequest request) {
        GoalAccess goalAccess = sharingAccessService.requireGoalOwner(goalId, actorUserId);
        return createInvitation(actorUserId, goalAccess.goal().getOwnerUserId(), TARGET_GOAL, goalId, request);
    }

    @Transactional
    public ShareInvitationDto createTaskInvitation(UUID actorUserId, UUID taskId, ShareRequest request) {
        TaskAccess taskAccess = sharingAccessService.requireTaskOwner(taskId, actorUserId);
        return createInvitation(actorUserId, taskAccess.task().getOwnerUserId(), TARGET_TASK, taskId, request);
    }

    @Transactional
    public ShareInvitationListResponse listInvitations(UUID actorUserId) {
        refreshExpiredInvitations();
        User actor = requireUser(actorUserId);
        bindLegacyPendingInvitations(actor);
        return new ShareInvitationListResponse(shareInvitationRepository.findVisibleToUser(actorUserId)
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

        bindLegacyPendingInvitationIfEmailMatches(invitation, actor);
        ensureInvitationTarget(invitation, actor);
        ensurePendingInvitation(invitation);

        Instant now = Instant.now();
        if (TARGET_GOAL.equals(invitation.getTargetType())) {
            createGoalShareFromInvitation(invitation, actorUserId, now);
        } else if (TARGET_TASK.equals(invitation.getTargetType())) {
            createTaskShareFromInvitation(invitation, actorUserId, now);
        } else if (TARGET_FOLDER.equals(invitation.getTargetType())) {
            createFolderShareFromInvitation(invitation, actorUserId, now);
        } else {
            throw notFound("Invitation");
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

        bindLegacyPendingInvitationIfEmailMatches(invitation, actor);
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
        folderShareRepository.findByInvitationId(invitationId).ifPresent(share -> revokeFolderShare(share, now));
        goalShareRepository.findByInvitationId(invitationId).ifPresent(share -> revokeGoalShare(share, now));
        taskShareRepository.findByInvitationId(invitationId).ifPresent(share -> revokeTaskShare(share, now));
        markInvitationResolved(invitation, INVITATION_REVOKED, actorUserId, now);
        return new ShareInvitationActionResponse(invitation.getId(), invitation.getStatus());
    }

    @Transactional
    public SharedResourcesResponse listSharedResources(UUID actorUserId) {
        List<FolderShare> folderShares = folderShareRepository.findByCollaboratorUserIdAndStatusOrderByCreatedAtAsc(actorUserId, SHARE_ACTIVE);
        List<GoalShare> goalShares = goalShareRepository.findByCollaboratorUserIdAndStatusOrderByCreatedAtAsc(actorUserId, SHARE_ACTIVE);
        List<TaskShare> taskShares = taskShareRepository.findByCollaboratorUserIdAndStatusOrderByCreatedAtAsc(actorUserId, SHARE_ACTIVE);

        Map<UUID, FolderDto> foldersById = folderShares.stream()
                .map(FolderShare::getFolderId)
                .distinct()
                .map(folderId -> sharingAccessService.requireFolderAccess(folderId, actorUserId).folder())
                .sorted(Comparator.comparing(Folder::getDisplayOrder).thenComparing(Folder::getCreatedAt))
                .collect(Collectors.toMap(
                        Folder::getId,
                        folder -> toFolderDto(folder, true),
                        (left, right) -> left,
                        LinkedHashMap::new
                ));

        Map<UUID, Goal> folderGoalsById = new LinkedHashMap<>();
        for (FolderShare folderShare : folderShares) {
            Folder folder = sharingAccessService.requireFolderAccess(folderShare.getFolderId(), actorUserId).folder();
            goalRepository.findByFolderIdAndOwnerUserIdOrderByCreatedAtAsc(folder.getId(), folder.getOwnerUserId())
                    .forEach(goal -> folderGoalsById.put(goal.getId(), goal));
        }

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
        folderGoalsById.values().stream()
                .sorted(Comparator.comparing(Goal::getCreatedAt))
                .forEach(goal -> goalsById.putIfAbsent(goal.getId(), toGoalDto(goal, true)));

        Map<UUID, Task> tasksById = new LinkedHashMap<>();
        for (Goal goal : folderGoalsById.values()) {
            taskRepository.findByGoalIdAndOwnerUserIdOrderByCreatedAtAsc(goal.getId(), goal.getOwnerUserId())
                    .forEach(task -> tasksById.put(task.getId(), task));
        }
        for (GoalShare goalShare : goalShares) {
            sharingAccessService.requireGoalAccess(goalShare.getGoalId(), actorUserId);
            taskRepository.findByGoalIdAndOwnerUserIdOrderByCreatedAtAsc(goalShare.getGoalId(), goalShare.getOwnerUserId())
                    .forEach(task -> tasksById.put(task.getId(), task));
        }
        for (TaskShare taskShare : taskShares) {
            Task task = sharingAccessService.requireTaskAccess(taskShare.getTaskId(), actorUserId).task();
            tasksById.put(task.getId(), task);
        }

        List<Task> sharedTasks = tasksById.values().stream().sorted(Comparator.comparing(Task::getCreatedAt)).toList();
        List<UUID> sharedTaskIds = sharedTasks.stream().map(Task::getId).toList();
        Map<UUID, RecurrenceDto> recurrenceByTaskId = recurrenceService.findDtos(sharedTaskIds);
        Map<UUID, List<ReminderDto>> remindersByTaskId = reminderService.findDtos(sharedTaskIds);

        List<TaskDto> taskDtos = new ArrayList<>();
        for (Task task : sharedTasks) {
            taskDtos.add(toTaskDto(
                    task,
                    true,
                    recurrenceByTaskId.get(task.getId()),
                    remindersByTaskId.getOrDefault(task.getId(), List.of())
            ));
        }

        return new SharedResourcesResponse(new ArrayList<>(foldersById.values()), new ArrayList<>(goalsById.values()), taskDtos);
    }

    private ShareInvitationDto createInvitation(
            UUID actorUserId,
            UUID ownerUserId,
            String targetType,
            UUID targetId,
            ShareRequest request
    ) {
        refreshExpiredInvitations();
        User actor = requireUser(actorUserId);
        User targetUser = resolveShareTarget(request);
        String normalizedEmail = normalizeEmail(targetUser.getEmail());

        if (targetUser.getId().equals(actorUserId)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "You cannot invite yourself.");
        }
        if (!ownerUserId.equals(actorUserId)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "forbidden", "Only the owner can share this resource.");
        }
        if (shareInvitationRepository.existsByTargetTypeAndTargetIdAndStatusAndTargetUserId(
                targetType,
                targetId,
                INVITATION_PENDING,
                targetUser.getId()
        ) || shareInvitationRepository.existsByTargetTypeAndTargetIdAndStatusAndTargetEmailIgnoreCase(
                targetType,
                targetId,
                INVITATION_PENDING,
                normalizedEmail
        )) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", "An active invitation already exists.");
        }
        if (TARGET_FOLDER.equals(targetType)
                && folderShareRepository.existsByFolderIdAndCollaboratorUserIdAndStatus(targetId, targetUser.getId(), SHARE_ACTIVE)) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", "Access already exists for this folder.");
        }
        if (TARGET_GOAL.equals(targetType)
                && goalShareRepository.existsByGoalIdAndCollaboratorUserIdAndStatus(targetId, targetUser.getId(), SHARE_ACTIVE)) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", "Access already exists for this goal.");
        }
        if (TARGET_TASK.equals(targetType)
                && taskShareRepository.existsByTaskIdAndCollaboratorUserIdAndStatus(targetId, targetUser.getId(), SHARE_ACTIVE)) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", "Access already exists for this task.");
        }

        Instant now = Instant.now();
        ShareInvitation invitation = new ShareInvitation();
        invitation.setId(UUID.randomUUID());
        invitation.setInviterUserId(actorUserId);
        invitation.setTargetType(targetType);
        invitation.setTargetId(targetId);
        invitation.setTargetEmail(normalizedEmail);
        invitation.setTargetUserId(targetUser.getId());
        invitation.setStatus(INVITATION_PENDING);
        invitation.setCreatedAt(now);
        invitation.setUpdatedAt(now);
        invitation.setExpiresAt(now.plus(INVITATION_TTL));
        return toDto(shareInvitationRepository.save(invitation));
    }

    @Transactional
    public ShareLinkCreateResponse createFolderShareLink(UUID actorUserId, UUID folderId, ShareLinkRequest request) {
        FolderAccess folderAccess = sharingAccessService.requireFolderOwner(folderId, actorUserId);
        return createShareLink(actorUserId, TARGET_FOLDER, folderAccess.folder().getId(), request);
    }

    @Transactional
    public ShareLinkCreateResponse createGoalShareLink(UUID actorUserId, UUID goalId, ShareLinkRequest request) {
        GoalAccess goalAccess = sharingAccessService.requireGoalOwner(goalId, actorUserId);
        return createShareLink(actorUserId, TARGET_GOAL, goalAccess.goal().getId(), request);
    }

    @Transactional
    public ShareLinkCreateResponse createTaskShareLink(UUID actorUserId, UUID taskId, ShareLinkRequest request) {
        TaskAccess taskAccess = sharingAccessService.requireTaskOwner(taskId, actorUserId);
        return createShareLink(actorUserId, TARGET_TASK, taskAccess.task().getId(), request);
    }

    @Transactional(readOnly = true)
    public ShareLinkListResponse listFolderShareLinks(UUID actorUserId, UUID folderId) {
        FolderAccess folderAccess = sharingAccessService.requireFolderOwner(folderId, actorUserId);
        return listShareLinks(actorUserId, TARGET_FOLDER, folderAccess.folder().getId());
    }

    @Transactional(readOnly = true)
    public ShareLinkListResponse listGoalShareLinks(UUID actorUserId, UUID goalId) {
        GoalAccess goalAccess = sharingAccessService.requireGoalOwner(goalId, actorUserId);
        return listShareLinks(actorUserId, TARGET_GOAL, goalAccess.goal().getId());
    }

    @Transactional(readOnly = true)
    public ShareLinkListResponse listTaskShareLinks(UUID actorUserId, UUID taskId) {
        TaskAccess taskAccess = sharingAccessService.requireTaskOwner(taskId, actorUserId);
        return listShareLinks(actorUserId, TARGET_TASK, taskAccess.task().getId());
    }

    @Transactional(readOnly = true)
    public ShareLinkResolveResponse resolveShareLink(UUID actorUserId, String token) {
        requireUser(actorUserId);
        ShareLink link = requireUsableShareLink(token);
        return new ShareLinkResolveResponse(link.getId(), link.getTargetType(), link.getTargetId(), link.getStatus(), link.getExpiresAt());
    }

    @Transactional
    public ShareLinkAcceptResponse acceptShareLink(UUID actorUserId, String token) {
        requireUser(actorUserId);
        ShareLink link = requireUsableShareLink(token);
        if (link.getOwnerUserId().equals(actorUserId)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "You cannot accept your own share link.");
        }

        Instant now = Instant.now();
        UUID shareId;
        if (TARGET_FOLDER.equals(link.getTargetType())) {
            FolderAccess folderAccess = sharingAccessService.requireFolderOwner(link.getTargetId(), link.getOwnerUserId());
            shareId = createFolderShare(folderAccess.folder(), actorUserId, null, link.getId(), now).getId();
        } else if (TARGET_GOAL.equals(link.getTargetType())) {
            GoalAccess goalAccess = sharingAccessService.requireGoalOwner(link.getTargetId(), link.getOwnerUserId());
            shareId = createGoalShare(goalAccess.goal(), actorUserId, null, link.getId(), now).getId();
        } else if (TARGET_TASK.equals(link.getTargetType())) {
            TaskAccess taskAccess = sharingAccessService.requireTaskOwner(link.getTargetId(), link.getOwnerUserId());
            shareId = createTaskShare(taskAccess.task(), actorUserId, null, link.getId(), now).getId();
        } else {
            throw notFound("Share link");
        }
        return new ShareLinkAcceptResponse(shareId, link.getTargetType(), link.getTargetId(), SHARE_ACTIVE);
    }

    @Transactional
    public ShareLinkActionResponse revokeShareLink(UUID actorUserId, UUID linkId) {
        ShareLink link = shareLinkRepository.findById(linkId)
                .orElseThrow(() -> notFound("Share link"));
        if (!link.getOwnerUserId().equals(actorUserId)) {
            throw notFound("Share link");
        }
        if (LINK_REVOKED.equals(link.getStatus())) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", "Share link is already revoked.");
        }

        Instant now = Instant.now();
        link.setStatus(LINK_REVOKED);
        link.setUpdatedAt(now);
        link.setRevokedAt(now);
        shareLinkRepository.save(link);
        return new ShareLinkActionResponse(link.getId(), link.getStatus());
    }

    private ShareLinkCreateResponse createShareLink(UUID actorUserId, String targetType, UUID targetId, ShareLinkRequest request) {
        Instant expiresAt = request == null ? null : request.expiresAt();
        if (expiresAt != null && !expiresAt.isAfter(Instant.now())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Share link expiry must be in the future.");
        }

        String token = generateShareLinkToken();
        Instant now = Instant.now();
        ShareLink link = new ShareLink();
        link.setId(UUID.randomUUID());
        link.setOwnerUserId(actorUserId);
        link.setTargetType(targetType);
        link.setTargetId(targetId);
        link.setTokenHash(tokenHasher.hash(token));
        link.setStatus(LINK_ACTIVE);
        link.setCreatedAt(now);
        link.setUpdatedAt(now);
        link.setExpiresAt(expiresAt);
        ShareLink saved = shareLinkRepository.save(link);
        return new ShareLinkCreateResponse(
                saved.getId(),
                saved.getTargetType(),
                saved.getTargetId(),
                token,
                saved.getStatus(),
                saved.getCreatedAt(),
                saved.getExpiresAt()
        );
    }

    private ShareLinkListResponse listShareLinks(UUID actorUserId, String targetType, UUID targetId) {
        return new ShareLinkListResponse(shareLinkRepository.findByOwnerUserIdAndTargetTypeAndTargetIdOrderByCreatedAtDesc(
                        actorUserId,
                        targetType,
                        targetId
                )
                .stream()
                .map(this::toLinkDto)
                .toList());
    }

    private ShareLink requireUsableShareLink(String token) {
        ShareLink link = shareLinkRepository.findByTokenHash(tokenHasher.hash(token))
                .orElseThrow(() -> notFound("Share link"));
        if (!LINK_ACTIVE.equals(link.getStatus())
                || (link.getExpiresAt() != null && !link.getExpiresAt().isAfter(Instant.now()))) {
            throw notFound("Share link");
        }
        return link;
    }

    private String generateShareLinkToken() {
        byte[] bytes = new byte[SHARE_LINK_TOKEN_BYTES];
        SHARE_LINK_RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private void createFolderShareFromInvitation(ShareInvitation invitation, UUID actorUserId, Instant now) {
        FolderAccess folderAccess = sharingAccessService.requireFolderOwner(invitation.getTargetId(), invitation.getInviterUserId());
        createFolderShare(folderAccess.folder(), actorUserId, invitation.getId(), null, now);
    }

    private void createGoalShareFromInvitation(ShareInvitation invitation, UUID actorUserId, Instant now) {
        GoalAccess goalAccess = sharingAccessService.requireGoalOwner(invitation.getTargetId(), invitation.getInviterUserId());
        createGoalShare(goalAccess.goal(), actorUserId, invitation.getId(), null, now);
    }

    private void createTaskShareFromInvitation(ShareInvitation invitation, UUID actorUserId, Instant now) {
        TaskAccess taskAccess = sharingAccessService.requireTaskOwner(invitation.getTargetId(), invitation.getInviterUserId());
        createTaskShare(taskAccess.task(), actorUserId, invitation.getId(), null, now);
    }

    private FolderShare createFolderShare(Folder folder, UUID collaboratorUserId, UUID invitationId, UUID linkId, Instant now) {
        if (folderShareRepository.existsByFolderIdAndCollaboratorUserIdAndStatus(folder.getId(), collaboratorUserId, SHARE_ACTIVE)) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", "Access already exists for this folder.");
        }

        FolderShare share = new FolderShare();
        share.setId(UUID.randomUUID());
        share.setFolderId(folder.getId());
        share.setOwnerUserId(folder.getOwnerUserId());
        share.setCollaboratorUserId(collaboratorUserId);
        share.setInvitationId(invitationId);
        share.setLinkId(linkId);
        share.setStatus(SHARE_ACTIVE);
        share.setCreatedAt(now);
        share.setUpdatedAt(now);
        return folderShareRepository.save(share);
    }

    private GoalShare createGoalShare(Goal goal, UUID collaboratorUserId, UUID invitationId, UUID linkId, Instant now) {
        if (goalShareRepository.existsByGoalIdAndCollaboratorUserIdAndStatus(goal.getId(), collaboratorUserId, SHARE_ACTIVE)) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", "Access already exists for this goal.");
        }

        GoalShare share = new GoalShare();
        share.setId(UUID.randomUUID());
        share.setGoalId(goal.getId());
        share.setOwnerUserId(goal.getOwnerUserId());
        share.setCollaboratorUserId(collaboratorUserId);
        share.setInvitationId(invitationId);
        share.setLinkId(linkId);
        share.setStatus(SHARE_ACTIVE);
        share.setCreatedAt(now);
        share.setUpdatedAt(now);
        return goalShareRepository.save(share);
    }

    private TaskShare createTaskShare(Task task, UUID collaboratorUserId, UUID invitationId, UUID linkId, Instant now) {
        if (taskShareRepository.existsByTaskIdAndCollaboratorUserIdAndStatus(task.getId(), collaboratorUserId, SHARE_ACTIVE)) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", "Access already exists for this task.");
        }

        TaskShare share = new TaskShare();
        share.setId(UUID.randomUUID());
        share.setTaskId(task.getId());
        share.setOwnerUserId(task.getOwnerUserId());
        share.setCollaboratorUserId(collaboratorUserId);
        share.setInvitationId(invitationId);
        share.setLinkId(linkId);
        share.setStatus(SHARE_ACTIVE);
        share.setCreatedAt(now);
        share.setUpdatedAt(now);
        return taskShareRepository.save(share);
    }

    private User resolveShareTarget(ShareRequest request) {
        boolean hasEmail = request.email() != null && !request.email().isBlank();
        boolean hasUserId = request.userId() != null;
        if (hasEmail == hasUserId) {
            throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "validation_error",
                    "Share request requires exactly one of email or userId."
            );
        }

        if (hasUserId) {
            return userRepository.findById(request.userId())
                    .orElseThrow(() -> new ApiException(
                            HttpStatus.BAD_REQUEST,
                            "validation_error",
                            "The invitee must have an existing RocketFlow account before sharing."
                    ));
        }

        return userRepository.findByEmailIgnoreCase(normalizeEmail(request.email()))
                .orElseThrow(() -> new ApiException(
                        HttpStatus.BAD_REQUEST,
                        "validation_error",
                        "The invitee must have an existing RocketFlow account before sharing."
                ));
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
        if (!actor.getId().equals(invitation.getTargetUserId())) {
            throw new ApiException(HttpStatus.FORBIDDEN, "forbidden", "Invitation is not available for this account.");
        }
    }

    private void bindLegacyPendingInvitations(User actor) {
        shareInvitationRepository.findByStatusAndTargetUserIdIsNullAndTargetEmailIgnoreCase(
                        INVITATION_PENDING,
                        actor.getEmail()
                )
                .forEach(invitation -> bindLegacyPendingInvitationIfEmailMatches(invitation, actor));
    }

    private void bindLegacyPendingInvitationIfEmailMatches(ShareInvitation invitation, User actor) {
        if (invitation.getTargetUserId() != null || !INVITATION_PENDING.equals(invitation.getStatus())) {
            return;
        }
        if (!actor.getEmail().equalsIgnoreCase(invitation.getTargetEmail())) {
            return;
        }

        invitation.setTargetUserId(actor.getId());
        invitation.setUpdatedAt(Instant.now());
        shareInvitationRepository.save(invitation);
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

    private void revokeFolderShare(FolderShare share, Instant now) {
        if (!SHARE_REVOKED.equals(share.getStatus())) {
            share.setStatus(SHARE_REVOKED);
            share.setUpdatedAt(now);
            share.setRevokedAt(now);
            folderShareRepository.save(share);
        }
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
                invitation.getTargetUserId(),
                invitation.getStatus(),
                invitation.getCreatedAt(),
                invitation.getExpiresAt()
        );
    }

    private ShareLinkDto toLinkDto(ShareLink link) {
        return new ShareLinkDto(
                link.getId(),
                link.getTargetType(),
                link.getTargetId(),
                link.getStatus(),
                link.getCreatedAt(),
                link.getExpiresAt(),
                link.getRevokedAt()
        );
    }

    private FolderDto toFolderDto(Folder folder, boolean shared) {
        return new FolderDto(
                folder.getId(),
                folder.getName(),
                folder.getDescription(),
                folder.getDisplayOrder(),
                folder.isArchived(),
                shared,
                folder.getVersion(),
                folder.getCreatedAt(),
                folder.getUpdatedAt()
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

    private TaskDto toTaskDto(Task task, boolean shared, RecurrenceDto recurrence, List<ReminderDto> reminders) {
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
                recurrence,
                reminders,
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
