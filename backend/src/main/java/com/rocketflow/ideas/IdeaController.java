package com.rocketflow.ideas;

import static com.rocketflow.ideas.IdeasApi.*;

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
@RequestMapping("/api")
public class IdeaController {

    private final IdeaService ideaService;
    private final CurrentUserService currentUserService;

    public IdeaController(IdeaService ideaService, CurrentUserService currentUserService) {
        this.ideaService = ideaService;
        this.currentUserService = currentUserService;
    }

    @GetMapping("/folders/{folderId}/ideas")
    public IdeaListResponse listIdeas(@PathVariable String folderId) {
        return ideaService.listIdeas(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(folderId));
    }

    @PostMapping("/folders/{folderId}/ideas")
    @ResponseStatus(HttpStatus.CREATED)
    public IdeaDto createIdea(@PathVariable String folderId, @Valid @RequestBody CreateIdeaRequest request) {
        return ideaService.createIdea(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(folderId), request);
    }

    @GetMapping("/ideas/{ideaId}")
    public IdeaDto getIdea(@PathVariable String ideaId) {
        return ideaService.getIdea(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(ideaId));
    }

    @PatchMapping("/ideas/{ideaId}")
    public IdeaDto updateIdea(@PathVariable String ideaId, @Valid @RequestBody UpdateIdeaRequest request) {
        return ideaService.updateIdea(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(ideaId), request);
    }

    @DeleteMapping("/ideas/{ideaId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteIdea(@PathVariable String ideaId) {
        ideaService.softDeleteIdea(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(ideaId));
    }

    @GetMapping("/ideas/{ideaId}/notes")
    public IdeaNoteListResponse listIdeaNotes(@PathVariable String ideaId) {
        return ideaService.listIdeaNotes(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(ideaId));
    }

    @PostMapping("/ideas/{ideaId}/notes")
    @ResponseStatus(HttpStatus.CREATED)
    public IdeaNoteDto createIdeaNote(@PathVariable String ideaId, @Valid @RequestBody CreateIdeaNoteRequest request) {
        return ideaService.createIdeaNote(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(ideaId), request);
    }

    @GetMapping("/folders/{folderId}/notes")
    public FolderNoteListResponse listFolderNotes(@PathVariable String folderId) {
        return ideaService.listFolderNotes(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(folderId));
    }

    @PostMapping("/folders/{folderId}/notes")
    @ResponseStatus(HttpStatus.CREATED)
    public FolderNoteDto createFolderNote(@PathVariable String folderId, @Valid @RequestBody CreateFolderNoteRequest request) {
        return ideaService.createFolderNote(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(folderId), request);
    }

    @PatchMapping("/folder-notes/{noteId}")
    public FolderNoteDto updateFolderNote(@PathVariable String noteId, @Valid @RequestBody UpdateFolderNoteRequest request) {
        return ideaService.updateFolderNote(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(noteId), request);
    }

    @DeleteMapping("/folder-notes/{noteId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteFolderNote(@PathVariable String noteId) {
        ideaService.softDeleteFolderNote(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(noteId));
    }

    @PostMapping("/folder-notes/{noteId}/items")
    @ResponseStatus(HttpStatus.CREATED)
    public FolderNoteItemDto createFolderNoteItem(@PathVariable String noteId, @Valid @RequestBody CreateFolderNoteItemRequest request) {
        return ideaService.createFolderNoteItem(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(noteId), request);
    }

    @PatchMapping("/folder-note-items/{itemId}")
    public FolderNoteItemDto updateFolderNoteItem(@PathVariable String itemId, @Valid @RequestBody UpdateFolderNoteItemRequest request) {
        return ideaService.updateFolderNoteItem(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(itemId), request);
    }

    @DeleteMapping("/folder-note-items/{itemId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteFolderNoteItem(@PathVariable String itemId) {
        ideaService.deleteFolderNoteItem(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(itemId));
    }
}
