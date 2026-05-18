package com.rocketflow;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import com.rocketflow.accounts.UserRepository;
import com.rocketflow.auth.AuthSessionRepository;
import com.rocketflow.auth.UserCredentialRepository;
import com.rocketflow.calendar.TaskRescheduleEventRepository;
import com.rocketflow.folders.FolderRepository;
import com.rocketflow.goals.GoalRepository;
import com.rocketflow.ideas.IdeaNoteRepository;
import com.rocketflow.ideas.IdeaRepository;
import com.rocketflow.links.EntityLinkRepository;
import com.rocketflow.notes.NoteRepository;
import com.rocketflow.notifications.DeviceRegistrationRepository;
import com.rocketflow.notifications.NotificationDeliveryRepository;
import com.rocketflow.notifications.ReminderNotificationRuleRepository;
import com.rocketflow.recurrence.TaskRecurrenceRuleRepository;
import com.rocketflow.reminders.TaskReminderRuleRepository;
import com.rocketflow.settings.UserSettingsRepository;
import com.rocketflow.sharing.FolderShareRepository;
import com.rocketflow.sharing.GoalShareRepository;
import com.rocketflow.sharing.ShareInvitationRepository;
import com.rocketflow.sharing.ShareLinkRepository;
import com.rocketflow.sharing.TaskShareRepository;
import com.rocketflow.tasks.TaskRepository;
import com.rocketflow.tasks.TaskTagLinkRepository;
import com.rocketflow.tasks.TaskTagRepository;

@SpringBootTest(properties = {
        "rocketflow.web.cors.allowed-origins[0]=http://localhost:5173",
        "rocketflow.web.cors.allowed-origins[1]=http://45.10.110.42",
        "rocketflow.web.cors.allowed-origin-patterns[0]=http://127.0.0.1:[*]",
        "rocketflow.web.cors.allowed-origin-patterns[1]=http://localhost:[*]",
        "spring.autoconfigure.exclude="
                + "org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration,"
                + "org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration,"
                + "org.springframework.boot.autoconfigure.flyway.FlywayAutoConfiguration"
})
@AutoConfigureMockMvc
class CorsConfigurationIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private UserRepository userRepository;

    @MockitoBean
    private UserCredentialRepository userCredentialRepository;

    @MockitoBean
    private UserSettingsRepository userSettingsRepository;

    @MockitoBean
    private AuthSessionRepository authSessionRepository;

    @MockitoBean
    private FolderRepository folderRepository;

    @MockitoBean
    private GoalRepository goalRepository;

    @MockitoBean
    private IdeaRepository ideaRepository;

    @MockitoBean
    private IdeaNoteRepository ideaNoteRepository;

    @MockitoBean
    private NoteRepository noteRepository;

    @MockitoBean
    private EntityLinkRepository entityLinkRepository;

    @MockitoBean
    private ShareInvitationRepository shareInvitationRepository;

    @MockitoBean
    private ShareLinkRepository shareLinkRepository;

    @MockitoBean
    private FolderShareRepository folderShareRepository;

    @MockitoBean
    private GoalShareRepository goalShareRepository;

    @MockitoBean
    private TaskShareRepository taskShareRepository;

    @MockitoBean
    private TaskRecurrenceRuleRepository taskRecurrenceRuleRepository;

    @MockitoBean
    private TaskReminderRuleRepository taskReminderRuleRepository;

    @MockitoBean
    private TaskRescheduleEventRepository taskRescheduleEventRepository;

    @MockitoBean
    private DeviceRegistrationRepository deviceRegistrationRepository;

    @MockitoBean
    private ReminderNotificationRuleRepository reminderNotificationRuleRepository;

    @MockitoBean
    private NotificationDeliveryRepository notificationDeliveryRepository;

    @MockitoBean
    private TaskRepository taskRepository;

    @MockitoBean
    private TaskTagRepository taskTagRepository;

    @MockitoBean
    private TaskTagLinkRepository taskTagLinkRepository;

    @Test
    void preflightRequestAllowsConfiguredOriginForApiRoutes() throws Exception {
        mockMvc.perform(options("/api/auth/login")
                        .header("Origin", "http://localhost:5173")
                        .header("Access-Control-Request-Method", "POST")
                        .header("Access-Control-Request-Headers", "Authorization,Content-Type"))
                .andExpect(status().isOk())
                .andExpect(header().string("Access-Control-Allow-Origin", "http://localhost:5173"))
                .andExpect(header().string("Access-Control-Allow-Methods", org.hamcrest.Matchers.containsString("POST")));
    }

    @Test
    void preflightRequestAllowsConfiguredDevOriginPatternForApiRoutes() throws Exception {
        mockMvc.perform(options("/api/auth/register")
                        .header("Origin", "http://127.0.0.1:5191")
                        .header("Access-Control-Request-Method", "POST")
                        .header("Access-Control-Request-Headers", "Content-Type"))
                .andExpect(status().isOk())
                .andExpect(header().string("Access-Control-Allow-Origin", "http://127.0.0.1:5191"))
                .andExpect(header().string("Access-Control-Allow-Methods", org.hamcrest.Matchers.containsString("POST")));
    }

    @Test
    void preflightRequestAllowsProdLikePublicWebOriginForApiRoutes() throws Exception {
        mockMvc.perform(options("/api/tasks/00000000-0000-0000-0000-000000000001")
                        .header("Origin", "http://45.10.110.42")
                        .header("Access-Control-Request-Method", "PATCH")
                        .header("Access-Control-Request-Headers", "Authorization,Content-Type"))
                .andExpect(status().isOk())
                .andExpect(header().string("Access-Control-Allow-Origin", "http://45.10.110.42"))
                .andExpect(header().string("Access-Control-Allow-Methods", org.hamcrest.Matchers.containsString("PATCH")));
    }

    @Test
    void preflightRequestAllowsLocalPreviewOriginPatternForApiRoutes() throws Exception {
        mockMvc.perform(options("/api/tasks/00000000-0000-0000-0000-000000000001")
                        .header("Origin", "http://localhost:4173")
                        .header("Access-Control-Request-Method", "PATCH")
                        .header("Access-Control-Request-Headers", "Authorization,Content-Type"))
                .andExpect(status().isOk())
                .andExpect(header().string("Access-Control-Allow-Origin", "http://localhost:4173"))
                .andExpect(header().string("Access-Control-Allow-Methods", org.hamcrest.Matchers.containsString("PATCH")));
    }
}
