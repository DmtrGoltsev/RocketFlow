alter table share_invitations
    drop constraint share_invitations_target_type_chk;

alter table share_invitations
    add constraint share_invitations_target_type_chk check (target_type in ('folder', 'goal', 'task', 'idea'));

alter table share_links
    drop constraint share_links_target_type_chk;

alter table share_links
    add constraint share_links_target_type_chk check (target_type in ('folder', 'goal', 'task', 'idea'));

create table idea_shares (
    id uuid primary key,
    idea_id uuid not null references ideas (id) on delete cascade,
    owner_user_id uuid not null references users (id) on delete cascade,
    collaborator_user_id uuid not null references users (id) on delete cascade,
    invitation_id uuid references share_invitations (id) on delete set null,
    link_id uuid references share_links (id) on delete set null,
    status varchar(16) not null,
    full_access boolean not null default false,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    revoked_at timestamptz,
    constraint idea_shares_status_chk check (status in ('active', 'revoked'))
);

create index idea_shares_idea_id_idx on idea_shares (idea_id, status);
create index idea_shares_owner_user_id_idx on idea_shares (owner_user_id, status);
create index idea_shares_collaborator_user_id_idx on idea_shares (collaborator_user_id, status);
create index idea_shares_link_id_idx on idea_shares (link_id)
    where link_id is not null;

create unique index idea_shares_active_idea_collaborator_uq
    on idea_shares (idea_id, collaborator_user_id)
    where status = 'active';
create unique index idea_shares_invitation_id_uq
    on idea_shares (invitation_id)
    where invitation_id is not null;
