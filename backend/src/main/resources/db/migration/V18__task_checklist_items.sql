create table task_checklist_items (
    id uuid primary key,
    task_id uuid not null references tasks (id) on delete cascade,
    text varchar(500) not null,
    checked boolean not null default false,
    display_order integer not null,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    version bigint not null default 0,
    constraint task_checklist_items_text_nonblank_chk check (length(btrim(text)) > 0)
);

create index task_checklist_items_task_id_order_idx on task_checklist_items (task_id, display_order, created_at, id);
