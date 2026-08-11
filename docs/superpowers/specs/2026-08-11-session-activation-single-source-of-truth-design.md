# Session 激活单一事实来源 + Mixed 团队面板修复 — 设计

Date: 2026-08-11
Status: Approved (brainstorming)

## 问题

### Issue 1: 点击 Session 列表的 Session 却切到别的 Session / 只高亮不切换

用户复现路径:**相同名称的 Session 容易触发**。先打开一个 Session A,再点击打开另一个 Session B,B 只在侧边栏高亮,但顶部标签栏与中心内容仍停留在 A。

根因(按严重程度):

1. **全局镜像与 per-workspace bar 分叉**。`ChatState.activeSessionId` / `selectedMemberId` 是全局镜像,由 `WorkbenchChatBridge._syncForeground` 从 `tabStore.activeWorkspaceId` 对应的 bar 同步;而侧边栏高亮(`scopedActiveSessionId`)直接从 `WorkbenchCubit.bar(tabScopeId)` 读取。侧边栏与中心内容各自读取不同来源,任何时序偏差都导致"高亮在 B、内容在 A"。
2. **`surfaceExistingTab` 直接写镜像但不喂 bar**(`session_tab_surface_coordinator.dart:100`)。域内直接 `applyState(activeSessionId: ...)`,bar 不变;后续 `_syncForeground` 一旦从其他 bar 事件触发,镜像又被写回旧值。
3. **`openWorkspaceSessionTab` 在 await 后二次喂 bar**(`workspace_session_actions.dart:147`)。bridge 在 `requestOpenSession` 内部已喂过一次;`requestOpenSession` 返回后(经历 `_syncSessionTeam` 的异步 `selectTeam`、persist 等任意时长)再次 `workbench.openSession`,若期间用户已点击另一个 Session B,此调用会重新激活旧的 A — 慢点击覆盖快点击。
4. **`_WorkspaceRightToolsPane` 不订阅 bar 的 active 变化**(`workspace_split_pane.dart:217`),只订阅 `workspaceNewChatActive`(landing 切换)与 LayoutCubit。直接 Session→Session 切换时 `team` / `isPersonalContext` 参数陈旧。

### Issue 2: Mixed 团队 Session 右侧工具栏缺团队面板

用户现象:右侧工具栏有文件树/Git,但缺成员/信箱/任务板。

根因:

1. **陈旧上下文(主要)**:同 Issue 1-4。从个人 Session(或另一团队的 Session)直接切到 Mixed Session 时,`RightToolsPanel.team` / `isPersonalContext` 保持旧值,`RightToolsMailboxGate.resolve` 与成员面板条件(`!isPersonalContext && team != null`)全部不满足。
2. **TeamBus 缺失(次要)**:`prepareExistingTabConnect` 以 `installTeamRuntime: false` 运行(`session_launch_connect_prep_runner.dart:188`)。若 tab 首次打开时 bus 安装失败/被跳过(mixed placement 未就绪等),`tab.teamBus` 永久为 null,信箱/任务板(`hasTeamBus` 条件)永不出现。

## 设计

### 架构:单一事实来源

**Workbench bar 是 per-workspace 的唯一事实来源;`ChatTab` 持有 per-session 运行时;不再存在全局镜像。**

```
WorkbenchCubit.bar(wsId).center       ← 唯一身份来源(activeId / order / previews)
ChatTabStore.openTabBySessionId(id)   ← per-session 运行时(selectedMemberId, shells, teamBus, persistedSession)
```

1. 删除 `ChatState.activeSessionId` / `selectedMemberId`(连同 `clearActiveSessionId` 字段、`setForegroundSession`、`WorkbenchChatBridge._syncForeground` 的镜像职责)。
2. 新增/完善 scoped 解析族(`client/lib/utils/session/workspace_tab_session_scope.dart`),全部从 bar + tabStore 派生,与侧边栏高亮同源:
   - `scopedActiveSessionId(workbench, tabScopeId)`(已有)
   - `scopedActiveChatTab(workbench, chat, tabScopeId)`(已有)
   - `scopedSelectedMemberId(workbench, chat, tabScopeId)`(新):`scopedActiveChatTab()?.selectedMemberId ?? ''`
3. `ChatCubit` 全局 getter 改为实时派生(供 landing 提交、自动化、深层链接等 route-active 流程):`activeTab`、`activePod`、`currentSession`、`activeLaunchError`、`activeTabWorkingDirectory` 等从 `tabStore.activeWorkspaceId` + bar 现算,不存 state、不 emit。

### 打开会话流程:消除竞态

1. **`surfaceExistingTab`**(`session_tab_surface_coordinator.dart`):删除直接写 `activeSessionId` 的 `applyState`;统一改为 `onSessionTabOpened?.call(wsId, sessionId, preview: false, activate: true)` 喂 bar。`selectedMemberId` 直接写 `existing.selectedMemberId`,不再进 state。
2. **`surfaceNewTab`**:保持"注册 tab → 喂 bar"顺序,仅删除 `applyState(activeSessionId: ...)`。
3. **`openWorkspaceSessionTab`**(`workspace_session_actions.dart`):`requestOpenSession` 返回后删除二次 `workbench.openSession`。仅保留 `connectImmediately && tab 已运行` 时的一次 `openSession(preview: false)`(置 pin,无激活竞态)。
4. **pipeline 各处镜像写入**(`_connectPersonalSession` / `_connectExistingSession` / `_ensureActiveSessionTab` / `_appendLocalTab`):删除,统一由 bar 承载激活。

### 消费方迁移:per-workspace 解析

1. **`ChatWorkbenchSlice`**(`chat_workbench_slice.dart`):`from(state)` → `fromScope(workbench, chat, tabScopeId)`,内部使用 `scopedActiveSessionId` + `scopedSelectedMemberId`。`activeSessionId` 保留在 slice 中作为相等性依据。
2. **订阅链**:slice 消费方(`chat_workbench.dart`、`chat_workbench_terminal.dart`、`session_chat_compose_section.dart`、`right_tools_tool_views.dart` 的 `chatSlice`)采用**双层嵌套 select**:外层 `context.select<WorkbenchCubit, WorkbenchTabId?>` 取 `centerActiveId(tabScopeId)`,内层 `context.select<ChatCubit, ...>` 取会话数据(如 pod/session),确保 bar 变化时重建。
3. 逐点迁移其余 `state.activeSessionId` / `state.selectedMemberId` 读取(`chat_workbench.dart:96/115`、`session_chat_compose_section.dart:148`、`chat_page.dart`、`chat_page_shell.dart`、`chat_workbench_terminal.dart:100/109`)。
4. 侧边栏已使用 scoped,验证即可,不改。

### 右侧工具栏修复(Issue 2)

1. **订阅修复**:`_WorkspaceRightToolsPane` 增加 `context.select<WorkbenchCubit, WorkbenchTabId?>` 依赖 `centerActiveId(tabScopeId)`,Session 切换即重建,`WorkspaceActiveContext.resolve` 重算 `team` / `isPersonalContext`。
2. **解析下沉(双保险)**:`team` / `isPersonalContext` 解析下沉到 `RightToolsToolViews` 内部(scoped 解析,`_RightToolsViewsCacheKey` 已含 `team` / `chatSlice`),pane 层漏重建时 views 层仍解析最新上下文。
3. **TeamBus 补装**:`prepareExistingTabConnect` 改为 `team.teamMode == mixed && tab.teamBus == null` 时 `installTeamRuntime: true`;bus 已存在则跳过(幂等)。修复 mailbox/board 永不出现的路径。

### 错误处理与边界

- `surfaceExistingTab` 喂 bar 时若 bar 中无该 tab,`TabStripReducer.add` 自动追加;`replaced` 预览替换返回值继续由 `openWorkspaceSessionTab` 的 `closeReplacedPreview` 处理(此时来自 bridge 的单次返回,不再有二次喂导致的 null)。
- `scopedSelectedMemberId` 在 tab 缺失时返回空串(与现有语义一致)。
- bar 只存 id,不校验 session 存在,保持现状。
- TeamBus 补装失败:保持现有 `setLaunchError` 行为,不阻塞会话打开。

## 测试

- `TabStripReducer` 现有测试不变。
- 新增 `SessionTabSurfaceCoordinator` 测试:existing tab 也喂 bar(fake host 断言 `onSessionTabOpened` 被调用、`applyState` 不再携带 activeSessionId)。
- 新增 `openWorkspaceSessionTab` 竞态测试:慢 `requestOpenSession` + 快速二次点击,断言最终 bar active 为第二个点击。
- 新增 `scopedSelectedMemberId` 测试(空/非空)。
- 新增 `prepareExistingTabConnect` TeamBus 补装测试:null + mixed → install;存在 → 跳过。
- `RightToolsToolViews` 订阅重建测试:`centerActiveId` 变化 → 重建 → team 更新。
- 适配现有测试:`ChatState` 构造签名、`ChatWorkbenchSlice.from` 改名、`setForegroundSession` 删除等。

## 验证

`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`

## 范围外(后续任务)

- 方案 B 的完整形态已在此设计中落地;无需后续分解。
- `workingSessionIds` 等全局工作状态保持现状(非会话身份,不受影响)。
