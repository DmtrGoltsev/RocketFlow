package com.rocketflow.focusnotifications;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import org.springframework.http.HttpStatus;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import com.rocketflow.common.ApiException;
import com.rocketflow.focusnotifications.FocusNotificationCandidateStore.Candidate;
import com.rocketflow.focusnotifications.FocusNotificationDeliveryStore.Delivery;
import com.rocketflow.focusnotifications.FocusNotificationLeaseHeartbeat.ProviderCall;
import com.rocketflow.notifications.DeviceRegistration;
import com.rocketflow.notifications.DeviceRegistrationRepository;
import com.rocketflow.notifications.FcmSender;
import com.rocketflow.notifications.NotificationProperties;
import com.rocketflow.sharing.SharingAccessService;

@Service
public class FocusNotificationEngine {
    private static final Duration FCM_TTL = Duration.ofMinutes(15);

    private final FocusNotificationCandidateStore candidateStore;
    private final FocusNotificationDeliveryStore deliveryStore;
    private final DeviceRegistrationRepository deviceRepository;
    private final ObjectProvider<WebPushSubscriptionRepository> webPushRepositoryProvider;
    private final SharingAccessService sharingAccessService;
    private final FcmSender fcmSender;
    private final WebPushSender webPushSender;
    private final NotificationProperties notificationProperties;
    private final FocusNotificationProperties properties;
    private final FocusNotificationBackoff backoff;
    private final Clock clock;
    private final FocusNotificationLeaseHeartbeat leaseHeartbeat;

    @Autowired
    public FocusNotificationEngine(
            FocusNotificationCandidateStore candidateStore,
            FocusNotificationDeliveryStore deliveryStore,
            DeviceRegistrationRepository deviceRepository,
            ObjectProvider<WebPushSubscriptionRepository> webPushRepositoryProvider,
            SharingAccessService sharingAccessService,
            FcmSender fcmSender,
            WebPushSender webPushSender,
            NotificationProperties notificationProperties,
            FocusNotificationProperties properties,
            FocusNotificationBackoff backoff,
            Clock clock,
            FocusNotificationLeaseHeartbeat leaseHeartbeat
    ) {
        this.candidateStore = candidateStore;
        this.deliveryStore = deliveryStore;
        this.deviceRepository = deviceRepository;
        this.webPushRepositoryProvider = webPushRepositoryProvider;
        this.sharingAccessService = sharingAccessService;
        this.fcmSender = fcmSender;
        this.webPushSender = webPushSender;
        this.notificationProperties = notificationProperties;
        this.properties = properties;
        this.backoff = backoff;
        this.clock = clock;
        this.leaseHeartbeat = leaseHeartbeat;
    }

    FocusNotificationEngine(
            FocusNotificationCandidateStore candidateStore,
            FocusNotificationDeliveryStore deliveryStore,
            DeviceRegistrationRepository deviceRepository,
            WebPushSubscriptionRepository webPushRepository,
            SharingAccessService sharingAccessService,
            FcmSender fcmSender,
            WebPushSender webPushSender,
            NotificationProperties notificationProperties,
            FocusNotificationProperties properties,
            Clock clock,
            FocusNotificationLeaseHeartbeat leaseHeartbeat
    ) {
        this(
                candidateStore, deliveryStore, deviceRepository, new FixedObjectProvider<>(webPushRepository),
                sharingAccessService, fcmSender, webPushSender, notificationProperties, properties,
                new FocusNotificationBackoff(properties), clock, leaseHeartbeat
        );
    }

    public RunSummary process() {
        MutableSummary summary = new MutableSummary();
        Instant candidateLookupNow = clock.instant();
        List<Candidate> candidates = candidateStore.activeCandidates(candidateLookupNow).stream()
                .filter(candidate -> isEligible(candidate, candidateLookupNow))
                .filter(candidate -> !isQuiet(candidate, candidateLookupNow))
                .toList();
        if (candidates.isEmpty()) {
            processRetries(summary);
            return summary.freeze();
        }

        Set<UUID> userIds = candidates.stream().map(Candidate::userId).collect(Collectors.toSet());
        Map<UUID, List<DeviceRegistration>> devices = notificationProperties.getFcm().isEnabled()
                ? deviceRepository.findByUserIdInAndActiveTrueOrderByUserIdAscCreatedAtAsc(userIds).stream()
                        .collect(Collectors.groupingBy(DeviceRegistration::getUserId, LinkedHashMap::new, Collectors.toList()))
                : Map.of();
        WebPushSubscriptionRepository webPushRepository = webPushRepositoryProvider.getIfAvailable();
        Instant subscriptionLookupNow = clock.instant();
        Map<UUID, List<WebPushSubscription>> subscriptions = properties.getWebPush().isEnabled() && webPushRepository != null
                ? webPushRepository.findDeliverable(userIds, subscriptionLookupNow).stream()
                        .collect(Collectors.groupingBy(WebPushSubscription::getUserId, LinkedHashMap::new, Collectors.toList()))
                : Map.of();

        for (Candidate candidate : candidates) {
            for (DeviceRegistration device : devices.getOrDefault(candidate.userId(), List.of())) {
                claimAndDeliver(candidate, "fcm", device.getId(), summary);
            }
            for (WebPushSubscription subscription : subscriptions.getOrDefault(candidate.userId(), List.of())) {
                claimAndDeliver(candidate, "web_push", subscription.getId(), summary);
            }
        }
        processRetries(summary);
        return summary.freeze();
    }

    Map<String, String> fcmData(UUID eventId, UUID periodId) {
        FocusPushPayload payload = FocusPushPayload.reminder(eventId, periodId);
        return Map.of(
                "type", payload.type(),
                "periodId", periodId.toString(),
                "eventId", eventId.toString(),
                "route", "focus",
                "title", payload.title(),
                "body", payload.body()
        );
    }

    private void processRetries(MutableSummary summary) {
        Duration leaseDuration = Duration.ofMillis(properties.getFocus().getClaimLeaseMs());
        for (int processed = 0; processed < properties.getFocus().getMaxRetriesPerPoll(); processed++) {
            Instant claimNow = clock.instant();
            Delivery delivery = deliveryStore.claimOneDue(claimNow, leaseDuration);
            if (delivery == null) {
                return;
            }
            if (delivery.attemptCount() > properties.getFocus().getMaxDeliveryAttempts()) {
                finalizeDelivery(
                        delivery, "failed", null, "Focus delivery exhausted its retry budget.", summary, false
                );
                continue;
            }
            Instant eligibilityNow = clock.instant();
            Candidate candidate = candidateStore.activeCandidate(delivery.periodId(), eligibilityNow);
            if (candidate == null || !isEligible(candidate, eligibilityNow)) {
                finalizeDelivery(
                        delivery, "cancelled", null, "Focus is no longer eligible for notifications.", summary, true
                );
                continue;
            }
            if (isQuiet(candidate, eligibilityNow)) {
                Instant deferNow = clock.instant();
                boolean deferred = deliveryStore.deferWithoutAttempt(
                        delivery,
                        deferNow,
                        deferNow.plusMillis(properties.getFocus().getFixedDelayMs()),
                        "Focus is currently inside quiet hours."
                );
                if (deferred) {
                    summary.skipped++;
                } else {
                    summary.deduplicated++;
                }
                continue;
            }
            deliver(delivery, summary);
        }
    }

    private void claimAndDeliver(
            Candidate candidate,
            String channel,
            UUID targetId,
            MutableSummary summary
    ) {
        UUID deliveryId = UUID.randomUUID();
        UUID eventId = UUID.randomUUID();
        Instant enqueueNow = clock.instant();
        Delivery delivery = deliveryStore.claimNew(
                deliveryId, candidate.periodId(), candidate.userId(), channel, targetId,
                cadenceBucket(candidate, enqueueNow), eventId, enqueueNow,
                Duration.ofMillis(properties.getFocus().getClaimLeaseMs())
        );
        if (delivery == null) {
            summary.deduplicated++;
            return;
        }
        deliver(delivery, summary);
    }

    private void deliver(Delivery delivery, MutableSummary summary) {
        if ("fcm".equals(delivery.channel())) {
            DeviceRegistration device = deviceRepository.findById(delivery.targetId()).orElse(null);
            if (device == null || !device.isActive() || !device.getUserId().equals(delivery.userId())
                    || !notificationProperties.getFcm().isEnabled()) {
                finalizeDelivery(delivery, "cancelled", null, "FCM target is unavailable.", summary, true);
                return;
            }
            ProviderCall<FcmSender.SendResult> providerCall = leaseHeartbeat.aroundProviderCall(
                    delivery,
                    () -> fcmSender.sendDataOnly(
                            device,
                            fcmData(delivery.eventId(), delivery.periodId()),
                            "focus-" + delivery.periodId(),
                            FCM_TTL
                    )
            );
            if (!providerCall.leaseOwned()) {
                summary.deduplicated++;
                return;
            }
            FcmSender.SendResult result = providerCall.value();
            switch (result.outcome()) {
                case SENT -> finalizeDelivery(delivery, "sent", null, result.providerResponse(), summary, false);
                case RETRY -> scheduleRetry(delivery, null, result.providerResponse(), summary);
                case DEACTIVATE -> {
                    Instant finalizeNow = clock.instant();
                    if (deliveryStore.markAndDeactivateDevice(delivery, finalizeNow, result.providerResponse())) {
                        device.setActive(false);
                        device.setUpdatedAt(finalizeNow);
                        summary.failed++;
                    } else {
                        summary.deduplicated++;
                    }
                }
                case CONFIG_FAILURE -> finalizeDelivery(
                        delivery, "config_failed", null, result.providerResponse(), summary, false
                );
                case PERMANENT_FAILURE -> finalizeDelivery(
                        delivery, "failed", null, result.providerResponse(), summary, false
                );
            }
            return;
        }

        WebPushSubscriptionRepository webPushRepository = webPushRepositoryProvider.getIfAvailable();
        WebPushSubscription subscription = webPushRepository == null
                ? null
                : webPushRepository.findById(delivery.targetId()).orElse(null);
        if (subscription == null || !subscription.isActive() || !subscription.getUserId().equals(delivery.userId())
                || !properties.getWebPush().isEnabled()) {
            finalizeDelivery(delivery, "cancelled", null, "Web Push target is unavailable.", summary, true);
            return;
        }
        ProviderCall<WebPushSender.Result> providerCall = leaseHeartbeat.aroundProviderCall(
                delivery,
                () -> webPushSender.send(
                        subscription,
                        FocusPushPayload.reminder(delivery.eventId(), delivery.periodId())
                )
        );
        if (!providerCall.leaseOwned()) {
            summary.deduplicated++;
            return;
        }
        WebPushSender.Result result = providerCall.value();
        switch (result.outcome()) {
            case SENT -> finalizeDelivery(delivery, "sent", null, result.providerResponse(), summary, false);
            case DEACTIVATE -> {
                Instant finalizeNow = clock.instant();
                if (deliveryStore.markAndDeleteWebPushSubscription(
                        delivery, finalizeNow, result.providerResponse()
                )) {
                    summary.failed++;
                } else {
                    summary.deduplicated++;
                }
            }
            case RETRY -> scheduleRetry(delivery, result.retryAfter(), result.providerResponse(), summary);
            case CONFIG_FAILURE -> finalizeDelivery(
                    delivery, "config_failed", null, result.providerResponse(), summary, false
            );
            case PERMANENT_FAILURE -> finalizeDelivery(
                    delivery, "failed", null, result.providerResponse(), summary, false
            );
        }
    }

    private void scheduleRetry(
            Delivery delivery,
            Duration requestedDelay,
            String response,
            MutableSummary summary
    ) {
        if (delivery.attemptCount() >= properties.getFocus().getMaxDeliveryAttempts()) {
            finalizeDelivery(delivery, "failed", null, response, summary, false);
            return;
        }
        Duration delay = backoff.delay(delivery.attemptCount(), requestedDelay);
        Instant backoffNow = clock.instant();
        if (deliveryStore.mark(delivery, "retry", backoffNow, backoffNow.plus(delay), response)) {
            summary.retried++;
        } else {
            summary.deduplicated++;
        }
    }

    private void finalizeDelivery(
            Delivery delivery,
            String status,
            Instant nextAttemptAt,
            String response,
            MutableSummary summary,
            boolean skipped
    ) {
        Instant finalizeNow = clock.instant();
        if (!deliveryStore.mark(delivery, status, finalizeNow, nextAttemptAt, response)) {
            summary.deduplicated++;
        } else if (skipped) {
            summary.skipped++;
        } else if ("sent".equals(status)) {
            summary.sent++;
        } else {
            summary.failed++;
        }
    }

    private boolean isEligible(Candidate candidate, Instant now) {
        if (candidate.intervalMinutes() != 30 && candidate.intervalMinutes() != 60
                && candidate.intervalMinutes() != 120 && candidate.intervalMinutes() != 240) {
            return false;
        }
        for (UUID taskId : candidateStore.incompleteTaskIds(candidate.periodId())) {
            try {
                sharingAccessService.requireTaskAccess(taskId, candidate.userId());
                return true;
            } catch (ApiException exception) {
                if (exception.getStatus() != HttpStatus.NOT_FOUND) {
                    throw exception;
                }
            }
        }
        return false;
    }

    private boolean isQuiet(Candidate candidate, Instant now) {
        try {
            return QuietHours.contains(now, candidate.timezone(), candidate.quietStart(), candidate.quietEnd());
        } catch (RuntimeException exception) {
            return true;
        }
    }

    private Instant cadenceBucket(Candidate candidate, Instant now) {
        long intervalSeconds = Duration.ofMinutes(candidate.intervalMinutes()).toSeconds();
        long elapsed = Math.max(0, Duration.between(candidate.startsAt(), now).getSeconds());
        return candidate.startsAt().plusSeconds((elapsed / intervalSeconds) * intervalSeconds);
    }

    public record RunSummary(int sent, int failed, int retried, int deduplicated, int skipped) {
    }

    private static class MutableSummary {
        int sent;
        int failed;
        int retried;
        int deduplicated;
        int skipped;

        RunSummary freeze() {
            return new RunSummary(sent, failed, retried, deduplicated, skipped);
        }
    }
}
