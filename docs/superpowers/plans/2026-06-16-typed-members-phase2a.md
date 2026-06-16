# Typed Members Phase 2a — Backend Core (replicas) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A member type can declare `replicas: N`; opening a mixed-team session runs N identical instances (pods) that share the type as their routing capability and self-balance the type's task queue — with no UI yet.

**Architecture:** `TeamMemberConfig` is the type (Deployment); a new `MemberInstance` value type + pure `expandTeamRoster(team)` is the single Deployment→Pod fan-out. The runtime consumes `runtimeRosterMembers(team)` — instance *projections* (`TeamMemberConfig` with `id = instanceId`, `capabilities` seeded with the type id) — wherever it used to iterate `team.members`. Phase 1's "id is a capability" rule then makes routing fall out: a projection's caps = `{instanceId, typeId} ∪ explicit`. Singleton rule: `replicas == 1 → instanceId == typeId`, so existing teams are byte-identical.

**Tech Stack:** Dart / Flutter, `flutter_test`. Files under `client/lib/models/`, `client/lib/repositories/`, `client/lib/cubits/chat/`.

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `client/lib/models/team_config.dart` | `TeamMemberConfig.replicas` (the type's pool size) | Modify |
| `client/lib/models/discoverable_team.dart` | `DiscoverableTeamMember.replicas` for templates | Modify |
| `client/lib/models/member_instance.dart` | `MemberInstance` + `expandTeamRoster` + `runtimeRosterMembers` (pure) | Create |
| `client/lib/models/session_member_binding.dart` | add `typeId` | Modify |
| `client/lib/repositories/session_repository.dart` | allocate one binding per instance | Modify |
| `client/lib/cubits/chat/session_launch_service.dart` | launch fan-out iterates instances | Modify |
| `client/lib/cubits/chat/tab_team_bus_coordinator.dart` | bus declaration + forceWait iterate instances | Modify |

**Out of scope (Phase 2b / later):** member-config UI replicas stepper; tab/sidebar pod presentation; single-member connect paths for `replicas > 1` (UI-driven); provider native-roster resolvers (native-mode, not the mixed-mode TeamBus path).

---

## Task 1: `replicas` on the member type

**Files:**
- Modify: `client/lib/models/team_config.dart`
- Test: `client/test/models/team_config_replicas_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `client/test/models/team_config_replicas_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  test('replicas defaults to 1 and round-trips when > 1', () {
    const m = TeamMemberConfig(id: 'builder', name: 'Builder');
    expect(m.replicas, 1);

    const r = TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 3);
    expect(r.replicas, 3);
    expect(TeamMemberConfig.fromJson(r.toJson()).replicas, 3);
    // default omitted from json
    expect(m.toJson().containsKey('replicas'), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/team_config_replicas_test.dart`
Expected: FAIL — `replicas` is not a parameter of `TeamMemberConfig`.

- [ ] **Step 3: Add the `replicas` field**

In `client/lib/models/team_config.dart`, `class TeamMemberConfig`:

Constructor — add after `this.effort = '',`:
```dart
    this.replicas = 1,
```

`fromJson` — add after the `effort:` line:
```dart
      replicas: (json['replicas'] as num?)?.toInt() ?? 1,
```

Field declaration — add after `final String effort;`:
```dart
  /// Fixed instance/pool size for this member type (mixed-mode replicas).
  /// `1` (default) = a singleton; `> 1` = an interchangeable pool. See
  /// [MemberInstance] / `expandTeamRoster`.
  final int replicas;
```

`copyWith` — add parameter (after `String? effort,` / its `updateEffort` flag):
```dart
    int? replicas,
```
and in the returned `TeamMemberConfig(...)`:
```dart
      replicas: replicas ?? this.replicas,
```

`toJson` — add after the `effort` entry:
```dart
      if (replicas != 1) 'replicas': replicas,
```

`operator ==` — add:
```dart
            replicas == other.replicas &&
```

`hashCode` — add `replicas,` to the `Object.hash(...)` argument list.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/team_config_replicas_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/team_config.dart client/test/models/team_config_replicas_test.dart
git commit -m "feat(team): add replicas to the member type config"
```

---

## Task 2: `replicas` on the template member

**Files:**
- Modify: `client/lib/models/discoverable_team.dart`
- Test: `client/test/models/discoverable_team_test.dart` (extend)

- [ ] **Step 1: Write the failing test**

In `client/test/models/discoverable_team_test.dart`, add inside `main()`:

```dart
  test('member replicas round-trips and flows to TeamMemberConfig', () {
    const dm = DiscoverableTeamMember(name: 'builder', replicas: 4);
    expect(dm.replicas, 4);
    expect(DiscoverableTeamMember.fromJson(dm.toJson()).replicas, 4);
    expect(dm.toMemberConfig(joinedAt: 1).replicas, 4);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/discoverable_team_test.dart`
Expected: FAIL — `replicas` not a parameter of `DiscoverableTeamMember`.

- [ ] **Step 3: Add `replicas` to `DiscoverableTeamMember`**

In `client/lib/models/discoverable_team.dart`, `class DiscoverableTeamMember`:

Constructor — add after `this.capabilities = const {},`:
```dart
    this.replicas = 1,
```

`fromJson` — add after the `capabilities:` block:
```dart
        replicas: (json['replicas'] as num?)?.toInt() ?? 1,
```

Field — add after `final Set<String> capabilities;`:
```dart
  /// Pool size for this member type — maps to [TeamMemberConfig.replicas].
  final int replicas;
```

`toJson` — add after the `capabilities` entry:
```dart
        if (replicas != 1) 'replicas': replicas,
```

`toMemberConfig` — add to the returned `TeamMemberConfig(...)`:
```dart
      replicas: replicas,
```

`operator ==` — add:
```dart
      replicas == other.replicas &&
```

`hashCode` — add `replicas,` to the `Object.hash(...)` argument list.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/discoverable_team_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/discoverable_team.dart client/test/models/discoverable_team_test.dart
git commit -m "feat(team-hub): add replicas to the discoverable team member"
```

---

## Task 3: `MemberInstance` + `expandTeamRoster` (the fan-out)

**Files:**
- Create: `client/lib/models/member_instance.dart`
- Test: `client/test/models/member_instance_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `client/test/models/member_instance_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/member_instance.dart';
import 'package:teampilot/models/team_config.dart';

TeamConfig team(List<TeamMemberConfig> members) => TeamConfig(
      id: 'team-1',
      name: 'T',
      cli: CliTool.claude,
      teamMode: TeamMode.mixed,
      members: members,
    );

void main() {
  test('singleton type → one instance whose id is the type id', () {
    final insts = expandTeamRoster(const [
      TeamMemberConfig(id: 'builder', name: 'Builder'),
    ]);
    expect(insts.single.instanceId, 'builder');
    expect(insts.single.displayName, 'Builder');
  });

  test('replicated type → N numbered instances', () {
    final insts = expandTeamRoster(const [
      TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 3),
    ]);
    expect(insts.map((i) => i.instanceId), ['builder-0', 'builder-1', 'builder-2']);
    expect(insts.map((i) => i.displayName),
        ['Builder #0', 'Builder #1', 'Builder #2']);
  });

  test('the team-lead is always a singleton regardless of replicas', () {
    final insts = expandTeamRoster(const [
      TeamMemberConfig(id: 'team-lead', name: 'team-lead', replicas: 5),
    ]);
    expect(insts.single.instanceId, 'team-lead');
  });

  test('projection seeds the type id as a capability', () {
    final inst = expandTeamRoster(const [
      TeamMemberConfig(
          id: 'builder', name: 'Builder', replicas: 2,
          capabilities: {'rust'}),
    ]).first;
    final cfg = inst.toMemberConfig();
    expect(cfg.id, 'builder-0');
    expect(cfg.capabilities, {'builder', 'rust'});
  });

  test('runtimeRosterMembers projects every instance', () {
    final members = runtimeRosterMembers(team(const [
      TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
      TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
    ]));
    expect(members.map((m) => m.id), ['team-lead', 'builder-0', 'builder-1']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/member_instance_test.dart`
Expected: FAIL — `member_instance.dart` does not exist.

- [ ] **Step 3: Create the module**

Create `client/lib/models/member_instance.dart`:

```dart
import '../utils/team_member_naming.dart';
import 'team_config.dart';

/// A runtime instance (Pod) of a member [type] (Deployment). Holds no copy of
/// the spec — it resolves prompt/playbook/model/cli through [type]. The single
/// Deployment→Pod fan-out is [expandTeamRoster]; the runtime consumes the
/// [toMemberConfig] projection via [runtimeRosterMembers].
class MemberInstance {
  const MemberInstance({
    required this.type,
    required this.ordinal,
    required this.replicas,
  });

  final TeamMemberConfig type;

  /// 0-based position within the type's pool.
  final int ordinal;

  /// The type's effective pool size (drives the id rule).
  final int replicas;

  /// A singleton (`replicas == 1`) is named after its type; a replicated type
  /// yields `{typeId}-{ordinal}`.
  String get instanceId =>
      replicas <= 1 ? type.id : '${type.id}-$ordinal';

  String get displayName =>
      replicas <= 1 ? type.name : '${type.name} #$ordinal';

  /// Runtime projection: a [TeamMemberConfig] with `id = instanceId` and the
  /// type id seeded as a capability so [TaskRouter] routes the pool by type
  /// (and the pod by its own id, via the id-as-capability rule).
  TeamMemberConfig toMemberConfig() => type.copyWith(
        id: instanceId,
        name: displayName,
        capabilities: {type.id, ...type.capabilities},
      );
}

/// The single Deployment→Pod fan-out. The team-lead is always a singleton; any
/// other type yields `max(1, replicas)` instances.
List<MemberInstance> expandTeamRoster(List<TeamMemberConfig> members) {
  final out = <MemberInstance>[];
  for (final type in members) {
    final n = TeamMemberNaming.isTeamLead(type) || type.replicas < 1
        ? 1
        : type.replicas;
    for (var i = 0; i < n; i++) {
      out.add(MemberInstance(type: type, ordinal: i, replicas: n));
    }
  }
  return out;
}

/// Instance projections the launch/bus layers iterate in place of
/// `team.members`.
List<TeamMemberConfig> runtimeRosterMembers(TeamConfig team) =>
    [for (final inst in expandTeamRoster(team.members)) inst.toMemberConfig()];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/member_instance_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/member_instance.dart client/test/models/member_instance_test.dart
git commit -m "feat(team): MemberInstance + expandTeamRoster Deployment/Pod fan-out"
```

---

## Task 4: `typeId` on the session binding

**Files:**
- Modify: `client/lib/models/session_member_binding.dart`
- Test: `client/test/models/session_member_binding_test.dart` (create)

Note: the existing field `rosterMemberId` now holds the **instance id**; we add `typeId`. The field is intentionally not renamed (the rename would churn ~10 files without architectural gain).

- [ ] **Step 1: Write the failing test**

Create `client/test/models/session_member_binding_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_member_binding.dart';

void main() {
  test('typeId round-trips; defaults to the instance id when absent', () {
    const b = SessionMemberBinding(
        rosterMemberId: 'builder-0', typeId: 'builder', taskId: 't1');
    final back = SessionMemberBinding.fromJson(b.toJson());
    expect(back.rosterMemberId, 'builder-0');
    expect(back.typeId, 'builder');
    expect(back.taskId, 't1');

    // legacy json without typeId falls back to the instance id
    final legacy = SessionMemberBinding.fromJson(
        {'rosterMemberId': 'reviewer', 'taskId': 't2'});
    expect(legacy.typeId, 'reviewer');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/session_member_binding_test.dart`
Expected: FAIL — `typeId` not a parameter of `SessionMemberBinding`.

- [ ] **Step 3: Add `typeId`**

Replace the body of `client/lib/models/session_member_binding.dart` with:

```dart
import 'package:flutter/foundation.dart';

@immutable
class SessionMemberBinding {
  const SessionMemberBinding({
    required this.rosterMemberId,
    required this.taskId,
    String? typeId,
  }) : typeId = typeId ?? rosterMemberId;

  factory SessionMemberBinding.fromJson(Map<String, Object?> json) {
    final instanceId = json['rosterMemberId'] as String? ?? '';
    return SessionMemberBinding(
      rosterMemberId: instanceId,
      taskId: json['taskId'] as String? ?? '',
      typeId: json['typeId'] as String? ?? instanceId,
    );
  }

  /// The runtime instance id (pod). Named `rosterMemberId` for history.
  final String rosterMemberId;

  /// The member **type** this instance belongs to (the routing key).
  final String typeId;
  final String taskId;

  Map<String, Object?> toJson() => {
        'rosterMemberId': rosterMemberId,
        if (typeId != rosterMemberId) 'typeId': typeId,
        'taskId': taskId,
      };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SessionMemberBinding &&
            runtimeType == other.runtimeType &&
            rosterMemberId == other.rosterMemberId &&
            typeId == other.typeId &&
            taskId == other.taskId;
  }

  @override
  int get hashCode => Object.hash(rosterMemberId, typeId, taskId);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/session_member_binding_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/session_member_binding.dart client/test/models/session_member_binding_test.dart
git commit -m "feat(session): record the member typeId on each instance binding"
```

---

## Task 5: Allocate one binding per instance

**Files:**
- Modify: `client/lib/repositories/session_repository.dart`
- Test: `client/test/repositories/session_repository_replicas_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `client/test/repositories/session_repository_replicas_test.dart`. It drives `createSession` through the project's session-repo test harness. First inspect an existing repo test for the exact constructor/setup:

Run: `cd client && grep -rl "SessionRepository(" test/repositories | head`

Then mirror that harness. The assertion body (adapt the setup lines to the harness you find):

```dart
    final session = await repo.createSession(
      projectId,
      sessionTeam: 'team-1',
      rosterMembers: const [
        TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
        TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 2),
      ],
    );
    expect(
      session.members.map((b) => b.rosterMemberId),
      ['team-lead', 'builder-0', 'builder-1'],
    );
    expect(
      session.members.map((b) => b.typeId),
      ['team-lead', 'builder', 'builder'],
    );
    // distinct task ids
    expect(session.members.map((b) => b.taskId).toSet().length, 3);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/repositories/session_repository_replicas_test.dart`
Expected: FAIL — `createSession` emits one binding per type (`['team-lead', 'builder']`), no `typeId`.

- [ ] **Step 3: Expand bindings in `createSession`**

In `client/lib/repositories/session_repository.dart`, add the import at the top (with the other model imports):

```dart
import '../models/member_instance.dart';
```

Replace the binding allocation (around line 375-378):

```dart
      members = [
        for (final m in valid)
          SessionMemberBinding(rosterMemberId: m.id, taskId: const Uuid().v4()),
      ];
```
with:

```dart
      members = [
        for (final inst in expandTeamRoster(valid))
          SessionMemberBinding(
            rosterMemberId: inst.instanceId,
            typeId: inst.type.id,
            taskId: const Uuid().v4(),
          ),
      ];
```

- [ ] **Step 4: Mirror the same expansion in the copy/import path**

In the same file (around line 684-690), replace:

```dart
        members = [
          for (final m in valid)
            SessionMemberBinding(
              rosterMemberId: m.id,
              taskId: const Uuid().v4(),
            ),
        ];
```
with:

```dart
        members = [
          for (final inst in expandTeamRoster(valid))
            SessionMemberBinding(
              rosterMemberId: inst.instanceId,
              typeId: inst.type.id,
              taskId: const Uuid().v4(),
            ),
        ];
```

- [ ] **Step 5: Carry `typeId` through `ensureMemberBinding`**

In the same file, `ensureMemberBinding` (around line 443): add a `typeId` parameter and use it. Change the signature:

```dart
  Future<SessionMemberBinding> ensureMemberBinding(
    String sessionId,
    String rosterMemberId, {
    String? typeId,
  }) {
```
and the binding it creates (around line 465):

```dart
      final binding = SessionMemberBinding(
        rosterMemberId: trimmedMemberId,
        typeId: (typeId ?? trimmedMemberId).trim(),
        taskId: const Uuid().v4(),
      );
```

(Existing single caller passes a type id for `rosterMemberId`, so the `typeId` default is correct for `replicas == 1`.)

- [ ] **Step 6: Run test to verify it passes**

Run: `cd client && flutter test test/repositories/session_repository_replicas_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/repositories/session_repository.dart client/test/repositories/session_repository_replicas_test.dart
git commit -m "feat(session): allocate one binding per instance via expandTeamRoster"
```

---

## Task 6: Launch fan-out iterates instances

**Files:**
- Modify: `client/lib/cubits/chat/session_launch_service.dart`

This is the loop that connects all members when a mixed session opens
([session_launch_service.dart:228-236](../../../client/lib/cubits/chat/session_launch_service.dart)).

- [ ] **Step 1: Add the import**

In `client/lib/cubits/chat/session_launch_service.dart`, add with the other model imports:

```dart
import '../../models/member_instance.dart';
```

- [ ] **Step 2: Reroute the fan-out loop to instance projections**

Replace the loop body (around line 230):

```dart
    for (final candidate in team.members.where((m) => m.isValid)) {
      if (candidate.id == keepSelectedMemberId) continue;
      _scheduleMemberConnect(team, candidate, tab);
    }
    if (team.members.any((m) => m.id == keepSelectedMemberId)) {
      _h.selectMember(keepSelectedMemberId);
    }
```
with:

```dart
    final instances = runtimeRosterMembers(team).where((m) => m.isValid);
    for (final candidate in instances) {
      if (candidate.id == keepSelectedMemberId) continue;
      _scheduleMemberConnect(team, candidate, tab);
    }
    if (instances.any((m) => m.id == keepSelectedMemberId)) {
      _h.selectMember(keepSelectedMemberId);
    }
```

Each `candidate` is now an instance projection (`id == instanceId`); `_scheduleMemberConnect` keys shells / pending-connect / config-profile on that id, so each pod connects independently. For `replicas == 1`, `instanceId == typeId`, so this is identical to today.

- [ ] **Step 3: Run the existing launch tests to verify no regression**

Run: `cd client && flutter test test/widget_test.dart --plain-name "openSessionTab"`
Expected: PASS — existing single-instance behavior unchanged (instanceId == typeId).

- [ ] **Step 4: Commit**

```bash
git add client/lib/cubits/chat/session_launch_service.dart
git commit -m "feat(session): connect one terminal per instance on session open"
```

---

## Task 7: Bus declaration + forceWait iterate instances

**Files:**
- Modify: `client/lib/cubits/chat/tab_team_bus_coordinator.dart`

- [ ] **Step 1: Add the import**

In `client/lib/cubits/chat/tab_team_bus_coordinator.dart`, add with the other model imports:

```dart
import '../../models/member_instance.dart';
```

- [ ] **Step 2: Declare one bus node per instance**

Replace the declaration loop (around line 94-112):

```dart
    for (final m in team.members) {
      final taskId = session.members
          .where((b) => b.rosterMemberId == m.id)
          .map((b) => b.taskId)
          .where((id) => id.isNotEmpty)
          .firstOrNull;
      bus.declareMember(
        AgentNode(
          profile: TeammateRosterProfile.fromMember(
            member: m,
            team: team,
            cliTeamName: cliTeamName,
            cwd: session.primaryPath,
            taskId: taskId,
          ),
          lifecycle: MemberLifecycle.declared,
        ),
      );
    }
```
with:

```dart
    for (final m in runtimeRosterMembers(team)) {
      final taskId = session.members
          .where((b) => b.rosterMemberId == m.id)
          .map((b) => b.taskId)
          .where((id) => id.isNotEmpty)
          .firstOrNull;
      bus.declareMember(
        AgentNode(
          profile: TeammateRosterProfile.fromMember(
            member: m,
            team: team,
            cliTeamName: cliTeamName,
            cwd: session.primaryPath,
            taskId: taskId,
          ),
          lifecycle: MemberLifecycle.declared,
        ),
      );
    }
```

`m` is an instance projection: `m.id == instanceId`, and `fromMember` (Phase 1 rule) yields `capabilities = {instanceId} ∪ {typeId, ...explicit}` — the pool routes by `typeId`, the pod by `instanceId`.

- [ ] **Step 3: Resolve forceWait per instance**

In the same file, the `forceWaitForMember` resolver (around line 119-124) currently matches `team.members.where((m) => m.id == memberId)`. Replace `team.members` there with `runtimeRosterMembers(team)`:

```dart
        forceWaitForMember: (memberId) =>
            runtimeRosterMembers(team)
                .where((m) => m.id == memberId)
                .map((m) => m.effectiveForceWaitBeforeStop(team))
                .firstOrNull ??
            team.forceWaitBeforeStop,
```

(The projection preserves `cli`/`forceWaitBeforeStop`, so `effectiveForceWaitBeforeStop` resolves correctly per instance.)

- [ ] **Step 4: Run the team_bus + coordinator tests**

Run: `cd client && flutter test test/services/team_bus test/cubits`
Expected: PASS — single-instance teams unchanged; a `replicas: 2` team declares two bus nodes (`builder-0`, `builder-1`).

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/chat/tab_team_bus_coordinator.dart
git commit -m "feat(team-bus): declare one bus node per instance with type routing"
```

---

## Task 8: Verification

**Files:** none (verification only)

- [ ] **Step 1: Analyze the touched files**

Run: `cd client && flutter analyze lib/models/member_instance.dart lib/models/team_config.dart lib/models/discoverable_team.dart lib/models/session_member_binding.dart lib/repositories/session_repository.dart lib/cubits/chat/session_launch_service.dart lib/cubits/chat/tab_team_bus_coordinator.dart`
Expected: `No issues found!`

- [ ] **Step 2: Run the affected suites**

Run: `cd client && flutter test test/models test/repositories test/services/team_bus test/services/team_hub test/cubits`
Expected: PASS.

- [ ] **Step 3: Commit any fixups (only if Steps 1-2 surfaced issues)**

```bash
git add -A
git commit -m "fix(team): phase-2a verification fixups"
```

---

## Self-Review notes (already applied)

- **Spec coverage (Phase 2a):** `replicas` on type (Task 1) + template (Task 2); `MemberInstance`/`expandTeamRoster`/`runtimeRosterMembers`/projection (Task 3); binding `typeId` (Task 4); per-instance binding allocation (Task 5); launch fan-out reroute (Task 6); bus declaration + forceWait reroute (Task 7). Phase 2b (UI, pod presentation, single-connect paths for `replicas>1`) is out of scope.
- **Consistency:** the projection `toMemberConfig()` (`id=instanceId`, `capabilities={typeId}∪explicit`) feeds the unchanged `fromMember`, so Phase 1's id-as-capability rule yields `{instanceId, typeId, …}` everywhere; routing tests already cover eligibility.
- **Non-breaking:** `replicas == 1 → instanceId == typeId`, so every existing single-instance team produces identical binding ids, shells, config-profile dirs, and bus nodes.
- **Deviation from spec:** the binding field keeps its name `rosterMemberId` (value = instance id) instead of renaming to `instanceId`; `typeId` is added alongside. Rationale: avoids a ~10-file rename with no architectural gain.
