create table share_invitations (
    id uuid primary key,
    inviter_user_id uuid not null references users (id) on delete cascade,
    target_type varchar(16) not null,
    target_id uuid not null,
    target_email varchar(320) not null,
    status varchar(16) not null,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    expires_at timestamptz,
    resolved_at timestamptz,
    resolved_by_user_id uuid references users (id) on delete set null,
    constraint share_invitations_target_type_chk check (target_type in ('goal', 'task')),
    constraint share_invitations_status_chk check (status in ('pending', 'accepted', 'declined', 'revoked', 'expired'))
);

create index share_invitations_inviter_user_id_idx on share_invitations (inviter_user_id, status);
create index share_invitations_target_email_idx on share_invitations (lower(target_email), status);
create unique index share_invitations_pending_target_email_uq
    on share_invitations (target_type, target_id, lower(target_email))
    where status = 'pending';

create table goal_shares (
    id uuid primary key,
    goal_id uuid not null references goals (id) on delete cascade,
    owner_user_id uuid not null references users (id) on delete cascade,
    collaborator_user_id uuid not null references users (id) on delete cascade,
    invitation_id uuid references share_invitations (id) on delete set null,
    status varchar(16) not null,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    revoked_at timestamptz,
    constraint goal_shares_status_chk check (status in ('active', 'revoked'))
);

create index goal_shares_goal_id_idx on goal_shares (goal_id, status);
create index goal_shares_owner_user_id_idx on goal_shares (owner_user_id, status);
create index goal_shares_collaborator_user_id_idx on goal_shares (collaborator_user_id, status);
create unique index goal_shares_active_goal_collaborator_uq
    on goal_shares (goal_id, collaborator_user_id)
    where status = 'active';
create unique index goal_shares_invitation_id_uq
    on goal_shares (invitation_id)
    where invitation_id is not null;

create table task_shares (
    id uuid primary key,
    task_id uuid not null references tasks (id) on delete cascade,
    owner_user_id uuid not null references users (id) on delete cascade,
    collaborator_user_id uuid not null references users (id) on delete cascade,
    invitation_id uuid references share_invitations (id) on delete set null,
    status varchar(16) not null,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    revoked_at timestamptz,
    constraint task_shares_status_chk check (status in ('active', 'revoked'))
);

create index task_shares_task_id_idx on task_shares (task_id, status);
create index task_shares_owner_user_id_idx on task_shares (owner_user_id, status);
create index task_shares_collaborator_user_id_idx on task_shares (collaborator_user_id, status);
create unique index task_shares_active_task_collaborator_uq
    on task_shares (task_id, collaborator_user_id)
    where status = 'active';
create unique index task_shares_invitation_id_uq
    on task_shares (invitation_id)
    where invitation_id is not null;
