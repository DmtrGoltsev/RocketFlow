package com.rocketflow.folders;

import static com.rocketflow.folders.FoldersApi.*;

import java.time.Instant;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.common.ApiException;

@Service
public class FolderService {

    private final FolderRepository folderRepository;

    public FolderService(FolderRepository folderRepository) {
        this.folderRepository = folderRepository;
    }

    @Transactional(readOnly = true)
    public FolderListResponse list(UUID ownerUserId) {
        return new FolderListResponse(folderRepository.findByOwnerUserIdOrderByDisplayOrderAscCreatedAtAsc(ownerUserId)
                .stream()
                .map(this::toDto)
                .toList());
    }

    @Transactional
    public FolderDto create(UUID ownerUserId, CreateFolderRequest request) {
        Instant now = Instant.now();
        Folder folder = new Folder();
        folder.setId(UUID.randomUUID());
        folder.setOwnerUserId(ownerUserId);
        folder.setName(request.name().trim());
        folder.setDescription(request.description());
        folder.setDisplayOrder((int) folderRepository.countByOwnerUserId(ownerUserId) + 1);
        folder.setArchived(false);
        folder.setCreatedAt(now);
        folder.setUpdatedAt(now);
        return toDto(folderRepository.save(folder));
    }

    @Transactional
    public FolderDto update(UUID ownerUserId, UUID folderId, UpdateFolderRequest request) {
        Folder folder = requireFolder(folderId, ownerUserId);
        ensureVersion(folder.getVersion(), request.version(), "Folder");
        folder.setName(request.name().trim());
        folder.setDescription(request.description());
        folder.setDisplayOrder(request.displayOrder());
        folder.setArchived(request.archived());
        folder.setUpdatedAt(Instant.now());
        return toDto(folderRepository.save(folder));
    }

    @Transactional
    public void softDelete(UUID ownerUserId, UUID folderId) {
        Folder folder = requireFolder(folderId, ownerUserId);
        folder.setArchived(true);
        folder.setUpdatedAt(Instant.now());
        folderRepository.save(folder);
    }

    @Transactional(readOnly = true)
    public Folder requireFolder(UUID folderId, UUID ownerUserId) {
        return folderRepository.findByIdAndOwnerUserId(folderId, ownerUserId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "not_found", "Folder was not found."));
    }

    FolderDto toDto(Folder folder) {
        return new FolderDto(
                folder.getId(),
                folder.getName(),
                folder.getDescription(),
                folder.getDisplayOrder(),
                folder.isArchived(),
                folder.getVersion(),
                folder.getCreatedAt(),
                folder.getUpdatedAt()
        );
    }

    private void ensureVersion(long actual, long expected, String entityName) {
        if (actual != expected) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", entityName + " was updated by another request.");
        }
    }
}
