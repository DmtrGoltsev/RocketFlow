package com.rocketflow.common;

import java.util.Comparator;
import java.util.UUID;

public final class UuidOrder {

    // PostgreSQL orders UUIDs by their unsigned bytes; canonical strings preserve that order.
    public static final Comparator<UUID> POSTGRES_ASC = Comparator.comparing(UUID::toString);

    private UuidOrder() {
    }
}
