package com.rocketflow.folders;

import static com.rocketflow.folders.FoldersApi.*;

import java.time.Instant;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.common.ApiException;
import com.rocketflow.sharing.SharingAccessService;
import com.rocketflow.sharing.SharingAccessService.FolderAccess;

@Service
public class FolderService {

    private final FolderRepository folderRepository;
    private final SharingAccessService sharingAccessService;

    public FolderService(FolderRepository folderRepository, SharingAccessService sharingAccessService) {
        this.folderRepository = folderRepository;
        this.sharingAccessService = sharingAccessService;
    }

    @Transactional(readOnly = true)
    public FolderListResponse list(UUID ownerUserId) {
        Map<UUID, FolderDto> folders = new LinkedHashMap<>();
        folderRepository.findByOwnerUserIdOrderByDisplayOrderAscCreatedAtAsc(ownerUserId)
                .forEach(folder -> folders.put(folder.getId(), toDto(folder, sharingAccessService.hasActiveFolderShares(folder.getId()), true)));
        sharingAccessService.accessibleSharedFolders(ownerUserId)
                .forEach(access -> folders.putIfAbsent(access.folder().getId(), toDto(access.folder(), true, access.fullAccess())));
        List<FolderDto> items = folders.values().stream()
                .sorted(Comparator.comparing(FolderDto::displayOrder).thenComparing(FolderDto::createdAt))
                .toList();
        return new FolderListResponse(items);
    }

    @Transactional(readOnly = true)
    public FolderDto get(UUID actorUserId, UUID folderId) {
        FolderAccess access = sharingAccessService.requireFolderAccess(folderId, actorUserId);
        return toDto(access.folder(), access.shared(), access.fullAccess());
    }

    @Transactional
    public FolderDto create(UUID ownerUserId, CreateFolderRequest request) {
        return createInternal(ownerUserId, request.parentFolderId(), request.name(), request.description());
    }

    @Transactional
    public FolderDto createChild(UUID actorUserId, UUID parentFolderId, CreateFolderRequest request) {
        return createInternal(actorUserId, parentFolderId, request.name(), request.description());
    }

    private FolderDto createInternal(UUID actorUserId, UUID parentFolderId, String name, String description) {
        Instant now = Instant.now();
        FolderAccess parentAccess = null;
        UUID ownerUserId = actorUserId;
        if (parentFolderId != null) {
            parentAccess = sharingAccessService.requireFolderFullAccess(parentFolderId, actorUserId);
            ownerUserId = parentAccess.folder().getOwnerUserId();
        }
        Folder folder = new Folder();
        folder.setId(UUID.randomUUID());
        folder.setOwnerUserId(ownerUserId);
        folder.setParentFolderId(parentFolderId);
        folder.setName(name.trim());
        folder.setDescription(description);
        folder.setDisplayOrder(nextDisplayOrder(ownerUserId, parentFolderId));
        folder.setArchived(false);
        folder.setCreatedAt(now);
        folder.setUpdatedAt(now);
        Folder saved = folderRepository.save(folder);
        return toDto(saved, parentAccess != null && parentAccess.shared(), true);
    }

    @Transactional
    public FolderDto update(UUID actorUserId, UUID folderId, UpdateFolderRequest request) {
        FolderAccess access = sharingAccessService.requireFolderFullAccess(folderId, actorUserId);
        Folder folder = access.folder();
        ensureVersion(folder.getVersion(), request.version(), "Folder");
        folder.setName(request.name().trim());
        folder.setDescription(request.description());
        folder.setDisplayOrder(request.displayOrder());
        folder.setArchived(request.archived());
        folder.setUpdatedAt(Instant.now());
        return toDto(folderRepository.save(folder), access.shared(), access.fullAccess());
    }

    @Transactional
    public FolderDto move(UUID actorUserId, UUID folderId, MoveFolderRequest request) {
        FolderAccess access = sharingAccessService.requireFolderFullAccess(folderId, actorUserId);
        Folder folder = access.folder();
        ensureVersion(folder.getVersion(), request.version(), "Folder");
        if (request.targetFolderId() != null) {
            FolderAccess targetAccess = sharingAccessService.requireFolderFullAccess(request.targetFolderId(), actorUserId);
            if (!targetAccess.folder().getOwnerUserId().equals(folder.getOwnerUserId())) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Folder cannot be moved across owners.");
            }
            ensureNotSelfOrDescendant(folder.getId(), request.targetFolderId());
        }
        folder.setParentFolderId(request.targetFolderId());
        folder.setUpdatedAt(Instant.now());
        return toDto(folderRepository.save(folder), access.shared(), access.fullAccess());
    }

    @Transactional
    public FolderDto clone(UUID actorUserId, UUID folderId, CloneFolderRequest request) {
        FolderAccess sourceAccess = sharingAccessService.requireFolderAccess(folderId, actorUserId);
        FolderAccess targetAccess = request.targetFolderId() == null
                ? null
                : sharingAccessService.requireFolderFullAccess(request.targetFolderId(), actorUserId);
        UUID ownerUserId = targetAccess == null ? actorUserId : targetAccess.folder().getOwnerUserId();
        if (!sourceAccess.folder().getOwnerUserId().equals(ownerUserId)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Folder cannot be cloned across owners.");
        }
        Instant now = Instant.now();
        Folder clone = new Folder();
        clone.setId(UUID.randomUUID());
        clone.setOwnerUserId(ownerUserId);
        clone.setParentFolderId(request.targetFolderId());
        clone.setName(request.name() == null || request.name().isBlank() ? sourceAccess.folder().getName() : request.name().trim());
        clone.setDescription(sourceAccess.folder().getDescription());
        clone.setDisplayOrder(nextDisplayOrder(ownerUserId, request.targetFolderId()));
        clone.setArchived(false);
        clone.setCreatedAt(now);
        clone.setUpdatedAt(now);
        Folder saved = folderRepository.save(clone);
        return toDto(saved, targetAccess != null && targetAccess.shared(), true);
    }

    @Transactional
    public void softDelete(UUID actorUserId, UUID folderId) {
        Folder folder = sharingAccessService.requireFolderFullAccess(folderId, actorUserId).folder();
        folder.setArchived(true);
        folder.setUpdatedAt(Instant.now());
        folderRepository.save(folder);
    }

    @Transactional(readOnly = true)
    public Folder requireFolder(UUID folderId, UUID ownerUserId) {
        return folderRepository.findByIdAndOwnerUserId(folderId, ownerUserId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "not_found", "Folder was not found."));
    }

    @Transactional(readOnly = true)
    public FolderAccess requireFolderAccess(UUID folderId, UUID actorUserId) {
        return sharingAccessService.requireFolderAccess(folderId, actorUserId);
    }

    FolderDto toDto(Folder folder, boolean shared, boolean fullAccess) {
        return new FolderDto(
                folder.getId(),
                folder.getParentFolderId(),
                folder.getName(),
                folder.getDescription(),
                folder.getDisplayOrder(),
                folder.isArchived(),
                shared,
                fullAccess,
                folder.getVersion(),
                folder.getCreatedAt(),
                folder.getUpdatedAt()
        );
    }

    private int nextDisplayOrder(UUID ownerUserId, UUID parentFolderId) {
        if (parentFolderId == null) {
            return (int) folderRepository.countByOwnerUserIdAndParentFolderIdIsNull(ownerUserId) + 1;
        }
        return (int) folderRepository.countByOwnerUserIdAndParentFolderId(ownerUserId, parentFolderId) + 1;
    }

    private void ensureNotSelfOrDescendant(UUID folderId, UUID targetFolderId) {
        UUID currentId = targetFolderId;
        while (currentId != null) {
            if (currentId.equals(folderId)) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Folder cannot be moved into itself or a descendant.");
            }
            currentId = folderRepository.findById(currentId)
                    .map(Folder::getParentFolderId)
                    .orElse(null);
        }
    }

    private void ensureVersion(long actual, long expected, String entityName) {
        if (actual != expected) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", entityName + " was updated by another request.");
        }
    }
}
