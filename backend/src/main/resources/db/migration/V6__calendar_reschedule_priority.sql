create table task_reschedule_events (
    id uuid primary key,
    task_id uuid not null references tasks (id) on delete cascade,
    rescheduled_by_user_id uuid not null references users (id) on delete cascade,
    previous_planned_time timestamptz not null,
    new_planned_time timestamptz not null,
    reason varchar(500),
    priority_before integer not null,
    priority_after integer not null,
    priority_decay_applied boolean not null default false,
    created_at timestamptz not null,
    constraint task_reschedule_events_planned_time_chk check (new_planned_time > previous_planned_time),
    constraint task_reschedule_events_priority_before_chk check (priority_before between 1 and 10),
    constraint task_reschedule_events_priority_after_chk check (priority_after between 1 and 10)
);

create index task_reschedule_events_task_id_idx on task_reschedule_events (task_id, created_at);
create index task_reschedule_events_rescheduled_by_user_id_idx on task_reschedule_events (rescheduled_by_user_id, created_at);
