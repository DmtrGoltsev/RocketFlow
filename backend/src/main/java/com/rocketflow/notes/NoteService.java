package com.rocketflow.notes;

import static com.rocketflow.notes.NotesApi.*;

import java.time.Instant;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.accounts.UserRepository;
import com.rocketflow.common.ApiException;
import com.rocketflow.sharing.SharingAccessService;
import com.rocketflow.sharing.SharingAccessService.FolderAccess;

@Service
public class NoteService {

    private final NoteRepository noteRepository;
    private final SharingAccessService sharingAccessService;
    private final UserRepository userRepository;

    public NoteService(NoteRepository noteRepository, SharingAccessService sharingAccessService, UserRepository userRepository) {
        this.noteRepository = noteRepository;
        this.sharingAccessService = sharingAccessService;
        this.userRepository = userRepository;
    }

    @Transactional(readOnly = true)
    public NoteListResponse list(UUID actorUserId, UUID folderId) {
        FolderAccess access = sharingAccessService.requireFolderContentAccess(folderId, actorUserId);
        return new NoteListResponse(noteRepository.findByFolderIdAndOwnerUserIdOrderByDisplayOrderAscCreatedAtAsc(
                        folderId,
                        access.folder().getOwnerUserId()
                )
                .stream()
                .map(note -> toDto(note, access.shared(), access.fullAccess()))
                .toList());
    }

    @Transactional
    public NoteDto create(UUID actorUserId, UUID folderId, CreateNoteRequest request) {
        FolderAccess access = sharingAccessService.requireFolderFullAccess(folderId, actorUserId);
        Instant now = Instant.now();
        Note note = new Note();
        note.setId(UUID.randomUUID());
        note.setFolderId(access.folder().getId());
        note.setOwnerUserId(access.folder().getOwnerUserId());
        note.setAuthorUserId(actorUserId);
        note.setTitle(request.title().trim());
        note.setBody(request.body());
        note.setDisplayOrder((int) noteRepository.countByFolderIdAndOwnerUserId(folderId, access.folder().getOwnerUserId()) + 1);
        note.setArchived(false);
        note.setCreatedAt(now);
        note.setUpdatedAt(now);
        return toDto(noteRepository.save(note), access.shared(), access.fullAccess());
    }

    @Transactional(readOnly = true)
    public NoteDto get(UUID actorUserId, UUID noteId) {
        NoteAccess access = requireNoteAccess(noteId, actorUserId);
        return toDto(access.note(), access.folderAccess().shared(), access.folderAccess().fullAccess());
    }

    @Transactional
    public NoteDto update(UUID actorUserId, UUID noteId, UpdateNoteRequest request) {
        NoteAccess access = requireNoteFullAccess(noteId, actorUserId);
        Note note = access.note();
        ensureVersion(note.getVersion(), request.version(), "Note");
        note.setTitle(request.title().trim());
        note.setBody(request.body());
        note.setDisplayOrder(request.displayOrder());
        note.setArchived(request.archived());
        note.setUpdatedAt(Instant.now());
        return toDto(noteRepository.save(note), access.folderAccess().shared(), access.folderAccess().fullAccess());
    }

    @Transactional
    public void softDelete(UUID actorUserId, UUID noteId) {
        NoteAccess access = requireNoteFullAccess(noteId, actorUserId);
        access.note().setArchived(true);
        access.note().setUpdatedAt(Instant.now());
        noteRepository.save(access.note());
    }

    @Transactional
    public NoteDto move(UUID actorUserId, UUID noteId, MoveNoteRequest request) {
        NoteAccess access = requireNoteFullAccess(noteId, actorUserId);
        FolderAccess targetAccess = sharingAccessService.requireFolderFullAccess(request.targetFolderId(), actorUserId);
        Note note = access.note();
        ensureVersion(note.getVersion(), request.version(), "Note");
        if (!note.getOwnerUserId().equals(targetAccess.folder().getOwnerUserId())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Note cannot be moved across owners.");
        }
        note.setFolderId(targetAccess.folder().getId());
        note.setUpdatedAt(Instant.now());
        return toDto(noteRepository.save(note), targetAccess.shared(), targetAccess.fullAccess());
    }

    @Transactional
    public NoteDto clone(UUID actorUserId, UUID noteId, CloneNoteRequest request) {
        NoteAccess sourceAccess = requireNoteAccess(noteId, actorUserId);
        FolderAccess targetAccess = sharingAccessService.requireFolderFullAccess(request.targetFolderId(), actorUserId);
        Note source = sourceAccess.note();
        if (!source.getOwnerUserId().equals(targetAccess.folder().getOwnerUserId())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Note cannot be cloned across owners.");
        }
        Instant now = Instant.now();
        Note clone = new Note();
        clone.setId(UUID.randomUUID());
        clone.setFolderId(targetAccess.folder().getId());
        clone.setOwnerUserId(source.getOwnerUserId());
        clone.setAuthorUserId(actorUserId);
        clone.setTitle(request.title() == null || request.title().isBlank() ? source.getTitle() : request.title().trim());
        clone.setBody(source.getBody());
        clone.setDisplayOrder((int) noteRepository.countByFolderIdAndOwnerUserId(targetAccess.folder().getId(), source.getOwnerUserId()) + 1);
        clone.setArchived(false);
        clone.setCreatedAt(now);
        clone.setUpdatedAt(now);
        return toDto(noteRepository.save(clone), targetAccess.shared(), targetAccess.fullAccess());
    }

    @Transactional(readOnly = true)
    public NoteAccess requireNoteAccess(UUID noteId, UUID actorUserId) {
        Note note = noteRepository.findById(noteId).orElseThrow(() -> notFound("Note"));
        FolderAccess folderAccess = sharingAccessService.requireFolderContentAccess(note.getFolderId(), actorUserId);
        if (!note.getOwnerUserId().equals(folderAccess.folder().getOwnerUserId())) {
            throw notFound("Note");
        }
        return new NoteAccess(note, folderAccess);
    }

    @Transactional(readOnly = true)
    public NoteAccess requireNoteFullAccess(UUID noteId, UUID actorUserId) {
        NoteAccess access = requireNoteAccess(noteId, actorUserId);
        if (!access.folderAccess().fullAccess()) {
            throw notFound("Note");
        }
        return access;
    }

    public NoteDto toDto(Note note, boolean shared, boolean fullAccess) {
        AuthorDetails author = authorDetails(note.getAuthorUserId());
        return new NoteDto(
                note.getId(),
                note.getFolderId(),
                note.getTitle(),
                note.getBody(),
                note.getDisplayOrder(),
                note.isArchived(),
                shared,
                fullAccess,
                note.getAuthorUserId(),
                author.email(),
                author.name(),
                note.getVersion(),
                note.getCreatedAt(),
                note.getUpdatedAt()
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

    public record NoteAccess(Note note, FolderAccess folderAccess) {
    }

    private record AuthorDetails(String email, String name) {
    }
}
