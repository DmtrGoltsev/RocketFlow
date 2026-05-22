alter table tasks
    add column effort integer not null default 0;

alter table tasks
    add constraint tasks_effort_chk check (effort >= 0);
