package com.rocketflow.focusnotifications;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.util.Base64;
import java.util.Optional;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.PlatformTransactionManager;

import com.rocketflow.common.ApiException;
import com.rocketflow.focusnotifications.WebPushApi.KeysRequest;
import com.rocketflow.focusnotifications.WebPushApi.RegisterSubscriptionRequest;

class WebPushSubscriptionServiceTest {
    private WebPushSubscriptionRepository repository;
    private WebPushEndpointValidator endpointValidator;
    private WebPushSubscriptionService service;
    private FocusNotificationProperties properties;

    @BeforeEach
    void setUp() {
        repository = org.mockito.Mockito.mock(WebPushSubscriptionRepository.class);
        endpointValidator = org.mockito.Mockito.mock(WebPushEndpointValidator.class);
        properties = new FocusNotificationProperties();
        service = new WebPushSubscriptionService(
                repository,
                endpointValidator,
                properties
        );
        when(repository.saveAndFlush(any())).thenAnswer(invocation -> invocation.getArgument(0));
    }

    @Test
    void onlyOwnerCanDeleteSubscription() {
        UUID userId = UUID.randomUUID();
        UUID subscriptionId = UUID.randomUUID();
        when(repository.findByIdAndUserId(subscriptionId, userId)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.deactivate(userId, subscriptionId))
                .isInstanceOf(ApiException.class)
                .extracting("status")
                .isEqualTo(HttpStatus.NOT_FOUND);
        verify(repository, never()).delete(any());
    }

    @Test
    void deleteReleasesEndpointOnlyForItsOwner() {
        UUID userId = UUID.randomUUID();
        WebPushSubscription subscription = subscription(userId, "installation-a", "https://fcm.googleapis.com/a");
        when(repository.findByIdAndUserId(subscription.getId(), userId)).thenReturn(Optional.of(subscription));

        service.deactivate(userId, subscription.getId());

        verify(repository).delete(subscription);
    }

    @Test
    void rejectsEndpointOwnedByAnotherAccount() {
        UUID userId = UUID.randomUUID();
        String endpoint = "https://fcm.googleapis.com/shared";
        WebPushSubscription existing = subscription(UUID.randomUUID(), "other-installation", endpoint);
        when(repository.findByEndpointHash(anyString())).thenReturn(Optional.of(existing));

        assertThatThrownBy(() -> service.register(userId, request(endpoint, "installation-a")))
                .isInstanceOf(ApiException.class)
                .extracting("status")
                .isEqualTo(HttpStatus.CONFLICT);
        verify(repository, never()).saveAndFlush(any());
    }

    @Test
    void rejectsSubscriptionAboveConfiguredActiveLimit() {
        UUID userId = UUID.randomUUID();
        properties.getWebPush().setMaxActiveSubscriptionsPerUser(1);
        when(repository.countActiveUnexpiredByUserId(org.mockito.ArgumentMatchers.eq(userId), any())).thenReturn(1L);

        assertThatThrownBy(() -> service.register(
                userId,
                request("https://fcm.googleapis.com/new", "installation-b")
        )).isInstanceOf(ApiException.class)
                .extracting("status")
                .isEqualTo(HttpStatus.TOO_MANY_REQUESTS);
        verify(repository, never()).saveAndFlush(any());
    }

    @Test
    void rotatesEndpointForExistingInstallationWithoutConsumingAnotherSlot() {
        UUID userId = UUID.randomUUID();
        WebPushSubscription existing = subscription(userId, "installation-a", "https://fcm.googleapis.com/old");
        when(repository.findByUserIdAndInstallationId(userId, "installation-a"))
                .thenReturn(Optional.of(existing));
        when(repository.countActiveUnexpiredByUserId(org.mockito.ArgumentMatchers.eq(userId), any())).thenReturn(10L);

        var response = service.register(
                userId,
                request("https://fcm.googleapis.com/new", "installation-a")
        );

        assertThat(response.id()).isEqualTo(existing.getId());
        assertThat(existing.getEndpoint()).isEqualTo("https://fcm.googleapis.com/new");
        assertThat(existing.isActive()).isTrue();
    }

    @Test
    void expiredSubscriptionDoesNotConsumeAnActiveSlot() {
        UUID userId = UUID.randomUUID();
        properties.getWebPush().setMaxActiveSubscriptionsPerUser(1);
        WebPushSubscription expired = subscription(userId, "installation-a", "https://fcm.googleapis.com/old");
        expired.setExpirationTime(Instant.parse("2020-01-01T00:00:00Z"));
        when(repository.findByUserIdAndInstallationId(userId, "installation-a")).thenReturn(Optional.of(expired));
        when(repository.countActiveUnexpiredByUserId(org.mockito.ArgumentMatchers.eq(userId), any())).thenReturn(0L);

        var response = service.register(
                userId,
                request("https://fcm.googleapis.com/new", "installation-a")
        );

        assertThat(response.id()).isEqualTo(expired.getId());
        assertThat(expired.getExpirationTime()).isNull();
        verify(repository).countActiveUnexpiredByUserId(org.mockito.ArgumentMatchers.eq(userId), any());
    }

    @Test
    void failingEndpointValidationNeverOpensRegistrationTransaction() {
        PlatformTransactionManager transactionManager = org.mockito.Mockito.mock(PlatformTransactionManager.class);
        service = new WebPushSubscriptionService(repository, endpointValidator, properties, transactionManager);
        when(endpointValidator.requirePublicHttps(anyString())).thenThrow(
                new ApiException(HttpStatus.BAD_REQUEST, "web_push_endpoint_invalid", "invalid")
        );

        assertThatThrownBy(() -> service.register(
                UUID.randomUUID(),
                request("https://fcm.googleapis.com/fail", "installation-a")
        )).isInstanceOf(ApiException.class);

        verifyNoInteractions(transactionManager, repository);
    }

    private RegisterSubscriptionRequest request(String endpoint, String installationId) {
        byte[] publicKey = new byte[65];
        publicKey[0] = 0x04;
        return new RegisterSubscriptionRequest(
                endpoint,
                null,
                new KeysRequest(
                        Base64.getUrlEncoder().withoutPadding().encodeToString(publicKey),
                        Base64.getUrlEncoder().withoutPadding().encodeToString(new byte[16])
                ),
                installationId
        );
    }

    private WebPushSubscription subscription(UUID userId, String installationId, String endpoint) {
        WebPushSubscription subscription = new WebPushSubscription();
        subscription.setId(UUID.randomUUID());
        subscription.setUserId(userId);
        subscription.setInstallationId(installationId);
        subscription.setEndpoint(endpoint);
        subscription.setActive(true);
        return subscription;
    }
}
