package com.rocketflow.focusnotifications;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(prefix = "rocketflow.notifications.focus", name = "enabled", havingValue = "true")
public class FocusNotificationScheduler {
    private static final Logger log = LoggerFactory.getLogger(FocusNotificationScheduler.class);

    private final FocusNotificationEngine engine;
    private final FocusNotificationProperties properties;

    public FocusNotificationScheduler(
            FocusNotificationEngine engine,
            FocusNotificationProperties properties
    ) {
        this.engine = engine;
        this.properties = properties;
    }

    @Scheduled(
            fixedDelayString = "${rocketflow.notifications.focus.fixed-delay-ms:15000}",
            initialDelayString = "${rocketflow.notifications.focus.fixed-delay-ms:15000}"
    )
    public void poll() {
        if (!properties.getFocus().isEnabled()) {
            return;
        }
        FocusNotificationEngine.RunSummary result = engine.process();
        if (result.sent() > 0 || result.failed() > 0 || result.retried() > 0) {
            log.info(
                    "Focus notification poll sent={} failed={} retried={} deduplicated={} skipped={}",
                    result.sent(), result.failed(), result.retried(), result.deduplicated(), result.skipped()
            );
        }
    }
}
