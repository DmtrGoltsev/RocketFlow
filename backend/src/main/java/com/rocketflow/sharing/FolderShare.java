package com.rocketflow.sharing;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "folder_shares")
public class FolderShare {

    @Id
    private UUID id;

    @Column(name = "folder_id", nullable = false)
    private UUID folderId;

    @Column(name = "owner_user_id", nullable = false)
    private UUID ownerUserId;

    @Column(name = "collaborator_user_id", nullable = false)
    private UUID collaboratorUserId;

    @Column(name = "invitation_id")
    private UUID invitationId;

    @Column(name = "link_id")
    private UUID linkId;

    @Column(nullable = false, length = 16)
    private String status;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Column(name = "revoked_at")
    private Instant revokedAt;

    public UUID getId() {
        return id;
    }

    public void setId(UUID id) {
        this.id = id;
    }

    public UUID getFolderId() {
        return folderId;
    }

    public void setFolderId(UUID folderId) {
        this.folderId = folderId;
    }

    public UUID getOwnerUserId() {
        return ownerUserId;
    }

    public void setOwnerUserId(UUID ownerUserId) {
        this.ownerUserId = ownerUserId;
    }

    public UUID getCollaboratorUserId() {
        return collaboratorUserId;
    }

    public void setCollaboratorUserId(UUID collaboratorUserId) {
        this.collaboratorUserId = collaboratorUserId;
    }

    public UUID getInvitationId() {
        return invitationId;
    }

    public void setInvitationId(UUID invitationId) {
        this.invitationId = invitationId;
    }

    public UUID getLinkId() {
        return linkId;
    }

    public void setLinkId(UUID linkId) {
        this.linkId = linkId;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(Instant createdAt) {
        this.createdAt = createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public void setUpdatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
    }

    public Instant getRevokedAt() {
        return revokedAt;
    }

    public void setRevokedAt(Instant revokedAt) {
        this.revokedAt = revokedAt;
    }
}
