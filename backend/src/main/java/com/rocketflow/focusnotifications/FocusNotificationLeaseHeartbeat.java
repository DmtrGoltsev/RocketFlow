package com.rocketflow.focusnotifications;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.ScheduledThreadPoolExecutor;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Supplier;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.rocketflow.focusnotifications.FocusNotificationDeliveryStore.Delivery;

import jakarta.annotation.PreDestroy;

@Component
public class FocusNotificationLeaseHeartbeat implements AutoCloseable {
    private static final Logger log = LoggerFactory.getLogger(FocusNotificationLeaseHeartbeat.class);

    private final FocusNotificationDeliveryStore deliveryStore;
    private final FocusNotificationProperties properties;
    private final Clock clock;
    private final ScheduledThreadPoolExecutor executor;
    private final AtomicBoolean closed = new AtomicBoolean();

    @Autowired
    public FocusNotificationLeaseHeartbeat(
            FocusNotificationDeliveryStore deliveryStore,
            FocusNotificationProperties properties,
            Clock clock
    ) {
        this(deliveryStore, properties, clock, executor());
    }

    FocusNotificationLeaseHeartbeat(
            FocusNotificationDeliveryStore deliveryStore,
            FocusNotificationProperties properties,
            Clock clock,
            ScheduledThreadPoolExecutor executor
    ) {
        this.deliveryStore = deliveryStore;
        this.properties = properties;
        this.clock = clock;
        this.executor = executor;
        this.executor.setRemoveOnCancelPolicy(true);
        this.executor.setExecuteExistingDelayedTasksAfterShutdownPolicy(false);
        this.executor.setContinueExistingPeriodicTasksAfterShutdownPolicy(false);
    }

    public <T> ProviderCall<T> aroundProviderCall(Delivery delivery, Supplier<T> providerCall) {
        LeaseState state = new LeaseState();
        if (closed.get() || !renew(delivery, state)) {
            return ProviderCall.leaseLost();
        }

        ScheduledFuture<?> heartbeat;
        long intervalMs = properties.getFocus().getHeartbeatIntervalMs();
        try {
            heartbeat = executor.scheduleWithFixedDelay(
                    () -> renew(delivery, state), intervalMs, intervalMs, TimeUnit.MILLISECONDS
            );
        } catch (RejectedExecutionException exception) {
            return ProviderCall.leaseLost();
        }

        T value;
        try {
            value = providerCall.get();
        } finally {
            synchronized (state.monitor) {
                state.active = false;
                heartbeat.cancel(false);
            }
        }

        boolean owned;
        synchronized (state.monitor) {
            owned = !closed.get() && !state.lost && renewLocked(delivery, state);
        }
        return new ProviderCall<>(value, owned);
    }

    private boolean renew(Delivery delivery, LeaseState state) {
        synchronized (state.monitor) {
            if (!state.active || state.lost || closed.get()) {
                return false;
            }
            return renewLocked(delivery, state);
        }
    }

    private boolean renewLocked(Delivery delivery, LeaseState state) {
        Instant renewNow = clock.instant();
        try {
            boolean renewed = deliveryStore.renewLease(
                    delivery,
                    renewNow,
                    Duration.ofMillis(properties.getFocus().getClaimLeaseMs())
            );
            if (!renewed) {
                state.lost = true;
                state.active = false;
            }
            return renewed;
        } catch (RuntimeException exception) {
            // A transient DB failure does not prove ownership was lost. A later heartbeat or
            // token-guarded finalization will make the authoritative decision.
            log.warn("Could not renew Focus notification delivery lease id={}", delivery.id(), exception);
            return true;
        }
    }

    @Override
    @PreDestroy
    public void close() {
        if (closed.compareAndSet(false, true)) {
            executor.shutdownNow();
        }
    }

    boolean isShutdown() {
        return executor.isShutdown();
    }

    private static ScheduledThreadPoolExecutor executor() {
        ThreadFactory threadFactory = runnable -> {
            Thread thread = new Thread(runnable, "focus-notification-lease-heartbeat");
            thread.setDaemon(true);
            return thread;
        };
        return new ScheduledThreadPoolExecutor(2, threadFactory);
    }

    public record ProviderCall<T>(T value, boolean leaseOwned) {
        static <T> ProviderCall<T> leaseLost() {
            return new ProviderCall<>(null, false);
        }
    }

    private static final class LeaseState {
        private final Object monitor = new Object();
        private boolean active = true;
        private boolean lost;
    }
}
