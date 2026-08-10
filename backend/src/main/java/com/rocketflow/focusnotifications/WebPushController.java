package com.rocketflow.focusnotifications;

import static com.rocketflow.focusnotifications.WebPushApi.*;

import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.rocketflow.accounts.CurrentUserService;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/notifications/web-push")
public class WebPushController {
    private final WebPushSubscriptionService service;
    private final CurrentUserService currentUserService;

    public WebPushController(WebPushSubscriptionService service, CurrentUserService currentUserService) {
        this.service = service;
        this.currentUserService = currentUserService;
    }

    @GetMapping("/config")
    public ConfigResponse config() {
        return service.config();
    }

    @PostMapping("/subscriptions")
    @ResponseStatus(HttpStatus.CREATED)
    public SubscriptionResponse register(@Valid @RequestBody RegisterSubscriptionRequest request) {
        return service.register(userId(), request);
    }

    @DeleteMapping("/subscriptions/{subscriptionId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID subscriptionId) {
        service.deactivate(userId(), subscriptionId);
    }

    private UUID userId() {
        return currentUserService.requireAuthenticatedUser().userId();
    }
}
