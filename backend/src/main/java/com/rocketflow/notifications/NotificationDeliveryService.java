package com.rocketflow.notifications;

import java.time.Instant;
import java.time.ZoneId;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.rocketflow.accounts.User;
import com.rocketflow.accounts.UserRepository;
import com.rocketflow.reminders.ReminderEligibilityService;
import com.rocketflow.reminders.TaskReminderRule;
import com.rocketflow.settings.UserSettings;
import com.rocketflow.settings.UserSettingsRepository;
import com.rocketflow.tasks.Task;
import com.rocketflow.tasks.TaskRepository;

@Service
public class NotificationDeliveryService {

    private static final Logger log = LoggerFactory.getLogger(NotificationDeliveryService.class);

    private final ReminderNotificationRuleRepository reminderRuleRepository;
    private final TaskRepository taskRepository;
    private final UserRepository userRepository;
    private final UserSettingsRepository userSettingsRepository;
    private final DeviceRegistrationRepository deviceRegistrationRepository;
    private final NotificationDeliveryRepository notificationDeliveryRepository;
    private final ReminderEligibilityService reminderEligibilityService;
    private final NotificationPayloadFactory notificationPayloadFactory;
    private final FcmSender fcmSender;

    public NotificationDeliveryService(
            ReminderNotificationRuleRepository reminderRuleRepository,
            TaskRepository taskRepository,
            UserRepository userRepository,
            UserSettingsRepository userSettingsRepository,
            DeviceRegistrationRepository deviceRegistrationRepository,
            NotificationDeliveryRepository notificationDeliveryRepository,
            ReminderEligibilityService reminderEligibilityService,
            NotificationPayloadFactory notificationPayloadFactory,
            FcmSender fcmSender
    ) {
        this.reminderRuleRepository = reminderRuleRepository;
        this.taskRepository = taskRepository;
        this.userRepository = userRepository;
        this.userSettingsRepository = userSettingsRepository;
        this.deviceRegistrationRepository = deviceRegistrationRepository;
        this.notificationDeliveryRepository = notificationDeliveryRepository;
        this.reminderEligibilityService = reminderEligibilityService;
        this.notificationPayloadFactory = notificationPayloadFactory;
        this.fcmSender = fcmSender;
    }

    @Transactional
    public DeliveryRunSummary processDueReminders(Instant now) {
        List<TaskReminderRule> activeRules = reminderRuleRepository.findByActiveTrueOrderByTaskIdAscSortOrderAsc();
        if (activeRules.isEmpty()) {
            return new DeliveryRunSummary(0, 0, 0);
        }

        Map<UUID, Task> tasksById = toTaskMap(activeRules.stream().map(TaskReminderRule::getTaskId).collect(Collectors.toSet()));
        Set<UUID> ownerUserIds = tasksById.values().stream()
                .map(Task::getOwnerUserId)
                .collect(Collectors.toSet());
        Map<UUID, User> ownersById = toUserMap(ownerUserIds);
        Map<UUID, UserSettings> settingsByUserId = toSettingsMap(ownerUserIds);
        Map<UUID, List<DeviceRegistration>> devicesByUserId = toDevicesMap(ownerUserIds);

        int sent = 0;
        int failed = 0;
        int skipped = 0;

        for (TaskReminderRule activeRule : activeRules) {
            Task task = tasksById.get(activeRule.getTaskId());
            if (task == null || !isTaskDeliverable(task)) {
                continue;
            }

            User owner = ownersById.get(task.getOwnerUserId());
            if (owner == null) {
                continue;
            }

            Instant scheduledAt = reminderEligibilityService.calculateEligibleAt(task, activeRule, ZoneId.of(owner.getTimezone()))
                    .orElse(null);
            if (scheduledAt == null || scheduledAt.isAfter(now)) {
                continue;
            }
            if (notificationDeliveryRepository.existsByTaskIdAndReminderRuleIdAndScheduledAt(
                    task.getId(),
                    activeRule.getId(),
                    scheduledAt)) {
                continue;
            }

            UserSettings settings = settingsByUserId.get(task.getOwnerUserId());
            if (settings != null && !settings.isNotificationsEnabled()) {
                if (saveSkipIfMissing(task, activeRule, scheduledAt, "skipped_notifications_disabled", "User notifications are disabled.")) {
                    skipped++;
                }
                continue;
            }

            List<DeviceRegistration> devices = devicesByUserId.getOrDefault(task.getOwnerUserId(), List.of());
            if (devices.isEmpty()) {
                if (saveSkipIfMissing(task, activeRule, scheduledAt, "skipped_no_active_device", "No active device registrations found.")) {
                    skipped++;
                }
                continue;
            }

            NotificationPayload payload = notificationPayloadFactory.createTaskReminderPayload(task, activeRule, scheduledAt);
            for (DeviceRegistration device : devices) {
                if (notificationDeliveryRepository.existsByTaskIdAndReminderRuleIdAndScheduledAtAndDeviceRegistrationId(
                        task.getId(),
                        activeRule.getId(),
                        scheduledAt,
                        device.getId())) {
                    continue;
                }

                FcmSender.SendResult sendResult;
                try {
                    sendResult = fcmSender.send(device, payload);
                } catch (RuntimeException exception) {
                    sendResult = FcmSender.SendResult.failed(exception.getMessage());
                }

                saveAttempt(task, activeRule, device, scheduledAt, now, sendResult);
                if (sendResult.successful()) {
                    sent++;
                } else {
                    failed++;
                }
            }
        }

        if (sent > 0 || failed > 0 || skipped > 0) {
            log.info("Reminder delivery run sent={} failed={} skipped={}", sent, failed, skipped);
        }
        return new DeliveryRunSummary(sent, failed, skipped);
    }

    private Map<UUID, Task> toTaskMap(Collection<UUID> taskIds) {
        Map<UUID, Task> result = new LinkedHashMap<>();
        for (Task task : taskRepository.findAllById(taskIds)) {
            result.put(task.getId(), task);
        }
        return result;
    }

    private Map<UUID, User> toUserMap(Set<UUID> ownerUserIds) {
        Map<UUID, User> result = new LinkedHashMap<>();
        for (User user : userRepository.findAllById(ownerUserIds)) {
            result.put(user.getId(), user);
        }
        return result;
    }

    private Map<UUID, UserSettings> toSettingsMap(Set<UUID> ownerUserIds) {
        Map<UUID, UserSettings> result = new LinkedHashMap<>();
        for (UserSettings settings : userSettingsRepository.findAllById(ownerUserIds)) {
            result.put(settings.getUserId(), settings);
        }
        return result;
    }

    private Map<UUID, List<DeviceRegistration>> toDevicesMap(Set<UUID> ownerUserIds) {
        if (ownerUserIds.isEmpty()) {
            return Map.of();
        }
        return deviceRegistrationRepository.findByUserIdInAndActiveTrueOrderByUserIdAscCreatedAtAsc(ownerUserIds)
                .stream()
                .collect(Collectors.groupingBy(DeviceRegistration::getUserId, LinkedHashMap::new, Collectors.toList()));
    }

    private boolean saveSkipIfMissing(
            Task task,
            TaskReminderRule reminderRule,
            Instant scheduledAt,
            String status,
            String providerResponse
    ) {
        if (notificationDeliveryRepository.existsByTaskIdAndReminderRuleIdAndScheduledAtAndDeviceRegistrationIdIsNull(
                task.getId(),
                reminderRule.getId(),
                scheduledAt)) {
            return false;
        }

        NotificationDelivery delivery = new NotificationDelivery();
        delivery.setId(UUID.randomUUID());
        delivery.setTaskId(task.getId());
        delivery.setReminderRuleId(reminderRule.getId());
        delivery.setDeviceRegistrationId(null);
        delivery.setScheduledAt(scheduledAt);
        delivery.setAttemptedAt(null);
        delivery.setStatus(status);
        delivery.setProviderResponse(truncate(providerResponse));
        delivery.setCreatedAt(Instant.now());
        notificationDeliveryRepository.save(delivery);
        return true;
    }

    private void saveAttempt(
            Task task,
            TaskReminderRule reminderRule,
            DeviceRegistration device,
            Instant scheduledAt,
            Instant attemptedAt,
            FcmSender.SendResult sendResult
    ) {
        NotificationDelivery delivery = new NotificationDelivery();
        delivery.setId(UUID.randomUUID());
        delivery.setTaskId(task.getId());
        delivery.setReminderRuleId(reminderRule.getId());
        delivery.setDeviceRegistrationId(device.getId());
        delivery.setScheduledAt(scheduledAt);
        delivery.setAttemptedAt(attemptedAt);
        delivery.setStatus(sendResult.successful() ? "sent" : "failed");
        delivery.setProviderResponse(truncate(sendResult.providerResponse()));
        delivery.setCreatedAt(attemptedAt);
        notificationDeliveryRepository.save(delivery);
    }

    private boolean isTaskDeliverable(Task task) {
        return !task.isArchived() && !"done".equals(task.getStatus()) && !"cancelled".equals(task.getStatus());
    }

    private String truncate(String value) {
        if (value == null || value.length() <= 2000) {
            return value;
        }
        return value.substring(0, 2000);
    }

    public record DeliveryRunSummary(int sent, int failed, int skipped) {
    }
}
