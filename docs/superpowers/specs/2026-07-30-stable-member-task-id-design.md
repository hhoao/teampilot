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
| Persist | Write the staged bindings; **do not** re-allocate `taskId` |
| Builder | Single shared plan builder for expand + placement + allocate |
| Placement mismatch | `StateError` if staged roster ids ≠ persist included set (bug, not self-heal) |
| History | Unchanged APIs / softReload semantics |

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

Add a pure(ish) plan builder, e.g. `client/lib/services/session/team_session_member_plan.dart`:

**Input:** workspace, team id, roster members, `memberClis` (type id → `CliTool`), remembered targets / placement inputs as today.

**Output:** `{ members: List<SessionMemberBinding>, memberTargets: Map<String,String> }` (and fail the same way `createSession` fails today for lead placement / uninitialized mixed placement).

Lift / reuse placement resolution currently private on `SessionRepository` (`_resolveSessionMemberTargets` and related) so provisional and persist cannot diverge.

### Call sites

| Caller | Behavior |
|--------|----------|
| `session_launch_pipeline` (team create) | Call plan → provisional `members` / `memberTargets`; pass bindings into persist params (or persist reads `session.members`) |
| `SessionRepository.createSession` | When bindings are supplied (UI staged path): validate included set, assign `cliTeamName`, write disk — **no new taskIds**. When bindings are absent (automation / default materializer): call the **same** plan builder internally, then write — still one allocation path |
| `SessionPersistParams` | Carry staged `List<SessionMemberBinding>` (and targets if not already on `AppSession`), or document that persist uses `session.members` as source of truth after staging |

Prefer **one** allocation path (builder always), not “repo allocates unless optional override”.

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
