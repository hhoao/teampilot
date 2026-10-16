# Remote ACP Adapter Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a personal ACP session on an SSH work machine detect, prompt for, and install the separate ACP adapter (`claude-agent-acp` / `codex-acp`) the same way a missing remote CLI is handled today, then inject the located absolute adapter path at launch.

**Architecture:** Add a `CliBinaryKind` dimension to the remote-readiness pipeline. A personal remote launch that requested ACP now emits a second `RemoteCliRequirement` with `kind: adapter`; the landing gate probes it, the landing panel installs it over SSH, and the resolved path is cached in `targets.json` (`acpAdapterPathOverrides`). At launch, `AcpRuntimeAttach` reads that override and feeds it to `capabilityToPlan`'s `discoveredAdapterPath` so the adapter is spawned by absolute path instead of relying on the non-interactive SSH `PATH`.

**Tech Stack:** Dart / Flutter, `flutter_bloc` cubits, npm-based remote CLI/adapter installers (`CliInstallerService`), `dartssh2` exec transport. Spec: `docs/superpowers/specs/2026-10-16-remote-acp-adapter-readiness-design.md`.

## Global Constraints

- **Never invoke `flutter test` directly** — always `cd client && dart run tool/run_tests.dart <paths/options>`.
- Inner loop is `flutter analyze`; verify one test file with `--plain-name` to narrow; full suite only once before claiming done.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- l10n: edit `client/lib/l10n/app_en.arb` and `app_zh.arb` only; then `cd client && flutter gen-l10n`.
- Only `CliTool.claude` and `CliTool.codex` have `AcpSettingsCapability.usesSeparateAdapter == true`. Cursor / OpenCode / Gemini must never produce an adapter requirement.
- Adapter install-job targets are `ClaudeAcpAdapterInstaller.jobTarget` and `CodexAcpAdapterInstaller.jobTarget`; npm packages `@agentclientprotocol/claude-agent-acp` and `@agentclientprotocol/codex-acp`.
- The connect path (`RemoteCliReadinessService.probe`) must **never install**.
- Diagnostics → `AppLogger`; user-facing copy → l10n. No `print`.
- Test files live under `client/test/...` mirroring `client/lib/...`.

---

### Task 1: `RemoteCliRequirement.kind` + adapter requirement for simple launches

**Files:**
- Modify: `client/lib/services/remote/remote_cli_requirements.dart`
- Test: `client/test/services/remote/remote_cli_requirements_test.dart`

**Interfaces:**
- Consumes: `CliBinaryKind` (`client/lib/models/cli_binary_kind.dart`), `AcpSettingsCapability` (`client/lib/services/cli/registry/capabilities/acp_settings_capability.dart`), `CliToolRegistry`.
- Produces: `RemoteCliRequirement.kind` (`CliBinaryKind`, default `CliBinaryKind.cli`); `cacheKey` = `'<targetId>|<kind.name>|<cliValue>'`; `remoteCliRequirementsForSimpleLaunch({..., bool requestedAcp = false})`.

- [ ] **Step 1: Write the failing test**

Append inside the existing `group('remoteCliRequirementsForSimpleLaunch', ...)` in `client/test/services/remote/remote_cli_requirements_test.dart` (after the `returns empty for local project folder` test, before the group's closing `});`):

```dart
    test('appends an adapter requirement when ACP is requested', () {
      final requirements = remoteCliRequirementsForSimpleLaunch(
        workspace: workspace,
        projectFolderPath: '/remote',
        cli: CliTool.claude,
        requestedAcp: true,
        selectableTargets: [localTarget, sshTarget],
        home: localHome,
        usesPosixPaths: false,
      );

      expect(requirements, hasLength(2));
      expect(requirements[0].kind, CliBinaryKind.cli);
      expect(requirements[1].kind, CliBinaryKind.adapter);
      expect(requirements[1].cli, CliTool.claude);
      expect(
        requirements.map((r) => r.cacheKey).toSet(),
        hasLength(2),
      );
    });

    test('omits the adapter requirement for a CLI without one', () {
      final requirements = remoteCliRequirementsForSimpleLaunch(
        workspace: workspace,
        projectFolderPath: '/remote',
        cli: CliTool.cursor,
        requestedAcp: true,
        selectableTargets: [localTarget, sshTarget],
        home: localHome,
        usesPosixPaths: false,
      );

      expect(requirements, hasLength(1));
      expect(requirements.single.kind, CliBinaryKind.cli);
    });
```

Add this import at the top of the test file (with the other `package:teampilot/...` imports):

```dart
import 'package:teampilot/models/cli_binary_kind.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/remote/remote_cli_requirements_test.dart`
Expected: FAIL — compile error: `requestedAcp` is not a named parameter of `remoteCliRequirementsForSimpleLaunch` / `kind` is not defined on `RemoteCliRequirement`.

- [ ] **Step 3: Write minimal implementation**

In `client/lib/services/remote/remote_cli_requirements.dart`, add imports:

```dart
import '../../models/cli_binary_kind.dart';
import '../cli/registry/capabilities/acp_settings_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
```

Replace the `RemoteCliRequirement` class with:

```dart
/// One required remote binary (a CLI, or a separate ACP adapter) for an SSH
/// machine used by the current placement.
class RemoteCliRequirement {
  const RemoteCliRequirement({
    required this.target,
    required this.cli,
    required this.hostLabel,
    this.kind = CliBinaryKind.cli,
  });

  final RuntimeTarget target;
  final CliTool cli;
  final String hostLabel;
  final CliBinaryKind kind;

  String get cacheKey => '${target.id}|${kind.name}|${cli.value}';
}

/// True when [cli]'s ACP mode needs a separate adapter binary.
bool _cliUsesSeparateAcpAdapter(CliTool cli) {
  final settings = CliToolRegistry.builtIn()
      .capability<AcpSettingsCapability>(cli);
  return settings?.usesSeparateAdapter == true;
}
```

Replace `remoteCliRequirementsForSimpleLaunch` with:

```dart
/// Required remote binaries for a Simple (personal) launch on an SSH folder.
///
/// When [requestedAcp] is true and the CLI needs a separate ACP adapter
/// (Claude / Codex), a second `kind: adapter` requirement is appended.
List<RemoteCliRequirement> remoteCliRequirementsForSimpleLaunch({
  required Workspace workspace,
  required String projectFolderPath,
  required CliTool cli,
  required List<RuntimeTarget> selectableTargets,
  required RuntimeTarget home,
  required bool usesPosixPaths,
  bool requestedAcp = false,
}) {
  final target = sshTargetForProjectFolder(
    workspace: workspace,
    projectFolderPath: projectFolderPath,
    selectableTargets: selectableTargets,
    home: home,
    usesPosixPaths: usesPosixPaths,
  );
  if (target == null) return const [];

  final hostLabel = target.label.trim().isNotEmpty ? target.label : target.id;
  return [
    RemoteCliRequirement(target: target, cli: cli, hostLabel: hostLabel),
    if (requestedAcp && _cliUsesSeparateAcpAdapter(cli))
      RemoteCliRequirement(
        target: target,
        cli: cli,
        hostLabel: hostLabel,
        kind: CliBinaryKind.adapter,
      ),
  ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/remote/remote_cli_requirements_test.dart test/services/remote/remote_cli_requirements_termux_test.dart`
Expected: PASS (all tests in both files).

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/remote/remote_cli_requirements.dart client/test/services/remote/remote_cli_requirements_test.dart
git commit -m "feat(remote-acp): add adapter kind to remote CLI requirements"
```

---

### Task 2: Landing gate requests the adapter for ACP drafts

**Files:**
- Modify: `client/lib/services/chat/launch/pre_send/workspace_landing_launch_gate.dart:160-207`
- Test: `client/test/services/chat/launch/workspace_landing_launch_gate_test.dart`

**Interfaces:**
- Consumes: `RemoteCliRequirement.kind` and `remoteCliRequirementsForSimpleLaunch(requestedAcp:)` (Task 1); `RemoteCliReadinessService.probe({target, cli, kind})` (Task 6 — until Task 6 lands the extra `kind:` argument is not yet accepted, so do Task 6 first if the analyzer complains; the two tasks are merged in one commit if needed).

**Note:** Task 6 adds the `kind` parameter to `probe`. To keep each task's test cycle green, **do Task 6 before Task 2**, or apply Task 6's `probe` signature change together with Task 2. This plan orders Task 6 first — see "Task ordering" at the bottom. The numbering below is logical, not temporal.

- [ ] **Step 1: Write the failing test**

**Extend** `client/test/services/chat/launch/workspace_landing_launch_gate_test.dart`.

Add this import:

```dart
import 'package:teampilot/models/cli_binary_kind.dart';
```

Add this test inside the existing
`group('WorkspaceLandingLaunchGate.asyncRemoteCliBlockForSimple', ...)` (that
group already declares the `sshTarget` and `localHome` locals):

```dart
    test('probes an adapter requirement when the draft requested ACP', () async {
      final probed = <(String, CliBinaryKind)>[];
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: [
          const WorkspaceFolder(path: '/remote', targetId: 'ssh:host-a'),
        ],
        createdAt: 1,
      );

      final block = await gate.asyncRemoteCliBlockForSimple(
        workspace: workspace,
        draft: const LandingLaunchContext(
          isPersonal: true,
          acp: true,
          cli: CliTool.claude,
        ),
        projectFolderPath: '/remote',
        globalPresets: const [],
        selectableTargets: const [sshTarget],
        readiness: _FakeRemoteCliReadiness(
          onProbe: (target, cli, kind) async {
            probed.add((cli.value, kind));
            if (kind == CliBinaryKind.adapter) {
              return RemoteCliMissing(targetId: target.id, cli: cli);
            }
            return RemoteCliReady(
              targetId: target.id,
              cli: cli,
              path: '/home/u/.local/bin/claude',
            );
          },
        ),
        home: localHome,
      );

      expect(probed, [
        ('claude', CliBinaryKind.cli),
        ('claude', CliBinaryKind.adapter),
      ]);
      expect(block, isA<RemoteCliMissingLaunchBlock>());
      expect(
        (block! as RemoteCliMissingLaunchBlock).missing.single.kind,
        CliBinaryKind.adapter,
      );
    });
```

Replace the existing `_FakeRemoteCliReadiness` class (bottom of the file) with:

```dart
class _FakeRemoteCliReadiness extends RemoteCliReadinessService {
  _FakeRemoteCliReadiness({this.alwaysReady = false, this.onProbe})
    : super(
        registry: CliToolRegistry.builtIn(),
        sshClientFactory: _ThrowingSshClientFactory(),
        profileById: (_) => null,
        cliPathOverride: (_, __) async => null,
        setCliPathOverride: (_, __, ___) async {},
      );

  final bool alwaysReady;
  final Future<RemoteCliReadiness> Function(
    RuntimeTarget target,
    CliTool cli,
    CliBinaryKind kind,
  )? onProbe;

  @override
  Future<RemoteCliReadiness> probe({
    required RuntimeTarget target,
    required CliTool cli,
    CliBinaryKind kind = CliBinaryKind.cli,
  }) async {
    final custom = onProbe;
    if (custom != null) return custom(target, cli, kind);
    if (alwaysReady) {
      return RemoteCliReady(
        targetId: target.id,
        cli: cli,
        path: '/bin/${cli.value}',
      );
    }
    return RemoteCliMissing(targetId: target.id, cli: cli);
  }
}
```

The two existing tests still compile — they call
`_FakeRemoteCliReadiness(alwaysReady: false)` / `(alwaysReady: true)`.

**Note:** This test needs Task 6's `probe(kind:)` signature; run Task 6's service
change first (see "Task ordering").

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/workspace_landing_launch_gate_test.dart --plain-name "probes an adapter requirement"`
Expected: FAIL — `probed` only contains the CLI entry (no adapter requirement is generated).

- [ ] **Step 3: Write minimal implementation**

In `client/lib/services/chat/launch/pre_send/workspace_landing_launch_gate.dart`, change the `asyncRemoteCliBlockForSimple` requirements call to pass the draft's ACP flag:

```dart
    final requirements = remoteCliRequirementsForSimpleLaunch(
      workspace: workspace,
      projectFolderPath: projectFolderPath,
      cli: identity.cli,
      requestedAcp: draft.acp,
      selectableTargets: selectableTargets,
      home: home,
      usesPosixPaths: _storage.usesPosixPaths,
    );
```

and change `_probeRemoteCliRequirements` to forward the kind:

```dart
    for (final requirement in requirements) {
      final result = await readiness.probe(
        target: requirement.target,
        cli: requirement.cli,
        kind: requirement.kind,
      );
      if (result is RemoteCliMissing || result is RemoteCliFailed) {
        missing.add(requirement);
      }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/workspace_landing_launch_gate_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/chat/launch/pre_send/workspace_landing_launch_gate.dart client/test/services/chat/launch/workspace_landing_launch_gate_test.dart
git commit -m "feat(remote-acp): probe remote adapter readiness from the landing gate"
```

---

### Task 3: `AcpAdapterDiscovery.locateRemote`

**Files:**
- Modify: `client/lib/services/cli/acp_adapter_discovery.dart`
- Test: `client/test/services/cli/acp_adapter_discovery_test.dart`

**Interfaces:**
- Consumes: `DefaultRemoteCliLocator` and `SshCommandRunner` (`client/lib/services/cli/remote_cli_locator.dart`), `AppLogger` (`client/lib/utils/logging/logger.dart`).
- Produces: `Future<Map<CliTool, String>> AcpAdapterDiscovery.locateRemote({required SshCommandRunner run})` — one entry per separate-adapter CLI whose adapter probe returned a non-empty path.

- [ ] **Step 1: Write the failing test**

Replace `client/test/services/cli/acp_adapter_discovery_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/acp_adapter_discovery.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('locateLocal returns only absolute Claude/Codex adapter hits', () async {
    final discovery = AcpAdapterDiscovery(registry: CliToolRegistry.builtIn());
    final located = await discovery.locateLocal(
      environment: const {'PATH': '/opt/bin', 'HOME': '/home/u'},
      fileExists: (p) => p == '/opt/bin/claude-agent-acp',
      isWindows: false,
    );
    expect(located[CliTool.claude], '/opt/bin/claude-agent-acp');
    expect(located.containsKey(CliTool.codex), isFalse);
    expect(located.containsKey(CliTool.cursor), isFalse);
  });

  test('locateRemote maps only separate-adapter CLIs via the probe', () async {
    final discovery = AcpAdapterDiscovery(registry: CliToolRegistry.builtIn());
    final located = await discovery.locateRemote(
      run: (command) async {
        if (command.contains('claude-agent-acp')) {
          return const SshCommandResult(
            exitCode: 0,
            stdout: '/home/u/.local/bin/claude-agent-acp\n',
          );
        }
        return const SshCommandResult(exitCode: 1, stdout: '');
      },
    );

    expect(located[CliTool.claude], '/home/u/.local/bin/claude-agent-acp');
    expect(located.containsKey(CliTool.codex), isFalse);
    expect(located.containsKey(CliTool.cursor), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/acp_adapter_discovery_test.dart`
Expected: FAIL — `locateRemote` is not defined.

- [ ] **Step 3: Write minimal implementation**

Replace `client/lib/services/cli/acp_adapter_discovery.dart` with:

```dart
import '../../models/team_config.dart';
import '../../utils/logging/logger.dart';
import 'acp_adapter_locator.dart';
import 'registry/capabilities/acp_settings_capability.dart';
import 'registry/capabilities/cli_executable_capability.dart';
import 'registry/cli_tool_registry.dart';
import 'remote_cli_locator.dart';

class AcpAdapterDiscovery {
  AcpAdapterDiscovery({required CliToolRegistry registry}) : _registry = registry;

  final CliToolRegistry _registry;

  Future<Map<CliTool, String>> locateLocal({
    Map<String, String>? environment,
    bool Function(String path)? fileExists,
    bool? isWindows,
  }) async {
    final located = <CliTool, String>{};
    for (final def in _registry.launchable) {
      final settings = _registry.capability<AcpSettingsCapability>(def.id);
      if (settings == null ||
          !settings.usesSeparateAdapter ||
          settings.adapterExecutableName == null ||
          settings.adapterExecutableName!.isEmpty) {
        continue;
      }
      final path = locateAcpAdapter(
        name: settings.adapterExecutableName!,
        environment: environment,
        fileExists: fileExists,
        isWindows: isWindows,
      );
      if (path.contains('/') || path.contains(r'\')) {
        located[def.id] = path;
      }
    }
    return located;
  }

  /// Locates separate ACP adapters (Claude / Codex) on a remote host over
  /// [run]. Entries are omitted when the probe cannot resolve an absolute path.
  Future<Map<CliTool, String>> locateRemote({
    required SshCommandRunner run,
  }) async {
    final located = <CliTool, String>{};
    for (final def in _registry.launchable) {
      final settings = _registry.capability<AcpSettingsCapability>(def.id);
      final name = settings?.adapterExecutableName?.trim() ?? '';
      if (settings == null || !settings.usesSeparateAdapter || name.isEmpty) {
        continue;
      }
      try {
        final path =
            (await DefaultRemoteCliLocator(name).locate(run))?.trim() ?? '';
        if (path.isNotEmpty) located[def.id] = path;
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[acp-adapter] remote locate failed cli=${def.id.value} name=$name',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return located;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/acp_adapter_discovery_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/cli/acp_adapter_discovery.dart client/test/services/cli/acp_adapter_discovery_test.dart
git commit -m "feat(remote-acp): locate ACP adapters on remote hosts"
```

---

### Task 4: `buildRemotePreflightAdapterInstall`

**Files:**
- Modify: `client/lib/services/remote/remote_preflight_cli_install.dart`
- Test: `client/test/services/remote/remote_preflight_cli_install_test.dart` (extend)

**Interfaces:**
- Consumes: `CliInstallerService.installAdapter` (`client/lib/services/cli/cli_installer_service.dart:89`), `NpmInstallerCapability`, `ClaudeAcpAdapterInstaller`.
- Produces: `RemoteInstallAction buildRemotePreflightAdapterInstall({required NpmInstallerCapability installer, required SshProfile profile, String? Function()? preferredNodePath})`.

- [ ] **Step 1: Write the failing test**

**Extend** `client/test/services/remote/remote_preflight_cli_install_test.dart`
(reuse its `_isTermuxProbe` / `_isNodeBootstrap` / `_isBareNpmLocate` matchers).

Add this import:

```dart
import 'package:teampilot/services/cli/claude/capabilities/acp_adapter_installer.dart';
```

Add these two tests inside `main()` (after the first
`remote preflight install bootstraps node then npm-installs claude` test):

```dart
  test('adapter preflight installs the npm package and returns the path',
      () async {
    final calls = <String>[];
    final install = buildRemotePreflightAdapterInstall(
      installer: const ClaudeAcpAdapterInstaller(),
      profile: profile,
    );

    final path = await install(
      run: (command) async {
        calls.add(command);
        if (_isTermuxProbe(command)) {
          return const SshCommandResult(exitCode: 0, stdout: 'TERMUX=0\n');
        }
        if (_isNodeBootstrap(command)) {
          return const SshCommandResult(exitCode: 0, stdout: '10.0.0\n');
        }
        if (_isBareNpmLocate(command)) {
          return const SshCommandResult(exitCode: 1, stdout: '');
        }
        if (command.contains('npm install -g --prefix') &&
            command.contains('@agentclientprotocol/claude-agent-acp')) {
          return const SshCommandResult(exitCode: 0, stdout: '');
        }
        if (command.startsWith('sh -c') &&
            command.contains('command -v claude-agent-acp')) {
          return const SshCommandResult(
            exitCode: 0,
            stdout: '/home/dev/.local/bin/claude-agent-acp\n',
          );
        }
        return const SshCommandResult(exitCode: 1, stdout: '');
      },
      onProgress: (_) {},
    );

    expect(path, '/home/dev/.local/bin/claude-agent-acp');
    expect(
      calls.any(
        (c) =>
            c.contains('npm install -g --prefix') &&
            c.contains('@agentclientprotocol/claude-agent-acp'),
      ),
      isTrue,
    );
  });

  test('adapter preflight reports a missing executable path', () async {
    final install = buildRemotePreflightAdapterInstall(
      installer: const ClaudeAcpAdapterInstaller(),
      profile: profile,
    );

    await expectLater(
      () => install(
        run: (command) async {
          if (_isTermuxProbe(command)) {
            return const SshCommandResult(exitCode: 0, stdout: 'TERMUX=0\n');
          }
          if (_isNodeBootstrap(command)) {
            return const SshCommandResult(exitCode: 0, stdout: '10.0.0\n');
          }
          if (_isBareNpmLocate(command)) {
            return const SshCommandResult(exitCode: 1, stdout: '');
          }
          if (command.contains('npm install -g --prefix')) {
            return const SshCommandResult(exitCode: 0, stdout: '');
          }
          return const SshCommandResult(exitCode: 1, stdout: '');
        },
        onProgress: (_) {},
      ),
      throwsA(isA<StateError>()),
    );
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/remote/remote_preflight_cli_install_test.dart --plain-name "adapter preflight installs"`
Expected: FAIL — `buildRemotePreflightAdapterInstall` is not defined.

- [ ] **Step 3: Write minimal implementation**

In `client/lib/services/remote/remote_preflight_cli_install.dart`, add the import:

```dart
import '../cli/registry/installer/npm_installer_capability.dart';
```

and add this function after `buildRemotePreflightCliInstall` (before `remoteCliInstallProgressLabel`):

```dart
/// Remote install of a separate ACP adapter npm package (Claude / Codex) over
/// an existing preflight [SshCommandRunner]. Twin of
/// [buildRemotePreflightCliInstall] for `CliInstallerService.installAdapter`.
RemoteInstallAction buildRemotePreflightAdapterInstall({
  required NpmInstallerCapability installer,
  required SshProfile profile,
  String? Function()? preferredNodePath,
}) {
  return ({required run, required onProgress}) async {
    final service = CliInstallerService(
      hostEnvironment: HostExecutionEnvironment.resolve(
        isWindowsHost: false,
        forceRemoteUnix: true,
      ),
      sshRunner: preflightSshInstallRunner(profile, run),
      sshClientFactory: null,
      preferredNodePath: preferredNodePath,
    );
    final result = await service.installAdapter(
      installer: installer,
      mode: CliInstallMode.ssh,
      sshProfile: profile,
      onProgress: onProgress,
    );
    if (!result.success) {
      throw StateError(result.message);
    }
    final path = result.executablePath?.trim() ?? '';
    if (path.isEmpty) {
      throw StateError(
        '${installer.displayName} install finished but did not report an '
        'executable path.',
      );
    }
    return path;
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/remote/remote_preflight_cli_install_test.dart`
Expected: PASS (the four preflight tests, including the two new adapter ones).

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/remote/remote_preflight_cli_install.dart client/test/services/remote/remote_preflight_cli_install_test.dart
git commit -m "feat(remote-acp): add remote preflight adapter install action"
```

---

### Task 5: `targets.json` adapter path overrides + remember helper

**Files:**
- Modify: `client/lib/services/storage/targets_repository.dart`
- Modify: `client/lib/services/remote/remember_remote_cli_path.dart`
- Test: `client/test/services/storage/targets_repository_p3c_test.dart`
- Test: `client/test/services/remote/remember_remote_cli_path_test.dart`

**Interfaces:**
- Produces:
  - `TargetsRegistryFile.acpAdapterPathOverrides` (`Map<String, Map<String, String>>`, JSON key `acpAdapterPathOverrides`, omitted from `toJson` when empty).
  - `TargetsRepository.acpAdapterPathOverride(String targetId, String cliValue) → Future<String?>`.
  - `TargetsRepository.setAcpAdapterPathOverride(String targetId, String cliValue, String path) → Future<void>` (empty path removes).
  - `rememberRemoteAcpAdapterPathIfNeeded({targetId, cli, resolvedPath, readAcpAdapterPathOverride, writeAcpAdapterPathOverride})`.

- [ ] **Step 1: Write the failing tests**

Append inside `main()` of `client/test/services/storage/targets_repository_p3c_test.dart` (before the final `}`):

```dart
  test('acp adapter path override round-trips per target+cli and clears',
      () async {
    expect(await repo.acpAdapterPathOverride('ssh:p1', 'claude'), isNull);

    await repo.setAcpAdapterPathOverride(
      'ssh:p1',
      'claude',
      '/opt/claude-agent-acp',
    );
    await repo.setAcpAdapterPathOverride('ssh:p1', 'codex', '/opt/codex-acp');
    expect(
      await repo.acpAdapterPathOverride('ssh:p1', 'claude'),
      '/opt/claude-agent-acp',
    );
    expect(await repo.acpAdapterPathOverride('ssh:p2', 'claude'), isNull);

    await repo.setAcpAdapterPathOverride('ssh:p1', 'claude', '');
    expect(await repo.acpAdapterPathOverride('ssh:p1', 'claude'), isNull);
    expect(
      await repo.acpAdapterPathOverride('ssh:p1', 'codex'),
      '/opt/codex-acp',
    );
  });

  test('omits empty acpAdapterPathOverrides from json', () async {
    final reloaded = await repo.load();
    expect(reloaded.toJson().containsKey('acpAdapterPathOverrides'), isFalse);
  });
```

Append inside `main()` of `client/test/services/remote/remember_remote_cli_path_test.dart`:

```dart
  test('persists a resolved ACP adapter path', () async {
    final writes = <(String, String, String)>[];
    await rememberRemoteAcpAdapterPathIfNeeded(
      targetId: 'ssh:work',
      cli: CliTool.claude,
      resolvedPath: '/home/dev/.local/bin/claude-agent-acp',
      readAcpAdapterPathOverride: (_, __) async => null,
      writeAcpAdapterPathOverride: (targetId, cliValue, path) async {
        writes.add((targetId, cliValue, path));
      },
    );
    expect(writes, [
      ('ssh:work', 'claude', '/home/dev/.local/bin/claude-agent-acp'),
    ]);
  });

  test('skips a resolved ACP adapter path that is empty', () async {
    var writeCount = 0;
    await rememberRemoteAcpAdapterPathIfNeeded(
      targetId: 'ssh:work',
      cli: CliTool.claude,
      resolvedPath: '  ',
      readAcpAdapterPathOverride: (_, __) async => null,
      writeAcpAdapterPathOverride: (_, __, ___) async => writeCount++,
    );
    expect(writeCount, 0);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/storage/targets_repository_p3c_test.dart test/services/remote/remember_remote_cli_path_test.dart`
Expected: FAIL — undefined `acpAdapterPathOverride` / `rememberRemoteAcpAdapterPathIfNeeded`.

- [ ] **Step 3: Write minimal implementation**

In `client/lib/services/storage/targets_repository.dart`:

Add to the `TargetsRegistryFile` constructor and fields:

```dart
  const TargetsRegistryFile({
    this.schemaVersion = 1,
    this.targets = const [],
    this.credentialOptIn = const [],
    this.installOptOut = const [],
    this.cliPathOverrides = const {},
    this.acpAdapterPathOverrides = const {},
  });
```

```dart
  /// Per-target manual ACP adapter path overrides —
  /// `targetId → {cliValue → absolute path}` (the separate ACP adapter binary
  /// located/installed on that host).
  final Map<String, Map<String, String>> acpAdapterPathOverrides;
```

In `fromJson`, after the `cliPathOverrides` parse, add:

```dart
    final adapterOverrides = json['acpAdapterPathOverrides'];
```

and pass to the constructor:

```dart
      acpAdapterPathOverrides: adapterOverrides is Map<String, Object?>
          ? {
              for (final e in adapterOverrides.entries)
                if (e.value is Map<String, Object?>)
                  e.key: {
                    for (final c in (e.value as Map<String, Object?>).entries)
                      c.key: '${c.value}',
                  },
            }
          : const {},
```

In `toJson`, add:

```dart
    if (acpAdapterPathOverrides.isNotEmpty)
      'acpAdapterPathOverrides': acpAdapterPathOverrides,
```

In `copyWith`, add the parameter and pass-through:

```dart
  TargetsRegistryFile copyWith({
    List<RuntimeTarget>? targets,
    List<String>? credentialOptIn,
    List<String>? installOptOut,
    Map<String, Map<String, String>>? cliPathOverrides,
    Map<String, Map<String, String>>? acpAdapterPathOverrides,
  }) => TargetsRegistryFile(
    schemaVersion: schemaVersion,
    targets: targets ?? this.targets,
    credentialOptIn: credentialOptIn ?? this.credentialOptIn,
    installOptOut: installOptOut ?? this.installOptOut,
    cliPathOverrides: cliPathOverrides ?? this.cliPathOverrides,
    acpAdapterPathOverrides:
        acpAdapterPathOverrides ?? this.acpAdapterPathOverrides,
  );
```

At the end of `TargetsRepository`, add:

```dart
  // ── P3c: per-target manual ACP adapter path override ───────────────────────

  Future<String?> acpAdapterPathOverride(String targetId, String cliValue) async =>
      (await load()).acpAdapterPathOverrides[targetId]?[cliValue];

  Future<void> setAcpAdapterPathOverride(
    String targetId,
    String cliValue,
    String path,
  ) async {
    final file = await load();
    final overrides = {
      for (final e in file.acpAdapterPathOverrides.entries) e.key: {...e.value},
    };
    final forTarget = overrides.putIfAbsent(targetId, () => {});
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      forTarget.remove(cliValue);
      if (forTarget.isEmpty) overrides.remove(targetId);
    } else {
      forTarget[cliValue] = trimmed;
    }
    await save(file.copyWith(acpAdapterPathOverrides: overrides));
  }
```

In `client/lib/services/remote/remember_remote_cli_path.dart`, append:

```dart
/// Caches a resolved remote ACP adapter path into `targets.json` when it
/// differs from the stored per-target override.
Future<void> rememberRemoteAcpAdapterPathIfNeeded({
  required String targetId,
  required CliTool cli,
  required String resolvedPath,
  required Future<String?> Function(String targetId, String cliValue)
  readAcpAdapterPathOverride,
  required Future<void> Function(String targetId, String cliValue, String path)
  writeAcpAdapterPathOverride,
}) async {
  final trimmed = resolvedPath.trim();
  if (trimmed.isEmpty) return;
  final stored =
      (await readAcpAdapterPathOverride(targetId, cli.value) ?? '').trim();
  if (trimmed == stored) return;
  await writeAcpAdapterPathOverride(targetId, cli.value, trimmed);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/storage/targets_repository_p3c_test.dart test/services/storage/targets_repository_test.dart test/services/remote/remember_remote_cli_path_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/storage/targets_repository.dart client/lib/services/remote/remember_remote_cli_path.dart client/test/services/storage/targets_repository_p3c_test.dart client/test/services/remote/remember_remote_cli_path_test.dart
git commit -m "feat(remote-acp): persist per-target ACP adapter path overrides"
```

---

### Task 6: Kind-aware `RemoteCliReadinessService` (probe / locate / install)

**Files:**
- Modify: `client/lib/services/remote/remote_cli_readiness.dart`
- Test: `client/test/services/remote/remote_cli_readiness_adapter_test.dart` (create)

**Interfaces:**
- Consumes: `AcpAdapterDiscovery.locateRemote` (Task 3), `buildRemotePreflightAdapterInstall` (Task 4), `rememberRemoteAcpAdapterPathIfNeeded` (Task 5), `CliBinaryKind`.
- Produces:
  - Constructor gains optional `acpAdapterPathOverride`, `setAcpAdapterPathOverride`, `adapterInstallActionBuilder`.
  - `probe({required RuntimeTarget target, required CliTool cli, CliBinaryKind kind = CliBinaryKind.cli})`.
  - `locate({required RuntimeTarget target, required CliTool cli, CliBinaryKind kind = CliBinaryKind.cli})` — locate + remember, never installs.
  - `install({required RuntimeTarget target, required CliTool cli, CliBinaryKind kind = CliBinaryKind.cli, onProgress})`.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/remote/remote_cli_readiness_adapter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_binary_kind.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/cli/remote_cli_installer.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/remote/remote_cli_readiness.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';

void main() {
  const target = RuntimeTarget(
    id: 'ssh:host-a',
    label: 'host',
    kind: RuntimeKind.ssh,
    sshProfileId: 'host-a',
  );

  late Map<String, String> overrides;
  late RemoteCliReadinessService service;

  RemoteCliReadinessService build({
    required SshCommandRunner run,
    RemoteInstallAction? adapterInstall,
  }) {
    overrides = {};
    return RemoteCliReadinessService(
      registry: CliToolRegistry.builtIn(),
      sshClientFactory: _ThrowingSshClientFactory(),
      profileById: (id) => id == 'host-a'
          ? const SshProfile(
              id: 'host-a',
              name: 'host',
              host: 'host',
              username: 'u',
            )
          : null,
      cliPathOverride: (_, __) async => null,
      setCliPathOverride: (_, __, ___) async {},
      acpAdapterPathOverride: (_, cli) async => overrides[cli],
      setAcpAdapterPathOverride: (_, cli, path) async {
        overrides[cli] = path;
      },
      adapterInstallActionBuilder: adapterInstall == null
          ? null
          : (_, __, ___) => adapterInstall,
      remoteRunnerFor: (_, {required includeStderr}) => run,
    );
  }

  test('probe(adapter) reports ready when the adapter is on the host', () async {
    service = build(
      run: (command) async {
        if (command.contains('claude-agent-acp')) {
          return const SshCommandResult(
            exitCode: 0,
            stdout: '/home/u/.local/bin/claude-agent-acp\n',
          );
        }
        return const SshCommandResult(exitCode: 1, stdout: '');
      },
    );

    final result = await service.probe(
      target: target,
      cli: CliTool.claude,
      kind: CliBinaryKind.adapter,
    );

    expect(result, isA<RemoteCliReady>());
    expect((result as RemoteCliReady).path,
        '/home/u/.local/bin/claude-agent-acp');
  });

  test('probe(adapter) reports missing when nothing resolves', () async {
    service = build(
      run: (_) async => const SshCommandResult(exitCode: 1, stdout: ''),
    );

    final result = await service.probe(
      target: target,
      cli: CliTool.claude,
      kind: CliBinaryKind.adapter,
    );

    expect(result, isA<RemoteCliMissing>());
  });

  test('probe(adapter) uses a stored override without probing', () async {
    var probed = false;
    service = build(
      run: (_) async {
        probed = true;
        return const SshCommandResult(exitCode: 1, stdout: '');
      },
    );
    overrides['claude'] = '/opt/claude-agent-acp';

    final result = await service.probe(
      target: target,
      cli: CliTool.claude,
      kind: CliBinaryKind.adapter,
    );

    expect((result as RemoteCliReady).path, '/opt/claude-agent-acp');
    expect(probed, isFalse);
  });

  test('install(adapter) installs and remembers the path', () async {
    var installCalls = 0;
    service = build(
      run: (_) async => const SshCommandResult(exitCode: 1, stdout: ''),
      adapterInstall: ({required run, required onProgress}) async {
        installCalls++;
        return '/home/u/.local/bin/claude-agent-acp';
      },
    );

    final result = await service.install(
      target: target,
      cli: CliTool.claude,
      kind: CliBinaryKind.adapter,
    );

    expect(installCalls, 1);
    expect((result as RemoteCliReady).path,
        '/home/u/.local/bin/claude-agent-acp');
    expect(overrides['claude'], '/home/u/.local/bin/claude-agent-acp');
  });

  test('install(adapter) fails for a CLI without an adapter installer',
      () async {
    service = build(
      run: (_) async => const SshCommandResult(exitCode: 1, stdout: ''),
    );

    final result = await service.install(
      target: target,
      cli: CliTool.cursor,
      kind: CliBinaryKind.adapter,
    );

    expect(result, isA<RemoteCliFailed>());
  });
}

class _ThrowingSshClientFactory implements SshClientFactory {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/remote/remote_cli_readiness_adapter_test.dart`
Expected: FAIL — `kind` is not a parameter of `probe`; `locate`/adapter branches are missing.

- [ ] **Step 3: Write minimal implementation**

> **Keep the tree compiling:** changing `probe`'s signature breaks the existing
> `@override probe({required target, required cli})` in
> `client/test/services/chat/launch/workspace_landing_launch_gate_test.dart`
> (line ~297). Add `CliBinaryKind kind = CliBinaryKind.cli` to that override
> (the parameter is ignored) in this task so `flutter analyze` stays clean.
> Task 2 later extends the same fake; do not otherwise change that file here.

Replace `client/lib/services/remote/remote_cli_readiness.dart` with:

```dart
import '../../models/cli_binary_kind.dart';
import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../../models/team_config.dart';
import '../../utils/logging/logger.dart';
import '../cli/acp_adapter_discovery.dart';
import '../cli/installer_types.dart';
import '../cli/registry/capabilities/acp_settings_capability.dart';
import '../cli/registry/capabilities/cli_executable_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../cli/registry/installer/npm_installer_capability.dart';
import '../cli/remote_cli_installer.dart';
import '../cli/remote_cli_locator.dart';
import '../ssh/ssh_client_factory.dart';
import 'remote_preflight_cli_install.dart';
import 'remember_remote_cli_path.dart';

/// Result of probing or installing a binary on one runtime target.
sealed class RemoteCliReadiness {
  const RemoteCliReadiness({required this.targetId, required this.cli});

  final String targetId;
  final CliTool cli;
}

final class RemoteCliProbing extends RemoteCliReadiness {
  const RemoteCliProbing({required super.targetId, required super.cli});
}

final class RemoteCliReady extends RemoteCliReadiness {
  const RemoteCliReady({
    required super.targetId,
    required super.cli,
    required this.path,
  });

  final String path;
}

final class RemoteCliMissing extends RemoteCliReadiness {
  const RemoteCliMissing({required super.targetId, required super.cli});
}

final class RemoteCliInstalling extends RemoteCliReadiness {
  const RemoteCliInstalling({
    required super.targetId,
    required super.cli,
    this.progress,
  });

  final CliInstallProgress? progress;
}

final class RemoteCliFailed extends RemoteCliReadiness {
  const RemoteCliFailed({
    required super.targetId,
    required super.cli,
    required this.message,
  });

  final String message;
}

/// Test seam: build the remote command runner for a profile without dartssh2.
typedef RemoteRunnerForProfile =
    SshCommandRunner Function(SshProfile profile, {required bool includeStderr});

/// Builds the adapter install action for a profile over an existing runner.
typedef AdapterInstallActionBuilder =
    RemoteInstallAction Function(
      NpmInstallerCapability installer,
      SshProfile profile,
      SshCommandRunner run,
    );

/// Locate / user-driven install of remote binaries (CLIs and separate ACP
/// adapters) for the Machines panel and the landing gate.
///
/// Connect path must not call [install] — only [probe].
class RemoteCliReadinessService {
  RemoteCliReadinessService({
    required this.registry,
    required this.sshClientFactory,
    required this.profileById,
    required this.cliPathOverride,
    required this.setCliPathOverride,
    Future<String?> Function(String targetId, String cliValue)?
    acpAdapterPathOverride,
    Future<void> Function(String targetId, String cliValue, String path)?
    setAcpAdapterPathOverride,
    RemoteCliInstaller? installer,
    RemoteInstallAction Function(CliTool cli, SshProfile profile, SshCommandRunner run)?
    installActionBuilder,
    AdapterInstallActionBuilder? adapterInstallActionBuilder,
    RemoteRunnerForProfile? remoteRunnerFor,
  }) : _installer =
           installer ??
           RemoteCliInstaller(locator: RemoteCliLocator(registry: registry)),
       _installActionBuilder = installActionBuilder,
       _adapterInstallActionBuilder = adapterInstallActionBuilder,
       _remoteRunnerFor = remoteRunnerFor,
       acpAdapterPathOverride =
           acpAdapterPathOverride ?? ((_, __) async => null),
       setAcpAdapterPathOverride =
           setAcpAdapterPathOverride ?? ((_, __, ___) async {});

  final CliToolRegistry registry;
  final SshClientFactory sshClientFactory;
  final SshProfile? Function(String profileId) profileById;
  final Future<String?> Function(String targetId, String cliValue)
  cliPathOverride;
  final Future<void> Function(String targetId, String cliValue, String path)
  setCliPathOverride;
  final Future<String?> Function(String targetId, String cliValue)
  acpAdapterPathOverride;
  final Future<void> Function(String targetId, String cliValue, String path)
  setAcpAdapterPathOverride;

  final RemoteCliInstaller _installer;
  final RemoteInstallAction Function(CliTool cli, SshProfile profile, SshCommandRunner run)?
  _installActionBuilder;
  final AdapterInstallActionBuilder? _adapterInstallActionBuilder;
  final RemoteRunnerForProfile? _remoteRunnerFor;

  Future<SshCommandRunner> _runnerFor(
    SshProfile profile, {
    required bool includeStderr,
  }) async {
    final override = _remoteRunnerFor;
    if (override != null) return override(profile, includeStderr: includeStderr);
    final client = await sshClientFactory.clientForStorage(profile);
    return RemoteCliLocator.getRunnerForClient(
      client,
      includeStderr: includeStderr,
    );
  }

  /// Locate only. Never installs.
  Future<RemoteCliReadiness> probe({
    required RuntimeTarget target,
    required CliTool cli,
    CliBinaryKind kind = CliBinaryKind.cli,
  }) async {
    if (!usesSshTransport(target.kind)) {
      throw ArgumentError(
        'probe requires an SSH transport target, got ${target.id}',
      );
    }
    try {
      final path = kind == CliBinaryKind.adapter
          ? await _locateAdapter(target: target, cli: cli)
          : await _locateCli(target: target, cli: cli);
      if (path == null) {
        return RemoteCliMissing(targetId: target.id, cli: cli);
      }
      return RemoteCliReady(targetId: target.id, cli: cli, path: path);
    } on Object catch (e, st) {
      final message = remoteCliFailureMessage(e);
      appLogger.w(
        '[remote-cli] probe failed target=${target.id} cli=${cli.value} '
        'kind=${kind.name}: $message',
        error: e,
        stackTrace: st,
      );
      return RemoteCliFailed(targetId: target.id, cli: cli, message: message);
    }
  }

  /// Locate and remember the resolved path. Never installs.
  Future<RemoteCliReadiness> locate({
    required RuntimeTarget target,
    required CliTool cli,
    CliBinaryKind kind = CliBinaryKind.cli,
  }) async {
    if (!usesSshTransport(target.kind)) {
      throw ArgumentError(
        'locate requires an SSH transport target, got ${target.id}',
      );
    }
    try {
      final profile = profileById(target.sshProfileId ?? '');
      if (profile == null) {
        throw StateError('No SSH profile for target "${target.id}".');
      }
      final run = await _runnerFor(profile, includeStderr: false);
      final path = kind == CliBinaryKind.adapter
          ? await _locateAdapterWithRun(target: target, cli: cli, run: run)
          : await _locateCliWithRun(target: target, cli: cli, run: run);
      if (path == null) {
        return RemoteCliMissing(targetId: target.id, cli: cli);
      }
      if (kind == CliBinaryKind.adapter) {
        await rememberRemoteAcpAdapterPathIfNeeded(
          targetId: target.id,
          cli: cli,
          resolvedPath: path,
          readAcpAdapterPathOverride: acpAdapterPathOverride,
          writeAcpAdapterPathOverride: setAcpAdapterPathOverride,
        );
      } else {
        await rememberRemoteCliPathIfNeeded(
          targetId: target.id,
          cli: cli,
          resolvedPath: path,
          readCliPathOverride: cliPathOverride,
          writeCliPathOverride: setCliPathOverride,
        );
      }
      return RemoteCliReady(targetId: target.id, cli: cli, path: path);
    } on Object catch (e, st) {
      final message = remoteCliFailureMessage(e);
      appLogger.w(
        '[remote-cli] locate failed target=${target.id} cli=${cli.value} '
        'kind=${kind.name}: $message',
        error: e,
        stackTrace: st,
      );
      return RemoteCliFailed(targetId: target.id, cli: cli, message: message);
    }
  }

  /// User-driven install on [target]. Remembers the resolved path on success.
  Future<RemoteCliReadiness> install({
    required RuntimeTarget target,
    required CliTool cli,
    CliBinaryKind kind = CliBinaryKind.cli,
    void Function(CliInstallProgress progress)? onProgress,
  }) {
    if (kind == CliBinaryKind.adapter) {
      return _installAdapter(
        target: target,
        cli: cli,
        onProgress: onProgress,
      );
    }
    return _installCli(target: target, cli: cli, onProgress: onProgress);
  }

  Future<RemoteCliReadiness> _installCli({
    required RuntimeTarget target,
    required CliTool cli,
    void Function(CliInstallProgress progress)? onProgress,
  }) async {
    if (!usesSshTransport(target.kind)) {
      throw ArgumentError(
        'install requires an SSH transport target, got ${target.id}',
      );
    }
    final profile = profileById(target.sshProfileId ?? '');
    if (profile == null) {
      return RemoteCliFailed(
        targetId: target.id,
        cli: cli,
        message: 'No SSH profile for target "${target.id}".',
      );
    }
    final supportsInstaller =
        registry.capability<CliExecutableCapability>(cli)?.supportsInstaller ??
        false;
    if (!supportsInstaller) {
      return RemoteCliFailed(
        targetId: target.id,
        cli: cli,
        message:
            '${cli.value} has no in-app installer; set a manual CLI path '
            'for this target.',
      );
    }

    try {
      final run = await _runnerFor(profile, includeStderr: true);
      final storedPath = (await cliPathOverride(target.id, cli.value) ?? '')
          .trim();
      final path = await _installer.ensure(
        cli: cli,
        run: run,
        optIn: true,
        supportsInstaller: true,
        install: _installActionBuilder?.call(cli, profile, run) ??
            buildRemotePreflightCliInstall(
              registry: registry,
              profile: profile,
              cli: cli,
            ),
        manualPathOverride: storedPath,
        onProgress: onProgress,
      );
      await rememberRemoteCliPathIfNeeded(
        targetId: target.id,
        cli: cli,
        resolvedPath: path,
        readCliPathOverride: cliPathOverride,
        writeCliPathOverride: setCliPathOverride,
      );
      return RemoteCliReady(targetId: target.id, cli: cli, path: path);
    } on Object catch (e, st) {
      final message = remoteCliFailureMessage(e);
      appLogger.w(
        '[remote-cli] install failed target=${target.id} cli=${cli.value}: '
        '$message',
        error: e,
        stackTrace: st,
      );
      return RemoteCliFailed(targetId: target.id, cli: cli, message: message);
    }
  }

  Future<RemoteCliReadiness> _installAdapter({
    required RuntimeTarget target,
    required CliTool cli,
    void Function(CliInstallProgress progress)? onProgress,
  }) async {
    if (!usesSshTransport(target.kind)) {
      throw ArgumentError(
        'install requires an SSH transport target, got ${target.id}',
      );
    }
    final profile = profileById(target.sshProfileId ?? '');
    if (profile == null) {
      return RemoteCliFailed(
        targetId: target.id,
        cli: cli,
        message: 'No SSH profile for target "${target.id}".',
      );
    }
    final installer =
        registry.capability<AcpSettingsCapability>(cli)?.adapterInstaller;
    if (installer == null) {
      return RemoteCliFailed(
        targetId: target.id,
        cli: cli,
        message:
            '${cli.value} has no ACP adapter installer; set a manual adapter '
            'path for this target.',
      );
    }

    try {
      final run = await _runnerFor(profile, includeStderr: true);
      final existing = await _locateAdapterWithRun(
        target: target,
        cli: cli,
        run: run,
      );
      final path = existing ??
          await (_adapterInstallActionBuilder?.call(installer, profile, run) ??
                  buildRemotePreflightAdapterInstall(
                    installer: installer,
                    profile: profile,
                  ))(
            run: run,
            onProgress: onProgress ?? (_) {},
          );
      await rememberRemoteAcpAdapterPathIfNeeded(
        targetId: target.id,
        cli: cli,
        resolvedPath: path,
        readAcpAdapterPathOverride: acpAdapterPathOverride,
        writeAcpAdapterPathOverride: setAcpAdapterPathOverride,
      );
      return RemoteCliReady(targetId: target.id, cli: cli, path: path);
    } on Object catch (e, st) {
      final message = remoteCliFailureMessage(e);
      appLogger.w(
        '[remote-cli] adapter install failed target=${target.id} '
        'cli=${cli.value}: $message',
        error: e,
        stackTrace: st,
      );
      return RemoteCliFailed(targetId: target.id, cli: cli, message: message);
    }
  }

  Future<String?> _locateCli({
    required RuntimeTarget target,
    required CliTool cli,
  }) async {
    final profile = profileById(target.sshProfileId ?? '');
    if (profile == null) {
      throw StateError('No SSH profile for target "${target.id}".');
    }
    final run = await _runnerFor(profile, includeStderr: false);
    return _locateCliWithRun(target: target, cli: cli, run: run);
  }

  Future<String?> _locateCliWithRun({
    required RuntimeTarget target,
    required CliTool cli,
    required SshCommandRunner run,
  }) async {
    final storedPath = (await cliPathOverride(target.id, cli.value) ?? '')
        .trim();
    return _installer.locate(
      cli: cli,
      run: run,
      manualPathOverride: storedPath,
    );
  }

  Future<String?> _locateAdapter({
    required RuntimeTarget target,
    required CliTool cli,
  }) async {
    final profile = profileById(target.sshProfileId ?? '');
    if (profile == null) {
      throw StateError('No SSH profile for target "${target.id}".');
    }
    final run = await _runnerFor(profile, includeStderr: false);
    return _locateAdapterWithRun(target: target, cli: cli, run: run);
  }

  Future<String?> _locateAdapterWithRun({
    required RuntimeTarget target,
    required CliTool cli,
    required SshCommandRunner run,
  }) async {
    final stored =
        (await acpAdapterPathOverride(target.id, cli.value) ?? '').trim();
    if (stored.isNotEmpty) return stored;
    final located = await AcpAdapterDiscovery(
      registry: registry,
    ).locateRemote(run: run);
    return located[cli];
  }
}

/// User-facing install/probe error text without Dart's `Bad state:` prefix.
String remoteCliFailureMessage(Object error) {
  if (error is StateError) {
    final message = error.message.trim();
    if (message.isNotEmpty) return message;
  }
  return '$error';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/remote/remote_cli_readiness_adapter_test.dart test/services/remote/remote_cli_readiness_termux_test.dart`
Expected: PASS. (The termux test's expectations are unchanged; `probe` still returns `RemoteCliFailed` for a throwing client.)

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/remote/remote_cli_readiness.dart client/test/services/remote/remote_cli_readiness_adapter_test.dart
git commit -m "feat(remote-acp): kind-aware remote readiness probe/locate/install"
```

---

### Task 7: Scope the ACP adapter install-job keys

**Files:**
- Modify: `client/lib/services/install/install_job_keys.dart`
- Modify: `client/lib/services/install/install_job_enqueue.dart`
- Test: `client/test/services/install/install_job_keys_adapter_scope_test.dart` (create)

**Interfaces:**
- Produces: `InstallJobKeys.claudeAcpAdapter({InstallJobScope scope = const InstallJobScopeLocal()})`, `InstallJobKeys.codexAcpAdapter({...})`, and matching `scope` params on `installClaudeAcpAdapter` / `installCodexAcpAdapter`.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/install/install_job_keys_adapter_scope_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/install_job/install_job_scope.dart';
import 'package:teampilot/services/install/install_job_keys.dart';

void main() {
  test('adapter keys default to local scope and differ per profile', () {
    final local = InstallJobKeys.claudeAcpAdapter();
    expect(local.scope, const InstallJobScopeLocal());

    final a = InstallJobKeys.claudeAcpAdapter(
      scope: const InstallJobScopeSsh('p1'),
    );
    final b = InstallJobKeys.claudeAcpAdapter(
      scope: const InstallJobScopeSsh('p2'),
    );
    expect(a == b, isFalse);
    expect(a == local, isFalse);
    expect(
      InstallJobKeys.codexAcpAdapter(scope: const InstallJobScopeSsh('p1')),
      isNot(InstallJobKeys.claudeAcpAdapter(
        scope: const InstallJobScopeSsh('p1'),
      )),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/install/install_job_keys_adapter_scope_test.dart`
Expected: FAIL — `scope` is not a parameter of `claudeAcpAdapter`.

- [ ] **Step 3: Write minimal implementation**

In `client/lib/services/install/install_job_keys.dart`, replace the two adapter key methods:

```dart
  /// Claude ACP adapter npm install (not a [CliTool]).
  static InstallJobKey claudeAcpAdapter({
    InstallJobScope scope = const InstallJobScopeLocal(),
  }) => InstallJobKey(
    kind: InstallJobKind.cliExecutable,
    target: ClaudeAcpAdapterInstaller.jobTarget,
    scope: scope,
  );

  /// Codex ACP adapter npm install (not a [CliTool]).
  static InstallJobKey codexAcpAdapter({
    InstallJobScope scope = const InstallJobScopeLocal(),
  }) => InstallJobKey(
    kind: InstallJobKind.cliExecutable,
    target: CodexAcpAdapterInstaller.jobTarget,
    scope: scope,
  );
```

In `client/lib/services/install/install_job_enqueue.dart`, add a `scope` parameter to both adapter helpers and pass it through:

```dart
  /// Installs the Claude ACP adapter (local or over SSH when scoped).
  Future<CliInstallResult> installClaudeAcpAdapter({
    required String title,
    String? subtitle,
    InstallJobScope scope = const InstallJobScopeLocal(),
    FutureOr<void> Function(CliInstallResult result)? onSucceeded,
    FutureOr<void> Function(Object error)? onFailed,
  }) {
    final runnerRegistry = this.runnerRegistry;
    if (runnerRegistry == null) {
      throw StateError('InstallJobRegistry has no runner registry');
    }
    final key = InstallJobKeys.claudeAcpAdapter(scope: scope);
    final runner = runnerRegistry.resolve(key);
    if (runner == null) {
      throw StateError('No InstallJobRunner for ${key.kind}');
    }
    late final InstallJobSpec<CliInstallResult> spec;
    spec = InstallJobSpec(
      key: key,
      title: title,
      subtitle: subtitle,
      cancelPolicy: InstallCancelPolicy.cooperative,
      onSucceeded: onSucceeded,
      onFailed: onFailed,
      run: (ctx) => runner.run(spec, ctx),
    );
    return enqueue(spec);
  }
```

```dart
  /// Installs the Codex ACP adapter (local or over SSH when scoped).
  Future<CliInstallResult> installCodexAcpAdapter({
    required String title,
    String? subtitle,
    InstallJobScope scope = const InstallJobScopeLocal(),
    FutureOr<void> Function(CliInstallResult result)? onSucceeded,
    FutureOr<void> Function(Object error)? onFailed,
  }) {
    final runnerRegistry = this.runnerRegistry;
    if (runnerRegistry == null) {
      throw StateError('InstallJobRegistry has no runner registry');
    }
    final key = InstallJobKeys.codexAcpAdapter(scope: scope);
    final runner = runnerRegistry.resolve(key);
    if (runner == null) {
      throw StateError('No InstallJobRunner for ${key.kind}');
    }
    late final InstallJobSpec<CliInstallResult> spec;
    spec = InstallJobSpec(
      key: key,
      title: title,
      subtitle: subtitle,
      cancelPolicy: InstallCancelPolicy.cooperative,
      onSucceeded: onSucceeded,
      onFailed: onFailed,
      run: (ctx) => runner.run(spec, ctx),
    );
    return enqueue(spec);
  }
```

(`InstallJobScope` is already imported in `install_job_enqueue.dart`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/install/install_job_keys_adapter_scope_test.dart test/services/install/install_job_runner_registry_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/install/install_job_keys.dart client/lib/services/install/install_job_enqueue.dart client/test/services/install/install_job_keys_adapter_scope_test.dart
git commit -m "feat(remote-acp): scope ACP adapter install job keys"
```

---

### Task 8: Landing panel renders and installs adapter requirements

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/remote_cli_machine_readiness_panel.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/home_workspace/workspace/remote_cli_machine_readiness_panel_test.dart` (create)

**Interfaces:**
- Consumes: `RemoteCliRequirement.kind` (Task 1), `RemoteCliReadinessService.probe/install(kind:)` (Task 6), `InstallJobKeys.claudeAcpAdapter(scope:)` / `codexAcpAdapter(scope:)` (Task 7), `AcpSettingsCapability`.
- Produces: l10n key `remoteCliMachineReadinessAdapterLabel` (`"{cli} ACP adapter"`).

- [ ] **Step 1: Add the l10n key**

In `client/lib/l10n/app_en.arb`, after the `"remoteCliMachineReadinessMissing"` block, add:

```json
  "remoteCliMachineReadinessAdapterLabel": "{cli} ACP adapter",
  "@remoteCliMachineReadinessAdapterLabel": {
    "description": "Landing readiness row label for a separate ACP adapter binary.",
    "placeholders": {
      "cli": {"type": "String"}
    }
  },
```

In `client/lib/l10n/app_zh.arb`, add the matching key at the same location:

```json
  "remoteCliMachineReadinessAdapterLabel": "{cli} ACP 适配器",
```

Then run: `cd client && flutter gen-l10n`
Expected: `lib/l10n/app_localizations*.dart` regenerated with the new getter.

- [ ] **Step 2: Write the failing test**

Create `client/test/pages/home_workspace/workspace/remote_cli_machine_readiness_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/cli_binary_kind.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/workspace/remote_cli_machine_readiness_panel.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/remote/remote_cli_readiness.dart';
import 'package:teampilot/services/remote/remote_cli_requirements.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/theme/app_theme.dart';

void main() {
  const target = RuntimeTarget(
    id: 'ssh:host-a',
    label: 'Build host',
    kind: RuntimeKind.ssh,
    sshProfileId: 'host-a',
  );

  testWidgets('renders an adapter row from an adapter requirement',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        RemoteCliMachineReadinessPanel(
          fixedRequirements: const [
            RemoteCliRequirement(
              target: target,
              cli: CliTool.claude,
              hostLabel: 'Build host',
              kind: CliBinaryKind.adapter,
            ),
          ],
          selectableTargets: const [target],
          readiness: _FakeReadiness(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Claude Code ACP adapter'), findsOneWidget);
  });
}

Widget _wrap(Widget child) {
  final theme = buildDarkTheme();
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1),
      child: CliToolRegistryScope(
        registry: CliToolRegistry.builtIn(),
        child: Scaffold(body: child),
      ),
    ),
  );
}

class _FakeReadiness extends RemoteCliReadinessService {
  _FakeReadiness()
      : super(
          registry: CliToolRegistry.builtIn(),
          sshClientFactory: _ThrowingSshClientFactory(),
          profileById: (_) => null,
          cliPathOverride: (_, __) async => null,
          setCliPathOverride: (_, __, ___) async {},
        );

  @override
  Future<RemoteCliReadiness> probe({
    required RuntimeTarget target,
    required CliTool cli,
    CliBinaryKind kind = CliBinaryKind.cli,
  }) async => RemoteCliMissing(targetId: target.id, cli: cli);
}

class _ThrowingSshClientFactory implements SshClientFactory {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
```

**Note:** `TpTheme` / `TpThemeData` come from `package:shared_ui/shared_ui.dart`;
`buildDarkTheme()` comes from `package:teampilot/theme/app_theme.dart` (both are
already imported above).

- [ ] **Step 3: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/remote_cli_machine_readiness_panel_test.dart`
Expected: FAIL — the row renders `Claude Code`, not `Claude Code ACP adapter` (the panel ignores `requirement.kind`).

- [ ] **Step 4: Write minimal implementation**

In `client/lib/pages/home_workspace/workspace/remote_cli_machine_readiness_panel.dart`:

Add imports:

```dart
import '../../../models/cli_binary_kind.dart';
import '../../../services/cli/registry/capabilities/acp_settings_capability.dart';
```

In `_CliReadinessRow.build`, after `cliLabel` is computed, add the adapter label and installer resolution:

```dart
    final isAdapter = requirement.kind == CliBinaryKind.adapter;
    final displayLabel = isAdapter
        ? l10n.remoteCliMachineReadinessAdapterLabel(cliLabel)
        : cliLabel;
    final supportsInstaller = isAdapter
        ? registry
                .capability<AcpSettingsCapability>(requirement.cli)
                ?.adapterInstaller !=
            null
        : registry
                .capability<CliExecutableCapability>(requirement.cli)
                ?.supportsInstaller ??
            false;
```

Replace the existing `supportsInstaller` local and use `displayLabel` in the `Text(cliLabel, ...)` line and in the `switch` subtitles (`cliLabel` → `displayLabel`):

```dart
      RemoteCliReady(:final path) => (
        Icons.check_circle_outline,
        cs.primary,
        l10n.remoteCliMachineReadinessReady(displayLabel, path),
      ),
      RemoteCliMissing() => (
        Icons.error_outline,
        cs.error,
        l10n.remoteCliMachineReadinessMissing(displayLabel),
      ),
      RemoteCliFailed(:final message) => (
        Icons.error_outline,
        cs.error,
        l10n.remoteCliMachineReadinessFailed(displayLabel, message),
      ),
```

and

```dart
                Text(displayLabel, style: TpTextStyles.of(context).md),
```

In `_RemoteCliMachineReadinessPanelState._probe`, forward the kind:

```dart
      final result = await widget.readiness.probe(
        target: requirement.target,
        cli: requirement.cli,
        kind: requirement.kind,
      );
```

In `_RemoteCliMachineReadinessPanelState._install`, branch the key and title for adapters:

```dart
      final isAdapter = requirement.kind == CliBinaryKind.adapter;
      final adapterLabel = isAdapter
          ? l10n.remoteCliMachineReadinessAdapterLabel(cliLabel)
          : cliLabel;
      final installer = cliRegistry
          .capability<AcpSettingsCapability>(requirement.cli)
          ?.adapterInstaller;
      final key = isAdapter
          ? (installer is CodexAcpAdapterInstaller
                ? InstallJobKeys.codexAcpAdapter(scope: scope)
                : InstallJobKeys.claudeAcpAdapter(scope: scope))
          : InstallJobKeys.cli(requirement.cli.value, scope: scope);
```

Use `adapterLabel` in the `title`, `historyMessageFor`, and pass `kind` to the install call:

```dart
      final result = await registry.enqueue(
        InstallJobSpec<RemoteCliReadiness>(
          key: key,
          title: 'Install $adapterLabel on $hostLabel',
          workspaceId: widget.workspace?.workspaceId,
          cancelPolicy: InstallCancelPolicy.cooperative,
          historyMessageFor: (readiness) => switch (readiness) {
            RemoteCliReady() => '$adapterLabel ready on $hostLabel',
            _ => null,
          },
          run: (ctx) async {
            final readiness = await widget.readiness.install(
              target: requirement.target,
              cli: requirement.cli,
              kind: requirement.kind,
              onProgress: (progress) {
                final phaseLabel = switch (progress.phase) {
                  CliInstallPhase.checkingNpm => 'Checking npm',
                  CliInstallPhase.bootstrappingNode => 'Bootstrapping Node',
                  CliInstallPhase.installingCli => 'Installing CLI',
                  CliInstallPhase.locatingExecutable => 'Locating executable',
                  CliInstallPhase.syncingRemoteWorkspace =>
                    'Syncing remote workspace',
                };
                final detail = progress.detail?.trim();
                if (detail != null && detail.isNotEmpty) {
                  ctx.reportPhase(phaseLabel, detail: detail);
                } else {
                  ctx.reportPhase(phaseLabel);
                }
              },
            );
            if (readiness is RemoteCliFailed) {
              throw StateError(readiness.message);
            }
            return readiness;
          },
        ),
      );
```

Add the import for the Codex installer:

```dart
import '../../../services/cli/codex/capabilities/acp_adapter_installer.dart';
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/remote_cli_machine_readiness_panel_test.dart test/services/remote/remote_cli_readiness_adapter_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/pages/home_workspace/workspace/remote_cli_machine_readiness_panel.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations*.dart client/test/pages/home_workspace/workspace/remote_cli_machine_readiness_panel_test.dart
git commit -m "feat(remote-acp): install the ACP adapter from the landing readiness panel"
```

---

### Task 9: Inject the resolved remote adapter path at launch

**Files:**
- Modify: `client/lib/services/chat/launch/connect/acp_runtime_attach.dart`
- Modify: `client/lib/services/chat/launch/session_launch_host.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Modify: `client/lib/app/app_shell.dart`
- Test: `client/test/services/chat/launch/acp_remote_adapter_path_test.dart` (create)

**Interfaces:**
- Produces:
  - `SessionLaunchHost.acpAdapterPathOverride` → `Future<String?> Function(String targetId, String cliValue)?` (default `null`).
  - `String? Function(CliTool tool) acpAdapterPathResolverFor({required bool remote, required String? remoteAdapterPath, String Function(CliTool tool)? localResolver})` in `acp_runtime_attach.dart`.
  - `AcpRuntimeAttach` resolves `_host.acpAdapterPathOverride` before building the cubit and passes it to `acpLaunchPlanResolver(discoveredAdapterPath: ...)`.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/chat/launch/acp_remote_adapter_path_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/connect/acp_runtime_attach.dart';

void main() {
  test('remote resolver returns the injected absolute adapter path', () {
    final resolver = acpAdapterPathResolverFor(
      remote: true,
      remoteAdapterPath: '/home/u/.local/bin/claude-agent-acp',
      localResolver: (tool) => '/local/${tool.value}',
    );
    expect(resolver, isNotNull);
    expect(resolver!(CliTool.claude), '/home/u/.local/bin/claude-agent-acp');
  });

  test('remote resolver returns null when no override was found', () {
    final resolver = acpAdapterPathResolverFor(
      remote: true,
      remoteAdapterPath: null,
      localResolver: (tool) => '/local/${tool.value}',
    );
    expect(resolver!(CliTool.claude), isNull);
  });

  test('local resolver returns the boot-discovered adapter path', () {
    final resolver = acpAdapterPathResolverFor(
      remote: false,
      remoteAdapterPath: '/ignored',
      localResolver: (tool) => '/local/${tool.value}',
    );
    expect(resolver!(CliTool.claude), '/local/claude');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/acp_remote_adapter_path_test.dart`
Expected: FAIL — `acpAdapterPathResolverFor` is not defined.

- [ ] **Step 3: Write minimal implementation**

In `client/lib/services/chat/launch/connect/acp_runtime_attach.dart`, add this top-level function near `acpTranscriptFileName`:

```dart
/// Adapter-path resolver for one ACP launch plan.
///
/// Remote launches use the per-target absolute override (or `null` → the plain
/// adapter name via PATH). Local launches use the boot-discovered map.
String? Function(CliTool tool) acpAdapterPathResolverFor({
  required bool remote,
  required String? remoteAdapterPath,
  String Function(CliTool tool)? localResolver,
}) {
  if (remote) return (_) => remoteAdapterPath;
  return localResolver;
}
```

In `AcpRuntimeAttach.attachAcpRuntime`, after `final remote = usesSshTransport(launchTarget.kind);`, nothing changes yet. Before constructing the cubit, resolve the override. Replace:

```dart
    final cubit = _cubit(
      session: session,
      cli: cli,
      personal: true,
      memberId: null,
      launchTarget: launchTarget,
      sshLaunch: sshLaunch,
      processWorkingDirectory: workingDirectory,
    );
```

with:

```dart
    final remoteAdapterPath = remote
        ? await _resolveRemoteAdapterPath(cli, launchTarget)
        : null;
    final cubit = _cubit(
      session: session,
      cli: cli,
      personal: true,
      memberId: null,
      launchTarget: launchTarget,
      sshLaunch: sshLaunch,
      remoteAdapterPath: remoteAdapterPath,
      processWorkingDirectory: workingDirectory,
    );
```

Add the helper to `AcpRuntimeAttach` (after `_productionSshLaunch`):

```dart
  /// Reads the per-target ACP adapter override for a remote launch. `null`
  /// keeps today's behavior (resolve the bare adapter name via remote PATH).
  Future<String?> _resolveRemoteAdapterPath(
    CliTool cli,
    RuntimeTarget launchTarget,
  ) async {
    final resolver = _host.acpAdapterPathOverride;
    if (resolver == null) return null;
    try {
      final path = (await resolver(launchTarget.id, cli.value))?.trim() ?? '';
      return path.isEmpty ? null : path;
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[acp-remote] adapter override lookup failed target=${launchTarget.id} '
        'cli=${cli.value}',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
```

Add `remoteAdapterPath` to `_cubit` and use the resolver function:

```dart
  AcpChatRuntimeCubit _cubit({
    required AppSession session,
    required CliTool cli,
    required bool personal,
    required String? memberId,
    required RuntimeTarget launchTarget,
    required String processWorkingDirectory,
    AcpSshLaunch? sshLaunch,
    String? remoteAdapterPath,
  }) {
```

and replace the `discoveredAdapterPath:` argument:

```dart
          launchPlanFor: acpLaunchPlanResolver(
            _host.cliRegistry,
            discoveredAdapterPath: acpAdapterPathResolverFor(
              remote: remote,
              remoteAdapterPath: remoteAdapterPath,
              localResolver: _host.discoveredAcpAdapterPath,
            ),
          ),
```

In `client/lib/services/chat/launch/session_launch_host.dart`, next to the `discoveredAcpAdapterPath` getter (line ~125), add:

```dart
  /// Per-target ACP adapter path override (`targets.json`), used to spawn a
  /// remote adapter by absolute path. Null in tests / when not wired.
  Future<String?> Function(String targetId, String cliValue)?
  get acpAdapterPathOverride => null;
```

In `client/lib/cubits/chat_cubit.dart`:

Add a constructor parameter next to `discoveredAcpAdapterPath` (line ~124) and the field/getter next to lines ~187 and ~542/846:

```dart
    Future<String?> Function(String targetId, String cliValue)?
    acpAdapterPathOverride,
```

```dart
       _acpAdapterPathOverride = acpAdapterPathOverride,
```

```dart
  final Future<String?> Function(String targetId, String cliValue)?
  _acpAdapterPathOverride;
```

```dart
  @override
  Future<String?> Function(String targetId, String cliValue)?
  get acpAdapterPathOverride => _acpAdapterPathOverride;
```

In `client/lib/app/app_shell.dart`, in the `chatCubit = ChatCubit(...)`
construction (line ~2205), directly after the existing
`discoveredAcpAdapterPath: sessionPreferencesCubit.resolveAcpAdapterPath,`
(line ~2224), add:

```dart
      acpAdapterPathOverride: targetsRepo.acpAdapterPathOverride,
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/acp_remote_adapter_path_test.dart test/services/chat/launch/acp_runtime_attach_test.dart test/cubits/session/acp/acp_launch_wiring_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/chat/launch/connect/acp_runtime_attach.dart client/lib/services/chat/launch/session_launch_host.dart client/lib/cubits/chat_cubit.dart client/lib/app/app_shell.dart client/test/services/chat/launch/acp_remote_adapter_path_test.dart
git commit -m "feat(remote-acp): spawn the remote adapter by absolute override path"
```

---

### Task 10: Settings card remote adapter row

**Files:**
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/main.dart`
- Modify: `client/lib/pages/config/cli_readiness_card.dart`
- Test: `client/test/pages/config/cli_config_section_test.dart` (extend)

**Interfaces:**
- Consumes: `RemoteCliReadinessService.probe/locate/install(kind: adapter)` (Task 6), `InstallJobKeys.*AcpAdapter(scope:)` (Task 7), `RuntimeTarget.ssh(profileId, label:)`.
- Produces: `RepositoryProvider<RemoteCliReadinessService>` available app-wide.

- [ ] **Step 1: Provide the service app-wide**

In `client/lib/app/app_shell.dart`, add a field to `AppShell` (next to `final ChatCubit chatCubit;` at line ~532):

```dart
  final RemoteCliReadinessService remoteCliReadiness;
```

add it to the `AppShell({...})` constructor (next to `required this.chatCubit,`):

```dart
    required this.remoteCliReadiness,
```

and pass it in the `AppShell(...)` construction at the end of `buildAppShell` (search for `chatCubit: chatCubit,` in the `AppShell(` literal):

```dart
    remoteCliReadiness: remoteCliReadiness,
```

In `client/lib/main.dart`, in the `MultiRepositoryProvider` list (after `RepositoryProvider<HomeStorage>.value(...)`), add:

```dart
                  RepositoryProvider<RemoteCliReadinessService>.value(
                    value: shell.remoteCliReadiness,
                  ),
```

and add the import at the top of `main.dart`:

```dart
import 'services/remote/remote_cli_readiness.dart';
```

(Adjust the relative path to match `main.dart`'s other imports.)

- [ ] **Step 2: Write the failing test**

**Extend the existing settings-card harness** in
`client/test/pages/config/cli_config_section_test.dart` (do **not** create a new
file — that harness already builds a real `SessionPreferencesCubit`, an install
registry with a runner, a silent version probe, and a `ConnectionModeService`).

Add these imports to the test file (with the existing `package:teampilot/...`
imports):

```dart
import 'package:mocktail/mocktail.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/remote/remote_cli_readiness.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
```

Add these test doubles at the bottom of the test file (outside `main`):

```dart
class _MockSshProfileCubit extends Mock implements SshProfileCubit {}

/// Records the `kind` each remote probe was asked for; always reports ready.
class _FakeRemoteReadiness extends RemoteCliReadinessService {
  _FakeRemoteReadiness()
      : super(
          registry: CliToolRegistry.builtIn(),
          sshClientFactory: _ThrowingSshClientFactory(),
          profileById: (_) => null,
          cliPathOverride: (_, __) async => null,
          setCliPathOverride: (_, __, ___) async {},
        );

  final probedKinds = <CliBinaryKind>[];

  @override
  Future<RemoteCliReadiness> probe({
    required RuntimeTarget target,
    required CliTool cli,
    CliBinaryKind kind = CliBinaryKind.cli,
  }) async {
    probedKinds.add(kind);
    return RemoteCliReady(
      targetId: target.id,
      cli: cli,
      path: '/home/u/.local/bin/claude-agent-acp',
    );
  }
}

class _ThrowingSshClientFactory implements SshClientFactory {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
```

Add this remote wrap helper next to `_wrapCard`:

```dart
Widget _wrapCardRemote(
  SessionPreferencesCubit cubit, {
  required SshProfileCubit sshProfileCubit,
  required RemoteCliReadinessService readiness,
}) {
  final progressCubit = ProgressActivityCubit(historyRecorder: _FakeRecorder());
  final registry = InstallJobRegistry(
    progressCubit: progressCubit,
    runnerRegistry: InstallJobRunnerRegistry(
      runners: [
        CliInstallJobRunner(
          installerFactory: () => _DelayedCliInstallerService(),
        ),
      ],
    ),
  );

  return MultiRepositoryProvider(
    providers: [
      RepositoryProvider<ConnectionModeService>(
        create: (_) => ConnectionModeService(
          defaultTargetResolver: () => const RuntimeTarget(
            id: 'ssh:host-a',
            label: 'host',
            kind: RuntimeKind.ssh,
            sshProfileId: 'host-a',
          ),
          hasSshProfiles: () => true,
        ),
      ),
      RepositoryProvider<InstallJobRegistry>.value(value: registry),
      RepositoryProvider<RemoteCliReadinessService>.value(value: readiness),
      RepositoryProvider<SshClientFactory>.value(
        value: _ThrowingSshClientFactory(),
      ),
    ],
    child: BlocProvider<SshProfileCubit>.value(
      value: sshProfileCubit,
      child: BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CliReadinessCard(
              cli: CliTool.claude,
              cubit: cubit,
              versionProbe: _silentProbe(),
            ),
          ),
        ),
      ),
    ),
  );
}
```

Add this test inside `main()` (after the existing `Needs setup shows adapter
Install` test):

```dart
  testWidgets(
    'remote: probes the ACP adapter on the host instead of local discovery',
    (tester) async {
      final cubit = await _makeCubit(
        locatedExecutables: const {CliTool.claude: '/usr/local/bin/claude'},
      );
      addTearDown(cubit.close);

      const profile = SshProfile(
        id: 'host-a',
        name: 'host',
        host: 'host',
        username: 'u',
      );
      final sshProfileCubit = _MockSshProfileCubit();
      when(() => sshProfileCubit.state).thenReturn(
        const SshProfileState(profiles: [profile], selectedProfileId: 'host-a'),
      );
      when(
        () => sshProfileCubit.stream,
      ).thenAnswer((_) => const Stream.empty());

      final readiness = _FakeRemoteReadiness();

      await tester.pumpWidget(
        _wrapCardRemote(
          cubit,
          sshProfileCubit: sshProfileCubit,
          readiness: readiness,
        ),
      );
      await tester.pumpAndSettle();

      expect(readiness.probedKinds, contains(CliBinaryKind.adapter));
    },
  );
```

**Note:** `_MockSshProfileCubit` is only read (`.state`, `.stream`), so the
mocktail stub is sufficient. `_FakeRemoteReadiness.probe` records the `kind` it
was asked for; the assertion proves the card probes the remote **adapter**
rather than trusting local discovery.

- [ ] **Step 3: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart --plain-name "probes the ACP adapter on the host"`
Expected: FAIL — the card never calls `RemoteCliReadinessService.probe` (it uses local discovery), so `probedKinds` is empty.

- [ ] **Step 4: Write minimal implementation**

In `client/lib/pages/config/cli_readiness_card.dart`:

Add imports (`install_job_scope_resolver.dart` is already imported at line 30,
so do not duplicate it):

```dart
import '../../models/install_job/install_cancel_policy.dart';
import '../../models/install_job/install_job_spec.dart';
import '../../models/runtime_target.dart';
import '../../services/remote/remote_cli_readiness.dart';
```

Add state:

```dart
  bool? _remoteAdapterKnown;
  bool _installingRemoteAdapter = false;
```

In `initState`, after the existing post-frame `_refreshLatest()` scheduling, add:

```dart
    if (!_isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refreshRemoteAdapter());
      });
    }
```

Add helpers:

```dart
  /// Remote work plane target + readiness service, or null when not remote.
  ({RuntimeTarget target, RemoteCliReadinessService readiness})?
  _remoteAdapterScope() {
    final mode = context.read<ConnectionModeService>();
    if (!mode.isRemoteWorkPlane) return null;
    final profile = _remoteSshProfile(context, mode);
    if (profile == null) return null;
    final readiness = context.read<RemoteCliReadinessService>();
    return (
      target: RuntimeTarget.ssh(profile.id, label: profile.name),
      readiness: readiness,
    );
  }

  Future<void> _refreshRemoteAdapter() async {
    if (!_separateAdapter) return;
    final scope = _remoteAdapterScope();
    if (scope == null) return;
    final result = await scope.readiness.probe(
      target: scope.target,
      cli: widget.cli,
      kind: CliBinaryKind.adapter,
    );
    if (!mounted) return;
    setState(() => _remoteAdapterKnown = result is RemoteCliReady);
  }
```

In `_buildCard`, compute remote adapter knownness:

```dart
    final isRemote = context.select<ConnectionModeService, bool>(
      (service) => service.isRemoteWorkPlane,
    );
    final adapterKnown = isRemote
        ? (_remoteAdapterKnown ??
            _looksAbsolute(cubit.configuredAcpAdapterPath(widget.cli)))
        : cubit.hasKnownAcpAdapter(widget.cli);
```

(Delete the old `final adapterKnown = cubit.hasKnownAcpAdapter(widget.cli);` and the old `final isRemote = context.select<...>` line so there is exactly one of each.)

Change `_adapterJobKey` to take the scope:

```dart
  InstallJobKey _adapterJobKey(BuildContext context) {
    final scope = installJobScopeForContext(context);
    final installer = _settings?.adapterInstaller;
    if (installer is CodexAcpAdapterInstaller) {
      return InstallJobKeys.codexAcpAdapter(scope: scope);
    }
    return InstallJobKeys.claudeAcpAdapter(scope: scope);
  }
```

Update the two call sites (`jobs.isRunning(_adapterJobKey())` → `jobs.isRunning(_adapterJobKey(context))`).

Change `_locateAdapter` to prefer the remote scope:

```dart
  Future<void> _locateAdapter() async {
    if (_locatingAdapter) return;
    setState(() => _locatingAdapter = true);
    try {
      final scope = _remoteAdapterScope();
      if (scope != null) {
        final result = await scope.readiness.locate(
          target: scope.target,
          cli: widget.cli,
          kind: CliBinaryKind.adapter,
        );
        if (!mounted) return;
        final ready = result is RemoteCliReady;
        setState(() => _remoteAdapterKnown = ready);
        AppToast.show(
          context,
          message: ready
              ? context.l10n.cliExecutablePathLocateSuccess(
                  widget.cli.value,
                  (result as RemoteCliReady).path,
                )
              : context.l10n.cliReadinessAdapterMissing,
          variant: ready ? TpToastVariant.success : TpToastVariant.error,
        );
        return;
      }
      // ...existing local body unchanged...
```

Change `_installOrUpgradeAdapter` to enqueue a scoped job in the remote plane:

```dart
  Future<void> _installOrUpgradeAdapter({required bool upgrading}) async {
    final jobs = context.read<InstallJobRegistry>();
    final scope = _remoteAdapterScope();
    if (scope != null) {
      if (_installingRemoteAdapter) return;
      setState(() => _installingRemoteAdapter = true);
      try {
        final result = await jobs.enqueue(
          InstallJobSpec<RemoteCliReadiness>(
            key: _adapterJobKey(context),
            title: _adapterInstallLabel(context.l10n),
            cancelPolicy: InstallCancelPolicy.cooperative,
            run: (ctx) async {
              final readiness = await scope.readiness.install(
                target: scope.target,
                cli: widget.cli,
                kind: CliBinaryKind.adapter,
              );
              if (readiness is RemoteCliFailed) {
                throw StateError(readiness.message);
              }
              return readiness;
            },
          ),
        );
        if (!mounted) return;
        setState(() => _remoteAdapterKnown = result is RemoteCliReady);
        AppToast.show(
          context,
          message: result is RemoteCliReady
              ? context.l10n.cliInstallUpgrading
              : context.l10n.cliReadinessAdapterMissing,
          variant: result is RemoteCliReady
              ? TpToastVariant.success
              : TpToastVariant.error,
        );
      } finally {
        if (mounted) setState(() => _installingRemoteAdapter = false);
      }
      return;
    }
    // ...existing local body unchanged...
```

Update the busy flag where `installingAdapter` is computed:

```dart
    final installingAdapter =
        _installingRemoteAdapter || jobs.isRunning(_adapterJobKey(context));
    final busyAdapter = _locatingAdapter || installingAdapter;
```

Add imports for `InstallJobSpec` / `InstallCancelPolicy` if not already present:

```dart
import '../../models/install_job/install_cancel_policy.dart';
import '../../models/install_job/install_job_spec.dart';
import '../../models/runtime_target.dart';
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/pages/config/cli_config_section_test.dart`
Expected: PASS (both the new remote test and the existing settings tests).

- [ ] **Step 6: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/pages/config/cli_readiness_card.dart client/lib/app/app_shell.dart client/lib/main.dart client/test/pages/config/cli_config_section_test.dart
git commit -m "feat(remote-acp): remote ACP adapter row in the CLI readiness settings card"
```

---

### Task 11: Real-machine smoke checklist + full verification

**Files:**
- Create: `docs/remote-acp-adapter-smoke.md`

**Interfaces:** none (documentation + verification gate).

- [ ] **Step 1: Write the checklist doc**

Create `docs/remote-acp-adapter-smoke.md`:

```markdown
# Remote ACP Adapter Smoke Checklist

Manual verification for `docs/superpowers/specs/2026-10-16-remote-acp-adapter-readiness-design.md`.
Unit tests cover the plumbing; the items below are the only proof that the
remote ACP session actually spawns and answers like the PTY path.

Run with a host reachable over SSH from the app (`ssh:<profile>` target).

1. **Missing adapter is surfaced**
   - Remote host has `claude` but not `claude-agent-acp`.
   - Compose a personal Claude launch on the remote project with ACP enabled.
   - Expect: the "Required CLIs on this machine" panel appears below the compose
     card with a "Claude Code ACP adapter" row marked not found and an Install
     button.

2. **Install lands on the host**
   - Press Install. Expect: progress phases (Checking npm / Bootstrapping Node /
     Installing CLI / Locating executable) and a ready row.
   - On the host, confirm `claude-agent-acp` exists and
     `targets.json` now has `acpAdapterPathOverrides["ssh:<profile>"]["claude"]`
     set to its absolute path.

3. **Handshake and first turn (Official OAuth)**
   - With the Claude provider set to official login, start the session.
   - Expect: ACP handshake completes, the first prompt is answered, and one tool
     call runs. **If it reports "Not logged in", stop and debug the remote
     `.credentials.json` → remote `CLAUDE_CONFIG_DIR` linkage before shipping.**

4. **Handshake and first turn (API key)**
   - Repeat 3 with an API-key provider.

5. **Codex**
   - Repeat 1-4 for Codex / `codex-acp`.

6. **Override reuse**
   - Kill the SSH session, relaunch the same personal Claude ACP session.
   - Expect: no re-locate needed; the stored absolute adapter path is used.

7. **PATH-independence**
   - Move/install the adapter to a location outside the ssh exec `PATH`
     (e.g. `/opt/acp/`), set the override via Settings Locate, and relaunch.
   - Expect: the session still starts (proof the absolute-path injection works).
```

- [ ] **Step 2: Run the analyzer**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: no errors (infos/warnings tolerated but review them).

- [ ] **Step 3: Run the full test suite once, in the background**

Run: `cd client && dart run tool/run_tests.dart` (background; do not run other test commands concurrently)
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add docs/remote-acp-adapter-smoke.md
git commit -m "docs(remote-acp): add remote ACP adapter smoke checklist"
```

---

## Task ordering

Execute in this order so every task's tests compile:

1. Task 1 (requirement `kind`)
2. Task 3 (`AcpAdapterDiscovery.locateRemote`)
3. Task 4 (`buildRemotePreflightAdapterInstall`)
4. Task 5 (`targets.json` overrides + remember helper)
5. Task 6 (`RemoteCliReadinessService` kind-aware — this adds `probe(kind:)`)
6. Task 2 (landing gate — needs `probe(kind:)` from Task 6)
7. Task 7 (adapter job key scope)
8. Task 8 (landing panel)
9. Task 9 (launch injection)
10. Task 10 (settings card)
11. Task 11 (smoke doc + full verification)

## Follow-up (not in this plan)

Spec (b): mixed-team remote seats running ACP. That needs `_memberAcpGates`
local-only restriction relaxed (`client/lib/services/chat/launch/session/member_acp_stamp.dart`),
remote TeamBus MCP reachability, and SSH reconnect. Do not start it until this
plan's smoke checklist passes on a real host.
