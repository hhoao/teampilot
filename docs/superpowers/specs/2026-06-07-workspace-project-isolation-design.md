# WorkspaceShell 项目级别隔离设计

- 日期:2026-06-07
- 主题:把 WorkspaceShell 周边的运行时状态改成「项目级别隔离 + 保活恢复」
- 架构方向:方向 B —— 项目键控工作区运行时(project-keyed workspace runtime)

## 背景与问题

`WorkspaceShell`(`client/lib/pages/workspace_shell/workspace_shell.dart`)本身是**纯展示型布局容器**,不持有状态。真正在跨项目共享的是它周边的几类状态。

当前 `HomeWorkspaceShell`(`client/lib/pages/home_workspace/home_workspace_shell.dart`)**只渲染单个路由 child**(第 264 行 `widget.child`);顶部 tab 仅是一个 tab *bar*(`HomeWorkspaceTitleBar`),并非 IndexedStack 保活。因此切换项目 = `context.go('/home-v2/project/<id>')` → GoRouter 重建 `HomeWorkspaceProjectPage`,**上一个项目的页面被销毁重建**。

由此产生三个现状问题:

| 关注点 | 当前状态 | 问题 |
|--------|----------|------|
| 工作区终端(底部 PTY) | 已按 cwd 隔离(`ValueKey('workspace-terminal-$cwd')`),切走即 `dispose` | PTY 进程被杀、scrollback 丢失,切回是全新终端 |
| 聊天 Tab / 会话(ChatCubit) | **全局单例 + 扁平 `List<ChatTab>`**,仅按 teamId 过滤可见性 | 跨项目泄漏;个人项目 teamId 均为空 → 互相看到对方的 tab |
| 右侧工具内容 | 选中项是 `_TabbedPanelState._selected` 本地 widget state | 切走即重置 |

## 目标(用户确认的范围)

按 `projectId` 隔离并**保活恢复**以下三块运行时状态:

1. 工作区终端(终端进程 / scrollback / 滚动位置)
2. 聊天 Tab / 会话
3. 右侧工具面板「选中的工具 / 内容选择」

明确**不在范围内**:

- 布局尺寸偏好(右侧工具宽度/可见性、底部终端高度/可见性、面板位置、preset)——保持现有 `LayoutCubit` 全局持久化语义。
- 跨 App 重启恢复 scrollback —— 仅做内存内保活(tab 打开期间),App 重启不恢复终端内容。
- 不改动 team session scoping 的既有语义(仅在分桶所需范围内调整)。

## 选定架构:方向 B

为每个打开的项目维护一份**脱离 widget 存活、按 `projectId` 键控的运行时状态**,生命周期跟随 HomeWorkspaceShell 「打开的项目 tab」,而非页面 widget。保持「单 child 路由」不变,只挂载当前项目页,切换时重建轻量 UI 并从仓库**重新挂接**已存活的会话与状态。

选择理由:

- **性能**:只挂载当前项目页,内存/GPU 开销最低(对比方向 A 的 IndexedStack 全量保活)。
- **扩展性**:隔离强制在数据层,新增「按项目」的状态走同一套 registry/store 模式;契合仓库 service/repository 分层(见 `AGENTS.md` / `docs/CODE_QUALITY.md`)。
- **体验**:PTY 后台存活 + 重挂接 `TerminalView` 保留 scrollback 与滚动位置,保活体验与方向 A 等价。

### 数据流

```
HomeWorkspaceShell (从路由得到 activeProjectId)
   ├─ setActiveProject → ChatCubit          (聊天 tab 按 projectId 分桶)
   ├─ ensureGroup       → WorkspaceTerminalRegistry (PTY 会话按 projectId)
   └─ ensure            → WorkspaceToolsStore (右侧工具选中项按 projectId)
        ↓ 全部按 projectId 读取
HomeWorkspaceProjectPage(projectId) → ChatPage → WorkspaceShell
   ├─ 顶部 tab 行 ← chatCubit.tabsForProject(id)
   ├─ WorkspaceTerminalPanel ← registry.group(id)   // 重挂接 TerminalView,不丢 scrollback
   └─ RightToolsPanel        ← toolsStore.state(id)
```

## 组件设计

### ① ChatCubit 分桶(强制项)

`ChatCubit` 是全局单例,被所有项目页共用,因此**无论用哪种保活方式,tab 分桶都绕不开**。

- `ChatTabStore`(`client/lib/cubits/chat/chat_tab_store.dart`):扁平 `List<ChatTab>` → `Map<String projectId, ProjectTabBucket{ List<ChatTab> tabs; int activeIndex }>`。
- `ChatCubit` 新增 `String? activeProjectId` 与 `setActiveProject(String projectId)`。
- `ChatState.tabs` / `activeTabIndex` 改为对 `activeProjectId` 桶的**派生值**;因为渲染是「单 child = 当前项目页」,活动项目即被渲染页,消费方(WorkspaceShell tab 行)代码基本不变。
- `openSessionTab` 增加 `projectId` 入参;磁盘会话加载时按 `AppProject.sessionIds` 归桶。
- 复用并以分桶为主键重写已有的 `closeTabsForProject` / `openTabCountForProject` / `_tabIndicesForProject`。
- 副作用:根治个人项目(teamId 为空)互相泄漏 tab 的问题。

### ② WorkspaceTerminalRegistry(新 service)

- 位置:`client/lib/services/terminal/`(或 `services/workspace/`),在 `app_shell.dart` DI 注册并向下提供。
- 数据:`Map<String projectId, WorkspaceTerminalGroup{ List<TerminalSession> tabs; int activeIndex; String cwd }>`。
- 生命周期由 registry 拥有,**不再由 widget 拥有**。
- API(草案):`group(projectId)`、`ensureGroup(projectId, cwd)`、`disposeProject(projectId)`、`disposeAll()`。
- `WorkspaceTerminalPanel`(`client/lib/widgets/workspace_terminal_panel.dart`)变薄:
  - build 时按 projectId 向 registry 取/懒建 group,渲染 `TerminalView(group.active.terminal)`。
  - **移除 `dispose()` 中销毁会话的逻辑**(`tab.dispose()`),销毁改由 registry 在关闭项目 tab 时触发。
  - xterm 的 `Terminal` / `TerminalController` 为纯对象,重建 widget 时直接重挂接,保留缓冲与滚动位置。
- `workspace_shell_layout.dart` 中 ValueKey 由 `workspace-terminal-$cwd` 改为 `workspace-terminal-$projectId`;cwd 仍作为会话工作目录,但身份键为 projectId。

### ③ WorkspaceToolsStore(右侧工具内容,轻量 store)

- 新增 `WorkspaceToolsStore`(小 cubit 或 store):`Map<String projectId, RightToolsUiState{ int selectedToolIndex; ... }>`。
- 把 `TabbedPanel`(`client/lib/widgets/right_tools/tabbed_panel.dart`)的 `_selected` 本地状态外置为按 projectId 读写。
- 边界:**面板宽度/可见性仍由 `LayoutCubit` 全局管理**,本 store 只负责「选中哪个工具 / 内容选择」。

### ④ 活动项目接线

- `HomeWorkspaceShell` 已在 build 中计算 `activeId`(`_projectIdFromLocation`)。在 `initState` / `didUpdateWidget` 切换路由时,除现有 `_syncTeamSessionScope` 外,新增:
  - `chatCubit.setActiveProject(activeId)`
  - `terminalRegistry.ensureGroup(activeId, cwd)`(懒建)
  - `toolsStore.ensure(activeId)`

## 生命周期

| 事件 | 行为 |
|------|------|
| 首次访问项目 | 三处懒建对应 projectId 的运行时状态 |
| 切走项目 | **不销毁任何东西**(这就是保活) |
| 关闭项目 tab | 复用现有 `HomeWorkspaceShell._closeTab`(带运行中会话确认弹窗):销毁 chat 桶 + `registry.disposeProject(id)` + `toolsStore.remove(id)` |
| App 退出 | 全部销毁(`disposeAll`) |

保活仅在内存、仅在 tab 打开期间。

## 错误处理

- 未知 / 已关闭 projectId:registry 返回 `null` → 面板懒建空 group 或渲染占位。
- 终端会话崩溃:走现有 `TerminalSession` 错误路径,registry 保留槽位允许重启。
- 未知 projectId 的 chat 桶:懒初始化为空桶。

## 测试

- **ChatTabStore 分桶单测**:在 A/B 项目分别开 tab,断言互不串;切换 `activeProjectId` 不互相清空;`closeTabsForProject` 只清一个桶。
- **WorkspaceTerminalRegistry 单测**(注入假 transport / filesystem):`ensureGroup` 只建一次;切换返回同一实例;`disposeProject` 正确拆除并不影响其他项目。
- **WorkspaceToolsStore 单测**:每个 projectId 的选中项独立保留。
- **Widget 测**:切换项目 tab 后,终端内容 + 滚动位置、右侧工具选中项恢复;个人项目之间不再互相泄漏 chat tab。
- 完成前运行:`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`。

## 分层 / 规模合规

- 新 service 进 `services/`,store/cubit 进 `cubits/`;ChatTabStore 改动留在 `cubits/chat/`。
- UI 层不出现 `Process.run` 或裸路径;状态仅用 `flutter_bloc`。
- 注意保持 `home_workspace_shell.dart`、`chat_cubit.dart` 的文件规模(软上限:cubit ~500 行),必要时把分桶逻辑拆到 `cubits/chat/` 下的独立文件。

## 后续(YAGNI,本次不做)

- 跨 App 重启恢复终端 scrollback(需落盘缓冲)。
- 保活项目数量上限 / LRU 回收(当前由用户显式开/关项目 tab 控制,暂不需要)。
