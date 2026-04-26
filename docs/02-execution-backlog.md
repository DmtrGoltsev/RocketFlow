# RocketFlow Execution Backlog

## 1. Planning Goal

This document turns the agreed MVP plan into an execution backlog with:
- implementation waves
- dependency-aware ordering
- parallel work groups
- subagent-sized task briefs
- clear definitions of done

The goal is to keep work small enough that subagents can execute safely without losing context.

## 2. Execution Principles

- keep each task within one main responsibility
- avoid mixing product shaping and implementation in the same task
- stabilize contracts before parallel feature work
- keep Android as a companion scope, not a second full product
- treat localization, testing, and delivery readiness as first-class work
- document every meaningful architectural or delivery decision inside the project repository

## 3. Delivery Waves

### Wave 0. Project Setup and Documentation

Goals:
- create the project document baseline
- preserve the primary plan
- prepare the repo for tracked execution

Tasks:
- create root documentation entrypoint
- save the primary MVP plan
- save the execution backlog
- define the documentation update rule for all future stages

Definition of done:
- the repository contains the project plan and backlog in a stable location
- future contributors know where to update project documentation

### Wave 1. Domain Freeze

Goals:
- remove ambiguity from the product model
- define invariants before code starts

Tasks:
- finalize entity rules for folder, goal, and task
- finalize sharing rules for goal and task
- finalize recurrence model
- finalize reminder rule model
- finalize quick reschedule behavior
- finalize priority decay behavior for `green` and `red`
- finalize localization operating rules

Definition of done:
- business rules are written down
- backend and frontend teams can start without hidden assumptions

### Wave 2. Architecture and Contracts

Goals:
- define implementation boundaries
- reduce rework risk before parallel execution

Tasks:
- create backend module map
- define persistence model direction
- define API surface
- define auth flow
- define Android notification flow
- define localization technical strategy
- define test strategy baseline

Definition of done:
- architecture is stable enough for implementation
- API contracts are clear enough for web and Android

### Wave 3. Backend Foundation

Goals:
- deliver the core application skeleton and the first usable data flow

Tasks:
- bootstrap Spring Boot application structure
- add database configuration and migrations
- implement auth
- implement user settings
- implement folder CRUD
- implement goal CRUD
- implement task CRUD
- add baseline validation and permission checks

Definition of done:
- authenticated users can manage folders, goals, and tasks through stable APIs

### Wave 4. Scheduling and Collaboration

Goals:
- complete the heart of the domain logic

Tasks:
- implement sharing invitations and acceptance flow
- implement goal and task collaborative access checks
- implement recurrence rules
- implement reminder rules
- implement quick reschedule operation
- implement reschedule event history
- implement priority decay evaluation
- implement device registration
- implement notification scheduling and FCM delivery

Definition of done:
- shared collaboration works
- scheduling logic works
- notifications can be delivered to Android devices

### Wave 5. Web MVP

Goals:
- ship the primary usable product experience

Tasks:
- build retro UI shell
- add Russian-first localization infrastructure
- add English localization support
- enforce key synchronization checks
- implement login and registration UI
- implement folders and goals navigation
- implement task creation and editing
- implement simple calendar
- implement quick reschedule UI
- implement settings UI
- implement sharing UI

Definition of done:
- users can complete the main web journeys end to end

### Wave 6. Android Companion

Goals:
- deliver the companion experience without expanding scope too far

Tasks:
- implement login
- implement task and goal browsing
- implement task detail screen
- implement device token registration
- implement push reception
- implement open task from notification

Definition of done:
- Android users can authenticate, browse, and receive notifications

### Wave 7. QA and Release Readiness

Goals:
- verify product stability and release the MVP responsibly

Tasks:
- run backend regression tests
- run web smoke and journey tests
- verify sharing permissions
- verify recurrence and reminder behavior
- verify priority decay behavior
- verify localization switching and key synchronization
- verify Android notification flow
- prepare deployment checklist
- prepare environment configuration guide

Definition of done:
- the MVP is testable, deployable, and understandable for the next implementation stage

## 4. Critical Path

Critical path:
1. documentation baseline
2. domain freeze
3. architecture and contracts
4. backend foundation
5. scheduling and collaboration
6. web MVP
7. Android companion
8. QA and release readiness

Safe parallel groups after architecture stabilizes:
- backend auth/settings and documentation refinements
- retro web shell and localization infrastructure
- CI/CD baseline and QA plan drafting
- Android app skeleton after auth and core task DTOs are stable

## 5. Detailed Subagent Task Briefs

### Task 1. Domain Specification

Role:
- Product/System Analyst

Objective:
- document the exact business rules for the MVP domain

Inputs:
- current primary plan
- confirmed product decisions from discussion

Expected outputs:
- domain glossary
- entity rules
- invariants
- unresolved edge cases list if needed

Definition of done:
- folder, goal, task, sharing, recurrence, reminder, reschedule, and priority decay rules are explicit

Out of bounds:
- implementation code

Parallel or sequential:
- sequential

### Task 2. Architecture Blueprint

Role:
- Solution Architect

Objective:
- define the modular backend architecture, storage direction, and API boundaries

Inputs:
- domain specification

Expected outputs:
- module map
- entity relationship direction
- API outline
- integration points
- technical risk list

Definition of done:
- implementation teams can start with stable architectural boundaries

Out of bounds:
- writing feature code

Parallel or sequential:
- sequential

### Task 3. QA Strategy

Role:
- QA Lead

Objective:
- turn product rules into a concrete test strategy early

Inputs:
- primary plan
- domain specification
- architecture blueprint

Expected outputs:
- test matrix
- high-risk scenarios
- smoke criteria
- release acceptance checklist draft

Definition of done:
- risky areas have explicit validation strategy before feature implementation grows

Out of bounds:
- test automation implementation unless specifically assigned later

Parallel or sequential:
- parallel after architecture starts stabilizing

### Task 4. Backend Auth and Settings

Role:
- Backend Engineer

Objective:
- implement authentication, profile basics, and user settings

Inputs:
- architecture blueprint
- API contracts

Expected outputs:
- auth endpoints
- user settings endpoints
- language preference support
- tests

Definition of done:
- a user can register, log in, and save settings

Out of bounds:
- folders, goals, tasks

Parallel or sequential:
- parallel with infrastructure tasks after contracts stabilize

### Task 5. Backend Folder, Goal, Task CRUD

Role:
- Backend Engineer

Objective:
- implement the core domain CRUD APIs

Inputs:
- domain rules
- API contracts

Expected outputs:
- folder, goal, task persistence and endpoints
- validation
- tests

Definition of done:
- authenticated CRUD for the three core entities is complete

Out of bounds:
- sharing
- recurrence
- reminder delivery

Parallel or sequential:
- sequential after auth baseline

### Task 6. Backend Sharing

Role:
- Backend Engineer

Objective:
- implement invitations and collaborative editing access

Inputs:
- sharing rules
- auth baseline
- goal/task models

Expected outputs:
- invitation flow
- share acceptance
- access checks
- tests

Definition of done:
- shared goals and tasks can be edited only by authorized users

Out of bounds:
- folder sharing

Parallel or sequential:
- sequential after core CRUD

### Task 7. Backend Scheduling Engine

Role:
- Backend Engineer

Objective:
- implement recurrence, reminders, quick reschedule, and priority decay

Inputs:
- recurrence and reminder rules
- task model
- user settings model

Expected outputs:
- recurrence logic
- reminder logic
- reschedule events
- priority decay evaluation
- tests

Definition of done:
- scheduling-related domain logic works predictably and is covered by focused tests

Out of bounds:
- Android delivery UI

Parallel or sequential:
- sequential after core CRUD, parallelizable in parts with sharing if boundaries stay clean

### Task 8. Notification Delivery

Role:
- Backend Engineer / Platform Engineer

Objective:
- deliver Android push notifications through FCM

Inputs:
- scheduling engine outputs
- Android token model

Expected outputs:
- device registration endpoints
- delivery scheduler
- FCM sender integration
- delivery logging

Definition of done:
- a due reminder can trigger a push notification to a registered Android device

Out of bounds:
- web notification UI

Parallel or sequential:
- sequential after reminder scheduling design is stable

### Task 9. Web Retro Shell and Localization

Role:
- Frontend Engineer

Objective:
- create the main UI shell and bilingual infrastructure

Inputs:
- architecture blueprint
- localization rules
- product UI direction

Expected outputs:
- application shell
- retro visual tokens
- Russian-first language files
- English mirrored language files
- settings-based language switch
- localization sync check

Definition of done:
- the app shell is usable and language switching works

Out of bounds:
- full task flows

Parallel or sequential:
- parallel after auth and core DTO direction are stable

### Task 10. Web Main Flows

Role:
- Frontend Engineer

Objective:
- implement the core user journeys on the web client

Inputs:
- web shell
- auth APIs
- folders/goals/tasks APIs

Expected outputs:
- login and registration screens
- folders and goals navigation
- task create/edit/delete flows
- simple calendar
- quick reschedule UI

Definition of done:
- a user can complete the main planning workflow entirely in the web client

Out of bounds:
- Android-specific concerns

Parallel or sequential:
- sequential after web shell and core APIs

### Task 11. Web Sharing and Settings

Role:
- Frontend Engineer

Objective:
- implement UI for sharing and advanced settings

Inputs:
- sharing APIs
- settings APIs
- notification and priority decay policies

Expected outputs:
- sharing dialogs
- invitation handling UI where applicable
- language settings
- priority decay settings for `green` and `red`
- reminder settings UI

Definition of done:
- collaboration and settings are manageable from the web client

Out of bounds:
- Android notification handling

Parallel or sequential:
- sequential after sharing and settings backend

### Task 12. Android Companion App

Role:
- Mobile Engineer

Objective:
- implement the Android companion experience

Inputs:
- auth APIs
- task and goal DTOs
- notification delivery contract

Expected outputs:
- login
- goal and task browsing
- task detail
- push handling
- open-from-notification behavior

Definition of done:
- Android supports the companion scenarios required for MVP

Out of bounds:
- full calendar editing parity with web

Parallel or sequential:
- parallel after auth and DTO stability

### Task 13. DevOps Baseline

Role:
- DevOps Engineer

Objective:
- prepare a minimal but reliable delivery pipeline

Inputs:
- architecture blueprint

Expected outputs:
- environment variable map
- build and test pipeline direction
- deployment shape
- secret handling notes

Definition of done:
- the team has a repeatable deployment baseline for MVP work

Out of bounds:
- feature implementation

Parallel or sequential:
- parallel after architecture

### Task 14. QA Hardening and Release Readiness

Role:
- QA Lead

Objective:
- validate the assembled MVP and prepare release confidence

Inputs:
- completed backend, web, and Android flows

Expected outputs:
- regression results
- bug list
- release checklist
- residual risk report

Definition of done:
- the MVP has explicit release confidence and known residual risks

Out of bounds:
- feature expansion

Parallel or sequential:
- final sequential wave

## 6. Suggested Queue Order

Recommended queue:

1. documentation baseline
2. domain specification
3. architecture blueprint
4. QA strategy
5. DevOps baseline
6. backend auth and settings
7. backend folder, goal, task CRUD
8. web retro shell and localization
9. backend sharing
10. backend scheduling engine
11. notification delivery
12. web main flows
13. web sharing and settings
14. Android companion app
15. QA hardening and release readiness

## 7. Documentation Rule

All meaningful work stages must be documented in the `RocketFlow` repository.

Minimum rule:
- each completed stage updates or adds documentation under `docs/`
- architecture changes must update the relevant architecture or planning document
- new product decisions must be recorded before or alongside implementation
- localization operating rules must stay documented as the source language model evolves

Suggested future documents:
- `docs/03-domain-specification.md`
- `docs/04-architecture-blueprint.md`
- `docs/05-api-contracts.md`
- `docs/06-qa-strategy.md`
- `docs/07-release-readiness.md`
