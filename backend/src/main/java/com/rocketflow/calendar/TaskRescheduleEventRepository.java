package com.rocketflow.calendar;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface TaskRescheduleEventRepository extends JpaRepository<TaskRescheduleEvent, UUID> {

    List<TaskRescheduleEvent> findByTaskIdOrderByCreatedAtAsc(UUID taskId);
}
