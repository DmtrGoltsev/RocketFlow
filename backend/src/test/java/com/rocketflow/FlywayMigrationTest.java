package com.rocketflow;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;

import javax.sql.DataSource;

import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;

class FlywayMigrationTest {

    @Test
    void appliesBaselineMigrationToPostgres() throws Exception {
        try (EmbeddedPostgres postgres = EmbeddedPostgres.start()) {
            DataSource dataSource = postgres.getPostgresDatabase();

            Flyway.configure()
                    .dataSource(dataSource)
                    .locations("classpath:db/migration")
                    .load()
                    .migrate();

            try (Connection connection = dataSource.getConnection();
                 Statement statement = connection.createStatement()) {
                assertEquals(1, count(statement, "select count(*) from information_schema.tables where table_name = 'users'"));
                assertEquals(1, count(statement, "select count(*) from information_schema.tables where table_name = 'user_credentials'"));
                assertEquals(1, count(statement, "select count(*) from information_schema.tables where table_name = 'user_settings'"));
            }
        }
    }

    private int count(Statement statement, String sql) throws Exception {
        try (ResultSet resultSet = statement.executeQuery(sql)) {
            resultSet.next();
            return resultSet.getInt(1);
        }
    }
}
