alter table folders
    add column parent_folder_id uuid references folders (id) on delete cascade;

create index folders_owner_parent_archived_order_idx
    on folders (owner_user_id, parent_folder_id, archived, display_order, created_at);
create index folders_parent_folder_id_idx on folders (parent_folder_id);

alter table goals
    add column status varchar(32) not null default 'todo',
    add constraint goals_status_chk check (status in ('todo', 'in_progress', 'done', 'cancelled'));

create index goals_folder_status_archived_idx on goals (folder_id, status, archived);

create table notes (
    id uuid primary key,
    folder_id uuid not null references folders (id) on delete cascade,
    owner_user_id uuid not null references users (id) on delete cascade,
    author_user_id uuid not null references users (id) on delete restrict,
    title varchar(200) not null,
    body varchar(4000),
    display_order integer not null,
    archived boolean not null default false,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    version bigint not null default 0
);

create index notes_folder_owner_idx on notes (folder_id, owner_user_id, archived, display_order, created_at);
create index notes_owner_user_id_idx on notes (owner_user_id);
create index notes_author_user_id_idx on notes (author_user_id);

create table entity_links (
    id uuid primary key,
    owner_user_id uuid not null references users (id) on delete cascade,
    source_type varchar(16) not null,
    source_id uuid not null,
    target_type varchar(16) not null,
    target_id uuid not null,
    relation_type varchar(16) not null,
    created_by_user_id uuid not null references users (id) on delete restrict,
    archived boolean not null default false,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    version bigint not null default 0,
    constraint entity_links_source_type_chk check (source_type in ('goal', 'task', 'idea', 'note')),
    constraint entity_links_target_type_chk check (target_type in ('goal', 'task', 'idea', 'note')),
    constraint entity_links_relation_type_chk check (relation_type in ('related', 'dependency')),
    constraint entity_links_not_self_chk check (source_type <> target_type or source_id <> target_id),
    constraint entity_links_dependency_task_task_chk check (
        relation_type <> 'dependency' or (source_type = 'task' and target_type = 'task')
    )
);

create unique index entity_links_active_exact_uq
    on entity_links (source_type, source_id, target_type, target_id, relation_type)
    where archived = false;
create index entity_links_source_idx on entity_links (source_type, source_id, archived);
create index entity_links_target_idx on entity_links (target_type, target_id, archived);
create index entity_links_owner_idx on entity_links (owner_user_id, archived);

alter table share_invitations
    add column full_access boolean not null default false;

alter table share_links
    add column full_access boolean not null default false;

alter table folder_shares
    add column full_access boolean not null default false;

alter table goal_shares
    add column full_access boolean not null default false;

alter table task_shares
    add column full_access boolean not null default false;

drop table if exists folder_note_items cascade;
drop table if exists folder_notes cascade;
