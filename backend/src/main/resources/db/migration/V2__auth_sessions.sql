create table auth_sessions (
    id uuid primary key,
    user_id uuid not null references users (id) on delete cascade,
    access_token_hash varchar(64) not null,
    refresh_token_hash varchar(64) not null,
    access_expires_at timestamptz not null,
    refresh_expires_at timestamptz not null,
    revoked_at timestamptz null,
    created_at timestamptz not null,
    updated_at timestamptz not null
);

create unique index auth_sessions_access_token_hash_uq on auth_sessions (access_token_hash);
create unique index auth_sessions_refresh_token_hash_uq on auth_sessions (refresh_token_hash);
create index auth_sessions_user_id_idx on auth_sessions (user_id);
