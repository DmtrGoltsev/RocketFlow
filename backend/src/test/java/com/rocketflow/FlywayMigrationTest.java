package com.rocketflow;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.UUID;

import javax.sql.DataSource;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;

class FlywayMigrationTest {

    @Test
    void appliesV1ThroughV22ToPostgres() throws Exception {
        try (EmbeddedPostgres postgres = EmbeddedPostgres.start()) {
            DataSource dataSource = postgres.getPostgresDatabase();
            Flyway flyway = flyway(dataSource);

            flyway.migrate();

            try (Connection connection = dataSource.getConnection();
                 Statement statement = connection.createStatement()) {
                assertEquals(22, count(statement, "select count(*) from flyway_schema_history where success"));
                assertEquals("22", flyway.info().current().getVersion().getVersion());
                assertV21CompatibilityMetadata(statement);
                assertDevicePlatformConstraint(statement);
            }
        }
    }

    @Test
    void upgradesV20ToLatestWithoutChangingHistoricalPriorityData() throws Exception {
        try (EmbeddedPostgres postgres = EmbeddedPostgres.start()) {
            DataSource dataSource = postgres.getPostgresDatabase();
            Flyway.configure()
                    .dataSource(dataSource)
                    .locations("classpath:db/migration")
                    .target("20")
                    .load()
                    .migrate();

            UUID userId = UUID.randomUUID();
            UUID folderId = UUID.randomUUID();
            UUID goalId = UUID.randomUUID();
            UUID taskId = UUID.randomUUID();
            try (Connection connection = dataSource.getConnection();
                 Statement statement = connection.createStatement()) {
                statement.executeUpdate("""
                        insert into users (id, email, display_name, timezone, active, created_at, updated_at)
                        values ('%s', 'v20@example.com', 'V20', 'UTC', true, now(), now())
                        """.formatted(userId));
                statement.executeUpdate("""
                        insert into user_settings (
                            user_id, language, notifications_enabled,
                            green_priority_decay_enabled, green_priority_decay_threshold, green_priority_decay_amount,
                            red_priority_decay_enabled, red_priority_decay_threshold, red_priority_decay_amount,
                            created_at, updated_at
                        ) values ('%s', 'en', true, true, 'month', 4, true, 'day', 3, now(), now())
                        """.formatted(userId));
                statement.executeUpdate("""
                        insert into folders (id, owner_user_id, name, description, display_order, archived, created_at, updated_at)
                        values ('%s', '%s', 'Folder', null, 1, false, now(), now())
                        """.formatted(folderId, userId));
                statement.executeUpdate("""
                        insert into goals (id, folder_id, owner_user_id, name, description, status, archived, created_at, updated_at)
                        values ('%s', '%s', '%s', 'Goal', null, 'todo', false, now(), now())
                        """.formatted(goalId, folderId, userId));
                statement.executeUpdate("""
                        insert into tasks (
                            id, goal_id, owner_user_id, creator_user_id, title, description, type, priority, effort,
                            status, planned_time, due_time, completed_at, archived, deleted_at, created_at, updated_at
                        ) values (
                            '%s', '%s', '%s', '%s', 'Historical', null, 'green', 9, 2,
                            'todo', '2026-08-20T09:00:00Z', null, null, false, null, now(), now()
                        )
                        """.formatted(taskId, goalId, userId, userId));
                statement.executeUpdate("""
                        insert into task_reschedule_events (
                            id, task_id, rescheduled_by_user_id, previous_planned_time, new_planned_time,
                            priority_before, priority_after, priority_decay_applied, created_at
                        ) values (
                            '%s', '%s', '%s', '2026-08-20T09:00:00Z', '2026-08-20T10:00:00Z',
                            9, 8, true, now()
                        )
                        """.formatted(UUID.randomUUID(), taskId, userId));
            }

            Flyway flyway = flyway(dataSource);
            flyway.migrate();

            try (Connection connection = dataSource.getConnection();
                 Statement statement = connection.createStatement()) {
                assertEquals(22, count(statement, "select count(*) from flyway_schema_history where success"));
                assertEquals(9, count(statement, "select priority from tasks where id = '" + taskId + "'"));
                assertEquals(9, count(statement, "select priority_before from task_reschedule_events where task_id = '" + taskId + "'"));
                assertEquals(8, count(statement, "select priority_after from task_reschedule_events where task_id = '" + taskId + "'"));
                assertEquals(1, count(statement, "select count(*) from task_reschedule_events where task_id = '" + taskId + "' and priority_decay_applied"));
                assertEquals(1, count(statement, "select count(*) from user_settings where user_id = '" + userId + "' and green_priority_decay_enabled and green_priority_decay_threshold = 'month' and green_priority_decay_amount = 4 and red_priority_decay_enabled and red_priority_decay_threshold = 'day' and red_priority_decay_amount = 3"));
                assertV21CompatibilityMetadata(statement);
                assertDevicePlatformConstraint(statement);
            }
        }
    }

    @Test
    void upgradesV21ToV22WithoutBreakingAndroidAndAcceptsIos() throws Exception {
        try (EmbeddedPostgres postgres = EmbeddedPostgres.start()) {
            DataSource dataSource = postgres.getPostgresDatabase();
            Flyway.configure()
                    .dataSource(dataSource)
                    .locations("classpath:db/migration")
                    .target("21")
                    .load()
                    .migrate();

            UUID userId = UUID.randomUUID();
            UUID androidDeviceId = UUID.randomUUID();
            try (Connection connection = dataSource.getConnection();
                 Statement statement = connection.createStatement()) {
                statement.executeUpdate("""
                        insert into users (id, email, display_name, timezone, active, created_at, updated_at)
                        values ('%s', 'devices@example.com', 'Devices', 'UTC', true, now(), now())
                        """.formatted(userId));
                statement.executeUpdate("""
                        insert into device_registrations (
                            id, user_id, push_token, device_name, platform, active, created_at, updated_at
                        ) values ('%s', '%s', 'android-token', 'Android', 'android', true, now(), now())
                        """.formatted(androidDeviceId, userId));
            }

            Flyway flyway = flyway(dataSource);
            flyway.migrate();

            try (Connection connection = dataSource.getConnection();
                 Statement statement = connection.createStatement()) {
                assertEquals("22", flyway.info().current().getVersion().getVersion());
                assertEquals(1, count(statement, "select count(*) from device_registrations where id = '"
                        + androidDeviceId + "' and platform = 'android'"));
                statement.executeUpdate("""
                        insert into device_registrations (
                            id, user_id, push_token, device_name, platform, active, created_at, updated_at
                        ) values ('%s', '%s', 'ios-token', 'iPhone', 'ios', true, now(), now())
                        """.formatted(UUID.randomUUID(), userId));
                assertEquals(1, count(statement,
                        "select count(*) from device_registrations where push_token = 'ios-token' and platform = 'ios'"));
                assertThrows(java.sql.SQLException.class, () -> statement.executeUpdate("""
                        insert into device_registrations (
                            id, user_id, push_token, device_name, platform, active, created_at, updated_at
                        ) values ('%s', '%s', 'unsupported-token', 'Other', 'windows', true, now(), now())
                        """.formatted(UUID.randomUUID(), userId)));
                assertDevicePlatformConstraint(statement);
            }
        }
    }

    private Flyway flyway(DataSource dataSource) {
        return Flyway.configure()
                .dataSource(dataSource)
                .locations("classpath:db/migration")
                .load();
    }

    private void assertV21CompatibilityMetadata(Statement statement) throws Exception {
        assertEquals("5", value(statement, "select column_default from information_schema.columns where table_name = 'tasks' and column_name = 'priority'"));
        assertEquals("5", value(statement, "select column_default from information_schema.columns where table_name = 'task_reschedule_events' and column_name = 'priority_before'"));
        assertEquals("5", value(statement, "select column_default from information_schema.columns where table_name = 'task_reschedule_events' and column_name = 'priority_after'"));
        assertEquals("false", value(statement, "select column_default from information_schema.columns where table_name = 'user_settings' and column_name = 'green_priority_decay_enabled'"));
        assertEquals("false", value(statement, "select column_default from information_schema.columns where table_name = 'user_settings' and column_name = 'red_priority_decay_enabled'"));

        assertEquals(3, count(statement, """
                select count(*) from information_schema.columns
                where (table_name, column_name) in (
                    ('tasks', 'priority'),
                    ('task_reschedule_events', 'priority_before'),
                    ('task_reschedule_events', 'priority_after')
                ) and is_nullable = 'NO'
                """));
        assertEquals(3, count(statement, """
                select count(*) from pg_constraint
                where conname in (
                    'tasks_priority_chk',
                    'task_reschedule_events_priority_before_chk',
                    'task_reschedule_events_priority_after_chk'
                )
                """));
        assertEquals(4, count(statement, """
                select count(*) from pg_indexes
                where indexname in (
                    'tasks_goal_id_idx',
                    'tasks_owner_user_id_idx',
                    'tasks_planned_time_idx',
                    'tasks_creator_user_id_idx'
                )
                """));
    }

    private void assertDevicePlatformConstraint(Statement statement) throws Exception {
        assertEquals(1, count(statement, """
                select count(*) from pg_constraint
                where conname = 'device_registrations_platform_chk'
                  and pg_get_constraintdef(oid) like '%android%'
                  and pg_get_constraintdef(oid) like '%ios%'
                """));
    }

    private int count(Statement statement, String sql) throws Exception {
        try (ResultSet resultSet = statement.executeQuery(sql)) {
            resultSet.next();
            return resultSet.getInt(1);
        }
    }

    private String value(Statement statement, String sql) throws Exception {
        try (ResultSet resultSet = statement.executeQuery(sql)) {
            resultSet.next();
            return resultSet.getString(1);
        }
    }
}
