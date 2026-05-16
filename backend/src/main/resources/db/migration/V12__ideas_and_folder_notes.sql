create table ideas (
    id uuid primary key,
    folder_id uuid not null references folders (id) on delete cascade,
    owner_user_id uuid not null references users (id) on delete cascade,
    creator_user_id uuid not null references users (id) on delete restrict,
    title varchar(200) not null,
    body varchar(4000),
    status varchar(32) not null default 'active',
    display_order integer not null,
    archived boolean not null default false,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    version bigint not null default 0,
    constraint ideas_status_chk check (length(trim(status)) > 0)
);

create index ideas_folder_owner_idx on ideas (folder_id, owner_user_id, archived, display_order, created_at);
create index ideas_owner_user_id_idx on ideas (owner_user_id);
create index ideas_creator_user_id_idx on ideas (creator_user_id);

create table idea_notes (
    id uuid primary key,
    idea_id uuid not null references ideas (id) on delete cascade,
    owner_user_id uuid not null references users (id) on delete cascade,
    author_user_id uuid not null references users (id) on delete restrict,
    event_type varchar(32) not null,
    body varchar(4000),
    metadata jsonb not null default '{}'::jsonb,
    created_at timestamptz not null,
    constraint idea_notes_event_type_chk check (length(trim(event_type)) > 0)
);

create index idea_notes_idea_id_created_at_idx on idea_notes (idea_id, created_at);
create index idea_notes_owner_user_id_idx on idea_notes (owner_user_id);
create index idea_notes_author_user_id_idx on idea_notes (author_user_id);

create table folder_notes (
    id uuid primary key,
    folder_id uuid not null references folders (id) on delete cascade,
    owner_user_id uuid not null references users (id) on delete cascade,
    author_user_id uuid not null references users (id) on delete restrict,
    kind varchar(16) not null,
    title varchar(200) not null,
    body varchar(4000),
    display_order integer not null,
    archived boolean not null default false,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    version bigint not null default 0,
    constraint folder_notes_kind_chk check (kind in ('note', 'list'))
);

create index folder_notes_folder_owner_idx on folder_notes (folder_id, owner_user_id, archived, display_order, created_at);
create index folder_notes_owner_user_id_idx on folder_notes (owner_user_id);
create index folder_notes_author_user_id_idx on folder_notes (author_user_id);

create table folder_note_items (
    id uuid primary key,
    folder_note_id uuid not null references folder_notes (id) on delete cascade,
    text varchar(1000) not null,
    checked boolean not null default false,
    display_order integer not null,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    version bigint not null default 0
);

create index folder_note_items_note_order_idx on folder_note_items (folder_note_id, display_order, created_at);
