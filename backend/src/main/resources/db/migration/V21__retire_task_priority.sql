alter table tasks
    alter column priority set default 5;

alter table task_reschedule_events
    alter column priority_before set default 5,
    alter column priority_after set default 5;

alter table user_settings
    alter column green_priority_decay_enabled set default false,
    alter column red_priority_decay_enabled set default false;
