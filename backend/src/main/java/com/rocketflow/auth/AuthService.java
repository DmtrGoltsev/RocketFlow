package com.rocketflow.auth;

import static com.rocketflow.auth.AuthDtos.*;

import java.time.Instant;
import java.time.ZoneId;
import java.time.zone.ZoneRulesException;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.accounts.User;
import com.rocketflow.accounts.UserRepository;
import com.rocketflow.common.ApiException;
import com.rocketflow.settings.UserSettings;
import com.rocketflow.settings.UserSettingsService;

@Service
public class AuthService {

    private final UserRepository userRepository;
    private final UserCredentialRepository userCredentialRepository;
    private final UserSettingsService userSettingsService;
    private final PasswordEncoder passwordEncoder;
    private final AuthSessionRepository authSessionRepository;
    private final AuthSessionFactory authSessionFactory;
    private final TokenHasher tokenHasher;

    public AuthService(
            UserRepository userRepository,
            UserCredentialRepository userCredentialRepository,
            UserSettingsService userSettingsService,
            PasswordEncoder passwordEncoder,
            AuthSessionRepository authSessionRepository,
            AuthSessionFactory authSessionFactory,
            TokenHasher tokenHasher
    ) {
        this.userRepository = userRepository;
        this.userCredentialRepository = userCredentialRepository;
        this.userSettingsService = userSettingsService;
        this.passwordEncoder = passwordEncoder;
        this.authSessionRepository = authSessionRepository;
        this.authSessionFactory = authSessionFactory;
        this.tokenHasher = tokenHasher;
    }

    @Transactional
    public AuthResponse register(RegisterRequest request) {
        String normalizedEmail = request.email().trim().toLowerCase();
        validateTimezone(request.timezone());

        if (userRepository.findByEmailIgnoreCase(normalizedEmail).isPresent()) {
            throw new ApiException(HttpStatus.CONFLICT, "conflict", "A user with this email already exists.");
        }

        Instant now = Instant.now();

        User user = new User();
        user.setId(UUID.randomUUID());
        user.setEmail(normalizedEmail);
        user.setDisplayName(request.displayName().trim());
        user.setTimezone(request.timezone());
        user.setActive(true);
        user.setCreatedAt(now);
        user.setUpdatedAt(now);
        userRepository.save(user);

        UserCredential credential = new UserCredential();
        credential.setUserId(user.getId());
        credential.setPasswordHash(passwordEncoder.encode(request.password()));
        credential.setPasswordUpdatedAt(now);
        credential.setCreatedAt(now);
        credential.setUpdatedAt(now);
        userCredentialRepository.save(credential);

        UserSettings settings = userSettingsService.createDefaultSettings(user.getId(), request.language(), now);

        AuthSessionFactory.CreatedSession createdSession = authSessionFactory.create(user, now);
        authSessionRepository.save(createdSession.session());

        return new AuthResponse(toUserResponse(user, settings), toTokensResponse(createdSession.tokenPair()));
    }

    @Transactional
    public AuthResponse login(LoginRequest request) {
        User user = userRepository.findByEmailIgnoreCase(request.email().trim())
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "authentication_failed", "Invalid email or password."));

        UserCredential credential = userCredentialRepository.findByUserId(user.getId())
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "authentication_failed", "Invalid email or password."));

        if (!passwordEncoder.matches(request.password(), credential.getPasswordHash())) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "authentication_failed", "Invalid email or password.");
        }

        Instant now = Instant.now();
        AuthSessionFactory.CreatedSession createdSession = authSessionFactory.create(user, now);
        authSessionRepository.save(createdSession.session());

        UserSettings settings = userSettingsService.getUserSettingsEntity(user.getId());
        return new AuthResponse(toUserResponse(user, settings), toTokensResponse(createdSession.tokenPair()));
    }

    @Transactional
    public RefreshResponse refresh(RefreshRequest request) {
        AuthSession session = authSessionRepository.findByRefreshTokenHashAndRevokedAtIsNull(tokenHasher.hash(request.refreshToken()))
                .filter(existing -> existing.getRefreshExpiresAt().isAfter(Instant.now()))
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "authentication_failed", "Refresh token is invalid or expired."));

        User user = userRepository.findById(session.getUserId())
                .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "authentication_failed", "User account is not available."));

        session.setRevokedAt(Instant.now());
        session.setUpdatedAt(Instant.now());
        authSessionRepository.save(session);

        AuthSessionFactory.CreatedSession createdSession = authSessionFactory.create(user, Instant.now());
        authSessionRepository.save(createdSession.session());

        return new RefreshResponse(toTokensResponse(createdSession.tokenPair()));
    }

    @Transactional
    public void logout(LogoutRequest request) {
        authSessionRepository.findByRefreshTokenHashAndRevokedAtIsNull(tokenHasher.hash(request.refreshToken()))
                .ifPresent(session -> {
                    session.setRevokedAt(Instant.now());
                    session.setUpdatedAt(Instant.now());
                    authSessionRepository.save(session);
                });
    }

    private void validateTimezone(String timezone) {
        try {
            ZoneId.of(timezone);
        } catch (ZoneRulesException exception) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "validation_error", "Timezone is invalid.");
        }
    }

    private UserResponse toUserResponse(User user, UserSettings settings) {
        return new UserResponse(
                user.getId(),
                user.getEmail(),
                user.getDisplayName(),
                user.getTimezone(),
                settings.getLanguage(),
                user.getCreatedAt()
        );
    }

    private TokensResponse toTokensResponse(AuthTokenPair tokenPair) {
        return new TokensResponse(tokenPair.accessToken(), tokenPair.refreshToken(), tokenPair.expiresAt());
    }
}
