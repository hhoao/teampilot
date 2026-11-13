# Session 打开卡顿：turn 内分块渲染设计

日期：2026-11-13

## 背景与问题

打开一个历史会话时，UI 线程会被整段阻塞 1–2 秒，期间滚动、输入、拖动窗口全部无响应。
DevTools 导出（`test27.json`，debug 构建，240Hz）显示：

- 53/53 帧超预算；最差 #252 = 1484.8 ms（build 1466.4 ms），p95 539 ms。
- #252 单帧内 `AiTextPartView` / `_ExpandableHistoryMarkdown` / `MarkdownView` 各 rebuild
  237 次、`AiChainOfThoughtView` 232 次 —— 整段消息内容在同一帧里建出来。
- 布局热点为 `RenderFlex` / `RenderPadding` / `RenderPositionedBox` / `RenderMouseRegion`，
  叶子是 `RenderParagraph`。

对照真实数据（`sessions/369c4e16…`，6 MB transcript、1755 条 part 记录）：

| 项 | 数量 |
|---|---|
| 消息 | 36（17 user / 15 assistant / 4 system） |
| 最大单条 assistant 消息 | 1229 个 part（399 reasoning ≈2.2 MB、572 tool ≈1.8 MB、258 text ≈67 KB） |
| 逻辑 turn | 17（上述巨型消息与其 user 消息同属一个 turn） |

根因是三处叠加：

1. **虚拟化粒度是 turn**。`buildTurns`（`thread_turns.dart:11`）把 user + 之后所有
   assistant 消息合成一个 turn；`VirtualThreadViewport` 只按 turn 挂载
   （`virtual_thread_viewport.dart:789`），turn body 是一个 `Column`（`:725`）。
   一个 1229-part 的 turn 进入视口，就必须整体 build + layout，
   `clampUnmeasuredMounts` 的"最多 5 个未测量 turn"上限对它无效。
2. **assistant 内容不做预算裁剪**。`text_part_view.dart:135` 只对 user 消息做 preview
   clip；assistant prose 全量内联（`:358`）。巨型 turn 的 232 个 collapsed CoT 头
   加上 258 个 text part 形成约 490 个顶层组件，一次布局。
3. **打开后立刻铺满整个数据窗口**。桌面端 `retainMountedTurns + fillDataWindow`
   （`session_history_thread.dart:1332`）在打开后逐帧把窗口内所有 turn 挂满，持续
   产生 measure/setState churn。

用户要求：**点击打开后不能出现 1–2 秒的整段阻塞**；不接受折叠内容。

## 目标与非目标

**目标**

- 打开任意长度的会话，UI 线程不出现整段阻塞：单帧新增布局内容有上界（约半屏）。
- 打开过程中滚动、输入、拖动窗口始终有响应。
- 普通会话的视觉与交互与现状完全一致；不折叠、不裁剪任何可见内容。
- 不重复渲染：视口外的节点不创建 widget，滑出后按现有机制回收。

**非目标**

- 不做超大 turn 的折叠 / "点击展开"。
- 不改 markdown 组件树、不做 assistant 文本预览裁剪（后续独立优化）。
- 不做跨会话持久化测量高度（后续）。
- 不承诺 release 下的绝对帧时间，只保证阻塞有界、交互不中断。

## 决策

| 决策点 | 结论 |
|---|---|
| 虚拟化粒度 | turn 内部再按节点切 chunk，chunk 成为虚拟项 |
| 切点位置 | 只在 `groupMessageParts` 节点边界切；CoT 不劈叉 |
| 折叠 | 不做 |
| 打开填充 | 首帧只挂视口 + overscan；用户滚动后或挂载后约 500 ms 空闲才开始补 |
| 填充节奏 | 每帧最多 1 个 chunk，由实测帧耗时决定是否继续 |
| 后台 tab | `_foreground == false` 时不填充 |
| 对外契约 | `onVisibleRange` 仍上报逻辑 turn 下标；`messageBuilder` 保留 |

## 架构

### 1. 分块模型（`thread_turns.dart`）

逻辑层 `ThreadTurn` 不变（branch、reveal、`owningUserTurnId` 均按它工作）。
视口内部新增渲染项：

```dart
class ThreadChunk {
  final String id;          // "<turnId>/<messageId>" | "<turnId>/<messageId>#<nodeStart>"
  final String turnId;      // 逻辑 turn
  final int turnIndex;      // 逻辑 turn 下标（对外映射用）
  final String messageId;
  final int partStart;      // 节点对齐
  final int partEnd;
}
```

分块规则：

- 只切 `AiRole.assistant` 消息；user/system 消息保持整条一个 chunk。
- 用 `groupMessageParts(parts, shouldFold: null)` 得到最粗节点边界；在该边界上累计
  `estimateNodeHeight` 估算高度，达到约半屏（或 24 个节点，先到为准）切一段。
  粗边界必然是实际渲染（可能更细）的节点边界，因此不会产生重复 CoT 头。
- `estimateNodeHeight` 为纯函数：text 按字符数 / 估计每行字符数 × 行高，CoT header
  固定高度，tool 节点固定预览高度。首帧后由现有 `TurnHeightCache` 实测修正。
- 流式尾段：最后一个 chunk 的 `partEnd` 随 part 追加增长，`id` 不变；内容 identity
  变化只失效该 chunk 的高度缓存与 body 缓存。

### 2. 视口（`virtual_thread_viewport.dart`）

- `_turns` → `_chunks`；高度缓存、`clampUnmeasuredMounts`、retain、offstage cache、
  `FrozenSize` 全部以 chunk 为单位。
- 新增可选 `chunkMessageBuilder(BuildContext, AiMessage, AiPartRange)`；`AiPartRange`
  是 ai_message_ui 内的值类型 `(start, end)`（半开区间），为空时每个消息退回整条
  `messageBuilder`（旧行为，包外用法不破）。
- 内容 identity = 消息 identity + `[partStart, partEnd)` + `buildKey` 命中情况；
  `_identityByTurnId` 按逻辑 turn 记录，turn 内容变化时失效该轮所有 chunk 的 body 与高度。
- 对外映射：
  - `onVisibleRange` 上报 `chunk.turnIndex`，保持 `owningUserTurnId` 等消费方语义不变。
  - `revealMessageId` 定位到包含该消息的第一个 chunk，用 chunk 高度求 offset。
  - `buildKey`/`bodyCacheKeyForTurn` 只影响包含对应消息的 chunk。
- `keepAlive`/retain/fill 的窗口计算继续复用，只是单位换成 chunk。

### 3. 渲染（`ai_message_view.dart` / `ai_message_parts.dart`）

- `AiMessageView` 新增可选 `partRange`；只把 `message.parts[start..end]` 传给
  `AiMessageParts`，后者现有的节点缓存与分组逻辑不变。
- chrome 由消息自身判断：`start > 0` 时隐藏头像、时间戳、操作栏；`end < parts.length`
  时去掉底部 `messageSpacing`。首末段拼接后与现状视觉一致。
- 跨段选择/复制不受影响（`SelectionArea` 位于 chunk 外层）。

### 4. 打开与填充预算

- 保留"先占位 → 跳到末尾 → 再挂载"（`_mountTurns`）路径；首帧只挂视口 + overscan。
- `fillDataWindow` 的启动条件改为：首次用户滚动后，或首帧挂载完成后约 500 ms 内没有
  用户交互（一次性定时器，交互则取消）；每次最多补 1 个 chunk。
- 新增 `MountBudget`（ai_message_ui 内部）：
  - 用 `SchedulerBinding.addTimingsCallback` 维护最近帧 build+raster 的 p90；
  - `hasHeadroom`（p90 < 软预算，默认 12 ms）时允许继续填充，超预算暂停；
  - 测试环境拿不到 timings 时默认 `hasHeadroom == true`。
- 用户主动滚动触发的挂载优先，但仍以 chunk 为粒度；单次最多约半屏内容。
- `_foreground == false`（后台 tab / `TickerMode` 关闭）时完全不填充。

## 兼容性与降级

- 公共 API 只新增：`VirtualThreadViewport.chunkMessageBuilder`、`AiMessageView.partRange`。
- `chunkMessageBuilder` 为 null 时退化为"一条消息一个 chunk"，行为与现状一致。
- 估高不准由既有 `_onTurnMeasured` 纠正路径处理；scroll correction 语义不变。
- 现有测试若断言 turn 级挂载数量，需改为 chunk 级断言。

## 测试计划

- 单元（`thread_turns` / chunk builder）：节点边界切分、id 跨帧稳定、流式追加只失效
  尾段、`estimateNodeHeight`、CoT 不劈叉。
- Widget（`virtual_thread_viewport`）：1200-part 合成消息首帧只构建视口附近 chunk；
  滚动后按需挂载；CoT 头数量不变；reveal / retain / keepAlive 语义不变；
  `onVisibleRange` 仍返回逻辑 turn 下标。
- 集成（tag `performance`）：合成巨型 turn 的打开 harness，断言首帧构建的 part 组件数
  不超过 chunk 上界；profile 前后对比用
  `analyze_performance_json.dart --compare`。
- 回归：现有 viewport、visible-range、keep-alive、session history 测试。

## 验收标准

- 打开含 1229-part turn 的会话：首帧构建的 part 组件 ≤ 视口 + 1 个 chunk；打开过程中
  无单帧挂载超过 1 个新 chunk 的情况。
- 打开全程可连续滚动、输入、拖动窗口；后台 tab 不产生填充帧。
- 普通会话的布局、间距、操作栏、选择行为与现状一致。
- profile 构建下重录 trace，最差帧 build 时间相对现状显著下降（目标 < 300 ms，
  以实际测量为准），且不出现 1 s 级单帧。

## 风险

- `AiMessageView` 的 chrome 抑制若漏项，切片处会出现重复头像/间距——用首末段拼接的
  golden/widget 断言覆盖。
- chunk id 与逻辑 turn 的映射若错位，会影响大纲/visible owner——单元测试固定映射。
- 软预算 12 ms 在 debug 下必然超；该预算只在 release/profile 有意义，debug 下以
  chunk 上界保证有界，不追求 60fps。
