# RocketFlow Primary MVP Plan

## 1. Business Idea Restatement

RocketFlow is a web-first task and goal planning application with a very simple retro interface inspired by the 1990s and 2000s. The product combines folders, goals, tasks, calendar planning, collaboration, recurring tasks, Android notifications, and bilingual support with Russian as the primary language and English as the secondary language.

The MVP includes:
- a web client as the primary working interface
- an Android companion client for viewing goals and tasks and receiving push notifications
- a Java backend
- a simple calendar view
- collaboration through shared goals and tasks
- quick task rescheduling
- configurable automatic priority decay after repeated postponement

## 2. Product Framing

### Product Summary

Users create folders, place goals inside folders, and create tasks inside goals. Tasks can be scheduled on a calendar, tagged, linked, shared, repeated, and postponed. Tasks are intentionally categorized by outcome type:
- `green`: doing the task moves the user toward success; not doing it keeps life as it is
- `red`: not doing the task causes negative consequences; doing it only preserves the current state

### Business Objective

Deliver an MVP that helps users:
- structure personal and work planning around goals
- distinguish growth work from maintenance or pressure-driven work
- schedule tasks in a simple calendar
- collaborate with one more account on goals and tasks
- receive timely reminders on Android

### User Roles

- `Owner`: the user who creates folders, goals, and tasks
- `Collaborator`: a user invited by email to edit a shared goal or task

### Primary User Journeys

- register and log in using email and password
- create a folder
- create one or more goals inside the folder
- create tasks inside a goal
- set task type to `green` or `red`
- assign task priority from `1` to `10`
- assign due date, planned time, reminder rules, and recurrence rules
- view tasks in a simple calendar
- quickly postpone a task using one click
- share a goal or task with another account
- switch the interface language between Russian and English in settings

### MVP Scope

- email and password authentication
- user profile and settings
- folders
- goals
- tasks
- tags and task links
- `green` and `red` task types
- priority `1..10`
- due date and planned date/time
- flexible recurrence
- flexible reminders
- simple calendar
- quick reschedule presets: `30 minutes`, `1 hour`, `3 hours`, `24 hours`
- automatic priority decay after postponement
- separate priority decay rules for `green` and `red`
- sharing at goal and task level with edit access
- Android push notifications
- Russian and English localization with Russian as the source language
- language switching in settings
- localization file synchronization as an explicit engineering responsibility

### Non-MVP Scope

- sharing at folder level
- advanced roles and permissions
- comments and chat
- file attachments
- audit history visible in UI
- offline mode
- desktop application
- advanced analytics and reporting
- complex real-time collaborative editing
- arbitrary enterprise-grade recurrence rule grammar

## 3. Confirmed Product Rules

### Folder, Goal, Task Hierarchy

- a folder contains multiple goals
- a goal belongs to exactly one folder
- a task belongs to exactly one goal
- a folder is not the same thing as a goal

Example:
- folder: `Work`
- goals inside it: `Promotion`, `Team Growth`

### Sharing

- only goals and tasks can be shared in MVP
- shared access is collaborative editing access
- invitations are tied to email
- owner remains the single owner

### Calendar

- the calendar in MVP is intentionally simple
- users can move, edit, and delete tasks
- the web client is the primary place for calendar management

### Recurrence

- recurrence is flexible
- recurrence support must be designed deliberately to avoid overcomplicating the MVP

### Quick Reschedule

- tasks support a one-click postpone action
- the action opens preset options:
  - `30 minutes`
  - `1 hour`
  - `3 hours`
  - `24 hours`
- every postpone action must be stored as a separate event

### Priority Decay

- repeated postponement may reduce task priority automatically
- priority decay is configured separately for `green` and `red` tasks
- each task type has its own rule
- initial supported thresholds:
  - `1 day`
  - `1 week`
  - `1 month`
- example: every `24 hours` of postponement subtracts `1` priority point
- priority must never go below `1`

### Localization

- the default interface language is Russian
- English is supported from the first release
- language switching must exist in settings
- translation files must be kept synchronized
- Russian text is primary and is the source of truth

## 4. Delivery Model

The delivery model must follow this order:

1. clarify the business idea and MVP boundaries
2. establish architecture
3. define the master delivery plan
4. decompose the work into small tasks
5. execute in parallel where safe
6. continuously validate product intent, architecture, testing, and readiness

Implementation should stay web-first:
- web is the main functional client
- Android is a focused companion client for viewing and notifications

## 5. Required Roles and Leads

Required roles:
- Solution Architect
- Project Tech Lead / Delivery Planner
- Lead Business/System Analyst
- Lead Backend Engineer
- Lead Frontend Engineer
- Lead Mobile Engineer
- Lead QA / Test Lead
- Lead DevOps Engineer
- Lead Security Engineer

Not required as separate leads for MVP:
- dedicated Data Lead
- dedicated SRE Lead
- dedicated UX Research Lead

## 6. Architecture Direction

### Architectural Style

- modular monolith
- backend: `Java + Spring Boot`
- API: `REST`
- database: `PostgreSQL`
- notifications: background scheduler + `Firebase Cloud Messaging`
- web client: SPA
- Android client: native companion app

### Backend Modules

- `auth`
- `accounts`
- `folders`
- `goals`
- `tasks`
- `calendar`
- `recurrence`
- `reminders`
- `priority-policy`
- `sharing`
- `notifications`
- `settings`

### Core Entities

- `User`
- `UserCredential`
- `UserSettings`
- `Folder`
- `Goal`
- `Task`
- `TaskTag`
- `TaskLink`
- `GoalShare`
- `TaskShare`
- `ShareInvitation`
- `TaskRecurrenceRule`
- `TaskReminderRule`
- `TaskRescheduleEvent`
- `PriorityDecayPolicy`
- `DeviceRegistration`
- `NotificationDelivery`

### Important Relationships

- `User 1 -> N Folder`
- `Folder 1 -> N Goal`
- `Goal 1 -> N Task`
- `Task N -> N TaskTag`
- `Task N -> N Task` through links
- `Goal 1 -> N GoalShare`
- `Task 1 -> N TaskShare`
- `Task 1 -> 0..1 TaskRecurrenceRule`
- `Task 1 -> N TaskReminderRule`
- `Task 1 -> N TaskRescheduleEvent`
- `User 1 -> 1 UserSettings`

## 7. UX/UI Direction

The product should have a simple, deliberate retro visual identity:
- dense layouts
- gray and blue system-like colors
- hard borders and bevel-like controls
- low decoration
- functional, readable screens
- no glossy modern SaaS look

The interface must be:
- Russian-first
- English-supported
- simple to scan
- optimized for desktop web first

MVP3 simplification overlay:
- `docs/62-mvp3-design-simplification-contract.md` defines the current acceptance contract for simplifying web/iPhone and Android hierarchy, quick capture, details, sharing, links, dependencies, DnD, and RU-first copy without removing advanced features.
- `docs/64-mvp3-ba-simple-journeys.md` defines the simple BA journeys QA and implementers should use for the MVP3 user-facing planning flows.

## 8. Testing Strategy

The testing strategy must include:

- smoke testing
- API testing
- permission testing for sharing
- recurrence testing
- reminder scheduling testing
- quick reschedule testing
- priority decay testing
- web localization switching checks
- localization key synchronization validation
- Android notification flow testing
- deployment smoke checks

High-risk areas:
- recurrence logic
- reminder scheduling
- access control for shared goals and tasks
- priority decay transparency and predictability
- synchronization of localization files

## 9. Master MVP Plan

### Phase 1. Product and Domain Freeze

- finalize all domain rules
- confirm invariants for folders, goals, tasks, sharing, recurrence, reminders, and priority decay

### Phase 2. Architecture and Contracts

- finalize module boundaries
- finalize data model direction
- define REST contracts
- define notification flow
- define localization strategy

### Phase 3. Backend Foundation

- authentication
- settings
- folders, goals, tasks CRUD
- database migrations
- baseline security

### Phase 4. Scheduling and Sharing

- sharing
- recurrence
- reminders
- quick reschedule
- priority decay
- device registration
- push pipeline

### Phase 5. Web MVP

- retro UI shell
- localization infrastructure
- folders, goals, tasks flows
- simple calendar
- settings
- sharing UI

### Phase 6. Android Companion

- authentication
- list and detail screens
- push handling
- open-from-notification flow

### Phase 7. QA and Release

- regression checks
- deploy setup
- environment documentation
- release checklist

## 10. Immediate Next Step

The next practical step after this primary plan is a detailed execution backlog:
- execution waves
- concrete queue ordering
- subagent-sized tasks
- explicit dependencies
- definitions of done

This is documented in `docs/02-execution-backlog.md`.
