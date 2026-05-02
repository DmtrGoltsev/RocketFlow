alter table share_invitations
    drop constraint share_invitations_target_type_chk;

alter table share_invitations
    add constraint share_invitations_target_type_chk check (target_type in ('folder', 'goal', 'task'));

create unique index share_invitations_pending_target_user_uq
    on share_invitations (target_type, target_id, target_user_id)
    where status = 'pending' and target_user_id is not null;

create table folder_shares (
    id uuid primary key,
    folder_id uuid not null references folders (id) on delete cascade,
    owner_user_id uuid not null references users (id) on delete cascade,
    collaborator_user_id uuid not null references users (id) on delete cascade,
    invitation_id uuid references share_invitations (id) on delete set null,
    link_id uuid,
    status varchar(16) not null,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    revoked_at timestamptz,
    constraint folder_shares_status_chk check (status in ('active', 'revoked'))
);

create index folder_shares_folder_id_idx on folder_shares (folder_id, status);
create index folder_shares_owner_user_id_idx on folder_shares (owner_user_id, status);
create index folder_shares_collaborator_user_id_idx on folder_shares (collaborator_user_id, status);
create unique index folder_shares_active_folder_collaborator_uq
    on folder_shares (folder_id, collaborator_user_id)
    where status = 'active';
create unique index folder_shares_invitation_id_uq
    on folder_shares (invitation_id)
    where invitation_id is not null;

create table share_links (
    id uuid primary key,
    owner_user_id uuid not null references users (id) on delete cascade,
    target_type varchar(16) not null,
    target_id uuid not null,
    token_hash varchar(64) not null,
    status varchar(16) not null,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    expires_at timestamptz,
    revoked_at timestamptz,
    constraint share_links_target_type_chk check (target_type in ('folder', 'goal', 'task')),
    constraint share_links_status_chk check (status in ('active', 'revoked'))
);

create unique index share_links_token_hash_uq on share_links (token_hash);
create index share_links_owner_target_idx on share_links (owner_user_id, target_type, target_id, status);

alter table folder_shares
    add constraint folder_shares_link_id_fk foreign key (link_id) references share_links (id) on delete set null;

alter table goal_shares
    add column link_id uuid references share_links (id) on delete set null;

alter table task_shares
    add column link_id uuid references share_links (id) on delete set null;

create index folder_shares_link_id_idx on folder_shares (link_id)
    where link_id is not null;
create index goal_shares_link_id_idx on goal_shares (link_id)
    where link_id is not null;
create index task_shares_link_id_idx on task_shares (link_id)
    where link_id is not null;
