package com.rocketflow.focus;

import java.sql.Timestamp;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.UUID;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class FocusLifecycleService {
    private final JdbcTemplate jdbcTemplate;

    public FocusLifecycleService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @Transactional
    public void archiveTask(UUID taskId) {
        archiveTasks(List.of(taskId));
    }

    @Transactional
    public void archiveTasks(Collection<UUID> taskIds) {
        mutateActiveItems(taskIds, false);
    }

    @Transactional
    public void deleteTask(UUID taskId) {
        deleteTasks(List.of(taskId));
    }

    @Transactional
    public void deleteTasks(Collection<UUID> taskIds) {
        mutateActiveItems(taskIds, true);
    }

    private void mutateActiveItems(Collection<UUID> taskIds, boolean delete) {
        List<UUID> ids = taskIds == null ? List.of() : taskIds.stream().distinct().toList();
        if (ids.isEmpty()) {
            return;
        }
        String placeholders = String.join(",", java.util.Collections.nCopies(ids.size(), "?"));
        Object[] arguments = ids.toArray();
        Timestamp now = Timestamp.from(Instant.now());

        jdbcTemplate.update("""
                update weekly_focus_periods period
                   set updated_at = ?, version = version + 1
                 where period.status = 'active'
                   and exists (
                       select 1 from weekly_focus_items item
                        where item.period_id = period.id
                          and item.task_id in (%s)
                          and (? or item.history_only = false)
                   )
                """.formatted(placeholders), prependAndAppend(arguments, now, delete));

        if (delete) {
            jdbcTemplate.update("""
                    delete from weekly_focus_items item
                     using weekly_focus_periods period
                     where item.period_id = period.id
                       and period.status = 'active'
                       and item.task_id in (%s)
                    """.formatted(placeholders), arguments);
        } else {
            jdbcTemplate.update("""
                    update weekly_focus_items item
                       set history_only = true, updated_at = ?, version = item.version + 1
                      from weekly_focus_periods period
                     where item.period_id = period.id
                       and period.status = 'active'
                       and item.history_only = false
                       and item.task_id in (%s)
                    """.formatted(placeholders), prepend(arguments, now));
        }
    }

    private Object[] prepend(Object[] values, Object first) {
        Object[] result = new Object[values.length + 1];
        result[0] = first;
        System.arraycopy(values, 0, result, 1, values.length);
        return result;
    }

    private Object[] prependAndAppend(Object[] values, Object first, Object last) {
        Object[] result = new Object[values.length + 2];
        result[0] = first;
        System.arraycopy(values, 0, result, 1, values.length);
        result[result.length - 1] = last;
        return result;
    }
}
