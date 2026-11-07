# 定时任务启动新会话的标题

## 背景

定时任务的 `launchPrompt` 动作会创建新 Session（`AutomationDispatcher._createSessionForLaunchPrompt`），
但创建请求不带标题，首条消息通过 ACP `sendPrompt` 或 PTY `directToPty: true` 直接注入：

- 两条路径都不经过键盘输入的 `FirstUserLineCapture`，因此不会触发
  `SessionPromptMetadataSync.autoRenameOnFirstPrompt`。
- 手动 landing / 历史会话继续等路径会显式调用 `applyFirstPromptTitle`
  （`workspace_session_actions.dart`、`session_history_review_submit.dart`），
  定时任务的 dispatcher 没有这一步。

结果：

- 个人 Session 的 `display` 为空，列表显示兜底文案。
- 团队 Session 会拿到 `SessionCreateRequest.emptyDisplayTitleFallback` 的默认值
  `'New Chat'`，被 `SessionLaunchCoordinator` 写入 `display`，且因为非空而
  永远不会再被自动重命名。

## 目标

- `launchPrompt` 自动化新增可选的自定义会话标题。
- 未设置（空字符串/null）时，自动用定时任务的 `name` 命名新 Session。
- 只命名 **没有标题** 的 Session：用户手动改过的名字、或复用 Session 已有标题，
  不会被覆盖。
- 个人 / 团队、ACP / PTY、新建 / 复用首次创建都生效。

## 非目标

- 不改 `scheduledMessage`（发给已有会话）与 `runCommand`（无会话）的语义。
- 不新增"定时任务按消息内容自动命名"的选项；自动命名固定使用任务 `name`。
- 不暴露到 agent catalog 的 `create_automation` / `update_automation` 参数
  （`toJson` 中可见即可；未设置时行为与"留空"一致）。
- 不改 `AutomationRun` 模型与持久化格式。

## 行为

### 1. 编辑器

`AutomationEditorDialog` / `AutomationEditorFormBody`：

- 仅 `AutomationEditorKind.launchPrompt` 渲染可选字段「会话标题」，
  位于 Message 字段之后。
- 字段 id 为 `sessionTitle`，初始值取 `initial.sessionTitle`，无必填校验。
- 说明文案：留空则使用定时任务名称。
- 保存时 `sessionTitle` 取 `trim()`；空串存为 null；非 launchPrompt 一律 null。

### 2. 数据模型

`Automation` 新增 `String? sessionTitle`：

- `fromJson` 读取 `sessionTitle`。
- `toJson` 仅在 `isLaunchPrompt` 且非空时写入。
- `copyWith` 增加 `sessionTitle` 与 `clearSessionTitle`。
- 纳入 `==` / `hashCode`。

### 3. 调度

`AutomationDispatcher`：

- 解析 `resolvedTitle`：
  - `sessionTitle.trim()` 非空 → 用它；
  - 否则用 `name.trim()`（`name` 必填，结果保证非空）。
- 个人与团队两条 `SessionCreateRequest` 分支都传
  `emptyDisplayTitleFallback: resolvedTitle`：
  - 团队 Session 创建时即写入 `display`，Tab 立刻有标题；
  - 个人 Session 的 fallback 仅用于 Tab 显示，持久化由下一步完成。
- Session 解析成功后，若 `automation.isLaunchPrompt`，调用新增注入回调
  `applySessionTitle(sessionId, resolvedTitle)`：
  - best-effort：异常只记 `appLogger.w`，不影响 run 结果；
  - 在消息投放前执行，标题在首条消息期间就可见。
- 新增构造参数：
  `Future<void> Function(String sessionId, String title)? applySessionTitle`。
- 在 `app_shell.dart` 注入 `chatCubit.applySessionTitle`。

### 4. 重命名通道

`SessionPromptMetadataSync` 新增：

```dart
Future<void> applySessionTitle(String sessionId, String title);
```

语义：

- `local-` 前缀 Session、无 `sessionRepository`、host 已关闭时直接返回。
- 标题 `trim()` 后为空则返回。
- 在 host 状态中找不到 Session 则返回。
- `session.display.trim()` 非空则返回（保护手动改名与已有标题）。
- 否则调用 `_host.renameSession(repo, sessionId, title)`。

`applyFirstPromptTitle` 改为：派生标题后复用 `applySessionTitle`，
保留 `teamGeneration` 的自动命名守卫。

`SessionLaunchService` / `ChatCubit` 各加一层透传方法。

## 边界与失败处理

- 自定义标题留空 → 用 `name`，不会出现无标题的新 Session。
- 复用已绑定且已有标题的 Session → 不重命名。
- 复用已绑定但标题为空的历史 Session → 补上标题（首次解析时）。
- 团队 Session 创建时已写入标题 → 后续 `applySessionTitle` 因 display 非空而 no-op。
- 重命名失败（IO/状态竞争）→ 仅告警日志，run 继续并保持原标题。
- Session 创建返回非 `opened` → 不调用重命名。

## 测试

- `client/test/models/automation_test.dart`：`sessionTitle` JSON round-trip、
  `copyWith` / `clearSessionTitle`、非 launchPrompt 不持久化。
- `client/test/services/chat/launch/session_prompt_metadata_sync_test.dart`：
  - 无标题才重命名；
  - 已有标题跳过；
  - 空标题跳过；
  - 未知 Session 跳过。
- `client/test/services/automation/automation_dispatcher_test.dart`：
  - 自定义标题优先；
  - 留空使用 `name`；
  - 创建请求收到正确的 `emptyDisplayTitleFallback`；
  - `scheduledMessage` 不触发重命名；
  - 重命名抛错不影响 run 成功。
- 编辑器 widget 测试（若现有 harness 成本可控）：
  - launchPrompt 显示字段、scheduledMessage 不显示；
  - 保存值写入 `sessionTitle`。

## 验证

- `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
- `cd client && dart run tool/run_tests.dart <改动涉及的测试文件>`
- 收尾前跑一次完整 `dart run tool/run_tests.dart`（后台）。
