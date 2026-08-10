package com.rocketflow.focus;

import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

interface FocusNotificationSettingsRepository extends JpaRepository<FocusNotificationSettings, UUID> {
}
