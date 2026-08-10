package com.rocketflow.focusnotifications;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;

import com.rocketflow.focusnotifications.FocusNotificationDeliveryStore.Delivery;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;

class FocusNotificationDeliveryStoreTest {
    @Test
    void committedClaimKeepsStableEventAcrossRetryAndSuppressesNewBucket() throws Exception {
        try (EmbeddedPostgres postgres = EmbeddedPostgres.start()) {
            JdbcTemplate jdbc = schema(postgres);
            FocusNotificationDeliveryStore store = new FocusNotificationDeliveryStore(jdbc);
            UUID periodId = UUID.randomUUID();
            UUID userId = UUID.randomUUID();
            UUID targetId = UUID.randomUUID();
            UUID eventId = UUID.randomUUID();
            Instant now = Instant.parse("2026-08-09T12:00:00Z");

            Delivery first = store.claimNew(
                    UUID.randomUUID(), periodId, userId, "fcm", targetId, now, eventId, now, Duration.ofMinutes(2)
            );

            assertThat(first).isNotNull();
            assertThat(jdbc.queryForObject(
                    "select event_id from focus_notification_deliveries where id = ?",
                    UUID.class,
                    first.id()
            )).isEqualTo(eventId);
            assertThat(store.claimNew(
                    UUID.randomUUID(), periodId, userId, "fcm", targetId, now.plusSeconds(60),
                    UUID.randomUUID(), now, Duration.ofMinutes(2)
            )).isNull();

            Instant retryAt = now.plusSeconds(45);
            assertThat(store.mark(first, "retry", now, retryAt, "temporary")).isTrue();
            assertThat(store.claimNew(
                    UUID.randomUUID(), periodId, userId, "fcm", targetId, now.plusSeconds(60),
                    UUID.randomUUID(), now, Duration.ofMinutes(2)
            )).isNull();
            Delivery retry = store.claimOneDue(retryAt, Duration.ofMinutes(2));

            assertThat(retry).isNotNull();
            assertThat(retry.id()).isEqualTo(first.id());
            assertThat(retry.eventId()).isEqualTo(eventId);
            assertThat(retry.attemptCount()).isEqualTo(2);
            assertThat(retry.leaseToken()).isNotEqualTo(first.leaseToken());
            assertThat(store.mark(retry, "sent", retryAt, null, "accepted")).isTrue();
            assertThat(store.claimNew(
                    UUID.randomUUID(), periodId, userId, "fcm", targetId, now.plusSeconds(60),
                    UUID.randomUUID(), retryAt, Duration.ofMinutes(2)
            )).isNotNull();
        }
    }

    @Test
    void expiredLeaseRecoversCrashWithTheSameEventId() throws Exception {
        try (EmbeddedPostgres postgres = EmbeddedPostgres.start()) {
            JdbcTemplate jdbc = schema(postgres);
            FocusNotificationDeliveryStore store = new FocusNotificationDeliveryStore(jdbc);
            Instant now = Instant.parse("2026-08-09T12:00:00Z");
            UUID eventId = UUID.randomUUID();
            Delivery claimed = store.claimNew(
                    UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID(), "web_push", UUID.randomUUID(),
                    now, eventId, now, Duration.ofMinutes(2)
            );

            assertThat(store.claimOneDue(now.plusSeconds(119), Duration.ofMinutes(2))).isNull();
            Delivery recovered = store.claimOneDue(now.plusSeconds(120), Duration.ofMinutes(2));
            assertThat(recovered).isNotNull();
            assertThat(recovered.id()).isEqualTo(claimed.id());
            assertThat(recovered.eventId()).isEqualTo(eventId);
            assertThat(recovered.attemptCount()).isEqualTo(2);
        }
    }

    @Test
    void oneAtATimeClaimNeverPreLeasesTheQueuedLateDelivery() throws Exception {
        try (EmbeddedPostgres postgres = EmbeddedPostgres.start()) {
            JdbcTemplate jdbc = schema(postgres);
            FocusNotificationDeliveryStore firstInstance = new FocusNotificationDeliveryStore(jdbc);
            FocusNotificationDeliveryStore secondInstance = new FocusNotificationDeliveryStore(jdbc);
            Instant now = Instant.parse("2026-08-09T12:00:00Z");
            Delivery first = retryable(firstInstance, now, UUID.randomUUID());
            Delivery second = retryable(firstInstance, now, UUID.randomUUID());

            Delivery firstClaim = firstInstance.claimOneDue(now, Duration.ofMinutes(2));
            UUID queuedId = firstClaim.id().equals(first.id()) ? second.id() : first.id();

            assertThat(jdbc.queryForObject(
                    "select status from focus_notification_deliveries where id = ?", String.class, queuedId
            )).isEqualTo("retry");
            assertThat(jdbc.queryForObject(
                    "select lease_token is null from focus_notification_deliveries where id = ?", Boolean.class, queuedId
            )).isTrue();

            Delivery secondClaim = secondInstance.claimOneDue(now.plusSeconds(121), Duration.ofMinutes(2));
            assertThat(secondClaim.id()).isEqualTo(queuedId);
            assertThat(secondClaim.attemptCount()).isEqualTo(2);
        }
    }

    @Test
    void concurrentClaimsProduceOnlyOneUnresolvedDeliveryPerTarget() throws Exception {
        try (EmbeddedPostgres postgres = EmbeddedPostgres.start()) {
            JdbcTemplate jdbc = schema(postgres);
            FocusNotificationDeliveryStore store = new FocusNotificationDeliveryStore(jdbc);
            UUID periodId = UUID.randomUUID();
            UUID userId = UUID.randomUUID();
            UUID targetId = UUID.randomUUID();
            Instant now = Instant.parse("2026-08-09T12:00:00Z");
            CountDownLatch ready = new CountDownLatch(2);
            CountDownLatch start = new CountDownLatch(1);

            try (var executor = Executors.newFixedThreadPool(2)) {
                Future<Delivery> first = executor.submit(() -> claimAfterLatch(
                        store, ready, start, periodId, userId, targetId, now
                ));
                Future<Delivery> second = executor.submit(() -> claimAfterLatch(
                        store, ready, start, periodId, userId, targetId, now.plusSeconds(60)
                ));
                ready.await();
                start.countDown();

                assertThat(java.util.stream.Stream.of(first.get(), second.get()).filter(java.util.Objects::nonNull))
                        .hasSize(1);
            }
        }
    }

    @Test
    void renewedLeaseCannotBeReclaimedByASecondInstance() throws Exception {
        try (EmbeddedPostgres postgres = EmbeddedPostgres.start()) {
            JdbcTemplate jdbc = schema(postgres);
            FocusNotificationDeliveryStore firstInstance = new FocusNotificationDeliveryStore(jdbc);
            FocusNotificationDeliveryStore secondInstance = new FocusNotificationDeliveryStore(jdbc);
            Duration lease = Duration.ofMinutes(2);
            Instant now = Instant.parse("2026-08-09T12:00:00Z");
            Delivery claimed = firstInstance.claimNew(
                    UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID(), "fcm", UUID.randomUUID(),
                    now, UUID.randomUUID(), now, lease
            );

            assertThat(firstInstance.renewLease(claimed, now.plusSeconds(119), lease)).isTrue();
            assertThat(secondInstance.claimOneDue(now.plusSeconds(121), lease)).isNull();
            Delivery recovered = secondInstance.claimOneDue(now.plusSeconds(239), lease);
            assertThat(recovered).isNotNull();
            assertThat(recovered.id()).isEqualTo(claimed.id());
            assertThat(recovered.eventId()).isEqualTo(claimed.eventId());
        }
    }

    private Delivery claimAfterLatch(
            FocusNotificationDeliveryStore store,
            CountDownLatch ready,
            CountDownLatch start,
            UUID periodId,
            UUID userId,
            UUID targetId,
            Instant bucket
    ) throws InterruptedException {
        ready.countDown();
        start.await();
        return store.claimNew(
                UUID.randomUUID(), periodId, userId, "web_push", targetId, bucket,
                UUID.randomUUID(), bucket, Duration.ofMinutes(2)
        );
    }

    private Delivery retryable(FocusNotificationDeliveryStore store, Instant now, UUID targetId) {
        Delivery delivery = store.claimNew(
                UUID.randomUUID(), UUID.randomUUID(), UUID.randomUUID(), "web_push", targetId,
                now, UUID.randomUUID(), now, Duration.ofMinutes(2)
        );
        assertThat(store.mark(delivery, "retry", now, now, "temporary")).isTrue();
        return delivery;
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
