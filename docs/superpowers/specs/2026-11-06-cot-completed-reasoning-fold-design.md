# 流式输出期间折叠已完成的推理块

## 背景

会话历史里连续的「推理 + 工具调用」被聚合成「思考过程」块
（`AiChainOfThoughtView`，标题形如「思考过程 · N 步」）。当前自动展开机制见
`docs/superpowers/specs/2026-10-15-cot-tip-auto-expand-design.md`，其中 2026-10-26 的
追加调整已经实现：回合结束 / 正文开始 / 冷开历史时，外层思考链与内层推理一起收回摘要行。

剩余问题在**流式输出进行中**：当最新一条消息处于 `liveThinkingTail` 时，
`AiChainOfThoughtView._buildInnerPart` 对链内**每一个** `AiReasoningPart` 都传
`initiallyExpanded: widget.autoExpand || aiTheme.cotExpandReasoningOnOpen` 与
`autoFollow: widget.autoExpand`（`chain_of_thought_view.dart:155`）。自动展开期间两者恒为
true，于是这段链里所有已输出完的推理块全部摊开。每个推理体是最高 256px 的内部滚动区
（`reasoning_part_view.dart:177`），10 块就是 2500px 以上；且多个内层
`SingleChildScrollView` 会吞掉滚轮事件，导致外层会话列表难以滚动。

流式数据按 `(mid, index)` 顺序 append：`acp_chat_transcript_replay.dart:144` 对
reasoning 做 `previous.text + append`，新 part 只会出现在更大的 index。因此「链内最后一个
推理块」天然就是当前正在输出的那一块，无需额外的增量追踪。

## 目标

- 流式输出期间，只展开**当前正在输出的那一块推理**；已经输出完成的推理块折成一行
  「Reasoning」标题（沿用现有折叠态，点击可回看）。
- 把展开内容高度从「N 块 × 256px」降到「1 块 × 256px + N 行标题」，解决滚动困难。
- 不改变回合结束 / 正文开始 / 冷开历史时的收起行为，不改变工具调用行的折叠行为。

## 非目标

- 不新增设置项，不改 host 层（`AiMessageView` / `AiMessageParts` /
  `SessionHistoryThread`）接口。
- 不改动「思考过程」块的分组规则与摘要文案。
- 不处理已完成推理块的可见性隐藏或汇总成单行。

## 行为

1. **活跃块判定**：仅当 `AiChainOfThoughtView.autoExpand == true` 且
   `parts.last is AiReasoningPart` 时，活跃索引为 `parts.length - 1`；否则为 `-1`。
   链尾是工具调用（AI 正在执行工具、暂时没有推理输出）时活跃索引为 -1，所有推理块折叠。
2. **渲染**：内部带索引遍历 `parts`。对 `AiReasoningPart`：
   - `initiallyExpanded = isActive || (!autoExpand && cotExpandReasoningOnOpen)`
   - `autoFollow = isActive`
   对 `AiToolCallPart` 保持不变（`initiallyExpanded: cotExpandToolsOnOpen`）。
3. **状态迁移**（`AiReasoningPartView.didUpdateWidget`）：
   - `autoFollow` false→true：`_open = true`、`_stickToBottom = true`、调度滚到底部。
   - `autoFollow` true→false：沿用现有折回逻辑（`_open = false`、`_stickToBottom = true`）。
   - `autoFollow` 不变：不介入，保留「手动点开优先」。
4. **典型序列**：第一块推理输出时展开；第二块开始输出时第一块折回、第二块展开；工具
   执行期间全部折起；工具结束后第三块推理展开；回合结束或正文开始时全部收起。
5. **手动优先**：用户手动点开的已完成块，其 `autoFollow` 始终为 false，新块到来时两个
   迁移分支都不触发，因此保持展开；用户手动折叠的活跃块在 `autoFollow` 不变期间也保持
   折叠。

## `cotExpandReasoningOnOpen` 的行为变更

「打开时展开推理」在**流式自动展开期间不再生效**，仍只作用于用户手动点开「思考过程」
块时的全展开。理由：该设置文案（「展开『思考过程』时，自动展开内部推理步骤」）描述的是
手动展开动作，而 live 期间全展开正是滚动问题的根源；且该设置默认关闭，多数用户无感。

公式 `initiallyExpanded = isActive || (!autoExpand && cotExpandReasoningOnOpen)` 在
`autoExpand == false` 时退化为原来的 `cotExpandReasoningOnOpen`，因此手动展开路径的行为
完全不变。

## 实现

- `client/packages/ai_message_ui/lib/src/parts/chain_of_thought_view.dart`
  - `_buildInnerPart` 改为接收索引；build 时计算 `activeReasoningIndex`。
  - 内部循环 `for (final part in widget.parts)` 改为带索引遍历。
  - 按上述公式传 `initiallyExpanded` / `autoFollow`。
  - 更新 `autoExpand` 字段的文档注释：说明自动展开期间只展开最后一块活跃推理。
- `client/packages/ai_message_ui/lib/src/parts/reasoning_part_view.dart`
  - `didUpdateWidget` 增加 `autoFollow` false→true 时展开并调度滚动的分支。
  - 更新 `autoFollow` 的文档注释：语义从「流式跟随」扩展为「当前活跃展开目标」。
- 不改 `AiMessageView`、`AiMessageParts`、`AiThread`、`SessionHistoryThread`、
  `LayoutPreferences`、l10n ARB。

依赖 existing 机制：外层 `AiChainOfThoughtView.didUpdateWidget`（`autoExpand` 变化时开合）、
`AiMessageParts._NodeKey` 的 part 实例缓存（parts 变化时重建 chain widget 但复用其 State）、
`AiReasoningPartView` 的 `ScrollMetricsNotification` 底部跟随。

## 边界

- **part 实例变化**：append 会让最后一个 part 变成新实例，`_NodeKey` 判定整段 chain 变化，
  chain widget 重建但 State 复用；内部 children 按位置复用 State，最后一个
  `AiReasoningPartView` 只更新 `part.text`，滚动位置与手动状态不丢失。
- **新增 part**：追加到末尾，前面位置稳定，新增的 State 按 `initiallyExpanded` 展开。
- **手动折叠外层链**：`autoExpand` 不变时 `_open` 保持 false；用户再点开时 children 重新
  inflate，按当前活跃索引只展开活跃块。
- **链尾为 tool call 后新增 reasoning**：工具行保持默认折叠，新推理块成为活跃块并展开。
- **`cotExpandLatestOnOpen` 关闭**：`chainOfThoughtAutoExpand` 为 false，整段不自动展开，
  行为与现状一致。
- **多段思考链**：`AiMessageParts._lastChainOfThoughtIndex` 仍只对最后一段传
  `autoExpand = true`，其余段保持折叠。

## 测试

`client/packages/ai_message_ui/test/chain_of_thought_view_test.dart`：
- live 链（`autoExpand: true`）含多个 `AiReasoningPart` 时，只有最后一块正文可见，前面的
  呈现为「Reasoning」标题行。
- 追加一块 reasoning 后，前一块折回标题行、新块展开。
- 链尾为 `AiToolCallPart` 时，所有 reasoning 折叠。
- 手动点开的已完成块，在追加新块后保持展开。
- live 结束（`autoExpand` true→false）时全部折回（多块场景，补强现有
  `reasoning body folds when streaming stops` 单块测试）。
- `autoExpand == false` 且 `cotExpandReasoningOnOpen == true` 时，手动展开仍展开所有推理
  （回归现有 `theme cotExpand*OnOpen auto-expands nested kinds`）。

`client/test/pages/chat/session_history_thread_test.dart`：
- 集成层回归：live tip 多块推理时，已完成块的正文不可见、活跃块正文可见；回合结束后
  全部收起为「Thinking process」摘要行。

## 不做的事

- 不引入「已完成 N 步推理」汇总行，也不隐藏已完成推理块。
- 不新增 `LayoutPreferences` 字段或设置 UI 行。
- 不改工具调用详情的默认折叠策略。
- 不改 l10n 文案（复用现有 `Reasoning` / `Thinking process` 字符串）。

## 决策记录

- 折叠时机：流式输出**进行中**（非回合结束后；后者的收起逻辑已存在）。
- 折叠形态：每个已完成块折成一行「Reasoning」标题，可点开回看。
- 工具执行期间：不留任何展开的推理块。
- 实现方案：chain 内计算活跃索引 + 复用 `autoFollow` 状态机（未采用 host 逐层下传，
  也未采用 `ValueKey` 强制重建）。
