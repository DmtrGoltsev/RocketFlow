package com.rocketflow.notifications;

import static com.rocketflow.notifications.DevicesApi.*;

import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.rocketflow.accounts.CurrentUserService;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api")
public class DeviceController {

    private final DevicesService devicesService;
    private final CurrentUserService currentUserService;

    public DeviceController(DevicesService devicesService, CurrentUserService currentUserService) {
        this.devicesService = devicesService;
        this.currentUserService = currentUserService;
    }

    @PostMapping("/devices")
    @ResponseStatus(HttpStatus.CREATED)
    public DeviceRegistrationResponse register(@Valid @RequestBody RegisterDeviceRequest request) {
        return devicesService.register(currentUserService.requireAuthenticatedUser().userId(), request);
    }

    @DeleteMapping("/devices/{deviceId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable String deviceId) {
        devicesService.deactivate(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(deviceId));
    }
}
