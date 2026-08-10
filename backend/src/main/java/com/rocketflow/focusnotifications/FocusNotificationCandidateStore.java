package com.rocketflow.focusnotifications;

import java.sql.Timestamp;
import java.time.Instant;
import java.time.LocalTime;
import java.util.List;
import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Repository;

@Repository
class FocusNotificationCandidateStore {
    private final ObjectProvider<JdbcTemplate> jdbcTemplateProvider;

    @Autowired
    FocusNotificationCandidateStore(ObjectProvider<JdbcTemplate> jdbcTemplateProvider) {
        this.jdbcTemplateProvider = jdbcTemplateProvider;
    }

    FocusNotificationCandidateStore(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplateProvider = new FixedObjectProvider<>(jdbcTemplate);
    }

    List<Candidate> activeCandidates(Instant now) {
        return jdbc().query(baseQuery() + " order by period.created_at asc", this::candidate, Timestamp.from(now), Timestamp.from(now));
    }

    Candidate activeCandidate(UUID periodId, Instant now) {
        List<Candidate> rows = jdbc().query(
                baseQuery() + " and period.id = ?",
                this::candidate,
                Timestamp.from(now), Timestamp.from(now), periodId
        );
        return rows.isEmpty() ? null : rows.getFirst();
    }

    List<UUID> incompleteTaskIds(UUID periodId) {
        return jdbc().query("""
                select item.task_id
                  from weekly_focus_items item
                  join tasks task on task.id = item.task_id
                  join goals goal on goal.id = task.goal_id
                  join folders folder on folder.id = goal.folder_id
                 where item.period_id = ? and item.history_only = false
                   and task.deleted_at is null and task.archived = false and task.status <> 'done'
                   and goal.archived = false and folder.archived = false
                 order by item.position asc
                """, (rs, row) -> rs.getObject(1, UUID.class), periodId);
    }

    private String baseQuery() {
        return """
                select period.id, period.user_id, period.starts_at, period.ends_at,
                       period.timezone_snapshot, settings.interval_minutes,
                       settings.quiet_hours_start, settings.quiet_hours_end
                  from weekly_focus_periods period
                  join focus_notification_settings settings on settings.user_id = period.user_id
                  join user_settings user_settings on user_settings.user_id = period.user_id
                 where period.status = 'active'
                   and period.starts_at <= ? and period.ends_at > ?
                   and settings.interval_minutes is not null
                   and user_settings.notifications_enabled = true
                """;
    }

    private Candidate candidate(java.sql.ResultSet rs, int row) throws java.sql.SQLException {
        return new Candidate(
                rs.getObject(1, UUID.class),
                rs.getObject(2, UUID.class),
                rs.getTimestamp(3).toInstant(),
                rs.getTimestamp(4).toInstant(),
                rs.getString(5),
                rs.getInt(6),
                rs.getObject(7, LocalTime.class),
                rs.getObject(8, LocalTime.class)
        );
    }

    private JdbcTemplate jdbc() {
        JdbcTemplate jdbcTemplate = jdbcTemplateProvider.getIfAvailable();
        if (jdbcTemplate == null) {
            throw new IllegalStateException("Focus notification candidates require a configured DataSource.");
        }
        return jdbcTemplate;
    }

    record Candidate(
            UUID periodId,
            UUID userId,
            Instant startsAt,
            Instant endsAt,
            String timezone,
            int intervalMinutes,
            LocalTime quietStart,
            LocalTime quietEnd
    ) {
    }
}
