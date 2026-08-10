create table web_push_subscriptions (
    id uuid primary key,
    user_id uuid not null references users (id) on delete cascade,
    endpoint text not null,
    endpoint_hash varchar(64) not null,
    p256dh varchar(256) not null,
    auth varchar(256) not null,
    installation_id varchar(120) not null,
    expiration_time timestamptz,
    active boolean not null default true,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    constraint web_push_subscriptions_endpoint_hash_uq unique (endpoint_hash)
);

create unique index web_push_subscriptions_user_installation_uq
    on web_push_subscriptions (user_id, installation_id);
create index web_push_subscriptions_user_active_idx
    on web_push_subscriptions (user_id, active, created_at);

create table focus_notification_deliveries (
    id uuid primary key,
    period_id uuid not null references weekly_focus_periods (id) on delete cascade,
    user_id uuid not null references users (id) on delete cascade,
    channel varchar(16) not null,
    target_id uuid not null,
    cadence_bucket timestamptz not null,
    event_id uuid not null,
    status varchar(32) not null,
    attempt_count integer not null default 0,
    next_attempt_at timestamptz,
    attempted_at timestamptz,
    lease_token uuid,
    lease_expires_at timestamptz,
    provider_response varchar(2000),
    created_at timestamptz not null,
    updated_at timestamptz not null,
    constraint focus_notification_deliveries_channel_chk check (channel in ('fcm', 'web_push')),
    constraint focus_notification_deliveries_attempt_count_chk check (attempt_count >= 0),
    constraint focus_notification_deliveries_lease_chk check (
        (status = 'in_flight' and lease_token is not null and lease_expires_at is not null)
        or (status <> 'in_flight' and lease_token is null and lease_expires_at is null)
    ),
    constraint focus_notification_deliveries_dedupe_uq
        unique (period_id, channel, target_id, cadence_bucket),
    constraint focus_notification_deliveries_event_uq unique (event_id)
);

create index focus_notification_deliveries_retry_idx
    on focus_notification_deliveries (next_attempt_at, created_at)
    where status = 'retry';
create index focus_notification_deliveries_stale_lease_idx
    on focus_notification_deliveries (lease_expires_at, created_at)
    where status = 'in_flight';
create unique index focus_notification_deliveries_lease_token_uq
    on focus_notification_deliveries (lease_token)
    where lease_token is not null;
create unique index focus_notification_deliveries_target_unresolved_uq
    on focus_notification_deliveries (period_id, channel, target_id)
    where status in ('in_flight', 'retry');
create index focus_notification_deliveries_period_idx
    on focus_notification_deliveries (period_id, cadence_bucket desc);
