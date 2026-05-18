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

    @PatchMapping("/idea-notes/{noteId}")
    public IdeaNoteDto updateIdeaNote(@PathVariable String noteId, @Valid @RequestBody UpdateIdeaNoteRequest request) {
        return ideaService.updateIdeaNote(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(noteId), request);
    }

    @PostMapping("/ideas/{ideaId}/move")
    public IdeaDto moveIdea(@PathVariable String ideaId, @Valid @RequestBody MoveIdeaRequest request) {
        return ideaService.moveIdea(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(ideaId), request);
    }

    @PostMapping("/ideas/{ideaId}/clone")
    @ResponseStatus(HttpStatus.CREATED)
    public IdeaDto cloneIdea(@PathVariable String ideaId, @Valid @RequestBody CloneIdeaRequest request) {
        return ideaService.cloneIdea(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(ideaId), request);
    }
}
