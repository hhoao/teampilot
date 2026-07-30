# Stable Member `taskId` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allocate each team seat’s `SessionMemberBinding.taskId` once at provisional staging and persist/launch/History all use that same id — no placeholder `sessionId`, no re-UUID on `createSession`.

**Architecture:** Extract a shared `buildTeamSessionMemberPlan` (heal → expand → placement → allocate bindings). `session_launch_pipeline` stages those bindings on the provisional `AppSession`. `createSession` accepts staged `members`/`memberTargets`, re-runs placement only to validate inclusion + compute `persistTargets`, and never re-allocates `taskId`. History is unchanged.

**Tech Stack:** Flutter / Dart, `SessionRepository`, `expandTeamRoster` / workspace topology helpers, existing session launch pipeline.

**Spec:** `docs/superpowers/specs/2026-07-30-stable-member-task-id-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/session/team_session_member_plan.dart` | **New.** Pure plan: placement resolve + allocate `SessionMemberBinding`s; returns `members`, `memberTargets`, `persistTargets` |
| `client/lib/repositories/session_repository.dart` | Delegate team-member construction to plan; accept optional staged `members`/`memberTargets`; keep `updateWorkspaceMemberTargets` when `persistTargets` |
| `client/lib/services/launch/session_launch_pipeline.dart` | Stage real taskIds via plan (placement-included only); drop `taskId = sessionId` placeholder |
| `client/lib/cubits/chat/session_launch_service.dart` | `_persistSessionIfNeeded` passes staged `session.members` / `memberTargets` into `createSession` |
| `client/lib/cubits/chat/session_data_store.dart` | Thread staged members through any `createSession` wrappers if present |
| `client/test/services/session/team_session_member_plan_test.dart` | **New.** Plan unit tests |
| `client/test/repositories/session_repository_stable_task_id_test.dart` | **New.** Staged bindings survive persist; wrong set → `StateError` |
| `client/test/services/session/stable_task_id_history_locate_test.dart` | **New.** Narrow History locate: real taskId hits; `taskId == sessionId` misses |

---

### Task 1: `buildTeamSessionMemberPlan` (TDD)

**Files:**
- Create: `client/lib/services/session/team_session_member_plan.dart`
- Create: `client/test/services/session/team_session_member_plan_test.dart`
- Modify: `client/lib/repositories/session_repository.dart` (move `_resolveSessionMemberTargets` / `_includedLeadWhenRequired` into the plan module as public/library functions; repository calls them via the plan)

- [ ] **Step 1: Write failing plan unit tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/session/team_session_member_plan.dart';

void main() {
  test('allocates unique taskIds not equal to sessionId; includes lead', () {
    final workspace = Workspace(
      workspaceId: 'ws',
      folders: [WorkspaceFolder(path: '/proj')],
      createdAt: 1,
      updatedAt: 1,
    );
    const sessionId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    final plan = buildTeamSessionMemberPlan(
      workspace: workspace,
      teamId: 'team-1',
      rosterMembers: [
        TeamMemberConfig(id: 'team-lead', name: 'Lead'),
        TeamMemberConfig(id: 'builder', name: 'Builder'),
      ],
      memberClis: {
        'team-lead': CliTool.claude,
        'builder': CliTool.claude,
      },
      // fixed ids for determinism in tests — inject via optional UuidFn
      allocateTaskId: () => 'task-${_seq++}',
    );
    expect(plan.members, isNotEmpty);
    final ids = plan.members.map((m) => m.taskId).toSet();
    expect(ids.length, plan.members.length);
    expect(ids.contains(sessionId), isFalse);
    expect(
      plan.members.any((m) => m.rosterMemberId == 'team-lead'),
      isTrue,
    );
  });

  test('mixed workspace omits unpinned instances from members', () {
    // folders: local + ssh; remembered targets only pin team-lead → local
    // expect builder-* absent from plan.members
  });
}
```

(Use a `String Function()? allocateTaskId` / `Uuid` injector on the plan so tests are deterministic; production default `const Uuid().v4`.)

- [ ] **Step 2: Run tests — expect FAIL (library missing)**

```bash
cd client && flutter test test/services/session/team_session_member_plan_test.dart
```

Expected: compilation / import failure for `team_session_member_plan.dart`.

- [ ] **Step 3: Implement plan module**

Move logic from `SessionRepository.createSession` team branch + `_resolveSessionMemberTargets` + `_includedLeadWhenRequired` into:

```dart
class TeamSessionMemberPlan {
  const TeamSessionMemberPlan({
    required this.members,
    required this.memberTargets,
    required this.persistTargets,
  });
  final List<SessionMemberBinding> members;
  final Map<String, String> memberTargets;
  final bool persistTargets;
}

TeamSessionMemberPlan buildTeamSessionMemberPlan({
  required Workspace workspace,
  required String teamId,
  required List<TeamMemberConfig> rosterMembers,
  required Map<String, CliTool> memberClis,
  String Function()? allocateTaskId,
}) {
  // heal → expand → resolveSessionMemberTargets → included
  // leadPlacementValid / includedLead checks → throw StateError as today
  // missing memberClis → ArgumentError as today
  // mixed uninitialized → StateError as today (or let caller check first)
  // for each included: SessionMemberBinding(..., taskId: allocate(), cli: ...)
}
```

Keep `resolveSessionMemberTargets` as a top-level function in the same file (or `session_member_targets.dart` if it grows) so repository and plan share one implementation.

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/services/session/team_session_member_plan_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/session/team_session_member_plan.dart \
  client/test/services/session/team_session_member_plan_test.dart \
  client/lib/repositories/session_repository.dart
git commit -m "feat(session): extract team session member plan builder"
```

---

### Task 2: `createSession` accepts staged bindings

**Files:**
- Modify: `client/lib/repositories/session_repository.dart`
- Modify: `client/lib/cubits/chat/session_data_store.dart` (if it wraps `createSession`)
- Create: `client/test/repositories/session_repository_stable_task_id_test.dart`

- [ ] **Step 1: Write failing repository tests**

```dart
test('staged members taskIds are preserved on createSession', () async {
  // createWorkspace + mark placement initialized if mixed
  final staged = [
    SessionMemberBinding(
      rosterMemberId: 'team-lead',
      taskId: 'fixed-lead-task',
      cli: CliTool.claude,
    ),
    SessionMemberBinding(
      rosterMemberId: 'builder-0',
      typeId: 'builder',
      taskId: 'fixed-builder-task',
      cli: CliTool.claude,
    ),
  ];
  final session = await repo.createSession(
    workspace.workspaceId,
    sessionTeam: 'team-1',
    rosterMembers: [/* matching types */],
    memberClis: {/* ... */},
    fixedSessionId: 'sess-1',
    members: staged,
    memberTargets: {
      'team-lead': 'local',
      'builder-0': 'local',
    },
  );
  expect(session.bindingFor('team-lead')!.taskId, 'fixed-lead-task');
  expect(session.bindingFor('builder-0')!.taskId, 'fixed-builder-task');
});

test('staged members whose ids disagree with placement throw', () async {
  // staged includes builder-0 but placement would exclude it → StateError
});
```

- [ ] **Step 2: Run test — expect FAIL (no `members:` param)**

```bash
cd client && flutter test test/repositories/session_repository_stable_task_id_test.dart
```

- [ ] **Step 3: Implement `createSession` staged path**

Add optional named params:

```dart
List<SessionMemberBinding>? members,
Map<String, String>? memberTargets,
```

Team branch algorithm:

1. Always run `buildTeamSessionMemberPlan(...)` (or placement-only) to get `persistTargets` + expected included id set.
2. If staged `members != null`:
   - Assert `Set(staged.rosterMemberId) == Set(plan.members.rosterMemberId)` else `StateError`.
   - Use **staged** bindings as `members` (preserve `taskId`/`cli`); use staged or plan `memberTargets` (prefer staged if provided and matching keys).
3. Else: use `plan.members` / `plan.memberTargets` (allocate path for automation).
4. If `plan.persistTargets`: `updateWorkspaceMemberTargets` as today.
5. Allocate `cliTeamName`, write session as today.

Do **not** call `Uuid.v4()` for seats when staged members are present.

- [ ] **Step 4: Run repository tests — expect PASS**

Also run existing session repository suites:

```bash
cd client && flutter test test/repositories/session_repository_test.dart \
  test/repositories/session_repository_replicas_test.dart \
  test/repositories/session_repository_stable_task_id_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/repositories/session_repository.dart \
  client/lib/cubits/chat/session_data_store.dart \
  client/test/repositories/session_repository_stable_task_id_test.dart
git commit -m "feat(session): persist staged member taskIds without reallocation"
```

---

### Task 3: Provisional staging uses the plan

**Files:**
- Modify: `client/lib/services/launch/session_launch_pipeline.dart`
- Modify: `client/lib/cubits/chat/session_launch_service.dart` (`_persistSessionIfNeeded`)
- Test: extend or add under `client/test/services/launch/` or `client/test/cubits/chat/` — prefer a focused unit that mocks/fakes as existing launch tests do

- [ ] **Step 1: Write failing test — provisional taskId ≠ sessionId and survives persist**

Preferred shape (mirror existing launch/persist tests):

```dart
test('team provisional bindings keep taskIds through persist', () async {
  // Drive CreateSessionOperation / pipeline with a fake host that captures
  // appendSessionSnapshot + replaceSessionSnapshot.
  // After persist: for each rosterMemberId,
  // provisional.taskId == persisted.taskId
  // and provisional.taskId != provisional.sessionId
});
```

If full pipeline harness is heavy, split:
1. Unit: pipeline staging function / extracted helper returns plan-based members.
2. Unit: `_persistSessionIfNeeded` passes `session.members` into repo (mock repo asserting args).

- [ ] **Step 2: Run — expect FAIL (still placeholder sessionId)**

- [ ] **Step 3: Implement pipeline + persist wiring**

In `session_launch_pipeline.dart` replace:

```dart
taskId: taskIdPlaceholder, // sessionId
```

with:

```dart
final memberClis = resolveSessionMemberCliLocks(
  team: request.team!,
  rosterMembers: request.team!.members,
  globalPresets: /* same source as persist path */,
);
final plan = buildTeamSessionMemberPlan(
  workspace: request.workspace,
  teamId: sessionTeamId,
  rosterMembers: request.team!.members,
  memberClis: memberClis,
);
provisional = provisional.copyWith(
  members: plan.members,
  memberTargets: plan.memberTargets,
);
```

Handle plan failures the same way create would (surface blocked / rollback). Do **not** stage full-expand placeholders for excluded mixed seats.

In `_persistSessionIfNeeded`:

```dart
final persisted = await repo.createSession(
  session.workspaceId,
  // ... existing args ...
  fixedSessionId: session.sessionId,
  members: session.members,           // staged
  memberTargets: session.memberTargets,
);
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/services/launch/ # or the specific new test file
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/launch/session_launch_pipeline.dart \
  client/lib/cubits/chat/session_launch_service.dart \
  client/test/...
git commit -m "fix(session): stage real member taskIds before persist"
```

---

### Task 4: History locate regression (narrow)

**Files:**
- Create: `client/test/services/session/stable_task_id_history_locate_test.dart`

Uses existing `AiHistoryLoader` / locator patterns from `ai_history_loader_test.dart` (fake registry + temp FS JSONL).

- [ ] **Step 1: Write failing tests documenting the contract**

```dart
test('locate hits transcript when binding.taskId matches filename', () async {
  // Write .../runtime/team-lead/claude/projects/{bucket}/{taskId}.jsonl
  // Session members: team-lead → that taskId
  // load History for team-lead → messages.isNotEmpty
});

test('locate misses when binding.taskId equals sessionId (old bug shape)', () async {
  // Same file named with realTaskId
  // Binding.taskId = sessionId
  // load → empty messages (or null locate)
});
```

Second test must pass **after** Task 1–3 only as documentation of the failure mode if someone reintroduces placeholder ids — it does not require production code that “handles” the miss.

- [ ] **Step 2: Run — first test may FAIL if harness wrong; fix harness until first PASS with correct taskId**

```bash
cd client && flutter test test/services/session/stable_task_id_history_locate_test.dart
```

- [ ] **Step 3: Commit**

```bash
git add client/test/services/session/stable_task_id_history_locate_test.dart
git commit -m "test(history): lock locate key to member taskId not sessionId"
```

---

### Task 5: Verification

- [ ] **Step 1: Analyze + unit suite**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test \
  test/services/session/team_session_member_plan_test.dart \
  test/repositories/session_repository_stable_task_id_test.dart \
  test/services/session/stable_task_id_history_locate_test.dart \
  test/repositories/session_repository_test.dart \
  test/repositories/session_repository_replicas_test.dart
```

Expected: no new analyzer errors; all listed tests PASS.

- [ ] **Step 2: Manual smoke (optional but matches acceptance)**

New mixed team → leader Chat → send first message → History shows user/assistant without switching members; `session.json` leader `taskId` equals JSONL basename under `runtime/team-lead/claude/projects/…`.

- [ ] **Step 3: Final commit if any fixups**

```bash
git commit -m "chore: stable taskId follow-ups"
```

---

## Out of scope (do not implement)

- History `softReloadOrLoad` taskId-change detection
- `SessionPersistParams` new fields
- Migrating old sessions
- Changing `ensureMemberBinding` / `cloneWorkspace` UUID behavior
