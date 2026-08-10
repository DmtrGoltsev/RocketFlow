package com.rocketflow.focusnotifications;

import static com.rocketflow.focusnotifications.WebPushApi.*;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

import com.rocketflow.common.ApiException;

@Service
class WebPushSubscriptionService {
    private final ObjectProvider<WebPushSubscriptionRepository> repositoryProvider;
    private final ObjectProvider<JdbcTemplate> jdbcTemplateProvider;
    private final ObjectProvider<PlatformTransactionManager> transactionManagerProvider;
    private final WebPushEndpointValidator endpointValidator;
    private final FocusNotificationProperties properties;

    @Autowired
    WebPushSubscriptionService(
            ObjectProvider<WebPushSubscriptionRepository> repositoryProvider,
            ObjectProvider<JdbcTemplate> jdbcTemplateProvider,
            ObjectProvider<PlatformTransactionManager> transactionManagerProvider,
            WebPushEndpointValidator endpointValidator,
            FocusNotificationProperties properties
    ) {
        this.repositoryProvider = repositoryProvider;
        this.jdbcTemplateProvider = jdbcTemplateProvider;
        this.transactionManagerProvider = transactionManagerProvider;
        this.endpointValidator = endpointValidator;
        this.properties = properties;
    }

    WebPushSubscriptionService(
            WebPushSubscriptionRepository repository,
            WebPushEndpointValidator endpointValidator,
            FocusNotificationProperties properties
    ) {
        this(
                new FixedObjectProvider<>(repository),
                new FixedObjectProvider<>(null),
                new FixedObjectProvider<>(null),
                endpointValidator,
                properties
        );
    }

    WebPushSubscriptionService(
            WebPushSubscriptionRepository repository,
            WebPushEndpointValidator endpointValidator,
            FocusNotificationProperties properties,
            PlatformTransactionManager transactionManager
    ) {
        this(
                new FixedObjectProvider<>(repository),
                new FixedObjectProvider<>(null),
                new FixedObjectProvider<>(transactionManager),
                endpointValidator,
                properties
        );
    }

    ConfigResponse config() {
        boolean enabled = properties.getWebPush().isEnabled();
        return new ConfigResponse(enabled, enabled ? properties.getWebPush().getVapidPublicKey() : null);
    }

    SubscriptionResponse register(UUID userId, RegisterSubscriptionRequest request) {
        ValidatedRegistration registration = validateRegistration(request);
        PlatformTransactionManager transactionManager = transactionManagerProvider.getIfAvailable();
        if (transactionManager == null) {
            return registerInTransaction(userId, registration);
        }
        return new TransactionTemplate(transactionManager).execute(
                status -> registerInTransaction(userId, registration)
        );
    }

    private ValidatedRegistration validateRegistration(RegisterSubscriptionRequest request) {
        String endpoint = request.endpoint().strip();
        endpointValidator.requirePublicHttps(endpoint);
        String p256dh = request.keys().p256dh().strip();
        String auth = request.keys().auth().strip();
        validateSubscriptionKey(p256dh, 65, "p256dh");
        validateSubscriptionKey(auth, 16, "auth");
        return new ValidatedRegistration(
                endpoint,
                sha256(endpoint),
                p256dh,
                auth,
                request.installationId().strip(),
                request.expirationTime(),
                Instant.now()
        );
    }

    private SubscriptionResponse registerInTransaction(UUID userId, ValidatedRegistration registration) {
        WebPushSubscriptionRepository repository = repository();
        lockUserRegistration(userId);

        WebPushSubscription endpointMatch = repository.findByEndpointHash(registration.endpointHash()).orElse(null);
        WebPushSubscription installationMatch = repository.findByUserIdAndInstallationId(
                userId,
                registration.installationId()
        ).orElse(null);
        if (endpointMatch != null && !registration.endpoint().equals(endpointMatch.getEndpoint())) {
            throw new ApiException(HttpStatus.CONFLICT, "web_push_endpoint_conflict", "The Web Push endpoint hash is already registered.");
        }
        if (endpointMatch != null && !userId.equals(endpointMatch.getUserId())) {
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "web_push_endpoint_owned",
                    "The Web Push endpoint belongs to another account."
            );
        }
        WebPushSubscription subscription = endpointMatch != null ? endpointMatch : installationMatch;
        long projectedActive = repository.countActiveUnexpiredByUserId(userId, registration.now());
        if (endpointMatch != null && installationMatch != null && !endpointMatch.getId().equals(installationMatch.getId())) {
            if (isDeliverable(installationMatch, registration.now())) {
                projectedActive--;
            }
        }
        if (subscription == null || !isDeliverable(subscription, registration.now())) {
            projectedActive++;
        }
        if (projectedActive > properties.getWebPush().getMaxActiveSubscriptionsPerUser()) {
            throw new ApiException(
                    HttpStatus.TOO_MANY_REQUESTS,
                    "web_push_subscription_limit",
                    "The account has reached its active Web Push subscription limit."
            );
        }
        if (endpointMatch != null && installationMatch != null && !endpointMatch.getId().equals(installationMatch.getId())) {
            repository.delete(installationMatch);
            repository.flush();
        }
        if (subscription == null) {
            subscription = new WebPushSubscription();
            subscription.setId(UUID.randomUUID());
            subscription.setCreatedAt(registration.now());
        }
        subscription.setUserId(userId);
        subscription.setEndpoint(registration.endpoint());
        subscription.setEndpointHash(registration.endpointHash());
        subscription.setP256dh(registration.p256dh());
        subscription.setAuth(registration.auth());
        subscription.setInstallationId(registration.installationId());
        subscription.setExpirationTime(registration.expirationTime());
        subscription.setActive(true);
        subscription.setUpdatedAt(registration.now());
        try {
            WebPushSubscription saved = repository.saveAndFlush(subscription);
            return new SubscriptionResponse(saved.getId(), saved.isActive());
        } catch (DataIntegrityViolationException exception) {
            throw new ApiException(
                    HttpStatus.CONFLICT,
                    "web_push_subscription_conflict",
                    "The Web Push subscription changed concurrently."
            );
        }
    }

    private boolean isDeliverable(WebPushSubscription subscription, Instant now) {
        return subscription.isActive()
                && (subscription.getExpirationTime() == null || subscription.getExpirationTime().isAfter(now));
    }

    @Transactional
    void deactivate(UUID userId, UUID subscriptionId) {
        WebPushSubscriptionRepository repository = repository();
        WebPushSubscription subscription = repository.findByIdAndUserId(subscriptionId, userId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "not_found", "Web Push subscription was not found."));
        repository.delete(subscription);
    }

    private void validateSubscriptionKey(String value, int expectedBytes, String name) {
        try {
            byte[] decoded = Base64.getUrlDecoder().decode(value.strip());
            if (decoded.length != expectedBytes || (expectedBytes == 65 && decoded[0] != 0x04)) {
                throw invalidKey(name);
            }
        } catch (IllegalArgumentException exception) {
            throw invalidKey(name);
        }
    }

    private ApiException invalidKey(String name) {
        return new ApiException(HttpStatus.BAD_REQUEST, "web_push_key_invalid", "The Web Push " + name + " key is invalid.");
    }

    private String sha256(String value) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable.", exception);
        }
    }

    private WebPushSubscriptionRepository repository() {
        WebPushSubscriptionRepository repository = repositoryProvider.getIfAvailable();
        if (repository == null) {
            throw new IllegalStateException("Web Push subscription storage requires a configured DataSource.");
        }
        return repository;
    }

    private void lockUserRegistration(UUID userId) {
        JdbcTemplate jdbcTemplate = jdbcTemplateProvider.getIfAvailable();
        if (jdbcTemplate != null) {
            jdbcTemplate.queryForObject("select id from users where id = ? for update", UUID.class, userId);
        }
    }

    private record ValidatedRegistration(
            String endpoint,
            String endpointHash,
            String p256dh,
            String auth,
            String installationId,
            Instant expirationTime,
            Instant now
    ) {
    }
}
