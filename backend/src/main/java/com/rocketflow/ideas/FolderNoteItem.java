package com.rocketflow.ideas;

import java.time.Instant;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

@Entity
@Table(name = "folder_note_items")
public class FolderNoteItem {

    @Id
    private UUID id;

    @Column(name = "folder_note_id", nullable = false)
    private UUID folderNoteId;

    @Column(nullable = false, length = 1000)
    private String text;

    @Column(nullable = false)
    private boolean checked;

    @Column(name = "display_order", nullable = false)
    private int displayOrder;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Version
    private long version;

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public UUID getFolderNoteId() { return folderNoteId; }
    public void setFolderNoteId(UUID folderNoteId) { this.folderNoteId = folderNoteId; }
    public String getText() { return text; }
    public void setText(String text) { this.text = text; }
    public boolean isChecked() { return checked; }
    public void setChecked(boolean checked) { this.checked = checked; }
    public int getDisplayOrder() { return displayOrder; }
    public void setDisplayOrder(int displayOrder) { this.displayOrder = displayOrder; }
    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
    public long getVersion() { return version; }
}
