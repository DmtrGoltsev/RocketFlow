create table users (
    id uuid primary key,
    email varchar(320) not null,
    display_name varchar(120) not null,
    timezone varchar(64) not null,
    active boolean not null default true,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    version bigint not null default 0
);

create unique index users_email_uq on users (lower(email));

create table user_credentials (
    user_id uuid primary key references users (id) on delete cascade,
    password_hash varchar(255) not null,
    password_updated_at timestamptz not null,
    created_at timestamptz not null,
    updated_at timestamptz not null
);

create table user_settings (
    user_id uuid primary key references users (id) on delete cascade,
    language varchar(8) not null,
    notifications_enabled boolean not null default true,
    green_priority_decay_enabled boolean not null default true,
    green_priority_decay_threshold varchar(16) not null,
    green_priority_decay_amount integer not null,
    red_priority_decay_enabled boolean not null default true,
    red_priority_decay_threshold varchar(16) not null,
    red_priority_decay_amount integer not null,
    created_at timestamptz not null,
    updated_at timestamptz not null,
    version bigint not null default 0,
    constraint user_settings_language_chk check (language in ('ru', 'en')),
    constraint user_settings_green_threshold_chk check (green_priority_decay_threshold in ('day', 'week', 'month')),
    constraint user_settings_red_threshold_chk check (red_priority_decay_threshold in ('day', 'week', 'month')),
    constraint user_settings_green_amount_chk check (green_priority_decay_amount > 0),
    constraint user_settings_red_amount_chk check (red_priority_decay_amount > 0)
);
