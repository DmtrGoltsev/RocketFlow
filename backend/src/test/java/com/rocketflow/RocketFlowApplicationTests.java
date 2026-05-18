package com.rocketflow;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;

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
import com.rocketflow.sharing.FolderShareRepository;
import com.rocketflow.sharing.GoalShareRepository;
import com.rocketflow.sharing.ShareInvitationRepository;
import com.rocketflow.sharing.ShareLinkRepository;
import com.rocketflow.sharing.TaskShareRepository;
import com.rocketflow.reminders.TaskReminderRuleRepository;
import com.rocketflow.settings.UserSettingsRepository;
import com.rocketflow.tasks.TaskRepository;
import com.rocketflow.tasks.TaskTagLinkRepository;
import com.rocketflow.tasks.TaskTagRepository;

@SpringBootTest(properties = {
        "spring.autoconfigure.exclude="
                + "org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration,"
                + "org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration,"
                + "org.springframework.boot.autoconfigure.flyway.FlywayAutoConfiguration"
})
class RocketFlowApplicationTests {

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
    void contextLoads() {
    }
}
