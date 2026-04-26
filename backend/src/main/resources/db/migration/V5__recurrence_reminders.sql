create table task_recurrence_rules (
    id uuid primary key,
    task_id uuid not null unique references tasks (id) on delete cascade,
    mode varchar(32) not null,
    interval_value integer not null,
    days_of_week varchar(128),
    day_of_month integer,
    start_at timestamptz not null,
    end_at timestamptz,
    active boolean not null default true,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    constraint task_recurrence_rules_mode_chk check (mode in ('daily', 'weekly', 'monthly')),
    constraint task_recurrence_rules_interval_chk check (interval_value > 0),
    constraint task_recurrence_rules_day_of_month_chk check (day_of_month is null or day_of_month between 1 and 31),
    constraint task_recurrence_rules_dates_chk check (end_at is null or end_at > start_at)
);

create index task_recurrence_rules_task_id_idx on task_recurrence_rules (task_id);

create table task_reminder_rules (
    id uuid primary key,
    task_id uuid not null references tasks (id) on delete cascade,
    mode varchar(32) not null,
    offset_minutes integer not null,
    active boolean not null default true,
    sort_order integer not null,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    constraint task_reminder_rules_mode_chk check (mode in ('before_planned_time', 'before_due_time')),
    constraint task_reminder_rules_offset_chk check (offset_minutes > 0),
    constraint task_reminder_rules_sort_order_chk check (sort_order >= 0)
);

create index task_reminder_rules_task_id_idx on task_reminder_rules (task_id);
create unique index task_reminder_rules_task_sort_uq on task_reminder_rules (task_id, sort_order);
