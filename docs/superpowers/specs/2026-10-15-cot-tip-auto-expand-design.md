# 最新消息的思考过程自动展开

## 背景

聊天记录里聚合「推理 + 工具调用」的思维链块（`AiChainOfThoughtView`，标题形如
「思考过程 · N 步」）默认折叠。它本就有自动展开机制，但条件过窄：

```dart
// session_history_thread.dart
chainOfThoughtAutoExpand: ai.id == realTipId && aiMessageIsThinkingOnly(ai),
```

`aiMessageIsThinkingOnly` 要求整条消息**只由 `AiReasoningPart` 组成**。而工具调用也属于
思维链块（见 `part_grouping.dart`），所以一个回合只要发生任意工具调用，条件立即为 false，
思考过程在整个回合里始终折叠。这正是"思考过程总是折叠"的原因。

## 目标

- 当某条消息是对话中的**最新一条**（`ai.id == realTipId`）时，其中的思考过程块默认展开。
- 不再要求"整条消息只含推理"。
- 展开的是外层「思考过程」外壳（可看到内部的推理行 / 工具行）；内部单条推理、工具详情的
  展开与否仍由设置项 `cotExpandReasoningOnOpen` / `cotExpandToolsOnOpen` 及手动点击决定
  （自动展开的外层沿用现有语义，会一并展开内部推理文本）。
- 一个消息里出现**多个**思考过程块（正文把推理/工具隔开）时，**只展开最后一个**。

## 行为

1. 触发：消息为最新一条且含 `AiRenderChainOfThought` 节点 → 展开最后一个该节点。
2. 保持：流式过程中、以及回合完成后，只要它还是最新一条，就一直保持展开。
3. 收起：有更新的消息成为最新（新回合 / 用户消息 / Running 占位插入）后，原节点因
   `autoExpand` 变为 false 自动折叠（沿用 `AiChainOfThoughtView.didUpdateWidget`）。
4. 手动优先：用户手动点开/收起后，在该消息内容继续增长期间不会被强行覆盖。

## 实现

- `packages/ai_message_ui/lib/src/ai_message_parts.dart`：把 `chainOfThoughtAutoExpand`
  只传给**最后一个** `AiRenderChainOfThought` 节点，其余 `AiChainOfThoughtView` 保持
  `autoExpand: false`。
- `lib/pages/chat/session_history_thread.dart`：条件简化为 `ai.id == realTipId`。
- `packages/ai_message_ui/lib/src/ai_thread.dart`：默认 `messageBuilder` 同步放宽为 `isLast`。
- 相关 doc 注释同步更新（`AiMessageView` / `AiMessageParts` / `AiChainOfThoughtView`）；
  `aiMessageIsThinkingOnly` 不再是该机制的判据。

## 设置开关（后续追加）

该行为做成用户可关闭的设置项：

- `LayoutPreferences.cotExpandLatestOnOpen`（默认 `true`）；设置 UI 在「布局外观 → 思考过程」区顶部新增一行
  `cotExpandLatestOnOpenTitle/Description`。
- 传递路径：`session_chat_view.dart` 选择该 pref → `PinnedSessionHistoryColumnWidth.expandLatest` →
  `AiMessageTheme.cotExpandLatestOnOpen`。
- `session_history_thread.dart`：`chainOfThoughtAutoExpand: ai.id == realTipId && aiTheme.cotExpandLatestOnOpen`。
- 关闭后，最新消息的思考过程恢复默认折叠；内部推理/工具展开仍由既有两项 pref 控制。

## 测试

- 最新消息含「推理 + 工具调用」时，思考过程块展开（回归点）。
- 非最新消息保持折叠。
- 一条消息含两个思考过程块时，只有最后一个展开。
- `AiThread` 默认构建器只展开最新消息。
