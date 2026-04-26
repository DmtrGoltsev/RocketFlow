create table device_registrations (
    id uuid primary key,
    user_id uuid not null references users (id) on delete cascade,
    push_token varchar(1024) not null,
    device_name varchar(120),
    platform varchar(32) not null,
    active boolean not null default true,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    constraint device_registrations_platform_chk check (platform in ('android'))
);

create unique index device_registrations_push_token_uq on device_registrations (push_token);
create index device_registrations_user_active_idx on device_registrations (user_id, active);

create table notification_deliveries (
    id uuid primary key,
    task_id uuid not null references tasks (id) on delete cascade,
    reminder_rule_id uuid not null references task_reminder_rules (id) on delete cascade,
    device_registration_id uuid references device_registrations (id) on delete set null,
    scheduled_at timestamptz not null,
    attempted_at timestamptz,
    status varchar(48) not null,
    provider_response varchar(2000),
    created_at timestamptz not null,
    constraint notification_deliveries_status_chk check (
        status in ('sent', 'failed', 'skipped_notifications_disabled', 'skipped_no_active_device')
    )
);

create index notification_deliveries_task_scheduled_idx on notification_deliveries (task_id, scheduled_at);
create index notification_deliveries_reminder_scheduled_idx on notification_deliveries (reminder_rule_id, scheduled_at);
create unique index notification_deliveries_device_dedupe_uq
    on notification_deliveries (task_id, reminder_rule_id, scheduled_at, device_registration_id)
    where device_registration_id is not null;
create unique index notification_deliveries_skip_dedupe_uq
    on notification_deliveries (task_id, reminder_rule_id, scheduled_at)
    where device_registration_id is null;
