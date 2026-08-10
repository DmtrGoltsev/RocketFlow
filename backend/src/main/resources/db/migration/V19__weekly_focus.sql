alter table tasks
    add column deleted_at timestamptz null;

create index tasks_deleted_at_idx on tasks (deleted_at) where deleted_at is not null;

create table weekly_focus_periods (
    id uuid primary key,
    user_id uuid not null references users (id) on delete cascade,
    week_start date not null,
    week_end_exclusive date not null,
    starts_at timestamptz not null,
    ends_at timestamptz not null,
    timezone_snapshot varchar(64) not null,
    status varchar(16) not null,
    previous_period_id uuid references weekly_focus_periods (id) on delete set null,
    rollover_resolved_at timestamptz,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    version bigint not null default 0,
    constraint weekly_focus_periods_status_chk check (status in ('active', 'completed')),
    constraint weekly_focus_periods_dates_chk check (week_end_exclusive = week_start + 7),
    constraint weekly_focus_periods_bounds_chk check (ends_at > starts_at),
    unique (user_id, week_start)
);

create unique index weekly_focus_periods_one_active_uq
    on weekly_focus_periods (user_id) where status = 'active';
create index weekly_focus_periods_user_history_idx
    on weekly_focus_periods (user_id, week_start desc);

create table weekly_focus_items (
    id uuid primary key,
    period_id uuid not null references weekly_focus_periods (id) on delete cascade,
    task_id uuid not null,
    position integer not null,
    history_only boolean not null default false,
    snapshot_title varchar(200) not null,
    snapshot_status varchar(32) not null,
    snapshot_effort integer,
    snapshot_effective_weight integer not null,
    snapshot_planned_time timestamptz,
    snapshot_due_time timestamptz,
    snapshot_folder_id uuid,
    snapshot_folder_title varchar(160),
    snapshot_goal_id uuid,
    snapshot_goal_title varchar(160),
    snapshot_shared boolean not null,
    snapshot_can_write boolean not null,
    snapshot_at timestamptz not null,
    added_at timestamptz not null,
    updated_at timestamptz not null,
    version bigint not null default 0,
    constraint weekly_focus_items_weight_chk check (snapshot_effective_weight > 0),
    constraint weekly_focus_items_position_chk check (position >= 0),
    unique (period_id, task_id),
    unique (period_id, position)
);

create index weekly_focus_items_period_idx on weekly_focus_items (period_id, position);
create index weekly_focus_items_task_idx on weekly_focus_items (task_id);

create table focus_notification_settings (
    user_id uuid primary key references users (id) on delete cascade,
    interval_minutes integer,
    quiet_hours_start time,
    quiet_hours_end time,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    version bigint not null default 0,
    constraint focus_notification_settings_interval_chk
        check (interval_minutes is null or interval_minutes in (30, 60, 120, 240)),
    constraint focus_notification_settings_quiet_pair_chk
        check ((quiet_hours_start is null) = (quiet_hours_end is null))
);

create table focus_idempotency_keys (
    user_id uuid not null references users (id) on delete cascade,
    idempotency_key varchar(128) not null,
    operation varchar(48) not null,
    created_at timestamptz not null,
    primary key (user_id, idempotency_key)
);

create index focus_idempotency_keys_created_at_idx on focus_idempotency_keys (created_at);
