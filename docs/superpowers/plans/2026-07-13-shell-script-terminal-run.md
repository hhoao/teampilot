# Shell Script Terminal Run Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace built-in Run type `process` with IDEA-aligned **Shell Script** (`shellScript`) that defaults to injecting commands into workspace Terminal tabs, while preserving a non-terminal Run-panel path and deterministic `process` migration.

**Architecture:** Add `ShellScriptLaunchSchema` + `ShellScriptCommandBuilder` + `ShellScriptMigrator`. Route `shellScript` through a new `RunShellScriptLauncher` in `RunSessionManager`: terminal mode registers a lightweight `RunSession` and uses `WorkspaceTerminalRunService` (extracted from panel create/connect) to open/reuse a tab and `writeToPty`; non-terminal mode shells out via existing `ProcessRunExecutor`. UI gains a type picker, expanded schema form fields, and rerun rules keyed off `allowMultipleInstances`.

**Tech Stack:** Flutter, `flutter_bloc`, existing Run platform (`RunSessionManager`, `LaunchTypeRegistry`), workspace Terminal stack (`WorkspaceTerminalRegistry`, `WorkspaceShellConnector`, `WorkspaceTerminalConnectCoordinator`, `TerminalSession.input.writeToPty`), l10n ARB files.

**Spec:** [docs/superpowers/specs/2026-07-13-shell-script-terminal-run-design.md](../specs/2026-07-13-shell-script-terminal-run-design.md)

**Locked choices (from spec + plan):**

| Topic | Choice |
|-------|--------|
| Built-in wire type | `shellScript` (writers); `process` read alias only |
| Terminal execution | Approach A: login shell tab → wait `transportReadyForIo` → inject one line + `\r` |
| `scriptText` shape | `interpreterPath` + `interpreterOptions` + `-c` + single-quoted escaped text |
| `scriptFile` shape | `interpreterPath` + opts + quoted `scriptPath` + `scriptOptions` |
| Inject prefix | `cd` + optional `export` entries + interpreter, all `&&`-joined (quoted keys/values) |
| Transport timeout | 30s polling `session.transportReadyForIo` (same gate as PTY I/O) |
| Tab bind key | `(workspaceId, selectionKey)` where `selectionKey = targetId\|folderPath\|configId` |
| Migrated `process` | `executeInTerminal: false`; map to `scriptText` per spec branches |
| Terminal session exit | No exit-code watch; `RunLaunchHandle.exitCode` never completes until v2 |
| Stop (terminal) | `writeToPty('\x03')` + session → `exited` |
| Rerun when `allowMultipleInstances: false` | Restart only (hide New instance) |
| Non-terminal invocation | `shell: true`, `command` = `HostInteractiveShell.defaultExecutable()`, `args` = `['-c', fullLine]` |
| `process` alias in registry | Not registered; `normalizeLaunchType()` maps `process` → `shellScript` on read in store/platform |
| Multi-instance binding | `selectionKey → entryId` for reuse; `sessionId → entryId` always (Stop/focus/close) |
| Bootstrap order | `WorkspaceRunRegistry` precedes `WorkspaceShellConnector` — lazy resolver at launch time |
| Before launch / Show page | Out of scope |

---

## File map

| File | Action | Responsibility |
|------|--------|----------------|
| `client/lib/services/run/shell_script_launch_schema.dart` | Create | JSON schema, defaults, validate |
| `client/lib/services/run/shell_script_configuration.dart` | Create | Parse `LaunchConfiguration` → typed shell-script view |
| `client/lib/services/run/shell_script_migrator.dart` | Create | `process` → `shellScript` normalization |
| `client/lib/services/run/shell_script_command_builder.dart` | Create | Build inject line + non-terminal argv/shell command |
| `client/lib/services/run/shell_script_launcher.dart` | Create | `RunShellScriptLauncher` (terminal vs process branches) |
| `client/lib/services/terminal/workspace_terminal_run_service.dart` | Create | Tab open/reuse/bind/inject/interrupt |
| `client/lib/services/terminal/workspace_terminal_session_ops.dart` | Create | Shared create+connect extracted from panel |
| `client/lib/models/run/run_ui_intent.dart` | Create | `activateToolWindow` / `focusToolWindow` / surface hint |
| `client/lib/services/run/process_launch_schema.dart` | Keep | Used only by migrator tests / legacy references during transition |
| `client/lib/services/run/launch_type_registry.dart` | Modify | Register `shellScript` only (not `process`) |
| `client/lib/services/run/run_platform.dart` | Modify | `normalizeLaunchType`; validate/start; all `ProcessLaunchSchema` branches → `shellScript` |
| `client/lib/services/run/run_session_manager.dart` | Modify | Dispatch `shellScript` launcher; skip `_watchExit` for terminal-backed |
| `client/lib/services/run/workspace_run_platform_factory.dart` | Modify | Inject `RunShellScriptLauncher` via lazy terminal-deps resolver |
| `client/lib/services/terminal/terminal_session.dart` | Modify | Expose `transportReadyForIo` getter (delegate to launch controller) |
| `client/lib/services/run/launch_config_l10n.dart` | Modify | New field labels + validation codes |
| `client/lib/services/run/launch_config_schema_fields.dart` | Modify | Add `enum` field type; monospace for script/interpreter paths |
| `client/lib/services/run/launch_variable_expander.dart` | Modify | **Task 3:** expand all shell-script string fields before validate/build |
| `client/lib/cubits/run_cubit.dart` | Modify | `normalizeLaunchType` in select/create; `shellScript` defaults; `RunUiIntent`; remove `process` branches |
| `client/lib/widgets/run/run_config_type_picker_dialog.dart` | Create | IDEA-style type picker before editor |
| `client/lib/widgets/run/run_configurations_dialog.dart` | Modify | Add → type picker |
| `client/lib/widgets/run/run_toolbar_config_dropdown.dart` | Modify | Add config → type picker |
| `client/lib/widgets/run/run_config_editor_dialog.dart` | Modify | Default type `shellScript`; enum field for `execute` |
| `client/lib/widgets/run/launch_config_schema_form.dart` | Modify | `enum` control for `execute`; conditional scriptPath/scriptText |
| `client/lib/widgets/run/run_toolbar.dart` | Modify | Rerun dialog respects `allowMultipleInstances` |
| `client/lib/widgets/workspace_terminal_panel.dart` | Modify | Delegate create/connect to `WorkspaceTerminalSessionOps`; tab-close → service |
| `client/lib/widgets/workspace_bottom_dock.dart` | Modify | Consume `RunUiIntent` (Terminal vs Run tab + visibility) |
| `client/lib/app/app_shell.dart` | Modify | Wire `WorkspaceTerminalRunService` singleton |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | Modify | Shell Script strings |
| `client/test/services/run/shell_script_*_test.dart` | Create | Schema, migrator, command builder, launcher |
| `client/test/services/terminal/workspace_terminal_session_ops_test.dart` | Create | Ops create+connect (mocked) |
| `client/test/services/run/launch_config_store_test.dart` | Modify | `process` on disk → `shellScript` in memory |
| Existing `client/test/services/run/*`, `run_toolbar_test.dart`, etc. | Modify | Update `process` → `shellScript` expectations |

Keep files under soft limits (`docs/CODE_QUALITY.md`). Do not put terminal inject logic in widgets beyond focus/visibility hooks.

---

### Task 1: Shell Script schema + configuration model

**Files:**
- Create: `client/lib/services/run/shell_script_launch_schema.dart`
- Create: `client/lib/services/run/shell_script_configuration.dart`
- Create: `client/test/services/run/shell_script_launch_schema_test.dart`

- [ ] **Step 1: Write failing schema tests**

```dart
// shell_script_launch_schema_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/run/shell_script_launch_schema.dart';

void main() {
  test('defaults for new shellScript map', () {
    final withDefaults = ShellScriptLaunchSchema.withDefaults({});
    expect(withDefaults['execute'], 'scriptFile');
    expect(withDefaults['executeInTerminal'], true);
    expect(withDefaults['allowMultipleInstances'], false);
    expect(withDefaults['interpreterPath'], ShellScriptLaunchSchema.defaultInterpreterPath());
  });

  test('validate requires scriptPath when execute is scriptFile', () {
    final errors = ShellScriptLaunchSchema.validate({
      'execute': 'scriptFile',
      'scriptPath': '',
    });
    expect(errors, contains(ShellScriptValidationCodes.scriptPathRequired));
  });

  test('validate requires scriptText when execute is scriptText', () {
    final errors = ShellScriptLaunchSchema.validate({
      'execute': 'scriptText',
      'scriptText': '  ',
    });
    expect(errors, contains(ShellScriptValidationCodes.scriptTextRequired));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/run/shell_script_launch_schema_test.dart`
Expected: FAIL — library/target not found

- [ ] **Step 3: Implement schema + configuration parser**

```dart
// shell_script_launch_schema.dart
abstract final class ShellScriptLaunchSchema {
  static const typeName = 'shellScript';
  static const processAlias = 'process';

  static Map<String, Object?> withDefaults(Map<String, Object?> raw) { /* ... */ }

  static const configurationSchema = <String, Object?>{
    'type': 'object',
    'required': ['execute'],
    'properties': {
      'execute': {'type': 'string', 'enum': ['scriptFile', 'scriptText']},
      'scriptPath': {'type': 'string', 'title': 'Script path'},
      'scriptText': {'type': 'string', 'title': 'Script text'},
      'scriptOptions': {'type': 'string'},
      'interpreterPath': {'type': 'string'},
      'interpreterOptions': {'type': 'string'},
      'cwd': {'type': 'string'},
      'env': {'type': 'object', 'additionalProperties': {'type': 'string'}},
      'executeInTerminal': {'type': 'boolean'},
      'allowMultipleInstances': {'type': 'boolean'},
      'activateToolWindow': {'type': 'boolean'},
      'focusToolWindow': {'type': 'boolean'},
    },
  };

  static List<String> validate(Map<String, Object?> map) { /* stable codes */ }
}
```

`ShellScriptConfiguration.fromLaunchConfiguration(LaunchConfiguration c)` reads `c.toJson()` merged fields.

- [ ] **Step 4: Run tests**

Run: `cd client && flutter test test/services/run/shell_script_launch_schema_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/run/shell_script_launch_schema.dart \
  client/lib/services/run/shell_script_configuration.dart \
  client/test/services/run/shell_script_launch_schema_test.dart
git commit -m "feat(run): add shellScript launch schema and configuration model"
```

---

### Task 2: `process` → `shellScript` migrator

**Files:**
- Create: `client/lib/services/run/shell_script_migrator.dart`
- Create: `client/test/services/run/shell_script_migrator_test.dart`
- Modify: `client/lib/services/run/launch_config_store.dart` (normalize on read in `listConfigurations` path)

- [ ] **Step 1: Write failing migration tests**

```dart
test('shell true maps to scriptText with joined command line', () { /* ... */ });

test('flutter run style maps to quoted scriptText (branch 2)', () {
  final migrated = ShellScriptMigrator.migrate({
    'type': 'process',
    'command': 'flutter',
    'args': ['run'],
  });
  expect(migrated['type'], 'shellScript');
  expect(migrated['execute'], 'scriptText');
  expect(migrated['executeInTerminal'], false);
  expect(migrated['activateToolWindow'], true);
  expect(migrated['interpreterPath'], isNotEmpty);
});

test('launch_config_store loads process json as shellScript', () async {
  // MemoryLaunchConfigIo + listConfigurations round-trip
});
```

- [ ] **Step 2: Run test — expect FAIL**

- [ ] **Step 3: Implement migrator + hook store load**

`LaunchConfiguration.fromJson` path: if `type == 'process'`, run migrator and rebuild `LaunchConfiguration` (fields in `extras` + drop `command`/`args`/`shell`).

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(run): migrate process launch configs to shellScript"
```

---

### Task 3: Command builder + variable expansion (before validate/launch)

**Files:**
- Create: `client/lib/services/run/shell_script_command_builder.dart`
- Modify: `client/lib/services/run/launch_variable_expander.dart`
- Create: `client/test/services/run/shell_script_command_builder_test.dart`
- Modify: `client/test/services/run/launch_variable_expander_test.dart`

- [ ] **Step 1: Write failing expander tests for shell fields**

Expand `scriptPath`, `scriptText`, `interpreterPath`, `interpreterOptions`, `scriptOptions`, `cwd`, env values in configuration `extras` **before** validate/build (spec requirement).

- [ ] **Step 2: Write failing builder tests**

Cover:
- `scriptFile`: `cd '/proj' && /bin/bash ./scripts/a.sh --flag`
- `scriptText`: `cd '/proj' && /bin/bash -c 'echo hi'`
- env prefix: `cd ... && export 'FOO'='bar' && ...`
- shell-safe quoting for paths with spaces

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement builder**

```dart
class ShellScriptCommandBuilder {
  const ShellScriptCommandBuilder();

  /// Single line for terminal inject (ends without CR; caller adds \r).
  String buildInjectLine(ShellScriptConfiguration config);

  /// For non-terminal ProcessRunExecutor: returns shell invocation.
  ShellScriptProcessInvocation buildProcessInvocation(ShellScriptConfiguration config);
}

class ShellScriptProcessInvocation {
  const ShellScriptProcessInvocation({
    required this.command,
    required this.args,
    required this.shell,
    required this.cwd,
    required this.env,
  });
  final String command;
  final List<String> args;
  final bool shell;
  final String? cwd;
  final Map<String, String> env;
}
```

- [ ] **Step 3: Implement expander + builder**

Non-terminal locked shape:

```dart
ShellScriptProcessInvocation(
  command: HostInteractiveShell.defaultExecutable(),
  args: ['-c', fullLine],
  shell: true,
  cwd: expandedCwd,
  env: mergedEnv,
)
```

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(run): add shellScript command builder and field expansion"
```

---

### Task 4: Launch type registry + platform validation

**Files:**
- Modify: `client/lib/services/run/launch_type_registry.dart`
- Modify: `client/lib/services/run/run_platform.dart`
- Modify: `client/lib/cubits/run_cubit.dart` (`select` / `createConfiguration` / `schemaForType` fallbacks)
- Modify: `client/test/services/run/launch_type_registry_test.dart`
- Modify: `client/test/services/run/run_platform_test.dart`

- [ ] **Step 1: Update tests expecting built-in `process` → `shellScript`**

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Register `shellScript` in `LaunchTypeRegistry.withBuiltIns()`**

Add shared helper (e.g. `launch_type_normalize.dart`):

```dart
String normalizeLaunchType(String type) =>
  type == ShellScriptLaunchSchema.processAlias
      ? ShellScriptLaunchSchema.typeName
      : type;
```

Use in `run_platform.validateConfiguration`, `launch_config_store` load, and `run_cubit.select` (skip `provideOptions` for `shellScript` like old `process`).

Replace **all** `ProcessLaunchSchema.typeName` branches in `run_platform.dart` with `shellScript` checks (or `isBuiltInShellType(type)`).

`registry.get('process')` returns null — alias handled only at normalize layer.

- [ ] **Step 4: Run targeted tests — PASS**

- [ ] **Step 5: Commit**

---

### Task 5: Terminal transport API + session ops (extract from panel)

**Files:**
- Modify: `client/lib/services/terminal/terminal_session.dart`
- Create: `client/lib/services/terminal/workspace_terminal_session_ops.dart`
- Modify: `client/lib/widgets/workspace_terminal_panel.dart`
- Create: `client/test/services/terminal/workspace_terminal_session_ops_test.dart`

- [ ] **Step 1: Expose `transportReadyForIo` on `TerminalSession`**

```dart
// terminal_session.dart
bool get transportReadyForIo => _launch.transportReadyForIo;
```

Add unit test delegating to launch controller mock/stub.

- [ ] **Step 2: Write failing ops test (mock registry + connector)**

Test `createAndConnect` calls `group.addEntry` + connect coordinator with given `cwd` + `WorkspaceTerminalWorkspaceTargetSpec(targetId)`.

- [ ] **Step 3: Extract shared ops from panel `_addEntry` / `_runConnect`**

```dart
class WorkspaceTerminalSessionOps {
  Future<WorkspaceTerminalEntry> openEntry({
    required WorkspaceTerminalGroup group,
    required WorkspaceShellConnector connector,
    required WorkspaceTerminalConnectCoordinator connectCoordinator,
    required String cwd,
    required WorkspaceTerminalSessionSpec spec,
    required TerminalTheme theme,
    required String sshConnectFailedMessage,
    required bool select,
    String titleLabel = '',
  });
}
```

Panel delegates to ops; behavior unchanged for manual "+" tabs.

- [ ] **Step 4: Run `workspace_terminal_session_ops_test.dart` — PASS**

- [ ] **Step 5: Commit**

---

### Task 6: WorkspaceTerminalRunService + bootstrap wiring

**Files:**
- Create: `client/lib/services/terminal/workspace_terminal_run_service.dart`
- Create: `client/test/services/terminal/workspace_terminal_run_service_test.dart`
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/services/run/workspace_run_platform_factory.dart` (lazy deps holder)

**Bootstrap constraint:** `workspaceRunRegistry` is constructed at `app_shell.dart` ~733 before `workspaceShellConnector` ~758. Do **not** reorder blindly. Instead:

```dart
// app_shell.dart — after workspaceShellConnector exists:
final workspaceTerminalSessionOps = WorkspaceTerminalSessionOps();
final workspaceTerminalRunService = WorkspaceTerminalRunService();
final terminalRunDeps = TerminalRunDepsResolver(
  registry: workspaceTerminalRegistry,
  connector: workspaceShellConnector,
  ops: workspaceTerminalSessionOps,
  runService: workspaceTerminalRunService,
);
workspaceRunRegistry.setTerminalRunDeps(terminalRunDeps); // or pass into factory on create()
```

`WorkspaceRunPlatformFactory.create()` resolves deps at **launch time** when building `RunShellScriptLauncher`.

- [ ] **Step 1: Write failing service tests**

Cases:
- reuse bind when `allowMultipleInstances == false`
- new entry when `allowMultipleInstances == true` (does not overwrite prior `sessionId → entry`)
- dual maps: `bindKey → entryId` and `sessionId → entryId`
- `waitForReady` polls `entry.session.transportReadyForIo`, times out at 30s
- `inject` calls `writeToPty` with `line + '\r'`
- `interrupt` sends `\x03`
- `onEntryDisposed` clears bind + notifies listener

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement service**

```dart
class WorkspaceTerminalRunService {
  final Map<TerminalRunBindKey, String> _entryByBind = {};
  final Map<String, String> _entryBySession = {}; // sessionId → entryId
  final Map<String, TerminalRunBindKey> _bindByEntry = {};

  void registerSessionEntry({required String sessionId, required String entryId});
  // ...
}
```

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Wire `TerminalRunDepsResolver` in `app_shell.dart` after connector**

- [ ] **Step 6: Commit**

---

### Task 7: RunShellScriptLauncher + session manager integration

**Files:**
- Create: `client/lib/services/run/shell_script_launcher.dart`
- Modify: `client/lib/services/run/run_session_manager.dart`
- Modify: `client/lib/services/run/workspace_run_platform_factory.dart`
- Create: `client/test/services/run/shell_script_launcher_test.dart`
- Modify: `client/test/services/run/run_session_manager_test.dart`

- [ ] **Step 1: Write failing launcher tests**

Terminal branch:
- registers no `ProcessRunExecutor` call
- calls `openForRun` + `waitForReady` + `inject`
- returns `RunLaunchHandle` whose `stop` calls `interrupt`

Non-terminal branch:
- delegates to `ProcessRunExecutor` with built invocation

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement `RunShellScriptLauncher`**

Terminal `RunLaunchHandle`:

```dart
final exitCompleter = Completer<int>(); // intentionally never completed in v1
return RunLaunchHandle(
  exitCode: exitCompleter.future,
  stop: () async { terminalRuns.interrupt(entry); },
);
```

Register `sessionId → entryId` via `terminalRuns.registerSessionEntry`.

- [ ] **Step 4: Update `RunSessionManager` + `WorkspaceRunPlatformFactory`**

Factory replaces bare `DefaultRunProcessLauncher` with composite dispatch:

```dart
RunSessionManager(
  executor: RunShellScriptLauncher(..., processExecutor: ProcessRunExecutor(...)),
  // shellScript handled inside RunShellScriptLauncher; legacy process type removed after migrator
)
```

After successful terminal launch, **do not** call `_watchExit` when `executeInTerminal == true`:

```dart
final shell = ShellScriptConfiguration.fromLaunchConfiguration(expanded);
final watchExit = !shell.executeInTerminal;
if (watchExit) unawaited(_watchExit(...));
else _upsert(session.copyWith(status: RunSessionStatus.running));
```

- [ ] **Step 5: Run tests — PASS**

- [ ] **Step 6: Commit**

---

### Task 8: Run UI intent + bottom dock activation

**Files:**
- Create: `client/lib/models/run/run_ui_intent.dart`
- Modify: `client/lib/cubits/run_cubit.dart`
- Modify: `client/lib/widgets/workspace_bottom_dock.dart`

- [ ] **Step 1: Add `RunUiIntent` and emit from `runSelected` / compound start**

```dart
@immutable
class RunUiIntent {
  const RunUiIntent({
    required this.surface, // terminal | run
    required this.activateToolWindow,
    required this.focusToolWindow,
    this.terminalEntryId,
  });
  final RunToolSurface surface;
  final bool activateToolWindow;
  final bool focusToolWindow;
  final String? terminalEntryId;
}
```

Expose `Stream<RunUiIntent>` or single-slot in `RunState` consumed once by dock.

- [ ] **Step 2: Update `WorkspaceBottomDock`**

On intent:
- if `activateToolWindow`: `layout.setWorkspaceTerminalVisible(true)`
- switch `_tab` to Terminal or Run per `surface`
- if `focusToolWindow` + terminal entry id: call focus hook on panel (add `WorkspaceTerminalPanel.focusEntry(id)` using existing view key map)

**Important:** Change dock auto-switch logic: only auto-switch to **Run** tab when new session is **non-terminal** (`executeInTerminal: false`). Terminal sessions should not force Run tab.

- [ ] **Step 3: Manual smoke checklist** (document in commit message; no integration tag required)

- [ ] **Step 4: Commit**

---

### Task 9: Tab close cleanup hook

**Files:**
- Modify: `client/lib/widgets/workspace_terminal_panel.dart`
- Modify: `client/lib/services/run/run_session_manager.dart` (optional package-level callback)

- [ ] **Step 1: On tab close in panel, call `WorkspaceTerminalRunService.handleEntryClosed(entry.id)`**

- [ ] **Step 2: Service looks up bound `RunSession` via callback registry**

Wire: `RunSessionManager.registerTerminalSession(entryId, sessionId)` inside launcher; service notifies manager to mark `exited`.

- [ ] **Step 3: Unit test bind cleanup**

- [ ] **Step 4: Commit**

---

### Task 10: l10n + schema form + type picker UI

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/services/run/launch_config_l10n.dart`
- Modify: `client/lib/services/run/launch_config_schema_fields.dart`
- Modify: `client/lib/widgets/run/launch_config_schema_form.dart`
- Create: `client/lib/widgets/run/run_config_type_picker_dialog.dart`
- Modify: `client/lib/widgets/run/run_configurations_dialog.dart`
- Modify: `client/lib/widgets/run/run_toolbar_config_dropdown.dart`
- Modify: `client/lib/widgets/run/run_config_editor_dialog.dart`
- Modify: `client/lib/cubits/run_cubit.dart`
- Modify: `client/test/widgets/run/launch_config_schema_form_test.dart`
- Modify: `client/test/widgets/run/run_config_editor_dialog_test.dart`

- [ ] **Step 1: Add arb keys**

Examples:
- `runTypeShellScript` = "Shell Script" / 「Shell 脚本」
- `runFieldScriptPath`, `runFieldScriptText`, `runFieldExecute`, `runFieldInterpreterPath`, …
- `runFieldExecuteInTerminal`, `runFieldAllowMultipleInstances`, `runFieldActivateToolWindow`, `runFieldFocusToolWindow`
- `runPickLaunchType` title
- validation codes for new schema errors

Run: `cd client && flutter gen-l10n`

- [ ] **Step 2: Extend `launch_config_schema_fields.dart`**

Add `LaunchConfigSchemaFieldType.enumValue` when schema property has `'enum': [...]`.

- [ ] **Step 3: Extend `launch_config_schema_form.dart`**

- `execute` enum → `AppDropdownField` with scriptFile/scriptText labels
- Show `scriptPath` when `execute == scriptFile`; `scriptText` when `scriptText`
- Booleans → `AppFormField` checkbox style (match automations)

- Show `scriptPath` only when `execute == scriptFile`; `scriptText` only when `scriptText` (form currently renders all properties unconditionally — add conditional filter)
- Wire `ShellScriptValidationCodes` through `launch_config_l10n.dart` (same pattern as `LaunchConfigValidationCodes`)

- [ ] **Step 4: Type picker dialog**

```dart
Future<String?> showRunConfigTypePickerDialog(BuildContext context, {
  required List<LaunchTypeContribution> types,
});
```

Lists built-in Shell Script first, then extension types (disabled + reason when unavailable).

- [ ] **Step 5: Wire Add flows**

`RunConfigurationsDialog._create` and dropdown "Add" → picker → `showRunConfigEditorDialog(..., initialType: picked)`.

`createConfiguration` defaults:

```dart
configuration: LaunchConfiguration(
  id: '',
  name: '',
  type: type,
  extras: type == ShellScriptLaunchSchema.typeName
      ? ShellScriptLaunchSchema.withDefaults({})
      : const {},
),
```

Remove `command: ''` default for shellScript.

- [ ] **Step 6: Update widget tests (enum dropdown + conditional fields)**

- [ ] **Step 7: Commit**

---

### Task 11: Toolbar rerun dialog + Stop routing

**Files:**
- Modify: `client/lib/widgets/run/run_toolbar.dart`
- Modify: `client/lib/cubits/run_cubit.dart`
- Modify: `client/test/widgets/run/run_toolbar_test.dart`

- [ ] **Step 1: Write failing test — `allowMultipleInstances: false` hides New instance**

- [ ] **Step 2: Implement**

Read `allowMultipleInstances` from selected config extras via `ShellScriptConfiguration`.

When false and already running: dialog shows only Restart (+ Cancel).

- [ ] **Step 3: Ensure Stop uses session manager (terminal interrupt already wired via launcher.stop)**

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Commit**

---

### Task 12: Regression sweep + docs cross-link

**Files:**
- Modify: tests referencing `process` type throughout `client/test/services/run/`
- Modify: `docs/superpowers/specs/2026-07-11-workspace-run-platform-design.md` (short supersession note — optional one paragraph)

- [ ] **Step 1: Run full verification**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration
```

Expected: PASS (fix any broken tests from type rename)

- [ ] **Step 2: Commit**

```bash
git commit -m "test(run): update run platform tests for shellScript built-in"
```

---

## Testing matrix

| Area | Command / file |
|------|----------------|
| Schema + migrator | `flutter test test/services/run/shell_script_*` |
| Command builder | `flutter test test/services/run/shell_script_command_builder_test.dart` |
| Terminal service | `flutter test test/services/terminal/workspace_terminal_run_service_test.dart` |
| Session manager | `flutter test test/services/run/run_session_manager_test.dart` |
| UI | `flutter test test/widgets/run/` |
| Full | `flutter analyze ... && flutter test --exclude-tags integration` |

## Manual QA (post-implementation)

1. Add Shell Script (script file) → Run → bottom dock shows **Terminal**, command appears in new tab.
2. Run again with `allowMultipleInstances: false` → same tab, new inject.
3. Enable `allowMultipleInstances` → second tab.
4. Stop → Ctrl+C in tab; Run session exits.
5. Toggle `executeInTerminal: false` → output in Run panel; dock switches to Run.
6. Load legacy `.teampilot/launch.json` with `"type": "process"` → still runs (non-terminal).
7. Mixed workspace folder on SSH → terminal tab uses folder `targetId`.
8. Compound with two shellScript configs → two tabs / two sessions.

## Risk notes

| Risk | Mitigation |
|------|------------|
| Inject races shell prompt | Wait `transportReadyForIo` only (spec); add integration test later if flaky |
| Panel/service circular deps | Ops + service live under `services/terminal/`; panel only calls service on close/focus |
| `RunSession` list grows for terminal runs | Sessions stay `running` until Stop; user can dismiss from Run panel if shown — optional: hide Run page for terminal-only sessions in a follow-up (not in this plan) |
| Windows default interpreter | Use `COMSPEC` / `bash` detection same as `HostInteractiveShell`; document if gaps remain |
