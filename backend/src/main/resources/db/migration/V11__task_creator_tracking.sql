alter table tasks
    add column creator_user_id uuid;

update tasks
set creator_user_id = owner_user_id
where creator_user_id is null;

alter table tasks
    alter column creator_user_id set not null,
    add constraint tasks_creator_user_id_fk foreign key (creator_user_id) references users (id) on delete restrict;

create index tasks_creator_user_id_idx on tasks (creator_user_id);
