# Session History Continue Chrome

**Date:** 2026-07-11  
**Status:** Draft  
**Related:** [Session History Review](2026-07-10-session-history-review-design.md), `WorkspaceChatLanding`, `ExistingSessionConnect`, `AppSession`, `SessionMemberBinding`

## Summary

History review’s slim compose gains a **continue chrome**: session-scoped controls for permission and same-CLI model/preset switching, plus a team-settings shortcut in team mode. Overrides persist on `AppSession` and apply on every connect via one merge entry point. Session-fixed identity (workspace, worktree, team↔simple, expert, CLI) stays read-only.

This supersedes the History Review non-goal that deferred permission / preset chips on review compose.

## Problem

Users open an existing session in review to continue later. Today the compose only offers text + attach/enhance/voice. When a provider quota is exhausted, or they need full-access permissions for the next turn, they cannot adjust launch knobs without leaving the session or mutating the team template. Landing’s permission chip is also UI-only today (not written into create/launch), so permission semantics are inconsistent.

## Goals

| Goal | Description |
|------|-------------|
| Continue without new session | Change permission / model for **this** session and resume |
| Quota escape hatch | Switch provider/model via same-CLI preset (Simple) or per-member override (Team) |
| Session is source of truth | Overrides persist on `AppSession`; team template / workspace agent defaults are not mutated |
| One merge path | All connects apply overrides through a single pure function |
| Shared chrome primitives | Landing and History share permission / model chips; Landing permission becomes real |
| No CLI switch on continue | Preset/model pickers lock to the session member’s CLI |

## Non-goals

- Changing expert, project, worktree, Team↔Simple, or team id from History
- Changing CLI via preset on continue
- Writing session overrides back into `TeamProfile` or workspace agent config
- Hot-swapping model/permission on an already-running PTY (edit in review, then connect)
- Bulk “apply model to all members” in one action
- Backward-compatible dual-read of the old Landing-only permission UI state

## Decision

**Session continue overrides + dedicated continue chrome on History**, with Landing create writing the same fields.

```text
Landing create / History chip edit
  → persist SessionContinueOverrides on AppSession
  → ExistingSessionConnect / prepareLaunch
  → applySessionContinueOverrides(base, session, memberId)
  → launch member (CLI unchanged)
```

## Data model

### `SessionContinueOverrides` on `AppSession`

```text
SessionContinueOverrides
  dangerouslySkipPermissions: bool?   // session default; null = unset
  memberOverrides: Map<rosterMemberId, SessionMemberContinueOverride>

SessionMemberContinueOverride
  presetId?: string
  provider?: string
  model?: string
  effort?: string
  dangerouslySkipPermissions?: bool   // optional per-member override
```

**Permission resolution (both modes):**

```text
memberOverrides[id].dangerouslySkipPermissions
  ?? session.continueOverrides.dangerouslySkipPermissions
  ?? launchDefault
```

- `launchDefault`: Simple → `false`; Team → that member’s template `dangerouslySkipPermissions`
- **Landing** (one permission chip, Simple or Team): writes **only** session-level `SessionContinueOverrides.dangerouslySkipPermissions` at create. Does not fan out into every `memberOverrides` entry.
- **History Team** permission chip: writes **per selected member** `memberOverrides[id].dangerouslySkipPermissions` (specializes that seat; other members keep session default / template).
- **History Simple** permission chip: writes session-level field (same field Landing uses).

**Simple model:** via existing `AppSession.presetId` / `provider` / `model` / `effort` only (selecting a same-CLI preset updates those fields). No second Simple model store. Permission is **only** on `SessionContinueOverrides.dangerouslySkipPermissions` — not duplicated onto Simple identity.

**Team model:** provider/model/effort/presetId live under `memberOverrides[rosterMemberId]` for the workbench-selected member. Team template (`TeamMemberConfig`) is unchanged.

**Unset semantics:** `null` / missing → fall through the resolution chain above. Pre-override sessions have no fields → behave as unset (Simple reconnect default `false`; Team uses template). Intentional: do not preserve any prior “UI-only Landing permission” or pack default skip=`true` for Simple unless the template/member path supplies it for Team.

No dual-read compatibility shims for pre-override sessions: missing fields simply mean “unset.”

### Merge entry point

`applySessionContinueOverrides(baseMember, session, memberId) → TeamMemberConfig` (or equivalent launch member view for Simple).

Rules:

1. Start from team member or Simple-derived launch member.
2. Apply session continue overrides for that member / Simple session.
3. **CLI is always `base.cli`** — overrides must not change CLI. Persisting a cross-CLI preset is a hard error (UI must not offer it; code path rejects without write).
4. Used by History submit, reconnect, and any other connect of this session — never apply overrides only in the History UI layer.

### Persist API

`SessionRepository` patch (e.g. `updateContinueOverrides` / update session identity fields). UI goes through `ChatCubit` (or a thin session-update helper): update in-memory snapshot + disk. On failure: toast and revert chip to last successful value.

## UI — Continue chrome

History bottom card is **not** full Landing. Toolbar (left → right):

| Control | Simple | Team | Behavior |
|---------|--------|------|----------|
| Identity (read-only) | Expert label (or none) | Team name | Not tappable |
| Model / preset chip | Same-CLI presets | Same-CLI presets / model for **selected member** | Persist immediately on select |
| Permission chip | default / full access (session-level) | default / full access (**selected member** override) | Persist immediately |
| Team settings | — | Gear | Opens existing team settings (edits **template**; copy may clarify vs session override) |
| attach / enhance / voice / send | ✓ | ✓ | Unchanged slim compose |

**Absent:** project, worktree, Team↔Simple, switch team, switch expert, switch CLI.

### Interaction

- Changing workbench `selectedMemberId` reloads that member’s override into the chips.
- Preset menus use `presetsForCli(sessionMemberCli)` only.
- Permission display: override if set; else launch default. After first explicit choice, session value wins.
- Chip edits do **not** wait for send.
- Send uses already-persisted overrides via `ExistingSessionConnect` → merge → launch → inject.

### Components

- Extract shared `ComposePermissionChip` and `ComposeModelPresetChip` (Landing + History).
- `SessionReviewComposeCard` gains a continue-toolbar slot; do not mount `WorkspaceChatLanding`.
- `SessionHistoryReview` owns read/write of session overrides and passes effective labels/specs to the card.

## Connect / launch flow

```text
1. Chips already persisted overrides on AppSession
2. submitSessionHistoryReviewMessage
3. connectWorkspaceSession(ExistingSessionConnect)
4. prepareLaunch / resolveMemberForLaunch
     → base from team | simple
     → applySessionContinueOverrides
5. ensureMemberInputReady → inject → switch to terminal
```

### Landing alignment

- Permission chip writes **session-level** `SessionContinueOverrides.dangerouslySkipPermissions` at create (Simple and Team). No UI-only state; no fan-out into `memberOverrides` at create.
- Simple preset selection sets `presetId` + provider/model/effort on the new session (identity fields only).
- After create, first History open: permission chip reads the resolution chain (session-level from Landing); Simple model chip matches create preset; Team model chip shows template / unset member override until the user specializes a member.

### Errors and edge cases

| Case | Behavior |
|------|----------|
| Cross-CLI preset | Not listed; if reached in code → no persist + toast |
| Missing provider credentials | Existing launch validation / incomplete dialog; block connect |
| Member removed from roster | Drop that member’s override; chips fall back to template defaults |
| Team settings changes template | Session override still wins for model/permission chips and launch |
| Connect/inject failure | Keep compose text (existing); keep persisted overrides |
| SSH root + full access | Existing `remote_ssh_launch_constraints` |

### Runtime boundary

Overrides apply at **connect** time only. To change model/permission after the PTY is running, disconnect back to review, edit chips, submit again.

## Relationship to History Review spec

Update [2026-07-10-session-history-review-design.md](2026-07-10-session-history-review-design.md):

- Remove non-goal “Permission / project / worktree / expert / preset chips on review compose (permission deferred)”.
- Keep project / worktree / expert / mode as out of scope on review compose.
- Point permission + same-CLI preset/model chips at this document.
- Review layout diagram: replace “Removed: … expert, preset, permission” with continue chrome (identity read-only + model + permission [+ team settings]).

## Testing

- Pure unit tests for `applySessionContinueOverrides` (override wins, CLI locked, null = default, per-member isolation).
- Persist round-trip for `SessionContinueOverrides` / Simple identity fields.
- History submit path (mocked lifecycle) asserts launch member received merged overrides.
- UI/widget or cubit tests: chip select persists; member switch reloads overrides; cross-CLI presets excluded.

## Acceptance

1. History Simple: same-CLI preset change → disk → reopen → connect uses new provider/model.
2. History Team: selected-member model change → only that session’s member override → team template unchanged → connect uses override.
3. Permission full access → disk → next History shows full access → launch requests skip-permissions (subject to SSH root rules).
4. Cross-CLI presets not selectable; mistaken path does not write.
5. Team settings still edits template; when a session override exists, model chip shows override (not silently replaced by template).
6. Expert / project / worktree / mode switch absent from History compose.
7. Landing create with permission → first History open matches session-level permission (Team: all members resolve to that session default until a per-member override is set).
8. Merge + persist covered by unit tests; submit path covered with mocks.

## Out of scope follow-ups (explicit)

- Hot-reload model into a live PTY without reconnect
- Syncing session overrides upward into team templates
- Expert switch on continue
