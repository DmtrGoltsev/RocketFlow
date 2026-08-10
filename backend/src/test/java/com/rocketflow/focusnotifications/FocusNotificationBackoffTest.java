package com.rocketflow.focusnotifications;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Duration;

import org.junit.jupiter.api.Test;

class FocusNotificationBackoffTest {
    @Test
    void appliesExponentialDelayWithBoundedJitter() {
        FocusNotificationProperties properties = properties();

        Duration low = new FocusNotificationBackoff(properties, () -> 0.0).delay(3, null);
        Duration high = new FocusNotificationBackoff(properties, () -> 0.999999).delay(3, null);

        assertThat(low).isEqualTo(Duration.ofMinutes(4));
        assertThat(high).isGreaterThan(low).isLessThanOrEqualTo(Duration.ofMinutes(5));
    }

    @Test
    void retryAfterIsAMinimumAndStillReceivesJitter() {
        FocusNotificationProperties properties = properties();
        Duration retryAfter = Duration.ofMinutes(5);

        Duration delay = new FocusNotificationBackoff(properties, () -> 0.5).delay(1, retryAfter);

        assertThat(delay).isGreaterThan(retryAfter).isLessThanOrEqualTo(retryAfter.plusSeconds(15));
    }

    private FocusNotificationProperties properties() {
        FocusNotificationProperties properties = new FocusNotificationProperties();
        properties.getFocus().setRetryInitialDelayMs(Duration.ofMinutes(1).toMillis());
        properties.getFocus().setRetryMaxDelayMs(Duration.ofMinutes(10).toMillis());
        properties.getFocus().setRetryJitterRatio(0.25);
        return properties;
    }
}
