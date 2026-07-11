# Workspace Run Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an IDE-style Run platform: per-folder `.teampilot/launch.json`, built-in `process` runs, extension `launch-type` + Launch Adapter protocol, top-bar controls, bottom Run pages, parallel sessions — without touching agent launch profiles.

**Architecture:** Thin `RunPlatform` (config store, type registry, session manager, target resolver, adapter client) owned by per-workspace `RunCubit`. Execution always uses the config’s owning `WorkspaceFolder.targetId`. Adapters speak newline-delimited JSON-RPC on stdin/stdout; built-in `process` bypasses adapters but shares the same session/UI path.

**Tech Stack:** Flutter, `flutter_bloc`, existing PTY/SSH/WSL transport (`WorkspaceShellConnector` patterns), declarative `ExtensionManifest` effects, `AppLogger` + l10n.

**Spec:** [docs/superpowers/specs/2026-07-11-workspace-run-platform-design.md](../specs/2026-07-11-workspace-run-platform-design.md)

**Locked choices (from spec):**

| Topic | Choice |
|-------|--------|
| Scope v1 | Run only (no breakpoints/DAP) |
| Config file | `{folder.path}/.teampilot/launch.json` per `WorkspaceFolder` |
| Selection key | `(owningFolder, configId)` |
| Compounds | Same-file `id` refs only |
| Built-in type | `process` |
| Adapter runtime | `workspace` only; remote provisioning out of scope |
| Protocol framing | **Newline-delimited JSON-RPC** (one object per line on stdin/stdout) |
| Action / file pick | Host UI first, then `configureAction` with result |
| Agent launch | Untouched |

---

## File map (target)

| File | Responsibility |
|------|----------------|
| `client/lib/models/run/launch_config_document.dart` | Parse/serialize `launch.json` (`version`, configurations, compounds) |
| `client/lib/models/run/launch_configuration.dart` | Single config + owning folder identity |
| `client/lib/models/run/run_session.dart` | Runtime session state (`id`, status, exitCode, …) |
| `client/lib/models/run/launch_type_contribution.dart` | Parsed `launch-type` effect |
| `client/lib/services/run/launch_variable_expander.dart` | `${workspaceFolder}`, `${env:NAME}` |
| `client/lib/services/run/launch_config_store.dart` | Read/write/merge per-folder docs (reload on load/refresh; watch optional) |
| `client/lib/services/run/launch_type_registry.dart` | `process` + extension types; conflicts |
| `client/lib/services/run/process_launch_schema.dart` | Built-in `process` JSON schema fields |
| `client/lib/services/run/run_target_resolver.dart` | Folder → transport plan for process/adapter |
| `client/lib/services/run/run_session_manager.dart` | Parallel sessions, stop/restart, compounds |
| `client/lib/services/run/process_run_executor.dart` | Spawn `process` on resolved target |
| `client/lib/services/run/launch_adapter_protocol.dart` | Message types + encode/decode |
| `client/lib/services/run/launch_adapter_client.dart` | Spawn sticky/oneshot adapter, JSON-RPC |
| `client/lib/services/run/run_platform.dart` | Facade wiring store/registry/manager/adapters |
| `client/lib/services/run/run_terminal_bridge.dart` | Thin mapper: session output events → panel controllers (keep small; may live beside panel) |
| `client/lib/services/run/launch_type_registrar.dart` | Feed enabled extensions → registry; resolve `${extensionPath}`; probe availability on target |
| `client/lib/cubits/run_cubit.dart` | Per-workspace UI state |
| `client/lib/widgets/run/run_toolbar.dart` | Top-bar dropdown + Run/Stop + options + `isAction` |
| `client/lib/widgets/run/run_panel.dart` | Bottom Run pages (beside Terminal) |
| `client/lib/models/extension_manifest.dart` | Accessors for `launch-type` effect fields |
| `client/lib/pages/workspace_ide/workspace_ide_shell.dart` | Mount Run toolbar in IDE chrome |
| `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart` | Bottom slot: Terminal + Run panel |
| `client/lib/widgets/workspace_terminal_panel.dart` | Sibling reference for bottom chrome patterns |
| `client/test/services/run/**`, `client/test/cubits/run_cubit_test.dart` | Unit/protocol tests |
| `client/test/fixtures/fake_launch_adapter/` | Fixture adapter for protocol tests |

Keep files under soft limits (`docs/CODE_QUALITY.md`). Do not put Run logic in `ChatCubit` or `SessionLifecycleService`. `RunTerminalBridge` is a small helper — do not invent a second parallel output pipeline.

---

### Task 1: Launch config models + variable expansion

**Files:**
- Create: `client/lib/models/run/launch_config_document.dart`
- Create: `client/lib/models/run/launch_configuration.dart`
- Create: `client/lib/services/run/launch_variable_expander.dart`
- Create: `client/test/services/run/launch_config_document_test.dart`
- Create: `client/test/services/run/launch_variable_expander_test.dart`

- [ ] **Step 1: Write failing parse/expand tests**

```dart
// launch_config_document_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/run/launch_config_document.dart';

void main() {
  test('parses version, configurations, compounds', () {
    final doc = LaunchConfigDocument.fromJson({
      'version': 1,
      'configurations': [
        {
          'id': 'api',
          'name': 'API',
          'type': 'process',
          'request': 'launch',
          'command': 'echo',
          'args': ['hi'],
        },
      ],
      'compounds': [
        {
          'id': 'all',
          'name': 'All',
          'configurations': ['api'],
        },
      ],
    });
    expect(doc.version, 1);
    expect(doc.configurations.single.id, 'api');
    expect(doc.compounds.single.configurationIds, ['api']);
  });

  test('fills missing id from name slug on normalize', () {
    final doc = LaunchConfigDocument.fromJson({
      'version': 1,
      'configurations': [
        {'name': 'API Dev', 'type': 'process', 'command': 'true'},
      ],
    }).normalized();
    expect(doc.configurations.single.id, isNotEmpty);
  });
}
```

```dart
// launch_variable_expander_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/run/launch_variable_expander.dart';

void main() {
  test('expands workspaceFolder and env', () {
    final out = LaunchVariableExpander.expand(
      r'${workspaceFolder}/bin:${env:HOME}',
      workspaceFolder: '/proj',
      env: {'HOME': '/home/u'},
    );
    expect(out, '/proj/bin:/home/u');
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter test test/services/run/launch_config_document_test.dart test/services/run/launch_variable_expander_test.dart
```

Expected: FAIL (libraries not found).

- [ ] **Step 3: Implement models + expander**

- `LaunchConfigDocument` / `LaunchConfiguration` / `LaunchCompound` with `fromJson` / `toJson` / `normalized()` (assign ids).
- `OwnedLaunchConfiguration` (or fields on a view model): `WorkspaceFolder owner` + config.
- `LaunchVariableExpander.expand` for string fields; recursive map helper for `env` values / `cwd` / `args`.

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter test test/services/run/launch_config_document_test.dart test/services/run/launch_variable_expander_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/run client/lib/services/run/launch_variable_expander.dart client/test/services/run/launch_config_document_test.dart client/test/services/run/launch_variable_expander_test.dart
git commit -m "$(cat <<'EOF'
feat(run): add launch.json models and variable expansion

EOF
)"
```

---

### Task 2: `LaunchConfigStore` (per-folder merge)

**Files:**
- Create: `client/lib/services/run/launch_config_store.dart`
- Create: `client/test/services/run/launch_config_store_test.dart`
- Use: test filesystem helpers from `client/test/support/post_frame_test_harness.dart` if touching `AppStorage`; otherwise inject an abstract `LaunchConfigIo` for unit tests.

- [ ] **Step 1: Write failing merge test**

```dart
test('merges configs from multiple folders with owner tags', () async {
  final store = LaunchConfigStore(io: memoryIo);
  // folder A and B each have launch.json with id "main"
  final list = await store.listConfigurations(folders: [folderA, folderB]);
  expect(list, hasLength(2));
  expect(list.map((e) => e.selectionKey).toSet(), hasLength(2));
});

test('compound refs resolve only within same file', () async {
  final compounds = await store.listCompounds(folders: [folderA]);
  expect(compounds.single.configurationIds, ['a', 'b']);
});
```

Define `selectionKey` as a stable string or record: folder path + targetId + config id.

- [ ] **Step 2: Run test — expect FAIL**

- [ ] **Step 3: Implement store**

- Path: `{folder.path}/.teampilot/launch.json` via injected filesystem. **v1 of this task is local/memory IO only** — do not implement WSL/SSH reads here (that is Task 10). Document that production store will use folder `targetId` later.
- `listConfigurations`, `listCompounds`, `upsertConfiguration`, `writeDocument`.
- Missing file → empty list (not an error).
- **Watch (optional in this task):** if easy with injected IO, expose `watch(folders)` stream that reloads on file change; otherwise drop “watch” from the file map and reload on cubit `load()` / explicit refresh only.

- [ ] **Step 4: Tests PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(run): merge per-folder launch.json configs

EOF
)"
```

---

### Task 3: `LaunchTypeRegistry` + `process` schema + extension accessors

**Files:**
- Create: `client/lib/models/run/launch_type_contribution.dart`
- Create: `client/lib/services/run/launch_type_registry.dart`
- Create: `client/lib/services/run/process_launch_schema.dart`
- Modify: `client/lib/models/extension_manifest.dart` (launch-type getters)
- Create: `client/test/services/run/launch_type_registry_test.dart`
- Create: `client/test/models/extension_launch_type_effect_test.dart`

- [ ] **Step 1: Failing tests**

```dart
test('process type is always registered', () {
  final reg = LaunchTypeRegistry.withBuiltIns();
  expect(reg.get('process'), isNotNull);
});

test('duplicate type from two extensions marks conflict', () {
  final reg = LaunchTypeRegistry.withBuiltIns();
  reg.registerExtension(contribFlutterA);
  final result = reg.registerExtension(contribFlutterBSameType);
  expect(result.isConflict, isTrue);
  expect(reg.get('flutter')?.extensionId, contribFlutterA.extensionId);
});

test('launch-type effect parses type, adapter, kinds, discover, schema', () {
  final effect = ExtensionEffect.fromJson({
    'kind': 'launch-type',
    'type': 'flutter',
    'kinds': ['run'],
    'adapter': {
      'command': r'${extensionPath}/bin/adapter',
      'lifecycle': 'sticky',
      'runtime': 'workspace',
    },
    'configurationSchema': {
      'type': 'object',
      'required': ['device'],
      'properties': {
        'device': {'type': 'string'},
      },
    },
    'discover': {'enabled': true, 'globs': ['pubspec.yaml']},
  });
  final c = LaunchTypeContribution.fromEffect(
    extensionId: 'ext.flutter',
    effect: effect,
  );
  expect(c?.type, 'flutter');
  expect(c?.adapterRuntime, 'workspace');
  expect(c?.lifecycle, LaunchAdapterLifecycle.sticky);
  expect(c?.configurationSchema, isNotNull);
  expect(c?.configurationSchema!['required'], ['device']);
});
```

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement**

- `process` schema: require `command`; optional `args`, `env`, `cwd`, `shell`.
- `LaunchTypeContribution` **must** store `configurationSchema` (Map) from the effect for later validation.
- Reject `adapter.runtime` other than `workspace` at parse/register time.
- Registry API: `get`, `registerExtension`, `isAvailable(type, {required targetId})` stub returning true for `process`, false for extension types until Task 7 probes binary (document stub behavior in code comment).

- [ ] **Step 4: PASS + commit**

```bash
git commit -m "$(cat <<'EOF'
feat(run): register process type and launch-type extension effects

EOF
)"
```

---

### Task 4: `RunTargetResolver` + `ProcessRunExecutor` (local)

**Files:**
- Create: `client/lib/services/run/run_target_resolver.dart`
- Create: `client/lib/services/run/process_run_executor.dart`
- Create: `client/test/services/run/run_target_resolver_test.dart`
- Create: `client/test/services/run/process_run_executor_test.dart`
- Reference: `client/lib/services/terminal/workspace_shell_connector.dart`, `client/lib/models/workspace_shell_launch_plan.dart`

- [ ] **Step 1: Failing tests**

```dart
test('resolver uses owning folder path and targetId', () {
  final plan = RunTargetResolver().resolve(
    owner: WorkspaceFolder(path: '/proj', targetId: 'local'),
    cwd: r'${workspaceFolder}/app',
  );
  expect(plan.workingDirectory, '/proj/app');
  expect(plan.runtimeTarget, isA<LocalRuntimeTarget>()); // or existing RuntimeTarget shape
});

test('process executor runs command and reports exit 0', () async {
  final exec = ProcessRunExecutor(spawner: FakeSpawner());
  final result = await exec.start(
    sessionId: 's1',
    command: 'true',
    args: const [],
    plan: localPlan,
    onOutput: (_) {},
  );
  expect(await result.exitCode, 0);
});
```

Prefer constructor-injected process spawner (no raw `Process.start` in tests). **This task is local target only.** WSL/SSH process execution is **Task 10 only** — resolver may return a typed plan for non-local targets, but executor should throw a clear `UnsupportedError('remote process execution: Task 10')` until then.

- [ ] **Step 2–4: TDD implement, PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(run): resolve folder targets and execute process configs locally

EOF
)"
```

---

### Task 5: `RunSessionManager` (parallel, stop, restart, compound)

**Files:**
- Create: `client/lib/models/run/run_session.dart`
- Create: `client/lib/services/run/run_session_manager.dart`
- Create: `client/test/services/run/run_session_manager_test.dart`

- [ ] **Step 1: Failing tests**

```dart
test('two sessions can run in parallel', () async {
  final mgr = RunSessionManager(executor: fakeExecutor, adapters: noop);
  final a = await mgr.start(ownedConfigA);
  final b = await mgr.start(ownedConfigB);
  expect(mgr.sessions, hasLength(2));
  expect(a.id, isNot(b.id));
});

test('stop cancels running session', () async {
  final mgr = RunSessionManager(executor: hangExecutor, adapters: noop);
  final s = await mgr.start(ownedConfigA);
  await mgr.stop(s.id);
  expect(mgr.session(s.id)?.status, RunSessionStatus.exited);
});

test('compound starts all same-file members; partial failure keeps successes', () async {
  final ids = await mgr.startCompound(compound, documentConfigs);
  expect(ids, hasLength(2));
  // fakeExecutor: second config fails to start → still returns started ids + aggregated errors
  expect(mgr.sessions.where((s) => s.status == RunSessionStatus.running), isNotEmpty);
  expect(mgr.lastCompoundErrors, isNotEmpty);
});
```

- [ ] **Step 2–4: Implement manager**

- Allocate `sessionId` (UUID).
- Route `type == process` → `ProcessRunExecutor`; else → adapter client (stub throwing until Task 6).
- Same selection re-run: manager exposes `hasRunning(selectionKey)`; UI decides Restart vs new instance (Task 8).
- On executor exit → update status + exitCode; notify listeners/`Stream`.
- **Compound:** best-effort continue on partial failure; aggregate errors on the manager for UI; **group stop** via `stopCompound` / stop all returned session ids.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(run): manage parallel run sessions stop and compounds

EOF
)"
```

---

### Task 6: Launch Adapter protocol + client + fake adapter

**Files:**
- Create: `client/lib/services/run/launch_adapter_protocol.dart`
- Create: `client/lib/services/run/launch_adapter_client.dart`
- Create: `client/test/services/run/launch_adapter_client_test.dart`
- Create: `client/test/fixtures/fake_launch_adapter/` (Dart script that speaks the protocol)

**Protocol (locked):** newline-delimited JSON-RPC 2.0 objects on stdin/stdout.

Request example:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1}}
```

Notification example:

```json
{"jsonrpc":"2.0","method":"output","params":{"sessionId":"s1","category":"stdout","data":"hello\n"}}
```

**Required methods:** `initialize`, `launch`, `stop`, `shutdown`.

**v1 required for contribution surface (not optional):**

| Method / event | Direction | Purpose |
|----------------|-----------|---------|
| `provideOptions` | platform → adapter | `{ configurationId, configuration }` → `{ options: [LaunchOption] }` |
| `optionsChanged` | adapter → platform | push updated options |
| `configurationsChanged` | adapter → platform | dynamic list entries including `isAction: true` |
| `configureAction` | platform → adapter | host already collected UI result; see shapes below |

**`LaunchOption` shape:**

```json
{
  "id": "device",
  "label": "Device",
  "type": "choice",
  "value": "chrome",
  "choices": [{"value": "chrome", "label": "Chrome"}, {"value": "linux", "label": "Linux"}]
}
```

Supported `type` values v1: `string`, `boolean`, `choice`, `file`, `folder`.

**`configureAction` wire shape (host UI first):**

1. User picks an `isAction` item from the dropdown (from `configurationsChanged` or discover).
2. Host runs the needed UI (e.g. `file`/`folder` picker via existing window/file APIs).
3. Platform sends:

```json
{
  "jsonrpc": "2.0",
  "id": 10,
  "method": "configureAction",
  "params": {
    "actionId": "select_entry",
    "workspaceFolder": "/proj",
    "result": {"kind": "file", "path": "/proj/lib/main.dart"}
  }
}
```

4. Adapter responds with either a config draft to write/run:

```json
{
  "jsonrpc": "2.0",
  "id": 10,
  "result": {
    "configuration": {
      "id": "main",
      "name": "main.dart",
      "type": "flutter",
      "request": "launch",
      "target": "lib/main.dart"
    },
    "persist": true
  }
}
```

or `{ "cancelled": true }`. **Adapters never invoke host UI** — only consume `result`.

- [ ] **Step 1: Failing protocol test with fake adapter process**

```dart
test('initialize launch output exited', () async {
  final client = LaunchAdapterClient(
    startProcess: () => startFakeAdapter(),
    extensionPathResolver: (_) => '/ext/fake',
  );
  await client.initialize();
  final sessionId = 's1';
  await client.launch(sessionId: sessionId, configuration: {...});
  final outputs = await client.outputStream
      .where((e) => e.sessionId == sessionId)
      .take(1)
      .toList();
  expect(outputs.single.data, contains('ok'));
  final exited = await client.waitExited(sessionId);
  expect(exited.exitCode, 0);
});

test('configureAction returns configuration draft', () async {
  final draft = await client.configureAction(
    actionId: 'select_entry',
    workspaceFolder: '/proj',
    result: {'kind': 'file', 'path': '/proj/lib/main.dart'},
  );
  expect(draft.configuration?['id'], isNotEmpty);
});

test('provideOptions and optionsChanged', () async {
  final options = await client.provideOptions(
    configurationId: 'main',
    configuration: {'type': 'flutter'},
  );
  expect(options.single.id, 'device');
  // Fake adapter also pushes optionsChanged once after initialize.
  final pushed = await client.optionsChanged.take(1).first;
  expect(pushed, isNotEmpty);
});

test('configurationsChanged includes isAction', () async {
  final entries = await client.configurationsChanged.take(1).first;
  expect(entries.any((e) => e.isAction == true), isTrue);
});
```

Fake adapter: on `launch`, write one `output` then `exited` with 0; on `configureAction`, return a draft; on `provideOptions`, return a `device` choice; after `initialize`, emit `optionsChanged` + `configurationsChanged` (with one `isAction` item); on `stop`, exit early.

- [ ] **Step 2–4: Implement client**

- Sticky pool keyed by `(type, targetId)`. Support `oneshot` as: new process per `launch`, dispose after `exited`/`stop` (do not skip — manifest declares lifecycle).
- Timeouts on `initialize` / `launch` (constants in one place, e.g. 15s / 30s).
- Crash → fail all sessions for that adapter.
- Implement **request** `provideOptions` and **notification handlers** for `optionsChanged` / `configurationsChanged` / `output` / `exited` / `error` (expose as streams).
- `initialize` may negotiate capabilities; v1 client can ignore unknown caps. Stub or defer adapter-side `resolveConfiguration`, adapter `discover`, and optional `restart` (platform can stop+launch) unless needed by tests.
- Wire `RunSessionManager` to use client for non-`process` types.
- Expand `${extensionPath}` via an **injected** `ExtensionPathResolver` typedef/callback (e.g. `(extensionId) => path`). Do **not** depend on `LaunchTypeRegistrar` yet — Task 7 supplies the real resolver when constructing the client.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(run): add launch adapter JSON-RPC client and fixture

EOF
)"
```

---

### Task 7: Extension → registry wiring + `RunPlatform` + `RunCubit`

**Files:**
- Create: `client/lib/services/run/launch_type_registrar.dart`
- Create: `client/lib/services/run/run_platform.dart`
- Create: `client/lib/cubits/run_cubit.dart`
- Create: `client/lib/cubits/run_state.dart` (or private in cubit file if small)
- Create: `client/test/services/run/launch_type_registrar_test.dart`
- Create: `client/test/cubits/run_cubit_test.dart`
- Wire DI in workspace-scoped providers (follow how `ExtensionCubit` / workspace config is provided — `client/lib/app/app_shell.dart` and workspace page).

**Registrar behavior:**

1. Read enabled extensions for the workspace (same enablement chain as existing extension resolution: global → team → workspace overrides). Reuse `ExtensionCubit` / `ExtensionRepository` / `WorkspaceProjectConfig.effectiveExtensionEnabled` — do not invent a parallel enablement model.
2. For each enabled manifest, collect `effects` where `kind == 'launch-type'`, parse `LaunchTypeContribution`, `registerExtension` on the registry.
3. Run existing `detect` when deciding availability (reuse `ExtensionDetector` or equivalent).
4. Resolve `${extensionPath}` to the installed extension directory **on the run target**. v1: local path from acquisition layout; if folder `targetId` is remote and binary cannot be proven present → type unavailable for that folder (no host fallback).
5. Pass that path resolver into `LaunchAdapterClient` construction.
6. Rebuild registry when extension enablement changes.

- [ ] **Step 1: Failing tests**

```dart
test('registrar registers launch-type from enabled extension', () async {
  final reg = LaunchTypeRegistry.withBuiltIns();
  await LaunchTypeRegistrar(
    extensions: fakeEnabledWithFlutterLaunchType,
    detector: alwaysPresent,
    extensionPathFor: (_) => '/ext/flutter',
  ).rebuild(reg);
  expect(reg.get('flutter')?.extensionId, 'ext.flutter');
});

test('run selected process config creates session', () async {
  final cubit = RunCubit(platform: fakePlatform, folders: [folder]);
  await cubit.load();
  cubit.select(selectionKey);
  await cubit.runSelected();
  expect(cubit.state.sessions, isNotEmpty);
  expect(cubit.state.sessions.single.status, RunSessionStatus.running);
});

test('select loads options; setOption updates state', () async {
  final cubit = RunCubit(platform: fakePlatformWithOptions, folders: [folder]);
  await cubit.load();
  await cubit.select(selectionKey);
  expect(cubit.state.options, isNotEmpty);
  cubit.setOption('device', 'chrome');
  expect(cubit.state.optionValues['device'], 'chrome');
});

test('actions from configurationsChanged appear in state', () async {
  final cubit = RunCubit(platform: fakePlatformWithActions, folders: [folder]);
  await cubit.load();
  expect(cubit.state.actions.any((a) => a.isAction), isTrue);
});
```

State fields: `configurations`, `compounds`, `actions`, `selectedKey`, `options`, `optionValues`, `sessions`, `recommendations`, `errorMessage`.

Cubit API (required): `load`, `select`, `setOption`, `runSelected`, `stopSession`, `restartSession`, `stopCompound`, `refreshDiscover`, `acceptRecommendation`, `configureAction`, `openLaunchJson`.

- [ ] **Step 2–4: Implement + PASS**

- On `select` of a non-process config: call `provideOptions` and subscribe to `optionsChanged` for that type.
- Subscribe to `configurationsChanged` → update `state.actions`.
- `runSelected` / `stopSession` / `restartSession` / `configureAction`.
- `refreshDiscover` / `acceptRecommendation`: **no-op stubs** until Task 11 (return empty / throw `UnimplementedError` only in debug asserts — prefer empty success).
- **Schema validate before run and before persist** using built-in `process` schema or contribution `configurationSchema`; set `errorMessage` on failure (l10n keys in Task 10).

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(run): wire extensions into registry and add RunCubit

EOF
)"
```

---

### Task 8: Top-bar Run toolbar UI (options + isAction)

**Files:**
- Create: `client/lib/widgets/run/run_toolbar.dart`
- Modify: `client/lib/pages/workspace_ide/workspace_ide_shell.dart` (toolbar / actions chrome)
- Create: `client/test/widgets/run/run_toolbar_test.dart` (pump with mock cubit)

- [ ] **Step 1: Widget tests**

- Dropdown lists configs + `isAction` items.
- Choosing `isAction` triggers host file picker mock → `cubit.configureAction`.
- Inline `choice` option changes call `cubit.setOption`.
- Run button calls `cubit.runSelected`.

- [ ] **Step 2–4: Implement toolbar**

- Dropdown of merged configs (show folder label when >1 folder) + action items (`isAction`).
- Disable entries with unavailable type + tooltip reason.
- Inline dynamic options from cubit state (`provideOptions` / `optionsChanged`).
- Run / Stop; if same key running → dialog Restart vs New instance.
- “Open launch.json” → selected config’s owning file; else folder picker then open/create.
- Styling: existing shell actions + `AppControlTheme` height.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(run): add workspace top-bar run toolbar

EOF
)"
```

---

### Task 9: Bottom Run panel

**Files:**
- Create: `client/lib/widgets/run/run_panel.dart`
- Create: `client/lib/widgets/run/run_session_page.dart`
- Create: `client/lib/services/run/run_terminal_bridge.dart` (small)
- Modify: `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart` and/or bottom slot beside `client/lib/widgets/workspace_terminal_panel.dart`
- Reference: `docs/superpowers/specs/2026-07-10-workspace-panes-ide-shell-design.md`

- [ ] **Step 1: Test — new session focuses a Run page; output appends**

- [ ] **Step 2–4: Implement**

- Tab group “Run” beside Terminal (match existing bottom chrome).
- One page per session; stream output via `RunTerminalBridge` into a scrollable text log (**YAGNI: text log for all types in v1**).
- Close tab → confirm if running → `stop`.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(run): add bottom run session panel

EOF
)"
```

---

### Task 10: l10n, shortcuts, WSL/SSH IO + process path

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Modify: shortcuts registration (see shortcuts platform spec + existing command bus)
- Extend: `launch_config_store.dart`, `process_run_executor.dart`, `run_target_resolver.dart` for WSL/SSH using `WorkspaceShellConnector` patterns
- Tests: mocked transport selection (no live SSH required)

**This is the only task that implements remote process execution and remote `launch.json` reads.**

- [ ] **Step 1: Add ARB strings** (run, stop, restart, errors, unavailable type, open launch.json, options, …) then `flutter gen-l10n` if required.

- [ ] **Step 2: Register commands** `run.runSelected`, `run.stop`, `run.restart`.

- [ ] **Step 3: Remote store + process spawn** for WSL/SSH folder `targetId`. Adapter still unavailable if binary missing on target.

- [ ] **Step 4: Tests + analyze**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/services/run test/cubits/run_cubit_test.dart test/widgets/run --exclude-tags integration
```

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(run): add l10n shortcuts and remote process execution

EOF
)"
```

---

### Task 11: Discover recommendations + accept into `launch.json`

**Files:**
- Extend: `launch_type_registrar.dart`, `run_cubit.dart`, `run_toolbar.dart`
- Create: `client/test/services/run/launch_discover_test.dart`

- [ ] **Step 1: Test glob discover**

Given folder with `pubspec.yaml` and a registered type with `discover.globs`, `refreshDiscover` returns a recommendation; `acceptRecommendation` writes config into that folder’s `launch.json` after schema validation.

- [ ] **Step 2–4: Implement** (adapter `discover` optional; globs sufficient for v1)

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(run): discover and accept recommended launch configs

EOF
)"
```

---

### Task 12: End-to-end verification + spec status

**Files:**
- Modify: `docs/superpowers/specs/2026-07-11-workspace-run-platform-design.md` status → Implemented (when done)
- Manual checklist:

1. Local folder: create `.teampilot/launch.json` with `process` → Run → bottom page → Stop.
2. Two configs parallel; compound starts both; compound stop stops group.
3. Fake extension registered via registrar + fixture adapter run.
4. `isAction` → file picker → `configureAction` → draft persisted.
5. Dynamic option choice visible in toolbar.
6. SSH folder + missing adapter → disabled with reason.
7. Agent session launch unchanged.

- [x] **Step 1: Run full unit suite for run/**

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter test test/services/run test/cubits/run_cubit_test.dart test/widgets/run --exclude-tags integration && flutter analyze --no-fatal-infos --no-fatal-warnings
```

- [ ] **Step 2: Manual smoke on desktop**

- [x] **Step 3: Update spec status + commit**

```bash
git commit -m "$(cat <<'EOF'
docs(run): mark workspace run platform spec implemented

EOF
)"
```

---

## Out of scope (do not implement in this plan)

- Debug adapters / breakpoints
- VS Code `launch.json` import
- Remote extension/adapter provisioning
- In-host Dart plugin SDK
- First-party Flutter/Node adapters beyond fixtures
- Interactive PTY Run pages (text log first)
