package com.rocketflow.focusnotifications;

import java.net.URI;
import java.time.Duration;
import java.util.Base64;
import java.util.LinkedHashSet;
import java.util.Set;

import org.springframework.boot.context.properties.ConfigurationProperties;

import com.interaso.webpush.VapidKeys;
import com.rocketflow.notifications.NotificationProperties;

@ConfigurationProperties(prefix = "rocketflow.notifications")
public class FocusNotificationProperties {
    static final Duration WEB_PUSH_REQUEST_TIMEOUT = Duration.ofSeconds(10);

    private final Focus focus = new Focus();
    private final WebPush webPush = new WebPush();

    public Focus getFocus() {
        return focus;
    }

    public WebPush getWebPush() {
        return webPush;
    }

    public void validate() {
        if (focus.fixedDelayMs < 1_000) {
            throw new IllegalStateException("rocketflow.notifications.focus.fixed-delay-ms must be at least 1000.");
        }
        if (focus.maxDeliveryAttempts < 1 || focus.maxDeliveryAttempts > 10) {
            throw new IllegalStateException("rocketflow.notifications.focus.max-delivery-attempts must be between 1 and 10.");
        }
        if (focus.maxRetriesPerPoll < 1 || focus.maxRetriesPerPoll > 100) {
            throw new IllegalStateException("rocketflow.notifications.focus.max-retries-per-poll must be between 1 and 100.");
        }
        if (focus.claimLeaseMs < 30_000 || focus.claimLeaseMs > Duration.ofMinutes(15).toMillis()) {
            throw new IllegalStateException("rocketflow.notifications.focus.claim-lease-ms must be between 30000 and 900000.");
        }
        if (focus.heartbeatIntervalMs < 1_000 || focus.heartbeatIntervalMs > Duration.ofMinutes(1).toMillis()) {
            throw new IllegalStateException("rocketflow.notifications.focus.heartbeat-interval-ms must be between 1000 and 60000.");
        }
        if (focus.heartbeatIntervalMs >= focus.claimLeaseMs
                || focus.heartbeatIntervalMs > focus.claimLeaseMs / 3) {
            throw new IllegalStateException(
                    "Focus heartbeat interval must be less than one third of the claim lease."
            );
        }
        if (WEB_PUSH_REQUEST_TIMEOUT.isZero() || WEB_PUSH_REQUEST_TIMEOUT.isNegative()
                || WEB_PUSH_REQUEST_TIMEOUT.compareTo(Duration.ofMinutes(1)) > 0) {
            throw new IllegalStateException("Web Push request timeout must be between 1 ms and 60 seconds.");
        }
        if (focus.retryInitialDelayMs < 1_000 || focus.retryMaxDelayMs < focus.retryInitialDelayMs) {
            throw new IllegalStateException("Focus retry delays must be positive and max must be at least initial.");
        }
        if (focus.retryJitterRatio < 0 || focus.retryJitterRatio > 0.5) {
            throw new IllegalStateException("rocketflow.notifications.focus.retry-jitter-ratio must be between 0 and 0.5.");
        }
        if (webPush.maxActiveSubscriptionsPerUser < 1 || webPush.maxActiveSubscriptionsPerUser > 100) {
            throw new IllegalStateException("rocketflow.notifications.web-push.max-active-subscriptions-per-user must be between 1 and 100.");
        }
        if (webPush.allowedHostSuffixes == null || webPush.allowedHostSuffixes.isEmpty()
                || webPush.allowedHostSuffixes.stream().anyMatch(this::invalidHostSuffix)) {
            throw new IllegalStateException("Web Push allowed host suffixes must be non-empty DNS suffixes without wildcards.");
        }
        if (!webPush.enabled) {
            return;
        }
        if (blank(webPush.vapidPublicKey) || blank(webPush.vapidPrivateKey) || blank(webPush.vapidSubject)) {
            throw new IllegalStateException("Web Push is enabled, but the VAPID public key, private key, or subject is missing.");
        }
        validateSubject(webPush.vapidSubject);
        validateVapidBytes(webPush.vapidPublicKey, 65, "public");
        validateVapidBytes(webPush.vapidPrivateKey, 32, "private");
        try {
            VapidKeys.fromUncompressedBytes(webPush.vapidPublicKey, webPush.vapidPrivateKey);
        } catch (RuntimeException exception) {
            throw new IllegalStateException("The configured VAPID key pair is invalid.", exception);
        }
    }

    public void validate(NotificationProperties notificationProperties) {
        validate();
        NotificationProperties.Fcm fcm = notificationProperties.getFcm();
        fcm.validateTransportTimeouts();
    }

    private void validateSubject(String subject) {
        if (blank(subject) || !subject.equals(subject.trim()) || subject.chars().anyMatch(Character::isISOControl)) {
            throw new IllegalStateException("The VAPID subject must be a valid mailto address or absolute HTTPS URL.");
        }
        URI uri;
        try {
            uri = URI.create(subject);
        } catch (IllegalArgumentException exception) {
            throw new IllegalStateException("The VAPID subject must be a mailto or HTTPS URI.", exception);
        }
        if (uri.getScheme() == null) {
            throw new IllegalStateException("The VAPID subject must be a valid mailto address or absolute HTTPS URL.");
        }
        if ("https".equalsIgnoreCase(uri.getScheme())) {
            String authority = uri.getRawAuthority();
            boolean validPort = uri.getPort() == -1 || (uri.getPort() >= 1 && uri.getPort() <= 65_535);
            if (!uri.isAbsolute() || blank(uri.getHost()) || uri.getRawUserInfo() != null
                    || uri.getRawFragment() != null || authority == null || authority.endsWith(":") || !validPort) {
                throw new IllegalStateException("The VAPID HTTPS subject must be absolute and include a host without userinfo.");
            }
            return;
        }
        if ("mailto".equalsIgnoreCase(uri.getScheme()) && validMailAddress(uri)) {
            return;
        }
        throw new IllegalStateException("The VAPID subject must be a valid mailto address or absolute HTTPS URL.");
    }

    private boolean validMailAddress(URI uri) {
        String address = uri.getRawSchemeSpecificPart();
        if (blank(address) || uri.getRawFragment() != null || address.contains("?") || address.contains("%")
                || address.length() > 254 || address.chars().anyMatch(Character::isWhitespace)) {
            return false;
        }
        int at = address.indexOf('@');
        if (at < 1 || at != address.lastIndexOf('@') || at == address.length() - 1) {
            return false;
        }
        String local = address.substring(0, at);
        String domain = address.substring(at + 1);
        if (local.length() > 64 || local.startsWith(".") || local.endsWith(".") || local.contains("..")
                || !local.matches("[A-Za-z0-9.!#$&'*+/=?^_`{|}~-]+")) {
            return false;
        }
        if (!domain.contains(".") || domain.length() > 253) {
            return false;
        }
        for (String label : domain.split("\\.", -1)) {
            if (label.isEmpty() || label.length() > 63 || label.startsWith("-") || label.endsWith("-")
                    || !label.matches("[A-Za-z0-9-]+")) {
                return false;
            }
        }
        return true;
    }

    private void validateVapidBytes(String value, int expectedLength, String label) {
        try {
            byte[] decoded = Base64.getUrlDecoder().decode(value);
            if (decoded.length != expectedLength || (expectedLength == 65 && decoded[0] != 0x04)) {
                throw new IllegalStateException("The VAPID " + label + " key has an invalid length or format.");
            }
        } catch (IllegalArgumentException exception) {
            throw new IllegalStateException("The VAPID " + label + " key must use unpadded Base64URL.", exception);
        }
        if (value.indexOf('=') >= 0) {
            throw new IllegalStateException("The VAPID " + label + " key must use unpadded Base64URL.");
        }
    }

    private boolean blank(String value) {
        return value == null || value.isBlank();
    }

    private boolean invalidHostSuffix(String value) {
        return blank(value) || value.contains("*") || value.contains("/") || value.contains(":")
                || value.startsWith(".") || value.endsWith(".");
    }

    public static class Focus {
        private boolean enabled;
        private long fixedDelayMs = Duration.ofSeconds(15).toMillis();
        private int maxDeliveryAttempts = 3;
        private int maxRetriesPerPoll = 10;
        private long claimLeaseMs = Duration.ofMinutes(7).toMillis();
        private long heartbeatIntervalMs = Duration.ofSeconds(15).toMillis();
        private long retryInitialDelayMs = Duration.ofMinutes(1).toMillis();
        private long retryMaxDelayMs = Duration.ofMinutes(30).toMillis();
        private double retryJitterRatio = 0.5;

        public boolean isEnabled() { return enabled; }
        public void setEnabled(boolean enabled) { this.enabled = enabled; }
        public long getFixedDelayMs() { return fixedDelayMs; }
        public void setFixedDelayMs(long fixedDelayMs) { this.fixedDelayMs = fixedDelayMs; }
        public int getMaxDeliveryAttempts() { return maxDeliveryAttempts; }
        public void setMaxDeliveryAttempts(int maxDeliveryAttempts) { this.maxDeliveryAttempts = maxDeliveryAttempts; }
        public int getMaxRetriesPerPoll() { return maxRetriesPerPoll; }
        public void setMaxRetriesPerPoll(int maxRetriesPerPoll) { this.maxRetriesPerPoll = maxRetriesPerPoll; }
        public long getClaimLeaseMs() { return claimLeaseMs; }
        public void setClaimLeaseMs(long claimLeaseMs) { this.claimLeaseMs = claimLeaseMs; }
        public long getHeartbeatIntervalMs() { return heartbeatIntervalMs; }
        public void setHeartbeatIntervalMs(long heartbeatIntervalMs) { this.heartbeatIntervalMs = heartbeatIntervalMs; }
        public long getRetryInitialDelayMs() { return retryInitialDelayMs; }
        public void setRetryInitialDelayMs(long retryInitialDelayMs) { this.retryInitialDelayMs = retryInitialDelayMs; }
        public long getRetryMaxDelayMs() { return retryMaxDelayMs; }
        public void setRetryMaxDelayMs(long retryMaxDelayMs) { this.retryMaxDelayMs = retryMaxDelayMs; }
        public double getRetryJitterRatio() { return retryJitterRatio; }
        public void setRetryJitterRatio(double retryJitterRatio) { this.retryJitterRatio = retryJitterRatio; }
    }

    public static class WebPush {
        private boolean enabled;
        private String vapidPublicKey;
        private String vapidPrivateKey;
        private String vapidSubject;
        private int maxActiveSubscriptionsPerUser = 10;
        private Set<String> allowedHostSuffixes = new LinkedHashSet<>(Set.of(
                "fcm.googleapis.com",
                "push.services.mozilla.com",
                "notify.windows.com",
                "push.apple.com"
        ));

        public boolean isEnabled() { return enabled; }
        public void setEnabled(boolean enabled) { this.enabled = enabled; }
        public String getVapidPublicKey() { return vapidPublicKey; }
        public void setVapidPublicKey(String vapidPublicKey) { this.vapidPublicKey = vapidPublicKey; }
        public String getVapidPrivateKey() { return vapidPrivateKey; }
        public void setVapidPrivateKey(String vapidPrivateKey) { this.vapidPrivateKey = vapidPrivateKey; }
        public String getVapidSubject() { return vapidSubject; }
        public void setVapidSubject(String vapidSubject) { this.vapidSubject = vapidSubject; }
        public int getMaxActiveSubscriptionsPerUser() { return maxActiveSubscriptionsPerUser; }
        public void setMaxActiveSubscriptionsPerUser(int maxActiveSubscriptionsPerUser) {
            this.maxActiveSubscriptionsPerUser = maxActiveSubscriptionsPerUser;
        }
        public Set<String> getAllowedHostSuffixes() { return allowedHostSuffixes; }
        public void setAllowedHostSuffixes(Set<String> allowedHostSuffixes) {
            this.allowedHostSuffixes = allowedHostSuffixes == null ? Set.of() : new LinkedHashSet<>(allowedHostSuffixes);
        }
    }
}
