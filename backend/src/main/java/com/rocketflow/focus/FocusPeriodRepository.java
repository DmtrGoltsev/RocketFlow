package com.rocketflow.focus;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;

import jakarta.persistence.LockModeType;

interface FocusPeriodRepository extends JpaRepository<FocusPeriod, UUID> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<FocusPeriod> findFirstByUserIdAndStatus(UUID userId, String status);

    Optional<FocusPeriod> findByUserIdAndWeekStart(UUID userId, LocalDate weekStart);

    List<FocusPeriod> findByUserIdOrderByWeekStartDesc(UUID userId);

    Optional<FocusPeriod> findByIdAndUserId(UUID id, UUID userId);
}
