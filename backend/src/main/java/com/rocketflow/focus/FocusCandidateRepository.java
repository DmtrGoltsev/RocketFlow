package com.rocketflow.focus;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

import com.rocketflow.tasks.Task;

interface FocusCandidateRepository extends Repository<Task, UUID> {

    @Query(value = """
            with recursive visible_folders(id) as (
                select folder.id
                  from folders folder
                 where folder.parent_folder_id is null
                   and folder.archived = false
                union
                select child.id
                  from folders child
                  join visible_folders parent on parent.id = child.parent_folder_id
                 where child.archived = false
            ), shared_folder_descendants(id) as (
                select share.folder_id
                  from folder_shares share
                 where share.collaborator_user_id = :userId
                   and share.status = 'active'
                union
                select child.id
                  from folders child
                  join shared_folder_descendants parent on parent.id = child.parent_folder_id
            )
            select task.id as "taskId",
                   task.title as "title",
                   task.status as "status",
                   task.effort as "effort",
                   task.planned_time as "plannedTime",
                   task.due_time as "dueTime",
                   task.created_at as "createdAt",
                   goal.id as "goalId",
                   goal.name as "goalTitle",
                   folder.id as "folderId",
                   folder.name as "folderTitle"
              from tasks task
              join goals goal on goal.id = task.goal_id and goal.archived = false
              join folders folder on folder.id = goal.folder_id
              join visible_folders visible_folder on visible_folder.id = folder.id
             where task.deleted_at is null
               and task.archived = false
               and (cast(:folderId as uuid) is null or folder.id = cast(:folderId as uuid))
               and (cast(:goalId as uuid) is null or goal.id = cast(:goalId as uuid))
               and strpos(lower(concat_ws(' ', task.title, goal.name, folder.name)), :queryText) > 0
               and (
                    task.owner_user_id = :userId
                    or exists (
                        select 1 from shared_folder_descendants shared_folder
                         where shared_folder.id = folder.id
                    )
                    or exists (
                        select 1 from goal_shares goal_share
                         where goal_share.goal_id = goal.id
                           and goal_share.collaborator_user_id = :userId
                           and goal_share.status = 'active'
                    )
                    or exists (
                        select 1 from task_shares task_share
                         where task_share.task_id = task.id
                           and task_share.collaborator_user_id = :userId
                           and task_share.status = 'active'
                    )
               )
             order by task.created_at desc, task.id desc
             limit :maxResults offset :offset
            """, nativeQuery = true)
    List<CandidateRow> findVisibleCandidates(
            @Param("userId") UUID userId,
            @Param("queryText") String queryText,
            @Param("folderId") UUID folderId,
            @Param("goalId") UUID goalId,
            @Param("offset") int offset,
            @Param("maxResults") int maxResults
    );

    interface CandidateRow {
        UUID getTaskId();
        String getTitle();
        String getStatus();
        Integer getEffort();
        Instant getPlannedTime();
        Instant getDueTime();
        Instant getCreatedAt();
        UUID getGoalId();
        String getGoalTitle();
        UUID getFolderId();
        String getFolderTitle();
    }
}
