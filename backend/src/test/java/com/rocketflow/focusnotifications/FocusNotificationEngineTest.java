package com.rocketflow.focusnotifications;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Supplier;
import java.util.concurrent.atomic.AtomicLong;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
import org.mockito.ArgumentCaptor;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.focusnotifications.FocusNotificationCandidateStore.Candidate;
import com.rocketflow.focusnotifications.FocusNotificationDeliveryStore.Delivery;
import com.rocketflow.notifications.DeviceRegistration;
import com.rocketflow.notifications.DeviceRegistrationRepository;
import com.rocketflow.notifications.FcmSender;
import com.rocketflow.notifications.NotificationProperties;
import com.rocketflow.sharing.SharingAccessService;

class FocusNotificationEngineTest {
    private final FocusNotificationCandidateStore candidateStore = org.mockito.Mockito.mock(FocusNotificationCandidateStore.class);
    private final FocusNotificationDeliveryStore deliveryStore = org.mockito.Mockito.mock(FocusNotificationDeliveryStore.class);
    private final DeviceRegistrationRepository deviceRepository = org.mockito.Mockito.mock(DeviceRegistrationRepository.class);
    private final WebPushSubscriptionRepository webRepository = org.mockito.Mockito.mock(WebPushSubscriptionRepository.class);
    private final SharingAccessService sharingAccessService = org.mockito.Mockito.mock(SharingAccessService.class);
    private final FcmSender fcmSender = org.mockito.Mockito.mock(FcmSender.class);
    private final WebPushSender webPushSender = org.mockito.Mockito.mock(WebPushSender.class);
    private final FocusNotificationLeaseHeartbeat leaseHeartbeat = org.mockito.Mockito.mock(
            FocusNotificationLeaseHeartbeat.class
    );
    private final NotificationProperties notificationProperties = new NotificationProperties();
    private final FocusNotificationProperties properties = new FocusNotificationProperties();
    private FocusNotificationEngine engine;
    private Instant now;
    private Candidate candidate;
    private UUID taskId;

    @BeforeEach
    void setUp() {
        now = Instant.parse("2026-08-09T12:25:00Z");
        engine = new FocusNotificationEngine(
                candidateStore, deliveryStore, deviceRepository, webRepository, sharingAccessService,
                fcmSender, webPushSender, notificationProperties, properties,
                Clock.fixed(now, ZoneOffset.UTC), leaseHeartbeat
        );
        candidate = new Candidate(
                UUID.randomUUID(), UUID.randomUUID(), Instant.parse("2026-08-03T21:00:00Z"),
                Instant.parse("2026-08-10T21:00:00Z"), "Europe/Moscow", 60, null, null
        );
        taskId = UUID.randomUUID();
        when(deliveryStore.claimOneDue(eq(now), any())).thenReturn(null);
        when(candidateStore.activeCandidates(now)).thenReturn(List.of(candidate));
        when(candidateStore.incompleteTaskIds(candidate.periodId())).thenReturn(List.of(taskId));
        when(sharingAccessService.requireTaskAccess(taskId, candidate.userId()))
                .thenReturn(org.mockito.Mockito.mock(SharingAccessService.TaskAccess.class));
        when(deliveryStore.mark(any(), anyString(), any(), any(), any())).thenReturn(true);
        when(deliveryStore.markAndDeactivateDevice(any(), any(), anyString())).thenReturn(true);
        when(deliveryStore.markAndDeleteWebPushSubscription(any(), any(), anyString())).thenReturn(true);
        when(leaseHeartbeat.aroundProviderCall(any(), any())).thenAnswer(invocation -> {
            Supplier<?> providerCall = invocation.getArgument(1);
            return new FocusNotificationLeaseHeartbeat.ProviderCall<>(providerCall.get(), true);
        });
    }

    @Test
    void skipsFocusWithoutVisibleIncompleteTasks() {
        when(candidateStore.incompleteTaskIds(candidate.periodId())).thenReturn(List.of());

        FocusNotificationEngine.RunSummary summary = engine.process();

        assertThat(summary.sent()).isZero();
        verify(deliveryStore, never()).claimNew(any(), any(), any(), anyString(), any(), any(), any(), any(), any());
    }

    @Test
    void cadenceLedgerPreventsDuplicateFcmDelivery() {
        notificationProperties.getFcm().setEnabled(true);
        DeviceRegistration device = device(candidate.userId());
        when(deviceRepository.findByUserIdInAndActiveTrueOrderByUserIdAscCreatedAtAsc(any()))
                .thenReturn(List.of(device));
        when(deliveryStore.claimNew(any(), eq(candidate.periodId()), eq(candidate.userId()), eq("fcm"),
                eq(device.getId()), any(), any(), eq(now), any())).thenReturn(null);

        FocusNotificationEngine.RunSummary summary = engine.process();

        assertThat(summary.deduplicated()).isEqualTo(1);
        verify(fcmSender, never()).send(any(), any());
        verify(fcmSender, never()).sendDataOnly(any(), any(), anyString(), any());
    }

    @Test
    void fcmPayloadContainsStableFocusRouteWithoutTaskNames() {
        UUID eventId = UUID.randomUUID();
        Map<String, String> payload = engine.fcmData(eventId, candidate.periodId());

        assertThat(payload).containsAllEntriesOf(Map.of(
                "type", "focus_reminder",
                "periodId", candidate.periodId().toString(),
                "eventId", eventId.toString(),
                "route", "focus"
        ));
        assertThat(payload).containsKeys("title", "body");
        assertThat(payload.get("body")).doesNotContain("task", taskId.toString());
    }

    @Test
    void fcmDeliveryUsesDataOnlyPathWithHighPriorityContract() {
        notificationProperties.getFcm().setEnabled(true);
        DeviceRegistration device = device(candidate.userId());
        when(deviceRepository.findByUserIdInAndActiveTrueOrderByUserIdAscCreatedAtAsc(any()))
                .thenReturn(List.of(device));
        when(deliveryStore.claimNew(any(), eq(candidate.periodId()), eq(candidate.userId()), eq("fcm"),
                eq(device.getId()), any(), any(), eq(now), any())).thenAnswer(this::claimedDelivery);
        when(deviceRepository.findById(device.getId())).thenReturn(Optional.of(device));
        when(fcmSender.sendDataOnly(eq(device), any(), anyString(), any()))
                .thenReturn(FcmSender.SendResult.sent("message-id"));

        FocusNotificationEngine.RunSummary summary = engine.process();

        assertThat(summary.sent()).isEqualTo(1);
        verify(fcmSender).sendDataOnly(
                eq(device),
                org.mockito.ArgumentMatchers.argThat(data ->
                        "focus_reminder".equals(data.get("type"))
                                && data.containsKey("title")
                                && data.containsKey("body")
                                && candidate.periodId().toString().equals(data.get("periodId"))
                ),
                eq("focus-" + candidate.periodId()),
                eq(Duration.ofMinutes(15))
        );
        verify(fcmSender, never()).send(any(), any());
    }

    @Test
    void expiredWebPushResponseDeactivatesSubscription() {
        properties.getWebPush().setEnabled(true);
        WebPushSubscription subscription = subscription(candidate.userId());
        when(webRepository.findDeliverable(any(), eq(now))).thenReturn(List.of(subscription));
        when(deliveryStore.claimNew(any(), eq(candidate.periodId()), eq(candidate.userId()), eq("web_push"),
                eq(subscription.getId()), any(), any(), eq(now), any())).thenAnswer(this::claimedDelivery);
        when(webRepository.findById(subscription.getId())).thenReturn(Optional.of(subscription));
        when(webPushSender.send(eq(subscription), any())).thenReturn(WebPushSender.Result.deactivate("HTTP 410"));

        FocusNotificationEngine.RunSummary summary = engine.process();

        assertThat(summary.failed()).isEqualTo(1);
        verify(deliveryStore).markAndDeleteWebPushSubscription(any(), eq(now), eq("HTTP 410"));
    }

    @Test
    void retryDeliveryIsSentAndFinalizedBeforeTheNextDeliveryIsClaimed() {
        notificationProperties.getFcm().setEnabled(true);
        DeviceRegistration device = device(candidate.userId());
        Delivery first = retryDelivery(device, 2);
        Delivery second = retryDelivery(device, 2);
        when(deliveryStore.claimOneDue(eq(now), any())).thenReturn(first, second, null);
        when(deviceRepository.findById(device.getId())).thenReturn(Optional.of(device));
        when(fcmSender.sendDataOnly(eq(device), any(), anyString(), any()))
                .thenReturn(FcmSender.SendResult.sent("message-1"), FcmSender.SendResult.sent("message-2"));
        when(candidateStore.activeCandidates(now)).thenReturn(List.of());
        when(candidateStore.activeCandidate(first.periodId(), now)).thenReturn(candidate);

        FocusNotificationEngine.RunSummary summary = engine.process();

        assertThat(summary.sent()).isEqualTo(2);
        InOrder order = inOrder(deliveryStore, fcmSender);
        order.verify(deliveryStore).claimOneDue(eq(now), any());
        order.verify(fcmSender).sendDataOnly(eq(device), any(), anyString(), any());
        order.verify(deliveryStore).mark(eq(first), eq("sent"), eq(now), isNull(), eq("message-1"));
        order.verify(deliveryStore).claimOneDue(eq(now), any());
        order.verify(fcmSender).sendDataOnly(eq(device), any(), anyString(), any());
        order.verify(deliveryStore).mark(eq(second), eq("sent"), eq(now), isNull(), eq("message-2"));
        order.verify(deliveryStore).claimOneDue(eq(now), any());
    }

    @Test
    void currentDeliveryRunsBeforeRetryBacklogAndRetryQuotaIsHonored() {
        properties.getFocus().setMaxRetriesPerPoll(2);
        notificationProperties.getFcm().setEnabled(true);
        DeviceRegistration device = device(candidate.userId());
        Delivery firstRetry = retryDelivery(device, 2);
        Delivery secondRetry = retryDelivery(device, 2);
        Delivery unclaimedRetry = retryDelivery(device, 2);
        when(deviceRepository.findByUserIdInAndActiveTrueOrderByUserIdAscCreatedAtAsc(any()))
                .thenReturn(List.of(device));
        when(deliveryStore.claimNew(any(), eq(candidate.periodId()), eq(candidate.userId()), eq("fcm"),
                eq(device.getId()), any(), any(), eq(now), any())).thenAnswer(this::claimedDelivery);
        when(deliveryStore.claimOneDue(eq(now), any())).thenReturn(firstRetry, secondRetry, unclaimedRetry);
        when(candidateStore.activeCandidate(firstRetry.periodId(), now)).thenReturn(candidate);
        when(deviceRepository.findById(device.getId())).thenReturn(Optional.of(device));
        when(fcmSender.sendDataOnly(eq(device), any(), anyString(), any()))
                .thenReturn(FcmSender.SendResult.sent("current"), FcmSender.SendResult.sent("retry-1"),
                        FcmSender.SendResult.sent("retry-2"));

        FocusNotificationEngine.RunSummary summary = engine.process();

        assertThat(summary.sent()).isEqualTo(3);
        InOrder order = inOrder(deliveryStore);
        order.verify(deliveryStore).claimNew(any(), eq(candidate.periodId()), eq(candidate.userId()), eq("fcm"),
                eq(device.getId()), any(), any(), eq(now), any());
        order.verify(deliveryStore).claimOneDue(eq(now), any());
        verify(deliveryStore, times(2)).claimOneDue(eq(now), any());
    }

    @Test
    void invalidArgumentFcmOutcomeDisablesDeviceAndTerminatesDelivery() {
        notificationProperties.getFcm().setEnabled(true);
        DeviceRegistration device = device(candidate.userId());
        when(deviceRepository.findByUserIdInAndActiveTrueOrderByUserIdAscCreatedAtAsc(any()))
                .thenReturn(List.of(device));
        when(deliveryStore.claimNew(any(), eq(candidate.periodId()), eq(candidate.userId()), eq("fcm"),
                eq(device.getId()), any(), any(), eq(now), any())).thenAnswer(this::claimedDelivery);
        when(deviceRepository.findById(device.getId())).thenReturn(Optional.of(device));
        when(fcmSender.sendDataOnly(eq(device), any(), anyString(), any()))
                .thenReturn(FcmSender.SendResult.deactivate("INVALID_ARGUMENT"));

        FocusNotificationEngine.RunSummary summary = engine.process();

        assertThat(summary.failed()).isEqualTo(1);
        assertThat(device.isActive()).isFalse();
        verify(deliveryStore).markAndDeactivateDevice(any(), eq(now), eq("INVALID_ARGUMENT"));
        verify(deliveryStore, never()).mark(any(), eq("retry"), any(), any(), any());
    }

    @Test
    void permanentFcmOutcomeIsTerminalWithoutBlindRetry() {
        notificationProperties.getFcm().setEnabled(true);
        DeviceRegistration device = device(candidate.userId());
        when(deviceRepository.findByUserIdInAndActiveTrueOrderByUserIdAscCreatedAtAsc(any()))
                .thenReturn(List.of(device));
        when(deliveryStore.claimNew(any(), eq(candidate.periodId()), eq(candidate.userId()), eq("fcm"),
                eq(device.getId()), any(), any(), eq(now), any())).thenAnswer(this::claimedDelivery);
        when(deviceRepository.findById(device.getId())).thenReturn(Optional.of(device));
        when(fcmSender.sendDataOnly(eq(device), any(), anyString(), any()))
                .thenReturn(FcmSender.SendResult.permanentFailure("INVALID_ARGUMENT"));

        FocusNotificationEngine.RunSummary summary = engine.process();

        assertThat(summary.failed()).isEqualTo(1);
        verify(deliveryStore).mark(any(), eq("failed"), eq(now), isNull(), eq("INVALID_ARGUMENT"));
        verify(deliveryStore, never()).mark(any(), eq("retry"), any(), any(), any());
    }

    @Test
    void networkIoHasNoEngineOrSchedulerTransactionBoundary() throws Exception {
        assertThat(FocusNotificationEngine.class.getMethod("process")
                .isAnnotationPresent(Transactional.class)).isFalse();
        assertThat(FocusNotificationScheduler.class.getMethod("poll")
                .isAnnotationPresent(Transactional.class)).isFalse();
        assertThat(FocusNotificationDeliveryStore.class.getDeclaredMethod(
                "claimNew", UUID.class, UUID.class, UUID.class, String.class, UUID.class,
                Instant.class, UUID.class, Instant.class, Duration.class
        ).getAnnotation(Transactional.class).propagation()).isEqualTo(Propagation.REQUIRES_NEW);
    }

    @Test
    void readsFreshClockBeforeClaimEnqueueAndFinalization() {
        FocusNotificationCandidateStore localCandidates = org.mockito.Mockito.mock(
                FocusNotificationCandidateStore.class
        );
        FocusNotificationDeliveryStore localStore = org.mockito.Mockito.mock(FocusNotificationDeliveryStore.class);
        DeviceRegistrationRepository localDevices = org.mockito.Mockito.mock(DeviceRegistrationRepository.class);
        FcmSender localSender = org.mockito.Mockito.mock(FcmSender.class);
        FocusNotificationLeaseHeartbeat localHeartbeat = org.mockito.Mockito.mock(
                FocusNotificationLeaseHeartbeat.class
        );
        AdvancingClock advancingClock = new AdvancingClock(now, Duration.ofSeconds(1));
        DeviceRegistration device = device(candidate.userId());

        when(localStore.claimOneDue(any(), any())).thenReturn(null);
        when(localCandidates.activeCandidates(any())).thenReturn(List.of(candidate));
        when(localCandidates.incompleteTaskIds(candidate.periodId())).thenReturn(List.of(taskId));
        when(localDevices.findByUserIdInAndActiveTrueOrderByUserIdAscCreatedAtAsc(any()))
                .thenReturn(List.of(device));
        when(localStore.claimNew(any(), any(), any(), anyString(), any(), any(), any(), any(), any()))
                .thenAnswer(this::claimedDelivery);
        when(localDevices.findById(device.getId())).thenReturn(Optional.of(device));
        when(localSender.sendDataOnly(any(), any(), anyString(), any()))
                .thenReturn(FcmSender.SendResult.sent("message-id"));
        when(localStore.mark(any(), anyString(), any(), any(), any())).thenReturn(true);
        when(localHeartbeat.aroundProviderCall(any(), any())).thenAnswer(invocation -> {
            Supplier<?> providerCall = invocation.getArgument(1);
            return new FocusNotificationLeaseHeartbeat.ProviderCall<>(providerCall.get(), true);
        });

        NotificationProperties localNotificationProperties = new NotificationProperties();
        localNotificationProperties.getFcm().setEnabled(true);
        FocusNotificationEngine localEngine = new FocusNotificationEngine(
                localCandidates, localStore, localDevices, webRepository, sharingAccessService,
                localSender, webPushSender, localNotificationProperties, properties,
                advancingClock, localHeartbeat
        );

        localEngine.process();

        ArgumentCaptor<Instant> retryClaimTime = ArgumentCaptor.forClass(Instant.class);
        verify(localStore).claimOneDue(retryClaimTime.capture(), any());
        ArgumentCaptor<Instant> enqueueTime = ArgumentCaptor.forClass(Instant.class);
        verify(localStore).claimNew(
                any(), any(), any(), anyString(), any(), any(), any(), enqueueTime.capture(), any()
        );
        ArgumentCaptor<Instant> finalizeTime = ArgumentCaptor.forClass(Instant.class);
        verify(localStore).mark(any(), eq("sent"), finalizeTime.capture(), isNull(), eq("message-id"));
        assertThat(retryClaimTime.getValue()).isAfter(finalizeTime.getValue());
        assertThat(finalizeTime.getValue()).isAfter(enqueueTime.getValue());
    }

    private FocusNotificationDeliveryStore.Delivery claimedDelivery(org.mockito.invocation.InvocationOnMock invocation) {
        Instant claimNow = invocation.getArgument(7);
        Duration leaseDuration = invocation.getArgument(8);
        return new FocusNotificationDeliveryStore.Delivery(
                invocation.getArgument(0),
                invocation.getArgument(1),
                invocation.getArgument(2),
                invocation.getArgument(3),
                invocation.getArgument(4),
                invocation.getArgument(5),
                invocation.getArgument(6),
                "in_flight",
                1,
                null,
                UUID.randomUUID(),
                claimNow.plus(leaseDuration)
        );
    }

    private Delivery retryDelivery(DeviceRegistration device, int attemptCount) {
        return new Delivery(
                UUID.randomUUID(), candidate.periodId(), candidate.userId(), "fcm", device.getId(), now,
                UUID.randomUUID(), "in_flight", attemptCount, null, UUID.randomUUID(), now.plusSeconds(120)
        );
    }

    private DeviceRegistration device(UUID userId) {
        DeviceRegistration device = new DeviceRegistration();
        device.setId(UUID.randomUUID());
        device.setUserId(userId);
        device.setActive(true);
        device.setPlatform("android");
        device.setPushToken("secret-token");
        return device;
    }

    private WebPushSubscription subscription(UUID userId) {
        WebPushSubscription subscription = new WebPushSubscription();
        subscription.setId(UUID.randomUUID());
        subscription.setUserId(userId);
        subscription.setActive(true);
        subscription.setEndpoint("https://push.example.test/secret");
        subscription.setP256dh("p256dh-secret");
        subscription.setAuth("auth-secret");
        return subscription;
    }

    private static final class AdvancingClock extends Clock {
        private final Instant start;
        private final Duration step;
        private final AtomicLong reads = new AtomicLong();

        private AdvancingClock(Instant start, Duration step) {
            this.start = start;
            this.step = step;
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return start.plus(step.multipliedBy(reads.getAndIncrement()));
        }
    }
}
