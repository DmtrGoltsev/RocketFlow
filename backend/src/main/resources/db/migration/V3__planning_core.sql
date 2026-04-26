create table folders (
    id uuid primary key,
    owner_user_id uuid not null references users (id) on delete cascade,
    name varchar(160) not null,
    description varchar(1000),
    display_order integer not null,
    archived boolean not null default false,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    version bigint not null default 0
);

create index folders_owner_user_id_idx on folders (owner_user_id);

create table goals (
    id uuid primary key,
    folder_id uuid not null references folders (id) on delete cascade,
    owner_user_id uuid not null references users (id) on delete cascade,
    name varchar(160) not null,
    description varchar(1000),
    archived boolean not null default false,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    version bigint not null default 0
);

create index goals_folder_id_idx on goals (folder_id);
create index goals_owner_user_id_idx on goals (owner_user_id);

create table task_tags (
    id uuid primary key,
    owner_user_id uuid not null references users (id) on delete cascade,
    name varchar(80) not null,
    color varchar(16),
    created_at timestamptz not null,
    updated_at timestamptz not null
);

create unique index task_tags_owner_name_uq on task_tags (owner_user_id, lower(name));

create table tasks (
    id uuid primary key,
    goal_id uuid not null references goals (id) on delete cascade,
    owner_user_id uuid not null references users (id) on delete cascade,
    title varchar(200) not null,
    description varchar(2000),
    type varchar(16) not null,
    priority integer not null,
    status varchar(32) not null,
    planned_time timestamptz,
    due_time timestamptz,
    completed_at timestamptz,
    archived boolean not null default false,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    version bigint not null default 0,
    constraint tasks_type_chk check (type in ('green', 'red')),
    constraint tasks_priority_chk check (priority between 1 and 10),
    constraint tasks_status_chk check (status in ('todo', 'in_progress', 'done', 'cancelled'))
);

create index tasks_goal_id_idx on tasks (goal_id);
create index tasks_owner_user_id_idx on tasks (owner_user_id);
create index tasks_planned_time_idx on tasks (planned_time);

create table task_tag_links (
    task_id uuid not null references tasks (id) on delete cascade,
    tag_id uuid not null references task_tags (id) on delete cascade,
    primary key (task_id, tag_id)
);
