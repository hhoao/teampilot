# Remote Toolchain Locate (Git / Node) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable remote Locate for Git and Node, persist into `toolchainPaths`, and make Git runners + CLI installer honor those paths.

**Architecture:** Reuse `DefaultRemoteCliLocator` inside `ToolchainExecutableDiscovery.locateRemoteTool`. Settings row mirrors CLI remote locate. Optional git executable flows through `gitCommandRunnerForContext` via a process-wide provider set in `app_shell`. Node preference is a callback on `CliInstallerService` used before npm/node PATH probes.

**Tech Stack:** Flutter / Dart, `flutter_bloc`, existing SSH/`SshCommandRunner`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-03-remote-toolchain-locate-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/cli/toolchain_executable_discovery.dart` | Add `locateRemoteTool` using `DefaultRemoteCliLocator` |
| `client/test/services/cli/toolchain_executable_discovery_test.dart` | Remote locate unit tests |
| `client/lib/pages/config/toolchain_path_settings_row.dart` | Remote locate path (remove unsupported toast) |
| `client/lib/pages/config/cli_executable_path_settings_row.dart` | Optionally export/share `_remoteSshProfile` — prefer copy once first (YAGNI) |
| `client/test/pages/config/toolchain_path_locate_test.dart` | Remote locate writes path; flip old “unsupported” test |
| `client/lib/services/git/git_command_runner.dart` | `gitExecutable` on runners + `configuredGitExecutable` provider |
| `client/lib/services/git/git_service.dart` | `forContext` reads provider |
| `client/lib/services/git/git_worktree_service.dart` | `forContext` reads provider |
| `client/test/services/git/git_command_runner_test.dart` | Configured executable used; availability probe |
| `client/lib/app/app_shell.dart` | Wire `configuredGitExecutable` from `SessionPreferencesCubit` |
| `client/lib/services/cli/cli_installer_service.dart` | `preferredNodePath` callback; sibling npm before PATH |
| `client/lib/pages/config/cli_executable_path_settings_row.dart` | Pass preferred node when constructing installer |
| `client/lib/pages/onboarding/steps/cli_step.dart` | Same |
| `client/lib/services/remote/remote_preflight_cli_install.dart` | Same (getter from caller if available; else leave null) |
| `client/test/services/cli/cli_installer_service_test.dart` | Preferred node / sibling npm tests |

**Out of scope (do not touch unless one-line free):** `SkillRepoGitService`, `PluginRepoGitService`, per-target toolchain overrides, remote Browse/Install.

---

### Task 1: `locateRemoteTool` on ToolchainExecutableDiscovery

**Files:**
- Modify: `client/lib/services/cli/toolchain_executable_discovery.dart`
- Modify: `client/test/services/cli/toolchain_executable_discovery_test.dart`

- [ ] **Step 1: Write failing tests**

Append to `toolchain_executable_discovery_test.dart`:

```dart
test('locateRemoteTool finds git via DefaultRemoteCliLocator probe', () async {
  final discovery = ToolchainExecutableDiscovery(
    detectGit: () async => const GitInstallResult.notFound('skip'),
  );
  final path = await discovery.locateRemoteTool(
    toolId: SessionPreferences.toolchainGit,
    run: (command) async {
      expect(command, contains('git'));
      return const SshCommandResult(exitCode: 0, stdout: '/usr/bin/git\n');
    },
  );
  expect(path, '/usr/bin/git');
});

test('locateRemoteTool finds node via DefaultRemoteCliLocator probe', () async {
  final discovery = ToolchainExecutableDiscovery(
    detectGit: () async => const GitInstallResult.notFound('skip'),
  );
  final path = await discovery.locateRemoteTool(
    toolId: SessionPreferences.toolchainNode,
    run: (command) async {
      expect(command, contains('node'));
      return const SshCommandResult(exitCode: 0, stdout: '/usr/bin/node\n');
    },
  );
  expect(path, '/usr/bin/node');
});

test('locateRemoteTool returns null for unknown toolId', () async {
  final discovery = ToolchainExecutableDiscovery(
    detectGit: () async => const GitInstallResult.notFound('skip'),
  );
  expect(
    await discovery.locateRemoteTool(toolId: 'unknown', run: (_) async {
      fail('must not run');
    }),
    isNull,
  );
});

test('locateRemoteTool returns null when remote probe empty', () async {
  final discovery = ToolchainExecutableDiscovery(
    detectGit: () async => const GitInstallResult.notFound('skip'),
  );
  final path = await discovery.locateRemoteTool(
    toolId: SessionPreferences.toolchainGit,
    run: (_) async => const SshCommandResult(exitCode: 1, stdout: ''),
  );
  expect(path, isNull);
});
```

Import `SshCommandResult` from `remote_cli_locator.dart` / capability file.

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd client && flutter test test/services/cli/toolchain_executable_discovery_test.dart
```

Expected: FAIL (`locateRemoteTool` missing).

- [ ] **Step 3: Minimal implementation**

In `toolchain_executable_discovery.dart`:

```dart
import 'registry/capabilities/remote_cli_locator_capability.dart';

Future<String?> locateRemoteTool({
  required String toolId,
  required SshCommandRunner run,
}) async {
  final name = switch (toolId) {
    SessionPreferences.toolchainGit => 'git',
    SessionPreferences.toolchainNode => 'node',
    _ => null,
  };
  if (name == null) return null;
  return DefaultRemoteCliLocator(name).locate(run);
}
```

Update class doc comment: local + remote.

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/services/cli/toolchain_executable_discovery_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/toolchain_executable_discovery.dart \
  client/test/services/cli/toolchain_executable_discovery_test.dart
git commit -m "$(cat <<'EOF'
feat(cli): add locateRemoteTool for git and node

EOF
)"
```

---

### Task 2: Settings row remote Locate

**Files:**
- Modify: `client/lib/pages/config/toolchain_path_settings_row.dart`
- Modify: `client/test/pages/config/toolchain_path_locate_test.dart`

- [ ] **Step 1: Rewrite failing/behavior tests**

Replace `remote Locate skips override and leaves path empty` with:

```dart
testWidgets('remote Locate uses override and persists path', (tester) async {
  final cubit = await _makeCubit();
  addTearDown(cubit.close);
  await tester.pumpWidget(
    _wrapRow(
      cubit,
      connectionMode: ConnectionModeService(
        defaultTargetResolver: () => RuntimeTarget.ssh('p1', label: 'box'),
        hasSshProfiles: () => true,
      ),
      locateOverride: () async => '/usr/local/bin/git',
    ),
  );
  await tester.pump();
  await tester.tap(find.byKey(AppKeys.gitToolchainPathResetButton));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  expect(
    cubit.toolchainPath(SessionPreferences.toolchainGit),
    '/usr/local/bin/git',
  );
  AppToast.dismiss();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
});
```

Add a test that remote with `locateOverride: () async => null` (or empty) shows failure and leaves path empty — optional if timeboxed.

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd client && flutter test test/pages/config/toolchain_path_locate_test.dart
```

Expected: FAIL (remote still early-returns before override / unsupported toast).

- [ ] **Step 3: Implement settings row**

Change `_locate` / `_resolveLocatePath` to mirror `CliExecutablePathSettingsRow`:

1. Delete the `isRemoteWorkPlane` → `cliExecutablePathLocateRemoteUnsupported` block.
2. `_resolveLocatePath`:
   - if `locateOverride != null` → use it (works for local **and** remote tests);
   - else if remote → resolve SSH profile (copy `_remoteSshProfile` logic from CLI row: Termux vs `SshProfileCubit`), `SshClientFactory.clientForStorage`, `ToolchainExecutableDiscovery().locateRemoteTool(toolId: widget.toolId, run: RemoteCliLocator.runnerForClient(client))`;
   - else → `locateLocalTool`.
3. Add imports: `ssh_profile_cubit`, `termux_cubit`, `ssh_client_factory`, `remote_cli_locator`, `ssh_profile`, `termux_transport_profile` as needed.
4. Missing profile → return null → existing failure toast.

Do **not** extract shared helper unless the copy is painful; a private top-level `_remoteSshProfile` in this file (duplicate of CLI row) is OK per spec YAGNI.

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/pages/config/toolchain_path_locate_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/config/toolchain_path_settings_row.dart \
  client/test/pages/config/toolchain_path_locate_test.dart
git commit -m "$(cat <<'EOF'
feat(settings): support remote Locate for toolchain git/node

EOF
)"
```

---

### Task 3: Git runners honor configured executable

**Files:**
- Modify: `client/lib/services/git/git_command_runner.dart`
- Modify: `client/lib/services/git/git_service.dart`
- Modify: `client/lib/services/git/git_worktree_service.dart`
- Modify: `client/test/services/git/git_command_runner_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
test('LocalGitCommandRunner uses injected gitExecutable', () async {
  String? seenExe;
  final runner = LocalGitCommandRunner(
    gitExecutable: '/custom/git',
    runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
      // Should not be used for locate when override set
      fail('locate runner should not run');
    },
    hostRunner: _CapturingHostRunner((req) => seenExe = req.executable),
  );
  await runner.runInDirectory('/repo', ['status']);
  expect(seenExe, '/custom/git');
});

test('RemoteGitCommandRunner uses injected gitExecutable in run and probe', () async {
  final commands = <String>[];
  final runner = RemoteGitCommandRunner(
    gitExecutable: '/opt/git',
    execShell: (cmd) async {
      commands.add(cmd);
      return _sshOk('/opt/git\n');
    },
  );
  expect(await runner.isAvailable, isTrue);
  expect(commands.first, contains('/opt/git'));
  await runner.runInDirectory('/repo', ['status']);
  expect(commands.last, contains("'/opt/git'"));
});

test('gitCommandRunnerForContext picks LocalGitCommandRunner when native', () {
  configuredGitExecutable = () => '/from/prefs/git';
  addTearDown(() {
    configuredGitExecutable = null;
    AppStorage.resetForTesting();
  });
  AppStorage.installForTesting(
    filesystem: LocalFilesystem(),
    paths: AppPaths('/tmp/teampilot-test'),
    home: '/tmp',
    cwd: '/tmp',
  );
  expect(
    gitCommandRunnerForContext(AppStorage.context),
    isA<LocalGitCommandRunner>(),
  );
  // Executable override behavior is covered by LocalGitCommandRunner(gitExecutable:) above.
});
```

Add a small `_CapturingHostRunner` in the test file if needed.

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd client && flutter test test/services/git/git_command_runner_test.dart
```

- [ ] **Step 3: Implement runner + forContext wiring**

In `git_command_runner.dart`:

```dart
/// Optional absolute/bare git from SessionPreferences.toolchainPaths['git'].
/// Empty/null → auto-discover. Set from app_shell; cleared in tests.
String? Function()? configuredGitExecutable;

String? _resolvedConfiguredGit([String? override]) {
  final raw = (override ?? configuredGitExecutable?.call())?.trim();
  if (raw == null || raw.isEmpty) return null;
  return raw;
}

GitCommandRunner gitCommandRunnerForContext(
  RuntimeContext ctx, {
  String? gitExecutable,
}) {
  final exe = _resolvedConfiguredGit(gitExecutable);
  return switch (ctx.mode) {
    StorageBackendMode.ssh => RemoteGitCommandRunner(
      store: ctx.remoteFileStore!,
      hostKey: ctx.target.id,
      gitExecutable: exe,
    ),
    StorageBackendMode.wsl => WslGitCommandRunner(
      distro: ctx.target.wslDistro,
      gitExecutable: exe,
    ),
    StorageBackendMode.native => LocalGitCommandRunner(gitExecutable: exe),
  };
}
```

Runner constructors: add optional `String? gitExecutable`.

- **Local:** if set, `_git` returns that future/value; skip locator.
- **WSL / Remote:** use `exe ?? 'git'` in `HostRunRequest.executable`.
- **Remote `isAvailable`:** if configured, probe that path (e.g. `command -v '/opt/git'` or `test -x`); else keep existing `command -v git || which git`. Cache key should include executable so override doesn’t reuse stale PATH probe — simplest: include exe in `_hostKey` suffix or separate cache key `$_hostKey|$_exe`.

`GitService.forContext` / `GitWorktreeService.forContext` keep calling `gitCommandRunnerForContext(ctx)` (provider picked up automatically).

Reset `configuredGitExecutable` in `GitService.debugResetExecutableCache` or test `setUp` where needed.

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/services/git/git_command_runner_test.dart \
  test/services/git/git_service_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/git/git_command_runner.dart \
  client/lib/services/git/git_service.dart \
  client/lib/services/git/git_worktree_service.dart \
  client/test/services/git/git_command_runner_test.dart
git commit -m "$(cat <<'EOF'
feat(git): honor configured toolchain git executable

EOF
)"
```

---

### Task 4: Wire `configuredGitExecutable` in app_shell

**Files:**
- Modify: `client/lib/app/app_shell.dart`

- [ ] **Step 1: No new test required** (wiring); manual check: after Task 3 unit tests, grep that provider is set near `sessionPreferencesCubit` creation.

- [ ] **Step 2: Implement**

Near where `sessionPreferencesCubit` exists (after construction, before return of shell):

```dart
configuredGitExecutable = () {
  final path = sessionPreferencesCubit.toolchainPath(
    SessionPreferences.toolchainGit,
  );
  return path.isEmpty ? null : path;
};
```

Import `configuredGitExecutable` from `git_command_runner.dart` and `SessionPreferences`.

**Cache policy (spec):** do **not** invalidate `GitRepoStore` on path change this iteration.

- [ ] **Step 3: Analyze**

```bash
cd client && dart analyze lib/app/app_shell.dart lib/services/git/
```

Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add client/lib/app/app_shell.dart
git commit -m "$(cat <<'EOF'
feat(app): bind configured git executable from session preferences

EOF
)"
```

---

### Task 5: CliInstallerService preferred Node path

**Files:**
- Modify: `client/lib/services/cli/cli_installer_service.dart`
- Modify: `client/test/services/cli/cli_installer_service_test.dart`
- Modify: `client/lib/pages/config/cli_executable_path_settings_row.dart`
- Modify: `client/lib/pages/onboarding/steps/cli_step.dart`
- Modify: `client/lib/services/remote/remote_preflight_cli_install.dart` (only if a `preferredNodePath` can be passed from a nearby cubit; else leave null and document)

- [ ] **Step 1: Write failing tests**

In `cli_installer_service_test.dart`, add cases (adapt to existing fake runner patterns in that file):

```dart
test('preferred node path supplies sibling npm before PATH probe', () async {
  // Arrange installer with preferredNodePath: () => '/opt/node/bin/node'
  // Fake local/ssh runner: if command looks for dirname/npm, return success path
  // Assert install / locate uses '/opt/node/bin/npm' (or npm.cmd on Windows override)
});

test('falls back to PATH npm when preferred node unset', () async {
  // existing behavior still works with preferredNodePath: null
});
```

Read existing tests first and match their `LocalCliInstallRunner` / SSH fake style — do not invent a second harness.

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd client && flutter test test/services/cli/cli_installer_service_test.dart --name preferred
```

- [ ] **Step 3: Implement**

```dart
CliInstallerService({
  ...
  String? Function()? preferredNodePath,
}) : _preferredNodePath = preferredNodePath,
     ...

final String? Function()? _preferredNodePath;
```

In `_locateRemoteNpm` / local npm locate (whichever methods feed install):

1. `final node = _preferredNodePath?.call()?.trim() ?? '';`
2. If non-empty, candidate = `p.dirname(node)` + `/npm` (use `path` package; on Windows host env try `npm.cmd`).
3. If candidate “exists” via a cheap probe (`command -v` / `test -x` over the same runner) return it.
4. Else existing locate chain.

Also if any code path needs the **node** binary itself, prefer `_preferredNodePath` first.

Wire call sites that have `SessionPreferencesCubit` / context:

```dart
// Prefer widget.cubit when already injected (CliExecutablePathSettingsRow):
CliInstallerService(
  sshClientFactory: ...,
  preferredNodePath: () =>
      widget.cubit.toolchainPath(SessionPreferences.toolchainNode),
);
// Onboarding / others: context.read<SessionPreferencesCubit>()...
```

For `remote_preflight_cli_install.dart`: add optional `preferredNodePath` parameter to `buildRemotePreflightCliInstall` and thread from callers if they have prefs; if not available without large refactor, leave default null (still OK — locate works; preference applies where UI constructs installer).

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/services/cli/cli_installer_service_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/cli_installer_service.dart \
  client/test/services/cli/cli_installer_service_test.dart \
  client/lib/pages/config/cli_executable_path_settings_row.dart \
  client/lib/pages/onboarding/steps/cli_step.dart \
  client/lib/services/remote/remote_preflight_cli_install.dart
git commit -m "$(cat <<'EOF'
feat(cli): prefer configured node path when locating npm

EOF
)"
```

---

### Task 6: Verification

- [ ] **Step 1: Run focused suites**

```bash
cd client && flutter test \
  test/services/cli/toolchain_executable_discovery_test.dart \
  test/pages/config/toolchain_path_locate_test.dart \
  test/services/git/git_command_runner_test.dart \
  test/services/git/git_service_test.dart \
  test/services/cli/cli_installer_service_test.dart
```

Expected: all PASS.

- [ ] **Step 2: Broader check**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 3: Done**

No extra commit unless analyze forced fixes — then commit those separately.

---

## Execution notes

- Follow TDD strictly per task (red → green → commit).
- Do not implement per-target toolchain storage.
- `cliExecutablePathLocateRemoteUnsupported` may remain in l10n unused by toolchain; do not delete unless analyze flags unused and no other references.
- Skill reference: @superpowers:subagent-driven-development or @superpowers:executing-plans; @superpowers:test-driven-development on every task.
