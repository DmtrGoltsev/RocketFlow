package com.rocketflow;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
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
import com.rocketflow.ideas.FolderNoteItemRepository;
import com.rocketflow.ideas.FolderNoteRepository;
import com.rocketflow.ideas.IdeaNoteRepository;
import com.rocketflow.ideas.IdeaRepository;
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
        "spring.autoconfigure.exclude="
                + "org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration,"
                + "org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration,"
                + "org.springframework.boot.autoconfigure.flyway.FlywayAutoConfiguration"
})
@AutoConfigureMockMvc
class HealthEndpointIntegrationTest {

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
    private FolderNoteRepository folderNoteRepository;

    @MockitoBean
    private FolderNoteItemRepository folderNoteItemRepository;

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
    void apiHealthIsPublicAndReportsUp() throws Exception {
        mockMvc.perform(get("/api/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"));
    }
}
