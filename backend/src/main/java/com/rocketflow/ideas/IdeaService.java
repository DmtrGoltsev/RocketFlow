package com.rocketflow.ideas;

import static com.rocketflow.ideas.IdeasApi.*;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.accounts.UserRepository;
import com.rocketflow.common.ApiException;
import com.rocketflow.sharing.SharingAccessService;
import com.rocketflow.sharing.SharingAccessService.FolderAccess;

@Service
public class IdeaService {

    private static final String DEFAULT_IDEA_STATUS = "active";
    private static final String FOLDER_NOTE_KIND_LIST = "list";

    private final IdeaRepository ideaRepository;
    private final IdeaNoteRepository ideaNoteRepository;
    private final FolderNoteRepository folderNoteRepository;
    private final FolderNoteItemRepository folderNoteItemRepository;
    private final SharingAccessService sharingAccessService;
    private final UserRepository userRepository;

    public IdeaService(
            IdeaRepository ideaRepository,
            IdeaNoteRepository ideaNoteRepository,
            FolderNoteRepository folderNoteRepository,
            FolderNoteItemRepository folderNoteItemRepository,
            SharingAccessService sharingAccessService,
            UserRepository userRepository
    ) {
        this.ideaRepository = ideaRepository;
        this.ideaNoteRepository = ideaNoteRepository;
        this.folderNoteRepository = folderNoteRepository;
        this.folderNoteItemRepository = folderNoteItemRepository;
        this.sharingAccessService = sharingAccessService;
        this.userRepository = userRepository;
    }

    @Transactional(readOnly = true)
    public IdeaListResponse listIdeas(UUID actorUserId, UUID folderId) {
        FolderAccess access = sharingAccessService.requireFolderContentAccess(folderId, actorUserId);
        return new IdeaListResponse(ideaRepository.findByFolderIdAndOwnerUserIdOrderByDisplayOrderAscCreatedAtAsc(
                        folderId,
                        access.folder().getOwnerUserId()
                )
                .stream()
                .map(idea -> toDto(idea, access.shared()))
                .toList());
    }

    @Transactional
    public IdeaDto createIdea(UUID actorUserId, UUID folderId, CreateIdeaRequest request) {
        FolderAccess access = sharingAccessService.requireFolderContentAccess(folderId, actorUserId);
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
        idea.setCreatedAt(now);
        idea.setUpdatedAt(now);
        return toDto(ideaRepository.save(idea), access.shared());
    }

    @Transactional(readOnly = true)
    public IdeaDto getIdea(UUID actorUserId, UUID ideaId) {
        IdeaAccess access = requireIdeaAccess(ideaId, actorUserId);
        return toDto(access.idea(), access.folderAccess().shared());
    }

    @Transactional
    public IdeaDto updateIdea(UUID actorUserId, UUID ideaId, UpdateIdeaRequest request) {
        Idea idea = requireIdeaOwner(ideaId, actorUserId);
        ensureVersion(idea.getVersion(), request.version(), "Idea");
        idea.setTitle(request.title().trim());
        idea.setBody(request.body());
        idea.setStatus(request.status().trim());
        idea.setDisplayOrder(request.displayOrder());
        idea.setArchived(request.archived());
        idea.setUpdatedAt(Instant.now());
        FolderAccess folderAccess = sharingAccessService.requireFolderContentOwner(idea.getFolderId(), actorUserId);
        return toDto(ideaRepository.save(idea), folderAccess.shared());
    }

    @Transactional
    public void softDeleteIdea(UUID actorUserId, UUID ideaId) {
        Idea idea = requireIdeaOwner(ideaId, actorUserId);
        idea.setArchived(true);
        idea.setUpdatedAt(Instant.now());
        ideaRepository.save(idea);
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
        note.setCreatedAt(Instant.now());
        return toDto(ideaNoteRepository.save(note));
    }

    @Transactional(readOnly = true)
    public FolderNoteListResponse listFolderNotes(UUID actorUserId, UUID folderId) {
        FolderAccess access = sharingAccessService.requireFolderContentAccess(folderId, actorUserId);
        List<FolderNote> notes = folderNoteRepository.findByFolderIdAndOwnerUserIdOrderByDisplayOrderAscCreatedAtAsc(
                folderId,
                access.folder().getOwnerUserId()
        );
        Map<UUID, List<FolderNoteItemDto>> itemsByNoteId = resolveItems(notes.stream().map(FolderNote::getId).toList());
        return new FolderNoteListResponse(notes.stream()
                .map(note -> toDto(note, access.shared(), itemsByNoteId.getOrDefault(note.getId(), List.of())))
                .toList());
    }

    @Transactional
    public FolderNoteDto createFolderNote(UUID actorUserId, UUID folderId, CreateFolderNoteRequest request) {
        FolderAccess access = sharingAccessService.requireFolderContentAccess(folderId, actorUserId);
        Instant now = Instant.now();
        FolderNote note = new FolderNote();
        note.setId(UUID.randomUUID());
        note.setFolderId(access.folder().getId());
        note.setOwnerUserId(access.folder().getOwnerUserId());
        note.setAuthorUserId(actorUserId);
        note.setKind(request.kind());
        note.setTitle(request.title().trim());
        note.setBody(request.body());
        note.setDisplayOrder((int) folderNoteRepository.countByFolderIdAndOwnerUserId(folderId, access.folder().getOwnerUserId()) + 1);
        note.setArchived(false);
        note.setCreatedAt(now);
        note.setUpdatedAt(now);
        return toDto(folderNoteRepository.save(note), access.shared(), List.of());
    }

    @Transactional
    public FolderNoteDto updateFolderNote(UUID actorUserId, UUID noteId, UpdateFolderNoteRequest request) {
        FolderNote note = requireFolderNoteOwner(noteId, actorUserId);
        ensureVersion(note.getVersion(), request.version(), "Folder note");
        note.setTitle(request.title().trim());
        note.setBody(request.body());
        note.setDisplayOrder(request.displayOrder());
        note.setArchived(request.archived());
        note.setUpdatedAt(Instant.now());
        FolderAccess access = sharingAccessService.requireFolderContentOwner(note.getFolderId(), actorUserId);
        FolderNote saved = folderNoteRepository.save(note);
        return toDto(saved, access.shared(), resolveItems(saved.getId()));
    }

    @Transactional
    public void softDeleteFolderNote(UUID actorUserId, UUID noteId) {
        FolderNote note = requireFolderNoteOwner(noteId, actorUserId);
        note.setArchived(true);
        note.setUpdatedAt(Instant.now());
        folderNoteRepository.save(note);
    }

    @Transactional
    public FolderNoteItemDto createFolderNoteItem(UUID actorUserId, UUID noteId, CreateFolderNoteItemRequest request) {
        FolderNoteAccess access = requireFolderNoteAccess(noteId, actorUserId);
        ensureListNote(access.note());
        Instant now = Instant.now();
        FolderNoteItem item = new FolderNoteItem();
        item.setId(UUID.randomUUID());
        item.setFolderNoteId(access.note().getId());
        item.setText(request.text().trim());
        item.setChecked(Boolean.TRUE.equals(request.checked()));
        item.setDisplayOrder((int) folderNoteItemRepository.countByFolderNoteId(noteId) + 1);
        item.setCreatedAt(now);
        item.setUpdatedAt(now);
        return toDto(folderNoteItemRepository.save(item));
    }

    @Transactional
    public FolderNoteItemDto updateFolderNoteItem(UUID actorUserId, UUID itemId, UpdateFolderNoteItemRequest request) {
        FolderNoteItem item = folderNoteItemRepository.findById(itemId)
                .orElseThrow(() -> notFound("Folder note item"));
        FolderNoteAccess access = requireFolderNoteAccess(item.getFolderNoteId(), actorUserId);
        ensureListNote(access.note());
        ensureVersion(item.getVersion(), request.version(), "Folder note item");
        item.setText(request.text().trim());
        item.setChecked(request.checked());
        item.setDisplayOrder(request.displayOrder());
        item.setUpdatedAt(Instant.now());
        return toDto(folderNoteItemRepository.save(item));
    }

    @Transactional
    public void deleteFolderNoteItem(UUID actorUserId, UUID itemId) {
        FolderNoteItem item = folderNoteItemRepository.findById(itemId)
                .orElseThrow(() -> notFound("Folder note item"));
        FolderNoteAccess access = requireFolderNoteAccess(item.getFolderNoteId(), actorUserId);
        ensureListNote(access.note());
        folderNoteItemRepository.delete(item);
    }

    private IdeaAccess requireIdeaAccess(UUID ideaId, UUID actorUserId) {
        Idea idea = ideaRepository.findById(ideaId).orElseThrow(() -> notFound("Idea"));
        FolderAccess folderAccess = sharingAccessService.requireFolderContentAccess(idea.getFolderId(), actorUserId);
        if (!idea.getOwnerUserId().equals(folderAccess.folder().getOwnerUserId())) {
            throw notFound("Idea");
        }
        return new IdeaAccess(idea, folderAccess);
    }

    private Idea requireIdeaOwner(UUID ideaId, UUID actorUserId) {
        Idea idea = ideaRepository.findById(ideaId).orElseThrow(() -> notFound("Idea"));
        if (!idea.getOwnerUserId().equals(actorUserId)) {
            throw notFound("Idea");
        }
        return idea;
    }

    private FolderNoteAccess requireFolderNoteAccess(UUID noteId, UUID actorUserId) {
        FolderNote note = folderNoteRepository.findById(noteId).orElseThrow(() -> notFound("Folder note"));
        FolderAccess folderAccess = sharingAccessService.requireFolderContentAccess(note.getFolderId(), actorUserId);
        if (!note.getOwnerUserId().equals(folderAccess.folder().getOwnerUserId())) {
            throw notFound("Folder note");
        }
        return new FolderNoteAccess(note, folderAccess);
    }

    private FolderNote requireFolderNoteOwner(UUID noteId, UUID actorUserId) {
        FolderNote note = folderNoteRepository.findById(noteId).orElseThrow(() -> notFound("Folder note"));
        if (!note.getOwnerUserId().equals(actorUserId)) {
            throw notFound("Folder note");
        }
        return note;
    }

    private String normalizeStatus(String status) {
        if (status == null || status.isBlank()) {
            return DEFAULT_IDEA_STATUS;
        }
        return status.trim();
    }

    private void ensureListNote(FolderNote note) {
        if (!FOLDER_NOTE_KIND_LIST.equals(note.getKind())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Folder note items can only be added to lists.");
        }
    }

    private Map<String, Object> copyMetadata(Map<String, Object> metadata) {
        if (metadata == null || metadata.isEmpty()) {
            return new LinkedHashMap<>();
        }
        return new LinkedHashMap<>(metadata);
    }

    private Map<UUID, List<FolderNoteItemDto>> resolveItems(List<UUID> noteIds) {
        if (noteIds.isEmpty()) {
            return Map.of();
        }
        Map<UUID, List<FolderNoteItemDto>> result = new LinkedHashMap<>();
        for (FolderNoteItem item : folderNoteItemRepository.findByFolderNoteIdInOrderByDisplayOrderAscCreatedAtAsc(noteIds)) {
            result.computeIfAbsent(item.getFolderNoteId(), ignored -> new ArrayList<>()).add(toDto(item));
        }
        return result;
    }

    private List<FolderNoteItemDto> resolveItems(UUID noteId) {
        return folderNoteItemRepository.findByFolderNoteIdOrderByDisplayOrderAscCreatedAtAsc(noteId)
                .stream()
                .map(this::toDto)
                .toList();
    }

    private IdeaDto toDto(Idea idea, boolean shared) {
        AuthorDetails creator = authorDetails(idea.getCreatorUserId());
        return new IdeaDto(
                idea.getId(),
                idea.getFolderId(),
                idea.getTitle(),
                idea.getBody(),
                idea.getStatus(),
                idea.getDisplayOrder(),
                idea.isArchived(),
                shared,
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
                note.getCreatedAt()
        );
    }

    private FolderNoteDto toDto(FolderNote note, boolean shared, List<FolderNoteItemDto> items) {
        AuthorDetails author = authorDetails(note.getAuthorUserId());
        return new FolderNoteDto(
                note.getId(),
                note.getFolderId(),
                note.getKind(),
                note.getTitle(),
                note.getBody(),
                note.getDisplayOrder(),
                note.isArchived(),
                shared,
                note.getAuthorUserId(),
                author.email(),
                author.name(),
                note.getVersion(),
                items,
                note.getCreatedAt(),
                note.getUpdatedAt()
        );
    }

    private FolderNoteItemDto toDto(FolderNoteItem item) {
        return new FolderNoteItemDto(
                item.getId(),
                item.getFolderNoteId(),
                item.getText(),
                item.isChecked(),
                item.getDisplayOrder(),
                item.getVersion(),
                item.getCreatedAt(),
                item.getUpdatedAt()
        );
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

    private ApiException notFound(String entityName) {
        return new ApiException(HttpStatus.NOT_FOUND, "not_found", entityName + " was not found.");
    }

    private record IdeaAccess(Idea idea, FolderAccess folderAccess) {
    }

    private record FolderNoteAccess(FolderNote note, FolderAccess folderAccess) {
    }

    private record AuthorDetails(String email, String name) {
    }
}
