package com.rocketflow.focusnotifications;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import com.rocketflow.focusnotifications.FocusNotificationDeliveryStore.Delivery;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;

class FocusNotificationLeaseHeartbeatTest {
    @Test
    void slowProviderCannotBeReclaimedUntilHeartbeatStopsAndLeaseExpires() throws Exception {
        try (EmbeddedPostgres postgres = EmbeddedPostgres.start()) {
            JdbcTemplate jdbc = schema(postgres);
            FocusNotificationDeliveryStore firstStore = new FocusNotificationDeliveryStore(jdbc);
            FocusNotificationDeliveryStore secondStore = new FocusNotificationDeliveryStore(jdbc);
            FocusNotificationProperties properties = new FocusNotificationProperties();
            properties.getFocus().setClaimLeaseMs(300);
            properties.getFocus().setHeartbeatIntervalMs(50);
            Clock clock = Clock.systemUTC();
            Duration lease = Duration.ofMillis(properties.getFocus().getClaimLeaseMs());
            Instant claimNow = clock.instant();
            UUID eventId = UUID.randomUUID();
            Delivery original = firstStore.claimNew(
                    UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID(), "fcm", UUID.randomUUID(),
                    claimNow, eventId, claimNow, lease
            );
            CountDownLatch providerStarted = new CountDownLatch(1);
            CountDownLatch releaseProvider = new CountDownLatch(1);

            try (FocusNotificationLeaseHeartbeat heartbeat = new FocusNotificationLeaseHeartbeat(
                    firstStore, properties, clock
            ); var providerExecutor = Executors.newSingleThreadExecutor()) {
                Future<FocusNotificationLeaseHeartbeat.ProviderCall<String>> provider = providerExecutor.submit(
                        () -> heartbeat.aroundProviderCall(original, () -> {
                            providerStarted.countDown();
                            await(releaseProvider);
                            return "accepted";
                        })
                );

                assertThat(providerStarted.await(5, TimeUnit.SECONDS)).isTrue();
                Thread.sleep(lease.toMillis() * 2);
                assertThat(secondStore.claimOneDue(clock.instant(), lease)).isNull();

                heartbeat.close();
                assertThat(heartbeat.isShutdown()).isTrue();
                Delivery recovered = awaitRecovery(secondStore, clock, lease);
                assertThat(recovered.id()).isEqualTo(original.id());
                assertThat(recovered.eventId()).isEqualTo(eventId);
                assertThat(recovered.leaseToken()).isNotEqualTo(original.leaseToken());

                releaseProvider.countDown();
                FocusNotificationLeaseHeartbeat.ProviderCall<String> completed = provider.get(5, TimeUnit.SECONDS);
                assertThat(completed.value()).isEqualTo("accepted");
                assertThat(completed.leaseOwned()).isFalse();
            }
        }
    }

    private Delivery awaitRecovery(
            FocusNotificationDeliveryStore store,
            Clock clock,
            Duration lease
    ) throws InterruptedException {
        Instant deadline = clock.instant().plusSeconds(5);
        Delivery recovered;
        do {
            recovered = store.claimOneDue(clock.instant(), lease);
            if (recovered != null) {
                return recovered;
            }
            Thread.sleep(25);
        } while (clock.instant().isBefore(deadline));
        throw new AssertionError("The delivery lease did not expire after the heartbeat stopped.");
    }

    private void await(CountDownLatch latch) {
        try {
            latch.await();
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("The simulated provider call was interrupted.", exception);
        }
    }

    private JdbcTemplate schema(EmbeddedPostgres postgres) {
        JdbcTemplate jdbc = new JdbcTemplate(postgres.getPostgresDatabase());
        jdbc.execute("""
                create table focus_notification_deliveries (
                    id uuid primary key, period_id uuid not null, user_id uuid not null,
                    channel varchar(16) not null, target_id uuid not null,
                    cadence_bucket timestamptz not null, event_id uuid not null unique,
                    status varchar(32) not null, attempt_count integer not null,
                    next_attempt_at timestamptz, attempted_at timestamptz,
                    lease_token uuid, lease_expires_at timestamptz,
                    provider_response varchar(2000), created_at timestamptz not null,
                    updated_at timestamptz not null,
                    unique(period_id, channel, target_id, cadence_bucket)
                )
                """);
        jdbc.execute("""
                create unique index focus_notification_deliveries_target_unresolved_uq
                    on focus_notification_deliveries (period_id, channel, target_id)
                    where status in ('in_flight', 'retry')
                """);
        jdbc.execute("""
                create unique index focus_notification_deliveries_lease_token_uq
                    on focus_notification_deliveries (lease_token)
                    where lease_token is not null
                """);
        return jdbc;
    }
}
