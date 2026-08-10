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
        private int connectTimeoutMs = 5_000;
        private int readTimeoutMs = 10_000;
        private int writeTimeoutMs = 5_000;

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

        public int getConnectTimeoutMs() {
            return connectTimeoutMs;
        }

        public void setConnectTimeoutMs(int connectTimeoutMs) {
            this.connectTimeoutMs = connectTimeoutMs;
        }

        public int getReadTimeoutMs() {
            return readTimeoutMs;
        }

        public void setReadTimeoutMs(int readTimeoutMs) {
            this.readTimeoutMs = readTimeoutMs;
        }

        public int getWriteTimeoutMs() {
            return writeTimeoutMs;
        }

        public void setWriteTimeoutMs(int writeTimeoutMs) {
            this.writeTimeoutMs = writeTimeoutMs;
        }

        public void validateTransportTimeouts() {
            validateTimeout(connectTimeoutMs, "connect-timeout-ms");
            validateTimeout(readTimeoutMs, "read-timeout-ms");
            validateTimeout(writeTimeoutMs, "write-timeout-ms");
        }

        private void validateTimeout(int value, String property) {
            if (value < 1 || value > Duration.ofMinutes(1).toMillis()) {
                throw new IllegalStateException(
                        "rocketflow.notifications.fcm." + property + " must be between 1 and 60000."
                );
            }
        }
    }
}
