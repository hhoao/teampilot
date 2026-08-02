# CLI Config Reset→Locate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On Settings → CLI, when the path field is empty, swap the trailing Reset button to Locate; on success persist the found absolute path as user config (AI CLIs + Git/Node).

**Architecture:** Keep one trailing `TextButton` slot that switches Reset ↔ Locate by stored-path emptiness. Add single-tool locate helpers on `CliExecutableDiscovery` / `ToolchainExecutableDiscovery`. Rows call those helpers (remote for AI CLIs only), then persist like Install/Browse — no `mergeLocated*`. Optional `locateOverride` on rows enables widget tests without `Process.run`.

**Tech Stack:** Flutter, flutter_bloc, existing CLI discovery + SSH remote locate, arb l10n.

**Spec:** `docs/superpowers/specs/2026-08-02-cli-config-locate-after-reset-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | Locate / success / failure / remote-unsupported strings |
| `client/lib/services/cli/cli_executable_discovery.dart` | Add `locateLocalCli(CliTool)` |
| `client/lib/services/cli/toolchain_executable_discovery.dart` | Add `locateLocalTool(String toolId)` |
| `client/lib/pages/config/cli_executable_path_settings_row.dart` | Slot swap + `_locate` (local/remote) |
| `client/lib/pages/config/toolchain_path_settings_row.dart` | Slot swap + local `_locate`; remote toast |
| `client/test/services/cli/cli_executable_discovery_test.dart` | Unit tests for `locateLocalCli` |
| `client/test/services/cli/toolchain_executable_discovery_test.dart` | Append unit tests for `locateLocalTool` |
| `client/test/pages/config/cli_config_section_test.dart` | Label + locate success/failure widget coverage |
| `client/test/pages/config/toolchain_path_locate_test.dart` | Toolchain label + remote-unsupported (create) |

---

### Task 1: l10n strings

**Files:**
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`

- [ ] **Step 1: Add English strings next to `cliExecutablePathReset`**

In `app_en.arb`, after `"cliExecutablePathReset": "Reset",` add:

```json
"cliExecutablePathLocate": "Locate",
"cliExecutablePathLocateFailed": "Could not find {name} on PATH.",
"@cliExecutablePathLocateFailed": {
  "placeholders": { "name": { "type": "String" } }
},
"cliExecutablePathLocateSuccess": "Located {name} at {path}.",
"@cliExecutablePathLocateSuccess": {
  "placeholders": {
    "name": { "type": "String" },
    "path": { "type": "String" }
  }
},
"cliExecutablePathLocateRemoteUnsupported": "Remote locate is not supported for this tool.",
```

- [ ] **Step 2: Add Chinese strings in `app_zh.arb`**

After `"cliExecutablePathReset": "重置",` add:

```json
"cliExecutablePathLocate": "定位",
"cliExecutablePathLocateFailed": "未能在 PATH 上找到 {name}。",
"@cliExecutablePathLocateFailed": {
  "placeholders": { "name": { "type": "String" } }
},
"cliExecutablePathLocateSuccess": "已定位 {name}：{path}。",
"@cliExecutablePathLocateSuccess": {
  "placeholders": {
    "name": { "type": "String" },
    "path": { "type": "String" }
  }
},
"cliExecutablePathLocateRemoteUnsupported": "远程工作面不支持定位此工具。",
```

- [ ] **Step 3: Regenerate l10n**

Run from `client/`:

```bash
flutter gen-l10n
```

Expected: `app_localizations*.dart` gain the four getters; no arb parse errors.

- [ ] **Step 4: Commit**

```bash
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart
git commit -m "$(cat <<'EOF'
feat(l10n): add CLI path Locate strings

EOF
)"
```

---

### Task 2: `CliExecutableDiscovery.locateLocalCli`

**Files:**
- Modify: `client/lib/services/cli/cli_executable_discovery.dart`
- Modify: `client/test/services/cli/cli_executable_discovery_test.dart`

- [ ] **Step 1: Write failing unit tests**

Append to `cli_executable_discovery_test.dart`:

```dart
test('locateLocalCli returns path for one CLI', () async {
  final discovery = CliExecutableDiscovery();
  final path = await discovery.locateLocalCli(
    CliTool.claude,
    runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
      if (executable == 'which' || executable == 'where') {
        return ProcessResult(0, 0, '/opt/bin/${arguments.single}\n', '');
      }
      return ProcessResult(1, 1, '', '');
    },
  );
  expect(path, '/opt/bin/claude');
});

test('locateLocalCli returns null when missing', () async {
  final discovery = CliExecutableDiscovery();
  final path = await discovery.locateLocalCli(
    CliTool.codex,
    includeShellFallback: false,
    runner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
      return ProcessResult(1, 1, '', '');
    },
  );
  expect(path, isNull);
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd client && flutter test test/services/cli/cli_executable_discovery_test.dart
```

Expected: FAIL — `locateLocalCli` not defined.

- [ ] **Step 3: Implement `locateLocalCli`**

In `cli_executable_discovery.dart`, add (reuse the same resolver wiring as `locateLocal`):

```dart
Future<String?> locateLocalCli(
  CliTool cli, {
  ProcessRunner runner = cliToolDefaultProcessRun,
  bool includeShellFallback = true,
}) async {
  final resolver = _registry.capability<ExecutableResolverCapability>(cli);
  if (resolver == null) return null;
  final path = await CliToolLocator(resolver.defaultExecutableName).locate(
    runner: runner,
    includeShellFallback: includeShellFallback,
  );
  final trimmed = path?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd client && flutter test test/services/cli/cli_executable_discovery_test.dart
```

Expected: PASS (all tests in file).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/cli_executable_discovery.dart \
  client/test/services/cli/cli_executable_discovery_test.dart
git commit -m "$(cat <<'EOF'
feat(cli): add locateLocalCli for single-tool PATH scan

EOF
)"
```

---

### Task 3: `ToolchainExecutableDiscovery.locateLocalTool`

**Files:**
- Modify: `client/lib/services/cli/toolchain_executable_discovery.dart`
- Modify: `client/test/services/cli/toolchain_executable_discovery_test.dart` (file already exists — **append** tests, do not replace `void main`)

- [ ] **Step 1: Append failing unit tests**

Append inside the existing `void main()` in `toolchain_executable_discovery_test.dart` (match existing `GitInstallResult.found` / `notFound` style):

```dart
test('locateLocalTool finds node via which', () async {
  final discovery = ToolchainExecutableDiscovery(
    detectGit: () async => const GitInstallResult.notFound('skip'),
    processRunner: (executable, arguments, {stdoutEncoding, stderrEncoding}) async {
      if (arguments.isNotEmpty && arguments.first == 'node') {
        return ProcessResult(0, 0, '/usr/bin/node', '');
      }
      return ProcessResult(0, 1, '', '');
    },
  );
  final path = await discovery.locateLocalTool(
    SessionPreferences.toolchainNode,
  );
  expect(path, '/usr/bin/node');
});

test('locateLocalTool finds git via detectGit', () async {
  final discovery = ToolchainExecutableDiscovery(
    detectGit: () async => const GitInstallResult.found('/usr/bin/git'),
  );
  final path = await discovery.locateLocalTool(
    SessionPreferences.toolchainGit,
  );
  expect(path, '/usr/bin/git');
});

test('locateLocalTool returns null for unknown toolId', () async {
  final discovery = ToolchainExecutableDiscovery(
    detectGit: () async => const GitInstallResult.notFound('skip'),
  );
  expect(await discovery.locateLocalTool('unknown'), isNull);
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd client && flutter test test/services/cli/toolchain_executable_discovery_test.dart
```

Expected: FAIL — `locateLocalTool` not defined; existing `locateLocal` tests still compile.

- [ ] **Step 3: Implement `locateLocalTool`**

In `toolchain_executable_discovery.dart`:

```dart
Future<String?> locateLocalTool(String toolId) async {
  if (toolId == SessionPreferences.toolchainGit) {
    final git = await _detectGit();
    final gitPath = git.executablePath?.trim() ?? '';
    if (git.success && gitPath.isNotEmpty) return gitPath;
    return null;
  }
  if (toolId == SessionPreferences.toolchainNode) {
    final node = await CliToolLocator('node').locate(
      runner: _processRunner,
      includeShellFallback: true,
    );
    final nodePath = node?.trim() ?? '';
    return nodePath.isEmpty ? null : nodePath;
  }
  return null;
}
```

Keep existing `locateLocal()` body as-is (do not require a refactor to call `locateLocalTool`).

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd client && flutter test test/services/cli/toolchain_executable_discovery_test.dart
```

Expected: PASS (old + new tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/toolchain_executable_discovery.dart \
  client/test/services/cli/toolchain_executable_discovery_test.dart
git commit -m "$(cat <<'EOF'
feat(cli): add locateLocalTool for git/node PATH scan

EOF
)"
```

---

### Task 4: AI CLI settings row — Reset ↔ Locate

**Files:**
- Modify: `client/lib/pages/config/cli_executable_path_settings_row.dart`
- Modify: `client/test/pages/config/cli_config_section_test.dart`

- [ ] **Step 1: Add optional locate override + failing widget tests**

On `CliExecutablePathSettingsRow`, add:

```dart
/// Test seam: when non-null, used instead of discovery.
final Future<String?> Function()? locateOverride;
```

(pass through constructor; default `null`)

Extend `cli_config_section_test.dart` (or add a focused row harness in the same file) with:

```dart
testWidgets('shows Locate when CLI path is empty', (tester) async {
  final cubit = await _makeCubit();
  addTearDown(cubit.close);
  await tester.pumpWidget(_wrap(cubit));
  await tester.pump();

  // Cursor row resetKey is shared slot — label should be Locate.
  final button = find.byKey(AppKeys.cursorCliExecutablePathResetButton);
  expect(button, findsOneWidget);
  expect(
    find.descendant(of: button, matching: find.text('Locate')),
    findsOneWidget,
  );
  expect(
    find.descendant(of: button, matching: find.text('Reset')),
    findsNothing,
  );
});

testWidgets('shows Reset when CLI path is configured', (tester) async {
  final cubit = await _makeCubit();
  addTearDown(cubit.close);
  await cubit.setCliExecutablePathFor(CliTool.cursor, '/custom/cursor-agent');
  await tester.pumpWidget(_wrap(cubit));
  await tester.pump();

  final button = find.byKey(AppKeys.cursorCliExecutablePathResetButton);
  expect(
    find.descendant(of: button, matching: find.text('Reset')),
    findsOneWidget,
  );
});
```

For success/failure with override, prefer a small harness that mounts a single `CliExecutablePathSettingsRow` with `locateOverride` (avoids pumping the whole section). Add helper `_wrapRow` + tests:

```dart
testWidgets('Locate success writes and persists path', (tester) async {
  final cubit = await _makeCubit();
  addTearDown(cubit.close);
  await tester.pumpWidget(_wrapRow(
    cubit,
    locateOverride: () async => '/found/claude',
  ));
  await tester.pump();
  await tester.tap(find.byKey(AppKeys.claudeCliExecutablePathResetButton));
  await tester.pumpAndSettle();
  expect(cubit.configuredExecutablePath(CliTool.claude), '/found/claude');
  expect(find.text('Reset'), findsOneWidget);
});

testWidgets('Locate failure leaves path empty and keeps Install', (tester) async {
  final cubit = await _makeCubit();
  addTearDown(cubit.close);
  await tester.pumpWidget(_wrapRow(
    cubit,
    locateOverride: () async => null,
  ));
  await tester.pump();
  await tester.tap(find.byKey(AppKeys.claudeCliExecutablePathResetButton));
  await tester.pumpAndSettle();
  expect(cubit.configuredExecutablePath(CliTool.claude), isEmpty);
  expect(find.text('Locate'), findsOneWidget);
  expect(find.byKey(AppKeys.claudeCliInstallButton), findsOneWidget);
});
```

`_wrapRow` must provide the same `ConnectionModeService` / cubit providers as `_wrap`, plus any toast host if required (if `AppToast` needs overlay, wrap with `Scaffold` + material — match existing toast tests if any; otherwise assert prefs only).

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd client && flutter test test/pages/config/cli_config_section_test.dart
```

Expected: FAIL — still shows disabled Reset / no Locate label / no override wiring.

- [ ] **Step 3: Implement row locate + slot swap**

In `cli_executable_path_settings_row.dart`:

1. Add `bool _isLocating = false`.
2. Replace trailing button:

```dart
final locatingOrInstalling = _isLocating || _isInstalling;
TextButton(
  key: widget.resetKey,
  onPressed: locatingOrInstalling
      ? null
      : (isFallback ? _locate : _reset),
  child: _isLocating
      ? const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Text(
          isFallback
              ? l10n.cliExecutablePathLocate
              : l10n.cliExecutablePathReset,
        ),
),
```

3. Implement `_locate`:

```dart
Future<void> _locate() async {
  if (_isLocating || _isInstalling) return;
  setState(() => _isLocating = true);
  try {
    final path = (await _resolveLocatePath())?.trim() ?? '';
    if (!mounted) return;
    if (path.isEmpty) {
      AppToast.show(
        context,
        message: context.l10n.cliExecutablePathLocateFailed(widget.title),
        variant: TpToastVariant.error,
      );
      return;
    }
    _persistDebouncer.cancel();
    _controller.text = path;
    await widget.cubit.setCliExecutablePathFor(widget.cli, path);
    if (!mounted) return;
    AppToast.show(
      context,
      message: context.l10n.cliExecutablePathLocateSuccess(widget.title, path),
      variant: TpToastVariant.success,
    );
  } finally {
    if (mounted) setState(() => _isLocating = false);
  }
}

Future<String?> _resolveLocatePath() async {
  if (widget.locateOverride != null) return widget.locateOverride!();
  final connectionMode = context.read<ConnectionModeService>();
  final discovery = CliExecutableDiscovery();
  if (connectionMode.isRemoteWorkPlane) {
    final profile = _remoteSshProfile(context, connectionMode);
    if (profile == null) return null;
    final client = await context.read<SshClientFactory>().clientForStorage(profile);
    return discovery.locateRemoteCli(
      cli: widget.cli,
      run: RemoteCliLocator.runnerForClient(client),
    );
  }
  return discovery.locateLocalCli(widget.cli);
}
```

Import `cli_executable_discovery.dart` and `remote_cli_locator.dart` as needed. Reuse existing `_remoteSshProfile`.

Also disable Install while `_isLocating` (`onPressed: locatingOrInstalling ? null : _installCli`).

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd client && flutter test test/pages/config/cli_config_section_test.dart
```

Expected: PASS (including prior install-button tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/config/cli_executable_path_settings_row.dart \
  client/test/pages/config/cli_config_section_test.dart
git commit -m "$(cat <<'EOF'
feat(settings): swap CLI Reset to Locate when path empty

EOF
)"
```

---

### Task 5: Toolchain settings row — Reset ↔ Locate

**Files:**
- Modify: `client/lib/pages/config/toolchain_path_settings_row.dart`
- Create: `client/test/pages/config/toolchain_path_locate_test.dart`

- [ ] **Step 1: Write failing widget tests**

Create `toolchain_path_locate_test.dart` mirroring the CLI row harness:

1. Empty path → Locate label on `AppKeys.gitToolchainPathResetButton`.
2. Configured path → Reset.
3. `locateOverride: () async => '/usr/bin/git'` → persists via cubit + becomes Reset.
4. Remote `ConnectionModeService` (SSH mode) + tap Locate → toast / prefs unchanged. Prefer asserting `configured` toolchain path stays empty; if toast finder is flaky, assert cubit path only **and** that `locateOverride` was **not** called (pass a throwing override / flag). Spec requires remote unsupported without writing — implement `_locate` to short-circuit before override when remote, **or** document that override is local-only and remote check runs first.

Remote short-circuit must run **before** `locateOverride` so test 4 works:

```dart
if (connectionMode.isRemoteWorkPlane) {
  AppToast.show(..., message: l10n.cliExecutablePathLocateRemoteUnsupported, ...);
  return;
}
if (widget.locateOverride != null) return widget.locateOverride!();
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd client && flutter test test/pages/config/toolchain_path_locate_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement toolchain slot swap + `_locate`**

Same button pattern as Task 4. `_locate`:

1. If remote work plane → unsupported toast; return.
2. Else `locateOverride` or `ToolchainExecutableDiscovery().locateLocalTool(widget.toolId)`.
3. Success → set controller + `setToolchainPath` + success toast.
4. Failure → failed toast with `widget.title`.

Gate install button with `_isLocating` as well. Browse stays as today (toolchain currently always enables browse — do not change).

Add `locateOverride` constructor param like CLI row.

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd client && flutter test test/pages/config/toolchain_path_locate_test.dart \
  test/pages/config/cli_config_section_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/config/toolchain_path_settings_row.dart \
  client/test/pages/config/toolchain_path_locate_test.dart
git commit -m "$(cat <<'EOF'
feat(settings): swap toolchain Reset to Locate when path empty

EOF
)"
```

---

### Task 6: Verification

**Files:** none (verify only)

- [ ] **Step 1: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no new errors in touched files.

- [ ] **Step 2: Run targeted + discovery tests**

```bash
cd client && flutter test \
  test/services/cli/cli_executable_discovery_test.dart \
  test/services/cli/toolchain_executable_discovery_test.dart \
  test/pages/config/cli_config_section_test.dart \
  test/pages/config/toolchain_path_locate_test.dart
```

Expected: all PASS.

- [ ] **Step 3: Manual smoke (optional, human)**

Settings → CLI: set a path → Reset → Locate appears → Locate fills path → Reset returns. With SSH work plane, toolchain Locate shows unsupported toast.

- [ ] **Step 4: Final commit only if Step 1–2 left uncommitted fixes**

Otherwise done — no empty commit.

---

## Execution notes

- Do **not** call `mergeLocatedExecutables` / `mergeLocatedToolchains` after Locate persist (spec invariant).
- Reuse `resetKey` for the shared button; do not add `locateKey` in v1.
- Prefer Chinese UI copy from `app_zh.arb`; do not edit generated `app_localizations_*.dart` by hand except via `flutter gen-l10n`.
