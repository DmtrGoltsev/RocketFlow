package com.rocketflow;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.clearInvocations;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.http.MediaType;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.rocketflow.notifications.DeviceRegistration;
import com.rocketflow.notifications.DeviceRegistrationRepository;
import com.rocketflow.notifications.FcmSender;
import com.rocketflow.notifications.NotificationDelivery;
import com.rocketflow.notifications.NotificationDeliveryRepository;
import com.rocketflow.notifications.NotificationDeliveryService;
import com.rocketflow.notifications.NotificationPayload;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;

@SpringBootTest
@AutoConfigureMockMvc
class NotificationDeliveryIntegrationTest {

    private static final EmbeddedPostgres POSTGRES = startPostgres();

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private DeviceRegistrationRepository deviceRegistrationRepository;

    @Autowired
    private NotificationDeliveryRepository notificationDeliveryRepository;

    @Autowired
    private NotificationDeliveryService notificationDeliveryService;

    @Autowired
    private TestFcmSender testFcmSender;

    @DynamicPropertySource
    static void configureDatasource(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", () -> POSTGRES.getJdbcUrl("postgres", "postgres"));
        registry.add("spring.datasource.username", () -> "postgres");
        registry.add("spring.datasource.password", () -> "postgres");
        registry.add("rocketflow.notifications.scheduler.enabled", () -> false);
    }

    @BeforeEach
    void cleanDatabase() throws Exception {
        testFcmSender.reset();
        clearInvocations(testFcmSender);
        try (var connection = POSTGRES.getPostgresDatabase().getConnection();
             var statement = connection.createStatement()) {
            statement.executeUpdate("""
                    truncate table
                        notification_deliveries,
                        device_registrations,
                        task_reminder_rules,
                        task_recurrence_rules,
                        task_shares,
                        goal_shares,
                        share_invitations,
                        task_tag_links,
                        task_tags,
                        tasks,
                        goals,
                        folders,
                        auth_sessions,
                        user_settings,
                        user_credentials,
                        users cascade
                    """);
        }
    }

    @AfterAll
    static void shutdown() throws Exception {
        POSTGRES.close();
    }

    @Test
    void deviceRegistrationUpsertsDuplicateTokenAndDeletionIsOwnerScoped() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        Session otherUser = registerAndLogin("other@example.com", "Other");

        String firstRegistration = mockMvc.perform(post("/api/devices")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "platform": "android",
                                  "pushToken": "shared-token",
                                  "deviceName": "Pixel 8"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.platform").value("android"))
                .andExpect(jsonPath("$.deviceName").value("Pixel 8"))
                .andReturn()
                .getResponse()
                .getContentAsString();
        String deviceId = read(firstRegistration, "/id");

        mockMvc.perform(post("/api/devices")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "platform": "android",
                                  "pushToken": "shared-token",
                                  "deviceName": "Pixel 8 Pro"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(deviceId))
                .andExpect(jsonPath("$.deviceName").value("Pixel 8 Pro"));

        mockMvc.perform(post("/api/devices")
                        .header("Authorization", "Bearer " + otherUser.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "platform": "android",
                                  "pushToken": "shared-token",
                                  "deviceName": "Other phone"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(deviceId))
                .andExpect(jsonPath("$.deviceName").value("Other phone"));

        mockMvc.perform(delete("/api/devices/" + deviceId)
                        .header("Authorization", "Bearer " + owner.accessToken()))
                .andExpect(status().isNotFound());

        mockMvc.perform(delete("/api/devices/" + deviceId)
                        .header("Authorization", "Bearer " + otherUser.accessToken()))
                .andExpect(status().isNoContent());

        DeviceRegistration registration = deviceRegistrationRepository.findById(UUID.fromString(deviceId)).orElseThrow();
        assertEquals("Other phone", registration.getDeviceName());
        assertFalse(registration.isActive());
    }

    @Test
    void deviceRegistrationUpsertsSameLogicalDeviceWhenTokenRotates() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");

        String firstRegistration = registerDevice(owner.accessToken(), "token-a", "Pixel 8", "install-1");
        String deviceId = read(firstRegistration, "/id");

        mockMvc.perform(post("/api/devices")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "platform": "android",
                                  "pushToken": "token-b",
                                  "installationId": "install-1",
                                  "deviceName": "Pixel 8 Pro"
                                }
                                """))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(deviceId))
                .andExpect(jsonPath("$.deviceName").value("Pixel 8 Pro"));

        DeviceRegistration registration = deviceRegistrationRepository.findById(UUID.fromString(deviceId)).orElseThrow();
        assertEquals(owner.userId(), registration.getUserId().toString());
        assertEquals("token-b", registration.getPushToken());
        assertEquals("install-1", registration.getInstallationId());
        assertTrue(registration.isActive());
    }

    @Test
    void deviceRegistrationPrefersCurrentTokenAndRetiresSupersededInstallationRow() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        Session otherUser = registerAndLogin("other@example.com", "Other");

        String installationRegistration = registerDevice(owner.accessToken(), "token-a", "Owner Pixel", "install-1");
        String staleTokenRegistration = registerDevice(otherUser.accessToken(), "token-b", "Other Pixel");
        String installationDeviceId = read(installationRegistration, "/id");
        String staleTokenDeviceId = read(staleTokenRegistration, "/id");

        String migratedRegistration = registerDevice(owner.accessToken(), "token-b", "Owner Pixel 9", "install-1");
        assertEquals(staleTokenDeviceId, read(migratedRegistration, "/id"));

        DeviceRegistration canonicalRegistration =
                deviceRegistrationRepository.findById(UUID.fromString(staleTokenDeviceId)).orElseThrow();
        assertEquals(owner.userId(), canonicalRegistration.getUserId().toString());
        assertEquals("token-b", canonicalRegistration.getPushToken());
        assertEquals("install-1", canonicalRegistration.getInstallationId());
        assertEquals("Owner Pixel 9", canonicalRegistration.getDeviceName());
        assertTrue(canonicalRegistration.isActive());

        DeviceRegistration supersededRegistration =
                deviceRegistrationRepository.findById(UUID.fromString(installationDeviceId)).orElseThrow();
        assertFalse(supersededRegistration.isActive());
        assertNull(supersededRegistration.getInstallationId());
    }

    @Test
    void serverSideTaskReminderEndpointIsDisabledAndNoDeliveryRuns() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        Session collaborator = registerAndLogin("collaborator@example.com", "Collaborator");

        String folderId = createFolder(owner.accessToken());
        String goalId = read(createGoal(owner.accessToken(), folderId, "Work", "Shared project"), "/id");
        String taskId = read(createTask(owner.accessToken(), goalId, """
                {
                  "title": "Prepare launch note",
                  "description": "Finish the owner-facing reminder flow",
                  "type": "green",
                  "priority": 7,
                  "status": "todo",
                  "plannedTime": "2026-05-01T09:30:00Z",
                  "dueTime": "2026-05-01T12:00:00Z",
                  "tagIds": []
                }
                """), "/id");

        mockMvc.perform(put("/api/tasks/" + taskId + "/reminders")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "reminders": [
                                    {
                                      "mode": "before_planned_time",
                                      "offsetMinutes": 30,
                                      "active": true
                                    }
                                  ]
                                }
                                """))
                .andExpect(status().isGone())
                .andExpect(jsonPath("$.error.code").value("reminders_not_supported"));

        String invitationId = read(mockMvc.perform(post("/api/tasks/" + taskId + "/share")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "collaborator@example.com"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString(), "/id");

        mockMvc.perform(post("/api/shares/invitations/" + invitationId + "/accept")
                        .header("Authorization", "Bearer " + collaborator.accessToken()))
                .andExpect(status().isOk());

        registerDevice(owner.accessToken(), "owner-token", "Owner Pixel");
        registerDevice(collaborator.accessToken(), "collab-token", "Collaborator Pixel");

        NotificationDeliveryService.DeliveryRunSummary summary =
                notificationDeliveryService.processDueReminders(Instant.parse("2026-05-01T09:00:00Z"));
        assertEquals(0, summary.sent());
        assertEquals(0, summary.failed());
        assertEquals(0, summary.skipped());

        List<NotificationDelivery> deliveries = notificationDeliveryRepository.findAllByOrderByCreatedAtAsc();
        assertEquals(0, deliveries.size());
        assertEquals(0, testFcmSender.sentMessages.size());

        notificationDeliveryService.processDueReminders(Instant.parse("2026-05-01T09:00:00Z"));
        assertEquals(0, notificationDeliveryRepository.findAllByOrderByCreatedAtAsc().size());
        assertEquals(0, testFcmSender.sentMessages.size());
    }

    @Test
    void disabledServerSideTaskReminderEndpointDoesNotCreateFailedDeliveries() throws Exception {
        Session owner = registerAndLogin("owner@example.com", "Owner");
        String folderId = createFolder(owner.accessToken());
        String goalId = read(createGoal(owner.accessToken(), folderId, "Ops", "Delivery checks"), "/id");
        String taskId = read(createTask(owner.accessToken(), goalId, """
                {
                  "title": "Check failed push",
                  "description": "Make sure failure is persisted",
                  "type": "red",
                  "priority": 8,
                  "status": "todo",
                  "plannedTime": "2026-05-01T10:15:00Z",
                  "dueTime": "2026-05-01T12:00:00Z",
                  "tagIds": []
                }
                """), "/id");

        mockMvc.perform(put("/api/tasks/" + taskId + "/reminders")
                        .header("Authorization", "Bearer " + owner.accessToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "reminders": [
                                    {
                                      "mode": "before_planned_time",
                                      "offsetMinutes": 15,
                                      "active": true
                                    }
                                  ]
                                }
                                """))
                .andExpect(status().isGone())
                .andExpect(jsonPath("$.error.code").value("reminders_not_supported"));

        registerDevice(owner.accessToken(), "broken-token", "Broken Pixel");
        testFcmSender.failToken("broken-token");

        NotificationDeliveryService.DeliveryRunSummary summary =
                notificationDeliveryService.processDueReminders(Instant.parse("2026-05-01T10:00:00Z"));
        assertEquals(0, summary.sent());
        assertEquals(0, summary.failed());
        assertEquals(0, summary.skipped());

        List<NotificationDelivery> deliveries = notificationDeliveryRepository.findAllByOrderByCreatedAtAsc();
        assertEquals(0, deliveries.size());
        assertEquals(0, testFcmSender.sentMessages.size());
    }

    private String registerDevice(String accessToken, String pushToken, String deviceName) throws Exception {
        return registerDevice(accessToken, pushToken, deviceName, null);
    }

    private String registerDevice(String accessToken, String pushToken, String deviceName, String installationId) throws Exception {
        String installationIdField = installationId == null
                ? "\"installationId\": null,"
                : "\"installationId\": \"%s\",".formatted(installationId);
        return mockMvc.perform(post("/api/devices")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "platform": "android",
                                  "pushToken": "%s",
                                  %s
                                  "deviceName": "%s"
                                }
                                """.formatted(pushToken, installationIdField, deviceName)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
    }

    private Session registerAndLogin(String email, String displayName) throws Exception {
        mockMvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "%s",
                                  "password": "strong-password",
                                  "displayName": "%s",
                                  "timezone": "Europe/Moscow",
                                  "language": "ru"
                                }
                                """.formatted(email, displayName)))
                .andExpect(status().isCreated());

        String loginResponse = mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "email": "%s",
                                  "password": "strong-password"
                                }
                                """.formatted(email)))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();

        return new Session(
                read(loginResponse, "/tokens/accessToken"),
                read(loginResponse, "/user/id")
        );
    }

    private String createFolder(String accessToken) throws Exception {
        return read(mockMvc.perform(post("/api/folders")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "Work",
                                  "description": "Main work area"
                                }
                                """))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString(), "/id");
    }

    private String createGoal(String accessToken, String folderId, String name, String description) throws Exception {
        return mockMvc.perform(post("/api/folders/" + folderId + "/goals")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {
                                  "name": "%s",
                                  "description": "%s"
                                }
                                """.formatted(name, description)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
    }

    private String createTask(String accessToken, String goalId, String taskPayload) throws Exception {
        return mockMvc.perform(post("/api/goals/" + goalId + "/tasks")
                        .header("Authorization", "Bearer " + accessToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(taskPayload))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
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

    private record Session(String accessToken, String userId) {
    }

    private record SentMessage(String pushToken, NotificationPayload payload) {
    }

    @TestConfiguration
    static class NotificationTestConfig {

        @Bean
        @Primary
        TestFcmSender testFcmSender() {
            return org.mockito.Mockito.spy(new TestFcmSender());
        }
    }

    static class TestFcmSender implements FcmSender {

        private final List<SentMessage> sentMessages = new ArrayList<>();
        private final List<String> failingTokens = new ArrayList<>();

        @Override
        public SendResult send(DeviceRegistration deviceRegistration, NotificationPayload payload) {
            if (failingTokens.contains(deviceRegistration.getPushToken())) {
                return SendResult.failed("simulated_failure");
            }
            sentMessages.add(new SentMessage(deviceRegistration.getPushToken(), payload));
            return SendResult.sent("sent_by_test_sender");
        }

        void failToken(String pushToken) {
            failingTokens.add(pushToken);
        }

        void reset() {
            sentMessages.clear();
            failingTokens.clear();
        }
    }
}
