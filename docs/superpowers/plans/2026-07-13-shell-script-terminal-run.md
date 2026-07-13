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
| Inject prefix | `cd <quoted-cwd> &&` + optional `export K=V;` per env entry |
| Transport timeout | 30s polling `session.transportReadyForIo` (same gate as PTY I/O) |
| Tab bind key | `(workspaceId, selectionKey)` where `selectionKey = targetId\|folderPath\|configId` |
| Migrated `process` | `executeInTerminal: false`; map to `scriptText` per spec branches |
| Terminal session exit | No exit-code watch; `RunLaunchHandle.exitCode` never completes until v2 |
| Stop (terminal) | `writeToPty('\x03')` + session → `exited` |
| Rerun when `allowMultipleInstances: false` | Restart only (hide New instance) |
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
| `client/lib/services/run/launch_type_registry.dart` | Modify | Register `shellScript`; `process` resolves to same schema |
| `client/lib/services/run/run_platform.dart` | Modify | Validate/start paths for `shellScript` |
| `client/lib/services/run/run_session_manager.dart` | Modify | Dispatch `shellScript` launcher; skip `_watchExit` for terminal-backed |
| `client/lib/services/run/launch_config_l10n.dart` | Modify | New field labels + validation codes |
| `client/lib/services/run/launch_config_schema_fields.dart` | Modify | Monospace keys for script/interpreter paths |
| `client/lib/services/run/launch_variable_expander.dart` | Modify | Expand shell-script string fields in `extras` |
| `client/lib/cubits/run_cubit.dart` | Modify | Defaults for new configs; expose `allowMultipleInstances`; emit `RunUiIntent` |
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
| `client/test/services/terminal/workspace_terminal_run_service_test.dart` | Create | Bind/reuse/inject (mocked) |
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
    expect(withDefaults['interpreterPath'], isNotEmpty);
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
test('shell true maps to scriptText with joined command line', () {
  final migrated = ShellScriptMigrator.migrate({
    'type': 'process',
    'command': 'npm',
    'args': ['run', 'dev'],
    'shell': true,
  });
  expect(migrated['type'], 'shellScript');
  expect(migrated['execute'], 'scriptText');
  expect(migrated['scriptText'], 'npm run dev');
  expect(migrated['executeInTerminal'], false);
  expect(migrated.containsKey('command'), false);
});

test('flutter run style maps to quoted scriptText', () {
  final migrated = ShellScriptMigrator.migrate({
    'type': 'process',
    'command': 'flutter',
    'args': ['run'],
  });
  expect(migrated['execute'], 'scriptText');
  expect(migrated['scriptText'], contains('flutter'));
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

### Task 3: Command builder (inject + non-terminal)

**Files:**
- Create: `client/lib/services/run/shell_script_command_builder.dart`
- Create: `client/test/services/run/shell_script_command_builder_test.dart`

- [ ] **Step 1: Write failing builder tests**

Cover:
- `scriptFile`: `cd '/proj' && /bin/bash ./scripts/a.sh --flag`
- `scriptText`: `cd '/proj' && /bin/bash -c 'echo hi'`
- env prefix: `export FOO=bar; cd ...`
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

Locked: non-terminal uses `shell: true` with `command` = default shell and `args` = `['-c', fullLine]` OR single `sh -c` string per existing executor conventions — pick one and test against `ProcessRunExecutor` expectations.

- [ ] **Step 4: Run — PASS**

- [ ] **Step 5: Commit**

---

### Task 4: Launch type registry + platform validation

**Files:**
- Modify: `client/lib/services/run/launch_type_registry.dart`
- Modify: `client/lib/services/run/run_platform.dart`
- Modify: `client/test/services/run/launch_type_registry_test.dart`
- Modify: `client/test/services/run/run_platform_test.dart`

- [ ] **Step 1: Update tests expecting built-in `process` → `shellScript`**

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Register `shellScript` in `LaunchTypeRegistry.withBuiltIns()`**

`registry.get('process')` may return null; `run_platform.validateConfiguration` normalizes alias:

```dart
String normalizeLaunchType(String type) =>
  type == ShellScriptLaunchSchema.processAlias
      ? ShellScriptLaunchSchema.typeName
      : type;
```

`isTypeAvailable('shellScript', ...)` always true (like old process).

- [ ] **Step 4: Run targeted tests — PASS**

- [ ] **Step 5: Commit**

---

### Task 5: Workspace terminal session ops (extract from panel)

**Files:**
- Create: `client/lib/services/terminal/workspace_terminal_session_ops.dart`
- Modify: `client/lib/widgets/workspace_terminal_panel.dart`

- [ ] **Step 1: Write failing unit test for ops (mock registry + connector)**

Test `createAndConnect` calls `group.addEntry` + connect coordinator with given `cwd` + `WorkspaceTerminalWorkspaceTargetSpec(targetId)`.

- [ ] **Step 2: Run — FAIL**

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

- [ ] **Step 4: Run widget-free tests + existing terminal tests if any — PASS**

- [ ] **Step 5: Commit**

---

### Task 6: WorkspaceTerminalRunService

**Files:**
- Create: `client/lib/services/terminal/workspace_terminal_run_service.dart`
- Create: `client/test/services/terminal/workspace_terminal_run_service_test.dart`
- Modify: `client/lib/app/app_shell.dart` (provide service)

- [ ] **Step 1: Write failing service tests**

Cases:
- reuse bind when `allowMultipleInstances == false`
- new entry when `allowMultipleInstances == true`
- `waitForReady` times out at 30s → throws
- `inject` calls `writeToPty` with `line + '\r'`
- `interrupt` sends `\x03`
- `onEntryDisposed` clears bind + notifies listener

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement service**

```dart
typedef TerminalRunBindKey = ({String workspaceId, String selectionKey});

class WorkspaceTerminalRunService {
  final Map<TerminalRunBindKey, String> _entryByBind = {};
  final Map<String, TerminalRunBindKey> _bindByEntry = {};

  Future<WorkspaceTerminalEntry> openForRun({
    required String workspaceId,
    required String selectionKey,
    required bool allowMultipleInstances,
    required String cwd,
    required String targetId,
    required String title,
    required WorkspaceTerminalSessionOps ops,
    // ... registry, connector, coordinator, theme, l10n error string
  });

  Future<void> waitForReady(WorkspaceTerminalEntry entry, {Duration timeout = const Duration(seconds: 30)});

  void inject(WorkspaceTerminalEntry entry, String line);
  void interrupt(WorkspaceTerminalEntry entry);
  void handleEntryClosed(String entryId); // called from panel on tab close
}
```

Use `WorkspaceTerminalWorkspaceTargetSpec(targetId)` for spec.

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Wire in `app_shell.dart` as lazy singleton (like registry)**

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

```dart
class RunShellScriptLauncher implements RunProcessLauncher {
  RunShellScriptLauncher({
    required ProcessRunExecutor executor,
    required RunTargetResolver resolver,
    required WorkspaceTerminalRunService terminalRuns,
    required WorkspaceTerminalSessionOps terminalOps,
    required ShellScriptCommandBuilder commandBuilder,
    required void Function(RunUiIntent intent) emitUiIntent,
    // inject workspaceId + theme/connect deps via closure or context holder
  });

  @override
  Future<RunLaunchHandle> launch({...});
}
```

- [ ] **Step 4: Update `RunSessionManager`**

```dart
Future<RunLaunchHandle> _launchForType(...) {
  final type = owned.configuration.type;
  if (type == ShellScriptLaunchSchema.typeName ||
      type == ShellScriptLaunchSchema.processAlias) {
    return _shellScriptLauncher.launch(...);
  }
  if (type == ProcessLaunchSchema.typeName) { /* remove after migrator always normalizes */ }
  ...
}
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

- [ ] **Step 2: Extend `launch_config_schema_form.dart`**

- `execute` enum → `AppDropdownField` with scriptFile/scriptText labels
- Show `scriptPath` when `execute == scriptFile`; `scriptText` when `scriptText`
- Booleans → `AppFormField` checkbox style (match automations)

- [ ] **Step 3: Type picker dialog**

```dart
Future<String?> showRunConfigTypePickerDialog(BuildContext context, {
  required List<LaunchTypeContribution> types,
});
```

Lists built-in Shell Script first, then extension types (disabled + reason when unavailable).

- [ ] **Step 4: Wire Add flows**

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

- [ ] **Step 5: Update widget tests**

- [ ] **Step 6: Commit**

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

### Task 12: Variable expansion for shell fields

**Files:**
- Modify: `client/lib/services/run/launch_variable_expander.dart`
- Create/extend: `client/test/services/run/launch_variable_expander_test.dart`

- [ ] **Step 1: Test expanding `scriptPath`, `scriptText`, `interpreterPath` in extras**

- [ ] **Step 2: Implement `expandShellScriptFields(Map<String, Object?> json, ...)`** called from launcher before build

- [ ] **Step 3: Commit**

---

### Task 13: Regression sweep + docs cross-link

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
