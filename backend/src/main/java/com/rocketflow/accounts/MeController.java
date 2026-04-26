package com.rocketflow.accounts;

import static com.rocketflow.auth.AuthDtos.*;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.rocketflow.settings.UserSettingsService;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/me")
public class MeController {

    private final CurrentUserService currentUserService;
    private final UserSettingsService userSettingsService;

    public MeController(CurrentUserService currentUserService, UserSettingsService userSettingsService) {
        this.currentUserService = currentUserService;
        this.userSettingsService = userSettingsService;
    }

    @GetMapping
    public UserResponse getCurrentUser() {
        return currentUserService.getCurrentUserProfile();
    }

    @GetMapping("/settings")
    public UserSettingsResponse getSettings() {
        return userSettingsService.getSettings(currentUserService.requireAuthenticatedUser().userId());
    }

    @PatchMapping("/settings")
    public UserSettingsResponse updateSettings(@Valid @RequestBody UpdateSettingsRequest request) {
        return userSettingsService.updateSettings(currentUserService.requireAuthenticatedUser().userId(), request);
    }
}
