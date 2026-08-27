# Chat History Performance Design

## Goal

让聊天界面在大型 transcript、工具调用、子 Agent 和 mailbox 混合存在时更快显示，同时保持五种 CLI 的消息语义、流式合并、工具结果、搜索、任务面板和滚动行为不变。

## Scope

本次改造包含四个相互关联的部分：

1. JSONL 全量重建和增量读取的批量化；
2. 聊天历史的首屏窗口和旧消息分页；
3. 子 Agent side transcript 的按需加载；
4. mailbox 时间线和 Flutter 消息 widget 的增量复用。

OpenCode SQLite 继续使用行级增量路径；Claude、Codex、Cursor、flashskyai 继续使用 JSONL 的 `lineAppend` 语义。各 CLI 的 adapter 仍是最终的语义基准。

## Non-goals

- 不更改任何 CLI transcript 格式或持久化文件；
- 不把五种 CLI 合并成一套有 CLI 分支的解析器；
- 不取消完整历史搜索和任务面板；
- 不用固定的毫秒阈值作为 CI 性能测试标准；
- 不在本次改造中引入新的本地数据库迁移。

## Current bottlenecks

当前 `AiHistoryLoader` 已有 cache token、JSONL tail、OpenCode 行级增量、worker isolate 和消息窗口，但仍有以下成本：

- `AiTranscriptTailReader._fullReload` 对每一行单独调用 decoder，生产 worker 下会产生大量 isolate 通信和 Future 调度；
- tail reader 的首次建立、锚点丢失和周期校验会在 UI isolate 完成事件追加；
- Claude tool-result enricher 可能再次完整读取并解码同一 transcript；
- `SubagentAttachmentInflater` 遍历完整消息并串行读取每个 side transcript；
- `buildConversationTimeline` 每次刷新都复制、排序、去重并重新创建全部 `AiMessage`；
- UI 只限制渲染最近消息，但数据层仍可能先完成完整历史和所有附件处理。

## Architecture

### 1. Unified paged history source

在 CLI history capability 下新增可选分页能力，保持已有 `AiTranscriptAdapter`、`AiTranscriptLineAppend` 和 `AiTranscriptIncrementalRefresher` 不变：

```dart
abstract interface class AiTranscriptPageReader {
  Future<AiHistoryPage?> readLatest({
    required SessionHistoryContext ctx,
    required int limit,
  });

  Future<AiHistoryPage?> readOlder({
    required SessionHistoryContext ctx,
    required AiHistoryCursor cursor,
    required int limit,
  });
}
```

`AiHistoryPage` 必须包含消息列表、是否还有更早内容、下一 cursor、来源 token 和必要的行边界状态。cursor 只由具体 CLI reader 解释，不能在通用层猜测 transcript 路径或格式。

JSONL reader 使用字节偏移和完整行边界读取最近窗口；跨窗口的 assistant 流式片段必须通过 `lineAppend` 继续合并。OpenCode reader 使用其 SQLite 增量存储的稳定排序键。任何无法保证顺序或完整性的情况返回不可用，让 loader 走完整 adapter 回退。

### 2. Loader and seat data flow

首屏流程：

```text
resolve seat/context
  -> readLatest(limit = initial turns)
  -> merge mailbox incrementally
  -> publish recent window immediately
  -> schedule complete index in background
```

旧消息流程：

```text
scroll near top
  -> readOlder(cursor)
  -> merge/prepend while preserving message identity
  -> adjust scroll offset by measured height
```

完整历史仍由 loader 的后台任务维护，用于搜索、任务面板和必要的全量一致性校验。若分页 reader 不可用，loader 使用现有完整 adapter parse；大型完整解析仍放到 worker isolate。

`AiHistorySeat` 保存当前显示窗口、完整索引状态、分页 cursor 和 mailbox 快照。seat 只向 runtime 发布当前窗口，不把完整索引直接交给首屏 widget。

### 3. Batched transcript decoding

`AiTranscriptTailReader._fullReload` 必须先拆出所有非空行，再一次调用 `EventDecoder`，然后按返回结果顺序调用 `lineAppend`。必须保持：

- 无效 JSON 不推进 fallback sequence；
- 无显示内容事件不推进 anchor；
- EOF 完整 JSON 和半行行为不变；
- coalesce 和 fallback id 与 adapter 全量解析一致。

增量 tail refresh 继续一次批量解码尾部行。常驻 `JsonlDecodeWorker` 继续复用，避免每轮启动 isolate。

### 4. Tool-result index reuse

Claude-compatible 主 parser 和 tool-result enricher 共享一次事件解码结果，或由 enricher 使用与 transcript token 绑定的索引缓存。文件未变化时不重新建立索引；文件追加时只处理新增行；文件重写时丢弃索引并完整重建。

输出必须与当前 enricher 一致：只替换满足 truncation marker 的 tool result，保留错误标记、tool call id 和原始消息顺序。

### 5. Lazy subagent attachments

首屏不执行完整 `SubagentAttachmentInflater.inflate`。loader 只建立轻量 toolCallId 索引，包含标题、工具类型和是否可能存在 side transcript。

新增 seat/loader 的按 id 单飞加载接口：

```dart
Future<AiSubagentAttachment?> loadSubagentAttachment(
  String toolCallId,
);
```

点击预览时调用该接口；同一个 id 的并发请求共享 Future，成功后写入 attachment cache，失败时显示现有不可用提示。side transcript 不存在时继续生成 tool-result 降级 attachment。递归深度和现有 workflow 子节点语义保持不变。

自动打开只允许触发当前目标 id 的预加载，不得重新扫描并加载整份历史的所有附件。

### 6. Incremental timeline and widget identity

时间线缓存按 seat 保存 CLI snapshot、mailbox fingerprint 和合并后的消息列表：

- 两侧 token 都未变化：直接返回相同列表实例；
- 只有 transcript 尾部增加：复用既有 prefix，只合并新增事件；
- 只有 mailbox 增加：只插入新 mailbox event；
- 顺序、删除、压缩或 cursor 失效：完整排序、去重和重建。

完整重建继续使用现有 `(createdAt, cliOrder, id)` 排序和 dedupe 规则。增量路径必须通过同一规则验证结果，未变化消息保持 `identical`。

`VirtualThreadViewport` 保留现有窗口、keep-alive、height cache 和滚动锚定机制。旧页 prepend 后通过 measured height correction 保持用户当前阅读位置。首屏不增加新的同步 Markdown layout。

## Error and consistency rules

- 分页读取失败：保留已显示窗口，尝试完整 adapter parse；
- 完整解析失败：保留旧内容并显示非阻塞刷新错误；冷启动无内容时显示错误状态；
- JSONL anchor 丢失、文件截断或重写：完整重建 tail state；
- SQLite 行数回退、删除、压缩或 schema 不兼容：放弃增量，完整 parse；
- 子 Agent 加载失败：不影响父聊天历史，使用降级内容或不可用提示；
- 分页与完整解析结果不一致：以完整 adapter 结果为准，并记录诊断日志；
- mailbox 读取失败：沿用 CLI-only 降级，不阻塞聊天首屏。

## Testing strategy

### Unit tests

- tail full reload 使用一次批量 decoder；
- 大量无效 JSON、metadata、EOF 半行和无换行 EOF；
- JSONL 最新页/旧页 cursor 边界、流式 assistant 跨页合并；
- 五种 CLI 的分页结果与完整 adapter 结果逐条比较；
- OpenCode 增量、删除、排序变化和完整回退；
- tool-result index 的缓存命中、追加更新和文件重写；
- 子 Agent 按 id 加载、并发单飞、递归 workflow、失败降级；
- 时间线 mailbox 插入、重复 id、完整回退和消息实例复用。

### Seat and widget tests

- 首屏只发布最近窗口并正确报告 `hasOlder`；
- load older 后消息顺序、pending、mailbox 和 `totalMessageCount` 正确；
- prepend 保持滚动位置；
- 刷新不清空已有内容；
- 点击子 Agent 时才触发 side transcript 加载；
- 未变化 turn 不重新执行 message builder；
- 搜索和任务面板仍覆盖完整后台索引；
- 五种 CLI 的历史兼容 fixture 全部保持现有断言。

### Performance evidence

加入可测试的阶段计时/计数注入点，记录：`locate`、`read`、`decode`、`adapter.parse`、`enrich`、`inflate`、`timeline merge`、`first publish`。性能测试优先断言调用次数、批量大小、对象 identity 和未触发的 IO，不使用不稳定的固定毫秒门槛。需要人工比较时使用 profile 模式和 `tool/analyze_performance_json.dart`。

## Acceptance criteria

- 大型 JSONL 全量重建不再逐行向 decoder 发请求；
- 首屏不等待所有旧消息和所有子 Agent side transcript；
- 向上滚动可以完整读取旧记录，且滚动位置稳定；
- 搜索、任务面板、工具结果、mailbox、流式合并和五种 CLI 兼容测试通过；
- 未变化刷新复用消息和 widget 实例；
- 所有新增回退路径都有自动化测试；
- 完成前运行仓库规定的 `flutter analyze` 和完整测试命令。
