package com.rocketflow.focusnotifications;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@Repository
public class FocusNotificationDeliveryStore {
    private final ObjectProvider<JdbcTemplate> jdbcTemplateProvider;

    @Autowired
    FocusNotificationDeliveryStore(ObjectProvider<JdbcTemplate> jdbcTemplateProvider) {
        this.jdbcTemplateProvider = jdbcTemplateProvider;
    }

    FocusNotificationDeliveryStore(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplateProvider = new FixedObjectProvider<>(jdbcTemplate);
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public Delivery claimNew(
            UUID id,
            UUID periodId,
            UUID userId,
            String channel,
            UUID targetId,
            Instant cadenceBucket,
            UUID eventId,
            Instant now,
            Duration leaseDuration
    ) {
        UUID leaseToken = UUID.randomUUID();
        List<Delivery> claimed = jdbc().query("""
                insert into focus_notification_deliveries(
                    id, period_id, user_id, channel, target_id, cadence_bucket, event_id,
                    status, attempt_count, attempted_at, lease_token, lease_expires_at,
                    created_at, updated_at
                ) values (?, ?, ?, ?, ?, ?, ?, 'in_flight', 1, ?, ?, ?, ?, ?)
                on conflict do nothing
                returning id, period_id, user_id, channel, target_id, cadence_bucket,
                          event_id, status, attempt_count, next_attempt_at,
                          lease_token, lease_expires_at
                """, (rs, row) -> mapDelivery(rs),
                id, periodId, userId, channel, targetId, Timestamp.from(cadenceBucket), eventId,
                Timestamp.from(now), leaseToken, Timestamp.from(now.plus(leaseDuration)),
                Timestamp.from(now), Timestamp.from(now)
        );
        return claimed.isEmpty() ? null : claimed.getFirst();
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public Delivery claimOneDue(Instant now, Duration leaseDuration) {
        UUID leaseToken = UUID.randomUUID();
        Timestamp timestamp = Timestamp.from(now);
        List<Delivery> claimed = jdbc().query("""
                with due as (
                    select id
                      from focus_notification_deliveries
                     where (status = 'retry' and next_attempt_at <= ?)
                        or (status = 'in_flight' and lease_expires_at <= ?)
                     order by coalesce(next_attempt_at, lease_expires_at) asc, created_at asc, id asc
                     for update skip locked
                     limit 1
                )
                update focus_notification_deliveries delivery
                   set status = 'in_flight',
                       attempt_count = delivery.attempt_count + 1,
                       attempted_at = ?,
                       next_attempt_at = null,
                       lease_token = ?,
                       lease_expires_at = ?,
                       updated_at = ?
                  from due
                 where delivery.id = due.id
                returning delivery.id, delivery.period_id, delivery.user_id, delivery.channel,
                          delivery.target_id, delivery.cadence_bucket, delivery.event_id,
                          delivery.status, delivery.attempt_count, delivery.next_attempt_at,
                          delivery.lease_token, delivery.lease_expires_at
                """, (rs, row) -> mapDelivery(rs),
                timestamp, timestamp, timestamp, leaseToken,
                Timestamp.from(now.plus(leaseDuration)), timestamp
        );
        return claimed.isEmpty() ? null : claimed.getFirst();
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public boolean renewLease(Delivery delivery, Instant now, Duration leaseDuration) {
        return jdbc().update("""
                update focus_notification_deliveries
                   set lease_expires_at = ?, updated_at = ?
                 where id = ? and status = 'in_flight' and lease_token = ?
                """,
                Timestamp.from(now.plus(leaseDuration)),
                Timestamp.from(now),
                delivery.id(),
                delivery.leaseToken()
        ) == 1;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public boolean mark(
            Delivery delivery,
            String status,
            Instant now,
            Instant nextAttemptAt,
            String providerResponse
    ) {
        return jdbc().update("""
                update focus_notification_deliveries
                   set status = ?, next_attempt_at = ?, provider_response = ?,
                       lease_token = null, lease_expires_at = null, updated_at = ?
                 where id = ? and status = 'in_flight' and lease_token = ?
                """,
                status,
                nextAttemptAt == null ? null : Timestamp.from(nextAttemptAt),
                truncate(providerResponse),
                Timestamp.from(now),
                delivery.id(),
                delivery.leaseToken()
        ) == 1;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public boolean deferWithoutAttempt(Delivery delivery, Instant now, Instant nextAttemptAt, String reason) {
        return jdbc().update("""
                update focus_notification_deliveries
                   set status = 'retry', attempt_count = greatest(attempt_count - 1, 0),
                       next_attempt_at = ?, provider_response = ?,
                       lease_token = null, lease_expires_at = null, updated_at = ?
                 where id = ? and status = 'in_flight' and lease_token = ?
                """,
                Timestamp.from(nextAttemptAt), truncate(reason), Timestamp.from(now),
                delivery.id(), delivery.leaseToken()
        ) == 1;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public boolean markAndDeactivateDevice(
            Delivery delivery,
            Instant now,
            String providerResponse
    ) {
        if (!markInCurrentTransaction(delivery, "device_inactive", now, null, providerResponse)) {
            return false;
        }
        jdbc().update("""
                update device_registrations
                   set active = false, updated_at = ?
                 where id = ? and user_id = ?
                """, Timestamp.from(now), delivery.targetId(), delivery.userId());
        return true;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public boolean markAndDeleteWebPushSubscription(
            Delivery delivery,
            Instant now,
            String providerResponse
    ) {
        if (!markInCurrentTransaction(delivery, "subscription_inactive", now, null, providerResponse)) {
            return false;
        }
        jdbc().update("""
                delete from web_push_subscriptions
                 where id = ? and user_id = ?
                """, delivery.targetId(), delivery.userId());
        return true;
    }

    private boolean markInCurrentTransaction(
            Delivery delivery,
            String status,
            Instant now,
            Instant nextAttemptAt,
            String providerResponse
    ) {
        return jdbc().update("""
                update focus_notification_deliveries
                   set status = ?, next_attempt_at = ?, provider_response = ?,
                       lease_token = null, lease_expires_at = null, updated_at = ?
                 where id = ? and status = 'in_flight' and lease_token = ?
                """,
                status,
                nextAttemptAt == null ? null : Timestamp.from(nextAttemptAt),
                truncate(providerResponse),
                Timestamp.from(now),
                delivery.id(),
                delivery.leaseToken()
        ) == 1;
    }

    private Delivery mapDelivery(ResultSet rs) throws SQLException {
        return new Delivery(
                rs.getObject(1, UUID.class),
                rs.getObject(2, UUID.class),
                rs.getObject(3, UUID.class),
                rs.getString(4),
                rs.getObject(5, UUID.class),
                rs.getTimestamp(6).toInstant(),
                rs.getObject(7, UUID.class),
                rs.getString(8),
                rs.getInt(9),
                instant(rs, 10),
                rs.getObject(11, UUID.class),
                instant(rs, 12)
        );
    }

    private Instant instant(ResultSet rs, int column) throws SQLException {
        Timestamp timestamp = rs.getTimestamp(column);
        return timestamp == null ? null : timestamp.toInstant();
    }

    private String truncate(String value) {
        if (value == null || value.length() <= 2_000) {
            return value;
        }
        return value.substring(0, 2_000);
    }

    private JdbcTemplate jdbc() {
        JdbcTemplate jdbcTemplate = jdbcTemplateProvider.getIfAvailable();
        if (jdbcTemplate == null) {
            throw new IllegalStateException("Focus notification storage requires a configured DataSource.");
        }
        return jdbcTemplate;
    }

    public record Delivery(
            UUID id,
            UUID periodId,
            UUID userId,
            String channel,
            UUID targetId,
            Instant cadenceBucket,
            UUID eventId,
            String status,
            int attemptCount,
            Instant nextAttemptAt,
            UUID leaseToken,
            Instant leaseExpiresAt
    ) {
    }
}
