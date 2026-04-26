# Wave A Backend Sharing

## Implemented

- Added Flyway migration `V4__sharing_foundation.sql` for:
  - `share_invitations`
  - `goal_shares`
  - `task_shares`
- Implemented sharing persistence under `backend/src/main/java/com/rocketflow/sharing/`:
  - invitation entity and repositories
  - goal/task share entities and repositories
  - centralized access resolution service
  - sharing API DTOs, controller, and service flows
- Added invitation lifecycle endpoints:
  - `POST /api/goals/{goalId}/share`
  - `POST /api/tasks/{taskId}/share`
  - `GET /api/shares/invitations`
  - `POST /api/shares/invitations/{invitationId}/accept`
  - `POST /api/shares/invitations/{invitationId}/decline`
  - `POST /api/shares/invitations/{invitationId}/revoke`
  - `GET /api/shares/resources`

## Access Model

- Goal access is granted to:
  - the owner
  - an active accepted goal collaborator
- Task access is granted to:
  - the owner
  - an active accepted collaborator on the parent goal
  - an active accepted direct task collaborator
- Existing goal/task read and write flows now resolve access through `SharingAccessService` instead of owner-only assumptions where sharing applies.
- Folder access remains owner-only.
- Reminder ownership semantics were left untouched.

## Invitation And Share Behavior

- Invitations are normalized by email and expire after 7 days.
- Self-invites are rejected.
- Duplicate pending invitations and duplicate effective access are rejected.
- Accepting an invitation creates an active `goal_shares` or `task_shares` row.
- Declining does not create access.
- Revoking an accepted invitation also revokes the share so access is removed on the next request.
- Direct task shares remain independent from goal sharing.

## Shared Resource Discovery

- `GET /api/shares/resources` returns:
  - goals granted through active goal shares
  - tasks granted through active goal shares and direct task shares
- Goal/task DTOs reuse the existing planning DTO shapes and mark shared resources with `shared = true`.
- The existing `GoalDto.folderId` UUID shape was preserved, so shared goals currently return their persisted folder id rather than introducing a new virtual folder identifier.

## Tests

- Added `backend/src/test/java/com/rocketflow/SharingIntegrationTest.java`.
- Coverage includes:
  - goal invitation accept flow
  - collaborator reads and writes on shared goals/tasks
  - shared-resource discovery
  - direct task invitation decline
  - direct task revoke with immediate stale-access loss
  - duplicate and self-invite rejection
- Updated `RocketFlowApplicationTests` mocks for the new sharing repositories so the repo-free application-context smoke test continues to boot.
