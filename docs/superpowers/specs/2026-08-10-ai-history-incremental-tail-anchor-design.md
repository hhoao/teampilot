# AI History 增量解析:尾部锚点 — Design

**Date:** 2026-08-10
**Status:** Proposed

## Problem

History 面板打开且 CLI 持续输出时,TeamPilot 主 isolate 被 live-refresh
(150ms debounce)反复占满,窗口完全冻结、系统标记"未响应",且 CLI 进程照常
运行。冻结是不可恢复的,因为:

1. `AiHistoryLiveRefreshController._requestReload` 的 do-while 循环
   (`ai_history_live_refresh_controller.dart:159`)在持续输出下 `_reloadQueued`
   恒为 true,循环永不退出。
2. 每轮在主 isolate 上做**全量**工作:
   - transcript 全量重解析(mtime 一变就重读重排;≥256KB 才走 worker isolate,
     <256KB 时 parse 本身也在主 isolate);
   - `buildConversationTimeline` O(n log n) 全量排序 + 重建全部 AiMessage;
   - `_setSubagentAttachments` → `sameMessageListContent` 为每条消息构建
     **包含完整 tool result 全文**的 identity 字符串;
   - `ExternalStoreAiThreadRuntime._mergeReusingUnchanged` 对新实例逐条构建
     两份 identity 字符串(parse 总是产生新实例,`identical` 快速路径失效)。

会话越大、tool result 越大,每轮越慢;输出不停 → 循环不停 → 永久冻结。

**历史教训**:8/8 曾实现 byte-offset 增量 tailer,8/9 回滚
(`af7282ad`)。Claude Code 会原地重写 transcript(resume/compact/relocation
重发 prompt),"字节在游标之前移动",byte 游标把移动后的旧内容当新行解析,
消息重复累积成几十份。

## Goals

1. **增量解析**:live refresh 只处理新增事件,不做全量重解析;增量输出与
   全量解析输出**一致**(同一 transcript 在任意中间时刻,增量视图 == 全量视图)。
2. **重写安全**:Claude 的原地重写/压缩/截断不会造成消息重复或遗漏;重写
   导致锚点失效时回退全量重建。
3. **主 isolate 减负**:增量解析在 worker isolate 执行;主 isolate 上的消息
   合并走 `identical` 快速路径,不再做 identity 字符串构建。
4. **全 CLI 覆盖**:Claude Code / Codex / Cursor(JSONL)+ Opencode(SQLite /
   JSON 树)。
5. **刷新节流**:`_requestReload` 循环加最小间隔,双保险。

Non-goals (YAGNI): 不改 transcript 文件的写入端;不改
`buildConversationTimeline` 的排序/合并语义;不做 subagent 侧
(`subagents/` 目录)的增量——沿用现有 inflate 路径;不做滚动窗口裁剪
(transcript 无上限增长的问题另立课题)。

## Design decisions (author's call, reviewable)

| Decision | Choice | Why |
|----------|--------|-----|
| 增量游标 | **尾部锚点指纹**(最后一条已消费 user/assistant 事件的指纹),而非 byte offset / 行号 / 全文件 hash 集合 | 位置无关,重写时"锚点找不到 → 全量重建"统一兜底;O(1) 状态,每轮只读尾部 |
| 锚点指纹定义 | 事件自带稳定 id(Claude `uuid`)→ 用该 id;无 id 的 CLI(codex/cursor)→ 整行内容 hash | 各 CLI 格式已明确,指纹取"能唯一定位该事件"的最短字段 |
| 锚点候选范围 | 只追踪 **user/assistant** 事件 | 实测 Claude 尾部高频出现无 uuid 快照(ai-title×104、last-prompt×105、mode×29),做锚点会天天失效 |
| 尾部读取窗口 | 自适应:64KB → 256KB → 全文件 | 一次爆发写入可能几百行,窗口要能覆盖;最后才全量 |
| 重写/缩小检测 | 统一为"尾部窗口内找不到锚点 → 全量重建" | 比 byte-offset 方案的"首行指纹 + size 缩小"两条路径更简单,且覆盖 truncate、compact、resume 重写 |
| 已知弱点(锚点仍在但锚点前被改) | 接受,低频全量校验兜底(每 30 次 refresh 一次全量) | compact 保留尾部这种形态罕见;全量校验成本可控 |
| 消息列表实例 | **原地变异**:新增事件 append/merge 进同一个 `List<AiMessage>`,未变消息实例不动 | 兑现 `identical` 快速路径,主 isolate 不再构建 identity 字符串 |
| Opencode | 不走 tail:SQLite 用 `WHERE session_id=? AND id > last_seen`;JSON 树按 message 文件增量;**去掉每次全量复制 DB+WAL+SHM** | 存储形态不同,查询天然增量;当前每轮复制 ~6MB 是隐藏大头 |
| worker isolate | 增量行解析仍在 `Isolate.run`;主 isolate 只做 list 变异 + 合并 | 与 8/10 `43d20f74` 的 isolate 化方向一致 |
| 刷新节流 | `_requestReload` do-while 循环加最小间隔(≥1s),持续输出时强制降频 | 双保险;即使增量再快,也避免无意义的高频全量 |

## Design

### 1. 尾部锚点读取器(`AiTranscriptTailReader`)

新增 `client/lib/services/session/ai_transcript_tail_reader.dart`:

```
状态(per seat):
  anchorFp: String?          # 最后一条已消费 user/assistant 事件的指纹
  messages: List<AiMessage>  # 原地维护;未变消息实例不变
  fullReloadCount: int       # 低频全量校验计数器

refresh({path, force}) → TailRefreshResult:
  1. stat;path 缺失/不是文件 → 返回 unchanged(状态保留)
  2. 尾部窗口读:readBytesRange(path, max(0, size-window), window)
     window 自适应:64KB → 找不到锚点 → 256KB → 找不到 → 全文件
     (force / 首次 / 无锚点 → 直接全文件)
  3. 在窗口内逐行找 "指纹 == anchorFp" 的行(取第一个匹配;正常情况下锚点
     唯一):
     - 找到 → 该行之后的事件为新增 → 解析并 merge 进 messages,更新 anchorFp
     - 找不到 → 全量重建(messages 清空重解析),重置 anchorFp
  4. 每 30 次**成功增量**后强制一次全量校验(重建 + 与现列表比对,不同则
     替换;重建后计数清零)
```

**worker isolate 协作(状态归属)**:TailReader 状态(`anchorFp` + `messages`)
只存活在主 isolate(异步 IO + 轻量锚点查找都在这侧);重活是"新增行的
`jsonDecode` + 事件对象构建"(大 tool result 行的解码是开销大头),把
**锚点后的原始字节**交给 `Isolate.run` 解码为事件列表,回到主 isolate 后
用 `append*JsonlEvent` 逐条 merge(merge 是轻操作,且必须访问主 isolate 的
messages 状态)。

关键性质(正确性论证):
- **增量输出 ≡ 全量输出**:窗口内"锚点之后"的行集合与全量视角下"新增行"
  一致(锚点在则尾部未被重写;锚点不在则已全量重建)。逐事件
  `append*JsonlEvent` 与全量 parse 共用同一批函数,合并语义零分叉。
- **重写不产生重复**:重写导致锚点移动/消失 → 重建;重写后锚点仍在且其后
  行是重放旧事件(带原 uuid)→ `append*JsonlEvent` 按 message.id/uuid 合并,
  与全量解析行为一致(全量也会合并)。
- **部分行安全**:窗口按行切分,半行(无 `\n`)自然丢弃,补全后下次作为新行
  解析;与全量解析对畸形尾行的容忍一致。

### 2. 锚点指纹 per-CLI

| CLI | 行结构(实证) | 锚点指纹 |
|-----|--------------|----------|
| Claude Code | 事件带 `uuid`,message 带 `message.id` | 事件 `uuid`(fallback 行 hash) |
| Codex | `{type, timestamp, payload}`,无 uuid | 整行内容 hash(fnv1a-64) |
| Cursor | `{role, message}`,无 uuid/时间戳 | 整行内容 hash |
| Opencode(SQLite) | `message`/`part` 行主键自增 | `WHERE session_id=? AND id > lastSeenId` |

JSONL 三兄弟通过恢复 `AiTranscriptLineAppend` 钩子
(`AiHistoryCapability.lineAppend`,8/9 回滚时删除)接入:
`appendClaudeJsonlEvent` / `appendCodexJsonlEvent` / `appendCursorJsonlEvent`
均已是逐事件函数,直接复用。

### 3. 原地实例复用(性能兑现)

- TailReader 持有 `messages` 列表并原地 append/merge;
- `AiHistoryLoader.load` 返回**同一列表实例**(内容可能变);
- `AiHistorySeat.softReload` 的 `identical(messages, _cliMessages)` 检测
  transcript 是否变化依然成立(load 内部 token 缓存逻辑保留);
- `ExternalStoreAiThreadRuntime._mergeReusingUnchanged` 的 `identical` 快速
  路径对未变消息命中,identity 字符串构建只发生在真正新增/变更的消息上;
- `_sameSubagentAttachments` 同样受益:附件消息列表实例稳定时
  `sameMessageListContent` 的 `identical` 短路生效(需确认 inflate 复用实例)。

### 4. 刷新节流(双保险)

`AiHistoryLiveRefreshController._requestReload`:
- 记录 `lastReloadAt`;两次 reload 之间最小间隔 1s(持续输出时从 150ms 事件
  频率降为 1s 全量/增量频率);
- do-while 循环保留(输出结束时最后再刷一次),但 `_reloadQueued` 累积改为
  "间隔未到则合并为一次排队"。

### 5. Opencode 增量

- `_locateSqliteStorage`:`WHERE session_id=? AND id > ?` 增量查询;首次复制
  快照建立基线后,**后续刷新直接只读主库**(SQLite WAL 支持多进程只读,
  不再复制 6MB);检测 message 行数减少 → 全量。
- JSON 树(旧版):按 message 目录文件列表差异增量(listDir 快照)。

### 6. 集成点

| 文件 | 改动 |
|------|------|
| `services/session/ai_transcript_tail_reader.dart` | 新增:尾部锚点读取器(锚点查找 + 窗口自适应 + 重建兜底;worker 解码协作) |
| `services/cli/registry/capabilities/ai_history_capability.dart` | 恢复 `lineAppend` 钩子 |
| `services/session/ai_history_loader.dart` | load 走 TailReader 增量;token 缓存保留;返回同一实例 |
| `services/session/ai_history_live_refresh_controller.dart` | reload 节流 |
| `services/cli/opencode/.../ai_transcript.dart` | SQLite 增量查询;去全量复制 |
| `cubits/ai_history_seat.dart` | `_cliMessages` 引用增量实例;附件实例复用 |
| `packages/ai_message_core/.../runtime.dart` | 无需改(identical 快速路径已存在) |

## Testing

1. **幂等性单元测试**(核心):真实 transcript fixture(从
   `~/.claude/projects/**/*.jsonl` 脱敏样本)按"逐步 append 帧"喂给
   TailReader,每帧后断言增量输出 == 全量 parse 输出;覆盖:
   - 纯 append(多轮)
   - 一次性大块追加(超 64KB 窗口)
   - 模拟 compact/truncate 重写(锚点消失 → 重建)
   - 模拟 resume 重写(尾部重放旧 uuid 事件 → 合并不重复)
   - 半行写入
   - 每 30 次的全量校验兜底
2. **per-CLI 方言测试**:codex/cursor 用现有 fixture + 新构造的重写序列;
   opencode 用 SQLite 增量查询的等价性测试(同一 DB 快照,增量 vs 全量)。
3. **回归**:现有 `ai_history_loader_test.dart`、`virtual_thread_viewport_test.dart`
   全量跑通;softReload 不再依赖 identity 扫描的既有测试保留。
4. **真实环境冒烟**:开发机上用真实 Claude/opencode 会话(本机
   `~/.claude/projects`、`~/.local/share/opencode` 有真实数据)手动验证
   History 刷新与终端输出同步。

## Risks / Trade-offs

- **锚点窗口开销**:窗口扩大(256KB→全文件)在极端大文件上是 O(file) IO,
  但仅在锚点异常时发生,频率低。
- **低频全量校验**:每 30 次一次全量重建,大 transcript 时该轮 ~100ms+,
  但已被节流到 1s 间隔,且走 worker isolate,主 isolate 只做合并。
- **codex/cursor 无稳定 id**:行 hash 锚点偶发碰撞(64-bit fnv1a,可忽略);
  重写场景由"锚点找不到 → 重建"兜底。
- **UI 语义不变**:消息排序/去重/时间线合并完全复用现有
  `buildConversationTimeline`,无行为变化。
