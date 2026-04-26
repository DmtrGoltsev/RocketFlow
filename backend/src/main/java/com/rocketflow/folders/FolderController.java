package com.rocketflow.folders;

import static com.rocketflow.folders.FoldersApi.*;

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
@RequestMapping("/api/folders")
public class FolderController {

    private final FolderService folderService;
    private final CurrentUserService currentUserService;

    public FolderController(FolderService folderService, CurrentUserService currentUserService) {
        this.folderService = folderService;
        this.currentUserService = currentUserService;
    }

    @GetMapping
    public FolderListResponse list() {
        return folderService.list(currentUserService.requireAuthenticatedUser().userId());
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public FolderDto create(@Valid @RequestBody CreateFolderRequest request) {
        return folderService.create(currentUserService.requireAuthenticatedUser().userId(), request);
    }

    @PatchMapping("/{folderId}")
    public FolderDto update(@PathVariable String folderId, @Valid @RequestBody UpdateFolderRequest request) {
        return folderService.update(currentUserService.requireAuthenticatedUser().userId(), java.util.UUID.fromString(folderId), request);
    }

    @DeleteMapping("/{folderId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable String folderId) {
        folderService.softDelete(currentUserService.requireAuthenticatedUser().userId(), java.util.UUID.fromString(folderId));
    }
}
