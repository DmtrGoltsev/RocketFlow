package com.rocketflow.focusnotifications;

import java.time.Duration;
import java.util.concurrent.ThreadLocalRandom;
import java.util.function.DoubleSupplier;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

@Component
class FocusNotificationBackoff {
    private final FocusNotificationProperties properties;
    private final DoubleSupplier random;

    @Autowired
    FocusNotificationBackoff(FocusNotificationProperties properties) {
        this(properties, () -> ThreadLocalRandom.current().nextDouble());
    }

    FocusNotificationBackoff(FocusNotificationProperties properties, DoubleSupplier random) {
        this.properties = properties;
        this.random = random;
    }

    Duration delay(int attempt, Duration providerMinimum) {
        FocusNotificationProperties.Focus focus = properties.getFocus();
        long initialMs = focus.getRetryInitialDelayMs();
        long maxMs = focus.getRetryMaxDelayMs();
        int shift = Math.max(0, Math.min(attempt - 1, 30));
        long exponentialMs = initialMs > (Long.MAX_VALUE >> shift)
                ? maxMs
                : Math.min(maxMs, initialMs << shift);
        long providerMs = providerMillis(providerMinimum);
        long minimumMs = Math.max(exponentialMs, providerMs);
        long jitterBoundMs = Math.round(exponentialMs * focus.getRetryJitterRatio());
        long jitterMs = jitterBoundMs == 0
                ? 0
                : Math.min(jitterBoundMs, (long) Math.floor(random.getAsDouble() * (jitterBoundMs + 1)));
        return Duration.ofMillis(saturatedAdd(minimumMs, jitterMs));
    }

    private long saturatedAdd(long left, long right) {
        if (right > 0 && left > Long.MAX_VALUE - right) {
            return Long.MAX_VALUE;
        }
        return left + right;
    }

    private long providerMillis(Duration providerMinimum) {
        if (providerMinimum == null || providerMinimum.isNegative()) {
            return 0;
        }
        try {
            return providerMinimum.toMillis();
        } catch (ArithmeticException exception) {
            return Long.MAX_VALUE;
        }
    }
}
