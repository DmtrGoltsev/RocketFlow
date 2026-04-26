package com.rocketflow.settings;

import static com.rocketflow.auth.AuthDtos.*;

import java.time.Instant;
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
        settings.setGreenPriorityDecayEnabled(true);
        settings.setGreenPriorityDecayThreshold("day");
        settings.setGreenPriorityDecayAmount(1);
        settings.setRedPriorityDecayEnabled(true);
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

        validateDecayAmount(request.greenPriorityDecayPolicy().decayAmount(), GREEN);
        validateDecayAmount(request.redPriorityDecayPolicy().decayAmount(), RED);

        settings.setLanguage(request.language());
        settings.setNotificationsEnabled(request.notificationsEnabled());
        settings.setGreenPriorityDecayEnabled(request.greenPriorityDecayPolicy().enabled());
        settings.setGreenPriorityDecayThreshold(request.greenPriorityDecayPolicy().thresholdPreset());
        settings.setGreenPriorityDecayAmount(request.greenPriorityDecayPolicy().decayAmount());
        settings.setRedPriorityDecayEnabled(request.redPriorityDecayPolicy().enabled());
        settings.setRedPriorityDecayThreshold(request.redPriorityDecayPolicy().thresholdPreset());
        settings.setRedPriorityDecayAmount(request.redPriorityDecayPolicy().decayAmount());
        settings.setUpdatedAt(Instant.now());

        return toResponse(userSettingsRepository.save(settings));
    }

    private void validateDecayAmount(int decayAmount, String taskType) {
        if (decayAmount <= 0) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error",
                    "Priority decay amount must be positive for " + taskType + " tasks.");
        }
    }

    public UserSettingsResponse toResponse(UserSettings settings) {
        return new UserSettingsResponse(
                settings.getLanguage(),
                toPolicyDto(GREEN, settings.isGreenPriorityDecayEnabled(), settings.getGreenPriorityDecayThreshold(), settings.getGreenPriorityDecayAmount()),
                toPolicyDto(RED, settings.isRedPriorityDecayEnabled(), settings.getRedPriorityDecayThreshold(), settings.getRedPriorityDecayAmount()),
                settings.isNotificationsEnabled(),
                settings.getVersion()
        );
    }

    private PriorityDecayPolicyDto toPolicyDto(String taskType, boolean enabled, String threshold, int amount) {
        return new PriorityDecayPolicyDto(taskType, enabled, threshold, amount);
    }
}
