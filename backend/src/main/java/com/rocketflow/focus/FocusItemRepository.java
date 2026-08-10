package com.rocketflow.focus;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

interface FocusItemRepository extends JpaRepository<FocusItem, UUID> {
    List<FocusItem> findByPeriodIdOrderByPositionAsc(UUID periodId);
    Optional<FocusItem> findByPeriodIdAndTaskId(UUID periodId, UUID taskId);
    boolean existsByPeriodIdAndTaskId(UUID periodId, UUID taskId);
    void deleteByPeriodIdAndTaskId(UUID periodId, UUID taskId);
}
