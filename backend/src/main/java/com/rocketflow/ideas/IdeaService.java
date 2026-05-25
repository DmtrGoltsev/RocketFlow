package com.rocketflow.ideas;

import static com.rocketflow.ideas.IdeasApi.*;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.accounts.UserRepository;
import com.rocketflow.common.ApiException;
import com.rocketflow.links.EntityLinkCleanupService;
import com.rocketflow.links.EntityLinkService;
import com.rocketflow.sharing.SharingAccessService;
import com.rocketflow.sharing.SharingAccessService.FolderAccess;
import com.rocketflow.sharing.SharingAccessService.IdeaAccess;

@Service
public class IdeaService {

    private static final String DEFAULT_IDEA_STATUS = "active";

    private final IdeaRepository ideaRepository;
    private final IdeaNoteRepository ideaNoteRepository;
    private final SharingAccessService sharingAccessService;
    private final UserRepository userRepository;
    private final EntityLinkCleanupService entityLinkCleanupService;

    public IdeaService(
            IdeaRepository ideaRepository,
            IdeaNoteRepository ideaNoteRepository,
            SharingAccessService sharingAccessService,
            UserRepository userRepository,
            EntityLinkCleanupService entityLinkCleanupService
    ) {
        this.ideaRepository = ideaRepository;
        this.ideaNoteRepository = ideaNoteRepository;
        this.sharingAccessService = sharingAccessService;
        this.userRepository = userRepository;
        this.entityLinkCleanupService = entityLinkCleanupService;
    }

    @Transactional(readOnly = true)
    public IdeaListResponse listIdeas(UUID actorUserId, UUID folderId) {
        FolderAccess access = sharingAccessService.requireFolderContentAccess(folderId, actorUserId);
        var ideas = ideaRepository.findByFolderIdAndOwnerUserIdOrderByDisplayOrderAscCreatedAtAsc(
                        folderId,
                        access.folder().getOwnerUserId()
                );
        var sharedIdeaIds = sharingAccessService.findSharedIdeaIds(ideas.stream().map(Idea::getId).toList());
        return new IdeaListResponse(ideas
                .stream()
                .map(idea -> toDto(idea, access.shared() || sharedIdeaIds.contains(idea.getId()), access.fullAccess()))
                .toList());
    }

    @Transactional
    public IdeaDto createIdea(UUID actorUserId, UUID folderId, CreateIdeaRequest request) {
        FolderAccess access = sharingAccessService.requireFolderFullAccess(folderId, actorUserId);
        Instant now = Instant.now();
        Idea idea = new Idea();
        idea.setId(UUID.randomUUID());
        idea.setFolderId(access.folder().getId());
        idea.setOwnerUserId(access.folder().getOwnerUserId());
        idea.setCreatorUserId(actorUserId);
        idea.setTitle(request.title().trim());
        idea.setBody(request.body());
        idea.setStatus(normalizeStatus(request.status()));
        idea.setDisplayOrder((int) ideaRepository.countByFolderIdAndOwnerUserId(folderId, access.folder().getOwnerUserId()) + 1);
        idea.setArchived(false);
        idea.setAllowAuthorNoteEdits(Boolean.TRUE.equals(request.allowAuthorNoteEdits()));
        idea.setCreatedAt(now);
        idea.setUpdatedAt(now);
        return toDto(ideaRepository.save(idea), access.shared(), access.fullAccess());
    }

    @Transactional(readOnly = true)
    public IdeaDto getIdea(UUID actorUserId, UUID ideaId) {
        IdeaAccess access = requireIdeaAccess(ideaId, actorUserId);
        return toDto(access.idea(), access.shared(), access.fullAccess());
    }

    @Transactional
    public IdeaDto updateIdea(UUID actorUserId, UUID ideaId, UpdateIdeaRequest request) {
        IdeaAccess access = requireIdeaFullAccess(ideaId, actorUserId);
        Idea idea = access.idea();
        ensureVersion(idea.getVersion(), request.version(), "Idea");
        ensureIdeaArchiveChangeAllowed(idea, actorUserId, request.archived());
        idea.setTitle(request.title().trim());
        idea.setBody(request.body());
        idea.setStatus(request.status().trim());
        idea.setDisplayOrder(request.displayOrder());
        idea.setArchived(request.archived());
        if (request.allowAuthorNoteEdits() != null) {
            idea.setAllowAuthorNoteEdits(request.allowAuthorNoteEdits());
        }
        idea.setUpdatedAt(Instant.now());
        return toDto(ideaRepository.saveAndFlush(idea), access.shared(), access.fullAccess());
    }

    @Transactional
    public void softDeleteIdea(UUID actorUserId, UUID ideaId) {
        Idea idea = requireIdeaAccess(ideaId, actorUserId).idea();
        if (!idea.getCreatorUserId().equals(actorUserId)) {
            throw notFound("Idea");
        }
        idea.setArchived(true);
        idea.setUpdatedAt(Instant.now());
        ideaRepository.save(idea);
        entityLinkCleanupService.archiveLinksForEntity(EntityLinkService.TYPE_IDEA, idea.getId());
    }

    @Transactional
    public IdeaDto moveIdea(UUID actorUserId, UUID ideaId, MoveIdeaRequest request) {
        IdeaAccess access = requireIdeaFullAccess(ideaId, actorUserId);
        FolderAccess targetAccess = sharingAccessService.requireFolderFullAccess(request.targetFolderId(), actorUserId);
        Idea idea = access.idea();
        ensureVersion(idea.getVersion(), request.version(), "Idea");
        if (!idea.getOwnerUserId().equals(targetAccess.folder().getOwnerUserId())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Idea cannot be moved across owners.");
        }
        idea.setFolderId(targetAccess.folder().getId());
        idea.setUpdatedAt(Instant.now());
        return toDto(ideaRepository.save(idea), targetAccess.shared(), targetAccess.fullAccess());
    }

    @Transactional
    public IdeaDto cloneIdea(UUID actorUserId, UUID ideaId, CloneIdeaRequest request) {
        IdeaAccess sourceAccess = requireIdeaAccess(ideaId, actorUserId);
        FolderAccess targetAccess = sharingAccessService.requireFolderFullAccess(request.targetFolderId(), actorUserId);
        Idea source = sourceAccess.idea();
        if (!source.getOwnerUserId().equals(targetAccess.folder().getOwnerUserId())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Idea cannot be cloned across owners.");
        }
        Instant now = Instant.now();
        Idea clone = new Idea();
        clone.setId(UUID.randomUUID());
        clone.setFolderId(targetAccess.folder().getId());
        clone.setOwnerUserId(source.getOwnerUserId());
        clone.setCreatorUserId(actorUserId);
        clone.setTitle(request.title() == null || request.title().isBlank() ? source.getTitle() : request.title().trim());
        clone.setBody(source.getBody());
        clone.setStatus(source.getStatus());
        clone.setDisplayOrder((int) ideaRepository.countByFolderIdAndOwnerUserId(targetAccess.folder().getId(), source.getOwnerUserId()) + 1);
        clone.setArchived(false);
        clone.setAllowAuthorNoteEdits(source.isAllowAuthorNoteEdits());
        clone.setCreatedAt(now);
        clone.setUpdatedAt(now);
        return toDto(ideaRepository.save(clone), targetAccess.shared(), targetAccess.fullAccess());
    }

    @Transactional(readOnly = true)
    public IdeaNoteListResponse listIdeaNotes(UUID actorUserId, UUID ideaId) {
        Idea idea = requireIdeaAccess(ideaId, actorUserId).idea();
        return new IdeaNoteListResponse(ideaNoteRepository.findByIdeaIdAndOwnerUserIdOrderByCreatedAtAsc(ideaId, idea.getOwnerUserId())
                .stream()
                .map(this::toDto)
                .toList());
    }

    @Transactional
    public IdeaNoteDto createIdeaNote(UUID actorUserId, UUID ideaId, CreateIdeaNoteRequest request) {
        Idea idea = requireIdeaAccess(ideaId, actorUserId).idea();
        IdeaNote note = new IdeaNote();
        note.setId(UUID.randomUUID());
        note.setIdeaId(idea.getId());
        note.setOwnerUserId(idea.getOwnerUserId());
        note.setAuthorUserId(actorUserId);
        note.setEventType(request.eventType().trim());
        note.setBody(request.body());
        note.setMetadata(copyMetadata(request.metadata()));
        Instant now = Instant.now();
        note.setCreatedAt(now);
        note.setUpdatedAt(now);
        return toDto(ideaNoteRepository.save(note));
    }

    @Transactional
    public IdeaNoteDto updateIdeaNote(UUID actorUserId, UUID noteId, UpdateIdeaNoteRequest request) {
        IdeaNoteAccess access = requireIdeaNoteAccess(noteId, actorUserId);
        IdeaNote note = access.note();
        if (!canEditIdeaNote(note, actorUserId)) {
            throw notFound("Idea note");
        }
        ensureVersion(note.getVersion(), request.version(), "Idea note");
        note.setEventType(request.eventType().trim());
        note.setBody(request.body());
        note.setMetadata(copyMetadata(request.metadata()));
        note.setUpdatedAt(Instant.now());
        return toDto(ideaNoteRepository.saveAndFlush(note));
    }

    @Transactional
    public void deleteIdeaNote(UUID actorUserId, UUID noteId) {
        IdeaNoteAccess access = requireIdeaNoteAccess(noteId, actorUserId);
        if (!canDeleteIdeaNote(access.ideaAccess().idea(), actorUserId)) {
            throw notFound("Idea note");
        }
        ideaNoteRepository.delete(access.note());
    }

    @Transactional(readOnly = true)
    public IdeaAccess requireIdeaAccess(UUID ideaId, UUID actorUserId) {
        return sharingAccessService.requireIdeaAccess(ideaId, actorUserId);
    }

    @Transactional(readOnly = true)
    public IdeaAccess requireIdeaFullAccess(UUID ideaId, UUID actorUserId) {
        return sharingAccessService.requireIdeaFullAccess(ideaId, actorUserId);
    }

    @Transactional(readOnly = true)
    public IdeaNoteAccess requireIdeaNoteAccess(UUID noteId, UUID actorUserId) {
        IdeaNote note = ideaNoteRepository.findById(noteId)
                .orElseThrow(() -> notFound("Idea note"));
        IdeaAccess access = requireIdeaAccess(note.getIdeaId(), actorUserId);
        if (!note.getOwnerUserId().equals(access.idea().getOwnerUserId())) {
            throw notFound("Idea note");
        }
        return new IdeaNoteAccess(note, access);
    }

    public IdeaDto toDto(Idea idea, boolean shared, boolean fullAccess) {
        AuthorDetails creator = authorDetails(idea.getCreatorUserId());
        return new IdeaDto(
                idea.getId(),
                idea.getFolderId(),
                idea.getTitle(),
                idea.getBody(),
                idea.getStatus(),
                idea.getDisplayOrder(),
                idea.isArchived(),
                idea.isAllowAuthorNoteEdits(),
                shared,
                fullAccess,
                idea.getCreatorUserId(),
                creator.email(),
                creator.name(),
                idea.getVersion(),
                idea.getCreatedAt(),
                idea.getUpdatedAt()
        );
    }

    private IdeaNoteDto toDto(IdeaNote note) {
        AuthorDetails author = authorDetails(note.getAuthorUserId());
        return new IdeaNoteDto(
                note.getId(),
                note.getIdeaId(),
                note.getEventType(),
                note.getBody(),
                note.getMetadata(),
                note.getAuthorUserId(),
                author.email(),
                author.name(),
                note.getVersion(),
                note.getCreatedAt(),
                note.getUpdatedAt()
        );
    }

    private String normalizeStatus(String status) {
        if (status == null || status.isBlank()) {
            return DEFAULT_IDEA_STATUS;
        }
        return status.trim();
    }

    private Map<String, Object> copyMetadata(Map<String, Object> metadata) {
        if (metadata == null || metadata.isEmpty()) {
            return new LinkedHashMap<>();
        }
        return new LinkedHashMap<>(metadata);
    }

    private AuthorDetails authorDetails(UUID authorUserId) {
        return userRepository.findById(authorUserId)
                .map(user -> new AuthorDetails(user.getEmail(), user.getDisplayName()))
                .orElse(new AuthorDetails(null, null));
    }

    private void ensureVersion(long actual, long expected, String entityName) {
        if (actual != expected) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", entityName + " was updated by another request.");
        }
    }

    private boolean canEditIdeaNote(IdeaNote note, UUID actorUserId) {
        return note.getAuthorUserId().equals(actorUserId);
    }

    private boolean canDeleteIdeaNote(Idea idea, UUID actorUserId) {
        return idea.getCreatorUserId().equals(actorUserId);
    }

    private void ensureIdeaArchiveChangeAllowed(Idea idea, UUID actorUserId, boolean requestedArchived) {
        if (idea.isArchived() != requestedArchived && !idea.getCreatorUserId().equals(actorUserId)) {
            throw notFound("Idea");
        }
    }

    private ApiException notFound(String entityName) {
        return new ApiException(HttpStatus.NOT_FOUND, "not_found", entityName + " was not found.");
    }

    public record IdeaNoteAccess(IdeaNote note, IdeaAccess ideaAccess) {
    }

    private record AuthorDetails(String email, String name) {
    }
}
