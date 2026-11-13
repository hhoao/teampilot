# ACP thought / text 通道 part 设计文档

日期：2026-11-13

## 目标

把 ACP 流式 `agent_thought_chunk` / `agent_message_chunk` 映射成两条被工具调用隔开的通道，而不是一条按类型切换切开的线性 token 流。交错到达的 thought 与 text 在同一工具边界内各自追加到已有 part：推理合成一段，答案合成一段。UI 的「思考过程」分组保持现有规则，因此会自然变成少数几个块，而不是每个 token 一个「思考过程 · 1 步」。

## 背景与已确认事实

- 复现 session：`0883ea34-5003-44a2-b132-31ff497f8470`（qoder-cn / dfmodel, effort=high）。第三轮 assistant 消息最终 650 个 part（269 reasoning + 228 text + 153 tool），text/reasoning 切换 436 次。展开后每个 CoT 里的「推理」也只有几个 token。
- 截图中夹在「思考过程 · 1 步」之间的碎片是 **答案正文**；折叠的 CoT 只露出标题。展开后看到的短句是 **同一条交错流里的 thought 通道**。
- Qoder 自己的 jsonl 把 thinking / text 存成完整块。碎裂发生在 ACP 实时 `session/update`：两条通道按 token 交错推过来。
- ACP 允许 `agent_thought_chunk` 与 `agent_message_chunk` 交错。这是两条并行内容流的增量，不是「类型一变就新开一步」。
- 客户端已经知道「每个 token 一个 part 会渲染成上百个思考步骤」，并做了相邻同类型合并（`acp_chat_runtime_cubit.dart:2095-2196`）。相邻合并覆盖不了交错。
- `_queueStreamChunk` 在类型切换时新开 `_PendingStreamRun`，并「故意保留 text/thought 切换顺序」（`:385-390`）。60ms 窗口是少 emit 的性能批处理，不是通道语义。
- `groupMessageParts`（`part_grouping.dart:34-54`）把任何 text 当作 CoT 切断点。part 一旦交错，每个孤立 reasoning 都变成「思考过程 · 1 步」。
- `AiMessagePart` 只有三类：`AiTextPart` / `AiReasoningPart` / `AiToolCallPart`。

## 已确认的决策

1. **通道模型**：工具调用是硬边界。每个边界之间 reasoning 最多占用一段、text 最多占用一段；同通道增量追加到该段。两段的相对顺序等于该段内两种类型 **第一次出现** 的顺序。
2. **只改 ingest / load 的 part 折叠**。不改 `groupMessageParts`、不改 CoT 组件、不加「太碎就合」分支。
3. **一个函数** 服务 live append（只折 incoming）和 `loadMessages`（折整条 assistant）。`decodeAcpChatTranscript` / delta replay **不**折叠，保住 v2 按下标寻址。已落盘的碎 transcript 在 `loadMessages` 时折叠，并标记 `_needsRewrite`，下次 save 整文件写成通道形态。
4. **`_queueStreamChunk` 的 60ms 批处理保持原样**。它只负责少 emit；语义由折叠函数保证。即使窗口内积了交错 run，flush 后折叠会收成通道 part。

## 非目标

- 不改 ACP wire schema，不改 Qoder / 其他 agent 的推流方式。
- 不改 CoT 折叠策略、统计文案、auto-expand。
- 不把工具前后的推理合成一块（工具是硬边界，时间顺序保留）。
- 不在渲染层做二次拼接。
- 不迁移改写磁盘上的旧 jsonl；下次 `saveMessages` 若带上已折叠的内存快照，才会按现有 v2 diff 写出更少的 part。加载路径不依赖这次写出。

## 不变式

对一条 assistant 消息的 `parts`，从左到右扫描：

- `AiToolCallPart` 开启新段。
- 一段之内，最多一个 reasoning 累积点、一个 text 累积点。
- 新的 thought 增量追加到本段已有 reasoning（越过中间的 text 找到它）；本段还没有 reasoning 则新开。
- text 增量对称处理。
- 空 text / 空 reasoning 仍在折叠前丢弃（现有 `_isEmptyStreamPart`）。

例子：

```
think "a" → text "1" → think "b" → text "2" → tool → think "c" → text "3"
```

结果：

```
[reasoning "ab"] [text "12"] [tool] [reasoning "c"] [text "3"]
```

`groupMessageParts` 得到 `CoT(ab + tool + c)` 和正文 `"12"` / `"3"`。

thought 后直接 text（现有测试 `keeps text/reasoning order across interleaved chunks`）：

```
[reasoning "thinking"] [text "Answer"]
```

行为不变。

## 架构与数据流

```
agent_thought_chunk / agent_message_chunk
  └─ AcpMessageChunk(isThought)
       └─ _queueStreamChunk          // 60ms 批处理，类型切换仍可产生多个 run
            └─ _flushPendingStreamRuns
                 └─ _appendMessageParts
                      ├─ drop empty
                      ├─ appendAcpStreamChannelPart(existing, incoming…)
                      └─ _splitStreamingText（仅 live 尾部 text 的 8KB 分段）

live / replay cubit
  └─ _coalesceStreamingParts：copy existing，对 incoming 调用 append
       （不重折 existing，保留 8KB 文本分段）

decodeAcpChatTranscript / applyAcpChatTranscriptDelta
  └─ _MessageBuilder.build() 原样产出（保住 v2 part 下标）

loadMessages
  └─ decode 之后对 assistant 调用 foldAcpStreamChannelParts
       └─ part 数量减少则 _needsRewrite，下次 save 整文件写成通道形态
```

### 1. 折叠函数

新增纯函数（建议放在 `client/lib/services/acp/` 下独立小文件，cubit 与 transcript decoder 共用，避免 cubit ↔ transcript 循环依赖）：

```dart
/// Appends [part] onto [out] in place.
///
/// Tool calls start a new segment. Within a segment, a text (reasoning)
/// part concatenates onto the last text (reasoning) part, skipping the
/// other channel; if none exists yet in the segment, [part] is appended.
void appendAcpStreamChannelPart(
  List<AiMessagePart> out,
  AiMessagePart part,
);
```

查找规则：从 `out` 尾部向前，遇到 `AiToolCallPart` 停止（新段，把 `part` 加在末尾）；遇到同类型则拼接并替换该下标；遇到另一通道则继续向前。

`_coalesceStreamingParts` 改为对每个 incoming part 调用该函数。不再只跟 `out.last` 合并。

`_mergeStreamParts` 删除或收进该函数内部。

### 2. Live 与 8KB 文本分段

`_splitStreamingText` 仍在 `_appendMessageParts` 末尾运行，只切 **最后一段** 过长的 `AiTextPart`。通道追加总是拼到本段 **最后一个** 同类型 part，因此已切出的 8KB 头不会在后续 thought 到来时被重新粘上。

加载路径只做通道折叠，不重跑 `_splitStreamingText`。已完成消息上，曾经为流式 markdown 切过的相邻 text 可能被粘回一段；这是可接受的，加载后不再逐 token 重编译。

### 3. Transcript 加载

`_MessageBuilder.build()` 不折叠：它是 v2 按下标寻址的共用出口（全量 decode、delta replay、writer 快照）。在这里折叠会让磁盘下标和内存 part 对不上，后续 `text` append / tool status 会写错位置。

通道折叠只发生在 `AcpChatTranscriptWriter.loadMessages`：decode 之后对 assistant 调用 `foldAcpStreamChannelParts`，user / system 原样。若折叠减少了 part 数，设 `_needsRewrite`，下一次 `saveMessages` 走现有 compact 整文件重写，磁盘下标与通道 part 对齐。

远端 `replace: true` 快照仍走 `decodeAcpChatTranscript`（不折叠），因此 live 的 8KB 分段头不会被 follower 粘掉。

### 4. 持久化

不单独写迁移。内存已经是通道 part 之后，下一次 `saveMessages` 按现有 v2 对 committed 快照做 diff：part 数量变少时现有 compact/rewrite 条件会处理（`acp_chat_transcript.dart` 在 parts 删除或重排时整文件重写）。加载不依赖这次写出。

## 测试

全部加在 `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`，折叠函数若抽到独立文件则再加一份纯函数测试（无 cubit）。

必须覆盖：

1. `think a, text 1, think b, text 2` → 两个 part，`reasoning "ab"` + `text "12"`。
2. `think a, tool, think b` → `[R a, tool, R b]`（工具硬边界）。
3. `think a, text 1, tool, think b, text 2` → `[R a, T 1, tool, R b, T 2]`。
4. `text 1, think a, text 2` → `[T "12", R a]`（段内谁先到谁在前）。
5. 现有 `consecutive thought chunks coalesce`、`consecutive text chunks coalesce; thought stays a separate part`、`keeps text/reasoning order across interleaved chunks` 仍然成立。
6. `loadMessages` 读入交错 part 的 jsonl 后得到与 (1) 相同的折叠结果；`decodeAcpChatTranscript` 保持磁盘下标，不折叠。
7. 空 chunk 仍丢弃，不新开 part。

## 错误与边界

- 未知未来 `AiMessagePart` 子类：当作硬边界（与 tool 相同，追加到末尾、截断当前段）。当前 sealed 只有三类，测试用 tool 覆盖边界语义即可。
- 同一 `toolCallId` 的后续 status 更新仍走现有 in-place 更新，不经过通道折叠。
- 折叠只拼接 `text` 字段；tool 的 args/result 不参与。
