# Android ACP Full Enablement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Subagent-driven execution is not available in this session.

**Goal:** Unify every ACP availability decision behind one platform-independent, target-aware policy and enable full ACP on Android, including remote team bus, Antigravity remote install, and Antigravity remote OAuth login.

**Architecture:** `launch_acp_policy.dart` becomes the only source of truth. All session, team, landing, settings, and automation call sites delegate to it. Android platform gates are removed. Remote mixed-team ACP reuses the PTY path's `RemoteMemberBusSetup`. Antigravity gains SSH CLI/adapter installers and a remote PTY login dialog.

**Tech Stack:** Flutter/Dart, `flutter_bloc`, `dartssh2`, `acpd`, existing `CliToolRegistry` capabilities, `RemoteCliReadinessService`, `SshMemberSession`, `TerminalEngine`.

## Global Constraints

- Never invoke `flutter test` directly. Use `cd client && dart run tool/run_tests.dart <paths/options>`.
- Inner loop is `cd client && flutter analyze`; verify with one test file; full suite only once before claiming done.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- l10n edits go in `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb` only.
- Diagnostics use `AppLogger`; never `print`.
- Workspace/app data paths come from injected `HomeStorage` / `RuntimeContextRegistry`; never `Directory.current`.
- Member placement uses `sessionRosterMembers(session, team)`.
- Keep `services/chat/` directory rules: lifecycle stages or named features; ports live in the owning feature.
- Tests that need a home plane use `setUpTestAppStorage()` / `tearDownTestAppStorage()` from `client/test/support/post_frame_test_harness.dart`.
- Commit after each task.

---

### Task 1: Add the unified ACP policy

**Files:**
- Create: `client/test/services/chat/launch/session/launch_acp_policy_test.dart`
- Modify: `client/lib/services/chat/launch/session/launch_acp_policy.dart`

**Interfaces:**
- Produces: `enum AcpAvailability { unsupported, optional, forced }`
- Produces: `AcpAvailability acpAvailabilityFor({required CliTool? cli, required String targetId})`
- Produces: `bool resolveAcpOnTarget({required CliTool? cli, required String targetId, required bool requested})`
- Produces: `bool canChooseAcpTransport({required CliTool? cli, required String targetId})`
- Produces: `bool acpForcedByCli(CliTool? cli)`

- [ ] **Step 1: Write the failing test**

Create `client/test/services/chat/launch/session/launch_acp_policy_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/session/launch_acp_policy.dart';

void main() {
  test('dual-transport CLI follows requested on local/ssh/termux', () {
    for (final target in ['local', 'ssh:box', 'termux:default']) {
      expect(
        resolveAcpOnTarget(
          cli: CliTool.claude,
          targetId: target,
          requested: true,
        ),
        isTrue,
        reason: target,
      );
      expect(
        resolveAcpOnTarget(
          cli: CliTool.claude,
          targetId: target,
          requested: false,
        ),
        isFalse,
        reason: target,
      );
    }
  });

  test('ACP-only CLIs are forced when the target supports ACP', () {
    for (final cli in [
      CliTool.gemini,
      CliTool.codebuddy,
      CliTool.qoder,
      CliTool.antigravity,
    ]) {
      expect(
        resolveAcpOnTarget(cli: cli, targetId: 'ssh:box', requested: false),
        isTrue,
        reason: cli.value,
      );
      expect(
        acpAvailabilityFor(cli: cli, targetId: 'ssh:box'),
        AcpAvailability.forced,
        reason: cli.value,
      );
    }
  });

  test('WSL has no exec channel', () {
    expect(
      acpAvailabilityFor(cli: CliTool.gemini, targetId: 'wsl:Ubuntu'),
      AcpAvailability.unsupported,
    );
    expect(
      resolveAcpOnTarget(
        cli: CliTool.claude,
        targetId: 'wsl:Ubuntu',
        requested: true,
      ),
      isFalse,
    );
  });

  test('CLI without ACP is unsupported', () {
    expect(
      resolveAcpOnTarget(
        cli: CliTool.flashskyai,
        targetId: 'local',
        requested: true,
      ),
      isFalse,
    );
    expect(
      resolveAcpOnTarget(cli: null, targetId: 'local', requested: true),
      isFalse,
    );
  });

  test('canChooseAcpTransport is true only for optional', () {
    expect(
      canChooseAcpTransport(cli: CliTool.claude, targetId: 'ssh:box'),
      isTrue,
    );
    expect(
      canChooseAcpTransport(cli: CliTool.gemini, targetId: 'ssh:box'),
      isFalse,
    );
    expect(
      canChooseAcpTransport(cli: CliTool.claude, targetId: 'wsl:Ubuntu'),
      isFalse,
    );
  });

  test('acpForcedByCli is capability-only', () {
    expect(acpForcedByCli(CliTool.gemini), isTrue);
    expect(acpForcedByCli(CliTool.antigravity), isTrue);
    expect(acpForcedByCli(CliTool.claude), isFalse);
    expect(acpForcedByCli(null), isFalse);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/session/launch_acp_policy_test.dart`
Expected: FAIL because `AcpAvailability`, `acpAvailabilityFor`, `resolveAcpOnTarget`, `canChooseAcpTransport`, and `acpForcedByCli` are not defined.

- [ ] **Step 3: Implement the policy**

In `client/lib/services/chat/launch/session/launch_acp_policy.dart`, add these declarations below the existing imports (keep the existing `resolveLaunchAcp` for now so other call sites still compile):

```dart
enum AcpAvailability { unsupported, optional, forced }

/// Capability-only check used by `AppSession` construction fallbacks.
bool acpForcedByCli(CliTool? cli) =>
    CliToolRegistry.builtIn().launchesAcpOnly(cli);

/// Whether ACP can run for [cli] on [targetId], ignoring user preference.
AcpAvailability acpAvailabilityFor({
  required CliTool? cli,
  required String targetId,
}) {
  if (cli == null) return AcpAvailability.unsupported;
  final registry = CliToolRegistry.builtIn();
  if (registry.capability<AcpCapability>(cli) == null) {
    return AcpAvailability.unsupported;
  }
  final kind = runtimeKindOfId(targetId);
  if (kind != RuntimeKind.local && !usesSshTransport(kind)) {
    return AcpAvailability.unsupported;
  }
  if (registry.launchesAcpOnly(cli)) return AcpAvailability.forced;
  final canChoose =
      registry
          .capability<CliTransportCapability>(cli)
          ?.canChooseTransport ??
      false;
  return canChoose ? AcpAvailability.optional : AcpAvailability.unsupported;
}

/// Final ACP flag for one personal session or team seat.
bool resolveAcpOnTarget({
  required CliTool? cli,
  required String targetId,
  required bool requested,
}) {
  return switch (acpAvailabilityFor(cli: cli, targetId: targetId)) {
    AcpAvailability.unsupported => false,
    AcpAvailability.forced => true,
    AcpAvailability.optional => requested,
  };
}

/// True when the user can choose PTY vs ACP for this CLI on this target.
bool canChooseAcpTransport({
  required CliTool? cli,
  required String targetId,
}) =>
    acpAvailabilityFor(cli: cli, targetId: targetId) ==
    AcpAvailability.optional;
```

Add the missing imports:

```dart
import '../../../../models/runtime_target.dart';
import '../../../cli/registry/capabilities/acp_capability.dart';
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/session/launch_acp_policy_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/chat/launch/session/launch_acp_policy.dart client/test/services/chat/launch/session/launch_acp_policy_test.dart
git commit -m "feat(acp): add unified target-aware launch policy"
```

---

### Task 2: Rename the local-only marker to no-PTY fallback

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/acp_capability.dart`
- Modify: `client/lib/services/cli/antigravity/capabilities/acp.dart`
- Modify: `client/lib/services/chat/launch/session_launch_service.dart`
- Modify: `client/lib/repositories/session_repository.dart`
- Modify: `client/lib/services/chat/launch/session/session_provisional_builder.dart`
- Modify: `client/lib/services/chat/launch/session/member_acp_stamp.dart`
- Modify: `client/lib/pages/home_workspace/workspace/acp_compose_permission.dart`

**Interfaces:**
- Produces: `abstract interface class AcpNoPtyFallbackCapability implements CliCapability {}`
- Consumes: existing `AcpCapability` marker pattern.

- [ ] **Step 1: Rename the marker**

In `client/lib/services/cli/registry/capabilities/acp_capability.dart`, replace:

```dart
/// Marker for an ACP agent whose adapter is local-only (no remote install).
/// Mixed seats on SSH/Termux targets stay on PTY instead of starting a broken
/// ACP session.
abstract interface class AcpLocalOnlyCapability implements CliCapability {}
```

with:

```dart
/// Marker for an ACP agent that has no useful PTY fallback when ACP attach
/// fails. Gemini/CodeBuddy/Qoder historically fall through to PTY; Antigravity
/// does not.
abstract interface class AcpNoPtyFallbackCapability implements CliCapability {}
```

- [ ] **Step 2: Update every production reference**

Run:

```bash
cd client && grep -rn "AcpLocalOnlyCapability" lib
```

Replace every occurrence with `AcpNoPtyFallbackCapability`. Keep the surrounding logic unchanged in this task so the tree still compiles and existing tests keep passing. In `client/lib/services/cli/antigravity/capabilities/acp.dart`, the class declaration becomes:

```dart
final class AntigravityAcpCapability
    implements AcpCapability, AcpNoPtyFallbackCapability, AcpUsageLogCapability {
```

- [ ] **Step 3: Run the affected tests**

Run:

```bash
cd client && dart run tool/run_tests.dart test/services/chat/launch/session/antigravity_acp_gate_test.dart test/services/chat/launch/session/qoder_member_acp_stamp_test.dart
```

Expected: PASS with the old target gating behavior still in place.

- [ ] **Step 4: Commit**

```bash
git add client/lib
git commit -m "refactor(acp): rename local-only marker to no-PTY fallback"
```

---

### Task 3: Route session creation through the unified policy

**Files:**
- Modify: `client/lib/repositories/session_repository.dart`
- Modify: `client/lib/services/chat/launch/session/session_provisional_builder.dart`
- Modify: `client/lib/models/app_session.dart`
- Test: `client/test/repositories/session_repository_acp_test.dart`
- Test: `client/test/services/chat/launch/session/antigravity_acp_gate_test.dart`

**Interfaces:**
- Consumes: `resolveAcpOnTarget` from Task 1.
- Consumes: `acpForcedByCli` from Task 1.
- Produces: `createSession` persists ACP based on `primaryTargetId`.
- Produces: `buildProvisionalSession` persists ACP based on its resolved folders.

- [ ] **Step 1: Extend the repository test**

In `client/test/repositories/session_repository_acp_test.dart`, add:

```dart
test('personal Claude requested ACP persists true on desktop', () async {
  final session = (await repo.createSession(
    workspaceId,
    cli: CliTool.claude,
    acp: true,
  )).session;
  expect(session.acp, isTrue);
});

test('personal Claude without ACP preference persists false', () async {
  final session = (await repo.createSession(
    workspaceId,
    cli: CliTool.claude,
    acp: false,
  )).session;
  expect(session.acp, isFalse);
});
```

- [ ] **Step 2: Run the tests to verify the new cases fail or are inconclusive**

Run: `cd client && dart run tool/run_tests.dart test/repositories/session_repository_acp_test.dart`
Expected: The two new cases may pass only because the old code also honors `acp: true`; continue to Step 3, which must preserve them while replacing the inference logic.

- [ ] **Step 3: Replace repository inference**

In `client/lib/repositories/session_repository.dart`, replace:

```dart
final registry = CliToolRegistry.builtIn();
final localOnly =
    cli != null &&
    registry.capability<AcpLocalOnlyCapability>(cli) != null;
final primaryTargetId = workspace.folders.isEmpty
    ? WorkspaceFolder.localTargetId
    : workspace.folders.first.targetId;
final targetLocal =
    runtimeKindOfId(primaryTargetId) == RuntimeKind.local;
final resolvedAcp =
    trimmedTeam.isEmpty &&
    (acp ||
        (registry.launchesAcpOnly(cli) &&
            (!localOnly || targetLocal)));
```

with:

```dart
final primaryTargetId = workspace.folders.isEmpty
    ? WorkspaceFolder.localTargetId
    : workspace.folders.first.targetId;
final resolvedAcp =
    trimmedTeam.isEmpty &&
    resolveAcpOnTarget(
      cli: cli,
      targetId: primaryTargetId,
      requested: acp,
    );
```

Add the import:

```dart
import '../services/chat/launch/session/launch_acp_policy.dart';
```

Remove now-unused imports (`runtime_target.dart`, `acp_capability.dart`) only if `dart analyze` reports them unused.

- [ ] **Step 4: Replace provisional-session inference**

In `client/lib/services/chat/launch/session/session_provisional_builder.dart`, replace:

```dart
final registry = CliToolRegistry.builtIn();
final launchCli = identity?.cli ?? cli;
final localOnly =
    launchCli != null &&
    registry.capability<AcpLocalOnlyCapability>(launchCli) != null;
final targetLocal = home == null || home.kind == RuntimeKind.local;
final resolvedAcp =
    trimmedTeam.isEmpty &&
    isPersonal &&
    ((acp ?? false) ||
        (registry.launchesAcpOnly(launchCli) &&
            (!localOnly || targetLocal)));
```

with:

```dart
final launchCli = identity?.cli ?? cli;
final targetId = folders.isEmpty
    ? WorkspaceFolder.localTargetId
    : folders.first.targetId;
final resolvedAcp =
    trimmedTeam.isEmpty &&
    isPersonal &&
    resolveAcpOnTarget(
      cli: launchCli,
      targetId: targetId,
      requested: acp ?? false,
    );
```

Add the import:

```dart
import 'launch_acp_policy.dart';
```

Add `WorkspaceFolder` import if not already present:

```dart
import '../../../../models/workspace_folder.dart';
```

- [ ] **Step 5: Update `AppSession` constructor inference**

In `client/lib/models/app_session.dart`, replace:

```dart
final resolvedAcp =
    acp ??
    (trimmedTeam.isEmpty &&
        CliToolRegistry.builtIn().launchesAcpOnly(cli));
```

with:

```dart
final resolvedAcp =
    acp ?? (trimmedTeam.isEmpty && acpForcedByCli(cli));
```

Add the import:

```dart
import '../services/chat/launch/session/launch_acp_policy.dart';
```

Remove the now-unused `cli_tool_registry.dart` import if analysis reports it unused.

- [ ] **Step 6: Run the tests**

Run:

```bash
cd client && dart run tool/run_tests.dart test/repositories/session_repository_acp_test.dart test/services/chat/launch/session/antigravity_acp_gate_test.dart
```

Expected: PASS. `antigravity_acp_gate_test` may need `home`/folder target updates; if it fails because `buildProvisionalSession` now uses `home == null` as local, update the test workspace folder to `targetId: 'local'` and pass `home: RuntimeTarget.local()`.

- [ ] **Step 7: Commit**

```bash
git add client/lib client/test
git commit -m "feat(acp): resolve personal ACP from the target policy"
```

---

### Task 4: Route team seats and readiness through the unified policy

**Files:**
- Modify: `client/lib/services/chat/launch/session/member_acp_stamp.dart`
- Modify: `client/lib/services/chat/launch/pre_send/local_binary_requirements.dart`
- Modify: `client/lib/services/remote/remote_cli_requirements.dart`
- Modify: `client/lib/services/chat/launch/pre_send/workspace_landing_launch_gate.dart`
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart`
- Test: `client/test/services/chat/launch/session/qoder_member_acp_stamp_test.dart`
- Test: `client/test/services/chat/launch/session/antigravity_acp_gate_test.dart`
- Test: `client/test/services/chat/launch/pre_send/workspace_landing_launch_gate_test.dart`

**Interfaces:**
- Consumes: `acpAvailabilityFor`, `resolveAcpOnTarget`.
- Produces: `remoteCliRequirementsForPlacement(..., MemberAcpSeed? acpSeed)`.
- Produces: `WorkspaceLandingLaunchGate(..., MemberAcpSeed? memberAcpSeed)`.

- [ ] **Step 1: Write the failing tests**

In `client/test/services/chat/launch/session/qoder_member_acp_stamp_test.dart` replace the Android expectation with:

```dart
test('remote qoder seat stamps ACP on SSH', () {
  final stamped = stampMemberAcp(
    members: [member('qoder')],
    memberTargets: const {'qoder': 'ssh:box'},
    seedClaudeMemberAcp: false,
    seedCodexMemberAcp: false,
  );
  expect(stamped.single.acp, isTrue);
});

test('qoder seat stays off on WSL', () {
  final stamped = stampMemberAcp(
    members: [member('qoder')],
    memberTargets: const {'qoder': 'wsl:Ubuntu'},
    seedClaudeMemberAcp: false,
    seedCodexMemberAcp: false,
  );
  expect(stamped.single.acp, isFalse);
});
```

Add a remote adapter requirement test to `workspace_landing_launch_gate_test.dart`:

```dart
test('remote mixed team adds adapter requirements for ACP seats', () {
  final requirements = remoteCliRequirementsForPlacement(
    workspace: workspace,
    team: team,
    placement: const {
      'ssh:box': {'lead': 1},
    },
    globalPresets: const [],
    selectableTargets: [
      RuntimeTarget.ssh('box', label: 'Box'),
    ],
    acpSeed: (cli) => cli == CliTool.claude,
  );
  expect(
    requirements.where((r) => r.kind == CliBinaryKind.adapter),
    isNotEmpty,
  );
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/session/qoder_member_acp_stamp_test.dart test/services/chat/launch/pre_send/workspace_landing_launch_gate_test.dart`
Expected: FAIL because the Android gate still returns false and `acpSeed` does not exist.

- [ ] **Step 3: Replace team-seat gating**

In `client/lib/services/chat/launch/session/member_acp_stamp.dart`, replace the Android helper and gates with:

```dart
bool _memberAcpSupported({required String targetId, required CliTool? cli}) =>
    acpAvailabilityFor(cli: cli, targetId: targetId) !=
    AcpAvailability.unsupported;

bool resolveMemberBindingAcp({
  required String targetId,
  required CliTool? cli,
  required bool requested,
}) {
  if (!_memberAcpSupported(targetId: targetId, cli: cli)) return false;
  return resolveAcpOnTarget(
    cli: cli,
    targetId: targetId,
    requested: requested,
  );
}
```

Delete `_isAndroid` and every `isAndroidOverride` parameter. Update `stampMemberAcp` and `shouldAttachMemberAcp` to the same signatures. `shouldAttachMemberAcp` becomes:

```dart
bool shouldAttachMemberAcp({
  required AppSession session,
  required String memberId,
  required String targetId,
}) {
  if (!isAcpChatSeat(session, memberId)) return false;
  final cli = session.bindingFor(memberId)?.cli;
  return _memberAcpSupported(targetId: targetId, cli: cli);
}
```

- [ ] **Step 4: Update local and remote requirements**

In `client/lib/services/chat/launch/pre_send/local_binary_requirements.dart`:

- Remove `isAndroidOverride` from `localBinaryRequirementsForPlacement`.
- Replace the member ACP call with:

```dart
final memberAcp = resolveAcpOnTarget(
  cli: cli,
  targetId: target.id,
  requested: acpSeed?.call(cli) ?? false,
);
```

In `client/lib/services/remote/remote_cli_requirements.dart`:

- Add `MemberAcpSeed? acpSeed` to `remoteCliRequirementsForPlacement`.
- Inside the member loop, compute:

```dart
final memberAcp = resolveAcpOnTarget(
  cli: cli,
  targetId: targetId,
  requested: acpSeed?.call(cli) ?? false,
);
```

- After adding the CLI requirement, add:

```dart
if (memberAcp && cliUsesSeparateAcpAdapter(cli)) {
  final adapter = RemoteCliRequirement(
    target: target,
    cli: cli,
    hostLabel: target.label.trim().isNotEmpty ? target.label : target.id,
    kind: CliBinaryKind.adapter,
  );
  out.putIfAbsent(adapter.cacheKey, () => adapter);
}
```

Move `typedef MemberAcpSeed = bool Function(CliTool cli);` from `local_binary_requirements.dart` to `launch_acp_policy.dart`. Both `local_binary_requirements.dart` and `remote_cli_requirements.dart` import the policy file, avoiding a circular import. Remove the old typedef from `local_binary_requirements.dart` and update its imports.

- [ ] **Step 5: Update the landing gate**

In `client/lib/services/chat/launch/pre_send/workspace_landing_launch_gate.dart`:

- Rename the constructor parameter and field `localMemberAcpSeed` to `memberAcpSeed`.
- In `localBlock`, replace `_localMemberAcpSeed` with `_memberAcpSeed`.
- In `asyncRemoteCliBlock`, pass `acpSeed: _memberAcpSeed` to `remoteCliRequirementsForPlacement`.
- In `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart`, rename the argument at the `WorkspaceLandingLaunchGate` construction to `memberAcpSeed: (cli) => readAcpDefault(context, cli)`.

- [ ] **Step 6: Run the tests**

Run:

```bash
cd client && dart run tool/run_tests.dart test/services/chat/launch/session/qoder_member_acp_stamp_test.dart test/services/chat/launch/session/antigravity_acp_gate_test.dart test/services/chat/launch/pre_send/workspace_landing_launch_gate_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib client/test
git commit -m "feat(acp): resolve team seats and readiness from the target policy"
```

---

### Task 5: Route landing UI, actions, and automation through the policy

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/acp_compose_permission.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`
- Modify: `client/lib/services/automation/automation_dispatcher.dart`
- Test: `client/test/pages/home_workspace/workspace/acp_compose_permission_test.dart`
- Test: `client/test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart`

**Interfaces:**
- Consumes: `resolveAcpOnTarget`.
- Produces: `willLaunchAcp({required CliTool? cli, required bool requested, required String targetId})`.
- Produces: `showLandingAcpPermissionChip(..., required String targetId, ...)`.

- [ ] **Step 1: Update the tests**

In `client/test/pages/home_workspace/workspace/acp_compose_permission_test.dart`:

- Remove every `isAndroidOverride` argument.
- Replace the Android cases with remote-target cases:

```dart
expect(
  willLaunchAcp(
    cli: CliTool.codebuddy,
    requested: false,
    targetId: 'ssh:box',
  ),
  isTrue,
  reason: 'CodeBuddy is ACP-only on remote targets',
);
expect(
  willLaunchAcp(
    cli: CliTool.qoder,
    requested: true,
    targetId: 'ssh:box',
  ),
  isTrue,
);
expect(
  willLaunchAcp(
    cli: CliTool.claude,
    requested: true,
    targetId: 'ssh:box',
  ),
  isTrue,
);
expect(
  willLaunchAcp(
    cli: CliTool.claude,
    requested: true,
    targetId: 'wsl:Ubuntu',
  ),
  isFalse,
);
```

For `showLandingAcpPermissionChip`, pass `targetId: 'ssh:box'` and assert true for Gemini/Claude, false for an ACP-less CLI.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/acp_compose_permission_test.dart`
Expected: FAIL because the functions still require `isAndroidOverride` and still use the Android gate.

- [ ] **Step 3: Replace the landing gate**

In `client/lib/pages/home_workspace/workspace/acp_compose_permission.dart`:

- Delete `_isAndroid`.
- Replace `willLaunchAcp` with:

```dart
bool willLaunchAcp({
  required CliTool? cli,
  required bool requested,
  required String targetId,
}) =>
    resolveAcpOnTarget(
      cli: cli,
      targetId: targetId,
      requested: requested,
    );
```

- `showLandingAcpPermissionChip` becomes:

```dart
bool showLandingAcpPermissionChip({
  required bool isPersonal,
  required CliTool? cli,
  required bool requested,
  required String targetId,
  List<SessionMemberBinding> stampedMembers = const [],
}) {
  if (isPersonal) {
    return willLaunchAcp(
      cli: cli,
      requested: requested,
      targetId: targetId,
    );
  }
  return stampedMembers.any((member) => member.acp);
}
```

- Remove `isAndroidOverride` from `stampedLandingMembers`, `buildLandingAcpComposePermissionControl`, and `landingAcpPermissionControl`. Pass `targetId` through to `willLaunchAcp`/`showLandingAcpPermissionChip`.
- `landingAcpPermissionControl` already receives `targetId`; make it required and forward it.

- [ ] **Step 4: Stop pre-resolving ACP in actions**

In `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`:

- Remove `isAndroidOverride` from `buildWorkspaceConversationCreateRequest`.
- Replace `acp: resolveLaunchAcp(...)` with:

```dart
acp: acp,
```

- Update the doc comment: `acp` is the requested preference; `SessionRepository` resolves it against the target.

In `client/lib/services/automation/automation_dispatcher.dart`, replace:

```dart
final acp = resolveLaunchAcp(
  cli: simpleIdentity.cli,
  requested: _acpDefaultFor(simpleIdentity.cli),
);
```

with:

```dart
final acp = _acpDefaultFor(simpleIdentity.cli);
```

Remove the now-unused import of `launch_acp_policy.dart`.

- [ ] **Step 5: Run the tests**

Run:

```bash
cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/acp_compose_permission_test.dart test/pages/home_workspace/workspace/claude_acp_launch_switch_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib client/test
git commit -m "feat(acp): make landing and automation use the target policy"
```

---

### Task 6: Enable ACP controls in Android settings

**Files:**
- Modify: `client/lib/pages/config/cli_readiness_card.dart`
- Modify: `client/lib/pages/config/cli_config_section.dart`
- Test: `client/test/pages/config/cli_config_section_test.dart`

**Interfaces:**
- Consumes: existing `CliTransportCapability.canChooseTransport`.
- Produces: `CliReadinessCard` no longer accepts `isAndroidOverride`.

- [ ] **Step 1: Update the test**

In `client/test/pages/config/cli_config_section_test.dart`:

- Remove the `isAndroidOverride` helper argument and every call-site argument.
- Assert the transport pill is present for a dual-transport CLI:

```dart
expect(
  find.byKey(AppKeys.personalAcpSwitchFor(CliTool.claude)),
  findsOneWidget,
);
```

- Assert the ACP adapter row is enabled for Claude:

```dart
final row = tester.widget<CliReadinessPathRow>(
  find.byKey(AppKeys.acpAdapterPathFieldFor(CliTool.claude)),
);
expect(row.enabled, isTrue);
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart`
Expected: FAIL because `isAndroidOverride` is still required by the widget.

- [ ] **Step 3: Remove the Android gates**

In `client/lib/pages/config/cli_readiness_card.dart`:

- Delete `isAndroidOverride` from the widget constructor and state.
- Delete `_isAndroid`.
- Replace `initState` body with:

```dart
@override
void initState() {
  super.initState();
  _probe = widget.versionProbe ?? CliVersionProbe();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    final mode = context.read<ConnectionModeService>();
    if (mode.isRemoteWorkPlane) {
      unawaited(_refreshRemoteAdapter());
    } else {
      unawaited(_refreshLatest());
    }
  });
}
```

- Change the transport pill condition from `if (_canChooseTransport && !_isAndroid)` to `if (_canChooseTransport)`.
- Change the adapter row `enabled: !_isAndroid` to `enabled: true`.

In `client/lib/pages/config/cli_config_section.dart`:

- Remove `isAndroidOverride` from `CliConfigSection` and `_CliControls`.
- Remove the argument from every `CliReadinessCard` construction.

- [ ] **Step 4: Run the test**

Run: `cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib client/test
git commit -m "feat(acp): show ACP controls on Android settings"
```

---

### Task 7: Block ACP-only CLIs on unsupported targets

**Files:**
- Modify: `client/lib/services/chat/launch/pre_send/workspace_landing_launch_gate.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_landing_launch_feedback.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Test: `client/test/services/chat/launch/pre_send/workspace_landing_launch_gate_test.dart`
- Test: `client/test/pages/home_workspace/workspace/workspace_landing_launch_feedback_test.dart`

**Interfaces:**
- Produces: `final class AcpUnsupportedTargetLaunchBlock extends WorkspaceLandingLaunchBlock`
- Produces: `String landingLaunchAcpUnsupportedMessage(AppLocalizations l10n, AcpUnsupportedTargetLaunchBlock block)`

- [ ] **Step 1: Write the failing test**

In `workspace_landing_launch_gate_test.dart`:

```dart
test('ACP-only CLI on WSL returns an unsupported-target block', () {
  final gate = WorkspaceLandingLaunchGate(storage: storage);
  final block = gate.syncBlock(
    workspace: workspaceWithWslFolder,
    draft: const LandingLaunchContext(
      isPersonal: true,
      acp: false,
      cli: CliTool.gemini,
    ),
  );
  expect(block, isA<AcpUnsupportedTargetLaunchBlock>());
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/pre_send/workspace_landing_launch_gate_test.dart`
Expected: FAIL because `AcpUnsupportedTargetLaunchBlock` does not exist.

- [ ] **Step 3: Add the block and the gate check**

In `workspace_landing_launch_gate.dart`:

```dart
/// ACP-only CLI cannot run on this target and has no PTY fallback.
final class AcpUnsupportedTargetLaunchBlock extends WorkspaceLandingLaunchBlock {
  const AcpUnsupportedTargetLaunchBlock({
    required this.cli,
    required this.targetId,
  });

  final CliTool cli;
  final String targetId;
}
```

Add a helper:

```dart
WorkspaceLandingLaunchBlock? _acpUnsupportedBlock({
  required CliTool? cli,
  required String targetId,
}) {
  if (cli == null) return null;
  if (!CliToolRegistry.builtIn().launchesAcpOnly(cli)) return null;
  if (acpAvailabilityFor(cli: cli, targetId: targetId) !=
      AcpAvailability.unsupported) {
    return null;
  }
  return AcpUnsupportedTargetLaunchBlock(cli: cli, targetId: targetId);
}
```

Call it from `syncBlock` for personal drafts:

```dart
final identity = resolveLandingSimpleLaunchIdentity(
  presets: globalPresets,
  presetId: draft.presetId,
  cli: draft.cli,
  provider: draft.provider,
  model: draft.model,
  effort: draft.effort,
  expertKey: draft.expertKey,
);
final targetId = projectFolderTarget(
  workspace: workspace,
  projectFolderPath: draft.projectFolderPath ?? '',
  home: _home,
  usesPosixPaths: _storage.usesPosixPaths,
)?.id;
final unsupported = _acpUnsupportedBlock(
  cli: identity.cli,
  targetId: targetId ?? _home.id,
);
if (unsupported != null) return unsupported;
```

For team drafts, iterate `memberPlacementForLaunch` and check each member's CLI; return the first unsupported block.

- [ ] **Step 4: Add the UI message and l10n**

In `workspace_landing_launch_feedback.dart`, add a switch case:

```dart
AcpUnsupportedTargetLaunchBlock(:final cli, :final targetId) =>
  landingLaunchAcpUnsupportedMessage(l10n, block),
```

Add:

```dart
String landingLaunchAcpUnsupportedMessage(
  AppLocalizations l10n,
  AcpUnsupportedTargetLaunchBlock block,
) {
  final registry = CliToolRegistry.builtIn();
  final def = registry.tryGet(block.cli);
  final label = def != null
      ? cliDisplayName(def, l10n, registry: registry)
      : block.cli.value;
  return l10n.landingLaunchAcpUnsupported(label, block.targetId);
}
```

Add to `app_en.arb`:

```json
"landingLaunchAcpUnsupported": "{cli} only supports ACP chat, and the selected target ({target}) cannot run ACP. Choose a local, SSH, or Termux target, or pick a CLI with terminal support.",
```

Add to `app_zh.arb`:

```json
"landingLaunchAcpUnsupported": "{cli} 仅支持 ACP 对话，当前目标（{target}）无法运行 ACP。请选择本机、SSH 或 Termux 目标，或改用支持终端的 CLI。",
```

- [ ] **Step 5: Run the tests**

Run:

```bash
cd client && dart run tool/run_tests.dart test/services/chat/launch/pre_send/workspace_landing_launch_gate_test.dart test/pages/home_workspace/workspace/workspace_landing_launch_feedback_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib client/test
git commit -m "feat(acp): block ACP-only CLIs on unsupported targets"
```

---

### Task 8: Bind the remote TeamBus for ACP mixed seats

**Files:**
- Modify: `client/lib/services/chat/launch/connect/acp_runtime_attach.dart`
- Test: `client/test/services/chat/launch/acp_runtime_attach_test.dart`

**Interfaces:**
- Consumes: `SessionLaunchHost.remoteBusSetup`, `SessionLaunchHost.lifecycle`.
- Produces: `_bindMixedRemoteBus` in `AcpRuntimeAttach`.
- Produces: `_productionExtraMcp(..., RemoteBusBinding? mixedRemoteBinding)`.

- [ ] **Step 1: Write the failing test**

In `acp_runtime_attach_test.dart`, add a test with a fake `RemoteMemberBusSetupPort` that records the call and returns a binding with `mcpHttpTunnelPort: 4567`. Assert that the captured `teammate-bus` extra MCP config contains `http://127.0.0.1:4567/mcp`.

```dart
test('remote mixed ACP seat binds the remote bus', () async {
  final setup = _RecordingRemoteBusSetup();
  final harness = await _harness(remoteBusSetup: setup);
  final handled = await harness.service.attachMemberAcpRuntime(
    harness.job,
    harness.teamSession,
    harness.resolvedMember,
  );
  expect(handled, isTrue);
  expect(setup.calls, 1);
  final bus = harness.capturedExtra[teammateBusMcpServerName]!;
  expect(bus['url'], 'http://127.0.0.1:4567/mcp');
});
```

If the harness does not expose `capturedExtra`, add a test seam getter in the harness.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/acp_runtime_attach_test.dart --plain-name "remote mixed ACP seat binds the remote bus"`
Expected: FAIL because `AcpRuntimeAttach` never calls `remoteBusSetup`.

- [ ] **Step 3: Add imports and helpers**

In `acp_runtime_attach.dart`, add:

```dart
import '../../team_bus/remote/member_bus_mcp_config.dart';
import '../../team_bus/remote/remote_member_bus_setup.dart';
```

Add:

```dart
Future<SshMemberSession> _memberSshSession({
  required ChatTab tab,
  required AppSession session,
  required RuntimeTarget launchTarget,
  required String key,
}) async {
  final existing = tab.memberSshSessions[key];
  if (existing != null) return existing;
  final factory = _host.shellFactory.sshClientFactory;
  final profile = _host.shellFactory.profileFor(launchTarget);
  if (factory == null || profile == null) {
    throw StateError('ACP remote session requires an SSH profile and client factory');
  }
  final opened = await SshMemberSession.open(factory, profile);
  tab.memberSshSessions[key] = opened;
  return opened;
}

Future<RemoteBusBinding> _bindMixedRemoteBus({
  required ChatTab tab,
  required AppSession session,
  required RuntimeTarget launchTarget,
  required TeamMemberConfig member,
  required CliTool cli,
  required SshMemberSession memberSession,
}) async {
  final setup = _host.remoteBusSetup;
  if (setup == null) {
    throw StateError('remoteBusSetup is not wired for a remote mixed ACP seat');
  }
  final workCtx = await _host.lifecycle.resolveWorkContextForTargetId(
    launchTarget.id,
  );
  final arch = archFromUname(await memberSession.run('uname -m'));
  return setup
      .mountAndBindMixed(
        tab: tab,
        memberId: member.id,
        cli: cli,
        memberSession: memberSession,
        gateway: _host.teammateBusMcpGateway,
        storageFs: workCtx.fs,
        arch: arch,
      )
      .timeout(const Duration(seconds: 45));
}
```

- [ ] **Step 4: Wire it into `attachMemberAcpRuntime`**

Before `_productionExtraMcp`, add:

```dart
final remote = usesSshTransport(launchTarget.kind);
final gateway = _host.teammateBusMcpGateway;
await gateway.ensureStarted();
final mixedBus =
    team.teamMode == TeamMode.mixed &&
    tab.teamBus != null &&
    gateway.isSessionRegistered(session.sessionId);
RemoteBusBinding? mixedRemoteBinding;
if (mixedBus && remote) {
  final memberSession = await _memberSshSession(
    tab: tab,
    session: session,
    launchTarget: launchTarget,
    key: member.id,
  );
  mixedRemoteBinding = await _bindMixedRemoteBus(
    tab: tab,
    session: session,
    launchTarget: launchTarget,
    member: member,
    cli: cli,
    memberSession: memberSession,
  );
}
```

If `ensureStarted` or `isSessionRegistered` throws, let the exception propagate: a mixed remote ACP seat must not start without its bus.

Then pass `mixedRemoteBinding: mixedRemoteBinding` to `_productionExtraMcp`.

- [ ] **Step 5: Update `_productionExtraMcp`**

Add the parameter:

```dart
RemoteBusBinding? mixedRemoteBinding,
```

Pass it to `resolveMemberBusMcpTransportConfig`:

```dart
remoteBinding: mixedRemoteBinding,
```

Pass it to `composeRuntimeExtraMcpServers`:

```dart
mixedRemoteBinding: mixedRemoteBinding,
```

- [ ] **Step 6: Run the test**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/acp_runtime_attach_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib client/test
git commit -m "feat(acp): bind remote TeamBus for mixed ACP seats"
```

---

### Task 9: Update Antigravity ACP launch arguments

**Files:**
- Modify: `client/lib/services/cli/antigravity/capabilities/acp.dart`
- Test: `client/test/services/cli/antigravity/antigravity_acp_capability_test.dart`

**Interfaces:**
- Produces: `AntigravityAcpCapability.launchArgCandidates` always returns `[[exe, '--uid='], [exe]]`.
- Produces: `AntigravityAcpCapability` implements `AcpNoPtyFallbackCapability`.

- [ ] **Step 1: Update the test**

In `antigravity_acp_capability_test.dart`, replace the platform-specific expectations with:

```dart
test('launch candidates always try the empty uid form first', () {
  const cap = AntigravityAcpCapability();
  expect(cap.launchArgCandidates('server'), [
    ['server', '--uid='],
    ['server'],
  ]);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_acp_capability_test.dart`
Expected: FAIL on macOS/Windows because the first candidate is omitted.

- [ ] **Step 3: Implement**

In `client/lib/services/cli/antigravity/capabilities/acp.dart`:

- Remove `linuxUid` and `_usesUid`.
- Replace `launchArgCandidates` with:

```dart
@override
List<List<String>> launchArgCandidates(String executable) => [
  [executable, '--uid='],
  [executable],
];
```

- Ensure the class implements `AcpNoPtyFallbackCapability`.

- [ ] **Step 4: Run the test**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_acp_capability_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib client/test
git commit -m "feat(antigravity): always probe the empty uid flag first"
```

---

### Task 10: Install the Antigravity CLI on SSH targets

**Files:**
- Create: `client/test/services/cli/fake_cli_installer_host.dart`
- Modify: `client/lib/services/cli/antigravity/capabilities/executable.dart`
- Test: `client/test/services/cli/antigravity/antigravity_executable_test.dart`
- Test: `client/test/services/cli/antigravity/antigravity_acp_adapter_test.dart`

**Interfaces:**
- Consumes: `CliInstallerHost.runSsh`, `CliInstallerCommand.unixShellScript`.
- Produces: `AntigravityExecutableCapability.install(mode: CliInstallMode.ssh)`.
- Produces: `FakeCliInstallerHost` with `sshCommands` and configurable `sshResponses`.

- [ ] **Step 1: Create the shared fake host**

Create `client/test/services/cli/fake_cli_installer_host.dart`:

```dart
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/cli/registry/installer/installer_context.dart';
import 'package:teampilot/services/host/host_execution_environment.dart';
import 'package:teampilot/services/host/host_script_runner.dart';

typedef FakeSshResponse = CliInstallerCommandResult Function(
  CliInstallerCommand command,
);

final class FakeCliInstallerHost implements CliInstallerHost {
  FakeCliInstallerHost({required this.sshResponses});

  final FakeSshResponse sshResponses;
  final sshCommands = <String>[];
  final reported = <CliInstallPhase>[];

  @override
  HostExecutionEnvironment get hostEnvironment =>
      HostExecutionEnvironment.resolve(
        isWindowsHost: false,
        storageMode: StorageBackendMode.native,
      );

  @override
  bool get isWindows => false;

  @override
  HostScriptRunner get scriptRunner => hostEnvironment.scriptRunner;

  @override
  void report(CliInstallPhase phase, {String? detail}) => reported.add(phase);

  @override
  Future<CliInstallerCommandResult> runLocal(
    CliInstallerCommand command, {
    required CliInstallPhase phase,
    bool streamOutput = false,
  }) async => const CliInstallerCommandResult(exitCode: 1);

  @override
  Future<CliInstallerCommandResult> runSsh(
    SshProfile profile,
    CliInstallerCommand command,
  ) async {
    sshCommands.add(command.commandLine);
    return sshResponses(command);
  }

  @override
  Future<String?> locateExecutable(String name) async => null;

  @override
  Future<String?> locateLocalNpm() async => null;

  @override
  Future<String?> locateRemoteNpm(SshProfile profile) async => null;

  @override
  bool get isCancelled => false;
}
```

- [ ] **Step 2: Write the failing test**

In `antigravity_executable_test.dart`, add:

```dart
test('ssh install runs the official script and locates agy', () async {
  final host = FakeCliInstallerHost(
    sshResponses: (command) {
      if (command.commandLine.contains('install.sh')) {
        return const CliInstallerCommandResult(exitCode: 0);
      }
      if (command.commandLine.contains('command -v agy')) {
        return const CliInstallerCommandResult(
          exitCode: 0,
          stdout: '/home/dev/.local/bin/agy\n',
        );
      }
      return const CliInstallerCommandResult(exitCode: 1);
    },
  );
  const cap = AntigravityExecutableCapability();
  final result = await cap.install(
    CliInstallContext(
      mode: CliInstallMode.ssh,
      host: host,
      hostEnvironment: host.hostEnvironment,
      sshProfile: const SshProfile(
        id: 'p1',
        name: 'box',
        host: 'example.invalid',
        username: 'dev',
      ),
    ),
  );
  expect(result.success, isTrue);
  expect(result.executablePath, '/home/dev/.local/bin/agy');
  expect(host.sshCommands.any((c) => c.contains('install.sh')), isTrue);
});
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_executable_test.dart --plain-name "ssh install runs"`
Expected: FAIL with the current "not available yet" message.

- [ ] **Step 4: Implement the SSH branch**

At the top of `install`, replace the existing SSH rejection with:

```dart
if (context.mode == CliInstallMode.ssh) {
  return _installSsh(context);
}
```

Add:

```dart
Future<CliInstallResult> _installSsh(CliInstallContext context) async {
  final profile = context.sshProfile;
  if (profile == null) {
    return const CliInstallResult(
      success: false,
      message: 'Select an SSH server before installing Antigravity remotely.',
    );
  }
  context.host.report(
    CliInstallPhase.installingCli,
    detail: 'Antigravity CLI',
  );
  final install = await context.host.runSsh(
    profile,
    CliInstallerCommand.unixShellScript(
      'curl -fsSL https://antigravity.google/cli/install.sh | bash',
    ),
  );
  if (install.exitCode != 0) {
    return CliInstallResult(
      success: false,
      message: installerFailureMessage(
        'Remote Antigravity CLI install failed',
        install,
      ),
    );
  }
  context.host.report(CliInstallPhase.locatingExecutable);
  final path = await const DefaultRemoteCliLocator('agy').locate((
    command,
  ) async {
    final result = await context.host.runSsh(
      profile,
      CliInstallerCommand.unixShellScript(command),
    );
    return SshCommandResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  });
  return CliInstallResult(
    success: path != null,
    message: path == null
        ? 'agy installed but was not found on the remote PATH.'
        : 'Antigravity CLI installed.',
    executablePath: path,
  );
}
```

- [ ] **Step 5: Run the test**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_executable_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib client/test
git commit -m "feat(antigravity): install the CLI over SSH"
```

---

### Task 11: Install the Antigravity ACP adapter on SSH targets

**Files:**
- Modify: `client/lib/services/cli/antigravity/capabilities/acp_adapter_installer.dart`
- Test: `client/test/services/cli/antigravity/antigravity_acp_adapter_test.dart`
- Reuse: `client/test/services/cli/fake_cli_installer_host.dart`

**Interfaces:**
- Consumes: `CliInstallerHost.runSsh`, `CliInstallerCommand.unixShellScript`, `FakeCliInstallerHost`.
- Produces: `AntigravityAcpAdapterInstaller.install(mode: CliInstallMode.ssh)`.
- Produces: remote path under `$HOME/.local/share/teampilot/toolchain/antigravity-acp/<version>`.

- [ ] **Step 1: Write the failing test**

Replace the old `ssh install returns a failure` test in `antigravity_acp_adapter_test.dart` with:

```dart
test('ssh install probes the host, downloads, extracts, and returns the path', () async {
  final host = FakeCliInstallerHost(
    sshResponses: (command) {
      final line = command.commandLine;
      if (line.contains('uname -s')) {
        return const CliInstallerCommandResult(exitCode: 0, stdout: 'Linux\n');
      }
      if (line.contains('uname -m')) {
        return const CliInstallerCommandResult(exitCode: 0, stdout: 'x86_64\n');
      }
      return const CliInstallerCommandResult(
        exitCode: 0,
        stdout:
            '/home/dev/.local/share/teampilot/toolchain/antigravity-acp/1.4.3/agy_acp_server.par\n',
      );
    },
  );
  const installer = AntigravityAcpAdapterInstaller();
  final result = await installer.install(
    CliInstallContext(
      mode: CliInstallMode.ssh,
      host: host,
      hostEnvironment: host.hostEnvironment,
      sshProfile: const SshProfile(
        id: 'p1',
        name: 'box',
        host: 'example.invalid',
        username: 'dev',
      ),
    ),
  );
  expect(result.success, isTrue);
  expect(
    result.executablePath,
    '/home/dev/.local/share/teampilot/toolchain/antigravity-acp/1.4.3/agy_acp_server.par',
  );
  final script = host.sshCommands.last;
  expect(script, contains('linux-x86_64'));
  expect(script, contains(antigravityAcpSha256['linux-x86_64']!));
  expect(script, contains('chmod +x'));
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_acp_adapter_test.dart --plain-name "ssh install probes"`
Expected: FAIL with the current "not available yet" message.

- [ ] **Step 3: Implement the SSH branch**

At the top of `install`, replace the SSH rejection with:

```dart
if (context.mode == CliInstallMode.ssh) {
  return _installSsh(context);
}
```

Add:

```dart
Future<CliInstallResult> _installSsh(CliInstallContext context) async {
  final profile = context.sshProfile;
  if (profile == null) {
    return const CliInstallResult(
      success: false,
      message: 'Select an SSH server before installing the Antigravity adapter.',
    );
  }

  Future<String> probe(String command) async {
    final result = await context.host.runSsh(
      profile,
      CliInstallerCommand.unixShellScript(command),
    );
    if (result.exitCode != 0) {
      throw StateError('Remote Antigravity probe failed: $command');
    }
    return result.stdout.trim();
  }

  final os = await probe('uname -s');
  final archRaw = await probe('uname -m');
  final arch = (archRaw == 'arm64' || archRaw == 'aarch64')
      ? 'arm64'
      : 'x64';
  final assetKey = switch (os) {
    'Linux' => antigravityAcpAssetKey(os: 'linux', arch: arch),
    'Darwin' => antigravityAcpAssetKey(os: 'darwin', arch: arch),
    _ => '',
  };
  if (assetKey.isEmpty || !antigravityAcpSha256.containsKey(assetKey)) {
    return CliInstallResult(
      success: false,
      message:
          'Remote Antigravity adapter only supports POSIX hosts; '
          'detected os=$os arch=$archRaw.',
    );
  }

  final sha = antigravityAcpSha256[assetKey]!;
  final url = antigravityAcpArchiveUrl(assetKey);
  final version = antigravityAcpVersion;
  final script = '''
set -eu
dest="\$HOME/.local/share/teampilot/toolchain/antigravity-acp/$version"
mkdir -p "\$dest"
tmp="\$(mktemp -d)"
trap 'rm -rf "\$tmp"' EXIT
if command -v curl >/dev/null 2>&1; then
  curl -fsSL '$url' -o "\$tmp/adapter.zip"
elif command -v wget >/dev/null 2>&1; then
  wget -q '$url' -O "\$tmp/adapter.zip"
else
  echo "curl or wget is required" >&2
  exit 1
fi
if command -v sha256sum >/dev/null 2>&1; then
  echo '$sha  \$tmp/adapter.zip' | sha256sum -c -
else
  echo '$sha  \$tmp/adapter.zip' | shasum -a 256 -c -
fi
if command -v unzip >/dev/null 2>&1; then
  unzip -oq "\$tmp/adapter.zip" -d "\$dest"
else
  python3 -m zipfile -e "\$tmp/adapter.zip" "\$dest"
fi
chmod +x "\$dest/agy_acp_server.par" "\$dest/localharness_external"
printf '%s\n' "\$dest/agy_acp_server.par"
''';

  context.host.report(CliInstallPhase.downloading);
  final installed = await context.host.runSsh(
    profile,
    CliInstallerCommand.unixShellScript(script),
  );
  context.host.report(CliInstallPhase.extracting);
  if (installed.exitCode != 0) {
    return CliInstallResult(
      success: false,
      message: installerFailureMessage(
        'Remote Antigravity adapter install failed',
        installed,
      ),
    );
  }
  final lines = installed.stdout
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final path = lines.isEmpty ? null : lines.last;
  return CliInstallResult(
    success: path != null,
    message: path == null
        ? 'Remote Antigravity adapter install did not report a path.'
        : 'Antigravity ACP adapter installed.',
    executablePath: path,
  );
}
```

- [ ] **Step 4: Run the test**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_acp_adapter_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib client/test
git commit -m "feat(antigravity): install the ACP adapter over SSH"
```

---

### Task 12: Resolve the remote profile for interactive login

**Files:**
- Create: `client/lib/services/remote/remote_profile_context.dart`
- Modify: `client/lib/pages/config/cli_readiness_card.dart`
- Modify: `client/lib/services/cli/antigravity/capabilities/provider.dart`
- Test: `client/test/services/cli/antigravity/antigravity_provider_test.dart`

**Interfaces:**
- Produces: `SshProfile? remoteSshProfileFromContext(BuildContext context)`
- Produces: `AntigravityProviderCapability.appliesTo` returns true for official mode on Android/remote.

- [ ] **Step 1: Write the failing test**

In `antigravity_provider_test.dart`, add:

```dart
test('official Antigravity login applies without a platform gate', () {
  const cap = AntigravityProviderCapability();
  const provider = AppProviderConfig(
    id: 'antigravity',
    cli: CliTool.antigravity,
    name: 'Antigravity',
    isOfficial: true,
  );
  expect(cap.appliesTo(provider), isTrue);
  expect(cap.actionsFor(provider), isNotEmpty);
});
```

- [ ] **Step 2: Run the test**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_provider_test.dart --plain-name "official Antigravity login applies without a platform gate"`
Expected: PASS on desktop. This assertion is regression coverage for removing the Android exclusion; the remote behavior itself is covered by Task 13's widget test.

- [ ] **Step 3: Add the shared context helper**

Create `client/lib/services/remote/remote_profile_context.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/termux_cubit.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../models/ssh_profile.dart';
import '../app/connection_mode_service.dart';
import '../termux/termux_transport_profile.dart';

/// Current SSH/Termux profile for the remote work plane, or null locally.
SshProfile? remoteSshProfileFromContext(BuildContext context) {
  final mode = context.read<ConnectionModeService>();
  if (!mode.isRemoteWorkPlane) return null;
  if (mode.isTermuxMode) {
    final config = context.read<TermuxCubit>().state.config;
    return config == null ? null : termuxTransportProfile(config);
  }
  return context.read<SshProfileCubit>().state.selectedProfile;
}
```

- [ ] **Step 4: Reuse the helper in the readiness card**

In `client/lib/pages/config/cli_readiness_card.dart`, replace the private `_remoteSshProfile` function body with a call to `remoteSshProfileFromContext(context)`, or delete the private function and call the shared helper directly in `_remoteAdapterScope`.

- [ ] **Step 5: Allow official login on Android**

In `client/lib/services/cli/antigravity/capabilities/provider.dart`, change:

```dart
@override
bool appliesTo(AppProviderConfig provider) =>
    _resolveAuthMode(provider) == _AntigravityAuthMode.official &&
    !Platform.isAndroid &&
    !Platform.isIOS;
```

to:

```dart
@override
bool appliesTo(AppProviderConfig provider) =>
    _resolveAuthMode(provider) == _AntigravityAuthMode.official;
```

Remove the `dart:io` import if `Platform` is no longer used in the file.

- [ ] **Step 6: Run the tests**

Run:

```bash
cd client && dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_provider_test.dart test/pages/config/cli_config_section_test.dart
```

Expected: PASS. `cli_config_section_test` exercises the readiness card after the helper extraction.

- [ ] **Step 7: Commit**

```bash
git add client/lib client/test
git commit -m "feat(antigravity): resolve the remote profile for login"
```

---

### Task 13: Add the Antigravity remote login dialog

**Files:**
- Create: `client/lib/services/cli/antigravity/provider/antigravity_remote_login_dialog.dart`
- Modify: `client/lib/services/cli/antigravity/capabilities/provider.dart`
- Test: `client/test/services/cli/antigravity/antigravity_remote_login_dialog_test.dart`

**Interfaces:**
- Consumes: `SshProfile`, `SshClientFactory`, `SshMemberSession`, `TerminalEngine`.
- Produces: `AntigravityRemoteLoginDialog`.
- Produces: `AntigravityProviderCapability.buildLoginDialog` selects local vs remote.

- [ ] **Step 1: Write the failing test**

Create `antigravity_remote_login_dialog_test.dart` with a fake `SshClientFactory`/`SshMemberSession` seam. The test should assert:

```dart
testWidgets('remote login starts agy with isolated HOME and verifies models', (
  tester,
) async {
  final session = _FakeMemberSession();
  await tester.pumpWidget(
    MaterialApp(
      home: AntigravityRemoteLoginDialog(
        provider: provider,
        executable: 'agy',
        profile: profile,
        factory: _FakeSshClientFactory(session),
        verifyModels: ({required executable, required environment, required workingDirectory}) async {
          expect(environment['HOME'], contains('cli-login/antigravity'));
          expect(environment['GEMINI_HOME'], endsWith('.gemini'));
          return true;
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(session.ptyCommands.single, contains('exec '));
  await tester.tap(find.byKey(const Key('antigravityRemoteLoginDone')));
  await tester.pumpAndSettle();
  expect(session.closed, isTrue);
});
```

Add `key: const Key('antigravityRemoteLoginDone')` to the Done button in the dialog.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_remote_login_dialog_test.dart`
Expected: FAIL because the dialog does not exist.

- [ ] **Step 3: Implement the remote dialog**

Create `antigravity_remote_login_dialog.dart` with the same visual structure as `AntigravityLoginDialog`:

- `StatefulWidget` fields: `provider`, `executable`, `profile`, `factory`, `verifyModels`.
- `initState` calls `_start`.
- `_start`:

```dart
final session = await SshMemberSession.open(widget.factory, widget.profile);
_session = session;
final root =
    '\$HOME/.local/share/teampilot/cli-login/antigravity/'
    '${_safeSegment(widget.provider.id)}';
await session.run('mkdir -p "$root/home" "$root/workspace"');
final located = await const DefaultRemoteCliLocator('agy').locate((
  command,
) async {
  final result = await session.runWithResult(command);
  return SshCommandResult(
    exitCode: result.exitCode ?? 1,
    stdout: utf8.decode(result.stdout, allowMalformed: true),
    stderr: utf8.decode(result.stderr, allowMalformed: true),
  );
});
final executable = located ?? widget.executable;
final command =
    'export HOME="$root/home"; '
    'export GEMINI_HOME="$root/home/.gemini"; '
    'export TERM=xterm-256color; '
    'export COLORTERM=truecolor; '
    'cd "$root/workspace"; '
    'exec ${_shellQuote(executable)}';
final channel = await session.openPty(
  command: command,
  columns: 100,
  rows: 30,
);
final transport = SshPtyTransport(channel: channel);
```

Import `SshPtyTransport` from `services/chat/runtime/pty/ssh_pty_transport.dart`. Note: the shell string contains `$HOME`; resolve it on the remote first as shown below, or keep it unexpanded in the remote shell string. Prefer resolving it:

```dart
final home = (await session.run('printf %s "\$HOME"')).trim();
final root =
    '$home/.local/share/teampilot/cli-login/antigravity/'
    '${_safeSegment(widget.provider.id)}';
```

- Feed `channel.output` to `TerminalEngine` and write engine output back to the channel.
- `_done` calls `verifyModels(executable: executable, environment: env, workingDirectory: root/workspace)`.
- `dispose` closes the channel and session.
- Add `_shellQuote` helper:

```dart
String _shellQuote(String value) =>
    "'${value.replaceAll("'", "'\"'\"'")}'";
```

- [ ] **Step 4: Select the dialog**

In `AntigravityProviderCapability.buildLoginDialog`:

```dart
final profile = remoteSshProfileFromContext(context);
if (profile != null) {
  return AntigravityRemoteLoginDialog(
    provider: provider,
    executable: executable,
    profile: profile,
    factory: context.read<SshClientFactory>(),
    verifyModels: _verifyRemoteModels,
  );
}
return AntigravityLoginDialog(
  executable: executable,
  provider: provider,
  storage: homeStorageOf(context),
);
```

Add a `_verifyRemoteModels` helper that opens a short-lived `SshMemberSession`, runs `agy models` with the same HOME/GEMINI_HOME, and closes it.

- [ ] **Step 5: Run the test**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_remote_login_dialog_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add client/lib client/test
git commit -m "feat(antigravity): add remote OAuth login dialog"
```

---

### Task 14: Verify the remote OAuth flow on a real host

**Files:**
- Create: `docs/remote-antigravity-oauth-smoke.md`
- Modify: `docs/remote-acp-adapter-smoke.md` (link the new checklist)

**Interfaces:**
- Produces: a documented decision on device-code vs loopback redirect.
- Produces: port-forward implementation only if the spike requires it.

- [ ] **Step 1: Run the spike on a real SSH target**

On a real Linux/macOS host reachable from the app:

```bash
ssh <profile>
export HOME="$HOME/.local/share/teampilot/cli-login/antigravity/spike/home"
mkdir -p "$HOME" "$HOME/.gemini"
export GEMINI_HOME="$HOME/.gemini"
agy
```

Record:

- Does `agy` print a device code + URL, or a `http://127.0.0.1:<port>/...` redirect?
- Does it require an OS keyring / DBus?
- After login, does `agy models` exit 0?
- Does the ACP adapter accept `initialize` / `session/new` with the same `GEMINI_HOME`?

- [ ] **Step 2: Branch on the result**

- **Device-code:** no code change; document it in `docs/remote-antigravity-oauth-smoke.md`.
- **Loopback redirect:** add a port-forward helper to `AntigravityRemoteLoginDialog` that opens a local listener and forwards to the remote port. Implement it behind a `RemoteLoginPortForward` interface and test it with a fake tunnel. If the SSH worker does not expose local-to-remote forwarding, extend `SshMemberSession` with a `forwardLocalPortToRemote(int localPort, int remotePort)` method and cover it with a fake worker test.
- **Keyring unavailable:** verify whether `GEMINI_HOME` file credentials are written. If not, keep API key / ADC as the working path and document the limitation. Do not silently drop the OAuth control.

- [ ] **Step 3: Write the smoke doc**

Create `docs/remote-antigravity-oauth-smoke.md` with:

1. CLI install steps.
2. Adapter install steps.
3. Login flow observed (device-code or loopback).
4. `agy models` verification.
5. ACP `session/new` and first prompt.
6. Known limitations.

- [ ] **Step 4: Commit**

```bash
git add docs/remote-antigravity-oauth-smoke.md docs/remote-acp-adapter-smoke.md
git commit -m "docs(antigravity): add remote OAuth smoke checklist"
```

---

### Task 15: Update docs and run the full suite

**Files:**
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/remote-acp-adapter-smoke.md`
- Modify: `docs/cli-architecture.md`

- [ ] **Step 1: Update the architecture docs**

In `docs/ARCHITECTURE.md`, replace the Android gate paragraph with:

```markdown
ACP availability is resolved by `launch_acp_policy.dart` from two inputs:
the CLI's declared capabilities and the work target's exec channel. `local`,
`ssh`, and `termux` targets support ACP; `wsl` does not. Android is no longer
special-cased. ACP-only CLIs are forced when the target supports ACP.
```

Add a note that remote mixed-team ACP seats bind the same `RemoteBusMount` reverse tunnel as PTY seats, and that Antigravity supports remote CLI/adapter install and OAuth.

In `docs/cli-architecture.md`, add:

```markdown
ACP launch decisions live in `services/chat/launch/session/launch_acp_policy.dart`.
When adding a CLI, declare `AcpCapability` / `CliTransportCapability`; never add
`Platform.isAndroid` or `cli == <value>` branches to launch code.
```

- [ ] **Step 2: Run the analyzer**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no new errors or warnings.

- [ ] **Step 3: Run the full test suite**

Run: `cd client && dart run tool/run_tests.dart`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add docs client
git commit -m "docs(acp): document unified Android ACP support"
```

---

## Self-Review

**Spec coverage:**

| Spec section | Task |
|---|---|
| 1. Unified policy | 1 |
| 2. Call-site unification | 3, 4, 5, 6 |
| 3. Capability rename | 2 |
| 4. Android UI | 6 |
| 5. Remote Team ACP TeamBus | 8 |
| 6. Antigravity remote CLI | 10 |
| 7. Antigravity remote adapter | 11 |
| 8. Antigravity launch args | 9 |
| 9. Antigravity remote OAuth | 12, 13, 14 |
| 10. Docs | 14, 15 |
| Unsupported-target block | 7 |
| Tests | each task |

**Placeholder scan:** No `TBD` / `TODO` steps. Task 14 is a deliberate spike with a concrete decision tree; it does not block Tasks 1–13.

**Type consistency:** `resolveAcpOnTarget`, `acpAvailabilityFor`, `canChooseAcpTransport`, `acpForcedByCli`, `AcpNoPtyFallbackCapability`, `remoteSshProfileFromContext`, and `RemoteBusBinding` are used consistently across tasks.
