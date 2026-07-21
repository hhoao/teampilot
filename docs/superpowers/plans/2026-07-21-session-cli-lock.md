# Session-level CLI Lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pin each team session member’s CLI on `SessionMemberBinding.cli` at create time so later launch-profile edits cannot reopen the session under a different tool.

**Architecture:** Callers that have `TeamProfile` + presets resolve a per-instance `Map<String, CliTool>` via a small pure helper; `SessionRepository` only persists those values onto bindings. Read paths go through `SessionMemberCliResolver`, which prefers `binding.cli` over live `memberLaunchCli`. No backfill for legacy sessions.

**Tech Stack:** Flutter / Dart, existing `SessionRepository`, `memberLaunchCli`, `expandTeamRoster`.

**Spec:** `docs/superpowers/specs/2026-07-21-session-cli-lock-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/models/session_member_binding.dart` | Add optional `cli`; JSON / equality / `withNativeSessionId` preserve it |
| `client/lib/services/session/session_member_cli_locks.dart` | Pure `resolveSessionMemberCliLocks` (**keyed by member type id**) + clone copy helper |
| `client/lib/services/terminal/session_member_cli_resolver.dart` | Prefer `binding.cli` for team sessions |
| `client/lib/repositories/session_repository.dart` | `memberClis` on create; require `cli` on new `ensureMemberBinding`; clone copies source `cli` |
| `client/lib/cubits/chat/session_data_store.dart` | Thread `memberClis` / resolve at create helpers |
| `client/lib/cubits/chat/session_launch_service.dart` | Resolve locks before `createSession` persist |
| `client/lib/services/launch/session_default_materializer.dart` | Pass locks when materializing new team session |
| `client/lib/services/team/default_workspace_service.dart` | Pass locks for bootstrap team session |
| `client/lib/services/launch/session_shell_connector.dart` | Pass CLI into `ensureMemberBinding` / local binding create |
| Launch/history/tab consumers listed in Task 5 | Use resolver (or thin wrapper) instead of bare `memberLaunchCli` when session is persisted |
| Tests under `client/test/models/`, `client/test/services/`, `client/test/repositories/` | Spec minimum coverage |

---

### Task 1: `SessionMemberBinding.cli` (TDD)

**Files:**
- Modify: `client/lib/models/session_member_binding.dart`
- Modify: `client/test/models/session_member_binding_test.dart`

- [ ] **Step 1: Write failing tests**

Extend `session_member_binding_test.dart`:

```dart
test('cli round-trips; absent key is null', () {
  const withCli = SessionMemberBinding(
    rosterMemberId: 'team-lead',
    taskId: 't1',
    cli: CliTool.claude,
  );
  final back = SessionMemberBinding.fromJson(withCli.toJson());
  expect(back.cli, CliTool.claude);
  expect(withCli.toJson()['cli'], 'claude');

  final legacy = SessionMemberBinding.fromJson({
    'rosterMemberId': 'team-lead',
    'taskId': 't2',
  });
  expect(legacy.cli, isNull);

  final kept = withCli.withNativeSessionId('cursor', 'native-1');
  expect(kept.cli, CliTool.claude);
  expect(kept.nativeSessionIds['cursor'], 'native-1');
});
```

Import `team_config.dart` (or wherever `CliTool` lives) as existing tests do.

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd client && flutter test test/models/session_member_binding_test.dart
```

- [ ] **Step 3: Implement**

Add `final CliTool? cli` to constructor; parse with `CliTool.tryParse(json['cli'] as String?)`; emit `'cli': cli!.value` when non-null; include in `==` / `hashCode`; pass through `withNativeSessionId`.

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/session_member_binding.dart client/test/models/session_member_binding_test.dart
git commit -m "feat(session): persist optional CLI on SessionMemberBinding"
```

---

### Task 2: Resolve + clone helpers (TDD)

**Files:**
- Create: `client/lib/services/session/session_member_cli_locks.dart`
- Create: `client/test/services/session/session_member_cli_locks_test.dart`

**Keying rule (important):** `memberClis` / `resolveSessionMemberCliLocks` are keyed by **member type id** (`TeamMemberConfig.id` / `MemberInstance.type.id`), **not** pod `instanceId`.

Reason: `createSession` may run `healMemberReplicasFromTargets` before `expandTeamRoster`, which changes instance ids (`builder` → `builder-0` / `builder-1`). Type ids stay stable; replicas of one type share one locked CLI (matches spec).

- [ ] **Step 1: Write failing tests**

Cover:

1. `resolveSessionMemberCliLocks` returns one entry per **valid roster type** → `memberLaunchCli(team, type, globalPresets: …)` (not one entry per expanded instance).
2. Mixed member with explicit `cli: cursor` while team default is claude → type locks `cursor`.
3. Map does **not** contain `builder-0` keys when type id is `builder`.
4. `copyCliFromSourceBinding(sourceMembers, rosterMemberId:, typeId:)` prefers same `rosterMemberId`, else any same `typeId`, else `null`.

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd client && flutter test test/services/session/session_member_cli_locks_test.dart
```

- [ ] **Step 3: Implement**

```dart
Map<String, CliTool> resolveSessionMemberCliLocks({
  required TeamProfile team,
  required List<TeamMemberConfig> rosterMembers,
  List<CliPreset> globalPresets = const [],
}) {
  final out = <String, CliTool>{};
  for (final type in rosterMembers.where((m) => m.isValid)) {
    out[type.id] = memberLaunchCli(
      team: team,
      member: type,
      globalPresets: globalPresets,
    );
  }
  return out;
}

CliTool? copyCliFromSourceBinding({
  required List<SessionMemberBinding> sourceMembers,
  required String rosterMemberId,
  required String typeId,
}) { /* prefer id match, else typeId match */ }
```

Do **not** reimplement placement healing in this helper — type-id keys avoid the heal/instance-id mismatch.

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/session/session_member_cli_locks.dart \
  client/test/services/session/session_member_cli_locks_test.dart
git commit -m "feat(session): add CLI lock resolve and clone helpers"
```

---

### Task 3: Repository create / ensure / clone (TDD)

**Files:**
- Modify: `client/lib/repositories/session_repository.dart`
- Modify: `client/test/repositories/session_repository_test.dart` (and clone test file if separate)

- [ ] **Step 1: Write failing tests**

1. Team `createSession(..., memberClis: {'team-lead': CliTool.claude, 'builder': CliTool.opencode})` → each binding gets CLI via **`inst.type.id`** lookup (replica `builder-0` uses `memberClis['builder']`).
2. Team `createSession` with non-empty included roster but **missing** `memberClis[typeId]` for an included instance’s type → throws (`ArgumentError` — use consistently).
3. Simple `createSession` ignores `memberClis`.
4. `ensureMemberBinding(..., cli: CliTool.codex)` on missing member persists `cli`; second call with different cli returns existing unchanged.
5. Clone workspace sessions: source binding `cli: cursor` → cloned binding `cli: cursor`; source `cli: null` → clone `null`.

- [ ] **Step 2: Run focused tests — expect FAIL**

```bash
cd client && flutter test test/repositories/session_repository_test.dart
```

- [ ] **Step 3: Implement repository API**

- `createSession`: add `Map<String, CliTool> memberClis = const {}` (**type id → CLI**).
  - When building each included instance binding: `final locked = memberClis[inst.type.id]; if (locked == null) throw ArgumentError('missing memberClis for ${inst.type.id}');` then `SessionMemberBinding(..., cli: locked)`.
  - Simple path unchanged.
- `ensureMemberBinding`: add required named `CliTool cli` when creating. On insert: `SessionMemberBinding(..., cli: cli)`. On existing: return as-is.
- `_cloneSessionRecord`: when creating bindings from `expandTeamRoster(valid)`, set `cli: copyCliFromSourceBinding(sourceMembers: source.members, rosterMemberId: inst.instanceId, typeId: inst.type.id)`.

Also update **existing team `createSession` tests** under `client/test/` in this task (or immediately after) so they pass `memberClis` for every roster type — otherwise Task 3 will red-fail unrelated suites. Grep:

```bash
cd client && rg -n "sessionTeam:|createSession\(" test/ | head -80
```

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/repositories/session_repository.dart client/test/repositories/
git commit -m "feat(session): persist caller-supplied member CLI locks"
```

---

### Task 4: Wire create / append callers

**Files:**
- Modify: `client/lib/cubits/chat/session_data_store.dart`
- Modify: `client/lib/cubits/chat/session_launch_service.dart` (`_persistSessionIfNeeded`)
- Modify: `client/lib/services/launch/session_default_materializer.dart`
- Modify: `client/lib/services/team/default_workspace_service.dart`
- Modify: `client/lib/services/launch/session_shell_connector.dart` (`_resolveMemberBinding`)
- Grep and fix any other `createSession(` / `ensureMemberBinding(` call sites under `client/lib/`

- [ ] **Step 1: Audit callers**

```bash
cd client && rg -n "createSession\(|ensureMemberBinding\(" lib/
```

For every **team** create path that has access to `TeamProfile`, compute:

```dart
final memberClis = resolveSessionMemberCliLocks(
  team: team,
  rosterMembers: rosterMembers,
  globalPresets: lifecycle.globalPresets, // or [] if unavailable
);
await repo.createSession(..., memberClis: memberClis);
```

`session_launch_service._persistSessionIfNeeded`: team from `request.team` / persist params; presets from host lifecycle.

`session_default_materializer.materializeTeamSession`: has `team`; pass locks + presets from `_host` if available.

`default_workspace_service.ensureDefault`: has `defaultTeam`; pass `resolveSessionMemberCliLocks(team: defaultTeam, rosterMembers: rosterMembers)` (empty presets OK if members/team carry `cli`).

`session_data_store.createWorkspaceWithFirstSession`: if `sessionTeamId` non-empty, require caller to pass `memberClis` or `team`+presets — extend signature accordingly; update `ChatCubit.createWorkspaceWithFirstSession` / dialog callers (often Simple-only — verify).

`session_shell_connector._resolveMemberBinding`: must receive (or look up) `TeamProfile` + presets / a pre-resolved `CliTool` so it can call `ensureMemberBinding(..., cli: locked)` and set `cli` on local tab bindings. If `team` is not already in scope on that method, thread it from `connectShell` (which already has `team`).

- [ ] **Step 2: Implement wiring**

- [ ] **Step 3: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Fix compile breaks from `ensureMemberBinding` signature.

- [ ] **Step 4: Commit**

```bash
git add client/lib/
git commit -m "feat(session): resolve CLI locks at team session create/append"
```

---

### Task 5: Resolver prefers binding lock (TDD) + call-site migration

**Files:**
- Modify: `client/lib/services/terminal/session_member_cli_resolver.dart`
- Modify: `client/test/services/terminal/session_member_cli_resolver_test.dart`
- Modify consumers that currently call `memberLaunchCli` **with a persisted session** (non-exhaustive audit — migrate all that affect launch/history/tab/preflight):

  - `session_shell_connector.dart`
  - `session_connect_orchestrator.dart`
  - `session_lifecycle_service.dart` (or pass locked cli into prepare paths)
  - `session_launch_service.dart`
  - `session_member_connect_scheduler.dart`
  - `ai_history_loader.dart`
  - `session_history_review.dart` (`_lockedCli`)
  - `session_tab_cli.dart`
  - `chat_session_shell_factory.dart`
  - `member_lifecycle_connect_gate.dart`
  - `remote_cli_requirements.dart`
  - `tab_team_bus_coordinator.dart`
  - `member_coordination.dart`

  Leave **preview** paths (team config UI, landing compose without session) on live `memberLaunchCli`.

- [ ] **Step 1: Extend resolver tests**

```dart
test('team session prefers binding.cli over live profile', () {
  final team = TeamProfile(
    id: 't1',
    name: 'Team',
    cli: CliTool.cursor, // live profile changed
    members: [
      TeamMemberConfig(id: 'team-lead', name: 'Lead', cli: CliTool.cursor),
    ],
  );
  final session = AppSession(
    sessionId: 's1',
    workspaceId: 'w1',
    sessionTeam: 't1',
    members: [
      SessionMemberBinding(
        rosterMemberId: 'team-lead',
        taskId: 'task',
        cli: CliTool.claude, // locked
      ),
    ],
    createdAt: 1,
  );
  final cli = SessionMemberCliResolver.resolve(
    persistedSession: session,
    team: team,
    memberId: 'team-lead',
    cliForMember: cliForMember,
  );
  expect(cli, CliTool.claude);
});

test('team session without binding.cli uses cliForMember', () { /* existing behavior */ });
```

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/services/terminal/session_member_cli_resolver_test.dart
```

- [ ] **Step 3: Implement resolver**

In `SessionMemberCliResolver.resolve`, after personal branch:

```dart
if (team == null) return CliTool.claude;
final locked = persistedSession?.bindingFor(memberId)?.cli;
if (locked != null) return locked;
return cliForMember(team, memberId, globalPresets: globalPresets);
```

- [ ] **Step 4: Migrate call sites**

Prefer one pattern: when `AppSession` + `memberId` + `team` are available, call `SessionMemberCliResolver.resolve` (passing `memberLaunchCli` as `cliForMember`, or a thin wrapper that looks up the member config then calls `memberLaunchCli`).

For `session_tab_cli.dart`: after optional session-level `AppSession.cli` for Simple, for team use binding lock via resolver (today it incorrectly prefers session.cli then live member — align with spec).

For `session_history_review._lockedCli`: use resolver so continue chrome filters presets by locked CLI.

- [ ] **Step 5: Run resolver + continue / history tests**

```bash
cd client && flutter test \
  test/services/terminal/session_member_cli_resolver_test.dart \
  test/cubits/chat_cubit_continue_overrides_test.dart \
  test/pages/chat/session_history_continue_chrome_test.dart
```

Add (if missing) one continue/history assertion where `binding.cli` is Claude but live team profile is Cursor → `lockedCli` / preset filter still Claude.

- [ ] **Step 6: Commit**

```bash
git add client/lib client/test
git commit -m "feat(session): prefer SessionMemberBinding.cli over live profile"
```

---

### Task 6: Verification

- [x] **Step 1: Full unit analyze + test**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  && flutter test --exclude-tags integration
```

Expected: clean analyze (infos/warnings OK per flag); all non-integration tests pass.

- [x] **Step 2: Manual smoke (optional but recommended)**

1. Create team session with Claude lead → confirm `session.json` `members[].cli` is `claude`.
2. Change team profile default CLI to Cursor → reopen session → still launches Claude / history visible.
3. Open a **legacy** session without `cli` → still follows live profile (no migration).

Skipped GUI; create-locks fixture coverage already in `session_repository_test` / `session_member_cli_locks_test`.

- [x] **Step 3: Final commit only if verification fixed stragglers**; otherwise done.

---

## Out of scope (do not implement)

- Backfill / transcript inference
- UI unlock / switch CLI
- Changing Simple `AppSession.cli` behavior
