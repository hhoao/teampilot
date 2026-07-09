# Landing-driven Member Placement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Landing team-settings Machines the only place that sets member instance counts and host pins, with placement-driven `replicas`, zero-replica support, and a mixed first-init flag.

**Architecture:** Placement (`MemberPlacementByTarget`) is the editor source of truth. On save, sum counts → `TeamMemberConfig.replicas`, expand → `memberTargetsByTeam`, and set `memberPlacementInitializedByTeam[teamId]`. Launch gates switch from “every instance assigned (mixed-only)” to “mixed needs init flag + lead host valid”. Session create omits unpinned mixed instances from bindings and TeamBus roster.

**Tech Stack:** Flutter / `flutter_bloc`, existing `Workspace` / `SessionRepository` JSON manifests, l10n ARB en/zh.

**Spec:** [docs/superpowers/specs/2026-07-09-landing-member-placement-design.md](../specs/2026-07-09-landing-member-placement-design.md)

---

## File map (target)

| File | Responsibility |
|------|----------------|
| `client/lib/models/member_instance.dart` | Allow non-lead `replicas <= 0` → zero instances; add `sessionRosterMembers` helper |
| `client/lib/models/workspace.dart` | Persist `memberPlacementInitializedByTeam` |
| `client/lib/models/workspace_topology.dart` | Lead host helpers, default placement, init/lead gates, apply placement→replicas |
| `client/lib/services/launch/member_placement_save.dart` | Shared save: replicas + targets + init flag |
| `client/lib/services/launch/workspace_landing_launch_gate.dart` | Block on mixed uninitialized / invalid lead |
| `client/lib/repositories/session_repository.dart` | Persist flag; reset on host-set change; createSession omit/pin rules |
| `client/lib/cubits/chat/session_launch_service.dart` | Schedule connects from session-scoped roster |
| `client/lib/cubits/chat/tab_team_bus_coordinator.dart` | Install bus from session-scoped roster |
| `client/lib/pages/.../mixed_workspace_member_placement_panel.dart` | Unbounded +/-; lead locks |
| `client/lib/pages/.../workspace_landing_team_settings_dialog.dart` | Always show Machines; new save path |
| `client/lib/pages/.../config/workspace_team_member_targets_*.dart` | Same save path as Landing |
| `client/lib/pages/team_config/team_config_member_section.dart` | Remove replicas row |
| `client/lib/l10n/app_en.arb` + `app_zh.arb` | First-init / lead copy |

---

### Task 1: Zero-replica roster expansion

**Files:**
- Modify: `client/lib/models/member_instance.dart`
- Modify: `client/lib/models/workspace_topology.dart` (`memberTypeReplicaCount`)
- Test: `client/test/models/member_instance_test.dart`
- Test: `client/test/models/workspace_topology_test.dart` (update any assumptions)

- [ ] **Step 1: Write failing tests**

Add to `client/test/models/member_instance_test.dart`:

```dart
test('non-lead replicas 0 yields no instances', () {
  final insts = expandTeamRoster(const [
    TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 0),
  ]);
  expect(insts, isEmpty);
});

test('lead with replicas 0 still yields one instance', () {
  final insts = expandTeamRoster(const [
    TeamMemberConfig(id: 'team-lead', name: 'team-lead', replicas: 0),
  ]);
  expect(insts.single.instanceId, 'team-lead');
});
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd client && flutter test test/models/member_instance_test.dart`
Expected: FAIL — `replicas: 0` still expands to 1

- [ ] **Step 3: Implement**

In `member_instance.dart` `expandTeamRoster`:

```dart
for (final type in members) {
  if (TeamMemberNaming.isTeamLead(type)) {
    out.add(MemberInstance(type: type, ordinal: 0, replicas: 1));
    continue;
  }
  final n = type.replicas;
  if (n < 1) continue;
  for (var i = 0; i < n; i++) {
    out.add(MemberInstance(type: type, ordinal: i, replicas: n));
  }
}
```

In `workspace_topology.dart`:

```dart
int memberTypeReplicaCount(TeamMemberConfig type) {
  if (TeamMemberNaming.isTeamLead(type)) return 1;
  return type.replicas < 0 ? 0 : type.replicas;
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/models/member_instance_test.dart test/models/workspace_topology_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/member_instance.dart client/lib/models/workspace_topology.dart client/test/models/member_instance_test.dart client/test/models/workspace_topology_test.dart
git commit -m "fix: allow zero replicas for non-lead member types"
```

---

### Task 2: Workspace init-flag field

**Files:**
- Modify: `client/lib/models/workspace.dart`
- Test: `client/test/models/workspace_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
test('memberPlacementInitializedByTeam round-trips and omits when empty', () {
  final w = Workspace(
    workspaceId: 'ws',
    folders: const [WorkspaceFolder(path: '/a')],
    createdAt: 1,
    memberPlacementInitializedByTeam: const {'team-1': true},
  );
  final decoded = Workspace.fromJson(w.toJson());
  expect(decoded.memberPlacementInitializedByTeam['team-1'], isTrue);
  expect(
    Workspace(
      workspaceId: 'ws',
      folders: const [WorkspaceFolder(path: '/a')],
      createdAt: 1,
    ).toJson().containsKey('memberPlacementInitializedByTeam'),
    isFalse,
  );
});
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd client && flutter test test/models/workspace_test.dart --name memberPlacementInitialized`

- [ ] **Step 3: Implement field**

Add `memberPlacementInitializedByTeam` to constructor, `fromJson`, `toJson`, `copyWith`, `==`, `hashCode`. Freeze as `Map<String, bool>` (trim keys; only store `true` values or explicit bools — prefer storing only `true` entries and treat missing as false).

```dart
static Map<String, bool> _initializedByTeamFromJson(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, bool>{};
  for (final e in raw.entries) {
    final id = e.key.toString().trim();
    if (id.isEmpty) continue;
    if (e.value == true) out[id] = true;
  }
  return Map.unmodifiable(out);
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/models/workspace_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/workspace.dart client/test/models/workspace_test.dart
git commit -m "feat: persist memberPlacementInitializedByTeam on Workspace"
```

---

### Task 3: Topology helpers (defaults, lead, init, apply)

**Files:**
- Modify: `client/lib/models/workspace_topology.dart`
- Test: `client/test/models/workspace_topology_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
test('preferredLeadHost prefers local when present', () {
  expect(
    preferredLeadHost([
      const WorkspaceFolder(path: '/a'),
      const WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
    ]),
    WorkspaceFolder.localTargetId,
  );
  expect(
    preferredLeadHost([
      const WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
    ]),
    'ssh:p1',
  );
});

test('defaultMemberPlacement pins all types to sole host', () {
  const members = [
    TeamMemberConfig(id: 'team-lead', name: 'Lead'),
    TeamMemberConfig(id: 'dev', name: 'Dev'),
  ];
  final p = defaultMemberPlacement(
    folders: [const WorkspaceFolder(path: '/a')],
    members: members,
  );
  expect(p['local']?['team-lead'], 1);
  expect(p['local']?['dev'], 1);
});

test('defaultMemberPlacement for mixed pins only lead', () {
  const members = [
    TeamMemberConfig(id: 'team-lead', name: 'Lead'),
    TeamMemberConfig(id: 'dev', name: 'Dev'),
  ];
  final p = defaultMemberPlacement(
    folders: [
      const WorkspaceFolder(path: '/a'),
      const WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
    ],
    members: members,
  );
  expect(p['local']?['team-lead'], 1);
  expect(memberPlacementCountForType(p, 'dev'), 0);
});

test('leadPlacementValid requires local lead when local exists', () {
  const folders = [
    WorkspaceFolder(path: '/a'),
    WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
  ];
  expect(
    leadPlacementValid(
      folders: folders,
      members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
      targets: const {'team-lead': 'ssh:p1'},
    ),
    isFalse,
  );
  expect(
    leadPlacementValid(
      folders: folders,
      members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
      targets: const {'team-lead': 'local'},
    ),
    isTrue,
  );
});

test('workspaceNeedsMixedPlacementInit is true until flag set', () {
  final folders = [
    const WorkspaceFolder(path: '/a'),
    const WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
  ];
  expect(
    workspaceNeedsMixedPlacementInit(
      folders: folders,
      teamId: 't1',
      initializedByTeam: const {},
    ),
    isTrue,
  );
  expect(
    workspaceNeedsMixedPlacementInit(
      folders: folders,
      teamId: 't1',
      initializedByTeam: const {'t1': true},
    ),
    isFalse,
  );
  expect(
    workspaceNeedsMixedPlacementInit(
      folders: [const WorkspaceFolder(path: '/a')],
      teamId: 't1',
      initializedByTeam: const {},
    ),
    isFalse,
  );
});

test('applyPlacementReplicasToMembers sums counts', () {
  const members = [
    TeamMemberConfig(id: 'team-lead', name: 'Lead', replicas: 9),
    TeamMemberConfig(id: 'dev', name: 'Dev', replicas: 9),
  ];
  final next = applyPlacementReplicasToMembers(
    members: members,
    placement: {
      'local': {'team-lead': 1, 'dev': 2},
      'ssh:p1': {'dev': 1},
    },
  );
  expect(next.firstWhere((m) => m.id == 'team-lead').replicas, 1);
  expect(next.firstWhere((m) => m.id == 'dev').replicas, 3);
});

test('inferMemberPlacementInitialized requires valid non-empty targets', () {
  const folders = [
    WorkspaceFolder(path: '/a'),
    WorkspaceFolder(path: '/b', targetId: 'ssh:p1'),
  ];
  expect(
    inferMemberPlacementInitialized(
      folders: folders,
      members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
      targets: const {'team-lead': 'local'},
      alreadyInitialized: false,
    ),
    isTrue,
  );
  expect(
    inferMemberPlacementInitialized(
      folders: folders,
      members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
      targets: const {'team-lead': 'ssh:gone'},
      alreadyInitialized: false,
    ),
    isFalse,
  );
});
```

Also update/remove the old test `requires member assignment only for mixed` / `memberTargetsComplete requires every instance` to match new helpers (keep `memberTargetsComplete` as a pure completeness check if still useful for UI progress, but it must no longer gate launch).

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd client && flutter test test/models/workspace_topology_test.dart`

- [ ] **Step 3: Implement helpers** in `workspace_topology.dart`

Required APIs:

```dart
String? preferredLeadHost(List<WorkspaceFolder> folders);
MemberPlacementByTarget defaultMemberPlacement({
  required List<WorkspaceFolder> folders,
  required List<TeamMemberConfig> members,
});
bool leadPlacementValid({
  required List<WorkspaceFolder> folders,
  required List<TeamMemberConfig> members,
  required MemberTargetAssignments targets,
});
bool workspaceNeedsMixedPlacementInit({
  required List<WorkspaceFolder> folders,
  required String teamId,
  required Map<String, bool> initializedByTeam,
});
List<TeamMemberConfig> applyPlacementReplicasToMembers({
  required List<TeamMemberConfig> members,
  required MemberPlacementByTarget placement,
});
bool inferMemberPlacementInitialized({
  required List<WorkspaceFolder> folders,
  required List<TeamMemberConfig> members,
  required MemberTargetAssignments targets,
  required bool alreadyInitialized,
});
```

Deprecate usage of `workspaceTopologyRequiresMemberAssignment` for launch (leave function temporarily returning `topology == mixed` only if call sites still need a mixed check, or replace call sites in later tasks).

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/models/workspace_topology_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/workspace_topology.dart client/test/models/workspace_topology_test.dart
git commit -m "feat: add placement defaults, lead validation, and init helpers"
```

---

### Task 4: Shared Machines save helper

**Files:**
- Create: `client/lib/services/launch/member_placement_save.dart`
- Create: `client/test/services/launch/member_placement_save_test.dart`

- [ ] **Step 1: Write failing test**

```dart
test('save applies replicas, targets, and init flag', () async {
  // Use an in-memory / fake SessionRepository + LaunchProfileCubit if existing
  // test harnesses allow; otherwise unit-test a pure prepare function:
  final prepared = prepareMemberPlacementSave(
    team: team,
    folders: folders,
    placement: placement,
  );
  expect(prepared.members.firstWhere((m) => m.id == 'dev').replicas, 2);
  expect(prepared.targets['dev-0'], 'local');
  expect(prepared.markInitialized, isTrue);
  expect(prepared.leadValid, isTrue);
});
```

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client && flutter test test/services/launch/member_placement_save_test.dart`

- [ ] **Step 3: Implement**

```dart
class PreparedMemberPlacementSave {
  const PreparedMemberPlacementSave({
    required this.members,
    required this.targets,
    required this.leadValid,
    required this.markInitialized,
  });
  final List<TeamMemberConfig> members;
  final MemberTargetAssignments targets;
  final bool leadValid;
  final bool markInitialized;
}

PreparedMemberPlacementSave prepareMemberPlacementSave({
  required TeamProfile team,
  required List<WorkspaceFolder> folders,
  required MemberPlacementByTarget placement,
}) {
  final members = applyPlacementReplicasToMembers(
    members: team.members,
    placement: placement,
  );
  final targets = memberTargetsFromMemberPlacement(
    workspaceFolders: folders,
    members: members,
    placement: placement,
  );
  return PreparedMemberPlacementSave(
    members: members,
    targets: targets,
    leadValid: leadPlacementValid(
      folders: folders,
      members: members,
      targets: targets,
    ),
    markInitialized: true,
  );
}
```

Add `SessionRepository.updateWorkspaceMemberPlacement` that writes **both** `memberTargetsByTeam[teamId]` and `memberPlacementInitializedByTeam[teamId]=true` in one manifest update. Prefer this single API over a separate meta method; Tasks 8–9 must call it (not targets-only).

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/launch/member_placement_save.dart client/test/services/launch/member_placement_save_test.dart client/lib/repositories/session_repository.dart
git commit -m "feat: shared prepare/save path for member placement"
```

---

### Task 5: Launch gate + attention affordance

**Files:**
- Modify: `client/lib/services/launch/workspace_landing_launch_gate.dart`
- Modify: `client/lib/services/launch/session_launch_readiness.dart`
- Modify: `client/lib/services/launch/session_launch_pipeline.dart`
- Modify: `client/lib/services/launch/session_launch_open_validator.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_landing_team_settings_dialog.dart` (`landingTeamSettingsNeedsAttention`)
- Test: `client/test/services/launch/workspace_landing_launch_gate_test.dart`

- [ ] **Step 1: Rewrite gate tests**

```dart
test('blocks mixed workspace when placement not initialized', () {
  final block = gate.syncBlock(
    workspace: _mixedWorkspace(), // no flag, no targets
    draft: LandingLaunchContext(isPersonal: false, teamId: team.id),
    team: team,
  );
  expect(block, isA<MixedMemberPlacementUninitializedLaunchBlock>());
});

test('allows mixed when initialized even if non-lead has zero replicas', () {
  final team = TeamProfile(
    id: 'team-1',
    name: 'Team',
    members: const [
      TeamMemberConfig(id: 'team-lead', name: 'Lead'),
      TeamMemberConfig(id: 'dev', name: 'Dev', replicas: 0),
    ],
    createdAt: 1,
  );
  final workspace = Workspace(
    workspaceId: 'ws-1',
    folders: [
      const WorkspaceFolder(path: '/a', targetId: 'local'),
      const WorkspaceFolder(path: '/b', targetId: 'ssh:host-a'),
    ],
    createdAt: 1,
    memberTargetsByTeam: {
      team.id: {'team-lead': 'local'},
    },
    memberPlacementInitializedByTeam: {team.id: true},
  );
  expect(
    gate.syncBlock(
      workspace: workspace,
      draft: LandingLaunchContext(isPersonal: false, teamId: team.id),
      team: team,
    ),
    isNull,
  );
});
```

Rename/repurpose `MixedMemberTargetsIncompleteLaunchBlock` → `MixedMemberPlacementUninitializedLaunchBlock` (or keep class name but change semantics — prefer rename + update call sites/l10n).

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement gate**

```dart
if (workspaceNeedsMixedPlacementInit(
      folders: workspace.folders,
      teamId: team.id,
      initializedByTeam: workspace.memberPlacementInitializedByTeam,
    )) {
  return const MixedMemberPlacementUninitializedLaunchBlock();
}
final targets = rememberedMemberTargets(
  workspace.memberTargetsByTeam,
  team.id,
);
if (!leadPlacementValid(
  folders: workspace.folders,
  members: team.members.where((m) => m.isValid).toList(),
  targets: targets,
)) {
  return const LeadPlacementInvalidLaunchBlock(); // new or reuse
}
```

Update `landingTeamSettingsNeedsAttention` the same way.

Replace remaining `workspaceTopologyRequiresMemberAssignment` + `memberTargetsComplete` launch checks in readiness/pipeline/open_validator.

- [ ] **Step 4: Run related tests**

Run: `cd client && flutter test test/services/launch/`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/launch client/lib/pages/home_workspace/workspace/workspace_landing_team_settings_dialog.dart client/test/services/launch
git commit -m "feat: gate mixed launch on placement init and lead host"
```

---

### Task 6: Session create — omit / implicit pin + session-scoped roster

**Files:**
- Modify: `client/lib/repositories/session_repository.dart` (`createSession`, `updateWorkspaceFolders`)
- Modify: `client/lib/cubits/chat/session_launch_service.dart` (member connect scheduling)
- Modify: TeamBus install path that currently uses full `runtimeRosterMembers(team)` (e.g. `TabTeamBusCoordinator.installBusForTab` or its caller) so the bus roster is **session bindings only**
- Test: `client/test/repositories/session_repository_replicas_test.dart`
- Test: `client/test/repositories/session_repository_folders_test.dart` (as needed)
- Test: existing TeamBus / session launch tests that assume full expanded roster — update to session-scoped

- [ ] **Step 1: Write failing tests**

```dart
test('createSession omits mixed instances without targets when initialized', () async {
  // Arrange: mixed workspace, memberPlacementInitializedByTeam[team]=true,
  // memberTargetsByTeam only {'team-lead':'local'},
  // rosterMembers = lead + TeamMemberConfig(id:'dev', replicas:2).
  // Act: createSession(...)
  // Assert: session.members.map((b) => b.rosterMemberId) == ['team-lead']
  //         session.memberTargets.keys == {'team-lead'}
});

test('createSession implicitly pins missing targets on single-host', () async {
  // Arrange: local-only workspace; remembered targets may be empty OR partial
  // (e.g. only lead pinned); roster lead + non-lead with replicas:2.
  // Act: createSession(...)
  // Assert: every expanded instance id is in session.memberTargets → 'local'
  //         (fill gaps; do not omit on single-host).
});

test('createSession empty single-host targets persists default pins', () async {
  // Arrange: local-only, empty memberTargetsByTeam, roster replicas already 1.
  // Act: createSession(...)
  // Assert: workspace.memberTargetsByTeam[team] written with default pins.
  // Pin every expanded instance to the sole host even if profile replicas > 1
  // (do not under-pin to default placement count while expanding N).
});

test('createSession throws when mixed not initialized', () async {
  // Arrange: mixed workspace, initialized flag missing/false.
  // Act/Assert: throws StateError('mixed_workspace_member_placement_uninitialized')
});

test('updateWorkspaceFolders clears init flags when host set changes to mixed', () async {
  // Arrange: workspace was local with initialized[team]=true; update folders to mixed.
  // Assert: memberPlacementInitializedByTeam[team] cleared/false.
});
```

Also add/adjust a test that TeamBus / remaining-member launch iterates **only** `session.members` via `sessionRosterMembers(session, team)` — not full `runtimeRosterMembers(team)`.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement createSession logic**

Replace the old `memberTargetsComplete` throw with:

1. If mixed && needs init → throw `mixed_workspace_member_placement_uninitialized`
2. Expand roster (`replicas <= 0` non-lead → no instances)
3. Resolve targets:
   - **local/remote:**
     - If remembered targets **empty**: build default pins for every **expanded** instance to the sole host, **persist** to `memberTargetsByTeam`.
     - If remembered targets **partial**: for every expanded instance missing a pin, **implicitly pin to the sole host** (do not omit). Persist merged map.
   - **mixed:** never invent pins; use remembered only; omit instances without resolvable folder-backed targets from bindings
4. Filter/omit applies **only for mixed**; single-host must end with every expanded instance pinned
5. If lead missing / lead invalid → throw
6. Set `session.memberTargets` to the final pin map for included members

**Session-scoped roster (required for omit rule):**

- Add `sessionRosterMembers(AppSession session, TeamProfile team)` in `member_instance.dart`: `runtimeRosterMembers(team)` filtered to ids present in `session.members`.
- Update `TabTeamBusCoordinator.installBusForTab` and `SessionLaunchService._launchRemainingMembersForTab` (and `session_member_connect_scheduler` if it re-installs the bus) to use that helper.

In `updateWorkspaceFolders`, after writing new folders, if topology became mixed or `workspaceTargetIds` changed vs previous, clear `memberPlacementInitializedByTeam` entries.

Note: `session_lifecycle_service.dart` still references `workspaceTopologyRequiresMemberAssignment` for connect-time checks — update here or in Task 11 so connect does not re-impose “complete targets” after omit.
- [ ] **Step 4: Run — expect PASS**

Run: `cd client && flutter test test/repositories/session_repository_replicas_test.dart test/repositories/session_repository_folders_test.dart` (+ any TeamBus/launch tests touched)

- [ ] **Step 5: Commit**

```bash
git add client/lib/repositories/session_repository.dart client/lib/cubits/chat/session_launch_service.dart client/lib/services/team_bus client/test/repositories client/test
git commit -m "feat: session create omits unpinned mixed members from bindings and bus"
```

---

### Task 7: Placement panel — unbounded counts + lead locks

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/mixed_workspace_member_placement_panel.dart`
- Create: `client/test/pages/home_workspace/mixed_workspace_member_placement_panel_test.dart` (widget test if feasible; else cover via dialog save tests)

- [ ] **Step 1: Change increment/decrement rules**

- Remove cap `total >= memberTypeReplicaCount(member)`.
- Non-lead: `+` up to practical max `99`; `-` down to `0` on that host.
- Lead: on preferred lead host, count locked at `1` (disable − / ignore −); on other hosts, disable `+`.
- Header: show `placedTotal` only, or `placedTotal` as total (needed == placedTotal). Update `_MemberPlacementRow` so `needed` is not a separate profile cap — pass `placedTotal` for both or change subtitle.

- [ ] **Step 2: Manual/widget verify lead cannot leave preferred host**

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/mixed_workspace_member_placement_panel.dart client/test/pages/home_workspace
git commit -m "feat: placement panel drives unbounded replica counts"
```

---

### Task 8: Landing team settings — always Machines + new save

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_landing_team_settings_dialog.dart`

- [ ] **Step 1: Always include Machines section**

```dart
List<_LandingTeamSettingsSection> get _sections => [
  _LandingTeamSettingsSection.team,
  _LandingTeamSettingsSection.members,
  _LandingTeamSettingsSection.machines, // always
];
```

- [ ] **Step 2: Init placement from remembered or defaults**

When remembered targets empty, `_placement = defaultMemberPlacement(...)` (in-memory only).

If mixed && uninitialized, set initial `_selectedIndex` to Machines pane.

- [ ] **Step 3: Save via shared helper**

```dart
final prepared = prepareMemberPlacementSave(
  team: _teamDraft,
  folders: widget.workspace.folders,
  placement: _placement,
);
if (!prepared.leadValid) return;
_teamDraft = _teamDraft.copyWith(members: prepared.members);
await cubit.updateSelected(_teamDraft);
await sessions.updateWorkspaceMemberPlacement(
  widget.workspace.workspaceId,
  widget.team.id,
  targets: prepared.targets,
); // writes targets + initialized flag together
```

`_canSave` → `!_saving && leadPlacementValid(...)` (not `_isMixed && _placementComplete`).

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_landing_team_settings_dialog.dart
git commit -m "feat: landing team settings always edits machines placement"
```

---

### Task 9: Workspace settings secondary entry — same save path

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/config/workspace_team_member_targets_dialog.dart`
- Modify: `client/lib/pages/home_workspace/workspace/config/workspace_team_member_targets_section.dart`

- [ ] **Step 1: Save must update replicas on team profile**

Dialog currently only writes targets. Change to:

1. `prepareMemberPlacementSave`
2. `LaunchProfileCubit.updateSelected` / team member replicas update (need cubit in dialog — pass it or read from context)
3. Persist via `updateWorkspaceMemberPlacement` (targets + init flag)

Enable save when `leadValid`, not when `memberPlacementComplete`.

Update status chip copy: for mixed uninitialized show “Needs confirmation”; after init show assigned counts without requiring full completeness.

- [ ] **Step 2: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/config/workspace_team_member_targets_dialog.dart client/lib/pages/home_workspace/workspace/config/workspace_team_member_targets_section.dart
git commit -m "feat: workspace member targets dialog uses shared placement save"
```

---

### Task 10: Remove replicas UI from team config + l10n

**Files:**
- Modify: `client/lib/pages/team_config/team_config_member_section.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Regenerate: `app_localizations*.dart` (project’s usual `flutter gen-l10n` / existing workflow)
- Modify tests that look for replicas row if any

- [ ] **Step 1: Remove `_MemberReplicasRow` usage and class**

- [ ] **Step 2: Update strings**

- Replace `mixedWorkspaceMemberAssignmentIncomplete` with first-init copy, e.g.  
  EN: `Confirm machine assignment once before starting this team in a mixed workspace.`  
  ZH: `混合工作区首次启动前，请先确认成员的机器分配。`
- Add lead-invalid string if needed.
- Keep or retire `memberReplicas*` keys (can leave unused ARB keys or delete — prefer delete if unused).

- [ ] **Step 3: Run analyze + focused tests**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/models/member_instance_test.dart test/models/workspace_topology_test.dart test/models/workspace_test.dart test/services/launch/ test/repositories/session_repository_replicas_test.dart`

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/team_config/team_config_member_section.dart client/lib/l10n
git commit -m "refactor: remove member replicas stepper; update placement copy"
```

---

### Task 11: Migration infer on load + cleanup call sites

**Files:**
- Modify: `client/lib/repositories/session_repository.dart` (`_readManifest` / `loadWorkspaces`)
- Grep and update remaining `workspaceTopologyRequiresMemberAssignment` / `memberTargetsComplete` launch uses
- Modify: `client/lib/pages/home_workspace/workspace/mixed_workspace_member_assignment_dialog.dart` if still used at launch — align with init flag or remove auto-prompt path

- [ ] **Step 1: On workspace load**, for each team key in `memberTargetsByTeam`, if mixed and flag missing, set in-memory initialized via `inferMemberPlacementInitialized` (optional write-back on next save).

- [ ] **Step 2: Grep**

```bash
cd client && rg -n "workspaceTopologyRequiresMemberAssignment|memberTargetsComplete|MixedMemberTargetsIncomplete" lib test
```

Fix stragglers.

- [ ] **Step 3: Full non-integration test pass**

Run: `cd client && flutter test --exclude-tags integration`

- [ ] **Step 4: Commit**

```bash
git add client
git commit -m "feat: infer mixed placement init from valid remembered targets"
```

---

## Execution notes

- Prefer extracting pure functions in `workspace_topology.dart` / `member_placement_save.dart` before wiring UI.
- Do not silently persist defaults for **mixed** on launch — only block and open Machines.
- Silent default materialization is **local/remote session create only**: empty maps get default pins persisted; partial maps get missing instances pinned to the sole host (never omit on single-host).
- After ARB edits, regenerate l10n the same way this repo already does (do not hand-edit `app_localizations*.dart` unless that is the project convention — currently those files are checked in; follow existing pattern in recent commits).

## Done when

1. Replicas stepper gone from team member settings.
2. Landing Machines always available; save writes replicas + targets + init flag.
3. Local launch works without opening Machines.
4. Mixed launch blocked until one Machines save (or valid inferred init).
5. `replicas: 0` non-lead members do not appear in session bindings.
6. Lead stays on local when workspace has a local folder.
