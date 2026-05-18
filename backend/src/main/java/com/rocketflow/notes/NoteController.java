package com.rocketflow.notes;

import static com.rocketflow.notes.NotesApi.*;

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
public class NoteController {

    private final NoteService noteService;
    private final CurrentUserService currentUserService;

    public NoteController(NoteService noteService, CurrentUserService currentUserService) {
        this.noteService = noteService;
        this.currentUserService = currentUserService;
    }

    @GetMapping("/folders/{folderId}/notes")
    public NoteListResponse list(@PathVariable String folderId) {
        return noteService.list(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(folderId));
    }

    @PostMapping("/folders/{folderId}/notes")
    @ResponseStatus(HttpStatus.CREATED)
    public NoteDto create(@PathVariable String folderId, @Valid @RequestBody CreateNoteRequest request) {
        return noteService.create(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(folderId), request);
    }

    @GetMapping("/notes/{noteId}")
    public NoteDto get(@PathVariable String noteId) {
        return noteService.get(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(noteId));
    }

    @PatchMapping("/notes/{noteId}")
    public NoteDto update(@PathVariable String noteId, @Valid @RequestBody UpdateNoteRequest request) {
        return noteService.update(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(noteId), request);
    }

    @DeleteMapping("/notes/{noteId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable String noteId) {
        noteService.softDelete(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(noteId));
    }

    @PostMapping("/notes/{noteId}/move")
    public NoteDto move(@PathVariable String noteId, @Valid @RequestBody MoveNoteRequest request) {
        return noteService.move(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(noteId), request);
    }

    @PostMapping("/notes/{noteId}/clone")
    @ResponseStatus(HttpStatus.CREATED)
    public NoteDto clone(@PathVariable String noteId, @Valid @RequestBody CloneNoteRequest request) {
        return noteService.clone(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(noteId), request);
    }
}
