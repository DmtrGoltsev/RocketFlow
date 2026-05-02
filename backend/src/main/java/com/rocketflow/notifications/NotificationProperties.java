package com.rocketflow.notifications;

import java.time.Duration;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "rocketflow.notifications")
public class NotificationProperties {

    private final Scheduler scheduler = new Scheduler();
    private final Fcm fcm = new Fcm();

    public Scheduler getScheduler() {
        return scheduler;
    }

    public Fcm getFcm() {
        return fcm;
    }

    public static class Scheduler {

        private boolean enabled;
        private Duration fixedDelay = Duration.ofMinutes(1);
        private Duration initialDelay = Duration.ofSeconds(15);
        private long advisoryLockKey = 7_304_001L;

        public boolean isEnabled() {
            return enabled;
        }

        public void setEnabled(boolean enabled) {
            this.enabled = enabled;
        }

        public Duration getFixedDelay() {
            return fixedDelay;
        }

        public void setFixedDelay(Duration fixedDelay) {
            this.fixedDelay = fixedDelay;
        }

        public Duration getInitialDelay() {
            return initialDelay;
        }

        public void setInitialDelay(Duration initialDelay) {
            this.initialDelay = initialDelay;
        }

        public long getAdvisoryLockKey() {
            return advisoryLockKey;
        }

        public void setAdvisoryLockKey(long advisoryLockKey) {
            this.advisoryLockKey = advisoryLockKey;
        }
    }

    public static class Fcm {

        private boolean enabled;
        private String projectId;
        private String credentialsJson;
        private String credentialsPath;

        public boolean isEnabled() {
            return enabled;
        }

        public void setEnabled(boolean enabled) {
            this.enabled = enabled;
        }

        public String getProjectId() {
            return projectId;
        }

        public void setProjectId(String projectId) {
            this.projectId = projectId;
        }

        public String getCredentialsJson() {
            return credentialsJson;
        }

        public void setCredentialsJson(String credentialsJson) {
            this.credentialsJson = credentialsJson;
        }

        public String getCredentialsPath() {
            return credentialsPath;
        }

        public void setCredentialsPath(String credentialsPath) {
            this.credentialsPath = credentialsPath;
        }
    }
}
