package com.rocketflow.accounts;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Service;

import com.rocketflow.auth.AuthDtos.UserResponse;
import com.rocketflow.auth.AuthenticatedUser;
import com.rocketflow.common.ApiException;
import com.rocketflow.settings.UserSettings;
import com.rocketflow.settings.UserSettingsService;

@Service
public class CurrentUserService {

    private final UserRepository userRepository;
    private final UserSettingsService userSettingsService;

    public CurrentUserService(UserRepository userRepository, UserSettingsService userSettingsService) {
        this.userRepository = userRepository;
        this.userSettingsService = userSettingsService;
    }

    public AuthenticatedUser requireAuthenticatedUser() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !(authentication.getPrincipal() instanceof AuthenticatedUser user)) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "unauthorized", "Authentication is required.");
        }
        return user;
    }

    public UserResponse getCurrentUserProfile() {
        AuthenticatedUser principal = requireAuthenticatedUser();
        User user = userRepository.findById(principal.userId())
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "not_found", "User was not found."));
        UserSettings settings = userSettingsService.getUserSettingsEntity(user.getId());
        return new UserResponse(
                user.getId(),
                user.getEmail(),
                user.getDisplayName(),
                user.getTimezone(),
                settings.getLanguage(),
                user.getCreatedAt()
        );
    }
}
