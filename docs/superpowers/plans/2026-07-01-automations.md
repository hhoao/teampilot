# TeamPilot Automations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship unified project/session automations with app-level scheduling, cold-start dispatch, Orca-style management UI, and Session right-click timed lead messages.

**Architecture:** `AutomationRepository` persists per-workspace JSON + global catalog. `AutomationScheduler` ticks every 30s with missed-run grace. `AutomationDispatcher` routes `sendToLead` through TeamBus/PTY (same path as operator input) and `launchPrompt` through `SessionLaunchService`. `AutomationCubit` drives three UI entry points: `WorkspaceSidebar` top, `HomeGlobalView.automations`, and `SidebarSessionTile` context menu.

**Tech Stack:** Flutter/Dart, `flutter_bloc`, `timezone` package, existing ChatCubit / TabTeamBusCoordinator / SessionLifecycleService.

**Design authority:** [docs/superpowers/specs/2026-07-01-automations-design.md](../specs/2026-07-01-automations-design.md)

## Global Constraints

- **零向后兼容** — 新存储路径与 JSON schema；不迁移旧数据、不保留 deprecated 字段。
- 分层：`models/` + `repositories/` + `services/automation/` + `cubits/` + `pages/automations/` + `widgets/`；UI 不直接 `Process.run` 或读写路径。
- l10n：仅改 `app_en.arb` / `app_zh.arb`；改后跑 `dart run tool/gen_warmup_glyphs.dart`。
- 完成判据：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` 全绿。
- 每 Task 独立 commit。

## File Structure

| 文件 | 职责 |
|------|------|
| `client/lib/models/automation.dart` | 枚举 + `Automation` / `AutomationRun` JSON |
| `client/lib/services/storage/workspace_layout.dart` | `workspaceAutomationsFile`, `automationsCatalogFile` |
| `client/lib/repositories/automation_repository.dart` | CRUD、catalog、run 截断 |
| `client/lib/services/automation/automation_schedule_calculator.dart` | preset/cron → `nextRunAtMs` |
| `client/lib/services/automation/automation_dispatcher.dart` | `sendToLead` / `launchPrompt` |
| `client/lib/services/automation/automation_scheduler.dart` | tick + missed run |
| `client/lib/cubits/automation_cubit.dart` | UI 状态 |
| `client/lib/pages/automations/automations_panel.dart` | 列表 + 筛选 |
| `client/lib/pages/automations/automation_editor_dialog.dart` | 完整/compact 编辑 |
| `client/lib/pages/automations/automation_schedule_picker.dart` | 调度 UI |
| `client/lib/pages/automations/automation_management_page.dart` | 全局页 shell |
| `client/lib/pages/home_workspace/home_workspace_global_section.dart` | `HomeGlobalView.automations` |
| `client/lib/pages/home_workspace/home_workspace_sidebar.dart` | 「全部自动化」入口 |
| `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart` | 项目级顶部入口 |
| `client/lib/widgets/sidebar_session_tile.dart` | 右键「定时消息…」 |
| `client/lib/app/app_shell.dart` | DI + scheduler start |
| `client/test/services/automation/automation_schedule_calculator_test.dart` | 调度单测 |
| `client/test/repositories/automation_repository_test.dart` | 持久化单测 |
| `client/test/services/automation/automation_dispatcher_test.dart` | 分发 mock 测 |
| `client/test/cubits/automation_cubit_test.dart` | cubit 测 |

---

### Task 1: Model + dependency + layout paths

**Files:**
- Create: `client/lib/models/automation.dart`
- Modify: `client/lib/services/storage/workspace_layout.dart`
- Modify: `client/pubspec.yaml`

**Interfaces:**
- Produces: `Automation`, `AutomationRun`, enums, `toJson`/`fromJson`
- Produces: `WorkspaceLayout.workspaceAutomationsFile`, `WorkspaceLayout.automationsCatalogFile`

- [ ] **Step 1: Add `timezone` dependency**

In `client/pubspec.yaml` dependencies:

```yaml
  timezone: ^0.10.0
```

Run: `cd client && flutter pub get`

- [ ] **Step 2: Write failing model tests**

Create `client/test/models/automation_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  test('Automation round-trips JSON', () {
    final a = Automation(
      id: 'a1',
      name: 'Reset',
      action: AutomationAction.sendToLead,
      scope: AutomationScope.session,
      workspaceId: 'ws1',
      sessionId: 's1',
      targetMemberId: 'team-lead',
      message: '/clear',
      preset: AutomationSchedulePreset.hourly,
      minute: 0,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 1_700_000_000_000,
      enabled: true,
      createdAtMs: 1,
      updatedAtMs: 2,
    );
    final json = a.toJson();
    final back = Automation.fromJson(json);
    expect(back.id, 'a1');
    expect(back.action, AutomationAction.sendToLead);
    expect(back.cli, isNull);
  });

  test('launchPrompt requires cli', () {
    expect(
      () => Automation(
        id: 'x',
        name: 'n',
        action: AutomationAction.launchPrompt,
        scope: AutomationScope.workspace,
        workspaceId: 'ws',
        targetMemberId: 'team-lead',
        message: 'ping',
        cli: null,
        preset: AutomationSchedulePreset.daily,
        minute: 0,
        hourMinute: '09:00',
        timezone: 'UTC',
        dtstartMs: 0,
        enabled: true,
        createdAtMs: 0,
        updatedAtMs: 0,
      ).validate(),
      throwsA(isA<ArgumentError>()),
    );
  });
}
```

- [ ] **Step 3: Run test — expect FAIL**

Run: `cd client && flutter test test/models/automation_test.dart`
Expected: FAIL — file not found / class not defined

- [ ] **Step 4: Implement `automation.dart`**

Implement immutable classes with `copyWith`, `toJson`/`fromJson`, and `validate()`:
- `launchPrompt` requires non-null `cli`
- `scope == session` requires non-null `sessionId`
- `preset == custom` requires non-null non-empty `customCron`
- `preset == weekly` requires `dayOfWeek` 1–7

- [ ] **Step 5: Extend `workspace_layout.dart`**

```dart
String automationsRootDir() => _ctx.join(teampilotRoot, 'automations');

String automationsCatalogFile() =>
    _ctx.join(automationsRootDir(), 'catalog.json');

String workspaceAutomationsFile(String workspaceId) =>
    _ctx.join(workspaceDir(workspaceId), 'automations.json');
```

- [ ] **Step 6: Run tests — expect PASS**

Run: `cd client && flutter test test/models/automation_test.dart`

- [ ] **Step 7: Commit**

```bash
git add client/lib/models/automation.dart client/lib/services/storage/workspace_layout.dart client/pubspec.yaml client/pubspec.lock client/test/models/automation_test.dart
git commit -m "feat(automations): add model and storage layout paths"
```

---

### Task 2: AutomationRepository

**Files:**
- Create: `client/lib/repositories/automation_repository.dart`
- Test: `client/test/repositories/automation_repository_test.dart`

**Interfaces:**
- Consumes: `WorkspaceLayout`, `Filesystem`, `Automation`
- Produces:
  - `Future<List<Automation>> listForWorkspace(String workspaceId)`
  - `Future<List<Automation>> listAll()` — via catalog
  - `Future<List<Automation>> listForSession(String workspaceId, String sessionId)`
  - `Future<Automation> upsert(Automation automation)`
  - `Future<void> delete(String workspaceId, String automationId)`
  - `Future<void> appendRun(String workspaceId, AutomationRun run)`
  - `Future<List<AutomationRun>> runsFor(String workspaceId, {String? automationId})`
  - `Future<void> disableForSession(String workspaceId, String sessionId)`

On-disk shape for `automations.json`:

```json
{
  "automations": [ { ... } ],
  "runs": [ { ... } ]
}
```

Keep max 100 runs (drop oldest).

- [ ] **Step 1: Write failing repository tests**

Use `setUpTestAppStorage()` / `tearDownTestAppStorage()` from `test/support/post_frame_test_harness.dart`.

Test cases:
1. upsert + listForWorkspace round-trip
2. catalog updated on upsert
3. listAll aggregates two workspaces
4. appendRun truncates to 100
5. disableForSession sets enabled=false

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement repository**

Follow `CliPresetsRepository` error-logging style; use atomic write (`writeString`).

- [ ] **Step 4: Run — expect PASS**

Run: `cd client && flutter test test/repositories/automation_repository_test.dart`

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(automations): add AutomationRepository with catalog"
```

---

### Task 3: AutomationScheduleCalculator

**Files:**
- Create: `client/lib/services/automation/automation_schedule_calculator.dart`
- Test: `client/test/services/automation/automation_schedule_calculator_test.dart`

**Interfaces:**
- Produces:
  - `int computeNextRunAtMs(Automation automation, {required int afterMs})`
  - `bool isValidCron(String expression)`
  - `String formatScheduleSummary(Automation automation)` — for list UI

Port Orca preset semantics from `/home/hhoa/git/opensource/orca/src/shared/automation-schedules.ts` (hourly/daily/weekdays/weekly/custom 5-field cron only).

Initialize timezone database once:

```dart
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void ensureTimezoneInitialized() {
  tz_data.initializeTimeZones();
}
```

- [ ] **Step 1: Write failing tests**

Cases (use fixed `afterMs` + `timezone: 'UTC'`):
- hourly minute=30 → next :30
- daily 09:00 → next 09:00 UTC
- weekdays skips Sat/Sun
- weekly Monday 10:00
- custom `0 */2 * * *` (every 2 hours)
- invalid cron → `isValidCron` false

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement calculator**

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(automations): add schedule calculator with presets and cron"
```

---

### Task 4: AutomationDispatcher

**Files:**
- Create: `client/lib/services/automation/automation_dispatcher.dart`
- Create: `client/lib/services/automation/automation_dispatch_result.dart`
- Test: `client/test/services/automation/automation_dispatcher_test.dart`

**Interfaces:**
- Consumes:
  - `AutomationRepository`
  - `Future<SessionOpenStatus> Function(SessionOpenRequest)` — from ChatCubit
  - `Future<AppSession> Function(SessionCreateRequest)` — create session
  - `MemberMaterializer` / `TabTeamBusCoordinator` for inject + deliverUserCommand
  - `AutomationScheduleCalculator`
- Produces:
  - `Future<AutomationRun> dispatch(Automation automation, {AutomationRunTrigger trigger})`

**sendToLead algorithm:**

```dart
Future<AutomationRun> _dispatchSendToLead(Automation a) async {
  final run = _pendingRun(a);
  await _repo.appendRun(a.workspaceId, run.copyWith(status: AutomationRunStatus.dispatching));

  final session = await _resolveSession(a);
  if (session == null) {
    return _finish(run, AutomationRunStatus.skippedUnavailable, error: 'session_not_found');
  }

  await _ensureSessionConnected(session, memberId: a.targetMemberId);
  final bus = _busCoordinator.busForSession(session.sessionId);
  if (bus != null) {
    bus.deliverUserCommand(a.targetMemberId, a.message);
  } else {
    _busCoordinator.injectMemberStdin(session.sessionId, a.targetMemberId, a.message);
    _busCoordinator.submitMemberPending(session.sessionId, a.targetMemberId);
  }
  return _finish(run, AutomationRunStatus.completed);
}
```

**launchPrompt:** call `createSession` or reuse `a.sessionId`, then same inject path with `a.message`.

Cold-start: `requestOpenSession(SessionOpenRequest(...))` then poll `_busCoordinator` member ready up to 60s (reuse pattern from `TabTeamBusCoordinator.materializeMember`).

- [ ] **Step 1: Write failing dispatcher tests with mocks**

Mock `MemberMaterializer`, fake session list, verify `deliverUserCommand` called with message.

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement dispatcher**

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(automations): add dispatcher for sendToLead and launchPrompt"
```

---

### Task 5: AutomationScheduler + AutomationCubit

**Files:**
- Create: `client/lib/services/automation/automation_scheduler.dart`
- Create: `client/lib/cubits/automation_cubit.dart`
- Create: `client/lib/cubits/automation_state.dart`
- Test: `client/test/services/automation/automation_scheduler_test.dart`
- Test: `client/test/cubits/automation_cubit_test.dart`

**Interfaces:**
- `AutomationScheduler.start()` / `stop()` / `Future<void> runNow(String workspaceId, String automationId)`
- `AutomationCubit`: `load()`, `loadForWorkspace(id)`, `save(Automation)`, `delete(...)`, `toggleEnabled(...)`, `runNow(...)`

Scheduler on tick:
1. `repo.listAll()` enabled items where `nextRunAtMs <= now`
2. dispatch each
3. update `lastRunAtMs`, recompute `nextRunAtMs` via calculator
4. missed on start: same with grace check

Use injectable `Clock` (`int Function() nowMs`) for tests.

- [ ] **Step 1: Scheduler unit tests** — fake clock, verify due automation dispatched once

- [ ] **Step 2: Cubit tests** — save updates state list; toggle flips enabled + nextRunAt

- [ ] **Step 3: Implement scheduler + cubit**

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Wire cubit to repository + scheduler callbacks**

- [ ] **Step 6: Commit**

```bash
git commit -m "feat(automations): add scheduler and AutomationCubit"
```

---

### Task 6: UI — schedule picker + editor dialog

**Files:**
- Create: `client/lib/pages/automations/automation_schedule_picker.dart`
- Create: `client/lib/pages/automations/automation_editor_dialog.dart`
- Test: `client/test/pages/automations/automation_editor_dialog_test.dart`

**Interfaces:**
- `AutomationEditorDialog.show(context, {Automation? initial, bool compact = false, String? workspaceId, String? sessionId})`
- compact mode hides action/scope/cli/reuseSession fields
- Returns `Automation?` on save

Follow existing dialog patterns: `showAppTextPromptDialog`, `AppDropdownField`, theme from `AppTextStyles`.

- [ ] **Step 1: Widget test** — compact shows message + schedule only; full shows action dropdown

- [ ] **Step 2: Implement picker + editor**

- [ ] **Step 3: Run widget test — PASS**

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(automations): add editor dialog and schedule picker"
```

---

### Task 7: UI — AutomationsPanel + global page

**Files:**
- Create: `client/lib/pages/automations/automations_panel.dart`
- Create: `client/lib/pages/automations/automation_management_page.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_global_section.dart`
- Modify: `client/lib/pages/home_workspace/home_workspace_sidebar.dart`

**Interfaces:**
- `AutomationsPanel({String? filterWorkspaceId, String? filterSessionId, bool groupByWorkspace = false})`
- Add `HomeGlobalView.automations` with route segment `automations`
- `HomeGlobalSection` case → `AutomationManagementPage`
- `HomeSidebar`: new `_ShortcutRow` above favorites — icon `Icons.schedule_rounded`, label l10n `automationsTitle`

Panel features:
- List with enable switch, next run, overflow menu (edit/run/delete)
- FAB or header `[+]` opens `AutomationEditorDialog`
- Tap row → expand run history (last 10)

- [ ] **Step 1: Implement panel + global page**

- [ ] **Step 2: Wire HomeGlobalView + HomeSidebar**

- [ ] **Step 3: Manual smoke** — navigate `/home-v2?global=automations`

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(automations): add management panel and global home view"
```

---

### Task 8: Workspace sidebar + Session context menu

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart`
- Modify: `client/lib/widgets/sidebar_session_tile.dart`

**WorkspaceSidebar** — insert before `_SidebarActionTile` (new chat):

```dart
_AutomationsHeader(
  workspaceId: widget.workspace.workspaceId,
  onTap: () => _openAutomationsPanel(context),
),
const SizedBox(height: 12),
```

Show enabled count + nearest next run from `AutomationCubit` (select by workspaceId).

**SidebarSessionTile** — extend context menu `itemCount: 4` (or 5 with manage):

```dart
SidebarActionMenuPopupItem(
  value: 'schedule',
  icon: Icons.schedule_rounded,
  label: l10n.automationsSessionContextMenu,
),
```

On select → `AutomationEditorDialog.show(..., compact: true, sessionId: session.sessionId, workspaceId: session.workspaceId)`.

Optional: if session has automations, add `manage_schedule` item.

- [ ] **Step 1: Implement workspace header widget**

- [ ] **Step 2: Extend session context menu**

- [ ] **Step 3: Widget test for context menu item presence**

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(automations): wire workspace sidebar and session context menu"
```

---

### Task 9: app_shell DI + session delete hook

**Files:**
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/cubits/chat_cubit.dart` (deleteSession hook)

In `app_shell.dart` after `ChatCubit` creation:

```dart
final automationRepo = AutomationRepository(
  fs: AppStorage.fs,
  layout: WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath),
);
final scheduleCalculator = AutomationScheduleCalculator();
final automationDispatcher = AutomationDispatcher(
  repository: automationRepo,
  scheduleCalculator: scheduleCalculator,
  requestOpenSession: chatCubit.requestOpenSession,
  requestCreateAndOpenSession: chatCubit.requestCreateAndOpenSession,
  busCoordinator: chatCubit.busCoordinator, // expose getter if needed
  sessionRepository: sessionRepository,
);
final automationScheduler = AutomationScheduler(
  repository: automationRepo,
  dispatcher: automationDispatcher,
  scheduleCalculator: scheduleCalculator,
);
final automationCubit = AutomationCubit(
  repository: automationRepo,
  scheduler: automationScheduler,
);
// start scheduler after bootstrap completes
automationScheduler.start();
```

Provide via `MultiBlocProvider` / `RepositoryProvider`.

In `ChatCubit.deleteSession`, after delete:

```dart
await _automationRepository.disableForSession(workspaceId, sessionId);
```

Inject repository into ChatCubit constructor (required param — no backward compat shim).

- [ ] **Step 1: Expose `TabTeamBusCoordinator busCoordinator` on ChatCubit if not public**

- [ ] **Step 2: Wire app_shell providers + scheduler lifecycle**

- [ ] **Step 3: Hook session delete**

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(automations): bootstrap scheduler in app shell"
```

---

### Task 10: l10n, docs, full verify

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Modify: `docs/DEVELOPMENT.md` (brief automations section)
- Modify: `AGENTS.md` (optional one-line pointer under Where to change)

- [ ] **Step 1: Add all l10n keys from spec §9**

- [ ] **Step 2: Run `cd client && flutter pub get` (regenerates localizations)**

- [ ] **Step 3: Run `cd client && dart run tool/gen_warmup_glyphs.dart`**

- [ ] **Step 4: Full verify**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration
```

Expected: all pass

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(automations): add l10n and document automations feature"
```

---

## Self-Review (spec coverage)

| Spec § | Task |
|--------|------|
| Unified model | Task 1 |
| Storage layout | Task 1–2 |
| Scheduler + missed run | Task 5 |
| sendToLead + cold start | Task 4 |
| launchPrompt | Task 4 |
| Session right-click | Task 8 |
| Workspace sidebar top | Task 8 |
| Home global view | Task 7 |
| Session delete disables automations | Task 9 |
| Tests + l10n | Tasks 1–5, 10 |

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-01-automations.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks
2. **Inline Execution** — implement task-by-task in this session with checkpoints

Which approach do you prefer?
