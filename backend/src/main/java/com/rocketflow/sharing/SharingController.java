package com.rocketflow.sharing;

import static com.rocketflow.sharing.SharingApi.*;

import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
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
public class SharingController {

    private final SharingService sharingService;
    private final CurrentUserService currentUserService;

    public SharingController(SharingService sharingService, CurrentUserService currentUserService) {
        this.sharingService = sharingService;
        this.currentUserService = currentUserService;
    }

    @PostMapping("/folders/{folderId}/share")
    @ResponseStatus(HttpStatus.CREATED)
    public ShareInvitationDto shareFolder(@PathVariable String folderId, @Valid @RequestBody ShareRequest request) {
        return sharingService.createFolderInvitation(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(folderId), request);
    }

    @PostMapping("/goals/{goalId}/share")
    @ResponseStatus(HttpStatus.CREATED)
    public ShareInvitationDto shareGoal(@PathVariable String goalId, @Valid @RequestBody ShareRequest request) {
        return sharingService.createGoalInvitation(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(goalId), request);
    }

    @PostMapping("/tasks/{taskId}/share")
    @ResponseStatus(HttpStatus.CREATED)
    public ShareInvitationDto shareTask(@PathVariable String taskId, @Valid @RequestBody ShareRequest request) {
        return sharingService.createTaskInvitation(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(taskId), request);
    }

    @PostMapping("/folders/{folderId}/share-links")
    @ResponseStatus(HttpStatus.CREATED)
    public ShareLinkCreateResponse createFolderShareLink(
            @PathVariable String folderId,
            @Valid @RequestBody(required = false) ShareLinkRequest request
    ) {
        return sharingService.createFolderShareLink(
                currentUserService.requireAuthenticatedUser().userId(),
                UUID.fromString(folderId),
                request
        );
    }

    @GetMapping("/folders/{folderId}/share-links")
    public ShareLinkListResponse listFolderShareLinks(@PathVariable String folderId) {
        return sharingService.listFolderShareLinks(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(folderId));
    }

    @PostMapping("/goals/{goalId}/share-links")
    @ResponseStatus(HttpStatus.CREATED)
    public ShareLinkCreateResponse createGoalShareLink(
            @PathVariable String goalId,
            @Valid @RequestBody(required = false) ShareLinkRequest request
    ) {
        return sharingService.createGoalShareLink(
                currentUserService.requireAuthenticatedUser().userId(),
                UUID.fromString(goalId),
                request
        );
    }

    @GetMapping("/goals/{goalId}/share-links")
    public ShareLinkListResponse listGoalShareLinks(@PathVariable String goalId) {
        return sharingService.listGoalShareLinks(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(goalId));
    }

    @PostMapping("/tasks/{taskId}/share-links")
    @ResponseStatus(HttpStatus.CREATED)
    public ShareLinkCreateResponse createTaskShareLink(
            @PathVariable String taskId,
            @Valid @RequestBody(required = false) ShareLinkRequest request
    ) {
        return sharingService.createTaskShareLink(
                currentUserService.requireAuthenticatedUser().userId(),
                UUID.fromString(taskId),
                request
        );
    }

    @GetMapping("/tasks/{taskId}/share-links")
    public ShareLinkListResponse listTaskShareLinks(@PathVariable String taskId) {
        return sharingService.listTaskShareLinks(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(taskId));
    }

    @GetMapping("/shares/invitations")
    public ShareInvitationListResponse listInvitations() {
        return sharingService.listInvitations(currentUserService.requireAuthenticatedUser().userId());
    }

    @PostMapping("/shares/invitations/{invitationId}/accept")
    public ShareInvitationActionResponse acceptInvitation(@PathVariable String invitationId) {
        return sharingService.acceptInvitation(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(invitationId));
    }

    @PostMapping("/shares/invitations/{invitationId}/decline")
    public ShareInvitationActionResponse declineInvitation(@PathVariable String invitationId) {
        return sharingService.declineInvitation(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(invitationId));
    }

    @PostMapping("/shares/invitations/{invitationId}/revoke")
    public ShareInvitationActionResponse revokeInvitation(@PathVariable String invitationId) {
        return sharingService.revokeInvitation(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(invitationId));
    }

    @GetMapping("/shares/links/{token}")
    public ShareLinkResolveResponse resolveShareLink(@PathVariable String token) {
        return sharingService.resolveShareLink(currentUserService.requireAuthenticatedUser().userId(), token);
    }

    @PostMapping("/shares/links/{token}/accept")
    public ShareLinkAcceptResponse acceptShareLink(@PathVariable String token) {
        return sharingService.acceptShareLink(currentUserService.requireAuthenticatedUser().userId(), token);
    }

    @PostMapping("/shares/links/{linkId}/revoke")
    public ShareLinkActionResponse revokeShareLink(@PathVariable String linkId) {
        return sharingService.revokeShareLink(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(linkId));
    }

    @GetMapping("/shares/resources")
    public SharedResourcesResponse listSharedResources() {
        return sharingService.listSharedResources(currentUserService.requireAuthenticatedUser().userId());
    }
}
