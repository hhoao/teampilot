# ACP 思考过程折叠补齐确定性统计

## 背景

会话历史里连续的「推理 + 工具调用」被聚合成「思考过程」块
（`AiChainOfThoughtView`）。折叠头文案由 `chain_of_thought_view.dart:57-67` 决定：
先算 `summarizeThinkingProcess(parts)`，有活动则显示「编辑了 N 个文件，探索了 M 个文件，
X 次搜索，运行了 Y 条命令」及 `+增/-删`；否则回退到「思考过程 · N 步」。

PTY 会话能显示丰富的统计，因为 transcript 解析后经过
`annotateToolCallCategories`（`ai_history_loader.dart:1004-1010`）按 CLI 名称表标注
`AiToolCallPart.category`，`session_chat_message_area.dart:162-186` 又注入 CLI 专属
`fileResolver` / `editResolver`。

ACP 会话不走这条路：`AcpChatRuntimeCubit` 直接从 `session/update` 构造
`AiToolCallPart`（`acp_chat_runtime_cubit.dart:1188`、`:1204`），只带
`toolCallId/title/args/result/status`，`category` 留默认 `other`
（`ai_message_core/lib/src/message.dart:40`）；`seat.adoptExternalMessages()`
（`ai_history_seat.dart:941`）不做标注。ACP 协议本身不提供工具类别，只有展示用的
`title`（`acp_session.dart:106-139`），且多为「Run npm install」「Read」这类自由文本。

后果：`summarizeThinkingProcess` 按 `category` 计数，`other` 全部落空，
ACP 折叠头只剩回退的「思考过程 · N 步」。同时 `shouldFold` 也按 category 判定
（`session_chat_message_area.dart:257-259`），默认折叠集合不含 `other`
（`layout_preferences.dart:339-347`），所以 ACP 工具卡不进入折叠链，独立显示。

## 目标

- 让 ACP 会话的思考过程折叠头显示**确定性**统计：推理步数 + 本轮工具调用次数。
- 数字必须 100% 准确，不依赖任何猜测或启发式分类。
- PTY 会话行为完全不变；ACP 工具卡仍独立显示，不折进思考过程。

## 非目标

- 不标注 `AiToolCallPart.category`，不猜测工具类别。
- 不显示「编辑/探索了 N 个文件」「N 次搜索」「Y 条命令」「+/- 行数」——这些依赖
  category 与 resolver，ACP 侧无法可靠提供。
- 不改 `foldToolCallCategories`、不改 `summarizeThinkingProcess`、不碰任何 resolver。
- 不改 ACP 工具卡的渲染位置与折叠策略。
- 不为 ACP 增加设置项、不新增 `LayoutPreferences` 字段。

## 决策记录

- **口径选「方案 1（确定性统计）」**：ACP 没有稳定的工具 kind / `rawInput` schema，
  跨 agent（claude-acp / gemini / codebuddy / cursor / qoder / opencode / antigravity）
  的 `title` 格式不一致。给自由文本 title 套现有精确名表会产生系统性偏低的数字，
  用户会信任一个错数字，比不显示更糟。`+/-` 行数还依赖 `editResolver` 的
  `AiEditHunk`，ACP 基本拿不到；拿不到路径时 `summarizeThinkingProcess` 会退化成
  `'edit:${toolCallId}'`（`thinking_process_summary.dart:90-102`），即把「编辑调用次数」
  冒充「文件数」。
- **实现路径选 P1（共享包向后兼容可选扩展）**：新增字段/hook 均带默认值，只有 ACP
  宿主启用。P2（给 ACP 注册自定义 `AiPartRegistry.chainOfThoughtBuilder` 自建折叠组件）
  物理上不碰共享包，但要重写折叠交互与内部 part 渲染，重复
  `AiChainOfThoughtView` 逻辑，不值得。「零外溢」指 PTY 行为不变，P1 满足。
- **只在最后一个折叠链头附加工具数**：ACP 的 `shouldFold=false`，工具卡会把一条
  assistant 消息切成多个 CoT 链。工具调用数是消息级统计，若每个链头都挂会重复显示。
  其余链头保持「思考过程 · N 步」。
- **N 的含义**：链内 part 数。ACP 链内全是 `AiReasoningPart`（工具被排除），因此 N
  即推理块数。不重定 PTY 的口径（PTY 的 N 含链内工具 part），避免扩大范围。

## 架构与数据流

```
AiMessageParts.build()
  ├─ widget.parts（整条消息的全部 part）
  ├─ toolCallCount = parts.whereType<AiToolCallPart>().length
  ├─ groupMessageParts(parts, shouldFold) → nodes
  ├─ lastChainIndex = nodes 中最后一个 AiRenderChainOfThought 的下标（独立计算）
  └─ 逐个 node 构建：仅 i == lastChainIndex 传 toolCallCount，其余传 0
        ↓
AiChainOfThoughtView(parts, autoExpand, toolCallCount)
  └─ build(): summary 有活动 → 原 summary 文案（优先，保证 PTY 不变）
             否则 hook 非空 && toolCallCount > 0 → formatThinkingProcessStats(N, M)
             否则 → formatThinkingProcessSteps(N)（原逻辑）
```

`AiMessageStrings.formatThinkingProcessStats` 为 `null` 表示未启用。PTY 宿主与所有
现有宿主都不传该 hook，因此 phrase 计算路径逐字不变。

## 组件改动清单

### `client/packages/ai_message_ui/lib/src/strings.dart`

`AiMessageStrings` 新增可选字段：

```dart
final String Function(int steps, int toolCalls)? formatThinkingProcessStats;
```

字段可空、hook 存在时返回非空文案。构造函数中默认 `null`——`null` 即「不启用」，这是
PTY 行为不变的开关，不提供默认实现。类为 `@immutable`，新增 final 字段无需其他改动。

### `client/packages/ai_message_ui/lib/src/parts/chain_of_thought_view.dart`

- 新增 `final int toolCallCount`，构造默认 `0`。
- `build()` 中把 phrase 计算改为三段：
  1. `summary.hasActivity` → `strings.formatThinkingProcessSummary(summary)`（保持优先，
     这样将来 ACP 若标了 category 也不会被统计文案覆盖）；
  2. 否则 `stats != null && toolCallCount > 0` → `stats(widget.parts.length, toolCallCount)`；
  3. 否则 → `strings.formatThinkingProcessSteps(widget.parts.length)`。
- `semanticsLabel` 与 `showDiff` 逻辑不变（`phrase` 仍是唯一文案来源）。
- `didUpdateWidget` 不变：只在 `autoExpand` 变化时重置 `_open`，工具数变化不会重置
  用户手动的展开/收起状态。

### `client/packages/ai_message_ui/lib/src/ai_message_parts.dart`

- `build()` 中计算 `toolCallCount` 与 `lastChainIndex`。
  **不能复用 `_lastChainOfThoughtIndex`**：该函数第 90 行在
  `chainOfThoughtAutoExpand == false` 时直接返回 -1，与是否启用统计无关。新增独立
  的倒序查找 `AiRenderChainOfThought` 下标，不依赖任何偏好。
- `autoExpand`（供 `_buildNode` 用）仍由原 `_lastChainOfThoughtIndex` 决定，两者独立。
- `_buildNode` 增加 `toolCallCount` 参数；默认 CoT 构建器分支传给
  `AiChainOfThoughtView`。仅该分支生效——当前所有宿主使用
  `AiPartRegistry.defaults`（`ai_message_view.dart:22`），无自定义
  `chainOfThoughtBuilder`；若将来有宿主注册自定义 builder，本统计不作用于它，
  属可接受边界（不改变该宿主现有行为）。
- `_NodeKey` 新增 `final int toolCallCount` 并纳入 `operator ==` 与 `hashCode`。
  这是 Dart Map 的缓存键，不是 Flutter `Key`（`children.add(child)` 未传 key），
  因此计数变化会生成新的 widget 实例、Flutter 复用 State 并走 `didUpdateWidget`，
  `_open` 得以保留；同时保证流式新增工具调用时折叠头文案会刷新。

### `client/lib/l10n/app_en.arb` / `app_zh.arb`

新增一条文案，两个 `int` 占位符 `steps`、`toolCalls`：

- zh: `思考过程 · {steps} 步 · 本轮共 {toolCalls} 次工具调用`
- en: `Thinking process · {steps} steps · {toolCalls} tool calls this turn`

两个 ARB 都需配套 `@aiMessageThinkingProcessStats` 元数据，声明 `steps` 与 `toolCalls`
均为 `int`（参照 `@aiMessageThinkingProcessSteps` 的写法），否则生成器无法产出带类型
参数的方法。按 AGENTS.md 硬规则只编辑这两个 ARB；`app_localizations*.dart` 与
`app_localizations.dart` 由 l10n 生成器产出后一并提交。

### `client/lib/pages/chat/ai_message_strings_from_l10n.dart`

`aiMessageStringsFromL10n` 新增可选参数 `bool thinkingProcessToolCalls = false`。
为 `true` 时传入 `formatThinkingProcessStats`，文案走新增 l10n key；为 `false` 时不传
（保持 `null`）。

### `client/lib/pages/chat/session_chat_message_area.dart`

`:256` 构造 `AiMessageStrings` 时按会话类型启用：

```dart
strings: aiMessageStringsFromL10n(
  l10n,
  thinkingProcessToolCalls: isAcpChatSession(session),
),
```

`isAcpChatSession` 来自 `services/chat/session/chat_tab.dart:17`，按需补 import。
`session` 在该 widget 内已可用（`:132`）。

## 边界与错误处理

- **无 CoT 链**（纯文本 + 工具卡）：`lastChainIndex == -1`，所有节点 `toolCallCount = 0`，
  不显示统计。无文案、无空指针。
- **无工具调用**（`toolCallCount == 0`）：回退到原「思考过程 · N 步」。
- **一条消息多个 CoT 链**：仅最后一段附加，其余保持原样。
- **流式追加**：ACP 逐 chunk upsert，`toolCallCount` 递增触发 `_NodeKey` 变化 → 头部刷新；
  `autoExpand` 未变时不重置 `_open`。
- **hook 为 null**（PTY 及所有非 ACP 宿主）：完全跳过新分支，`phrase` 计算与改动前一致。
- **自定义 `chainOfThoughtBuilder`**：统计不生效，行为与现状一致。
- **历史 transcript 回放**：本设计不读写 `category`，`acp_chat_transcript_replay.dart`
  的 category 字段不受影响，无新旧数据一致性问题。
- **性能**：`whereType<AiToolCallPart>()` 与倒序查找都是 O(n)，`n` 为单条消息 part 数，
  每帧一次；不引入 resolver 调用，不增加 `summarizeThinkingProcess` 的开销。

## 与并行设计文档的共存

`docs/superpowers/specs/2026-11-06-cot-completed-reasoning-fold-design.md` 也修改
`chain_of_thought_view.dart`（`_buildInnerPart` 改带索引遍历、计算
`activeReasoningIndex`）与 `reasoning_part_view.dart`。

- 改动区域不重叠：本文改 `build()` 头部的 phrase 计算与构造字段；该文改 `build()` 中
  `if (_open)` 内部的循环与 `_buildInnerPart`。
- 两份文档都不改分组规则。该文声明「不改动摘要文案」，本文改的正是摘要文案——这是
  **有意的范围差异**，实现时以本文为准，不构成矛盾。
- 若两份实现并行落地，冲突集中在 `chain_of_thought_view.dart` 的 `build()` 开头与字段
  声明处，按先落地者 rebase 即可。建议顺序：先让该文的流式折叠改动落地，再叠加本文。
- 该文声明不改 `AiMessageParts`；本文改的是 `AiMessageParts` 内部实现（新增缓存键字段
  与参数传递），不新增公开接口，两者不冲突。

## 测试

`client/packages/ai_message_ui/test/chain_of_thought_view_test.dart`：

- `AiMessageStrings` 未提供 `formatThinkingProcessStats` 时，折叠头仍为
  `Thinking process · N steps`（回归，PTY 路径）。
- 提供 hook 且 `toolCallCount = 3` 时，显示 `stats(N, 3)` 文案。
- `toolCallCount = 0` 时回退到 steps 文案。
- `summary.hasActivity` 为真时仍优先显示 summary 文案（hook 不覆盖）。
- `toolCallCount` 变化时文案刷新，且用户手动点开的展开态保持。

`client/packages/ai_message_ui/test/ai_message_parts_test.dart`：

- 一条消息含两个 `AiRenderChainOfThought` 与若干工具 part 时，只有最后一段链头带
  工具数，其余为 steps 文案。
- 工具数变化触发头部重建（`_NodeKey` 覆盖 `toolCallCount`）。

app 层（新建 `client/test/pages/chat/ai_message_strings_from_l10n_test.dart`
或并入现有测试）：

- `thinkingProcessToolCalls: false` → `formatThinkingProcessStats == null`。
- `thinkingProcessToolCalls: true` → 非 null，且格式化结果包含 steps 与 toolCalls。

按 AGENTS.md 硬规则：禁止直接 `flutter test`，使用
`cd client && dart run tool/run_tests.dart <paths>`；内层 `flutter analyze` 快速验证，
收尾前执行一次完整套件（后台）。

## 验收标准

1. ACP 会话最后一个思考过程折叠头显示「思考过程 · N 步 · 本轮共 M 次工具调用」，
   N = 该链推理块数，M = 该消息 `AiToolCallPart` 总数，与界面上可见的工具卡数量一致。
2. PTY 会话折叠头文案、折叠行为、工具统计与改动前逐字一致。
3. ACP 工具卡位置与折叠状态不变。
4. `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` 无新增问题，
   `dart run tool/run_tests.dart` 全绿。

## 后续（不在本次范围）

若 ACP 侧能提供结构化的工具 kind 或稳定的 `rawInput` schema，可再评估「文件数 /
搜索 / 命令数 / +/- 行数」。届时必须保留保护：识别不出类别或路径时宁可回退到
「N 步」，也不要输出可能错误的文件数；且需重新评估
`foldToolCallCategories` 与 ACP 工具卡折叠位置的关系。
