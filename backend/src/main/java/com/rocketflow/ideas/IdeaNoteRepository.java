package com.rocketflow.ideas;

import java.util.List;
import java.util.UUID;

import org.springframework.data.jpa.repository.JpaRepository;

public interface IdeaNoteRepository extends JpaRepository<IdeaNote, UUID> {

    List<IdeaNote> findByIdeaIdAndOwnerUserIdOrderByCreatedAtAsc(UUID ideaId, UUID ownerUserId);
}
