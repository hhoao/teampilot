# OpenCode 消息与工具调用格式参考

**日期:** 2026-08-12
**来源:** adapter `client/lib/services/cli/opencode/capabilities/history/{ai_transcript,ai_history_capability,side_resolver}.dart`、
`capabilities/{native_session_id,history_context_env,config_profile,tool_call_resolvers}.dart`、
测试 `client/test/services/cli/registry/capabilities/history/opencode_ai_transcript_test.dart`、
夹具 `client/test/fixtures/session_history/opencode/{storage,from_db_shape}`。
工具名 / args key 另经本机 `~/.local/share/opencode/opencode.db`（sqlite3 只读，WAL 模式）实测核实——
夹具与测试只覆盖 `bash`，`read/edit/write/grep/glob/todowrite/question/skill/webfetch` 等行来自本机实测（表中「来源」列标注）。

## Transcript 存储

| 项目 | 值 |
|---|---|
| 位置 | 原生默认 `$XDG_DATA_HOME/opencode/opencode.db`（`config_profile.dart:307-311` 注释：opencode 只认 `OPENCODE_DB`，**没有** `OPENCODE_DATA_DIR`；实测本机 `~/.local/share/opencode/opencode.db`）；TeamPilot 会话内为 `{toolRoot}/opencode.db`（`history_context_env.dart:10` 把 `OPENCODE_DB` 设为会话 runtime 目录下的 db 路径） |
| 数据目录 | `opencodeDataDirFromEnv` = `ctx.env['OPENCODE_DB']` 的 **dirname**（`ai_transcript.dart:119-124`）；空值或 `:memory:` → 返回 null |
| 会话关联 | `resolveOpencodeNativeSessionId`（`native_session_id.dart:14-26`）顺序：persistedNativeId → legacy JSON 树 `storage/session/**/ses_*.json` 字典序最大 → SQLite `SELECT id FROM session ORDER BY time_updated DESC, id DESC LIMIT 1`（最新会话） |
| 文件格式 | SQLite（`PRAGMA journal_mode=WAL`；open 时写 `opencode.db` + `-wal`/`-shm` 侧车）。本地只读连接可直接读 WAL、无需整库拷贝；SFTP/WSL 等 remote 后端才快照拷贝到临时目录（`native_session_id.dart:84-104, 147-223`） |
| 解析入口 | `OpencodeAiTranscriptAdapter` / `OpencodeAiHistoryCapability`（`ai_transcript.dart` / `ai_history_capability.dart`）；读 DB 的查询在 worker isolate 上跑（`OpencodeSqliteReadHandle.read`，避免 UI isolate 阻塞） |
| 增量能力 | **有（非 JSONL 机制）**——`lineAppend = null`（`ai_history_capability.dart:27`，注释 "multi-file DB; no single-line incremental dialect" ⇒ loader 无 tail reader，恒走全量 parse）；增量走 **sqlite 增量 locate** `locateOpencodeTranscriptIncremental(afterMessageId)`（`WHERE session_id=? AND id>?`，`ai_transcript.dart:242-303`）+ **liveCacheToken** store 级指纹驱动 loader 缓存（详见「增量 vs 全量」） |

### SQLite 表结构（本机 `.schema` 实测）

transcript 相关表为 `session` / `message` / `part`（其余 `project`/`workspace`/`event`/`todo`/`session_input`/`session_message` 等与 seat transcript 无关，adapter 不碰）。**注意：`message` 与 `part` 没有独立的 `role` / `content` 列——内容整体存在 `data` 列的 JSON 文本里。**

| 表 | 关键列 | 索引 |
|---|---|---|
| `session` | `id` TEXT PK；`project_id` NOT NULL；`workspace_id`；**`parent_id`**（子代理会话的父链接，真实列——见「子代理形态」）；`slug`/`directory`/`path`/`title`/`version`/`share_url`/`summary_*`/`metadata`；`cost` REAL；`tokens_input/output/reasoning/cache_read/cache_write`；`revert`/`permission`/`agent`/`model`；`time_created`/`time_updated` INTEGER NOT NULL；`time_compacting`/`time_archived` | `session_project_idx`、`session_workspace_idx`、`session_parent_idx(parent_id)` |
| `message` | `id` TEXT PK；`session_id` TEXT NOT NULL（FK→`session.id` ON DELETE CASCADE）；`time_created`/`time_updated` INTEGER NOT NULL；`data` TEXT NOT NULL（消息 JSON） | `message_session_time_created_id_idx(session_id, time_created, id)` |
| `part` | `id` TEXT PK；`message_id` TEXT NOT NULL（FK→`message.id` CASCADE）；`session_id` TEXT NOT NULL（旧 schema 无此列）；`time_created`/`time_updated` INTEGER NOT NULL；`data` TEXT NOT NULL（part JSON） | `part_message_id_id_idx(message_id, id)`、`part_session_idx(session_id)` |

- `data` 列实测为 TEXT（JSON 文本）；适配器 `_decodeDbJson`（`ai_transcript.dart:448-461`）同时兼容 `List<int>`（BLOB）——旧版 opencode 可能存字节。
- 测试内联建表是简化版（`opencode_ai_transcript_test.dart:197-215` 等：只有 `id/session_id/message_id/time_created/data`，无 `time_updated`、无 FK）。旧 schema 兼容路径：批量按 `part.session_id` 的查询抛 `SqliteException` → 回退逐消息 `WHERE message_id = ?`（`ai_transcript.dart:383-401, 422-432`）；无 `time_updated` 列的库做 `MAX(time_updated)` 指纹时查询失败被吞 → 指纹退化为 null（每次全量，正确但慢）。

### 定位输出的 fragment 布局（统一喂给 adapter）

| 布局 | 输出片段 | 说明 |
|---|---|---|
| SQLite（当前） | `message/{id}.json` + `part/{messageId}/{partId}.json` | 行 `data` JSON 解码后 `putIfAbsent` 回填 `id`/`sessionID`（part 回填 `messageID`）；`time` 非对象且 `time_created` 为 int 时回填 `{"created":…}`（`ai_transcript.dart:403-446`） |
| legacy JSON 树（`storage/` 下，已废弃） | `session/{sessionId}.json`、`message/{messageId}.json`、`part/{messageID}/{partId}.json` | 与 SQLite 路径产出**相同的片段名**，adapter 单一解析器不感知来源（`ai_transcript.dart:161-236`） |
| 排序 | message 全量 `ORDER BY time_created ASC, id ASC`；增量 `ORDER BY id ASC`；part `ORDER BY time_created ASC, id ASC`（`ai_transcript.dart:319-329, 386-391`） | adapter 内再按 `time.created` → `id` 排序消息、按 part `id` 字符串排序 parts（`ai_transcript.dart:555-566`） |

## 消息 schema

消息 = `message` 行（角色/时间戳）+ 该行下 `part` 行（内容）。`message.data` 实测字段：
`{"id","sessionID","parentID","role":"user|assistant","mode","agent","path":{"cwd","root"},"cost","tokens":{"input","output","reasoning","cache":{"read","write"}},"modelID","providerID","time":{"created":<ms>,"completed":<ms>},"finish":"stop","summary":{"diffs":[]}}`。
adapter 只用 `id` / `role` / `time.created` 三项；`role` 非 `user`/`assistant`（如 system/developer）的整条消息丢弃（`ai_transcript.dart:531-536`）；`time.created` 是毫秒 epoch（实测 1784616649823），`createdAt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)`。

`part.data` 的 `type` 实测分布（本机 3403 tool / 3015 step-start / 3009 step-finish / 2022 reasoning / 1232 text / 572 patch）——adapter 只消费 `text` / `reasoning` / `tool` 三种，其余一律忽略：

| part type | 关键字段 | AiMessage 映射 |
|---|---|---|
| `text` | `text`（实测可带 `time:{start,end}`；可选 `synthetic` / `ignored` 标记） | AiTextPart；trim 后为空、或 `synthetic==true`、或 `ignored==true` → 整 part 丢弃（`ai_transcript.dart:627-633`） |
| `reasoning` | `text` | AiReasoningPart；trim 后为空 → 丢弃（`ai_transcript.dart:634-637`） |
| `tool` | `tool` / `callID` / `state` | AiToolCallPart（详见工具调用 schema）；**仅 assistant 消息的 tool part 有效**，user 消息的 tool part 丢弃（`ai_transcript.dart:638-639`） |
| `step-start` / `step-finish` / `patch` | — | 忽略（`default → const []`，`ai_transcript.dart:679-680`；实测 `patch` 行只含 `{type,hash,files}`，write 的差异不在文本里） |

无 JSONL 意义上的 fallback id：`message` 行 `id` 为空即整条跳过，part 靠 `callID ?? id` 兜底——消息 id 恒等于 db 行 id（`msg_*`）。

## 工具调用 schema

tool part 实测形态（本机）：

```json
{"type":"tool","tool":"bash","callID":"call_…",
 "state":{"status":"completed","input":{"command":"ls"},
          "output":"a.txt\nb.txt","metadata":{}},
 "title":"ls","time":{"start":…,"end":…}}
```

adapter 映射（`ai_transcript.dart:638-682`）：`toolCallId = callID ?? part.id`（都为空则跳过）；`toolName = tool` 原样透传、空则兜底 `'tool'`；`args = state.input`（Map 才有效，非 Map → args=null）；`state.status` 映射：

| status（实测枚举） | AiToolCallStatus | result |
|---|---|---|
| `completed` | complete | `state.output`（字符串，原样） |
| `error` | complete + `isError=true` | `state.error`（trim 后空则 null） |
| `pending` / `running` / 空 | incomplete | — |
| 其他 | incomplete | — |

**工具名不做白名单**——`tool` 字段原样透传（实测含 1 条 `"tool":"invalid"`：模型输出非法工具调用时 opencode 记的占位名，照样显示）。「解析类别」来自共享表 `services/ai_history/tool_call_categories.dart`（`OpencodeToolCallResolvers` 直接继承 `SharedToolCallResolvers`，`tool_call_resolvers.dart:3` 无 CLI 专属 delta）：

| tool name | args 关键 key（实测） | 解析类别 | 来源 |
|---|---|---|---|
| bash | `command`（实测另见 `timeout`、`workdir`） | command | 夹具 `prt_tool1.json` / `prt_tool.json` + 测试 + 本机实测 |
| read | `filePath`、`limit`、`offset` | read | 本机实测 |
| edit | `filePath`、`oldString`、`newString` | edit | 本机实测 |
| write | `filePath`、`content` | write | 本机实测 |
| grep | `pattern`、`path`、`include` | read | 本机实测 |
| glob | `pattern`、`path` | read | 本机实测 |
| task | `description`、`prompt`、`subagent_type`、`task_id` | subagent | `subagentToolNames`（`ai_history_capability.dart:33`）+ 本机实测 |
| todowrite | `todos`（数组元素 `content`/`status`/`priority`） | task | 本机实测 |
| question | `questions`（数组元素 `question`/`header`/`options[]`） | other（共享表无条目） | 本机实测 |
| skill | `name`（实测值如 `"find-skills"`） | other（共享表无条目） | 本机实测（另 `resource.dart:5` 佐证 opencode 用单数 `skill` 目录） |
| webfetch | `url`、`format` | search | 本机实测 |
| （兜底）tool | 无 | other | `ai_transcript.dart:643`——`tool` 字段为空时的默认名 |

**共享解析器兜底别名（无内置 CLI 实测发射）**：`SharedToolCallResolvers` 的 str-replace / write / unified-diff codec 与 read 文件规则还接受一组别名——当前 5 个内置 CLI（claude/codex/opencode/cursor/flashskyai）**均未实测发出**，仅当未来某 CLI 发出时解析器才按对应类别处理（`shared_tool_call_resolvers.dart:20-71`；类别均已注册在共享表 `tool_call_categories.dart`）：

| tool name | 所属解析器配置 | 解析类别 |
|---|---|---|
| strreplace / editnotebook / notebookedit | str-replace codec `toolNames`（`shared_tool_call_resolvers.dart:20`） | edit |
| writefile / write_file / create / create_file | write codec `toolNames`（`shared_tool_call_resolvers.dart:28`） | write |
| applypatch / apply_patch | unified-diff codec `toolNames`（`shared_tool_call_resolvers.dart:34`） | edit |
| readfile / read_file | read 文件规则 `toolNames`（`shared_tool_call_resolvers.dart:41`） | read |

汇总工具调用覆盖矩阵时：上表别名计入「解析器可解析」列，不计入任何 CLI 的实测发射表。

**camelCase 与 snake_case 混用（重点）**：读写类工具参数是 **camelCase**——`read`/`edit`/`write`/`grep`/`glob` 的 `filePath`、`edit` 的 `oldString`/`newString`、`write` 的 `content`、`bash` 的 `workdir`；而子代理工具 `task` 用 **snake_case**——`subagent_type`、`task_id`。写解析器/文档对照时不可假设单一命名风格；`tool` part 内的字段名本身是 camelCase（`callID`、`state.input`、`state.output`），与 claude/codex 的 snake_case 事件层（`tool_use_id`、`call_id`）形成对照。

## Reasoning / 子代理形态

- **reasoning part**：`{"type":"reasoning","text":…}`（实测 2022 行）→ AiReasoningPart；与 claude 的 `thinking` 块不同，opencode 用独立的 `reasoning` part 类型名。
- **task 子代理**（`OpencodeSideResolver`，`subagentToolNames = {'task'}`）：
  - 子会话 id：`opencodeChildSessionId`（`side_resolver.dart:17-42`）——result 为 Map 时读 `sessionId` 或 `metadata.sessionId`；为文本时正则 `<task id="(ses_[^"]+)">`（实测 task 输出以 `<task id="ses_…" state="completed">` 包裹，`state.metadata` 含 `parentSessionId`/`sessionId`/`model`/`truncated`）；
  - **运行中 discovery**：task 未结束时输出里还没有子 id——扫描 `session WHERE parent_id = ?`（当前布局的真实列，`side_resolver.dart:352-355`）或 legacy `data` JSON 的 `parent_id`/`parentID`（`side_resolver.dart:363-377`）；命中规则 = 首个 `createdMs >= 工具调用时刻` 的子会话（顺序 spawn 场景），否则取最新子会话（`_pickRunningChild`，`side_resolver.dart:384-406`）；
  - 子 transcript 定位：`locateOpencodeTranscriptForSession(ctx, childId)` 按子会话 id 全量/增量定位同一 db；
  - 解析失败返回 null → inflater 回退 `syntheticSubagentMessagesFromResult`；
  - parent_id 不符只记日志告警（`side_resolver.dart:483-504`），不阻断。
- **fingerprint 恒为 null**（`side_resolver.dart:443-447`）：注释明确 opencode transcript 是 JSON/SQLite 树、不在 `projects/` 下，loader 的父 cache token 必 miss/move——live refresh 每次都重新定位解析（靠 store 级 liveCacheToken 变化触发，见下节）。
- **工具结果截断回填：无**——`toolResultEnricher = NoOpToolResultEnricher`（`ai_history_capability.dart:13`），与 claude 的 `ClaudeCompatibleToolResultEnricher` 不同。

## 增量 vs 全量

三层机制，按生产生效顺序：

1. **loader 层（生产实际生效）——liveCacheToken store 级指纹**：`opencodeLiveCacheToken` = `oc|{part 行数}|{part MAX(time_updated)}|{session 行数}|{session MAX(time_updated)}`（`ai_transcript.dart:139-159`，一次索引 count 查询，无整库拷贝）。`AiHistoryLoader` 用 `cap.liveCacheToken ?? 默认 probe` 作缓存 token（`ai_history_loader.dart:511-515, 214`）：token 不变 → 复用缓存消息（不 locate、不 parse、不 inflate）；token 变（seat 写一轮**或**运行中的 task 子会话 append——store 是全部会话共享的）→ 全量 locate + parse + 子代理 inflate。子会话写入同样推高 store 指纹，正是「live refresh 跟随运行中 task」的机制。
2. **sqlite 增量 locate（能力层面，测试覆盖）**：`locateOpencodeTranscriptIncremental(afterMessageId)`（`ai_transcript.dart:242-303`）——`SELECT id, data, time_created FROM message WHERE session_id = ? AND id > ? ORDER BY id ASC`，hints 带 `incremental=true` / `afterMessageId` / `lastMessageId` / `cacheToken=opencode-sqlite|$sessionId|$lastId`；part 走与全量同一个 `_buildSqliteFragments`（batch + 旧 schema 回退）。测试断言窗口语义（`opencode_ai_transcript_test.dart:363-429`）：`afterMessageId=0` → 2 条、`=1` → 仅剩 1 条 assistant，`lastMessageId=2`。
3. **lineAppend / tailer 层：无**——`lineAppend = null`（`ai_history_capability.dart:27`）⇒ loader `_tailReaderFor`/`_tryIncrementalLoad` 返回 null（`ai_history_loader.dart:120-154`）⇒ 恒回退全量 `adapter.parse`（无单行增量方言，这是与 claude/codex 的 JSONL 锚点 tailer 的本质差异；`tailFallbackPrefix='opencode'` 因此无实际用途）。

**记忆化（live refresh 免重复读库）**：parent bundle memo——seat-only 指纹（seat 会话的 part 行数 + `MAX(time_updated)`，`ai_transcript.dart:57-77`，cap 16；**子会话写不使 parent 失效**）；child bundle memo（每子会话同款指纹，`side_resolver.dart:110-131`，cap 64）；child discovery memo（`(dataDir, parent, toolCallId, toolCallAt)` + db/WAL 的 mtime+size 指纹，`side_resolver.dart:196-229`，cap 32）。SQLite 上的查询统一在 worker isolate 跑（`native_session_id.dart:120-144`）。

**id 一致性**：消息 id 恒 = db 行 id（无 fallback 序号、无 `seq`），增量 locate 与全量 locate 产出同一批行 id——因此增量/全量消息序列天然一致，不存在 claude/codex 那种 fallback 序号对齐问题。

## 已知陷阱

- **`message`/`part` 表没有 `role`/`content` 列**：常见直觉 `select role, content from message` 会直接报 `no such column`——角色与内容都在 `data` JSON（实测本机 schema 无此二列；brief 的抽查命令需改为 `select substr(data,1,…) from message`）。
- **camelCase / snake_case 混用**：`filePath`/`oldString`/`newString`/`content`（camelCase）与 task 的 `subagent_type`/`task_id`（snake_case）并存于同一 CLI；part 字段名本身也是 camelCase（`callID`/`state.input`/`state.output`）。
- **`message.data` 里的 `content` 数组字段不被解析**：内容唯一来源是 `part` 行（incremental 测试样本的 message data 自带 `content[]` 但 adapter 忽略，实测本机 message 无 `content` 字段——旧版形态残留）。
- **`patch`/`step-start`/`step-finish` part 被忽略**：实测各 ~3000 行的噪音；`patch` 行（write 的编辑差异）不并入任何文本 part。
- **user 消息的 tool part 丢弃**；**非 user/assistant 的 role 整条消息丢弃**。
- **坏 JSON part 静默跳过**（夹具 `prt_bad.json` 内容 `not-json`）。
- **无截断回填**：`NoOpToolResultEnricher`——工具输出被截断时无占位回填机制（claude 有，opencode 没有）。
- **WAL 陷阱**：open 时只拷贝 `opencode.db` 主文件读到的是空 schema（native_session_id.dart:84-104 注释 + 测试覆盖）；只读连接直读 WAL 没问题，但本地 watch 的 change 信号必须把 `-wal`/`-shm` 侧车计入（mtime 可能只在侧车上动）。
- **旧 schema 退化**：无 `time_updated` 列或 `part.session_id` 缺失时，指纹/批量查询失败被吞 → 每次全量（正确但失去增量收益）。
- **TEXT 主键的字典序**：真实 schema 的 `message.id` 是 `msg_…` TEXT（增量 `id > ?` 是字典序比较）；测试夹具用 INTEGER AUTOINCREMENT 主键验证窗口语义——两者对「新 id 单调增」的假设一致，但真实 id 的随机后缀不保证与创建序严格对应。
- **`invalid` 占位名**：模型输出非法工具调用时 opencode 记录 `"tool":"invalid"`（实测 1 行），adapter 原样透传、不纠错。
