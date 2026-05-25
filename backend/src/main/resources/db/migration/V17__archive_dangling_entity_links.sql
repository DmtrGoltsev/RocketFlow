update entity_links link
set archived = true,
    updated_at = now()
where link.archived = false
  and (
        (
          link.source_type = 'task'
          and not exists (
              select 1 from tasks entity
              where entity.id = link.source_id and entity.archived = false
          )
        )
     or (
          link.target_type = 'task'
          and not exists (
              select 1 from tasks entity
              where entity.id = link.target_id and entity.archived = false
          )
        )
     or (
          link.source_type = 'goal'
          and not exists (
              select 1 from goals entity
              where entity.id = link.source_id and entity.archived = false
          )
        )
     or (
          link.target_type = 'goal'
          and not exists (
              select 1 from goals entity
              where entity.id = link.target_id and entity.archived = false
          )
        )
     or (
          link.source_type = 'idea'
          and not exists (
              select 1 from ideas entity
              where entity.id = link.source_id and entity.archived = false
          )
        )
     or (
          link.target_type = 'idea'
          and not exists (
              select 1 from ideas entity
              where entity.id = link.target_id and entity.archived = false
          )
        )
     or (
          link.source_type = 'note'
          and not exists (
              select 1 from notes entity
              where entity.id = link.source_id and entity.archived = false
          )
        )
     or (
          link.target_type = 'note'
          and not exists (
              select 1 from notes entity
              where entity.id = link.target_id and entity.archived = false
          )
        )
  );
