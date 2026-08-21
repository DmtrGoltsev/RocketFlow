package com.rocketflow.settings;

import static com.rocketflow.auth.AuthDtos.*;

import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.common.ApiException;

@Service
public class UserSettingsService {

    private static final String GREEN = "green";
    private static final String RED = "red";

    private final UserSettingsRepository userSettingsRepository;

    public UserSettingsService(UserSettingsRepository userSettingsRepository) {
        this.userSettingsRepository = userSettingsRepository;
    }

    @Transactional
    public UserSettings createDefaultSettings(UUID userId, String language, Instant now) {
        UserSettings settings = new UserSettings();
        settings.setUserId(userId);
        settings.setLanguage(language);
        settings.setNotificationsEnabled(true);
        settings.setGreenPriorityDecayEnabled(false);
        settings.setGreenPriorityDecayThreshold("day");
        settings.setGreenPriorityDecayAmount(1);
        settings.setRedPriorityDecayEnabled(false);
        settings.setRedPriorityDecayThreshold("week");
        settings.setRedPriorityDecayAmount(1);
        settings.setCreatedAt(now);
        settings.setUpdatedAt(now);
        return userSettingsRepository.save(settings);
    }

    @Transactional(readOnly = true)
    public UserSettingsResponse getSettings(UUID userId) {
        return toResponse(getUserSettingsEntity(userId));
    }

    @Transactional(readOnly = true)
    public UserSettings getUserSettingsEntity(UUID userId) {
        return userSettingsRepository.findById(userId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "not_found", "User settings were not found."));
    }

    @Transactional
    public UserSettingsResponse updateSettings(UUID userId, UpdateSettingsRequest request) {
        UserSettings settings = getUserSettingsEntity(userId);
        if (settings.getVersion() != request.version()) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", "Settings were updated by another request.");
        }

        boolean changed = !Objects.equals(settings.getLanguage(), request.language())
                || settings.isNotificationsEnabled() != request.notificationsEnabled();
        if (!changed) {
            return toResponse(settings);
        }

        settings.setLanguage(request.language());
        settings.setNotificationsEnabled(request.notificationsEnabled());
        settings.setUpdatedAt(Instant.now());

        return toResponse(userSettingsRepository.save(settings));
    }

    public UserSettingsResponse toResponse(UserSettings settings) {
        return new UserSettingsResponse(
                settings.getLanguage(),
                toPolicyDto(GREEN, settings.getGreenPriorityDecayThreshold(), settings.getGreenPriorityDecayAmount()),
                toPolicyDto(RED, settings.getRedPriorityDecayThreshold(), settings.getRedPriorityDecayAmount()),
                settings.isNotificationsEnabled(),
                settings.getVersion()
        );
    }

    private PriorityDecayPolicyDto toPolicyDto(String taskType, String threshold, int amount) {
        return new PriorityDecayPolicyDto(taskType, false, threshold, amount);
    }
}
