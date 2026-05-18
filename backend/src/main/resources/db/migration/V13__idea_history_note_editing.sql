alter table ideas
    add column allow_author_note_edits boolean not null default false;

alter table idea_notes
    add column updated_at timestamptz;

update idea_notes
set updated_at = created_at
where updated_at is null;

alter table idea_notes
    alter column updated_at set not null,
    add column version bigint not null default 0;
