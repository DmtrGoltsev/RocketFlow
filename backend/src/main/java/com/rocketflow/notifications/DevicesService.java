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
        DeviceRegistration registration = deviceRegistrationRepository.findByPushToken(normalizedToken)
                .orElseGet(DeviceRegistration::new);

        if (registration.getId() == null) {
            registration.setId(UUID.randomUUID());
            registration.setCreatedAt(now);
        }

        registration.setUserId(userId);
        registration.setPlatform(request.platform());
        registration.setPushToken(normalizedToken);
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
}
