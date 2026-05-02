package com.rocketflow.notifications;

import static com.rocketflow.notifications.DevicesApi.*;

import java.time.Instant;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.common.ApiException;

@Service
public class DevicesService {

    private final DeviceRegistrationRepository deviceRegistrationRepository;

    public DevicesService(DeviceRegistrationRepository deviceRegistrationRepository) {
        this.deviceRegistrationRepository = deviceRegistrationRepository;
    }

    @Transactional
    public DeviceRegistrationResponse register(UUID userId, RegisterDeviceRequest request) {
        Instant now = Instant.now();
        String normalizedToken = request.pushToken().trim();
        String normalizedInstallationId = normalizeInstallationId(request.installationId());
        DeviceRegistration installationMatch = normalizedInstallationId == null
                ? null
                : deviceRegistrationRepository.findByInstallationId(normalizedInstallationId).orElse(null);
        DeviceRegistration tokenMatch = deviceRegistrationRepository.findByPushToken(normalizedToken).orElse(null);
        DeviceRegistration registration = tokenMatch != null ? tokenMatch : installationMatch;

        if (installationMatch != null
                && tokenMatch != null
                && !installationMatch.getId().equals(tokenMatch.getId())) {
            retireSupersededInstallation(installationMatch, now);
        }

        if (registration == null) {
            registration = new DeviceRegistration();
            registration.setId(UUID.randomUUID());
            registration.setCreatedAt(now);
        }

        registration.setUserId(userId);
        registration.setPlatform(request.platform());
        registration.setPushToken(normalizedToken);
        if (normalizedInstallationId != null) {
            registration.setInstallationId(normalizedInstallationId);
        }
        registration.setDeviceName(normalizeDeviceName(request.deviceName()));
        registration.setActive(true);
        registration.setUpdatedAt(now);

        return toResponse(deviceRegistrationRepository.save(registration));
    }

    @Transactional
    public void deactivate(UUID userId, UUID deviceId) {
        DeviceRegistration registration = deviceRegistrationRepository.findByIdAndUserId(deviceId, userId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "not_found", "Device was not found."));
        if (registration.isActive()) {
            registration.setActive(false);
            registration.setUpdatedAt(Instant.now());
            deviceRegistrationRepository.save(registration);
        }
    }

    private DeviceRegistrationResponse toResponse(DeviceRegistration registration) {
        return new DeviceRegistrationResponse(
                registration.getId(),
                registration.getPlatform(),
                registration.getDeviceName(),
                registration.isActive(),
                registration.getCreatedAt()
        );
    }

    private String normalizeDeviceName(String deviceName) {
        if (deviceName == null) {
            return null;
        }
        String trimmed = deviceName.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private String normalizeInstallationId(String installationId) {
        if (installationId == null) {
            return null;
        }
        String trimmed = installationId.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private void retireSupersededInstallation(DeviceRegistration registration, Instant now) {
        registration.setActive(false);
        registration.setInstallationId(null);
        registration.setUpdatedAt(now);
        deviceRegistrationRepository.saveAndFlush(registration);
    }
}
