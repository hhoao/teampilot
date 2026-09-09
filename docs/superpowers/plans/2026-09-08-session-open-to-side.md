# Session「在右侧分栏打开」(Open to the Side) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Session 列表项（`SidebarSessionTile`）的右键与 `⋯` 溢出菜单新增「在右侧分栏打开」：VSCode "Open to the Side" 语义，session tab 呈现在 center workbench 聚焦分组右侧的分组中。

**Architecture:** 三层递进——(1) split layout 纯函数 `adjacentLeaf`（中序相邻叶子查询）；(2) `WorkbenchCubit.revealTabBeside` 组合现有 reducer 原语（`moveTab` / `splitInto`）实现 reveal 语义；(3) action 层 `openWorkspaceSessionTabToSide`（复用 `openWorkspaceSessionTab`）+ tile 菜单接线。全部复用 PR #6（workbench split groups）已测试的 reducer，无新 reducer 语义。

**Tech Stack:** Flutter / flutter_bloc，项目既有测试工具链（`tool/run_tests.dart`、`test/support/` fakes）。

**Spec:** `docs/specs/2026-09-08-session-open-to-side-design.md`

## Global Constraints

- **绝不直接运行 `flutter test`** — 一律 `cd client && dart run tool/run_tests.dart <paths>`（并发直接运行会损坏共享构建缓存）。
- 单文件/单测名验证用 `dart run tool/run_tests.dart <file> --plain-name '<test name>'`。
- 完成前：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`（全量套件放后台跑）。
- l10n 只编辑 `client/lib/l10n/app_en.arb` 和 `app_zh.arb`；生成物 `app_localizations*.dart` 由 `flutter gen-l10n` 重新生成后一并提交。
- 不用 `print`；诊断走 `AppLogger`。
- 所有代码在 worktree `/home/hhoa/git/hhoa/teampilot/.claude/worktrees/pr-6-workbench-split-groups`（分支 `pr-6-workbench-split-groups`）上进行，**不要切分支**。
- 每个任务结束都独立提交（见各任务 Step）。

---

### Task 1: `adjacentLeaf` 纯函数（split layout 层）

**Files:**
- Modify: `client/lib/cubits/workbench/workbench_split_layout.dart`（顶层 helper 区，`singleGroupLayout` / `validateLayout` 旁边）
- Test: `client/test/cubits/workbench/workbench_split_layout_test.dart`（新增 `group('adjacentLeaf', ...)`）

**Interfaces:**
- Consumes: `WorkbenchGroupLayout.leafGroupIds`（既有，中序叶子 id 列表）、`SplitLayoutReducer.split/splitInto`（既有，用于测试构造布局）。
- Produces: `String? adjacentLeaf(WorkbenchGroupLayout layout, String groupId, {required Axis axis, required bool before})` — Task 2 依赖此签名。

- [ ] **Step 1: 写失败测试**

在 `test/cubits/workbench/workbench_split_layout_test.dart` 的 `main()` 内（`singleGroupLayout` group 之后）加入：

```dart
group('adjacentLeaf', () {
  test('single leaf has no neighbor on either side', () {
    final l = _seed(_s1);
    expect(
      adjacentLeaf(l, 'g0', axis: Axis.horizontal, before: false),
      isNull,
    );
    expect(
      adjacentLeaf(l, 'g0', axis: Axis.horizontal, before: true),
      isNull,
    );
  });

  test('returns the in-order neighbor in a horizontal split', () {
    // g0 [s1, s2] → split s2 right → g0 [s1] | g1 [s2]
    final l = const SplitLayoutReducer().split(
      _seed(_s1, _s2),
      tab: _s2,
      axis: Axis.horizontal,
      before: false,
    )!;
    expect(
      adjacentLeaf(l, 'g0', axis: Axis.horizontal, before: false),
      'g1',
    );
    expect(adjacentLeaf(l, 'g1', axis: Axis.horizontal, before: false), isNull);
    expect(adjacentLeaf(l, 'g1', axis: Axis.horizontal, before: true), 'g0');
    expect(adjacentLeaf(l, 'g0', axis: Axis.horizontal, before: true), isNull);
  });

  test('mixed-axis tree walks in-order leaves', () {
    // g0 [s1] | (g1 [s2] over g2 [s3])
    var l = const SplitLayoutReducer().split(
      _seed(_s1, _s2, _s3),
      tab: _s2,
      axis: Axis.horizontal,
      before: false,
    )!; // g0 [s1, s3] | g1 [s2]
    l = const SplitLayoutReducer().splitInto(
      l,
      tab: _s3,
      targetGroupId: 'g1',
      axis: Axis.vertical,
      before: false,
    )!; // g1 leaf → vertical [g1 [s2], g2 [s3]]
    expect(l.leafGroupIds, ['g0', 'g1', 'g2']);
    expect(adjacentLeaf(l, 'g0', axis: Axis.horizontal, before: false), 'g1');
    expect(adjacentLeaf(l, 'g1', axis: Axis.horizontal, before: false), 'g2');
    expect(adjacentLeaf(l, 'g2', axis: Axis.horizontal, before: false), isNull);
    expect(adjacentLeaf(l, 'g2', axis: Axis.horizontal, before: true), 'g1');
  });

  test('absent groupId returns null', () {
    final l = _seed(_s1);
    expect(
      adjacentLeaf(l, 'nope', axis: Axis.horizontal, before: false),
      isNull,
    );
  });
});
```

注意：`_seed` 目前只接受两个 tab（`_seed(a, [b])`）。第三个测试用 `_seed(_s1, _s2, _s3)` — 把 `_seed` 扩展为可变参数：

```dart
WorkbenchGroupLayout _seed(WorkbenchTabId a, [WorkbenchTabId? b, WorkbenchTabId? c]) {
  var layout = singleGroupLayout(a);
  for (final extra in [b, c]) {
    if (extra == null) continue;
    layout = _addToGroup(layout, 'g0', extra);
  }
  return layout;
}
```

（`_addToGroup` 已存在于该文件。）

- [ ] **Step 2: 运行测试确认失败**

```bash
cd client && dart run tool/run_tests.dart test/cubits/workbench/workbench_split_layout_test.dart --plain-name 'adjacentLeaf'
```

预期：编译失败，`adjacentLeaf` 未定义。

- [ ] **Step 3: 实现**

`client/lib/cubits/workbench/workbench_split_layout.dart` 顶层（`validateLayout` 旁）：

```dart
/// In-order neighbor leaf of [groupId]: the previous leaf when [before],
/// else the next one. Null when [groupId] is not a live leaf or has no
/// neighbor on that side. [axis] is accepted for future horizontal /
/// vertical differentiation; both axes currently use the in-order walk
/// (same order `workbenchFocusNextGroup` cycles in).
String? adjacentLeaf(
  WorkbenchGroupLayout layout,
  String groupId, {
  required Axis axis,
  required bool before,
}) {
  final leaves = layout.leafGroupIds;
  final index = leaves.indexOf(groupId);
  if (index < 0) return null;
  final target = before ? index - 1 : index + 1;
  return target >= 0 && target < leaves.length ? leaves[target] : null;
}
```

（文件已 `import 'package:flutter/widgets.dart' show Axis;` 风格引入 Axis —— 跟随该文件既有 import 写法。）

- [ ] **Step 4: 运行测试确认通过**

```bash
cd client && dart run tool/run_tests.dart test/cubits/workbench/workbench_split_layout_test.dart
```

预期：全部通过（既有测试 + 新增 4 个）。

- [ ] **Step 5: 提交**

```bash
git add lib/cubits/workbench/workbench_split_layout.dart test/cubits/workbench/workbench_split_layout_test.dart
git commit -m "feat(workbench): adjacentLeaf in-order neighbor lookup for split layouts"
```

---

### Task 2: `WorkbenchCubit.revealTabBeside`

**Files:**
- Modify: `client/lib/cubits/workbench/workbench_cubit.dart`（`---- split-group mutations ----` 区，`focusGroup` 之后）
- Test: `client/test/cubits/workbench/workbench_cubit_test.dart`（新增 `group('revealTabBeside', ...)`，放在既有 `group('split groups', ...)` 之后）

**Interfaces:**
- Consumes: Task 1 的 `adjacentLeaf`；既有 `moveTab`、`splitInto`、`focusGroup`、`centerLayout`、`_mutateLayout`、`_lr`（`SplitLayoutReducer` 常量）、静态 `_groupContainingTab`。
- Produces: `void revealTabBeside(String workspaceId, WorkbenchTabId tab, {required Axis axis, required bool before})` — Task 3 依赖此签名。

- [ ] **Step 1: 写失败测试**

`test/cubits/workbench/workbench_cubit_test.dart`（文件顶部已有 `_ws`、`_s1`、`_s2`、`_s3` 常量；新增局部 `_s9` 不必需，用内联 `WorkbenchTabId.session('s9')`）：

```dart
group('revealTabBeside', () {
  test('moves the tab into the adjacent right group and focuses it', () {
    cubit
      ..openSession(_ws, 's1')
      ..openSession(_ws, 's2')
      ..openSession(_ws, 's3')
      ..splitTab(_ws, _s3, axis: Axis.horizontal, before: false) // g1 [s3]
      ..focusGroup(_ws, 'g0');
    cubit.revealTabBeside(_ws, _s2, axis: Axis.horizontal, before: false);
    final layout = cubit.centerLayout(_ws);
    expect(layout.groups['g0']!.order, [_s1]);
    expect(layout.groups['g1']!.order, [_s3, _s2]);
    expect(layout.groups['g1']!.activeId, _s2);
    expect(layout.focusedGroupId, 'g1');
    expect(validateLayout(layout), isTrue);
  });

  test('tab already in the adjacent group just activates and focuses', () {
    cubit
      ..openSession(_ws, 's1')
      ..openSession(_ws, 's2')
      ..splitTab(_ws, _s2, axis: Axis.horizontal, before: false) // g1 [s2]
      ..activate(_ws, _s1) // focused g0, active s1
      ..revealTabBeside(_ws, _s2, axis: Axis.horizontal, before: false);
    final layout = cubit.centerLayout(_ws);
    expect(layout.groups['g0']!.order, [_s1]);
    expect(layout.groups['g1']!.order, [_s2]);
    expect(layout.focusedGroupId, 'g1');
    expect(layout.groups['g1']!.activeId, _s2);
  });

  test('sole tab of the rightmost group degrades to activate + focus', () {
    cubit
      ..openSession(_ws, 's1')
      ..openSession(_ws, 's2')
      ..splitTab(_ws, _s2, axis: Axis.horizontal, before: false); // g1 [s2], focused g1
    cubit.revealTabBeside(_ws, _s2, axis: Axis.horizontal, before: false);
    final layout = cubit.centerLayout(_ws);
    expect(layout.leafGroupIds, ['g0', 'g1']); // tree unchanged
    expect(layout.focusedGroupId, 'g1');
    expect(layout.groups['g1']!.activeId, _s2);
  });

  test('absent tab is a silent no-op', () {
    cubit.openSession(_ws, 's1');
    cubit.revealTabBeside(
      _ws,
      WorkbenchTabId.session('s9'),
      axis: Axis.horizontal,
      before: false,
    );
    expect(cubit.centerLayout(_ws).groups['g0']!.order, [_s1]);
  });
});
```

注意核对既有 API：`activate(String workspaceId, WorkbenchTabId id)` 存在（workbench_cubit.dart:410 一带使用 `_lr.activate`）；`validateLayout` 从 `workbench_split_layout.dart` 导入（该测试文件已 import）。

- [ ] **Step 2: 运行测试确认失败**

```bash
cd client && dart run tool/run_tests.dart test/cubits/workbench/workbench_cubit_test.dart --plain-name 'revealTabBeside'
```

预期：编译失败，`revealTabBeside` 未定义。

- [ ] **Step 3: 实现**

`client/lib/cubits/workbench/workbench_cubit.dart`，`focusGroup` 方法之后：

```dart
/// VSCode "Open to the Side": reveals [tab] in the group beside the focused
/// one along [axis] ([before] = left/up side). Reuses the adjacent group
/// when one exists (a source group emptied by the move is pruned);
/// otherwise splits a new sibling group off the focused group. When the
/// reducer declines both (absent tab, or the sole tab of its group with no
/// neighbor), falls back to activating and focusing the tab's own group.
/// Center layout only.
void revealTabBeside(
  String workspaceId,
  WorkbenchTabId tab, {
  required Axis axis,
  required bool before,
}) {
  final layout = centerLayout(workspaceId);
  final adjacent = adjacentLeaf(
    layout,
    layout.focusedGroupId,
    axis: axis,
    before: before,
  );
  if (adjacent != null) {
    moveTab(workspaceId, tab, adjacent);
    return;
  }
  _mutateLayout(
    workspaceId,
    floating: false,
    mutate: (current) =>
        _lr.splitInto(
          current,
          tab: tab,
          targetGroupId: current.focusedGroupId,
          axis: axis,
          before: before,
        ) ??
        _lr.moveTab(
          current,
          tab: tab,
          targetGroupId:
              _groupContainingTab(current, tab) ?? current.focusedGroupId,
        ),
  );
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd client && dart run tool/run_tests.dart test/cubits/workbench/workbench_cubit_test.dart
```

预期：全部通过。

- [ ] **Step 5: 提交**

```bash
git add lib/cubits/workbench/workbench_cubit.dart test/cubits/workbench/workbench_cubit_test.dart
git commit -m "feat(workbench): revealTabBeside open-to-the-side mutation"
```

---

### Task 3: l10n + `openWorkspaceSessionTabToSide` action

**Files:**
- Modify: `client/lib/l10n/app_en.arb`、`client/lib/l10n/app_zh.arb`（各一个 key）
- Regenerate: `client/lib/l10n/app_localizations*.dart`（`flutter gen-l10n` 产物）
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`（`openWorkspaceSessionTab` 函数之后、私有 `_handleSessionOpenStatus` 之前）
- Modify: `docs/specs/2026-09-08-session-open-to-side-design.md`（一处签名修订，见 Step 5）
- Test: `client/test/pages/home_workspace/workspace/workspace_session_actions_open_to_side_test.dart`（新建）

**Interfaces:**
- Consumes: Task 2 的 `revealTabBeside`；既有 `openWorkspaceSessionTab(context, workspace, session)`、`WorkbenchCubit.centerLayout`。
- Produces: `Future<void> openWorkspaceSessionTabToSide(BuildContext context, AppSession session)` — Task 4 依赖此签名。**注意：workspace 在函数内部从 `ChatCubit.state.workspaces` 解析（比 spec 原文在 tile 里解析更优——单一解析点，调用方只需 session）**，Step 5 同步修订 spec。

- [ ] **Step 1: 加 l10n key**

`client/lib/l10n/app_en.arb`（放在 `"renameConversation": "Rename conversation",` 附近）：

```json
"sessionOpenToSide": "Open to the Side",
```

`client/lib/l10n/app_zh.arb`（放在 `"renameConversation": "重命名对话",` 附近）：

```json
"sessionOpenToSide": "在右侧分栏打开",
```

- [ ] **Step 2: 重新生成 l10n**

```bash
cd client && flutter gen-l10n
```

预期：`lib/l10n/app_localizations.dart` 等三个生成文件出现 `sessionOpenToSide` getter。

- [ ] **Step 3: 写失败测试（新建文件）**

`client/test/pages/home_workspace/workspace/workspace_session_actions_open_to_side_test.dart`：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/chat/model/session_open_request.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_split_layout.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_session_actions.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/services/workbench/workbench_chat_bridge.dart';

void main() {
  testWidgets(
    'openWorkspaceSessionTabToSide splits the session into a new right group',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final sessionPreferencesCubit = SessionPreferencesCubit(
        repository: SessionPreferencesRepository(prefs),
      );
      addTearDown(sessionPreferencesCubit.close);

      final chatCubit = await tester.runAsync(() async {
        final tmp = await Directory.systemTemp.createTemp('open_to_side_');
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          WorkspaceFolder(path: tmp.path),
        ]);
        final sessionA = (await repo.createSession(workspace.workspaceId)).session;
        final sessionB = (await repo.createSession(workspace.workspaceId)).session;
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
        );
        final workbench = WorkbenchCubit();
        final bridge = WorkbenchChatBridge(workbench: workbench, chat: cubit);
        workbench.port = bridge;
        cubit.workbenchPort = bridge;
        await cubit.loadWorkspaceData(repo);
        // Session A opens first so the focused group already hosts a tab.
        await cubit.requestOpenSession(
          SessionOpenRequest(
            session: sessionA,
            workspace: workspace,
            repo: repo,
          ),
        );
        return (cubit, workbench, workspace, sessionB);
      });
      final (chatCubit, workbench, workspace, sessionB) = chatCubit!;
      addTearDown(workbench.close);
      addTearDown(chatCubit.close);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<SessionRepository>.value(
                value: chatCubit.sessionRepository,
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ChatCubit>.value(value: chatCubit),
                BlocProvider<WorkbenchCubit>.value(value: workbench),
                BlocProvider<SessionPreferencesCubit>.value(
                  value: sessionPreferencesCubit,
                ),
              ],
              child: Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: TextButton(
                      onPressed: () => openWorkspaceSessionTabToSide(
                        context,
                        sessionB,
                      ),
                      child: const Text('open-to-side'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-to-side'));
      await tester.pumpAndSettle();

      final layout = workbench.centerLayout(workspace.workspaceId);
      expect(layout.leafGroupIds, hasLength(2));
      expect(
        layout.groups[layout.leafGroupIds.first]!.order,
        [WorkbenchTabId.session(/* sessionA id */)],
      );
      expect(
        layout.groups[layout.leafGroupIds.last]!.order,
        [WorkbenchTabId.session(sessionB.sessionId)],
      );
      expect(layout.focusedGroupId, layout.leafGroupIds.last);
      expect(validateLayout(layout), isTrue);
    },
  );
}
```

实现说明（执行者注意）：
- `sessionA` 的 id 断言需要把 sessionA 从 runAsync 闭包一起带出（把返回元组扩为 5 元素），不要用占位注释——把 `WorkbenchTabId.session(sessionA.sessionId)` 写全。
- `testAutomationRepository()` 来自 `test/support/`（chat_cubit_test 同款；若它不在自动可见的 helper 文件里，加 `import '../../support/…'` 对应路径——参照 `test/cubits/chat_cubit_test.dart` 顶部 import）。
- `chatCubit.sessionRepository` 若无私有 getter，改为在 runAsync 里把 `repo` 一并带出，用 `RepositoryProvider<SessionRepository>.value(value: repo)`。
- 若 `requestOpenSession` 在该 fake 下需要 terminalSessionFactory，参照 chat_cubit_test 传入 `test/support/fake_terminal_session.dart` 的 `FakeTerminalSession`。

- [ ] **Step 4: 运行测试确认失败**

```bash
cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_session_actions_open_to_side_test.dart
```

预期：编译失败，`openWorkspaceSessionTabToSide` 未定义。

- [ ] **Step 5: 实现 action + 修订 spec**

`client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`，`openWorkspaceSessionTab` 之后：

```dart
/// [openWorkspaceSessionTab] + "Open to the Side": after the open (or
/// reuse-focus) settles, reveals the session's tab in the group to the
/// right of the focused one. Silently returns when the workspace is not
/// found, no workbench scope is in reach, or the open was blocked (status
/// toasts are already handled by [openWorkspaceSessionTab]).
Future<void> openWorkspaceSessionTabToSide(
  BuildContext context,
  AppSession session,
) async {
  final chat = context.read<ChatCubit>();
  final workspace = chat.state.workspaces.firstWhereOrNull(
    (item) => item.workspaceId == session.workspaceId,
  );
  if (workspace == null) return;
  await openWorkspaceSessionTab(context, workspace, session);
  if (!context.mounted) return;
  final WorkbenchCubit workbench;
  try {
    workbench = context.read<WorkbenchCubit>();
  } on ProviderNotFoundException {
    return;
  }
  final tab = WorkbenchTabId.session(session.sessionId);
  final layout = workbench.centerLayout(workspace.workspaceId);
  final hosted = layout.groups.values.any(
    (strip) => strip.order.contains(tab),
  );
  if (!hosted) return;
  workbench.revealTabBeside(
    workspace.workspaceId,
    tab,
    axis: Axis.horizontal,
    before: false,
  );
}
```

新增 import：`../../cubits/workbench/workbench_cubit.dart`、`../../cubits/workbench/workbench_tab.dart`、`package:flutter/widgets.dart` 的 `Axis`（若文件已 import material.dart 则已含）；`firstWhereOrNull`（collection）与 `ProviderNotFoundException`（flutter_bloc）按文件现有 import 情况补。

同步修订 `docs/specs/2026-09-08-session-open-to-side-design.md` 第 3 节签名为 `openWorkspaceSessionTabToSide(BuildContext context, AppSession session)`，并把「从 ChatCubit.state.workspaces 解析 workspace」移入函数体描述（删除 tile 侧解析的句子）。

- [ ] **Step 6: 运行测试确认通过**

```bash
cd client && dart run tool/run_tests.dart test/pages/home_workspace/workspace/workspace_session_actions_open_to_side_test.dart
```

预期：通过。

- [ ] **Step 7: 提交**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_zh.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_zh.dart
git add lib/pages/home_workspace/workspace/workspace_session_actions.dart test/pages/home_workspace/workspace/workspace_session_actions_open_to_side_test.dart ../docs/specs/2026-09-08-session-open-to-side-design.md
git commit -m "feat(workbench): openWorkspaceSessionTabToSide action + l10n"
```

---

### Task 4: tile 菜单接线（`sidebar_session_tile.dart`）

**Files:**
- Modify: `client/lib/widgets/sidebar_session_tile.dart`（三处：`_contextMenuItems`、`_handleContextAction`、build 里的 `⋯` 溢出菜单）
- Test: `client/test/widgets/sidebar_session_tile_test.dart`（新增 2 个 testWidgets）

**Interfaces:**
- Consumes: Task 3 的 `openWorkspaceSessionTabToSide(context, session)`；既有 `l10n.sessionOpenToSide`（Task 3 l10n）。
- Produces: 菜单项 value `'open_to_side'`（右键/长按菜单）与溢出菜单同名项，archive 模式均不显示。

- [ ] **Step 1: 写失败测试**

`test/widgets/sidebar_session_tile_test.dart`，放在 `'both session menus include the localized reference action'` 测试之后：

```dart
testWidgets('both session menus include the localized open-to-side action', (
  tester,
) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  final chatCubit = testChatCubit(executableResolver: () => 'claude');
  final (attention, automationCubit) = _tileCubits();
  addTearDown(chatCubit.close);
  addTearDown(automationCubit.close);
  addTearDown(attention.close);

  await tester.pumpWidget(
    _host(
      chatCubit: chatCubit,
      automationCubit: automationCubit,
      attentionCubit: attention,
      sessionRepository: SessionRepository(),
      locale: const Locale('zh'),
    ),
  );
  await tester.pump();

  await _openContextMenu(tester);

  final l10n = AppLocalizations.of(
    tester.element(find.byType(SidebarSessionTile)),
  );
  final contextItem = tester.widget<TpActionMenuPopupItem<String>>(
    find.byWidgetPredicate(
      (widget) =>
          widget is TpActionMenuPopupItem<String> &&
          widget.value == 'open_to_side',
    ),
  );
  expect(contextItem.label, l10n.sessionOpenToSide);
  expect(l10n.sessionOpenToSide, '在右侧分栏打开');

  await _dismissContextMenu(tester);

  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await tester.pump();
  await mouse.moveTo(tester.getCenter(find.byType(TpHoverRow)));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.more_horiz));
  await tester.pumpAndSettle();

  expect(find.text(l10n.sessionOpenToSide), findsOneWidget);
  debugDefaultTargetPlatformOverride = null;
});

testWidgets('archive mode omits the open-to-side action', (tester) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  final chatCubit = testChatCubit(executableResolver: () => 'claude');
  final (attention, automationCubit) = _tileCubits();
  addTearDown(chatCubit.close);
  addTearDown(automationCubit.close);
  addTearDown(attention.close);

  await tester.pumpWidget(
    _host(
      chatCubit: chatCubit,
      automationCubit: automationCubit,
      attentionCubit: attention,
      sessionRepository: SessionRepository(),
      child: SidebarSessionTile(
        session: _session,
        archiveMode: true,
        onTap: () {},
      ),
    ),
  );
  await tester.pump();

  await _openContextMenu(tester);
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is TpActionMenuPopupItem<String> &&
          widget.value == 'open_to_side',
    ),
    findsNothing,
  );
  debugDefaultTargetPlatformOverride = null;
});
```

（`_openContextMenu` 结束后菜单仍开着的话按 reference 测试的模式 `_dismissContextMenu`；archive 测试结束时菜单未关也无妨——测试结束自动清理。）

- [ ] **Step 2: 运行测试确认失败**

```bash
cd client && dart run tool/run_tests.dart test/widgets/sidebar_session_tile_test.dart --plain-name 'open-to-side'
```

预期：两个新测试失败（找不到 `open_to_side` 项）。

- [ ] **Step 3: 实现三处接线**

`client/lib/widgets/sidebar_session_tile.dart`：

**(a)** `_contextMenuItems`（约 166 行起）——items 列表开头、rename 之前插入：

```dart
final items = <TpActionMenuPopupItem<String>>[
  if (!widget.archiveMode)
    TpActionMenuPopupItem(
      value: 'open_to_side',
      icon: Icons.vertical_split_outlined,
      label: l10n.sessionOpenToSide,
    ),
  TpActionMenuPopupItem(
    value: 'rename',
    // …既有代码不动
```

**(b)** `_handleContextAction`（约 289 行起）switch 里加 case（放在 `case 'rename':` 之前）：

```dart
case 'open_to_side':
  await openWorkspaceSessionTabToSide(context, session);
```

**(c)** build 里的 `⋯` 溢出菜单 `buildMenuChildren`（约 675 行起）——列表开头、rename 之前插入：

```dart
if (!widget.archiveMode)
  TpActionMenuItem(
    icon: Icons.vertical_split_outlined,
    label: l10n.sessionOpenToSide,
    menuController: controller,
    onTap: () => unawaited(
      openWorkspaceSessionTabToSide(context, session),
    ),
  ),
```

`workspace_session_actions.dart` 已在该文件 import 列表中，无需新增 import。

- [ ] **Step 4: 运行测试确认通过**

```bash
cd client && dart run tool/run_tests.dart test/widgets/sidebar_session_tile_test.dart
```

预期：全部通过（含既有测试——回归确认 `_contextMenuItems` 改动没破坏 archive/分组等用例）。

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/sidebar_session_tile.dart test/widgets/sidebar_session_tile_test.dart
git commit -m "feat(sidebar): open-to-the-side menu item in session tile"
```

---

### Task 5: 全量验证

- [ ] **Step 1: 静态分析**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

预期：与 main 基线一致的既有 351 条问题，新增文件零问题。

- [ ] **Step 2: 全量测试（后台）**

```bash
cd client && dart run tool/run_tests.dart
```

预期：既有基线 8765 passed / 14 failed（14 个为 PR #6 之前就存在的失败集：workspace_shell_sidebar_toggle、opencode config_profile、run/launch_adapter_client）+ 本计划新增约 12 个测试全部通过。任何**新**失败都要修。

- [ ] **Step 3: 手动冒烟（应用已在跑则热重启）**

在运行的 app 里：Session 列表右键某未打开 session → 「在右侧分栏打开」→ 右侧新分组出现该会话；再右键一个已在左侧分组的 session → 它移动到聚焦分组右侧；右键已在最右分组的 session → 仅聚焦。重启 app → 布局恢复。

---

## Self-Review 记录

- **Spec 覆盖**：spec 第 1 节→Task 1；第 2 节→Task 2；第 3/4/5 节→Task 3；第 4 节菜单→Task 4；测试三件套→Tasks 1-4 各自 Step 1。降级路径（唯一 tab、landing 单分组、tab 缺席）均有对应用例。
- **占位符**：Task 3 测试里 sessionA id 的占位注释已显式要求执行者补全为真实元组带出，无 TBD。
- **类型一致性**：`adjacentLeaf` / `revealTabBeside` / `openWorkspaceSessionTabToSide` 三个签名在 Task 1/2/3 的 Produces 与后续 Consumes 完全一致；菜单 value `'open_to_side'` 三处统一。
- **已知风险**：Task 3 widget 测试的 `requestOpenSession` fake 依赖与 chat_cubit_test 相同的构造参数，执行时如遇缺参（terminalSessionFactory 等）按 Step 3 的实现说明补齐。
