package com.rocketflow.notifications;

import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface DeviceRegistrationRepository extends JpaRepository<DeviceRegistration, UUID> {

    Optional<DeviceRegistration> findByPushToken(String pushToken);

    Optional<DeviceRegistration> findByInstallationId(String installationId);

    Optional<DeviceRegistration> findByIdAndUserId(UUID id, UUID userId);

    List<DeviceRegistration> findByUserIdInAndActiveTrueOrderByUserIdAscCreatedAtAsc(Collection<UUID> userIds);
}
