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

    @GetMapping("/shares/resources")
    public SharedResourcesResponse listSharedResources() {
        return sharingService.listSharedResources(currentUserService.requireAuthenticatedUser().userId());
    }
}
