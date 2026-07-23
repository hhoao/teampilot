# Workspace Status Bar + Resource Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an extensible workspace bottom status bar whose first item is an Orca-style Resource Manager (memory · terminal count pill → tree panel with CPU/Mem, kill, refresh).

**Architecture:** Mount `WorkspaceStatusBar` at `WorkspacePage` card level. `ResourceManagerCubit` merges workspace terminal bindings with `ProcessMetricsService` snapshots (open-popover 2s poll only). Local PTY pids flow `Pty.pid` → transport → `PtyProcessRegistry`; remote/SSH rows stay in the tree with `—` metrics.

**Tech Stack:** Flutter / Dart, `flutter_bloc`, existing `ChatCubit` / `WorkspaceTerminalRegistry` / `flutter_pty_new`, Tp theme.

**Spec:** `docs/superpowers/specs/2026-07-23-workspace-status-bar-resource-manager-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/resource_manager/resource_memory_models.dart` | `ResourceMemorySnapshot`, host/app/group/leaf types, history rings |
| `client/lib/services/resource_manager/resource_binding.dart` | Binding kinds, stable `bindingKey`, leaf/group VM inputs |
| `client/lib/services/resource_manager/resource_binding_collector.dart` | Collect chat member shells + workspace shells for one workspace |
| `client/lib/services/resource_manager/resource_tree_merge.dart` | Pure merge: bindings + snapshot → tree VM + closed count / totals |
| `client/lib/services/resource_manager/resource_memory_format.dart` | Format bytes / CPU / `—` display helpers |
| `client/lib/services/resource_manager/pty_process_registry.dart` | `bindingKey` ↔ pid register/unregister |
| `client/lib/services/resource_manager/process_table_parser.dart` | Parse `ps` / Windows process table fixtures → pid/ppid/cpu/rss rows |
| `client/lib/services/resource_manager/process_metrics_service.dart` | Coalesced host sweep + subtree sum + history rings (len 30) |
| `client/lib/cubits/resource_manager_cubit.dart` | Open/close, poll, merge, kill/navigate/refresh façade |
| `client/lib/widgets/workspace_status_bar/workspace_status_bar.dart` | Extensible strip + item interface |
| `client/lib/widgets/workspace_status_bar/resource_usage_status_item.dart` | Closed pill |
| `client/lib/widgets/workspace_status_bar/resource_manager_panel.dart` | Popover panel shell (header, totals, space stub) |
| `client/lib/widgets/workspace_status_bar/resource_manager_tree.dart` | Two-level tree + sparklines |
| `client/lib/services/terminal/terminal_transport.dart` | Abstract `int? get pid` (every implementer declares it) |
| `client/lib/services/terminal/local_pty_transport.dart` | Expose `Pty.pid` |
| `client/lib/services/terminal/ssh_pty_transport.dart` | `pid => null` |
| `client/lib/services/terminal/terminal_launch_controller.dart` | Add `int? get pid => _transport?.pid` (pid exposure only — no resource_manager import) |
| `client/lib/services/terminal/terminal_session.dart` | Expose `int? get pid => _launch.pid` |
| `client/lib/pages/home_workspace/workspace/workspace_page.dart` | Column: body + status bar; provide cubit |
| `client/lib/pages/home_workspace/workspace/workspace_resource_manager_scope.dart` | Optional: adapters for bindings, kill, navigate; keep page thin |
| `client/lib/l10n/app_en.arb` + `app_zh.arb` | All user-visible strings |
| `client/lib/widgets/workspace_status_bar/resource_memory_sparkline.dart` | Compact memory history sparkline |
| Tests under `client/test/services/resource_manager/` and `client/test/cubits/` / `client/test/widgets/workspace_status_bar/` | As listed per task |

**PID registry ownership (locked):** `ResourceManagerCubit.syncRegistryFromBindings()` reads each binding’s live `TerminalSession.pid` and replaces `PtyProcessRegistry` entries. Do **not** call registry APIs from `terminal_launch_controller.dart`. Launch controller may only expose `pid` from `_transport`.

### Stable `bindingKey` scheme

| Kind | Key |
|------|-----|
| Chat member shell | `chat:{sessionId}:{memberId}` |
| Workspace shell tab | `shell:{workspaceId}:{entryId}` |

Navigate/kill dispatch on the prefix. WSL with a local pid: metrics like desktop local; no local pid: `—` (same as SSH).

### Sparkline ring

Keep **30** oldest-first memory samples per app total and per worktree group key (Orca-like). Drop oldest when full.

---

### Task 1: Models, formatters, tree merge (TDD)

**Files:**
- Create: `client/lib/services/resource_manager/resource_memory_models.dart`
- Create: `client/lib/services/resource_manager/resource_binding.dart`
- Create: `client/lib/services/resource_manager/resource_memory_format.dart`
- Create: `client/lib/services/resource_manager/resource_tree_merge.dart`
- Create: `client/test/services/resource_manager/resource_tree_merge_test.dart`
- Create: `client/test/services/resource_manager/resource_memory_format_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// resource_memory_format_test.dart
test('formats bytes as MB with one decimal', () {
  expect(formatResourceMemory(960.8 * 1024 * 1024), '960.8 MB');
});

test('null memory formats as em dash', () {
  expect(formatResourceMemory(null), '—');
});

test('null cpu formats as em dash', () {
  expect(formatResourceCpu(null), '—');
});
```

```dart
// resource_tree_merge_test.dart
test('closed count is binding leaf count not host process count', () {
  final bindings = [
    ResourceBinding(
      key: 'chat:s1:m1',
      kind: ResourceBindingKind.chatMember,
      groupKey: 'main',
      groupLabel: 'main',
      title: 'Terminal 1',
      connected: true,
      sessionId: 's1',
      memberId: 'm1',
    ),
    ResourceBinding(
      key: 'shell:w1:e1',
      kind: ResourceBindingKind.workspaceShell,
      groupKey: 'main',
      groupLabel: 'main',
      title: 'Shell',
      connected: false,
      workspaceId: 'w1',
      shellEntryId: 'e1',
    ),
  ];
  final vm = mergeResourceTree(bindings: bindings, snapshot: null);
  expect(vm.terminalCount, 2);
  expect(vm.groups.single.leaves, hasLength(2));
  expect(vm.groups.single.leaves.first.cpuDisplay, '—');
});

test('merges metrics onto matching bindingKey and aggregates group', () {
  final bindings = [
    ResourceBinding(
      key: 'chat:s1:m1',
      kind: ResourceBindingKind.chatMember,
      groupKey: 'main',
      groupLabel: 'main',
      title: 'Terminal 1',
      connected: true,
      sessionId: 's1',
      memberId: 'm1',
    ),
  ];
  final snapshot = ResourceMemorySnapshot(
    collectedAt: DateTime.utc(2026, 1, 1),
    totalCpu: 1.5,
    totalMemory: 10 * 1024 * 1024,
    leafMetrics: {
      'chat:s1:m1': const ResourceLeafMetrics(cpu: 1.5, memoryBytes: 10 * 1024 * 1024),
    },
  );
  final vm = mergeResourceTree(bindings: bindings, snapshot: snapshot);
  expect(vm.groups.single.leaves.single.cpuDisplay, isNot('—'));
  expect(vm.groups.single.aggregateMemoryBytes, 10 * 1024 * 1024);
});

test('unmatched snapshot pids do not create extra leaves', () {
  final bindings = [
    ResourceBinding(
      key: 'chat:s1:m1',
      kind: ResourceBindingKind.chatMember,
      groupKey: 'main',
      groupLabel: 'main',
      title: 'Terminal 1',
      connected: true,
      sessionId: 's1',
      memberId: 'm1',
    ),
  ];
  final snapshot = ResourceMemorySnapshot(
    collectedAt: DateTime.utc(2026, 1, 1),
    leafMetrics: {
      'chat:other:x': const ResourceLeafMetrics(cpu: 9, memoryBytes: 99),
    },
  );
  final vm = mergeResourceTree(bindings: bindings, snapshot: snapshot);
  expect(vm.groups.single.leaves, hasLength(1));
  expect(vm.groups.single.leaves.single.cpuDisplay, '—');
});
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd client && flutter test test/services/resource_manager/resource_memory_format_test.dart test/services/resource_manager/resource_tree_merge_test.dart
```

- [ ] **Step 3: Implement models + format + merge**

Define:

- `ResourceBinding` / `ResourceBindingKind`
- `ResourceMemorySnapshot` (+ host, optional app, per-key history)
- `ResourceTreeViewModel` / `ResourceTreeGroupVm` / `ResourceTreeLeafVm`
- `mergeResourceTree({required List<ResourceBinding> bindings, ResourceMemorySnapshot? snapshot})`
- Two-level grouping by `groupKey`; sort groups with `main` / main-worktree first if label matches; leaves by title

- [ ] **Step 4: Run tests — expect PASS**

```bash
cd client && flutter test test/services/resource_manager/resource_memory_format_test.dart test/services/resource_manager/resource_tree_merge_test.dart
```

- [ ] **Step 5: Commit** (only if user asked to commit)

```bash
git add client/lib/services/resource_manager/ client/test/services/resource_manager/
git commit -m "feat(resource-manager): add snapshot models and tree merge"
```

---

### Task 2: Binding collector (TDD)

**Files:**
- Create: `client/lib/services/resource_manager/resource_binding_collector.dart`
- Create: `client/test/services/resource_manager/resource_binding_collector_test.dart`
- Reuse: `client/lib/utils/session/session_worktree_grouping.dart` (`worktreePathForSessionPath`)

- [ ] **Step 1: Write failing tests** with fake session/shell lists (plain data structs or thin fakes — do not boot full `ChatCubit` if avoidable). Prefer a collector API that takes already-extracted inputs:

```dart
List<ResourceBinding> collectResourceBindings({
  required String workspaceId,
  required List<ChatMemberShellRef> chatShells,
  required List<WorkspaceShellRef> workspaceShells,
  required List<GitWorktree> worktrees,
});
```

Assert:

- Keys follow `chat:` / `shell:` scheme
- Group key = matched worktree path or `'main'` for **both** chat shells (via session primary path) and workspace shells (via shell `cwd`)
- Disconnected shells still included
- Only shells for `workspaceId`

- [ ] **Step 2: Run — expect FAIL**

```bash
cd client && flutter test test/services/resource_manager/resource_binding_collector_test.dart
```

- [ ] **Step 3: Implement collector + thin adapters**

Add a small helper on the cubit/UI side later that maps `ChatCubit` + `WorkspaceTerminalRegistry` → `ChatMemberShellRef` / `WorkspaceShellRef`. Keep mapping out of the pure collector if possible.

Title: prefer session display title + member name for chat; `titleLabel` for workspace shells.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit** (if requested)

---

### Task 3: PID plumbing + PtyProcessRegistry (TDD)

**Files:**
- Modify: `client/lib/services/terminal/terminal_transport.dart`
- Modify: `client/lib/services/terminal/local_pty_transport.dart`
- Modify: `client/lib/services/terminal/ssh_pty_transport.dart`
- Modify: `client/lib/services/terminal/terminal_launch_controller.dart` — **only** add `int? get pid => _transport?.pid` (no registry)
- Modify: `client/lib/services/terminal/terminal_session.dart` — `int? get pid => _launch.pid`
- Create: `client/lib/services/resource_manager/pty_process_registry.dart`
- Create: `client/test/services/resource_manager/pty_process_registry_test.dart`

- [ ] **Step 1: Failing registry tests**

```dart
test('register and list by bindingKey', () {
  final r = PtyProcessRegistry();
  r.register(bindingKey: 'chat:s1:m1', pid: 42);
  expect(r.pidFor('chat:s1:m1'), 42);
  expect(r.entries, hasLength(1));
});

test('unregister removes entry', () { … });

test('register with null pid is a no-op', () { … });
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

```dart
// terminal_transport.dart
abstract class TerminalTransport {
  // existing…
  int? get pid;
}

// local_pty_transport.dart
@override
int? get pid {
  final p = _pty.pid;
  return p > 0 ? p : null;
}
```

Add `int? get pid => null` on `SshPtyTransport` and **every** test/fake transport that `implements TerminalTransport`.

Expose the read path: `LocalPtyTransport.pid` → `TerminalLaunchController.pid` → `TerminalSession.pid`. Registry sync happens only in Task 6/9 via `ResourceManagerCubit.syncRegistryFromBindings()`.

- [ ] **Step 4: Run — expect PASS** + analyze touched terminal files

```bash
cd client && flutter test test/services/resource_manager/pty_process_registry_test.dart
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/terminal/ lib/services/resource_manager/pty_process_registry.dart
```

- [ ] **Step 5: Commit** (if requested)

---

### Task 4: Process table parser (TDD)

**Files:**
- Create: `client/lib/services/resource_manager/process_table_parser.dart`
- Create: `client/test/services/resource_manager/process_table_parser_test.dart`
- Create fixtures: `client/test/services/resource_manager/fixtures/ps_unix.txt` (and Windows sample if needed)

- [ ] **Step 1: Failing tests** with fixture output resembling:

```text
PID PPID %CPU RSS
1 0 0.0 1024
42 1 1.5 20480
43 42 0.2 4096
```

Assert subtree sum for pid 42 includes 42+43 RSS and CPU.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement Unix parser + Windows parser** (separate functions). Keep platform choice in `ProcessMetricsService`, not in the parser.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit** (if requested)

---

### Task 5: ProcessMetricsService (TDD)

**Files:**
- Create: `client/lib/services/resource_manager/process_metrics_service.dart`
- Create: `client/test/services/resource_manager/process_metrics_service_test.dart`

- [ ] **Step 1: Failing tests** injecting a `Future<String> Function()` process-table reader and host mem provider:

```dart
test('coalesces concurrent collect into one sweep', () async {
  var calls = 0;
  final svc = ProcessMetricsService(
    readProcessTable: () async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return fixture;
    },
    readHostMemory: () async => fakeHost,
    appPid: () => 1,
  );
  final a = svc.collect(registered: { 'chat:s1:m1': 42 });
  final b = svc.collect(registered: { 'chat:s1:m1': 42 });
  await Future.wait([a, b]);
  expect(calls, 1);
});

test('appends history and caps at 30', () async { … });

test('missing pid yields null leaf metrics', () async { … });
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

- Default production reader: `Process.run` with timeout (5s), platform command selection (Linux/macOS `ps`, Windows CIM/wmic).
- Host: `Platform` / `/proc/meminfo` / `sysctl` best-effort; on failure host fields null.
- App process: look up app via top-level `pid` from `dart:io`.
- `collect({required Map<String, int> registeredPids, required Map<String, String> bindingKeyToGroupKey})` so group sparkline rings can be keyed by `groupKey`.
- History rings keyed by `'app'` and by each binding `groupKey` (worktree path or `'main'`); leaf metrics keyed by `bindingKey`.
- Never throw to UI; return last-good or empty snapshot on failure.
- **Android / no sweep:** bar + tree still work; collector returns snapshot with null leaf metrics → UI `—` (same as SSH without local pid). WSL with local pid: metrics like desktop.

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit** (if requested)

---

### Task 6: ResourceManagerCubit (TDD)

**Files:**
- Create: `client/lib/cubits/resource_manager_cubit.dart`
- Create: `client/lib/cubits/resource_manager_state.dart` (or private in same file if small)
- Create: `client/test/cubits/resource_manager_cubit_test.dart`

- [ ] **Step 1: Failing tests** with fake metrics + fake binding source:

```dart
test('open starts polling; close cancels', () async { … });
test('closed state does not call collect', () async { … });
test('refresh forces collect while open', () async { … });
test('workspace change closes panel and stops timer', () async { … });
test('killLeaf invokes injector once per key', () async { … });
test('killAll invokes injector for each leaf', () async { … });
test('kill failure sets error and does not remove leaf until bindings refresh', () async { … });
test('snapshot failure keeps last good snapshot and sets error', () async { … });
test('syncRegistry drops null livePid and replaces map', () async { … });
```

Use injectable `Duration pollInterval` default `2s` (tests use `Duration.zero` or fake async).
- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement cubit**

State fields: `workspaceId`, `isOpen`, `bindings`, `snapshot`, `tree`, `terminalCount`, `error`, `expandedGroupKeys`.

Methods: `setWorkspace`, `openPanel`, `closePanel`, `togglePanel`, `refresh`, `killLeaf`, `killAll`, `onRouteActiveChanged(bool)` (close + stop when inactive), **`syncRegistryFromBindings()`** (or private `_syncRegistry` called whenever bindings update and on each open/poll tick before `collect`).

Constructor inject: `ProcessMetricsService`, `PtyProcessRegistry`, binding source that yields `List<ResourceBinding>` **plus** `Map<String, int?> bindingKey → livePid` (or each binding carries optional `livePid`), `Future<void> Function(String bindingKey) killBinding`.

`syncRegistryFromBindings`: **clear-and-replace** (or equivalent): build the desired map from current bindings’ **non-null** `livePid` only; unregister any registry key missing from that map **or** whose binding’s `livePid` is now null. Never leave a stale pid for a still-listed disconnected shell. Then `collect(registeredPids: registry.asMap, bindingKeyToGroupKey: …)`.

Closed pill memory uses **last good snapshot** (do not clear `snapshot` on `closePanel`).

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit** (if requested)

---

### Task 7: Status bar shell + WorkspacePage mount

**Files:**
- Create: `client/lib/widgets/workspace_status_bar/workspace_status_bar.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_page.dart`
- Wire DI near existing app providers if cubit must be workspace-scoped — prefer creating cubit in `WorkspacePage` state (`BlocProvider` in page) so each workspace tab has its own instance.

- [ ] **Step 1: Define item interface**

```dart
abstract class WorkspaceStatusBarItem {
  String get id;
  Widget buildSegment(BuildContext context, {required bool compact});
}
```

`WorkspaceStatusBar` lays out a height ~30 bar, `MainAxisAlignment.end` for right cluster, children = items.

- [ ] **Step 2: Mount**

Change `_buildLivePage` / card body so child of `WorkspacePageCardShell` is:

```dart
Column(
  children: [
    Expanded(child: _buildCardBody(...)),
    WorkspaceStatusBar(items: const [/* Task 8 fills */]),
  ],
)
```

Provide `ResourceManagerCubit` above the bar (and panel). On `WorkspaceRouteActiveScope` inactive: `cubit.onRouteActiveChanged(false)`.

- [ ] **Step 3: Smoke analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/home_workspace/workspace/workspace_page.dart lib/widgets/workspace_status_bar/
```

- [ ] **Step 4: Commit** (if requested)

---

### Task 8: Pill + panel UI + l10n

**Files:**
- Create: `client/lib/widgets/workspace_status_bar/resource_usage_status_item.dart`
- Create: `client/lib/widgets/workspace_status_bar/resource_manager_panel.dart`
- Create: `client/lib/widgets/workspace_status_bar/resource_manager_tree.dart`
- Create: `client/lib/widgets/workspace_status_bar/resource_memory_sparkline.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Create: `client/test/widgets/workspace_status_bar/resource_usage_status_item_test.dart`
- After ARB: run `flutter gen-l10n` (project default) and `dart run tool/gen_warmup_glyphs.dart` if required by repo convention

- [ ] **Step 1: Add ARB keys** (en + zh): Resource Manager title, tooltip template, column Name/CPU/Memory, refresh, kill, kill all, confirm kill all, Space, Beta, space not scanned, system memory percent, terminals count, empty tree.

- [ ] **Step 2: Widget tests**

- Pill: fake cubit `terminalCount: 2`, `totalMemoryLabel: '960.8 MB'`; expect those texts.
- Panel: leaf with null CPU/Mem renders `—`; when `state.error != null`, header shows subtle error affordance (icon or muted error text from l10n).

- [ ] **Step 3: Implement pill** — opens overlay/`showMenu`-style popover or `CompositedTransformFollower` anchored above; call `openPanel`/`closePanel`. Compact: when `MediaQuery.sizeOf(context).width < 720` (or LayoutBuilder), icon-only + short values.

- [ ] **Step 4: Implement panel** — header actions (incl. error affordance), totals + sparkline, optional app row (collapsed), tree, Space stub. Null metrics → `—`. Green connected dot.
- [ ] **Step 5: Run widget tests + analyze**

```bash
cd client && flutter test test/widgets/workspace_status_bar/
```

- [ ] **Step 6: Commit** (if requested)

---

### Task 9: Wire live bindings, kill, navigate

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_page.dart` (or a dedicated `workspace_resource_manager_scope.dart` under `pages/home_workspace/workspace/`)
- Modify: `client/lib/cubits/resource_manager_cubit.dart` adapters
- Possibly: `ChatCubit` read-only helpers; `WorkspaceTerminalRegistry` listeners

- [ ] **Step 1: Binding adapter** that, for `workspaceId`:

1. Lists open chat tabs/sessions for workspace → each `memberShells` entry → `ChatMemberShellRef` (+ worktree via `worktreePathForSessionPath(session.firstFolderPath, worktrees)`).
2. Lists `WorkspaceTerminalRegistry` group entries → `WorkspaceShellRef` including each entry’s `cwd` for worktree grouping.
3. Feeds collector; `cubit.syncRegistryFromBindings` updates `PtyProcessRegistry` from `TerminalSession.pid`.

Listen to `ChatCubit` stream + **`WorkspaceTerminalGroup`** for this workspace (`registry.groupFor(workspaceId)` is a `ChangeNotifier` — `WorkspaceTerminalRegistry` itself is **not**). Re-subscribe if the group instance is replaced.

- [ ] **Step 2: Kill**

`ChatCubit.disconnectSession()` only targets the **active** tab’s selected member — **do not** use it for Resource Manager.

Add a lifecycle helper (name up to implementer, e.g. `disconnectMemberShell(sessionId, memberId)` on `ChatCubit` / `SessionLaunchService`) that mirrors the active-path cleanup for an arbitrary pair: disconnect/dispose that `memberShells` entry, run the same remote-plane / SSH / agent-status teardown `disconnectSession` uses for a member, and **do not** close the session workbench tab.

Then:

- `chat:…` → that new helper with parsed `sessionId` + `memberId`.
- `shell:…` → `WorkspaceTerminalGroup.removeEntry` / entry dispose path.
- On kill failure: `AppToast` with l10n; cubit keeps leaf until bindings refresh.

Include a unit/cubit test that kill uses the helper with the binding’s ids, not `disconnectSession()`.

- [ ] **Step 3: Navigate** (UI-owned; then always `closePanel()`)

- Chat leaf → `WorkbenchCubit.ensureTab(workspaceId, WorkbenchTabId.session(sessionId), …)` (same pattern as `workspace_session_actions.dart` / `chat_workbench.dart`) + `ChatCubit.selectMember(memberId)` + `ChatCubit.setSessionWorkbenchView(sessionId, SessionWorkbenchView.terminal)` so the PTY is visible.
- Shell leaf → `WorkbenchCubit.ensureTab` / select `WorkbenchTabId.shell(entryId)` (and set group `activeId` if the shell surface requires it).
- **Always** `closePanel()` after successful navigate (spec Actions).

- [ ] **Step 4: Kill-all confirm** — `showDialog` with l10n; then `killAll`.
- [ ] **Step 5: Manual checklist** (document in PR): open workspace with 2 local terminals, open Resource Manager, see count/metrics update, kill one row, remote/SSH shows `—`.

- [ ] **Step 6: Commit** (if requested)

---

### Task 10: Verification sweep

- [ ] **Step 1: Run targeted tests**

```bash
cd client && flutter test test/services/resource_manager/ test/cubits/resource_manager_cubit_test.dart test/widgets/workspace_status_bar/
```

- [ ] **Step 2: Full gate**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration
```

- [ ] **Step 3: Fix any regressions** from analyze/test.

- [ ] **Step 4: Commit** (if requested) with message:

```bash
git commit -m "feat(workspace): add status bar Resource Manager"
```

---

## Execution notes

- Do not put `Process.run` in widgets.
- Do not poll metrics while panel closed.
- Do not implement Space disk scan.
- Do not add other status-bar segments in v1.
- Prefer splitting files early if any UI file approaches soft line limits (`docs/CODE_QUALITY.md`).
