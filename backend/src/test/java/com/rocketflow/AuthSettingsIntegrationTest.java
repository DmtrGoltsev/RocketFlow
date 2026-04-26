package com.rocketflow;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;

@SpringBootTest
@AutoConfigureMockMvc
class AuthSettingsIntegrationTest {

    private static final EmbeddedPostgres POSTGRES = startPostgres();

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @DynamicPropertySource
    static void configureDatasource(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", () -> POSTGRES.getJdbcUrl("postgres", "postgres"));
        registry.add("spring.datasource.username", () -> "postgres");
        registry.add("spring.datasource.password", () -> "postgres");
    }

    @BeforeEach
    void cleanDatabase() throws Exception {
        try (var connection = POSTGRES.getPostgresDatabase().getConnection();
             var statement = connection.createStatement()) {
            statement.executeUpdate("truncate table auth_sessions, user_settings, user_credentials, users cascade");
        }
    }

    @AfterAll
    static void shutdown() throws Exception {
        POSTGRES.close();
    }

    @Test
    void registerAndReadSettingsFlowWorks() throws Exception {
        String response = mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "user@example.com",
                                  "password": "strong-password",
                                  "displayName": "Dmitry",
                                  "timezone": "Europe/Moscow",
                                  "language": "ru"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.user.email").value("user@example.com"))
                .andExpect(jsonPath("$.user.language").value("ru"))
                .andExpect(jsonPath("$.tokens.accessToken").isNotEmpty())
                .andReturn()
                .getResponse()
                .getContentAsString();

        String accessToken = read(response, "/tokens/accessToken");

        mockMvc.perform(get("/api/me")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.email").value("user@example.com"))
                .andExpect(jsonPath("$.timezone").value("Europe/Moscow"))
                .andExpect(jsonPath("$.language").value("ru"));

        mockMvc.perform(get("/api/me/settings")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.language").value("ru"))
                .andExpect(jsonPath("$.greenPriorityDecayPolicy.thresholdPreset").value("day"))
                .andExpect(jsonPath("$.redPriorityDecayPolicy.thresholdPreset").value("week"));
    }

    @Test
    void loginRefreshAndUpdateSettingsFlowWorks() throws Exception {
        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "user@example.com",
                                  "password": "strong-password",
                                  "displayName": "Dmitry",
                                  "timezone": "Europe/Moscow",
                                  "language": "ru"
                                }
                                """))
                .andExpect(status().isCreated());

        String loginResponse = mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "user@example.com",
                                  "password": "strong-password"
                                }
                                """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.tokens.accessToken").isNotEmpty())
                .andExpect(jsonPath("$.tokens.refreshToken").isNotEmpty())
                .andReturn()
                .getResponse()
                .getContentAsString();

        String accessToken = read(loginResponse, "/tokens/accessToken");
        String refreshToken = read(loginResponse, "/tokens/refreshToken");

        String settingsResponse = mockMvc.perform(get("/api/me/settings")
                        .header("Authorization", "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        long version = Long.parseLong(read(settingsResponse, "/version"));

        mockMvc.perform(patch("/api/me/settings")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "language": "en",
                                  "greenPriorityDecayPolicy": {
                                    "enabled": true,
                                    "thresholdPreset": "month",
                                    "decayAmount": 1
                                  },
                                  "redPriorityDecayPolicy": {
                                    "enabled": false,
                                    "thresholdPreset": "week",
                                    "decayAmount": 2
                                  },
                                  "notificationsEnabled": false,
                                  "version": %d
                                }
                                """.formatted(version)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.language").value("en"))
                .andExpect(jsonPath("$.notificationsEnabled").value(false))
                .andExpect(jsonPath("$.greenPriorityDecayPolicy.thresholdPreset").value("month"))
                .andExpect(jsonPath("$.redPriorityDecayPolicy.enabled").value(false))
                .andExpect(jsonPath("$.redPriorityDecayPolicy.decayAmount").value(2));

        mockMvc.perform(post("/api/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "refreshToken": "%s"
                                }
                                """.formatted(refreshToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.tokens.accessToken").isNotEmpty())
                .andExpect(jsonPath("$.tokens.refreshToken").isNotEmpty());
    }

    private String read(String json, String path) throws Exception {
        JsonNode root = objectMapper.readTree(json);
        JsonNode value = root.at(path);
        return value.isTextual() ? value.asText() : value.toString();
    }

    private static EmbeddedPostgres startPostgres() {
        try {
            return EmbeddedPostgres.start();
        } catch (Exception exception) {
            throw new IllegalStateException("Failed to start embedded PostgreSQL", exception);
        }
    }
}
