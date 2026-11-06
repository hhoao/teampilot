# 绑定会话的定时任务：预设与会话 CLI 对齐 + 切换/解绑会话 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让「启动提示词 + 复用会话」定时任务在绑定会话后只能选该会话 CLI 的预设，并提供切换 / 解绑会话入口。

**Architecture:** 后端（`AutomationDispatcher`）零改动——解绑即 `sessionId=null` + `reuseSession=true`，切换即把 `sessionId` 指向另一会话，两条路径派发时都已存在。改动集中在三个层次：一个纯函数 resolver（从 `ChatCubit.state.sessions` 解析绑定会话 / CLI / 可绑定候选）、`CliPresetDropdownField` 的 `cliFilter`、以及自动化编辑器（Dialog 持有本地 `_boundSessionId`，FormBody 渲染绑定行，LaunchSection 透传 `cliFilter`）。

**Tech Stack:** Flutter / Dart、`flutter_bloc` (Cubit)、`shared_ui` (`TpForm` / `TpSelect` / `TpDialog`)、`package:collection` (`firstOrNull`)、flutter gen-l10n。

## Global Constraints

- 仓库根：`/home/hhoa/git/hhoa/teampilot`；所有 `client/...` 路径相对该根。
- **Never invoke `flutter test` directly** — always `cd client && dart run tool/run_tests.dart <paths/options>`.
- 测试内循环：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`；用**单个测试文件**验证行为，可用 `--plain-name` 收窄。
- 声称完成前：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`（全量，后台跑）。
- **Member placement:** 一律 `sessionRosterMembers(session, team)`，不用 `team.members` / `replicas`（本计划不涉及成员放置）。
- **l10n:** 只手工编辑 `client/lib/l10n/app_en.arb` 与 `client/lib/l10n/app_zh.arb`；`app_localizations*.dart` 由 `flutter gen-l10n` 生成且已纳入版本控制，需一并提交。
- **Logging:** 用户可见错误走 l10n；诊断走 `AppLogger`；禁止 `print`。
- **Tests:** 通过构造函数注入 mock 文件系统 / repo；widget 测试用 `setUpTestAppStorage()` / `tearDownTestAppStorage()`（`client/test/support/post_frame_test_harness.dart`）。
- 不要提交 `client/google_fonts/`。
- 每个任务独立提交；工作区已有其他未提交改动，**只 `git add` 本任务涉及的文件**。

---

## File Structure

| 文件 | 职责 |
|---|---|
| `client/lib/services/automation/automation_session_binding_resolver.dart`（新） | 纯函数：从会话列表解析绑定会话、绑定会话的 CLI 过滤器、可绑定候选（过滤 + 排序） |
| `client/lib/widgets/cli/cli_preset_dropdown_field.dart`（改） | 新增可选 `cliFilter` / `emptyHint`，把预设列表按 CLI 过滤 |
| `client/lib/l10n/app_en.arb` / `app_zh.arb`（改） | 新增 10 条文案 |
| `client/lib/pages/automations/automation_session_picker.dart`（新） | 轻量会话选择弹层，返回 `sessionId?` |
| `client/lib/pages/automations/automation_editor_launch_section.dart`（改） | 透传 `cliFilter` 给下拉；预设字段加 `description` 提示 |
| `client/lib/pages/automations/automation_editor_form_body.dart`（改） | 「复用会话」下新增「绑定会话」行 |
| `client/lib/pages/automations/automation_editor_dialog.dart`（改） | 本地 `_boundSessionId` 状态、切换 / 解绑回调、保存时写入与一致性校验 |
| 对应 `client/test/...` 测试文件 | 每个任务的验收 |

依赖顺序：Task 1（resolver）→ Task 2（l10n + 下拉）→ Task 3（picker）→ Task 4（编辑器接线）→ Task 5（全量验证）。

---

### Task 1: 会话绑定解析纯函数

**Files:**
- Create: `client/lib/services/automation/automation_session_binding_resolver.dart`
- Test: `client/test/services/automation/automation_session_binding_resolver_test.dart`

**Interfaces:**
- Consumes: `AppSession`（`models/app_session.dart`）、`Automation.matchesSession`（`models/automation.dart`）、`CliTool`（`models/team_config.dart`）、`activeSessions`（`utils/session/session_archive_filter.dart`）、`sortAppSessions` / `AppSessionSort`（`utils/session/app_session_sort.dart`）。
- Produces:
  - `AppSession? findBoundSession(String? sessionId, List<AppSession> sessions)`
  - `CliTool? bindingCliFilter(AppSession? boundSession)`
  - `List<AppSession> bindableSessionsFor({required Automation automation, required List<AppSession> sessions})`

- [ ] **Step 1: Write the failing test**

Create `client/test/services/automation/automation_session_binding_resolver_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/automation/automation_session_binding_resolver.dart';

Automation _launch({bool isPersonal = true, String? teamId}) => Automation(
      id: 'a1',
      name: 'Daily',
      action: AutomationAction.launchPrompt,
      workspaceId: 'ws1',
      isPersonal: isPersonal,
      teamId: teamId,
      presetId: isPersonal ? 'preset-1' : null,
      message: 'ping',
      preset: AutomationSchedulePreset.daily,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 1,
      createdAtMs: 1,
      updatedAtMs: 1,
    );

AppSession _session({
  required String id,
  String workspaceId = 'ws1',
  CliTool? cli = CliTool.claude,
  String sessionTeam = '',
  bool archived = false,
  SessionPurpose purpose = SessionPurpose.normal,
  int updatedAt = 0,
}) =>
    AppSession(
      sessionId: id,
      workspaceId: workspaceId,
      display: 'Session $id',
      cli: cli,
      sessionTeam: sessionTeam,
      archived: archived,
      purpose: purpose,
      createdAt: 1,
      updatedAt: updatedAt,
    );

void main() {
  test('findBoundSession resolves by id and ignores null/empty/unknown', () {
    final sessions = [_session(id: 's1'), _session(id: 's2')];
    expect(findBoundSession('s2', sessions)?.sessionId, 's2');
    expect(findBoundSession(null, sessions), isNull);
    expect(findBoundSession('  ', sessions), isNull);
    expect(findBoundSession('missing', sessions), isNull);
  });

  test('bindingCliFilter returns simple session cli with claude fallback', () {
    expect(
      bindingCliFilter(_session(id: 's1', cli: CliTool.codex)),
      CliTool.codex,
    );
    expect(bindingCliFilter(_session(id: 's1', cli: null)), CliTool.claude);
  });

  test('bindingCliFilter returns null for team sessions and null input', () {
    expect(bindingCliFilter(null), isNull);
    expect(
      bindingCliFilter(_session(id: 's1', sessionTeam: 'team-1')),
      isNull,
    );
  });

  test('bindableSessionsFor keeps only compatible active normal sessions', () {
    final sessions = [
      _session(id: 'simple', updatedAt: 5),
      _session(id: 'other-workspace', workspaceId: 'ws2'),
      _session(id: 'archived', archived: true),
      _session(id: 'builder', purpose: SessionPurpose.teamGeneration),
      _session(id: 'team', sessionTeam: 'team-1'),
    ];
    final result = bindableSessionsFor(
      automation: _launch(),
      sessions: sessions,
    );
    expect(result.map((s) => s.sessionId).toList(), ['simple']);
  });

  test('bindableSessionsFor for team keeps matching team only', () {
    final sessions = [
      _session(id: 'simple'),
      _session(id: 'team-1-session', sessionTeam: 'team-1'),
      _session(id: 'team-2-session', sessionTeam: 'team-2'),
    ];
    final result = bindableSessionsFor(
      automation: _launch(isPersonal: false, teamId: 'team-1'),
      sessions: sessions,
    );
    expect(result.map((s) => s.sessionId).toList(), ['team-1-session']);
  });

  test('bindableSessionsFor sorts by recentlyUpdated', () {
    final sessions = [
      _session(id: 'old', updatedAt: 1),
      _session(id: 'new', updatedAt: 9),
      _session(id: 'mid', updatedAt: 5),
    ];
    final result = bindableSessionsFor(
      automation: _launch(),
      sessions: sessions,
    );
    expect(result.map((s) => s.sessionId).toList(), ['new', 'mid', 'old']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_session_binding_resolver_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:teampilot/services/automation/automation_session_binding_resolver.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `client/lib/services/automation/automation_session_binding_resolver.dart`:

```dart
import '../../models/app_session.dart';
import '../../models/automation.dart';
import '../../models/team_config.dart';
import '../../utils/session/app_session_sort.dart';
import '../../utils/session/session_archive_filter.dart';

/// Resolves the current binding target. [sessions] is already scoped to the
/// automation's workspace by the caller.
AppSession? findBoundSession(String? sessionId, List<AppSession> sessions) {
  final trimmed = sessionId?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  for (final session in sessions) {
    if (session.sessionId == trimmed) return session;
  }
  return null;
}

/// CLI to scope the preset picker to when a session is bound.
///
/// Team launch prompts have no preset picker, and an unavailable bound session
/// cannot supply a CLI — both return null (no filtering).
CliTool? bindingCliFilter(AppSession? boundSession) {
  if (boundSession == null || !boundSession.isSimple) return null;
  return boundSession.cli ?? CliTool.claude;
}

/// Sessions the automation can be rebound to, in sidebar order.
List<AppSession> bindableSessionsFor({
  required Automation automation,
  required List<AppSession> sessions,
}) {
  final filtered = activeSessions(sessions)
      .where(
        (s) =>
            s.purpose == SessionPurpose.normal && automation.matchesSession(s),
      )
      .toList(growable: false);
  return sortAppSessions(filtered, sort: AppSessionSort.recentlyUpdated);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_session_binding_resolver_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Static check and commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: `No issues found!`

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/services/automation/automation_session_binding_resolver.dart \
        client/test/services/automation/automation_session_binding_resolver_test.dart
git commit -m "feat(automations): add session binding resolver"
```

---

### Task 2: l10n 文案 + 预设下拉 CLI 过滤

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Regenerate: `client/lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_zh.dart`
- Modify: `client/lib/widgets/cli/cli_preset_dropdown_field.dart`
- Test: `client/test/widgets/cli/cli_preset_dropdown_field_test.dart`

**Interfaces:**
- Consumes: `presetsForCli(List<CliPreset>, CliTool)`（`services/cli/preset_resolver.dart`）、`CliTool`（`models/team_config.dart`）。
- Produces: `CliPresetDropdownField({Key?, String? selectedPresetId, required ValueChanged<String?> onChanged, String? label, CliTool? cliFilter, String? emptyHint})`；新增 l10n getter：`automationsBoundSession`、`automationsBoundSessionPending`、`automationsBoundSessionUnavailable`、`automationsSwitchSession`、`automationsUnbindSession`、`automationsSessionPickerTitle`、`automationsSessionPickerEmpty`、`automationsPresetScopeHint`、`automationsPresetCliMismatch`、`automationsPresetEmptyForCli`。

- [ ] **Step 1: Add l10n keys**

In `client/lib/l10n/app_en.arb`, insert the block immediately **before** the line `"automationsTargetMember": "Target member",` (i.e. after the closing `},` of the `@automationsReuseSessionListHint` metadata block):

```json
  "automationsBoundSession": "Bound session",
  "automationsBoundSessionPending": "A session is bound after the first run",
  "automationsBoundSessionUnavailable": "Session unavailable — switch or unbind",
  "automationsSwitchSession": "Switch session",
  "automationsUnbindSession": "Unbind",
  "automationsSessionPickerTitle": "Select a session",
  "automationsSessionPickerEmpty": "No sessions available to bind",
  "automationsPresetScopeHint": "Bound to a session — only presets for that session's CLI are shown.",
  "automationsPresetCliMismatch": "The selected preset does not match the bound session's CLI.",
  "automationsPresetEmptyForCli": "No presets available for this CLI.",
```

In `client/lib/l10n/app_zh.arb`, insert the block immediately **before** the line `"automationsTargetMember": "目标成员",`:

```json
  "automationsBoundSession": "绑定会话",
  "automationsBoundSessionPending": "首次运行后自动绑定会话",
  "automationsBoundSessionUnavailable": "会话不可用，请切换或解绑",
  "automationsSwitchSession": "切换会话",
  "automationsUnbindSession": "解绑",
  "automationsSessionPickerTitle": "选择会话",
  "automationsSessionPickerEmpty": "没有可绑定的会话",
  "automationsPresetScopeHint": "已绑定会话，仅显示该会话 CLI 的预设。",
  "automationsPresetCliMismatch": "所选预设与绑定会话的 CLI 不一致。",
  "automationsPresetEmptyForCli": "该 CLI 暂无可用预设。",
```

Regenerate (generated files are tracked):

```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter gen-l10n
```

Expected: `app_localizations*.dart` updated with the 10 new getters, no errors.

- [ ] **Step 2: Write the failing widget test**

Create `client/test/widgets/cli/cli_preset_dropdown_field_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/widgets/cli/cli_preset_dropdown_field.dart';

import '../../support/in_memory_filesystem.dart';

void _noop(String? _) {}

CliPresetsCubit _cubit() {
  final cubit = CliPresetsCubit(
    repository: CliPresetsRepository(
      fs: InMemoryFilesystem(),
      presetsPath: '/cli-presets.json',
    ),
  );
  cubit.emit(
    CliPresetsState(
      status: CliPresetsLoadStatus.ready,
      presets: [
        CliPreset(
          id: 'p-claude',
          name: 'Claude preset',
          cli: CliTool.claude,
          provider: 'anthropic',
          model: 'sonnet',
          createdAt: 1,
          updatedAt: 1,
        ),
        CliPreset(
          id: 'p-codex',
          name: 'Codex preset',
          cli: CliTool.codex,
          provider: 'openai',
          model: 'o3',
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
    ),
  );
  return cubit;
}

Widget _host(CliPresetsCubit cubit, Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: BlocProvider<CliPresetsCubit>.value(
          value: cubit,
          child: CliToolRegistryScope(
            registry: CliToolRegistry.builtIn(),
            child: child,
          ),
        ),
      ),
    );

void main() {
  testWidgets('without filter all presets are offered', (tester) async {
    final cubit = _cubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      _host(
        cubit,
        const CliPresetDropdownField(
          selectedPresetId: 'p-claude',
          onChanged: _noop,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TpSelect<String>>(find.byType(TpSelect<String>)).items,
      ['p-claude', 'p-codex'],
    );
  });

  testWidgets('cliFilter restricts items to that CLI', (tester) async {
    final cubit = _cubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      _host(
        cubit,
        const CliPresetDropdownField(
          selectedPresetId: 'p-claude',
          cliFilter: CliTool.codex,
          onChanged: _noop,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TpSelect<String>>(find.byType(TpSelect<String>)).items,
      ['p-codex'],
    );
  });

  testWidgets('emptyHint is shown when filter matches nothing', (tester) async {
    final cubit = _cubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      _host(
        cubit,
        const CliPresetDropdownField(
          selectedPresetId: 'p-claude',
          cliFilter: CliTool.gemini,
          emptyHint: 'No presets available for this CLI.',
          onChanged: _noop,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No presets available for this CLI.'), findsOneWidget);
    expect(find.byType(TpSelect<String>), findsNothing);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/widgets/cli/cli_preset_dropdown_field_test.dart`
Expected: FAIL — `The named parameter 'cliFilter' isn't defined` / `The named parameter 'emptyHint' isn't defined`.

- [ ] **Step 4: Implement the filter**

In `client/lib/widgets/cli/cli_preset_dropdown_field.dart`:

(a) Add imports:

```dart
import '../../models/team_config.dart';
import '../../services/cli/preset_resolver.dart';
```

(b) Constructor — add the two optional params:

```dart
  const CliPresetDropdownField({
    required this.selectedPresetId,
    required this.onChanged,
    this.label,
    this.cliFilter,
    this.emptyHint,
    super.key,
  });

  final String? selectedPresetId;
  final ValueChanged<String?> onChanged;
  final String? label;

  /// When set, only presets for this CLI are offered (bound-session scoping).
  final CliTool? cliFilter;

  /// Shown instead of the generic empty hint when [cliFilter] matches nothing.
  final String? emptyHint;
```

(c) In `build`, replace `final presets = presetsState.presets;` with:

```dart
    final allPresets = presetsState.presets;
    final presets = cliFilter == null
        ? allPresets
        : presetsForCli(allPresets, cliFilter!);
```

(d) Replace the empty-state block:

```dart
    if (presets.isEmpty) {
      return Text(
        cliFilter != null && emptyHint != null
            ? emptyHint!
            : l10n.workspaceCliPresetsEmptyHint,
        style: TpTextStyles.of(context).sm,
      );
    }
```

Note: `_resolveInitialId(presets, selectedPresetId)` already receives the filtered list; the `itemLabel` closure uses `presetsState.presetById(presetId)` which resolves against all presets — correct, since filtered ids are a subset.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/widgets/cli/cli_preset_dropdown_field_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 6: Static check and commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: `No issues found!`

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
        client/lib/l10n/app_localizations.dart \
        client/lib/l10n/app_localizations_en.dart \
        client/lib/l10n/app_localizations_zh.dart \
        client/lib/widgets/cli/cli_preset_dropdown_field.dart \
        client/test/widgets/cli/cli_preset_dropdown_field_test.dart
git commit -m "feat(automations): scope preset picker by CLI and add binding l10n"
```

---

### Task 3: 会话选择弹层

**Files:**
- Create: `client/lib/pages/automations/automation_session_picker.dart`
- Test: `client/test/pages/automations/automation_session_picker_test.dart`

**Interfaces:**
- Consumes: `AppSession`、`sessionListDisplayTitle(AppSession, AppLocalizations)`（`utils/session/session_display_title.dart`）、`CliBrandIcon`（`widgets/cli/cli_brand_icon.dart`）、`showDialog` / `TpDialog` / `TpDialogPinnedLayout` / `TpDialogHeader` / `TpDialogActions`、Task 2 的 `automationsSessionPickerTitle` / `automationsSessionPickerEmpty`。
- Produces: `Future<String?> showAutomationSessionPicker(BuildContext context, {required List<AppSession> sessions, required String? selectedId})` 和 `class AutomationSessionPickerDialog`。

- [ ] **Step 1: Write the failing test**

Create `client/test/pages/automations/automation_session_picker_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/automations/automation_session_picker.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';

AppSession _session(String id) => AppSession(
      sessionId: id,
      workspaceId: 'ws1',
      display: 'Session $id',
      cli: CliTool.claude,
      createdAt: 1,
    );

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: CliToolRegistryScope(
          registry: CliToolRegistry.builtIn(),
          child: child,
        ),
      ),
    );

void main() {
  testWidgets('returns the tapped session id', (tester) async {
    late Future<String?> result;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () {
              result = showAutomationSessionPicker(
                context,
                sessions: [_session('s1'), _session('s2')],
                selectedId: 's1',
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Session s2'));
    await tester.pumpAndSettle();
    expect(await result, 's2');
  });

  testWidgets('empty state shows no selectable rows', (tester) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () {
              showAutomationSessionPicker(
                context,
                sessions: const <AppSession>[],
                selectedId: null,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AutomationSessionPickerDialog), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/pages/automations/automation_session_picker_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:teampilot/pages/automations/automation_session_picker.dart'`.

- [ ] **Step 3: Write minimal implementation**

Create `client/lib/pages/automations/automation_session_picker.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../utils/session/session_display_title.dart';
import '../../widgets/cli/cli_brand_icon.dart';

/// Returns the selected session id, or null when dismissed.
Future<String?> showAutomationSessionPicker(
  BuildContext context, {
  required List<AppSession> sessions,
  required String? selectedId,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => AutomationSessionPickerDialog(
      sessions: sessions,
      selectedId: selectedId,
    ),
  );
}

/// Lightweight picker for rebinding a launch-prompt automation.
class AutomationSessionPickerDialog extends StatelessWidget {
  const AutomationSessionPickerDialog({
    required this.sessions,
    required this.selectedId,
    super.key,
  });

  final List<AppSession> sessions;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TpDialog(
      maxWidth: 420,
      child: TpDialogPinnedLayout(
        header: TpDialogHeader(title: l10n.automationsSessionPickerTitle),
        body: sessions.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    l10n.automationsSessionPickerEmpty,
                    style: TpTextStyles.of(context).sm,
                  ),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final session in sessions)
                    ListTile(
                      key: ValueKey('automation-session-${session.sessionId}'),
                      leading: session.cli == null
                          ? null
                          : CliBrandIcon(cli: session.cli!, size: 22),
                      title: Text(sessionListDisplayTitle(session, l10n)),
                      selected: session.sessionId == selectedId,
                      onTap: () => Navigator.of(context).pop(session.sessionId),
                    ),
                ],
              ),
        footer: TpDialogActions(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/pages/automations/automation_session_picker_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Static check and commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: `No issues found!`

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/pages/automations/automation_session_picker.dart \
        client/test/pages/automations/automation_session_picker_test.dart
git commit -m "feat(automations): add session picker for rebinding"
```

---

### Task 4: 编辑器接线（LaunchSection + FormBody + Dialog）

**Files:**
- Modify: `client/lib/pages/automations/automation_editor_launch_section.dart`
- Modify: `client/lib/pages/automations/automation_editor_form_body.dart`
- Modify: `client/lib/pages/automations/automation_editor_dialog.dart`
- Test: `client/test/pages/automations/automation_editor_dialog_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `findBoundSession` / `bindingCliFilter` / `bindableSessionsFor`；Task 2 的 `cliFilter` / `emptyHint` / l10n；Task 3 的 `showAutomationSessionPicker`；`presetsForCli`（`services/cli/preset_resolver.dart`）；`ChatCubit.state.sessions`；`CliPresetsCubit.state.presets`；`TpFormState.setFieldError(String, String?)`；`sampleAutomation` / `_host` / `testAutomationSetup` 等现有测试辅助。
- Produces: 编辑器行为（绑定行、下拉过滤、切换 / 解绑、保存一致性校验）。`AutomationEditorFormBody` 新增可选参数 `boundSessionId` / `boundSession` / `boundCli` / `onSwitchSession` / `onUnbindSession`；`AutomationEditorLaunchSection` 新增 `cliFilter`。

**设计细节（实现时按此，不改变已批准 spec 的行为）：**
- 绑定行在 `reuseSession == true` 且 `kind == launchPrompt` 时显示；`_boundSessionId` 为空（pending）时只显示「首次运行后自动绑定」，不显示按钮；已绑定时显示「切换会话」+「解绑」。
- 绑定会话不在 `state.sessions` 时显示「不可用」，仍显示两个按钮，不拦截保存。
- team 模式无预设字段，绑定行不显示 CLI 徽标，但仍可切换 / 解绑。

- [ ] **Step 1: Write the failing tests (test-first batch)**

Append to `client/test/pages/automations/automation_editor_dialog_test.dart`.

(1) Add exactly two imports at the top — the file already imports `models/team_config.dart` (line 16), `models/cli_preset.dart`, `models/workspace.dart`, `cubits/cli_presets_cubit.dart`, `cubits/chat_cubit.dart`, `repositories/cli_presets_repository.dart`, `shared_ui`, the three `test/support/*` helpers, `flutter/material.dart` and `flutter_test`:

```dart
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/widgets/cli/cli_preset_dropdown_field.dart';
```

(2) Add helpers after `_chatCubitWithWorkspace()`:

```dart
ChatCubit _chatCubitWithSessions(List<AppSession> sessions) {
  final cubit = testChatCubit(executableResolver: () => 'claude');
  cubit.applyState(
    ChatState(
      workspaces: [
        Workspace(
          workspaceId: 'ws1',
          folders: [WorkspaceFolder(path: '/repo')],
          createdAt: 1,
        ),
      ],
      sessions: sessions,
    ),
  );
  return cubit;
}

AppSession _simpleSession(
  String id, {
  required CliTool cli,
  String display = 'Session',
}) =>
    AppSession(
      sessionId: id,
      workspaceId: 'ws1',
      display: display,
      cli: cli,
      createdAt: 1,
    );

CliPresetsCubit _cliPresetsCubitWithTwoClis() {
  final cubit = CliPresetsCubit(
    repository: CliPresetsRepository(
      fs: InMemoryFilesystem(),
      presetsPath: '/cli-presets.json',
    ),
  );
  cubit.emit(
    CliPresetsState(
      status: CliPresetsLoadStatus.ready,
      presets: [
        CliPreset(
          id: 'p-claude',
          name: 'Claude preset',
          cli: CliTool.claude,
          provider: 'anthropic',
          model: 'sonnet',
          createdAt: 1,
          updatedAt: 1,
        ),
        CliPreset(
          id: 'p-codex',
          name: 'Codex preset',
          cli: CliTool.codex,
          provider: 'openai',
          model: 'o3',
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
    ),
  );
  return cubit;
}

Automation _boundAutomation({
  required String presetId,
  required String sessionId,
  bool isPersonal = true,
  String? teamId,
}) =>
    sampleAutomation(
      id: 'edit-bound',
      workspaceId: 'ws1',
      isPersonal: isPersonal,
      presetId: presetId,
      teamId: teamId,
    ).copyWith(reuseSession: true, sessionId: sessionId);
```

(3) Insert these 5 tests just before the final `}` of `main()`:

```dart
  testWidgets('bound session scopes preset dropdown to its CLI', (tester) async {
    final setup = testAutomationSetup();
    final chatCubit = _chatCubitWithSessions([
      _simpleSession('sess-codex', cli: CliTool.codex, display: 'Codex session'),
    ]);
    final cliPresetsCubit = _cliPresetsCubitWithTwoClis();
    addTearDown(setup.cubit.close);
    addTearDown(chatCubit.close);
    addTearDown(cliPresetsCubit.close);

    await tester.pumpWidget(
      RepositoryProvider<HomeStorage>.value(
        value: testHomeStorage,
        child: _host(
          cubit: setup.cubit,
          chatCubit: chatCubit,
          cliPresetsCubit: cliPresetsCubit,
          child: AutomationEditorDialog(
            workspaceId: 'ws1',
            initial: _boundAutomation(
              presetId: 'p-codex',
              sessionId: 'sess-codex',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AutomationEditorDialog)),
    );
    final presetSelect = find.descendant(
      of: find.byType(CliPresetDropdownField),
      matching: find.byType(TpSelect<String>),
    );
    expect(
      tester.widget<TpSelect<String>>(presetSelect).items,
      ['p-codex'],
    );
    expect(find.text(l10n.automationsPresetScopeHint), findsOneWidget);
    expect(find.text(l10n.automationsBoundSession), findsOneWidget);
    expect(find.text('Codex session'), findsOneWidget);
  });

  testWidgets('unbind keeps reuseSession and clears sessionId on save', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    final chatCubit = _chatCubitWithSessions([
      _simpleSession('sess-codex', cli: CliTool.codex, display: 'Codex session'),
    ]);
    final cliPresetsCubit = _cliPresetsCubitWithTwoClis();
    addTearDown(setup.cubit.close);
    addTearDown(chatCubit.close);
    addTearDown(cliPresetsCubit.close);

    await tester.pumpWidget(
      RepositoryProvider<HomeStorage>.value(
        value: testHomeStorage,
        child: _host(
          cubit: setup.cubit,
          chatCubit: chatCubit,
          cliPresetsCubit: cliPresetsCubit,
          child: AutomationEditorDialog(
            workspaceId: 'ws1',
            initial: _boundAutomation(
              presetId: 'p-codex',
              sessionId: 'sess-codex',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AutomationEditorDialog)),
    );

    await tester.tap(find.byKey(const Key('automationUnbindSession')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.save));
    await tester.pumpAndSettle();

    expect(setup.cubit.state.automations, hasLength(1));
    final saved = setup.cubit.state.automations.single;
    expect(saved.sessionId, isNull);
    expect(saved.reuseSession, isTrue);
  });

  testWidgets('switching session re-aligns presetId to the new CLI', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    final chatCubit = _chatCubitWithSessions([
      _simpleSession('sess-codex', cli: CliTool.codex, display: 'Codex session'),
      _simpleSession('sess-claude', cli: CliTool.claude, display: 'Claude session'),
    ]);
    final cliPresetsCubit = _cliPresetsCubitWithTwoClis();
    addTearDown(setup.cubit.close);
    addTearDown(chatCubit.close);
    addTearDown(cliPresetsCubit.close);

    await tester.pumpWidget(
      RepositoryProvider<HomeStorage>.value(
        value: testHomeStorage,
        child: _host(
          cubit: setup.cubit,
          chatCubit: chatCubit,
          cliPresetsCubit: cliPresetsCubit,
          child: AutomationEditorDialog(
            workspaceId: 'ws1',
            initial: _boundAutomation(
              presetId: 'p-codex',
              sessionId: 'sess-codex',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AutomationEditorDialog)),
    );

    await tester.tap(find.byKey(const Key('automationSwitchSession')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude session').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.save));
    await tester.pumpAndSettle();

    expect(setup.cubit.state.automations, hasLength(1));
    final saved = setup.cubit.state.automations.single;
    expect(saved.sessionId, 'sess-claude');
    expect(saved.presetId, 'p-claude');
    expect(saved.reuseSession, isTrue);
  });

  testWidgets('preset CLI mismatch blocks save', (tester) async {
    final setup = testAutomationSetup();
    final chatCubit = _chatCubitWithSessions([
      _simpleSession('sess-codex', cli: CliTool.codex, display: 'Codex session'),
    ]);
    final cliPresetsCubit = _cliPresetsCubitWithTwoClis();
    addTearDown(setup.cubit.close);
    addTearDown(chatCubit.close);
    addTearDown(cliPresetsCubit.close);

    await tester.pumpWidget(
      RepositoryProvider<HomeStorage>.value(
        value: testHomeStorage,
        child: _host(
          cubit: setup.cubit,
          chatCubit: chatCubit,
          cliPresetsCubit: cliPresetsCubit,
          child: AutomationEditorDialog(
            workspaceId: 'ws1',
            initial: _boundAutomation(
              presetId: 'p-claude',
              sessionId: 'sess-codex',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AutomationEditorDialog)),
    );

    await tester.tap(find.text(l10n.save));
    await tester.pumpAndSettle();
    expect(setup.cubit.state.automations, isEmpty);
  });

  testWidgets('team mode offers switch/unbind without a preset field', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    final chatCubit = _chatCubitWithSessions([
      AppSession(
        sessionId: 'sess-team',
        workspaceId: 'ws1',
        display: 'Team session',
        sessionTeam: 'team-1',
        createdAt: 1,
      ),
    ]);
    final launchProfileCubit = _teamLaunchProfileCubit();
    addTearDown(setup.cubit.close);
    addTearDown(chatCubit.close);
    addTearDown(launchProfileCubit.close);

    await tester.pumpWidget(
      RepositoryProvider<HomeStorage>.value(
        value: testHomeStorage,
        child: _host(
          cubit: setup.cubit,
          chatCubit: chatCubit,
          launchProfileCubit: launchProfileCubit,
          child: AutomationEditorDialog(
            workspaceId: 'ws1',
            initial: _boundAutomation(
              presetId: '',
              sessionId: 'sess-team',
              isPersonal: false,
              teamId: 'team-1',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(AutomationEditorDialog)),
    );

    expect(find.byKey(const Key('automationUnbindSession')), findsOneWidget);
    expect(find.text(l10n.presetPickerTitle), findsNothing);
    await tester.tap(find.byKey(const Key('automationUnbindSession')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.save));
    await tester.pumpAndSettle();

    expect(setup.cubit.state.automations, hasLength(1));
    expect(setup.cubit.state.automations.single.sessionId, isNull);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/automations/automation_editor_dialog_test.dart`
Expected: FAIL on the 5 new tests — the binding row does not exist yet (`find.byKey(const Key('automationUnbindSession'))` finds nothing) and the preset dropdown is unfiltered (`Expected: ['p-codex']; Actual: ['p-claude', 'p-codex']`). The l10n getters must exist (Task 2 Step 1); if they are missing, re-run `cd client && flutter gen-l10n` first.

- [ ] **Step 3: Implement `AutomationEditorLaunchSection`**

In `client/lib/pages/automations/automation_editor_launch_section.dart`:

(a) No new imports: `../../models/team_config.dart` (for `CliTool`) and `../../l10n/l10n_extensions.dart` are already imported (lines 8 and 7); `shared_ui` is already imported for `TpFormField` / `TpTextStyles`.

(b) Constructor — add param after `required this.presetId,`:

```dart
    this.cliFilter,
```
and its field:

```dart
  /// Bound-session CLI filter for the preset picker.
  final CliTool? cliFilter;
```

(c) In the preset `TpFormField<String>` (starts at line 102), add a `description:` and pass `cliFilter` / `emptyHint` into `CliPresetDropdownField`:

```dart
          TpFormField<String>(
            key: ValueKey('preset-${presetId ?? ''}'),
            id: 'presetId',
            initialValue: presetId ?? '',
            label: Text(l10n.presetPickerTitle),
            description: cliFilter == null
                ? null
                : Text(l10n.automationsPresetScopeHint),
            layoutStyle: TpFormFieldLayoutStyle.inline,
            labelWidth: labelWidth,
            validator: (v) => (v == null || v.trim().isEmpty)
                ? l10n.workspaceCliPresetsEmptyHint
                : null,
            builder: (state) {
              return CliPresetDropdownField(
                selectedPresetId: state.value,
                cliFilter: cliFilter,
                emptyHint: cliFilter == null
                    ? null
                    : l10n.automationsPresetEmptyForCli,
                onChanged: (value) {
                  state.didChange(value ?? '');
                  onPresetChanged(value);
                },
              );
            },
          ),
```

(`l10n` and `context` are already in scope from `build`.)

- [ ] **Step 4: Implement `AutomationEditorFormBody`**

In `client/lib/pages/automations/automation_editor_form_body.dart`:

(a) Add imports (the file already imports `l10n/l10n_extensions.dart` at line 4 and `package:shared_ui/shared_ui.dart`; do not duplicate them):

```dart
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../utils/session/session_display_title.dart';
import '../../widgets/cli/cli_brand_icon.dart';
```

(b) Constructor — add the five optional params and fields:

```dart
    this.boundSessionId,
    this.boundSession,
    this.boundCli,
    this.onSwitchSession,
    this.onUnbindSession,
```

```dart
  /// Current binding (launchPrompt + reuseSession only).
  final String? boundSessionId;
  final AppSession? boundSession;
  final CliTool? boundCli;
  final VoidCallback? onSwitchSession;
  final VoidCallback? onUnbindSession;
```

(c) In `build`, pass `cliFilter` into `AutomationEditorLaunchSection`:

```dart
          AutomationEditorLaunchSection(
            workspace: workspace!,
            isPersonal: isPersonal,
            projectFolderPath: projectFolderPath,
            workingDirectoryPath: workingDirectoryPath,
            presetId: presetId,
            cliFilter: boundCli,
            teamId: teamId,
            expertKey: expertKey,
            targetMemberId: targetMemberId,
            labelWidth: kAutomationEditorFormLabelWidth,
            onProjectChanged: onProjectChanged ?? (_) {},
            onWorktreeChanged: onWorktreeChanged ?? (_) {},
            onIsPersonalChanged: onIsPersonalChanged ?? (_) {},
            onPresetChanged: onPresetChanged ?? (_) {},
            onTeamChanged: onTeamChanged ?? (_) {},
            onExpertChanged: onExpertChanged ?? (_) {},
            onTargetMemberChanged: onTargetMemberChanged ?? (_) {},
          ),
```

(d) Immediately after the `TpFormField<bool>` for `reuseSession` (the block ending at line 234), insert:

```dart
          if (reuseSession) ...[
            const SizedBox(height: 12),
            _AutomationBoundSessionRow(
              labelWidth: kAutomationEditorFormLabelWidth,
              sessionId: boundSessionId,
              session: boundSession,
              cli: boundCli,
              onSwitch: onSwitchSession ?? () {},
              onUnbind: onUnbindSession ?? () {},
            ),
          ],
```

(e) Append at the bottom of the file:

```dart
class _AutomationBoundSessionRow extends StatelessWidget {
  const _AutomationBoundSessionRow({
    required this.labelWidth,
    required this.sessionId,
    required this.session,
    required this.cli,
    required this.onSwitch,
    required this.onUnbind,
  });

  final double labelWidth;
  final String? sessionId;
  final AppSession? session;
  final CliTool? cli;
  final VoidCallback onSwitch;
  final VoidCallback onUnbind;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasBinding = sessionId?.trim().isNotEmpty ?? false;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: labelWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              l10n.automationsBoundSession,
              style: TpTextStyles.of(context).md,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!hasBinding)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l10n.automationsBoundSessionPending,
                    style: TpTextStyles.of(context).sm,
                  ),
                )
              else ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (session == null)
                      Flexible(
                        child: Text(
                          l10n.automationsBoundSessionUnavailable,
                          style: TpTextStyles.of(context).sm,
                        ),
                      )
                    else ...[
                      if (cli != null) ...[
                        CliBrandIcon(cli: cli!, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              sessionListDisplayTitle(session!, l10n),
                              overflow: TextOverflow.ellipsis,
                              style: TpTextStyles.of(context).md,
                            ),
                            if (cli != null)
                              Text(cli!.value, style: TpTextStyles.of(context).sm),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      key: const Key('automationSwitchSession'),
                      onPressed: onSwitch,
                      child: Text(l10n.automationsSwitchSession),
                    ),
                    OutlinedButton(
                      key: const Key('automationUnbindSession'),
                      onPressed: onUnbind,
                      child: Text(l10n.automationsUnbindSession),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Implement `AutomationEditorDialog`**

In `client/lib/pages/automations/automation_editor_dialog.dart`:

(a) Add imports (the file already imports `package:collection/collection.dart`, `models/automation.dart`, `models/team_config.dart`, `models/workspace.dart`, `cubits/chat_cubit.dart`, `cubits/cli_presets_cubit.dart`, `l10n/l10n_extensions.dart`, `services/automation/automation_launch_session_binding.dart`, and `package:shared_ui/shared_ui.dart`; do not duplicate them):

```dart
import '../../models/app_session.dart';
import '../../services/automation/automation_session_binding_resolver.dart';
import '../../services/cli/preset_resolver.dart';
import 'automation_session_picker.dart';
```

(b) Add state field next to `late bool _reuseSession;`:

```dart
  late String? _boundSessionId;
```

and initialize in `initState` after `_reuseSession = initial?.reuseSession ?? false;`:

```dart
    _boundSessionId = initial?.sessionId;
```

(c) Add getters (place near `_selectedTeam`):

```dart
  List<AppSession> get _workspaceSessions {
    final workspaceId = widget.initial?.workspaceId ?? widget.workspaceId ?? '';
    return context
        .read<ChatCubit>()
        .state
        .sessions
        .where((s) => s.workspaceId == workspaceId)
        .toList(growable: false);
  }

  AppSession? get _boundSession => _isScheduledMessage
      ? null
      : findBoundSession(_boundSessionId, _workspaceSessions);

  CliTool? get _boundCli =>
      _isScheduledMessage ? null : bindingCliFilter(_boundSession);

  Automation? get _sessionMatchAutomation {
    final initial = widget.initial;
    if (initial == null) return null;
    return initial.copyWith(
      isPersonal: _isPersonal,
      teamId: _teamId,
      clearTeamId: _teamId == null,
    );
  }

  List<AppSession> get _bindableSessions {
    if (_isScheduledMessage) return const <AppSession>[];
    final match = _sessionMatchAutomation;
    if (match == null) return const <AppSession>[];
    return bindableSessionsFor(automation: match, sessions: _workspaceSessions);
  }
```

(d) Add callbacks (place before `_save`):

```dart
  Future<void> _onSwitchSession() async {
    final picked = await showAutomationSessionPicker(
      context,
      sessions: _bindableSessions,
      selectedId: _boundSessionId,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _boundSessionId = picked;
      _alignPresetWithSession(picked);
    });
  }

  /// When rebinding to a different CLI, pick that CLI's first preset so the
  /// stored presetId stays valid for the next fresh session.
  void _alignPresetWithSession(String sessionId) {
    if (!_isPersonal) return;
    final target = findBoundSession(
      sessionId,
      context.read<ChatCubit>().state.sessions,
    );
    final targetCli = bindingCliFilter(target);
    if (targetCli == null) return;
    final presets = context.read<CliPresetsCubit>().state.presets;
    final current = presets.where((p) => p.id == _presetId).firstOrNull;
    if (current != null && current.cli == targetCli) return;
    final replacement = presetsForCli(presets, targetCli).firstOrNull;
    if (replacement != null) _presetId = replacement.id;
  }

  void _onUnbindSession() => setState(() => _boundSessionId = null);
```

(e) In `_save`, replace the `launchSessionId` line:

```dart
    final launchSessionId = _isScheduledMessage
        ? (widget.initial?.sessionId ?? widget.sessionId)
        : (_reuseSession ? _boundSessionId : null);
```

(f) In `_save`, after `if (schedule.abort) return;` add the consistency check:

```dart
    if (!_isScheduledMessage &&
        _reuseSession &&
        _isPersonal &&
        _boundSessionId != null) {
      final boundCli = _boundCli;
      final selectedPresetId = _presetId?.trim() ?? '';
      final selected = context
          .read<CliPresetsCubit>()
          .state
          .presets
          .where((p) => p.id == selectedPresetId)
          .firstOrNull;
      if (boundCli != null && selected != null && selected.cli != boundCli) {
        form.setFieldError('presetId', l10n.automationsPresetCliMismatch);
        return;
      }
    }
```
(`l10n` is defined above at `final l10n = context.l10n;`. `_isPersonal` guard guarantees the `presetId` form field is registered, so `setFieldError` cannot throw.)

(g) Update `_reuseSessionBoundSubtitle` to read local state:

```dart
  String _reuseSessionBoundSubtitle(AppLocalizations l10n) {
    if (!_reuseSession) return l10n.automationsReuseSessionSubtitleOff;
    final bound = _boundSessionId?.trim() ?? '';
    if (bound.isEmpty) return l10n.automationsReuseSessionSubtitlePending;
    return l10n.automationsReuseSessionSubtitleBound(bound);
  }
```

(h) In `build`, change the `onReuseSessionChanged` callback and add the new params to `AutomationEditorFormBody`:

```dart
            reuseSession: _reuseSession,
            onReuseSessionChanged: (v) => setState(() {
              _reuseSession = v;
              if (!v) _boundSessionId = null;
            }),
            reuseSessionSubtitle: _reuseSessionBoundSubtitle(l10n),
            boundSessionId: _isScheduledMessage ? null : _boundSessionId,
            boundSession: _boundSession,
            boundCli: _boundCli,
            onSwitchSession: _onSwitchSession,
            onUnbindSession: _onUnbindSession,
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/automations/automation_editor_dialog_test.dart`
Expected: PASS (all existing tests + the 5 new ones).

If the "switch" test fails because the picker dialog's `ListTile` text is duplicated, use `find.text('Claude session').last` (already used). If `find.byKey` for buttons is offscreen, call `tester.ensureVisible(find.byKey(...))` before tapping.

- [ ] **Step 7: Static check and commit**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: `No issues found!`

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/lib/pages/automations/automation_editor_launch_section.dart \
        client/lib/pages/automations/automation_editor_form_body.dart \
        client/lib/pages/automations/automation_editor_dialog.dart \
        client/test/pages/automations/automation_editor_dialog_test.dart
git commit -m "feat(automations): scope bound presets and add switch/unbind session"
```

---

### Task 5: 全量验证

**Files:** none (verification only; fix any regression in place).

- [ ] **Step 1: Static analysis**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: `No issues found!`

- [ ] **Step 2: Full test suite (background)**

Run (in background, per the slow outer loop):

```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart
```

Expected: all tests pass, including the new files:
- `test/services/automation/automation_session_binding_resolver_test.dart`
- `test/widgets/cli/cli_preset_dropdown_field_test.dart`
- `test/pages/automations/automation_session_picker_test.dart`
- `test/pages/automations/automation_editor_dialog_test.dart`

- [ ] **Step 3: Confirm dispatcher untouched**

Run:

```bash
cd /home/hhoa/git/hhoa/teampilot && git diff --stat HEAD -- client/lib/services/automation/automation_dispatcher.dart client/lib/models/automation.dart client/lib/repositories/automation_repository.dart
```

Expected: empty output (no changes to those files).

- [ ] **Step 4: Fix regressions if any**

If Step 2 reports failures, diagnose with `dart run tool/run_tests.dart <failing-file> --plain-name "<test name>"`, fix in place, re-run Step 1 and Step 2, then commit:

```bash
cd /home/hhoa/git/hhoa/teampilot
git add <only the files you changed>
git commit -m "fix(automations): address full-suite regressions"
```

- [ ] **Step 5: Final status**

Run: `cd /home/hhoa/git/hhoa/teampilot && git status --short && git log --oneline -8`
Expected: the 4 feature commits present (other sessions may interleave their own commits — that is fine); no stray files staged. Report the exact analyze/test output when claiming done.

---

## Spec Coverage Map

| Spec section | Task |
|---|---|
| 预设约束（方案 A，仅 personal） | Task 2 (`cliFilter`), Task 3/4 (LaunchSection `description` + 透传) |
| 切换 / 解绑会话（语义 1） | Task 3 (picker), Task 4 (FormBody 行 + Dialog 本地状态) |
| 保存：写 `_boundSessionId`、一致性校验、保留 `stripWhenReuseDisabled` | Task 4 Step 5(e)(f)（`stripWhenReuseDisabled` 调用保持原样，不改动） |
| 后端零改动 | Task 5 Step 3 验证 |
| 边界：会话不可用 / CLI 无预设 / 候选为空 / team 模式 | Task 1 单测、Task 2 空态、Task 3 空态、Task 4 team 测试 |
| l10n（10 条，arb only） | Task 2 Step 1 |
| 测试与 AGENTS.md 验证命令 | Task 1/2/3/4 各 Step、Task 5 |
| 非目标（不改模型 / dispatcher / scheduledMessage、不接 follow-sync、无兼容层） | 全计划未涉及 |
