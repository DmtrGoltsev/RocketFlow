package com.rocketflow.focusnotifications;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.math.BigInteger;
import java.util.Arrays;
import java.util.Base64;

import org.junit.jupiter.api.Test;

import com.interaso.webpush.VapidKeys;
import com.rocketflow.notifications.NotificationProperties;

class FocusNotificationPropertiesTest {
    @Test
    void allowsMissingVapidKeysWhenWebPushIsDisabled() {
        assertThatCode(new FocusNotificationProperties()::validate).doesNotThrowAnyException();
    }

    @Test
    void failsFastWhenWebPushIsEnabledWithoutKeys() {
        FocusNotificationProperties properties = new FocusNotificationProperties();
        properties.getWebPush().setEnabled(true);

        assertThatThrownBy(properties::validate)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("VAPID");
    }

    @Test
    void rejectsUnsafeSubscriptionAndRetryConfiguration() {
        FocusNotificationProperties properties = new FocusNotificationProperties();
        properties.getWebPush().setMaxActiveSubscriptionsPerUser(0);

        assertThatThrownBy(properties::validate)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("max-active-subscriptions-per-user");
    }

    @Test
    void heartbeatMustRunWellInsideClaimLease() {
        FocusNotificationProperties properties = new FocusNotificationProperties();
        properties.getFocus().setClaimLeaseMs(30_000);
        properties.getFocus().setHeartbeatIntervalMs(10_001);

        assertThatThrownBy(properties::validate)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("heartbeat interval");
    }

    @Test
    void fcmTransportTimeoutsAreValidatedWithoutPretendingToBoundCredentialRefresh() {
        FocusNotificationProperties properties = new FocusNotificationProperties();
        NotificationProperties notificationProperties = new NotificationProperties();
        notificationProperties.getFcm().setEnabled(true);
        properties.getFocus().setClaimLeaseMs(30_000);
        properties.getFocus().setHeartbeatIntervalMs(5_000);
        notificationProperties.getFcm().setReadTimeoutMs(60_001);

        assertThatThrownBy(() -> properties.validate(notificationProperties))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("read-timeout-ms");

        notificationProperties.getFcm().setReadTimeoutMs(60_000);
        assertThatCode(() -> properties.validate(notificationProperties)).doesNotThrowAnyException();
    }

    @Test
    void rejectsMalformedVapidSubjects() {
        for (String subject : new String[] {
                "https:invalid",
                "https://user@example.com/contact",
                "https://example.com:0/contact",
                "https://example.com:",
                "https://example.com/contact#fragment",
                "mailto:",
                "mailto:not-an-address",
                "mailto:ops@localhost",
                "mailto:ops@example.com?subject=test",
                " mailto:ops@example.com",
                "mailto:ops@example.com\n"
        }) {
            FocusNotificationProperties properties = enabledWebPush(subject);
            assertThatThrownBy(properties::validate)
                    .as("subject %s", subject)
                    .isInstanceOf(IllegalStateException.class)
                    .hasMessageContaining("VAPID");
        }
    }

    @Test
    void acceptsStrictHttpsAndMailtoVapidSubjects() {
        assertThatCode(enabledWebPush("mailto:alerts+rocketflow@example.com")::validate)
                .doesNotThrowAnyException();
        assertThatCode(enabledWebPush("https://example.com/security/contact")::validate)
                .doesNotThrowAnyException();
        assertThatCode(enabledWebPush("https://example.com:8443/contact")::validate)
                .doesNotThrowAnyException();
    }

    @Test
    void acceptsAValidGeneratedVapidKeyPair() {
        FocusNotificationProperties properties = enabledWebPush("mailto:ops@example.com");

        assertThatCode(properties::validate).doesNotThrowAnyException();
    }

    private FocusNotificationProperties enabledWebPush(String subject) {
        VapidKeys keys = VapidKeys.generate();
        FocusNotificationProperties properties = new FocusNotificationProperties();
        properties.getWebPush().setEnabled(true);
        properties.getWebPush().setVapidSubject(subject);
        properties.getWebPush().setVapidPublicKey(Base64.getUrlEncoder().withoutPadding()
                .encodeToString(keys.getApplicationServerKey()));
        properties.getWebPush().setVapidPrivateKey(Base64.getUrlEncoder().withoutPadding()
                .encodeToString(unsignedFixed(keys.getPrivateKey().getS(), 32)));
        return properties;
    }

    private byte[] unsignedFixed(BigInteger value, int length) {
        byte[] encoded = value.toByteArray();
        if (encoded.length == length) {
            return encoded;
        }
        if (encoded.length == length + 1 && encoded[0] == 0) {
            return Arrays.copyOfRange(encoded, 1, encoded.length);
        }
        byte[] result = new byte[length];
        System.arraycopy(encoded, 0, result, length - encoded.length, encoded.length);
        return result;
    }
}
