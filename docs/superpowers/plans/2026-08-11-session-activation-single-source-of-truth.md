# Session 激活单一事实来源 + Mixed 团队面板修复 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消除 `ChatState.activeSessionId`/`selectedMemberId` 全局镜像,让 workbench bar 成为 per-workspace 会话激活的唯一事实来源,修复"点击 Session 切到别的 Session/只高亮不切换"与"Mixed Session 右侧缺团队面板"两个 bug。

**Architecture:** `WorkbenchCubit.bar(wsId).center` 是唯一身份来源(active/order/previews);`ChatTabStore` 按 sessionId 持有运行时(selectedMemberId/shells/teamBus)。删除全局镜像字段,所有 UI 通过 `scopedActiveSessionId`/`scopedSelectedMemberId` 从 bar 派生;`ChatCubit.activeTab` 等全局 getter 通过新增的 `ChatWorkbenchPort.centerActiveForScope` 实时派生。会话打开流程只在 bridge 喂一次 bar(消除二次喂竞态);`surfaceExistingTab` 也喂 bar。TeamBus 在复用 tab 且缺失时按需补装。

**Tech Stack:** Flutter/Dart, flutter_bloc, equatable。测试:`flutter_test`。

## Global Constraints

- 遵循 [docs/CODE_QUALITY.md](../../CODE_QUALITY.md):禁止注释除非必要;l10n 走 `app_en.arb`/`app_zh.arb`;日志用 `AppLogger`/`appLogger`,禁止 `print`。
- 每个任务结束时 `flutter analyze --no-fatal-infos --no-fatal-warnings` 必须通过(编译绿),相关测试通过后才提交。
- `ChatState` 不再包含会话身份字段;任何新代码不得读 `state.activeSessionId`/`state.selectedMemberId`。
- 每任务一次独立 commit,commit message 参照仓库风格(`fix(...)`/`refactor(...)`/`test(...)`)。
- 本计划各任务按顺序执行;Task 1-2 期间镜像字段仍存在(编译绿过渡),Task 3 才删除。

---

### Task 1: scoped 解析族 + bar 派生 getter

**Files:**
- Modify: `client/lib/utils/session/workspace_tab_session_scope.dart`
- Modify: `client/lib/cubits/chat/session_launch_host.dart`
- Modify: `client/lib/services/workbench/workbench_chat_bridge.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Test: `client/test/utils/session/workspace_tab_session_scope_test.dart`(新建)

**Interfaces:**
- Produces:
  - `String scopedSelectedMemberId(WorkbenchCubit workbench, ChatCubit chat, String tabScopeId)`
  - `ChatWorkbenchPort.centerActiveForScope(String workspaceId) → WorkbenchTabId?`
  - `ChatCubit.activeTab` 从 bar 派生(带 legacy local-tab 回退);`ChatCubit.activePod` 跟随 `activeTab`
  - `ChatCubit.selectedMemberName(TeamProfile)`、`interruptSelectedMemberTurn`、`setSessionWorkbenchView`、`retrySessionLaunch`、`isMemberWorking`、`_sessionRuntime` 的 `activeSessionId` 回调全部改用 `activeTab`

- [ ] **Step 1: 写失败测试**

新建 `client/test/utils/session/workspace_tab_session_scope_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/utils/session/workspace_tab_session_scope.dart';
import '../support/post_frame_test_harness.dart';

void main() {
  group('scopedSelectedMemberId', () {
    late ChatCubit chat;

    setUp(() {
      setUpTestAppStorage();
      chat = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
      );
    });

    test('returns the active tab selectedMemberId', () {
      final workbench = WorkbenchCubit();
      final tab = ChatTab(
        info: ChatTabInfo(id: 'sess-1', title: 't', subtitle: ''),
        cliTeamName: 'team-1',
        workspaceId: 'ws-1',
      )..selectedMemberId = 'team-lead';
      chat.tabStore.registerSession(tab);
      chat.tabStore.setActiveWorkspaceId('ws-1');
      workbench.openSession('ws-1', 'sess-1', preview: false);

      expect(
        scopedSelectedMemberId(workbench, chat, 'ws-1'),
        'team-lead',
      );
    });

    test('returns empty when the active tab is absent', () {
      final workbench = WorkbenchCubit();

      expect(scopedSelectedMemberId(workbench, chat, 'ws-1'), '');
    });
  });
}
```

(ChatCubit 构造模式参考 `client/test/cubits/chat_cubit_session_launch_test.dart:64-72`;若 `testAutomationRepository` 不在 post_frame_test_harness,按该文件中的实际 import 位置调整。)

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/utils/session/workspace_tab_session_scope_test.dart`
Expected: FAIL — `scopedSelectedMemberId` 未定义。

- [ ] **Step 3: 实现 scoped helper**

`client/lib/utils/session/workspace_tab_session_scope.dart` 追加:

```dart
/// Active session's selected member id for [tabScopeId], or '' when the tab
/// is absent. Same bar-derived source as the sidebar highlight.
String scopedSelectedMemberId(
  WorkbenchCubit workbench,
  ChatCubit chat,
  String tabScopeId,
) =>
    scopedActiveChatTab(workbench, chat, tabScopeId)?.selectedMemberId ?? '';
```

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/utils/session/workspace_tab_session_scope_test.dart`
Expected: PASS。

- [ ] **Step 5: port 增加 `centerActiveForScope`**

`client/lib/cubits/chat/session_launch_host.dart`:
- 加 import: `import '../../cubits/workbench/workbench_tab.dart';`
- `ChatWorkbenchPort` 中把 `syncForeground()` 声明替换为:

```dart
  /// Bar center-active session tab id for [workspaceId] (null when landing or
  /// a file/diff tab is active). Lets the domain derive "the active session"
  /// from the bar — the single source of truth.
  WorkbenchTabId? centerActiveForScope(String workspaceId);
```

- [ ] **Step 6: 更新 bridge**

`client/lib/services/workbench/workbench_chat_bridge.dart`:
- 删除字段 `_workbenchSub`、构造器里的 `_workbench.stream.listen((_) => _syncForeground())`、方法 `_syncForeground()`、`dispose()` 中的 subscription cancel(dispose 保留空实现)。
- 新增:

```dart
  @override
  WorkbenchTabId? centerActiveForScope(String workspaceId) =>
      _workbench.centerActiveId(workspaceId);
```

- [ ] **Step 7: ChatCubit getter 派生**

`client/lib/cubits/chat_cubit.dart`:
- 加 import:`import 'cubits/workbench/workbench_tab.dart';`(按该文件现有相对导入风格写;文件在 `client/lib/cubits/`,故为 `workbench/workbench_tab.dart`;同时确认 `package:collection/collection.dart` 已导入,若未导入则补上)。
- `activeTab` getter(约 587 行)替换为:

```dart
  @override
  ChatTab? get activeTab {
    final wsId = _tabStore.activeWorkspaceId;
    if (wsId.isNotEmpty) {
      final tabId = _workbenchPort?.centerActiveForScope(wsId);
      if (tabId != null && tabId.kind == WorkbenchTabKind.session) {
        final tab = _tabStore.openTabBySessionId(tabId.id);
        if (tab != null) return tab;
      }
    }
    // Legacy local-tab fallback: pre-materialization runtimes are not bar-fed.
    return _tabStore.openTabs.firstOrNull;
  }
```

- `activePod`(约 461 行)替换为:

```dart
  SessionPodState? get activePod {
    final id = activeTab?.info.id;
    if (id == null || id.isEmpty) return null;
    return _pods[id]?.state;
  }
```

- `_sessionRuntime` 构造(约 301 行):`activeSessionId: () => state.activeSessionId,` → `activeSessionId: () => activeTab?.info.id,`
- `isMemberWorking`(约 947 行):`activeSessionId: state.activeSessionId,` → `activeSessionId: activeTab?.info.id,`
- `interruptSelectedMemberTurn`(约 966 行):`final sid = sessionId ?? state.activeSessionId;` → `final sid = sessionId ?? activeTab?.info.id;`
- `setSessionWorkbenchView`(约 1725 行):`final memberId = tab?.selectedMemberId ?? state.selectedMemberId;` → `final memberId = tab?.selectedMemberId ?? '';`
- `selectedMemberName`(约 1833 行):

```dart
  String selectedMemberName(TeamProfile team) {
    final id = activeTab?.selectedMemberId ?? '';
    for (final m in team.members) {
      if (m.id == id) return m.name;
    }
    return team.members.isEmpty ? 'member' : team.members.first.name;
  }
```

- `retrySessionLaunch`(约 1872 行):`selectedMemberId: tab?.selectedMemberId ?? state.selectedMemberId,` → `selectedMemberId: tab?.selectedMemberId ?? '',`

- [ ] **Step 8: 编译 + 测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/cubits/chat_cubit_session_launch_test.dart test/utils/session/`
Expected: 全部 PASS(镜像字段仍在,行为不变)。

- [ ] **Step 9: 提交**

```bash
git add client/lib client/test
git commit -m "refactor(chat): derive active session from workbench bar (scoped helpers)"
```

---

### Task 2: 消费方迁移到 scoped 解析

**Files:**
- Modify: `client/lib/pages/chat/chat_workbench_slice.dart`
- Modify: `client/lib/pages/chat/chat_page_shell.dart:415`
- Modify: `client/lib/pages/chat/chat_page_structural_signal.dart`
- Modify: `client/lib/pages/chat_page.dart:44`
- Modify: `client/lib/pages/chat_workbench.dart:96,115`
- Modify: `client/lib/pages/chat/chat_workbench_terminal.dart:100,109`
- Modify: `client/lib/pages/chat/session_chat_view.dart:874`
- Modify: `client/lib/pages/chat/session_chat_compose_section.dart:148`
- Modify: `client/lib/widgets/follow_up/terminal_follow_up_compose.dart:104`
- Modify: `client/lib/widgets/notification/session_idle_notification_listener.dart:71`
- Modify: `client/lib/main.dart:129`
- Modify: `client/lib/widgets/sidebar_session_tile.dart:298`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_search_dialog.dart:396`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart:258`
- Modify: `client/lib/services/launch/session_launch_pipeline.dart:579`
- Modify: `client/lib/widgets/right_tools/right_tools_tool_views.dart:349`
- Test: `client/test/pages/chat/chat_workbench_slice_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `scopedSelectedMemberId`、`ChatCubit.activeTab`
- Produces: `ChatWorkbenchSlice.fromScope({required ChatState state, required String? activeSessionId, required String selectedMemberId})`(替代 `from`);`RightToolsChatSlice.fromScope(...)`(替代 `from`)

**注意:此任务期间 `ChatState.activeSessionId`/`selectedMemberId` 仍存在,每步改完编译必须绿。**

- [ ] **Step 1: slice 增加 `fromScope`**

`client/lib/pages/chat/chat_workbench_slice.dart` — 在 `from` 旁新增(保留 `from` 直到 Task 3):

```dart
  /// Builds a slice from the scoped bar source: [activeSessionId] and
  /// [selectedMemberId] must come from `scopedActiveSessionId` /
  /// `scopedSelectedMemberId` (Task 1), never from [ChatState] mirrors.
  factory ChatWorkbenchSlice.fromScope({
    required ChatState state,
    required String? activeSessionId,
    required String selectedMemberId,
  }) {
    return ChatWorkbenchSlice(
      activeSessionId: activeSessionId,
      selectedMemberId: selectedMemberId,
      sessionLaunchError: state.sessionLaunchError,
    );
  }
```

- [ ] **Step 2: 适配 slice 测试**

`client/test/pages/chat/chat_workbench_slice_test.dart` — 将 `ChatWorkbenchSlice(...)` 常量构造改为经 `fromScope`(或保留 const 构造断言并新增 `fromScope` 用例):

```dart
import 'package:teampilot/cubits/chat/model/chat_state.dart';
import 'package:teampilot/pages/chat/chat_workbench_slice.dart';

void main() {
  group('ChatWorkbenchSlice.fromScope', () {
    test('projects the scoped identity', () {
      const state = ChatState(sessionLaunchError: 'boom');
      final slice = ChatWorkbenchSlice.fromScope(
        state: state,
        activeSessionId: 'sess-1',
        selectedMemberId: 'team-lead',
      );
      expect(slice.activeSessionId, 'sess-1');
      expect(slice.selectedMemberId, 'team-lead');
      expect(slice.sessionLaunchError, 'boom');
    });
  });
}
```

(保留原有相等性测试,`ChatWorkbenchSlice(...)` const 构造不变。)

- [ ] **Step 3: chat_page_shell 使用 fromScope**

`client/lib/pages/chat/chat_page_shell.dart` 约 415 行,在 `BlocBuilder<WorkbenchCubit, WorkbenchState>` 的 builder 内(`activeId`、`tabById` 已在作用域),将:

```dart
                    workbenchSlice: ChatWorkbenchSlice.from(state),
```

替换为:

```dart
                    workbenchSlice: ChatWorkbenchSlice.fromScope(
                      state: state,
                      activeSessionId: activeId?.sessionId,
                      selectedMemberId:
                          tabById[activeId?.sessionId]?.selectedMemberId ?? '',
                    ),
```

- [ ] **Step 4: 结构性信号改用 bar 派生**

`client/lib/pages/chat/chat_page_structural_signal.dart` 中 `chatPageStructuralSignal`:

```dart
  return ChatPageStructuralSignal(
    tabIds: tabIds,
    activeTabIndex: activeId == null ? -1 : order.indexOf(activeId),
    newChatActive: bar.center.landingActive,
    selectedMemberId: activeTab?.selectedMemberId ?? '',
    sessionLaunchError: isForeground
        ? (activeTab?.info.launchError ?? state.sessionLaunchError)
        : activeTab?.info.launchError,
    pinnedBySessionId: _pinnedForTabIds(state, tabIds),
  );
```

- [ ] **Step 5: chat_page / chat_workbench / chat_workbench_terminal**

- `client/lib/pages/chat_page.dart`(加 import `../../cubits/workbench/workbench_cubit.dart`):

```dart
    final activeSessionId = context.select<WorkbenchCubit, String?>(
      (w) => w.centerActiveId(_tabScopeId)?.sessionId,
    );
```

- `client/lib/pages/chat_workbench.dart:96`:`final sessionId = chatCubit.state.activeSessionId?.trim() ?? '';` → `final sessionId = chatCubit.activeTab?.info.id?.trim() ?? '';`
- `client/lib/pages/chat_workbench.dart:115`:`final memberId = chatCubit.state.selectedMemberId;` → `final memberId = chatCubit.activeTab?.selectedMemberId ?? '';`
- `client/lib/pages/chat/chat_workbench_terminal.dart:100`:`final sessionId = chat.state.activeSessionId?.trim() ?? '';` → `final sessionId = chat.activeTab?.info.id?.trim() ?? '';`
- `client/lib/pages/chat/chat_workbench_terminal.dart:109`:`final memberId = chat.state.selectedMemberId.trim();` → `final memberId = chat.activeTab?.selectedMemberId.trim() ?? '';`

- [ ] **Step 6: 会话级组件改用 bar 依赖**

- `client/lib/pages/chat/session_chat_view.dart` 约 874 行(加 import `workbench_cubit.dart`、`workbench_tab.dart`):

```dart
    // Rebuild when the session's workspace bar active changes (session switch)
    // or session working changes (seat-level stop).
    context.select<WorkbenchCubit, WorkbenchTabId?>(
      (w) => w.centerActiveId(widget.session.workspaceId),
    );
    context.select<ChatCubit, Set<String>>(
      (c) => c.state.workingSessionIds,
    );
```

- `client/lib/pages/chat/session_chat_compose_section.dart` 约 148 行,同样替换为上面两个 select(该 widget 有 `widget.session`)。

- `client/lib/widgets/follow_up/terminal_follow_up_compose.dart` 约 104 行(加 import):

```dart
    context.select<WorkbenchCubit, WorkbenchTabId?>(
      (w) => w.centerActiveId(session.workspaceId),
    );
    context.select<ChatCubit, Set<String>>(
      (c) => c.state.workingSessionIds,
    );
```

- [ ] **Step 7: 全局读取点**

- `client/lib/widgets/notification/session_idle_notification_listener.dart:71`:
  `activeSessionId: state.activeSessionId,` → `activeSessionId: context.read<ChatCubit>().activeTab?.info.id,`
- `client/lib/main.dart:129`:`hasSessionTab: chatCubit.state.activeSessionId != null,` → `hasSessionTab: chatCubit.activeTab != null,`
- `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart:258`:
  `final sessionId = context.read<ChatCubit>().state.activeSessionId?.trim() ?? '';` → `final sessionId = context.read<ChatCubit>().activeTab?.info.id?.trim() ?? '';`
- `client/lib/services/launch/session_launch_pipeline.dart:579`:
  `final activeId = _activeTab()?.info.id ?? state.activeSessionId ?? 'pending';` → `final activeId = _activeTab()?.info.id ?? 'pending';`(此时 `state` 变量可能不再使用,检查后删除局部 `final state = _state();`)

- [ ] **Step 8: 侧边栏 tile 与搜索对话框**

`client/lib/widgets/sidebar_session_tile.dart` 约 298-302 行(无 highlight 时的回退不再读镜像):

```dart
    final selected = widget.highlightSessionId != null
        ? widget.highlightSessionId == sessionId
        : false;
```

`client/lib/pages/home_workspace/workspace/workspace_search_dialog.dart` 约 396 行,给 tile 传显式 highlight(加 import `workbench_cubit.dart`、`workspace_tab_session_scope.dart`):

```dart
          SidebarSessionTile(
            session: session,
            highlightSessionId: scopedActiveSessionId(
              context.read<WorkbenchCubit>(),
              widget.workspace.workspaceId,
            ),
            tapThrottleKeyPrefix: 'workspace_search_recent',
            onTap: () => widget.onOpenSession(session),
          ),
```

- [ ] **Step 9: right-tools slice 改用 scoped**

`client/lib/widgets/right_tools/right_tools_tool_views.dart`:
- `RightToolsChatSlice.from(...)`(约 192-205 行)替换为:

```dart
  factory RightToolsChatSlice.fromScope({
    required String selectedMemberId,
    required String? activeSessionId,
    required bool hasActiveTab,
    required bool hasTeamBus,
    AppSession? persistedSession,
  }) {
    return RightToolsChatSlice(
      selectedMemberId: selectedMemberId,
      hasActiveTab: hasActiveTab,
      activeSessionId: activeSessionId,
      hasTeamBus: hasTeamBus,
      persistedSession: persistedSession,
    );
  }
```

- `_buildWithUnread`(约 348-357 行)替换为:

```dart
    final workbench = context.read<WorkbenchCubit>();
    final activeSessionId = context.select<WorkbenchCubit, String?>(
      (w) => scopedActiveSessionId(w, widget.toolsScopeId),
    );
    final chatSlice = context.select<ChatCubit, RightToolsChatSlice>(
      (c) => RightToolsChatSlice.fromScope(
        selectedMemberId:
            scopedSelectedMemberId(workbench, c, widget.toolsScopeId),
        activeSessionId: activeSessionId,
        hasActiveTab:
            c.tabStore.tabsForWorkspace(widget.toolsScopeId).isNotEmpty,
        hasTeamBus: scopedTeamBus(workbench, c, widget.toolsScopeId) != null,
        persistedSession:
            scopedActiveChatTab(workbench, c, widget.toolsScopeId)
                ?.persistedSession,
      ),
    );
```

- [ ] **Step 10: 编译 + 相关测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/pages/chat/chat_workbench_slice_test.dart test/pages/chat/keep_alive_session_stack_test.dart test/widgets/sidebar_session_tile_test.dart test/widgets/right_tools/members_panel_menu_test.dart test/pages/chat/terminal_follow_up_compose_test.dart test/utils/workspace/workspace_active_context_test.dart`
Expected: 全部 PASS。

- [ ] **Step 11: 提交**

```bash
git add client/lib client/test
git commit -m "refactor(chat): resolve session/member identity via workbench bar scopes"
```

---

### Task 3: 删除全局镜像字段与写入

**Files:**
- Modify: `client/lib/cubits/chat/model/chat_state.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Modify: `client/lib/cubits/chat/session_launch_service.dart`
- Modify: `client/lib/pages/chat/chat_workbench_slice.dart`(删 `from`)
- Modify: `client/lib/widgets/right_tools/right_tools_tool_views.dart`(删 `from` 若仍有引用)
- Test: `client/test/services/launch/session_tab_surface_coordinator_test.dart`、`client/test/cubits/chat_cubit_session_launch_test.dart`

- [ ] **Step 1: 删除 ChatState 镜像字段**

`client/lib/cubits/chat/model/chat_state.dart`:
- 构造参数删除 `this.activeSessionId,` 与 `this.selectedMemberId = '',`
- 字段删除 `final String? activeSessionId;` 与 `final String selectedMemberId;`
- `copyWith` 删除参数 `String? activeSessionId,`、`String? selectedMemberId,`、`bool clearActiveSessionId = false,`,并删除对应赋值行
- `props` 删除 `activeSessionId,` 与 `selectedMemberId,`

- [ ] **Step 2: 删除 ChatCubit 镜像写入**

`client/lib/cubits/chat_cubit.dart`:
- 删除 `setForegroundSession` 整个方法(约 1240-1251 行)
- `setActiveWorkspace` 删除 `_workbenchPort?.syncForeground();` 一行
- `activateWorkspaceTab` 删除 `_workbenchPort?.syncForeground();` 一行
- `syncTeam` 替换为:

```dart
  void syncTeam(TeamProfile team) {
    final tab = _activeTab;
    if (team.members.isEmpty) {
      if (tab != null) tab.selectedMemberId = '';
      return;
    }
    if (team.members.any((m) => m.id == tab?.selectedMemberId)) return;
    tab?.selectedMemberId = _tabStore.defaultMemberId(team);
  }
```

- `selectMember` 替换为:

```dart
  @override
  void selectMember(String memberId) {
    final tab = _activeTab;
    if (tab == null || tab.selectedMemberId == memberId) return;
    tab.selectedMemberId = memberId;
    if (tab.workbenchView == SessionWorkbenchView.terminal) {
      unawaited(ensureMemberTerminalForView(tab.info.id, memberId));
    }
  }
```

- `deleteSession`(约 2094-2124 行):删除 `final wasActive = ...;` 与 base copyWith 中的镜像参数:

```dart
      base: state.copyWith(
        workingSessionIds: working,
      ),
```

- [ ] **Step 3: 删除 launch service 镜像写入**

`client/lib/cubits/chat/session_launch_service.dart`:
- `_updateSelectedMember`(约 159-164 行)替换为:

```dart
  void _updateSelectedMember(String memberId) {
    // Selected member lives on the ChatTab; the tab-connect prep writes
    // tab.selectedMemberId. The bar is the single session-identity source.
  }
```

- `_appendLocalTab`(约 823-836 行)替换为:

```dart
  ChatTab _appendLocalTab(TeamProfile team, {required bool emitChange}) {
    final tab = _tabStore.appendLocalTab(team, cliTeamName: _uuid.v4());
    return tab;
  }
```

(`emitChange` 参数保留以维持调用点签名;若 analyzer 报 unused,在函数签名前加 `// ignore: avoid_unused_constructor_parameters` 风格处理或删除参数并同步调用点。)

- [ ] **Step 4: surface 流程删除镜像写入并喂 bar**

`client/lib/services/launch/session_tab_surface_coordinator.dart`:
- `surfaceExistingTab`(约 100-106 行):删除 `_host.applyState(_host.state.copyWith(activeSessionId: ...))`,替换为 bar feed(bar 是唯一写入者,复用 tab 也喂):

```dart
    // The bar is the single session-identity source: reuse feeds the bar too
    // (preview matches surfaceNewTab semantics; running tabs pin on reopen).
    onSessionTabOpened?.call(
      existing.workspaceId,
      session.sessionId,
      preview: !request.connectImmediately,
      activate: true,
    );
    _host.refreshActiveWorkspaceTabs();
```

- `surfaceNewTab`(约 174-179 行):删除 `_host.applyState(_host.state.copyWith(activeSessionId: ...))`,保留 `onSessionTabOpened?.call(...)` 与 `_host.refreshActiveWorkspaceTabs();`

- [ ] **Step 5: 适配测试中的镜像构造**

`client/test/services/launch/session_tab_surface_coordinator_test.dart`:
- `_FakeHost(ChatState(activeSessionId: 'sess-1'), ...)` → `_FakeHost(const ChatState(), ...)`
- 删除测试 `'does not feed onSessionTabOpened when reusing an existing tab'`(行为已在 Step 4 反转;Task 4 补回归断言)。
- 编译后若有其他 `ChatState(activeSessionId:...)` / `state.activeSessionId` 引用,逐一删除或改用 scoped。

`client/test/cubits/chat_cubit_session_launch_test.dart`:修复所有 `ChatState(...activeSessionId...)` 构造与 `state.activeSessionId` 断言(按编译器提示逐点改,必要时改为断言 `chat.activeTab?.info.id`)。

- [ ] **Step 6: 删除 `ChatWorkbenchSlice.from`**

`client/lib/pages/chat/chat_workbench_slice.dart`:删除 `from` 工厂(所有调用方已在 Task 2 迁移)。`right_tools_tool_views.dart` 的 `RightToolsChatSlice.from` 同理删除。

- [ ] **Step 7: 全量编译 + 测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: 编译绿;因删除测试行为导致的失败按 Task 4 的新断言处理,其余失败逐点修复。

- [ ] **Step 8: 提交**

```bash
git add client/lib client/test
git commit -m "refactor(chat): remove global activeSessionId/selectedMemberId mirrors"
```

---

### Task 4: 孤儿 tab 清除 + 移除二次喂 bar

**Files:**
- Modify: `client/lib/services/workbench/workbench_chat_bridge.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`
- Modify: `client/lib/services/workbench/workbench_shell_actions.dart`(删 `closeReplacedPreview`)
- Test: `client/test/services/workbench/workbench_chat_bridge_test.dart`(新建)、`client/test/services/launch/session_tab_surface_coordinator_test.dart`

**背景:** Task 3 已让 surface 流程只喂一次 bar;本任务消除"preview 被替换后域内 runtime 变孤儿"的残留,并删除 `openWorkspaceSessionTab` 中 await 后的二次喂 bar(慢点击覆盖快点击的竞态来源)。

- [ ] **Step 1: 写失败测试(preview 替换触发 teardown)**

新建 `client/test/services/workbench/workbench_chat_bridge_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/services/workbench/workbench_chat_bridge.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  group('WorkbenchChatBridge.onSessionTabOpened', () {
    late ChatCubit chat;

    setUp(() {
      setUpTestAppStorage();
      chat = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
      );
    });

    test('tears down a preview replaced in place', () async {
      final workbench = WorkbenchCubit();
      chat.tabStore.setActiveWorkspaceId('ws-1');
      final bridge = WorkbenchChatBridge(workbench: workbench, chat: chat);

      chat.tabStore.registerSession(
        ChatTab(
          info: ChatTabInfo(id: 'A', title: 'a', subtitle: ''),
          cliTeamName: '',
          workspaceId: 'ws-1',
        ),
      );
      chat.tabStore.registerSession(
        ChatTab(
          info: ChatTabInfo(id: 'B', title: 'b', subtitle: ''),
          cliTeamName: '',
          workspaceId: 'ws-1',
        ),
      );

      bridge.onSessionTabOpened('ws-1', 'A', preview: true);
      bridge.onSessionTabOpened('ws-1', 'B', preview: true);
      await pumpEventQueue();

      expect(chat.tabStore.openTabBySessionId('B'), isNotNull);
      // A was replaced in place by B and must not linger as an orphan runtime.
      expect(chat.tabStore.openTabBySessionId('A'), isNull);
    });
  });
}
```

Expected: FAIL — A 仍在 tabStore(teardown 未接线)。

- [ ] **Step 2: 实现 bridge teardown**

`client/lib/services/workbench/workbench_chat_bridge.dart`:

```dart
  void onSessionTabOpened(
    String workspaceId,
    String sessionId, {
    bool preview = false,
    bool activate = true,
  }) {
    final replaced = _workbench.openSession(
      workspaceId,
      sessionId,
      preview: preview,
      activate: activate,
    );
    // A preview slot replaced in place is no longer in the bar; tear its
    // domain runtime down so it cannot be resurrected as an orphan.
    if (replaced != null && replaced.kind == WorkbenchTabKind.session) {
      unawaited(_chat.teardownSession(replaced.id));
    }
  }
```

- [ ] **Step 3: 运行确认通过**

Run: `cd client && flutter test test/services/workbench/workbench_chat_bridge_test.dart`
Expected: PASS。

- [ ] **Step 4: 回归测试(surface 单一喂 bar)**

`client/test/services/launch/session_tab_surface_coordinator_test.dart`,在 `surfaceExistingTab` group 内新增:

```dart
    test('feeds onSessionTabOpened once when reusing an existing tab', () {
      final status = coordinator.surfaceExistingTab(
        request: SessionOpenRequest(
          session: session,
          connectImmediately: true,
        ),
        existing: existing,
      );

      expect(status, SessionOpenStatus.opened);
      expect(openedCalls, [
        (
          workspaceId: 'ws-1',
          sessionId: 'sess-1',
          preview: false,
          activate: true,
        ),
      ]);
    });

    test('feeds preview: true when history-reviewing an existing tab', () {
      final status = coordinator.surfaceExistingTab(
        request: SessionOpenRequest(
          session: session,
          connectImmediately: false,
        ),
        existing: existing,
      );

      expect(status, SessionOpenStatus.opened);
      expect(openedCalls, [
        (
          workspaceId: 'ws-1',
          sessionId: 'sess-1',
          preview: true,
          activate: true,
        ),
      ]);
    });
```

(这些断言此时已应通过 — Task 3 Step 4 已接线;作为回归护栏运行确认。)

- [ ] **Step 5: openWorkspaceSessionTab 删除二次喂 bar**

`client/lib/pages/home_workspace/workspace/workspace_session_actions.dart` `openWorkspaceSessionTab`(约 128-159 行)尾部替换为:

```dart
  if (status != SessionOpenStatus.opened) return;
}
```

即删除 `scopeId`/`tabId`/`asPreview`/`existing` 分支/`replaced`/`closeReplacedPreview` 全部代码。同时删除 `WorkbenchShellActions` 与 `workbench_tab.dart` 的 import(若不再使用)。

- [ ] **Step 6: 删除 closeReplacedPreview**

`client/lib/services/workbench/workbench_shell_actions.dart`:删除 `closeReplacedPreview` 静态方法(唯一调用方已删除)。

- [ ] **Step 7: 全量编译 + 测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: 编译绿,全部通过。

- [ ] **Step 8: 提交**

```bash
git add client/lib client/test
git commit -m "fix(session): tear down replaced previews; drop double bar feed on open"
```

---

### Task 5: TeamBus 复用补装

**Files:**
- Modify: `client/lib/services/launch/session_launch_connect_prep_runner.dart:181-189`
- Test: `client/test/services/launch/session_launch_connect_prep_runner_test.dart`(新建)

- [ ] **Step 1: 写失败测试**

新建 `client/test/services/launch/session_launch_connect_prep_runner_test.dart`(参考现有 `_FakeHost` 风格,最小化:直接测 `SessionLaunchConnectPrepRunner` 构造并调用 `prepareExistingTabConnect`,捕获传给 `runSessionTabConnectPrep` 的 `installTeamRuntime`;若该函数依赖过多,改为直接断言决策函数):

将决策提取为纯函数并测试(Step 2 实现):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/services/launch/session_launch_connect_prep_runner.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import '../team_bus/support/fake_member_launcher.dart';

void main() {
  group('needsTeamRuntimeOnReuse', () {
    test('true for a team tab without a bus', () {
      final tab = ChatTab(
        info: ChatTabInfo(id: 'sess-1', title: 't', subtitle: ''),
        cliTeamName: 'team-1',
        workspaceId: 'ws-1',
      );
      expect(needsTeamRuntimeOnReuse(tab, isPersonal: false), isTrue);
    });

    test('false when the bus is already installed', () {
      final tab = ChatTab(
        info: ChatTabInfo(id: 'sess-1', title: 't', subtitle: ''),
        cliTeamName: 'team-1',
        workspaceId: 'ws-1',
      )..teamBus = TeamBus(launcher: FakeMemberLauncher());
      expect(needsTeamRuntimeOnReuse(tab, isPersonal: false), isFalse);
    });

    test('false for personal sessions', () {
      final tab = ChatTab(
        info: ChatTabInfo(id: 'sess-1', title: 't', subtitle: ''),
        cliTeamName: '',
        workspaceId: 'ws-1',
      );
      expect(needsTeamRuntimeOnReuse(tab, isPersonal: true), isFalse);
    });
  });
}
```

Expected: FAIL — `needsTeamRuntimeOnReuse` 未定义。

- [ ] **Step 2: 提取决策函数并接线**

`client/lib/services/launch/session_launch_connect_prep_runner.dart` 新增顶层函数:

```dart
/// Whether an existing-tab reuse must (re)install the mixed team runtime:
/// personal sessions never need it, and an installed bus makes it a no-op.
bool needsTeamRuntimeOnReuse(ChatTab tab, {required bool isPersonal}) =>
    !isPersonal && tab.teamBus == null;
```

`prepareExistingTabConnect` 中,`runSessionTabConnectPrep(...)` 调用的 `installTeamRuntime: false,` 改为:

```dart
        installTeamRuntime: needsTeamRuntimeOnReuse(tab, isPersonal: request.isPersonal),
```

- [ ] **Step 3: 运行确认通过**

Run: `cd client && flutter test test/services/launch/session_launch_connect_prep_runner_test.dart`
Expected: PASS。

- [ ] **Step 4: 提交**

```bash
git add client/lib client/test
git commit -m "fix(session): install mixed TeamBus on tab reuse when missing"
```

---

### Task 6: 右侧工具栏订阅修复

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart:217`
- Test: `client/test/pages/home_workspace/workspace/workspace_split_pane_test.dart`(新建,或并入现有 widget 测试)

- [ ] **Step 1: 写失败测试(订阅模式回归护栏)**

新建 `client/test/pages/home_workspace/workspace/workspace_split_pane_test.dart` — 用与 `_WorkspaceRightToolsPane` 完全相同的 select 模式(`context.select<WorkbenchCubit, String?>` + `scopedActiveSessionId`)做探针,证明 bar active 变化会触发重建:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/utils/session/workspace_tab_session_scope.dart';

void main() {
  testWidgets('bar center-active change rebuilds a scoped-active consumer',
      (tester) async {
    final workbench = WorkbenchCubit();
    var rebuilds = 0;

    await tester.pumpWidget(
      BlocProvider<WorkbenchCubit>.value(
        value: workbench,
        child: _ActiveIdProbe(
          tabScopeId: 'ws-1',
          onBuild: () => rebuilds++,
        ),
      ),
    );
    expect(rebuilds, 1);

    workbench.openSession('ws-1', 'sess-a', preview: true);
    await tester.pump();
    expect(rebuilds, 2);

    workbench.openSession('ws-1', 'sess-b', preview: true);
    await tester.pump();
    expect(rebuilds, 3);
  });
}

/// Mirrors the `_WorkspaceRightToolsPane` subscription exactly: any bar
/// center-active change must rebuild the consumer.
class _ActiveIdProbe extends StatelessWidget {
  const _ActiveIdProbe({required this.tabScopeId, required this.onBuild});

  final String tabScopeId;
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    final _ = context.select<WorkbenchCubit, String?>(
      (w) => scopedActiveSessionId(w, tabScopeId),
    );
    onBuild();
    return const SizedBox.shrink();
  }
}
```

Expected: 失败(rebuilds 停在 1)仅在当前实现不订阅时成立;实际此测试在实现前会 PASS(select 模式本来就有效)。因此本测试是**回归护栏**,核心交付是 Step 2 的接线;执行者须确认 Step 2 完成后该测试仍 PASS。

- [ ] **Step 2: pane 订阅 centerActiveId**

`client/lib/pages/home_workspace/workspace/workspace_split_pane.dart` `_WorkspaceRightToolsPane.build` 中,在现有 `composeLanding` select 之后新增:

```dart
    // Rebuild whenever the bar's center-active session changes so the
    // team/personal context is never stale after a direct session switch.
    final activeSessionId = context.select<WorkbenchCubit, String?>(
      (w) => scopedActiveSessionId(w, tabScopeId),
    );
```

`activeSessionId` 变量仅用于触发重建(声明后不读取;若 analyzer 报 unused,使用 `final _ = ...`)。随后 `WorkspaceActiveContext.resolve(...)` 会基于最新 bar 重算 `team`/`isPersonalContext`,传入 `RightToolsPanel`。

(需要 import:`../../../utils/session/workspace_tab_session_scope.dart`。)

- [ ] **Step 3: 运行测试 + 编译**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/pages/home_workspace/workspace/`
Expected: PASS。

- [ ] **Step 4: 提交**

```bash
git add client/lib client/test
git commit -m "fix(workspace): refresh right-tools team context on session switch"
```

---

### Task 7: 全量验证与收尾

**Files:**
- Modify: 依验证结果

- [ ] **Step 1: 全量 analyze + 测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: 全部通过。若有失败:
- `ChatState(...)` 构造残留引用 → 删除镜像参数
- 任何 `state.activeSessionId`/`state.selectedMemberId` 残留 → 按 Task 2 模式改 scoped
- `syncForeground`/`setForegroundSession` 残留引用 → 删除

- [ ] **Step 2: grep 审计**

Run: `rg -n "state\.activeSessionId|state\.selectedMemberId|setForegroundSession|syncForeground|clearActiveSessionId" client/lib`
Expected: 无输出。

- [ ] **Step 3: 提交收尾**

```bash
git add client/lib client/test
git commit -m "chore(session): final mirror-cleanup fallout fixes"
```

(若 Step 1-2 无任何修改,跳过此 commit,本任务合并入验证结论。)

---

## 完成标准

1. `rg "state\.activeSessionId|state\.selectedMemberId|setForegroundSession|syncForeground" client/lib` 无输出。
2. `flutter analyze --no-fatal-infos --no-fatal-warnings` 通过。
3. `flutter test --exclude-tags integration` 全部通过。
4. 手工验证(桌面端):
   - 打开同名 Session A → 再点同名 Session B:标签栏与中心内容切到 B,侧边栏高亮 B,三处一致。
   - 快速连点两个 Session:最终落在最后点击的那个。
   - 个人 Session 切到 Mixed Session:右侧出现成员/信箱/任务板;反之切回个人:团队面板消失。
   - 复用已打开的 Mixed Session(先开一次、关掉 bus 相关路径再开):成员/信箱/任务板仍出现。
