package com.rocketflow.auth;

import java.security.Principal;
import java.util.UUID;

public record AuthenticatedUser(UUID userId, String email) implements Principal {

    @Override
    public String getName() {
        return email;
    }
}
