package com.rocketflow.sharing;

import java.time.Duration;

public final class SharingValues {

    public static final String TARGET_GOAL = "goal";
    public static final String TARGET_TASK = "task";

    public static final String INVITATION_PENDING = "pending";
    public static final String INVITATION_ACCEPTED = "accepted";
    public static final String INVITATION_DECLINED = "declined";
    public static final String INVITATION_REVOKED = "revoked";
    public static final String INVITATION_EXPIRED = "expired";

    public static final String SHARE_ACTIVE = "active";
    public static final String SHARE_REVOKED = "revoked";

    public static final Duration INVITATION_TTL = Duration.ofDays(7);

    private SharingValues() {
    }
}
