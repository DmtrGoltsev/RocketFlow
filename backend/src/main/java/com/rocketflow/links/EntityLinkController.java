package com.rocketflow.links;

import static com.rocketflow.links.LinksApi.*;

import java.util.UUID;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.rocketflow.accounts.CurrentUserService;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/entity-links")
public class EntityLinkController {

    private final EntityLinkService entityLinkService;
    private final CurrentUserService currentUserService;

    public EntityLinkController(EntityLinkService entityLinkService, CurrentUserService currentUserService) {
        this.entityLinkService = entityLinkService;
        this.currentUserService = currentUserService;
    }

    @GetMapping
    public EntityLinkListResponse list(@RequestParam String entityType, @RequestParam String entityId) {
        return entityLinkService.list(
                currentUserService.requireAuthenticatedUser().userId(),
                entityType,
                UUID.fromString(entityId)
        );
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public EntityLinkDto create(@Valid @RequestBody CreateEntityLinkRequest request) {
        return entityLinkService.create(currentUserService.requireAuthenticatedUser().userId(), request);
    }

    @PatchMapping("/{linkId}")
    public EntityLinkDto update(@PathVariable String linkId, @Valid @RequestBody UpdateEntityLinkRequest request) {
        return entityLinkService.update(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(linkId), request);
    }

    @DeleteMapping("/{linkId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable String linkId) {
        entityLinkService.delete(currentUserService.requireAuthenticatedUser().userId(), UUID.fromString(linkId));
    }
}
