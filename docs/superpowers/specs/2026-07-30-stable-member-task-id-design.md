# Stable member `taskId` (provisional == persisted)

## Problem

Team session open stages an in-memory **provisional** `AppSession` so the workbench (and History) can mount before disk persistence finishes. Today that provisional fills every roster seat with:

```text
SessionMemberBinding.taskId = sessionId   // placeholder
```

`SessionRepository.createSession` then allocates **new** UUIDs per included member and replaces the snapshot. Launch / Claude `--session-id` / on-disk JSONL use the persisted `taskId`. History often cold-loads (or softReloads from `_lastSession`) against the provisional placeholder, so locate looks for `{sessionId}.jsonl` while the real file is `{realTaskId}.jsonl`.

Symptoms (mixed team, leader Chat empty, members OK, Terminal OK):

- Leader connects and History mounts first → stuck on wrong locate key.
- Members connect later → History loads with the already-persisted bindings → works.
- Terminal reads PTY scrollback, not CLI transcript locate → works.

This is an **identity mutation** bug, not a missing History refresh.

## Goal

`SessionMemberBinding.taskId` is the CLI session identity for that seat. Allocate it **once** when the member enters the session member graph; provisional, persist, launch, History locate, and resume all read the same value. No mid-flight rewrite.

## Non-goals

- History softReload / “taskId changed → cold load” guards (defensive; identity must not change)
- Mailbox / TeamBus continue routing changes
- Migrating or rewriting existing sessions on disk
- Changing Simple / personal session identity (`taskId` remains session-scoped there)
- Changing `cloneWorkspace` (new session → new identities)
- Changing `ensureMemberBinding` for **new** seats added after create (those may allocate a fresh UUID once at append time)

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Fix locus | **Source identity** (allocate once), not History consumption |
| Provisional `taskId` | Real `Uuid.v4()` per included seat — **never** `sessionId` |
| Persist | Write staged `session.members` / `memberTargets`; **do not** re-allocate `taskId` |
| Workspace targets side effect | `createSession` still honors `persistTargets` → `updateWorkspaceMemberTargets` |
| Builder | Single shared plan builder for expand + placement + allocate |
| Placement mismatch | `StateError` if staged roster ids ≠ plan included set at persist (bug, not self-heal) |
| History | Unchanged APIs / softReload semantics |
| `SessionPersistParams` | Unchanged shape; bindings live on staged `AppSession` |

## Contract

```text
SessionMemberBinding.taskId
  = CLI session id for this seat
  = --session-id / resume pin / History locate key (Claude/flashskyai client-pinned)
```

Lifecycle:

1. Heal roster replicas from remembered targets (same as today).
2. Expand → placement → **included** instances (same inclusion rules as today’s `createSession`).
3. For each included instance: allocate `taskId`, lock `cli` → `SessionMemberBinding`.
4. Stage provisional `AppSession.members` + `memberTargets`.
5. Persist with those bindings + `fixedSessionId: session.sessionId`.
6. Launch / History read `requireBinding(memberId).taskId` only.

Members omitted by placement never receive a binding. Members appended later via `ensureMemberBinding` allocate once at append — that is a **new** seat, not a rewrite.

## Design

### Shared builder

Add a plan builder, e.g. `client/lib/services/session/team_session_member_plan.dart`:

**Input:** workspace, team id, roster members, `memberClis` (type id → `CliTool`; caller runs `resolveSessionMemberCliLocks` first), remembered targets / placement inputs as today.

**Output:**

```text
{
  members: List<SessionMemberBinding>,  // included seats only; real taskIds
  memberTargets: Map<String, String>,     // session-scoped pins for included
  persistTargets: bool,                   // same meaning as today's
                                          // _resolveSessionMemberTargets.persistTargets
}
```

Fail the same way `createSession` fails today for lead placement / uninitialized mixed placement.

Lift / reuse placement resolution currently private on `SessionRepository` (`_resolveSessionMemberTargets` and related) so provisional and persist cannot diverge.

### Call sites

| Caller | Behavior |
|--------|----------|
| `session_launch_pipeline` (team create) | `resolveSessionMemberCliLocks` → plan → provisional `AppSession.members` / `memberTargets`. Staged session is the source of truth for bindings. |
| `_persistSessionIfNeeded` / `createSession` | UI staged path: read **`session.members` + `session.memberTargets`** (do not re-expand roster to invent taskIds). Still assign `cliTeamName`, write `session.json`. If plan/`persistTargets` is true, **`createSession` still runs `updateWorkspaceMemberTargets`** (same workspace-manifest side effect as today) — do not drop this when skipping re-allocation. |
| Non-UI `createSession` (automation / default materializer) | Call the **same** plan builder inside the repository, then write — one allocation path. |
| `SessionPersistParams` | **No new binding fields required.** After staging, persist uses the in-memory `AppSession` members/targets already on the tab/snapshot. |

Prefer **one** allocation path (builder always), not “repo allocates unless optional override”.

**`persistTargets` ownership:** Plan computes the flag; **`SessionRepository.createSession` executes** `updateWorkspaceMemberTargets` when the flag is true (whether members came from staged session or an in-repo plan call). Pipeline does not pre-write workspace member targets.

### Explicitly out of History

Do **not** add:

- Compare old/new `taskId` in `softReloadOrLoad`
- Invalidate seat when `AppSession.members` changes
- Special-case `team-lead`

Once identity is stable, existing seat load / live refresh locate correctly.

## Testing

1. **Plan unit:** Single plan → unique non-empty `taskId`s, none equal to a caller-supplied `sessionId`; placement-excluded instances absent from `members`.
2. **Pipeline → persist:** Provisional `members[i].taskId` **equals** persisted session binding for the same `rosterMemberId`.
3. **History locate narrow regression:** Fixture transcript under `{taskId}.jsonl`; load with session whose binding uses that `taskId` → messages non-empty. Same fixture with `taskId == sessionId` → miss (documents the old failure mode; not a softReload test).
4. **Placement / lead:** Illegal lead placement still fails; included set matches today’s repository rules.

## Acceptance

- New mixed team → leader Chat immediately → first send → History shows the turn without switching members.
- On-disk `session.json` leader `taskId` matches provisional and the Claude JSONL basename.
- No new History branches that react to `taskId` mutation.

## Alternatives rejected

| Approach | Why rejected |
|----------|----------------|
| History cold-load when `taskId` changes | Treats identity churn as normal; other consumers (resume, live refresh) still wrong |
| Keep placeholder + “align after persist” | Still two identities in flight; race-prone |
| Defense-in-depth (source fix + History guard) | Guard is dead weight if source is correct; user explicitly rejected defensive programming |
