# `list_teammates` machine identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Snapshot each TeamBus member’s machine (`local` / `user@host:port` / `wsl:<distro>`) plus correct per-member `cwd` onto `TeammateRosterProfile` at bus install.

**Architecture:** Pure helper `rosterMachineFromTarget` maps `RuntimeTarget` (+ optional `SshProfile`) → `{machine, machineKind, machineId}`. Fields live on `TeammateRosterProfile`. `TabTeamBusCoordinator.installBusForTab` fills them via ChatCubit-injected `launchWorkTarget` / `memberWorkDirs` / `sshProfileById`.

**MCP emission is out of scope for this plan.** Prose `machine:` lines are superseded; JSON keys (`machine` / `machine_kind` / `machine_id`) are owned by Track B in [`2026-07-15-mixed-team-machine-ui-and-teambus-json-design.md`](../specs/2026-07-15-mixed-team-machine-ui-and-teambus-json-design.md). Do **not** add prose machine lines to `formatTeammate` here.

**Tech Stack:** Flutter/Dart, existing TeamBus + `RuntimeTarget` / `SshProfile`.

**Spec:** `docs/superpowers/specs/2026-07-15-list-teammates-machine-design.md` (install snapshot + profile; output shape superseded by Track B)

---

## File map

| Path | Responsibility |
|------|----------------|
| Create: `client/lib/services/team_bus/roster_machine.dart` | Pure `RosterMachine` + `rosterMachineFromTarget` |
| Modify: `client/lib/services/team_bus/teammate_roster_profile.dart` | Add `machine` / `machineKind` / `machineId`; pass through `fromMember` |
| Modify: `client/lib/cubits/chat/tab_team_bus_coordinator.dart` | Resolve machine + member cwd at install |
| Modify: `client/lib/cubits/chat_cubit.dart` | Inject resolvers into coordinator |
| Create: `client/test/services/team_bus/roster_machine_test.dart` | Helper unit tests |
| Modify: `client/test/services/team_bus/teammate_roster_profile_capabilities_test.dart` | Assert machine fields round-trip via `fromMember` |

**Not in this plan:** `teammate_bus_tool_format.dart`, `list_teammates_tool.dart` description (Track B).

---

### Task 1: `rosterMachineFromTarget` helper (TDD)

**Files:**
- Create: `client/lib/services/team_bus/roster_machine.dart`
- Test: `client/test/services/team_bus/roster_machine_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/team_bus/roster_machine.dart';

void main() {
  test('local → machine/id/kind all local', () {
    final m = rosterMachineFromTarget(RuntimeTarget.local());
    expect(m.machine, 'local');
    expect(m.machineId, 'local');
    expect(m.machineKind, 'local');
  });

  test('ssh with profile → hostIdentifier', () {
    final target = RuntimeTarget.ssh('p1', label: 'unused');
    final profile = SshProfile(
      id: 'p1',
      name: 'dev',
      host: 'localhost',
      username: 'root',
      port: 22,
    );
    final m = rosterMachineFromTarget(target, profile: profile);
    expect(m.machine, 'root@localhost:22');
    expect(m.machineId, 'ssh:p1');
    expect(m.machineKind, 'ssh');
  });

  test('ssh without profile → fall back to target.id', () {
    final m = rosterMachineFromTarget(RuntimeTarget.ssh('p1', label: ''));
    expect(m.machine, 'ssh:p1');
    expect(m.machineId, 'ssh:p1');
    expect(m.machineKind, 'ssh');
  });

  test('wsl → machine equals machineId', () {
    final m = rosterMachineFromTarget(RuntimeTarget.wsl('Ubuntu'));
    expect(m.machine, 'wsl:Ubuntu');
    expect(m.machineId, 'wsl:Ubuntu');
    expect(m.machineKind, 'wsl');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && flutter test test/services/team_bus/roster_machine_test.dart`

Expected: FAIL (library not found / undefined)

- [ ] **Step 3: Implement helper**

```dart
import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';

class RosterMachine {
  const RosterMachine({
    required this.machine,
    required this.machineKind,
    required this.machineId,
  });

  final String machine;
  final String machineKind;
  final String machineId;
}

RosterMachine rosterMachineFromTarget(
  RuntimeTarget target, {
  SshProfile? profile,
}) {
  final kind = target.kind.name;
  final id = target.id;
  final machine = switch (target.kind) {
    RuntimeKind.local => 'local',
    RuntimeKind.wsl => id,
    RuntimeKind.ssh =>
      (profile != null && profile.hostIdentifier.trim().isNotEmpty)
          ? profile.hostIdentifier
          : id,
  };
  return RosterMachine(machine: machine, machineKind: kind, machineId: id);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && flutter test test/services/team_bus/roster_machine_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team_bus/roster_machine.dart \
  client/test/services/team_bus/roster_machine_test.dart
git commit -m "$(cat <<'EOF'
feat(team-bus): add rosterMachineFromTarget helper

EOF
)"
```

---

### Task 2: Profile fields (TDD) — no MCP format change

**Files:**
- Modify: `client/lib/services/team_bus/teammate_roster_profile.dart`
- Modify: `client/test/services/team_bus/teammate_roster_profile_capabilities_test.dart`

**Do not** touch `teammate_bus_tool_format.dart` or `list_teammates_tool.dart` in this task.

- [ ] **Step 1: Write the failing round-trip test**

Add to `teammate_roster_profile_capabilities_test.dart`:

```dart
test('fromMember stores machine fields', () {
  final p = TeammateRosterProfile.fromMember(
    member: const TeamMemberConfig(id: 'dev', name: 'Dev'),
    team: team(),
    cliTeamName: 'team-1-1',
    cwd: '/work',
    machine: 'local',
    machineKind: 'local',
    machineId: 'local',
  );
  expect(p.machine, 'local');
  expect(p.machineKind, 'local');
  expect(p.machineId, 'local');
  expect(p.cwd, '/work');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/team_bus/teammate_roster_profile_capabilities_test.dart`

Expected: FAIL (unknown named args `machine` / `machineKind` / `machineId`)

- [ ] **Step 3: Implement profile fields**

1. Add to `TeammateRosterProfile` constructor + fields (defaults `''`):

```dart
this.machine = '',
this.machineKind = '',
this.machineId = '',
```

2. `fromMember` optional params (same names) and pass them into the returned profile.

`minimal` leaves them empty (Track B omits JSON keys when `machineId` empty).

- [ ] **Step 4: Run test to verify it passes**

Run same command as Step 2. Expected: PASS

Also: `cd client && flutter test test/services/team_bus/` — existing tests must still PASS.

- [ ] **Step 5: Commit**

```bash
git add \
  client/lib/services/team_bus/teammate_roster_profile.dart \
  client/test/services/team_bus/teammate_roster_profile_capabilities_test.dart
git commit -m "$(cat <<'EOF'
feat(team-bus): add machine fields to TeammateRosterProfile

EOF
)"
```

---

### Task 3: Wire installBusForTab + ChatCubit

**Files:**
- Modify: `client/lib/cubits/chat/tab_team_bus_coordinator.dart`
- Modify: `client/lib/cubits/chat_cubit.dart` (constructor of `_teamBus`)

Prefer keeping this task focused on wiring (helper + profile already unit-tested).

- [ ] **Step 1: Extend `TabTeamBusCoordinator` constructor**

Add required callbacks:

```dart
required RuntimeTarget Function(AppSession session, {String? memberId})
    launchWorkTarget,
required ({String workingDirectory, List<String> addDirs}) Function(
  AppSession session,
  String memberId,
) memberWorkDirs,
SshProfile? Function(String profileId)? sshProfileById,
```

Prefer `SshProfile? Function(String profileId)?` (not the chat typedef) so the coordinator does not import chat model typedefs.

Store as `_launchWorkTarget`, `_memberWorkDirs`, `_sshProfileById`.

Import: `roster_machine.dart`, `runtime_target.dart`, `ssh_profile.dart`.

- [ ] **Step 2: Fill machine + cwd in `installBusForTab` loop**

Replace `cwd: session.firstFolderPath` with:

```dart
final target = _launchWorkTarget(session, memberId: m.id);
final profileId = target.sshProfileId ?? sshProfileIdOfId(target.id);
final ssh = (profileId != null && profileId.isNotEmpty)
    ? _sshProfileById?.call(profileId)
    : null;
final rosterMachine = rosterMachineFromTarget(target, profile: ssh);
final work = _memberWorkDirs(session, m.id);

bus.declareMember(
  AgentNode(
    profile: TeammateRosterProfile.fromMember(
      member: m,
      team: team,
      cliTeamName: cliTeamName,
      cwd: work.workingDirectory,
      taskId: taskId,
      globalPresets: presets,
      machine: rosterMachine.machine,
      machineKind: rosterMachine.machineKind,
      machineId: rosterMachine.machineId,
    ),
    lifecycle: MemberLifecycle.declared,
  ),
);
```

Leave `TeamSessionContext.workingDirectory: session.firstFolderPath` unchanged (spec).

- [ ] **Step 3: Wire from `ChatCubit`**

`ChatCubit` does **not** store `_sshProfileById` itself — the constructor arg is only passed into `ChatSessionShellFactory`. Use `_shellFactory.profileById` (method already exists on the shell factory).

`_launchService` is declared before `_teamBus` (~147 then ~170), so reuse launch context:

```dart
launchWorkTarget: (session, {String? memberId}) =>
    _lifecycle.launchWorkTarget(
      _launchService.launchContextFor(session),
      memberId: memberId,
    ),
memberWorkDirs: (session, memberId) =>
    _lifecycle.memberWorkDirs(
      _launchService.launchContextFor(session),
      memberId,
    ),
sshProfileById: _shellFactory.profileById,
```

- [ ] **Step 4: Grep for other `TabTeamBusCoordinator(` call sites**

Today only `chat_cubit.dart` constructs it (no test fakes). Re-grep anyway; update any new call sites with the required callbacks.

- [ ] **Step 5: Analyze + focused tests**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/services/team_bus/roster_machine.dart \
  lib/services/team_bus/teammate_roster_profile.dart \
  lib/cubits/chat/tab_team_bus_coordinator.dart \
  lib/cubits/chat_cubit.dart

cd client && flutter test test/services/team_bus/
```

Expected: no errors; tests PASS

- [ ] **Step 6: Commit**

```bash
git add \
  client/lib/cubits/chat/tab_team_bus_coordinator.dart \
  client/lib/cubits/chat_cubit.dart
git commit -m "$(cat <<'EOF'
feat(team-bus): snapshot member machine and cwd at bus install

EOF
)"
```

---

### Task 4: Verification

- [ ] **Step 1: Full unit suite (non-integration)**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  && flutter test --exclude-tags integration
```

Expected: PASS (or only pre-existing failures unrelated to this change — do not claim green if new failures appear)

- [ ] **Step 2: Note Track B dependency**

Machine fields are on the profile after this plan, but agents will not see them in MCP until Track B converts `encodeRoster` to JSON and emits `machine` / `machine_kind` / `machine_id`. Do not manually smoke `list_teammates` prose for machine lines.

- [ ] **Step 3: No further commit required** unless verification found fixes.

---

## Done when

- `TeammateRosterProfile` carries `machine` / `machineKind` / `machineId`
- `installBusForTab` fills them via `rosterMachineFromTarget` + SSH profile lookup
- Member `cwd` comes from `memberWorkDirs` (not `session.firstFolderPath`)
- Team header cwd unchanged
- Helper + profile unit tests green; team_bus suite green
- MCP JSON emission deferred to Track B (not implemented here)
