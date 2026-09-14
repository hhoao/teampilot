# 历史冷加载：热标签门控 + 文档优先

- 日期：2026-09-14
- 状态：设计待审
- 目标：桌面启动时只冷加载「前台可见 tab + 正在运行的 session」，其余已打开 tab 延后到激活；冷加载前保证会话文档就绪，消除用默认 `claude` stub 先全量解析一次、文档就绪后再解析一次的双加载。
- 前作：[session 列表索引](2026-09-12-session-list-index-design.md)（该文非目标里写的「第二刀」）。

## 背景

桌面端启动日志（同一 `sessionId` 出现两轮解析）：

- `16:23:55` 第一轮：`[ai-history-full] full parse triggered cli=claude ... tokenNull=true`，随后 `seat cold-load ... msgs=0 complete=true`。此轮会话文档尚未 hydrate，`SessionMemberCliResolver` 对 personal session 走 `persistedSession?.cli ?? CliTool.claude`，CLI 回退 `claude`，找不到该 session 真实（cursor/opencode/codex）transcript，白解析一遍。
- `16:23:56`：`loadSessionListForWorkspace ... 176 sessions`（只是侧栏列表行，不解析 transcript）。
- `16:23:57`–`16:24:17` 第二轮：文档就绪后用真实 CLI `page-first hit` 再解析一次，`msgs=51/62/134/...`。

根因有两条：

1. **挂载即加载。** `SessionChatView.initState` 无条件调用 `_loadHistoryThenHydratePersistedPendingUsers()`（`session_chat_view.dart:266`）。启动时 `WorkbenchLayoutPersistence.restoreForWorkspace` 恢复上次打开的 session tab（`workbench_layout_persistence.dart:109`），每个 tab 的 `SessionChatView` 都会冷加载，且日志显示都是 `routeActive=false running=false`——不在前台也照跑全量 parse。
2. **文档未就绪就加载。** 恢复流程先注册 tab、再异步 `_hydrateRestoredSessionTabs`（`:191`）。`SessionChatView` 在 hydrate 完成前挂载，读到的是列表行 stub（无真实 CLI），于是先用 `claude` 白解析一次。

约束：live refresh 的 `_requestReload` 调 `seat.softReload()`（`ai_history_live_refresh_controller.dart:249`），而 `softReload` 对**冷** seat 是 no-op（`ai_history_seat.dart`）。所以「运行中的 offstage session」仍需先有一次加载，否则 live refresh 挂上也不会产出内容。

## 目标与非目标

### 目标

1. 冷 seat 只在 **hot**（`routeActive || isMemberRunning`）时才加载；非 hot 的挂载/重建一律不触发 `load` / 全量 parse。
2. hot 转变（tab 激活、session 开始运行）时补触发加载，不依赖「挂载时一次性加载」。
3. 任何冷加载都必须拿到**完整会话文档**（真实 CLI）后再解析；绝不对 stub 用默认 `claude` 解析。
4. 并发触发（initState、didUpdateWidget、busy 翻转在同一异步窗口）合并为一次冷加载。
5. 运行中的 offstage session 行为不变：照样加载 + live refresh，切过去时 transcript 是最新的。

### 非目标

- 不改 `WorkbenchLayoutPersistence` 的恢复/文档 hydrate 流程，不推迟 tab strip 渲染。
- 不改 loader / seat 契约，不改 `isHistorySeatHot` 等谓词语义。
- 不改侧栏列表加载（`loadSessionListForWorkspace`）。
- 不做「从磁盘发现 CLI」的 loader 级改造（team member 绑定语义以 session.json 为准）。

## 设计

全部编排改动在 `SessionChatView`（`routeActive` 与 running 是视图概念）。谓词复用 `isHistorySeatHot`（`history_seat_key.dart:21`）。

### 1. `ChatCubit.hydrateSessionDocument` 单飞

`hydrateSessionDocument(workspaceId, sessionId)`（`chat_cubit.dart:1821`）在文档缺失时会 `repo.loadSession`。恢复流程与视图 on-demand hydrate 会并发调用同一 session，改为单飞：以 sessionId 为键缓存 in-flight future，完成后移除；已是文档则仍走内存快路径。避免同一 `session.json` 读两次。

不新增公开方法，不改变返回值契约。

### 2. `_loadHistory` 热标签门控（延迟非热 tab）

`_loadHistory({bool force})` 拆为「单飞壳 + 实现」：

- 壳：`force` 直通实现（用户主动重试不被合并/丢弃）；非 force 单飞，缓存 `_loadHistoryInFlight`，完成后清理（与既有 `_startLiveRefresh` 单飞 `session_chat_view.dart:640` 同模式）。
- 实现：
  1. `running = chat.isMemberRunning(sessionId, _shellMemberId)`；`hot = isHistorySeatHot(routeActive: widget.routeActive, isMemberRunning: running)`。
  2. `!hot && !force`：`AppLogger.d('[history-defer] ...')`，`await _liveRefresh?.stop()`，直接 return。**不碰 seat**（不冷加载）。
  3. 判定 `ready = seat.state.status == AiHistoryViewStatus.ready && seat.state.sessionId == widget.session.sessionId && seat.state.memberId == widget.selectedMemberId`。
  4. 若 `!ready && !chat.sessionHasDocument(sessionId)`：`await chat.hydrateSessionDocument(session.workspaceId, sessionId)`；成功则用返回文档替换本次 load 的 `session`（真实 CLI）。仅对冷加载做此步，ready 时不读盘。
  5. 沿用现状：`force` 走 `seat.load(force: true)`；否则 `seat.softReloadOrLoad(...)`。尾部 `_maybeStartLiveRefreshForRunningPty()` / `_syncAwaitingFromWorkingSessions` / awaiting 时 `_startLiveRefresh` 保持。

要点：`softReloadOrLoad` 对非 ready seat 自动走冷加载，因此延迟后的首次激活是**单次**冷加载，不会重复。

### 3. 热转变补触发

新增私有 `_refreshWhenHot()`，作为「运行/可见性可能变化」后的统一入口：

```
running = chat.isMemberRunning(...)
hot = isHistorySeatHot(routeActive: widget.routeActive, isMemberRunning: running)
if (!hot) { await _liveRefresh?.stop(); return; }
if (!ready) { await _loadHistoryThenHydratePersistedPendingUsers(); return; }  // ready 同 §2 第 3 步
_maybeStartLiveRefreshForRunningPty();
```

调用点替换/新增：

- `didUpdateWidget` 的 `routeActive` 变化分支（`:337`）：`_maybeStartLiveRefreshForRunningPty()` → `unawaited(_refreshWhenHot())`。
- `isSessionBusy` 变化的 `BlocListener`（`:1307`）：在现有 `_syncAwaitingFromWorkingSessions` 等之外，用 `unawaited(_refreshWhenHot())` 替换裸的 `_maybeStartLiveRefreshForRunningPty()`。

`initState` 仍调 `_loadHistoryThenHydratePersistedPendingUsers()`——内部由 `_loadHistory` 门控决定是否延迟。

`_maybeStartLiveRefreshForRunningPty` 本身的热判定与 stop 语义保持不变；live refresh 对冷 seat 的 no-op 问题由「hot 时先 load」消除。

### 4. 现有语义保持

- 已加载 seat 回到非 hot：停 live refresh，seat 保持 warm（ready），再次激活只 `softReload`（廉价 page-first），不冷加载。
- `force`（find bar 重试 `:1484`）：绕过热门控，但同样享受文档优先（冷 seat 先 hydrate）。
- 状态机：`deferred`（冷、无 live refresh）→ `hot`（冷加载一次 + live refresh）→ `non-hot`（停 live refresh，warm）→ 激活（softReload + live refresh）。

## 边界情况

| 情况 | 行为 |
|---|---|
| 恢复的 offstage tab 且未运行 | 挂载不加载；激活或转运行时加载 |
| 前台 tab 且文档未 hydrate | hot → 先 hydrate 文档 → 单次真实 CLI 解析 |
| session 无 `session.json`（`hydrate` 返回 null） | 回退 `widget.session`，行为同现状 |
| 运行中的 offstage session | hot（running）→ 正常加载 + live refresh |
| 非 hot 时 `force` 重试 | 绕过热门控加载 |
| `_seat` 未绑定 / 已 unmount | 维持现有 return 保护 |
| 并发触发（挂载 + 激活 + busy 翻转） | `_loadHistory` 单飞合并 |

## 测试要点

`cd client && dart run tool/run_tests.dart <paths>`；沿用 `session_chat_view_draft_cache_test.dart` 的 mock seat harness。

- 冷 mount 且 `routeActive=false running=false`：`softReloadOrLoad` / `load` **不被**调用。
- `routeActive` false→true（`didUpdateWidget`）：调用一次加载。
- running 翻转（busy BlocListener，冷 seat）：调用一次加载。
- 文档优先：`sessionHasDocument=false` 时先调 `hydrateSessionDocument`，`softReloadOrLoad` 收到的 session 是 hydrate 后文档（CLI ≠ 默认 `claude` stub）。
- 已 ready 的 hot mount：走 `softReloadOrLoad`，不再 `hydrateSessionDocument`。
- `ChatCubit.hydrateSessionDocument` 单飞：并发两次 → `repo.loadSession` 只调一次。
- 更新 `session_chat_view_draft_cache_test.dart`：其 `routeActive:false` 的挂载会因门控不再加载；草稿恢复与加载无关，按新语义调整断言 / 参数。

## 文档更新

- 本设计即「第二刀」的收口文档（`docs/ARCHITECTURE.md` 在本仓库不存在，AGENTS.md 的引用为历史遗留，不新增/修改）。
- `docs/superpowers/specs/2026-09-12-session-list-index-design.md` 未覆盖的「第二刀」由此设计承接，其正文无需改动。
