# Work Target Literal `local` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `local` mean device-native only; when home is SSH/WSL, resolve and stamp folder targets as `home.id` so Android session launch uses SSH PTY instead of local `File.existsSync`.

**Architecture:** Add pure `WorkTargetCanonicalizer` as the single choke point. Wire it into lifecycle / shell / run / remote-CLI resolve paths first; stamp honest defaults on workspace create; then remove `RuntimeContextResolver`'s Android `||` so `local` is native again.

**Tech Stack:** Flutter / Dart, existing `RuntimeTarget`, `SessionLifecycleService`, `ChatSessionShellFactory`, workspace terminal specs.

**Spec:** `docs/superpowers/specs/2026-07-30-work-target-literal-local-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/storage/work_target_canonicalizer.dart` | Pure `defaultFolderTargetId` + `resolve` + shared id→`RuntimeTarget` parse |
| `client/test/services/storage/work_target_canonicalizer_test.dart` | Canonicalizer unit tests |
| `client/lib/services/session/session_lifecycle_service.dart` | Inject `homeTarget`; `launchWorkTarget` / `_runtimeTargetFromId` use canonicalize |
| `client/lib/app/app_shell.dart` | Pass `homeTarget: defaultTargetResolver` into lifecycle |
| `client/lib/models/workspace_terminal_session_spec.dart` | `defaultSessionSpecFor` takes `home`; canonicalize before LocalSpec branch |
| `client/lib/widgets/workspace_terminal_panel.dart` | Pass home into `defaultSessionSpecFor` |
| `client/lib/services/workbench/workbench_shell_launcher.dart` | Pass home into `defaultSessionSpecFor` |
| `client/lib/services/terminal/workspace_shell_connector.dart` | Resolve workspace-target ids via canonicalizer when home available |
| `client/lib/services/run/run_target_resolver.dart` | Resolve owner target via canonicalizer + home |
| `client/lib/services/remote/remote_cli_requirements.dart` | `sshTargetForProjectFolder` uses resolve(home) so SSH-home `local` counts as remote |
| `client/lib/pages/home_workspace/workspace/workspace_landing_launch_gate.dart` | Sole production caller of `remoteCliRequirementsForSimpleLaunch` — pass home |
| `client/lib/services/launch/workspace_provision_coordinator.dart` | `isOffHome` compares resolved ids |
| `client/lib/models/workspace.dart` | `foldersForPrimaryPath` implicit `WorkspaceFolder(path: primary)` — stamp home default |
| `client/lib/widgets/workspace_folders_editor.dart` / `workspace_details_dialog.dart` | Empty-row defaults — use home default when writing |
| `client/lib/pages/home_workspace/home_new_workspace_dialog.dart` | Initial `_targetId` = home default |
| `client/lib/widgets/create_workspace_dialog.dart` | Same |
| `client/lib/services/team/default_workspace_service.dart` | Stamp home default on create |
| `client/lib/cubits/chat/session_launch_service.dart` | Ad-hoc `WorkspaceFolder` includes resolved/home target |
| `client/lib/services/storage/runtime_context_resolver.dart` | Remove Android `||` after all resolve wires (last task) |
| Tests under `client/test/…` matching above | Regression coverage |

---

### Task 1: `WorkTargetCanonicalizer`

**Files:**
- Create: `client/lib/services/storage/work_target_canonicalizer.dart`
- Create: `client/test/services/storage/work_target_canonicalizer_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/storage/work_target_canonicalizer.dart';

void main() {
  final sshHome = RuntimeTarget.ssh('p1', label: 'box');
  final wslHome = RuntimeTarget.wsl('Ubuntu');
  final localHome = RuntimeTarget.local();

  test('defaultFolderTargetId follows home kind', () {
    expect(WorkTargetCanonicalizer.defaultFolderTargetId(localHome), 'local');
    expect(WorkTargetCanonicalizer.defaultFolderTargetId(sshHome), 'ssh:p1');
    expect(WorkTargetCanonicalizer.defaultFolderTargetId(wslHome), 'wsl:Ubuntu');
  });

  test('resolve keeps local when home is local', () {
    expect(
      WorkTargetCanonicalizer.resolve('local', home: localHome).id,
      'local',
    );
  });

  test('resolve rewrites local to non-local home', () {
    expect(
      WorkTargetCanonicalizer.resolve('local', home: sshHome),
      sshHome,
    );
    expect(
      WorkTargetCanonicalizer.resolve('local', home: wslHome),
      wslHome,
    );
  });

  test('resolve leaves explicit ssh/wsl ids unchanged', () {
    expect(
      WorkTargetCanonicalizer.resolve('ssh:other', home: sshHome).id,
      'ssh:other',
    );
    expect(
      WorkTargetCanonicalizer.resolve('wsl:Other', home: wslHome).id,
      'wsl:Other',
    );
  });

  test('fromId parses bare ids without home rewrite', () {
    expect(WorkTargetCanonicalizer.fromId('local').kind, RuntimeKind.local);
    expect(WorkTargetCanonicalizer.fromId('ssh:p1').sshProfileId, 'p1');
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd client && flutter test test/services/storage/work_target_canonicalizer_test.dart`

Expected: FAIL — target URI does not exist.

- [ ] **Step 3: Implement**

```dart
import '../../models/runtime_target.dart';

/// Single choke point: folder/member target ids ↔ execution [RuntimeTarget].
///
/// [RuntimeTarget.localId] means device-native only. When [home] is SSH/WSL,
/// bare `local` is normalized to [home] (dirty Android / SSH-home data).
abstract final class WorkTargetCanonicalizer {
  static String defaultFolderTargetId(RuntimeTarget home) {
    if (home.kind == RuntimeKind.local) return RuntimeTarget.localId;
    return home.id;
  }

  static RuntimeTarget fromId(String id) {
    final trimmed = id.trim();
    return switch (runtimeKindOfId(trimmed)) {
      RuntimeKind.ssh => RuntimeTarget.ssh(
        sshProfileIdOfId(trimmed) ?? '',
        label: '',
      ),
      RuntimeKind.wsl => RuntimeTarget.wsl(wslDistroOfId(trimmed) ?? ''),
      RuntimeKind.local => RuntimeTarget.local(),
    };
  }

  static RuntimeTarget resolve(String targetId, {required RuntimeTarget home}) {
    final trimmed = targetId.trim();
    if (trimmed.isEmpty ||
        trimmed == RuntimeTarget.localId ||
        trimmed == WorkspaceFolderLocalId) {
      if (home.kind != RuntimeKind.local) return home;
      return RuntimeTarget.local();
    }
    return fromId(trimmed);
  }
}

// Use RuntimeTarget.localId only — do not import WorkspaceFolder here.
// In resolve, compare to RuntimeTarget.localId ('local').
```

Fix the stub: do **not** invent `WorkspaceFolderLocalId`. Final `resolve`:

```dart
static RuntimeTarget resolve(String targetId, {required RuntimeTarget home}) {
  final trimmed = targetId.trim();
  if (trimmed.isEmpty || trimmed == RuntimeTarget.localId) {
    if (home.kind != RuntimeKind.local) return home;
    return RuntimeTarget.local();
  }
  return fromId(trimmed);
}
```

- [ ] **Step 4: Run test — expect PASS**

Run: `cd client && flutter test test/services/storage/work_target_canonicalizer_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/storage/work_target_canonicalizer.dart \
  client/test/services/storage/work_target_canonicalizer_test.dart
git commit -m "$(cat <<'EOF'
feat(storage): add WorkTargetCanonicalizer for literal local

EOF
)"
```

---

### Task 2: Lifecycle `launchWorkTarget` uses canonicalizer + home

**Files:**
- Modify: `client/lib/services/session/session_lifecycle_service.dart`
- Modify: `client/lib/app/app_shell.dart` (~675)
- Create or extend: `client/test/services/session/session_lifecycle_launch_work_target_test.dart`

- [ ] **Step 1: Write failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';

void main() {
  test('launchWorkTarget rewrites folder local when home is ssh', () {
    final home = RuntimeTarget.ssh('p1', label: 'box');
    final lifecycle = SessionLifecycleService(homeTarget: () => home);
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      folders: const [WorkspaceFolder(path: '/repo')], // targetId local
      createdAt: 1,
    );
    final ctx = WorkspaceLaunchContext(
      session: session,
      workspace: Workspace(
        workspaceId: 'w1',
        folders: session.folders,
        createdAt: 1,
      ),
    );
    final target = lifecycle.launchWorkTarget(ctx);
    expect(target.kind, RuntimeKind.ssh);
    expect(target.id, 'ssh:p1');
  });
}
```

(Adjust `WorkspaceLaunchContext` constructor to match the real type in `workspace_launch_context.dart`.)

- [ ] **Step 2: Run test — expect FAIL** (no `homeTarget` / still returns local)

Run: `cd client && flutter test test/services/session/session_lifecycle_launch_work_target_test.dart`

- [ ] **Step 3: Implement**

In `SessionLifecycleService`:

```dart
SessionLifecycleService({
  // ...existing...
  RuntimeTarget Function()? homeTarget,
}) : ...
     _homeTarget = homeTarget ?? RuntimeTarget.local;

final RuntimeTarget Function() _homeTarget;

RuntimeTarget _runtimeTargetFromId(String id) =>
    WorkTargetCanonicalizer.resolve(id, home: _homeTarget());
```

Replace the old switch-based `_runtimeTargetFromId`. Keep `launchWorkTarget` calling it.

In `app_shell.dart` when constructing lifecycle:

```dart
sessionLifecycleService = SessionLifecycleService(
  homeTarget: defaultTargetResolver,
  // ...existing args...
);
```

- [ ] **Step 4: Run test — expect PASS**

Also run any existing lifecycle tests that construct `SessionLifecycleService()` without home (default local home — OK).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/session/session_lifecycle_service.dart \
  client/lib/app/app_shell.dart \
  client/test/services/session/session_lifecycle_launch_work_target_test.dart
git commit -m "$(cat <<'EOF'
fix(session): canonicalize launch work targets against home

EOF
)"
```

---

### Task 3: `defaultSessionSpecFor` + call sites

**Files:**
- Modify: `client/lib/models/workspace_terminal_session_spec.dart`
- Modify: `client/lib/widgets/workspace_terminal_panel.dart`
- Modify: `client/lib/services/workbench/workbench_shell_launcher.dart`
- Create: `client/test/models/workspace_terminal_session_spec_test.dart` (or extend if exists)

- [ ] **Step 1: Write failing test**

```dart
test('defaultSessionSpecFor uses home ssh when folder target is local', () {
  final home = RuntimeTarget.ssh('p1', label: 'box');
  final spec = defaultSessionSpecFor(
    cwd: '/repo',
    folders: const [WorkspaceFolder(path: '/repo')],
    fallbackLocalShell: '/bin/bash',
    home: home,
  );
  expect(spec, isA<WorkspaceTerminalWorkspaceTargetSpec>());
  expect((spec as WorkspaceTerminalWorkspaceTargetSpec).targetId, 'ssh:p1');
});

test('defaultSessionSpecFor keeps LocalSpec when home is local', () {
  final spec = defaultSessionSpecFor(
    cwd: '/repo',
    folders: const [WorkspaceFolder(path: '/repo')],
    fallbackLocalShell: '/bin/bash',
    home: RuntimeTarget.local(),
  );
  expect(spec, isA<WorkspaceTerminalLocalSpec>());
});
```

- [ ] **Step 2: Run — expect FAIL** (missing `home` param)

- [ ] **Step 3: Implement**

```dart
WorkspaceTerminalSessionSpec defaultSessionSpecFor({
  required String cwd,
  required List<WorkspaceFolder> folders,
  required String fallbackLocalShell,
  required RuntimeTarget home,
}) {
  final rawId =
      targetIdForFolderPaths(folders, [cwd], matchSubpaths: true) ??
      (folders.isNotEmpty
          ? folders.first.targetId
          : WorkspaceFolder.localTargetId);
  final resolved = WorkTargetCanonicalizer.resolve(rawId, home: home);
  if (resolved.kind == RuntimeKind.local) {
    return WorkspaceTerminalLocalSpec(fallbackLocalShell);
  }
  return WorkspaceTerminalWorkspaceTargetSpec(resolved.id);
}
```

Update call sites to pass home. Prefer `HomeTargetController` (already used by `workspace_folders_editor`) or the same `homeTarget` callback wired into lifecycle — keep one source of truth. Grep `defaultSessionSpecFor(` and fix every call.

For `WorkspaceShellConnector._runtimeTargetFromId`: replace with `WorkTargetCanonicalizer.resolve(id, home: _homeTarget())` — inject `RuntimeTarget Function() homeTarget` into the connector (wire from `app_shell` / registry factory). If connector has no home today, add the same callback pattern as lifecycle.

- [ ] **Step 4: Tests PASS; `flutter analyze` on touched files clean**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
fix(terminal): canonicalize workspace shell session specs

EOF
)"
```

---

### Task 4: RunTargetResolver + remote CLI requirements + isOffHome

**Files:**
- Modify: `client/lib/services/run/run_target_resolver.dart`
- Modify: `client/lib/services/remote/remote_cli_requirements.dart`
- Modify: `client/lib/services/launch/workspace_provision_coordinator.dart`
- Modify: `client/test/services/run/run_target_resolver_test.dart`
- Modify: `client/test/services/remote/remote_cli_requirements_test.dart`

- [ ] **Step 1: Failing tests**

`RunTargetResolver`:

```dart
test('resolves local owner to ssh home', () {
  final home = RuntimeTarget.ssh('p1', label: 'box');
  final plan = RunTargetResolver(homeTarget: () => home).resolve(
    owner: const WorkspaceFolder(path: '/repo'),
  );
  expect(plan.runtimeTarget.kind, RuntimeKind.ssh);
  expect(plan.targetId, 'ssh:p1'); // plan.targetId should be resolved.id
});
```

`sshTargetForProjectFolder`:

```dart
test('SSH home + local folder returns home ssh target', () {
  final home = RuntimeTarget.ssh('host-a', label: 'Build host');
  final ws = Workspace(
    workspaceId: 'ws',
    folders: const [WorkspaceFolder(path: '/local')],
    createdAt: 1,
  );
  final target = sshTargetForProjectFolder(
    workspace: ws,
    projectFolderPath: '/local',
    selectableTargets: [home],
    home: home,
  );
  expect(target?.id, 'ssh:host-a');
});
```

`isOffHome`: when member target resolves to same ssh home, returns false even if raw id was `local` — add unit test on coordinator with `homeTarget: () => sshHome`.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

- `RunTargetResolver({RuntimeTarget Function()? homeTarget})` — resolve owner via canonicalizer; set `plan.targetId` to **resolved** id.
- `sshTargetForProjectFolder(..., required RuntimeTarget home)` — resolve folder targetId; if resolved.kind == ssh, match selectableTargets / return resolved.
- Update all call sites of `sshTargetForProjectFolder` / `remoteCliRequirementsForSimpleLaunch` to pass home.
- `isOffHome`: `final resolved = WorkTargetCanonicalizer.resolve(memberTarget.id, home: homeTarget()); return resolved.kind == RuntimeKind.ssh && resolved.id != homeTarget().id;`  
  (Or: if caller already passes resolved target, compare ids only — prefer resolving inside `isOffHome` when given a possibly-raw target.)

- [ ] **Step 4: PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
fix(launch): canonicalize run and remote-cli work targets

EOF
)"
```

---

### Task 5: Write path — stamp honest folder target ids

**Files:**
- Modify: `client/lib/pages/home_workspace/home_new_workspace_dialog.dart`
- Modify: `client/lib/widgets/create_workspace_dialog.dart`
- Modify: `client/lib/services/team/default_workspace_service.dart`
- Modify: `client/lib/cubits/chat/session_launch_service.dart` (~574)
- Tests: extend create-workspace / default-workspace tests if present; else add focused unit for `DefaultWorkspaceService` with injectable home

- [ ] **Step 1: Failing test for default workspace stamp**

Extend `client/test/services/team/default_workspace_service_test.dart` (existing harness):

```dart
test('ensureDefault stamps ssh home as folder targetId', () async {
  // Use existing test AppStorage harness; pass home: RuntimeTarget.ssh('p1', label: 'box')
  // into ensureDefault; expect created workspace folders.first.targetId == 'ssh:p1'.
});
```

Also cover `workspace.dart` `foldersForPrimaryPath` if it still emits bare `local` under SSH home.

- [ ] **Step 2: FAIL**

- [ ] **Step 3: Implement**

- Dialogs: init `_targetId = WorkTargetCanonicalizer.defaultFolderTargetId(context.read<ConnectionModeService>()…)` — if dialogs only have home via a cubit/service, use `HomeTargetController` / whatever `app_shell` already provides. Prefer reading the same `defaultTargetResolver` surface used elsewhere (e.g. `ConnectionModeService` does not expose id — check `HomeTargetController.current` or pass `homeTargetId` into dialog).
- `DefaultWorkspaceService.ensureDefault`: add `RuntimeTarget home` (or `String Function() defaultTargetId`) parameter; `WorkspaceFolder(path: primaryPath, targetId: WorkTargetCanonicalizer.defaultFolderTargetId(home))`.
- `session_launch_service` ad-hoc folders: use `WorkTargetCanonicalizer.defaultFolderTargetId(_h.lifecycle.home)` or session folder’s resolved id — inject/read home from lifecycle.

Grep `WorkspaceFolder(path:` and `targetId = WorkspaceFolder.localTargetId` under `client/lib` and fix every **write** of implicit local under SSH-home capable paths.

- [ ] **Step 4: PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(workspace): stamp home-bound folder target ids on create

EOF
)"
```

---

### Task 6: Shell factory regression + call-site audit

**Files:**
- Possibly only tests: `client/test/cubits/chat/chat_session_shell_factory_test.dart`
- Grep audit (no new production code if Task 2–5 covered):

```bash
cd client && rg -n '_runtimeTargetFromId|localTargetId|RuntimeTarget\.local\(\)|WorkspaceFolder\(path:' lib/
```

- [ ] **Step 1: Confirm existing factory test still covers SSH workTarget → `validateLaunch: false`**

Add test if missing:

```dart
test('ssh workTarget disables local launch validation', () { ... });
```

- [ ] **Step 2: Fix any remaining process-placement paths found by grep that still treat bare `local` as native while home can be SSH (document each fix in the commit message).

- [ ] **Step 3: Commit**

```bash
git commit -m "$(cat <<'EOF'
test(chat): lock SSH workTarget skips local exe validation

EOF
)"
```

---

### Task 7: Remove Android `||` in `RuntimeContextResolver` (last)

**Files:**
- Modify: `client/lib/services/storage/runtime_context_resolver.dart`
- Modify: `client/test/services/storage/runtime_context_resolver_test.dart`

- [ ] **Step 1: Write/adjust test**

Assert resolving `RuntimeTarget.local()` on a fake Android flag (inject `bool Function()? useSshStorage` or pass `forceNativeLocal` — prefer replacing the platform check with `target.kind == RuntimeKind.ssh` only, and test that local never opens SFTP).

Current:

```dart
final useSsh =
    Platform.isAndroid ||
    (target.kind == RuntimeKind.ssh && ...);
```

New:

```dart
final useSsh =
    target.kind == RuntimeKind.ssh &&
    sshProfile != null &&
    sshClientFactory != null;
```

Home on Android remains an SSH target at bind time — no need for Android special case.

- [ ] **Step 2: Run resolver tests — FAIL if tests assumed Android-local→SSH**

- [ ] **Step 3: Implement removal; update tests**

- [ ] **Step 4: Full verification**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test test/services/storage/work_target_canonicalizer_test.dart \
  test/services/session/session_lifecycle_launch_work_target_test.dart \
  test/services/storage/runtime_context_resolver_test.dart \
  test/services/remote/remote_cli_requirements_test.dart \
  test/services/run/run_target_resolver_test.dart \
  test/cubits/chat/chat_session_shell_factory_test.dart
```

Then broader: `flutter test --exclude-tags integration` (or at least storage/session/launch/terminal related suites).

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
refactor(storage): drop Android local→SSH filesystem special case

EOF
)"
```

---

## Manual check (after Task 7)

- Android device/emulator: SSH home → open workspace with (old) `local` folders → start Claude → connects over SSH, no `executable not found` from local validator.
- Workspace bottom terminal opens remote shell on that host.
- Desktop local home unchanged (local PTY + local FS).

---

## Execution note

Do **not** start Task 7 until Tasks 1–6 are green. Order is a hard dependency from the spec.
