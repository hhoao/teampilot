# Session-level CLI lock (team members)

Team sessions currently resolve each member’s launch CLI from the **live** launch profile (`memberLaunchCli`). Changing a team’s default CLI or preset after a session was created can reopen that session under a different CLI, so resume/history look “gone” even though transcripts remain under the original tool’s runtime dir.

## Goal

Pin each team member’s CLI onto the session at **create** time. Later profile edits must not change which CLI that session member launches, resumes, or loads history with.

## Non-goals

- Backfill / migrate existing sessions that lack a locked CLI
- Infer CLI from on-disk transcripts or `nativeSessionIds`
- UI to unlock or switch CLI on an existing session
- Locking provider / model / effort on the binding (continue overrides already cover those)
- Changing Simple-session semantics (`AppSession.cli` already pins CLI)

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Lock strength | Hard lock: continue chrome may only pick same-CLI presets |
| Capture time | Session **create** (and when appending a new member binding) |
| Storage | `SessionMemberBinding.cli` |
| Old sessions without `cli` | No compat work: keep today’s live-profile resolution |
| Simple sessions | Unchanged (`AppSession.cli`) |

## Data model

Extend `SessionMemberBinding`:

```dart
final CliTool? cli; // set at create / member append; never rewritten
```

Persisted in `session.json` `members[]` as `"cli": "claude"`. Missing key → `null`.

### Write boundary

`memberLaunchCli` needs `TeamProfile` + `globalPresets`. The repository today only receives `rosterMembers` / ids — it must **not** gain a hidden dependency on the full team profile.

**Rule:** resolve CLI in the create/append/clone **caller** (session launch / data store / automation dispatcher — wherever `TeamProfile` and presets already exist). The repository only **persists** caller-supplied `cli` on each binding.

Practical shape (plan may refine API names):

- `createSession`: accept a per-instance map (e.g. `Map<String, CliTool> memberClis` keyed by `instanceId`) **or** pre-built bindings that already carry `cli`. Missing entry for a team instance → fail create (new team sessions must lock every included member). Simple sessions ignore the map.
- `ensureMemberBinding`: require `CliTool cli` when inserting a **new** binding; if the binding already exists, return it unchanged (do not rewrite `cli`).
- Caller resolves with `memberLaunchCli` against the member **type** (`TeamMemberConfig` for `typeId` / base roster slot), not a synthetic instance-only id — same input `expandTeamRoster` already uses when building instances.

### Write rules

- **Create** (UI launch, automation, etc.): caller resolves each included instance’s CLI at create time → repository persists it on `SessionMemberBinding.cli`.
- **Append member** (`ensureMemberBinding` / placement adding a pod): caller supplies CLI from the profile **at append time**; never rewrite an existing member’s `cli`.
- **Workspace session clone** (`_cloneSessionRecord`): for each new binding, **copy** `cli` from the source session’s matching binding: prefer same `rosterMemberId`; else any source binding with the same `typeId` (replicas of one type share one locked CLI at create, so uniqueness is not required). Do **not** re-resolve from the live profile. Source with no usable match or `cli == null` (legacy) → new binding stays `null` (no backfill).
- **Model hygiene:** `withNativeSessionId`, `copyWith` / `==` / `hashCode`, and JSON round-trip must preserve `cli` so resume-id updates never drop the lock.
- **Never** overwrite `SessionMemberBinding.cli` after it is set (connect failure, continue overrides, profile edits, resume).

## Resolution

Single entry for “which CLI does this session member use?” — extend `SessionMemberCliResolver` (or a focused helper used by it):

1. If personal / Simple → `AppSession.cli` (existing).
2. Else if `session.bindingFor(memberId)?.cli != null` → that value (hard lock).
3. Else → `memberLaunchCli(team, member, …)` (legacy sessions only).

### Call sites that must use the resolver when a persisted session exists

| Area | Notes |
|------|--------|
| Connect / `prepareLaunch` / shell | Transport, runtime dirs, resume native id |
| AI history / history review | Transcript locate + continue `lockedCli` |
| Tab badge (`session_tab_cli`) | Show locked CLI |
| Continue preset filtering | `presetsForCli(…, lockedCli)`; cross-CLI patch still rejected |
| TeamBus / remote CLI preflight | Probe the locked CLI |
| `applySessionContinueOverrides` | Keep “never change cli”; lock lives on binding, not overrides |

Landing compose / team config previews (no session yet) keep using live `memberLaunchCli`.

## Error handling

- Create-time CLI resolution failure → fail create; do not persist a partial session (same as today).
- Locked CLI binary missing / connect exit ≠ 0 → existing fail paths; **do not** clear or rewrite the lock.

## Testing (minimum)

1. `SessionMemberBinding` JSON round-trip: `cli` present / absent (`null`).
2. Create path: caller-supplied `memberClis` land on bindings; team create without a CLI for an included instance fails.
3. Resolver: non-null binding `cli` wins over a changed team profile; null falls back to profile.
4. Continue `patchPreset`: cross-CLI rejected; same-CLI allowed.
5. Clone: copies source binding `cli` (including preserving `null`); does not adopt current profile CLI.

## Out of scope follow-ups

- Optional UI to intentionally re-lock or migrate a legacy session
- Persisting locked CLI on native-team sessions beyond “store resolved `team.cli` at create” (already in scope as write-through; no extra UI)
