# Members panel machine groups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the right-tools Members panel, group roster rows by machine (icon + label) when the team is mixed and the listed members resolve to ≥2 distinct targets.

**Architecture:** Pure `groupMembersByMachine` builds ordered sections from roster + `MemberTargetAssignments`. UI reuses `workspaceFolderTargetLabel` / `workspaceFolderTargetIcon`. Targets resolve as: active session `memberTargets` when present, else `rememberedMemberTargets(workspace.memberTargetsByTeam, teamId)` from `ChatCubit.state.workspaces`.

**Tech Stack:** Flutter/Dart, `flutter_test`, existing workspace topology helpers.

**Spec:** [`2026-07-15-mixed-team-machine-ui-and-teambus-json-design.md`](../specs/2026-07-15-mixed-team-machine-ui-and-teambus-json-design.md) Track A

**Independent of:** TeamBus MCP JSON (Track B) and list-teammates machine install.

---

## File map

| Path | Responsibility |
|------|----------------|
| Create: `client/lib/utils/members_machine_groups.dart` | `MembersMachineGroup`, `groupMembersByMachine`, pin resolve helpers |
| Create: `client/test/utils/members_machine_groups_test.dart` | Pure grouping tests |
| Modify: `client/lib/widgets/right_tools/members_panel.dart` | Render sections when `groups.length >= 2` |
| Modify: `client/lib/widgets/right_tools/right_tools_tool_views.dart` | Resolve `memberTargets`; convert `_ScopedMembersPanel` to **StatefulWidget** to async-load `HomeTargetController.listSelectable()`; pass into `MembersPanel` |

---

### Task 1: Pure grouping helper (TDD)

**Files:**
- Create: `client/lib/utils/members_machine_groups.dart`
- Test: `client/test/utils/members_machine_groups_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/utils/members_machine_groups.dart';
import 'package:teampilot/utils/team_member_naming.dart';

TeamMemberConfig _m(String id, {String name = ''}) => TeamMemberConfig(
  id: id,
  name: name.isEmpty ? id : name,
);

void main() {
  test('single target → one group (caller decides flat UI)', () {
    final members = [_m(TeamMemberNaming.teamLeadName), _m('dev')];
    final groups = groupMembersByMachine(
      members: members,
      memberTargets: {
        TeamMemberNaming.teamLeadName: 'local',
        'dev': 'local',
      },
    );
    expect(groups, hasLength(1));
    expect(groups.single.targetId, 'local');
  });

  test('two targets → lead machine first; lead within group first', () {
    final lead = _m(TeamMemberNaming.teamLeadName);
    final a = _m('a');
    final b = _m('b');
    // roster order: a, lead, b — lead on ssh, a/b on local
    final groups = groupMembersByMachine(
      members: [a, lead, b],
      memberTargets: {
        'a': 'local',
        TeamMemberNaming.teamLeadName: 'ssh:p1',
        'b': 'local',
      },
    );
    expect(groups.map((g) => g.targetId).toList(), ['ssh:p1', 'local']);
    expect(groups.first.members.map((m) => m.id), [TeamMemberNaming.teamLeadName]);
    expect(groups.last.members.map((m) => m.id), ['a', 'b']);
  });

  test('missing pin → local bucket', () {
    final groups = groupMembersByMachine(
      members: [_m('dev'), _m('ops')],
      memberTargets: {'ops': 'ssh:p1'},
    );
    expect(groups.map((g) => g.targetId).toSet(), {'local', 'ssh:p1'});
    expect(
      groups.firstWhere((g) => g.targetId == 'local').members.single.id,
      'dev',
    );
  });

  test('unknown non-empty targetId kept as bucket key', () {
    final groups = groupMembersByMachine(
      members: [_m('dev'), _m('ops')],
      memberTargets: {
        'dev': 'ssh:gone',
        'ops': 'local',
      },
    );
    expect(groups.map((g) => g.targetId).toSet(), {'ssh:gone', 'local'});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/utils/members_machine_groups_test.dart`

Expected: FAIL (library / symbol not found)

- [ ] **Step 3: Minimal implementation**

```dart
import '../models/team_config.dart';
import '../models/workspace_topology.dart';
import 'team_member_naming.dart';

class MembersMachineGroup {
  const MembersMachineGroup({
    required this.targetId,
    required this.members,
  });

  final String targetId;
  final List<TeamMemberConfig> members;
}

/// Resolve pin for grouping: missing/empty → `local`; else trimmed target id.
String resolveMemberMachineTargetId(
  MemberTargetAssignments memberTargets,
  String memberId,
) {
  final raw = memberTargetForInstanceId(memberTargets, memberId);
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty) return 'local';
  return trimmed;
}

/// Groups [members] by resolved target. Group order: lead's machine first,
/// then first-seen target order. Within group: lead first, else roster order.
List<MembersMachineGroup> groupMembersByMachine({
  required List<TeamMemberConfig> members,
  required MemberTargetAssignments memberTargets,
}) {
  final buckets = <String, List<TeamMemberConfig>>{};
  final order = <String>[];
  String? leadTarget;

  for (final m in members) {
    final tid = resolveMemberMachineTargetId(memberTargets, m.id);
    if (TeamMemberNaming.isTeamLead(m)) leadTarget = tid;
    buckets.putIfAbsent(tid, () {
      order.add(tid);
      return <TeamMemberConfig>[];
    }).add(m);
  }

  final sortedKeys = [...order];
  if (leadTarget != null) {
    sortedKeys
      ..remove(leadTarget)
      ..insert(0, leadTarget);
  }

  return [
    for (final tid in sortedKeys)
      MembersMachineGroup(
        targetId: tid,
        members: _leadFirst(buckets[tid]!),
      ),
  ];
}

List<TeamMemberConfig> _leadFirst(List<TeamMemberConfig> list) {
  final lead = list.where(TeamMemberNaming.isTeamLead).toList();
  final rest = list.where((m) => !TeamMemberNaming.isTeamLead(m)).toList();
  return [...lead, ...rest];
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/utils/members_machine_groups_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/utils/members_machine_groups.dart \
  client/test/utils/members_machine_groups_test.dart
git commit -m "feat: add members_machine_groups pure grouping helper"
```

---

### Task 2: Wire targets into MembersPanel + section headers

**Files:**
- Modify: `client/lib/widgets/right_tools/members_panel.dart`
- Modify: `client/lib/widgets/right_tools/right_tools_tool_views.dart`
- Test: extend `client/test/utils/members_machine_groups_test.dart` if needed (optional widget test skipped unless cheap)

- [ ] **Step 1: Resolve targets in `_buildViews` / `_ScopedMembersPanel`**

In `_buildViews` (where `session` / `members` are already known), compute:

```dart
// Spec: session targets when a session is present; else workspace remembered pins.
// If the session exists but memberTargets is empty, fall back to remembered
// (common before pins hydrate) — intentional, not a bug.
final MemberTargetAssignments memberTargets;
if (session != null && session.memberTargets.isNotEmpty) {
  memberTargets = session.memberTargets;
} else {
  final workspace = context
      .read<ChatCubit>()
      .state
      .workspaces
      .where((w) => w.workspaceId == widget.workspaceId)
      .firstOrNull;
  memberTargets = rememberedMemberTargets(
    workspace?.memberTargetsByTeam ?? const {},
    team.id,
  );
}
```

`HomeTargetController.listSelectable()` is **async**. Convert `_ScopedMembersPanel` from `StatelessWidget` → `StatefulWidget` and load targets the same way as `mixed_workspace_member_placement_panel.dart` (`initState` / post-frame → local `List<RuntimeTarget>`; empty until loaded / on missing provider). Pass `memberTargets` + `runtimeTargets` into `MembersPanel`.

Only attempt grouping when `team.teamMode == TeamMode.mixed`.

- [ ] **Step 2: Update `MembersPanel` API**

Add optional params:

```dart
final MemberTargetAssignments memberTargets;
final List<RuntimeTarget> runtimeTargets;
final bool groupByMachine; // true when team.teamMode == TeamMode.mixed
```

Defaults: `memberTargets: const {}`, `runtimeTargets: const []`, `groupByMachine: false`.

Import label/icon helpers from `client/lib/widgets/workspace_folder_directory_row.dart` (`workspaceFolderTargetLabel`, `workspaceFolderTargetIcon`).

- [ ] **Step 3: Render**

```dart
final groups = groupByMachine
    ? groupMembersByMachine(members: members, memberTargets: memberTargets)
    : const <MembersMachineGroup>[];
final useSections = groups.length >= 2;

// ListView children:
// if useSections: for each group → header row + member tiles
// else: flat member tiles (today's builder body extracted to _memberTile)
```

Header row:

```dart
Row(
  children: [
    Icon(workspaceFolderTargetIcon(group.targetId), size: 16, color: cs.onSurfaceVariant),
    const SizedBox(width: 6),
    Expanded(
      child: Text(
        workspaceFolderTargetLabel(runtimeTargets, group.targetId),
        style: styles.xsBoldWideColored(cs.onSurfaceVariant),
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
)
```

No member count in header. Extract existing tile body into a private method to avoid duplication.

- [ ] **Step 4: Manual / analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/widgets/right_tools/members_panel.dart lib/widgets/right_tools/right_tools_tool_views.dart lib/utils/members_machine_groups.dart`

Expected: no errors

- [ ] **Step 5: Commit**

```bash
git add client/lib/widgets/right_tools/members_panel.dart \
  client/lib/widgets/right_tools/right_tools_tool_views.dart
git commit -m "feat: group Members panel by machine when mixed multi-host"
```

---

## Verification

```bash
cd client && flutter test test/utils/members_machine_groups_test.dart
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Manual: open mixed workspace with ≥2 machines assigned → Members tab shows section headers with icons; single-machine mixed stays flat.
