# 设计:子 Agent 自动跟随预览(修复座位翻转 + 可配置自动打开)

日期:2026-08-14
状态:已评审待实现

## 背景与问题

### 现象

opencode 会话中出现 `task` 子 agent 时,聊天页面内容会"自动跳转"到子 agent 的对话:

- 聊天页内容变成子 agent 的会话,没有返回箭头,无法回到父会话;
- 与手动打开的子 agent 预览(带返回箭头、可逐层返回)行为不一致。

### 根因(已排查确认)

1. opencode 座位会话解析 `resolveOpencodeNativeSessionId`(native_session_id.dart:13)优先持久化的父会话 id,否则取 SQLite 中"最新的一行 session"(`opencodeNewestSessionId`,按 `time_updated DESC, id DESC` 取第一条)。
2. 会话**第一次启动时没有持久化 id**:`_persistNativeSessionId`(session_shell_connector.dart:581)拿到的 `nativeSessionIdToPersist` 是 PTY 启动**前**从空 store 探测的 → 为 null → 父 id 从未被捕获;只有第二次启动(resume)时才可能捕获。
3. `task` 子 agent 运行时,子会话就是"最新的一行"(其 part 持续写入)。当增量路径不可用(首次 seed 时 DB 尚未创建、schema 不兼容、cache 失效后重新 seed),全量解析路径(`locateOpencodeTranscript` → `_resolveSessionId` → 最新行)会把座位解析到子会话上,聊天页直接显示子 agent 的对话。

### 决策

- **修复根因**:座位/历史解析永不落到子会话(只解析根会话)——无条件修复,不涉及配置。
- **新增全局配置(默认关)**:"自动打开子会话预览"——子 agent 出现时自动弹出预览覆盖层并实时跟随;用户按返回后停止跟随(会话级)。
- 作用域:全局 `LayoutPreferences`(与 `chatUserMessageMode` 等 chat 偏好同级)。

## Section 1:根因修复(无条件)

### 问题定位

`opencodeNewestSessionId`(native_session_id.dart:103)取最新一行,运行中的 task 子会话就是最新行。

### 修复

`opencodeNewestSessionId` 改为**只解析根会话**:

- 当前 SQLite 布局:`parent_id` 为空或 `parent_id IS NULL`(仅这一列的过滤在 SQL 内完成);
- legacy 布局(parent 关联在 `data` JSON 内,无 `parent_id` 列):`SqliteException` → fallback 全表扫描 + Dart 侧过滤(借鉴 `_discoverChildQuery` 已有的 try/catch + `_parentOf(obj)` 模式)。

### 影响面

`resolveOpencodeNativeSessionId` 只有两个调用方,两者都想要"根会话",语义一致:

- 座位历史解析(`ai_transcript.dart:_resolveSessionId`);
- resume 探测(`opencode_resume_strategy.dart:detectNativeId`)。

修复同时解决 resume 时误捕获子会话 id、把子会话当主会话续跑的问题。

## Section 2:自动跟随的状态模型(`SubagentPreviewController` 扩展)

跟随语义全部放进 `SubagentPreviewController`(纯状态,可单测,不依赖 widget):

```
新增字段:
  bool follow = false          // 本会话是否处于自动跟随模式
  String? followUntilId        // 已跟随/已忽略的 toolCallId(返回后置位,阻止再次自动弹)
```

新增方法:

- `maybeAutoFollow({required bool prefEnabled, required List<String> runningIds, required Set<String> availableIds})`
  - 条件:`prefEnabled && follow && availableIds ⊇ runningIds` 中某 id;
  - 行为:对 `runningIds` 中"新出现"的 id(`!= followUntilId` 且未在 stack 中)push 该 id;
  - 多个 running 时跟随最新出现的:**调用方按消息时间从新到旧传入 `runningIds`(List 而非 Set),controller 取第一个未处理的 id**。
- `stopFollowOnBack()` — `pop()` 时同步:`follow = false`;记录 `followUntilId = 被弹出的 id`。
- `resetFollow()` — `follow = false; followUntilId = null`(会话切换时调用)。

规则汇总:

| 场景 | 行为 |
|------|------|
| 开关开启,子 agent 出现 | 自动打开预览,实时跟随(现有 side-transcript re-inflate 已支持) |
| 子 agent 结束 | 预览保持打开,不自动收起 |
| 之后又出现新 running 子 agent(未按返回) | 继续跟随最新的 |
| 用户按返回 | 回到父会话,本会话停止自动跟随;`followUntilId` 阻止同一子 agent 再次自动弹 |
| 嵌套子 agent(预览内再点进去) | 不自动跟随,仅顶层自动弹 |
| 开关中途关闭 | 不再自动弹;已打开的预览保留,可手动返回 |

## Section 3:接线

### 3a. 偏好字段

`client/lib/models/layout_preferences.dart`:

- 新增 `bool autoOpenSubagentPreview = false`(默认关);
- JSON 序列化 key:`autoOpenSubagentPreview`(`toJson`/`fromJson`/`copyWith` 三处同步)。
- `LayoutCubit` 新增 setter `setAutoOpenSubagentPreview(bool)`,与 `setChatUserMessageMode`(layout_cubit.dart:375)同款 `_save(copyWith(...))` 模式。

### 3b. 配置页 UI

`client/lib/pages/config/layout_appearance_in_layout_section.dart` 的 chat 偏好区(与 `chatUserMessageMode` 同组)新增开关行:

- 标题:"自动打开子会话预览"
- 描述:"子 agent 运行时自动弹出预览并实时跟随;按返回后停止跟随。"
- 组件:与同区其他开关一致的 `TpSwitch` 系组件;
- 读写:`context.select<LayoutCubit, ...>(...)` 读取 + `context.read<LayoutCubit>().setAutoOpenSubagentPreview(...)`。
- l10n:仅编辑 `client/lib/l10n/app_en.arb` 与 `app_zh.arb`。

### 3c. 触发点

`client/lib/pages/chat/session_chat_view.dart` 现有 `ListenableBuilder(listenable: _subagentPreview)` 的 builder(1124 行 `pruneToAvailable` 旁)追加:

```dart
_subagentPreview.maybeAutoFollow(
  prefEnabled: prefs.autoOpenSubagentPreview,
  availableIds: historySeat.subagentAttachments.keys.toSet(),
  runningIds: <running 子 agent 的 toolCallId>,
);
```

`runningIds` 来源:**从 seat 消息的 `AiToolCallPart` 推断**——`historySeat.loadedMessages` 中属于 `cap.subagentToolNames`(`task`)且 `status == AiToolCallStatus.incomplete` 的 `toolCallId` 列表,**按消息 `createdAt` 从新到旧排序**传入(controller 取第一个未处理的即"最新出现的 running 子 agent")。与附件 map 的 key 同源(均由 `SubagentAttachmentInflater` 以 `part.toolCallId` 为 key),准确可靠。

builder 在 epoch/stack 变化时重建,running 状态变化会 bump `subagentAttachmentEpoch`,触发时机足够。

### 3d. 会话切换重置

`didUpdateWidget` 中现有 `_subagentPreview.clear()`(session_chat_view.dart:249)处追加 `_subagentPreview.resetFollow()`。

## Section 4:测试

| 层 | 测试文件 | 覆盖 |
|---|---|---|
| controller | `client/test/pages/chat/subagent_preview_controller_test.dart` | follow 状态机:自动 push 新 running id / 已处理 id 不重复 push / 返回后停止跟随且 followUntilId 阻止再次自动弹 / 多 running 跟随最新 / resetFollow |
| 根因修复 | `client/test/services/cli/registry/capabilities/history/opencode_sqlite_worker_pool_test.dart` | `opencodeNewestSessionId` 含子会话(parent_id 非空)时仍返回根会话;legacy data-JSON 布局同样过滤子会话 |
| 回归 | `client/test/services/cli/registry/capabilities/history/opencode_side_resolver_test.dart`(或 loader 测试) | 全量解析路径在子会话最新时仍解析到根会话,座位不翻转 |
| 接线(可选) | widget 测试 | pref 开启时新 running 子 agent 自动出现预览;点返回后不再自动弹 |

## 不做的事(YAGNI)

- 不做"自动跳转到子会话页"的配置(会话视图切到子会话)。
- 不做 per-session / per-workspace 作用域。
- 不做预览内独立"跟随"开关。
- 不自动收起已结束子 agent 的预览。
