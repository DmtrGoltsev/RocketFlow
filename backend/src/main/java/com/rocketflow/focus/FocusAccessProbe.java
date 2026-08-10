package com.rocketflow.focus;

import java.util.UUID;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.sharing.SharingAccessService;
import com.rocketflow.sharing.SharingAccessService.TaskAccess;

@Service
class FocusAccessProbe {
    private final SharingAccessService sharingAccessService;

    FocusAccessProbe(SharingAccessService sharingAccessService) {
        this.sharingAccessService = sharingAccessService;
    }

    @Transactional(readOnly = true, propagation = Propagation.REQUIRES_NEW)
    TaskAccess requireTaskAccess(UUID taskId, UUID userId) {
        return sharingAccessService.requireTaskAccess(taskId, userId);
    }
}
