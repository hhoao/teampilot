# 新增 CLI 接入清单

**日期:** 2026-08-13
**状态:** 落地（子项目「测试校验 + 接入清单」Task 1，commit 见本分支 git log）

本文是「transcript 历史 / 工具调用解析」链路的**接入清单**：以 `client/lib/services/cli/claude/`（完整范例）与其余 4 个 CLI 的既有实现为对照，列出新增 CLI 的 6 个接入点。能力全集的接入（installer / headless / provider / 配置继承等）见 [docs/cli-architecture.md](../cli-architecture.md) 的「新增 CLI 流程」；分层约定见 [docs/tool-call-parsing-convention.md](../tool-call-parsing-convention.md)；本文只覆盖下述 6 点。

> 引用约定：src 路径可 grep 回验；`spl@93c9991` = system_prompts_leaks 固定 commit 快照锚点（禁止"最新版"表述，见 [tool-layer-coverage.md](tool-layer-coverage.md) 头注）。行号为撰写时点参考，以源码为准。

## 6 个接入点总览

| # | 接入点 | 文件 | 对照范例 |
|---|--------|------|---------|
| 0 | CliTool 枚举 + tool 定义 | `client/lib/models/team_config.dart` + `client/lib/services/cli/<cli>/<cli>_tool.dart` | `claude/claude_tool.dart`（最全）、`flashskyai/flashskyai_tool.dart`（最简） |
| 1 | history capability | `<cli>/capabilities/history/ai_history_capability.dart` + `ai_transcript.dart`（+ `side_resolver.dart`、enricher） | `claude/capabilities/history/`（ai_history_capability.dart + ai_transcript.dart + compatible_jsonl.dart）；`opencode/capabilities/history/`（SQLite 增量范例） |
| 2 | tool call resolvers | `<cli>/capabilities/tool_call_resolvers.dart` | 共享层 `registry/capabilities/shared_tool_call_resolvers.dart`；`cursor/`（追加覆写）、`opencode/`（全自定义） |
| 3 | 注册 | `registry/built_in_cli_tools.dart`（+ `cli_bootstrap.dart` entry，如需注入服务） | 既有 5 个 `registry.register(...)` + `CliTool.values` 遍历的完备性断言 |
| 4 | 测试 | `client/test/services/cli/registry/...` + `client/test/fixtures/session_history/<cli>/` | `message_layer_contract_test.dart`、`line_append_test.dart`、`cursor_tool_call_resolvers_test.dart`、`claude_ai_transcript_test.dart` |
| 5 | 文档 | `docs/cli-formats/<cli>.md` + `tool-layer-coverage.md` + `message-layer-audit.md` + `README.md` | 5 个既有格式页（claude.md / codex.md / opencode.md / cursor.md / flashskyai.md） |

---

## Step 0: CliTool 枚举 + 目录 + tool 定义

**文件**

- `client/lib/models/team_config.dart:19` — `enum CliTool { claude('claude'), … }`；新增 `newcli('newcli')`。附带静态辅助 `decode` / `tryParse` / `parse`（`CliTool.values` 遍历匹配 `value`，无需改动）。
- `client/lib/services/cli/<cli>/<cli>_tool.dart` — tool 定义（新增目录 `capabilities/history/`，provider 子层按需）。
- 可选：`client/lib/services/cli/registry/cli_tool_id.dart` 是 `team_config.dart` 的 `CliTool` re-export shim，新增枚举无需改它。

**接口签名要点**（`registry/cli_tool_definition.dart`）

```dart
abstract interface class CliToolDefinition {
  CliTool get id;
  bool get isLaunchSupported;
  Iterable<CliCapability> get capabilities;
}
```

- `final class NewcliCliTool implements CliToolDefinition`：各能力为 final 字段 + const 默认构造参数（可注入、可测），`capabilities` getter 枚举全部字段；`isLaunchSupported => true` 表示可 launch。
- 能力组合（capability pattern）见 `docs/cli-architecture.md`；本文第 1/2 步只涉 `AiHistoryCapability` 一个（四个 tool call resolver getter 已收编其中）。

**对照文件**

- 完整范例：`claude/claude_tool.dart`（14 功能域能力：provider / session / teamBehavior / chatInteraction / terminalBehavior / plugin / executable / mcp / prompt / headless / aiHistory / skill / hook / memberConfigInspection）。
- 最简参考：`flashskyai/flashskyai_tool.dart`；其余 `codex/codex_tool.dart`、`opencode/opencode_tool.dart`、`cursor/cursor_tool.dart`。

**验证命令**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

注册完备性由断言自动覆盖（Step 3）：枚举新增而未注册时，`CliTool.values.every((cli) => registry.tryGet(cli) != null)` 直接 assert 失败（`built_in_cli_tools.dart:95-98`）。

---

## Step 1: history capability（transcript 定位 / 解析 / 增量 / 子代理 / 回填）

**文件**

- 共享接口：`client/lib/services/cli/registry/capabilities/ai_history_capability.dart`
- 实现：`client/lib/services/cli/<cli>/capabilities/history/ai_history_capability.dart`
- 解析器：`<cli>/capabilities/history/ai_transcript.dart`（`AiTranscriptAdapter` 实现 + `locate*` 函数）
- 子代理 side resolver：`<cli>/capabilities/history/side_resolver.dart`（共享接口 `registry/capabilities/history/subagent_side_resolver.dart`）
- 结果回填 enricher：`<cli>/capabilities/history/*_tool_result_enricher.dart`（共享接口 `registry/capabilities/history/tool_result_enricher.dart`）

**接口签名要点**（`registry/capabilities/ai_history_capability.dart`）

```dart
abstract interface class AiHistoryCapability implements CliCapability {
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx);
  AiTranscriptAdapter get adapter;
  AiTranscriptLineAppend? get lineAppend;        // null = 无法逐行增量（如 opencode SQLite）
  String get tailFallbackPrefix;                 // 必须与 adapter fallback '$prefix-${seq}' 一致
  Set<String> get subagentToolNames;             // lowercase 工具名
  SubagentSideResolver get subagentSideResolver;
  ToolResultEnricher get toolResultEnricher;
  Future<String?> liveCacheToken(ctx);           // 可选；null → loader 默认 pinned-transcript probe
}

typedef AiTranscriptLineAppend = bool Function(
  List<AiMessage> messages,
  Map<String, dynamic> event, {
  required String Function() fallbackId,
}); // 返回 true = 该事件被消费（产生/修改了消息）
```

- **locate**：返回 `AiTranscriptBundle(adapterId: '<cli>', fragments: [...])`。JSONL 族用共享 `probePinnedTranscript`（`registry/capabilities/resume/pinned_transcript_probe.dart`，claude `layoutSegments: ['projects']` 范例；flashskyai 双探针 `['projects','workspaces']`）；SQLite 族（opencode）走 `id > afterMessageId` 增量 locate + `AiTranscriptIncrementalCapability`（同一文件内 `AiTranscriptIncrementalRefresher`，`createState` / `seedFromFullParse` / `refresh` 三钩子）。
- **adapter**：`final class NewcliAiTranscriptAdapter implements AiTranscriptAdapter`，`adapterId: '<cli>'` 必须非空（`session_history_registration_test.dart` 断言 `cap.adapter.id` 非空）。
- **增量/全量 id 一致性（最高优先级约束）**：`lineAppend` 只消费"解析成功"的行（快照/元数据事件返回 false、不推锚点、不消耗 fallback 序号）；fallback id 惰性求值；`tailFallbackPrefix` 必须与 adapter 全量 parse 的 `'$prefix-${seq}'` 完全一致——增量与全量（或重建）产出同一 id 序列。范例：claude `'claude'`、codex `'codex'`、cursor `'cursor'`、flashskyai `'flashskyai'`；opencode 无 fallback（id = db 行 id，天然一致，`lineAppend=null`）。
- **subagentToolNames**：lowercase 精确匹配。范例：claude `{'agent','task','workflow'}`、codex `{'spawn_agent','agent','task'}`（真实数据为裸名，`multi_agent_v1.` 前缀零命中）、cursor `{'agent','task'}`、opencode `{'task'}`。
- **enricher**：parse 为 result 第一通道，enricher 仅补"缺失结果"。四类范例：`ClaudeCompatibleToolResultEnricher`（截断占位回填，claude/flashskyai 共享）、`CursorTerminalToolResultEnricher`（`terminals/*.txt` 回填）、`OpencodeToolOutputBackfillEnricher`（`tool-output/` 全量文件回填，子项目 Task 6 实现，见 [truncation-backfill-audit.md](truncation-backfill-audit.md)）、`NoOpToolResultEnricher`（codex——已调研不可行）。
- 实现惯例：const 类 + 构造参数注入 `subagentSideResolver` / `toolResultEnricher`（可测）；cursor 另注入 `shellResolver`。

**对照文件**

- 完整：`claude/capabilities/history/ai_history_capability.dart` + `ai_transcript.dart`（`locateClaudeTranscript`）+ `compatible_jsonl.dart`（`appendClaudeJsonlEvent` 共享 lineAppend）。
- SQLite 增量：`opencode/capabilities/history/ai_history_capability.dart` + `ai_transcript.dart`（`liveCacheTokenImpl` 注入 + store 级指纹）。

**验证命令**

```bash
cd client && flutter test test/services/cli/registry/session_history_registration_test.dart \
  test/services/cli/registry/ai_history_capability_wiring_test.dart
```

---

## Step 2: tool call resolvers（edit / file / shell / category）

**文件**

- 共享层：`client/lib/services/cli/registry/capabilities/shared_tool_call_resolvers.dart`
- 实现：`client/lib/services/cli/<cli>/capabilities/tool_call_resolvers.dart`（追加配置）
- 载体接口：`registry/capabilities/ai_history_capability.dart`

**接口签名要点**（2026-08-14 起收编进 `AiHistoryCapability`，`ai_history_capability.dart:162-165`）

```dart
abstract interface class AiHistoryCapability implements CliCapability {
  // ... transcript 定位/解析面 ...
  AiEditToolTargetResolver get editResolver;
  AiToolFileTargetResolver get fileResolver;
  AiShellToolTargetResolver get shellResolver;
  AiToolCallCategoryResolver get categoryResolver;
}
```

- 共享层提供 `SharedToolCallResolverKeys`（edit/write/diff/file/shell 的**工具名 + 参数键**常量集）与 `SharedToolCallResolvers`（str-replace / write / unified-diff 三 codec + file 规则 + shell 名集 + `defaultToolCallCategoryResolver`）。
- **治理标准**（`shared_tool_call_resolvers.dart:14-23`）：共享键集内每个名字必须**真正跨 CLI 共享**（矩阵证据 ≥ 2 个 CLI：src / fixture / 本机 / `spl@93c9991`）；单 CLI 名字下沉到该 CLI 的 resolver 文件、以**追加**方式挂到共享键集之上（不替换）；无发射证据的名字不进共享集（tool-layer-coverage G-1..G-6 全部由此治理）。
- 三种实现模式：
  1. **无 delta**：`class NewcliToolCallResolvers extends SharedToolCallResolvers`（claude / flashskyai 范例，约 6 行）。
  2. **追加覆写**：`extends SharedToolCallResolvers` + `_editToolNames = {...SharedToolCallResolverKeys.editToolNames, 'strreplace', 'editnotebook'}` 等，并 override 各 getter（cursor 范例：追加 `path` / `contents` 键）。
  3. **全自定义**：`extends SharedToolCallResolvers` + 全套覆写 getter，共享键集仅作常量引用（opencode 范例：追加 camelCase `filePath` / `oldString` / `newString`）。

**对照文件**

- `claude/capabilities/tool_call_resolvers.dart`、`flashskyai/capabilities/tool_call_resolvers.dart`（模式 1）
- `cursor/capabilities/tool_call_resolvers.dart`（模式 2，追加语义）
- `opencode/capabilities/tool_call_resolvers.dart`（模式 3）

**验证命令**

```bash
cd client && flutter test test/services/cli/registry/capabilities/shared_tool_call_resolvers_test.dart \
  test/services/cli/registry/capabilities/tool_call_resolvers_test.dart \
  test/services/cli/registry/capabilities/tool_call_category_mapping_test.dart
```

（cursor/opencode 各自还有 `cursor_tool_call_resolvers_test.dart` / `opencode_tool_call_resolvers_test.dart`。）

---

## Step 3: 注册

**文件**

- `client/lib/services/cli/registry/built_in_cli_tools.dart` — `registerBuiltInCliTools`
- 如需注入服务：`registry/cli_bootstrap.dart`（Map 驱动） + `<cli>_bootstrap_entry.dart`

**要点**

```dart
final newcliEntry = bootstrap.entry<NewcliBootstrapEntry>(CliTool.newcli); // 无注入服务可省略
registry.register(NewcliCliTool(/* 注入参数 */));
```

- 注册后由 `CliTool.values` 遍历的断言**自动覆盖完备性**（新增枚举不注册即 fail）：
  - `CliTool.values.every((cli) => registry.tryGet(cli) != null)`（`built_in_cli_tools.dart:95-98`）
  - `registry.all.length == CliTool.values.length`（不许注册多余定义）
  - 全员必带：`ProviderCapability`、`MemberConfigInspectionCapability`
  - `_verifyRequired<T>`：`CliSessionCapability` / `TeamBehaviorCapability` / `ProviderCapability` / `CliExecutableCapability` / `TerminalBehaviorCapability` / `PluginCapability` / `ChatInteractionCapability`
  - `_verifyNativeTeamRegistration` / `_verifyMemberAgentPresetRegistration`：**allowed 集 = {claude, flashskyai}**——新 CLI 不得注册 `TeamBehaviorCapability.supportsNativeTeam` / `agentPresetStyle`（原生团队 / agent 预设），除非显式加入 allowed 集（否则 `StateError`）
- 依赖反转：launchable 定义里的 `CliAssetRegistry` 能力自动 collect（`built_in_cli_tools.dart:89-93`）。
- Bootstrap entry 模式：`bootstrap.entry<T>(cli)`（`cli_bootstrap.dart:23`），`CliBootstrap` Map 驱动——新增 CLI 不改 `CliBootstrap` 类（`cli-architecture.md:418-425` 旧/新模式对照）。
- 显示名：`registry/cli_display_name.dart` `cliDisplayName(def, l10n)` 经 `CliExecutableCapability.label`，fallback `CliTool.value`。

**对照文件**

- `claude/claude_tool.dart` + `claude/claude_bootstrap_entry.dart` + `built_in_cli_tools.dart:41-55`（claude 注册：`providerCredential` 经 entry 注入、`busIdleHooks` const）
- `flashskyai/flashskyai_tool.dart` + `built_in_cli_tools.dart:84-86`（无注入服务的最简注册）

**验证命令**

```bash
cd client && flutter test test/services/cli/registry/
```

（断言在 `registerBuiltInCliTools` 调用时执行，任何注册测试都会触发。）

---

## Step 4: 测试（契约 + resolver 单测 + 夹具）

**文件**

- 契约：`client/test/services/cli/registry/capabilities/history/message_layer_contract_test.dart`
- 增量一致性：`.../history/line_append_test.dart`
- adapter 单测：`.../history/<cli>_ai_transcript_test.dart`（opencode 另有 `opencode_history_full_vs_incremental_test.dart`）
- resolver 单测：`client/test/services/cli/registry/capabilities/<cli>_tool_call_resolvers_test.dart`
- wiring：`client/test/services/cli/registry/session_history_registration_test.dart`、`ai_history_capability_wiring_test.dart`
- 夹具：`client/test/fixtures/session_history/<cli>/`

**要点**

- **契约测试**（`message_layer_contract_test.dart` `checkContract`）：消息 id 非空且唯一；toolCallId / toolName 非空；`args` 必须 Map 或 null（**不得是裸字符串**）；有 result 的 tool call 不得 `running`；文本 part 非空；夹具须含 ≥1 工具调用；`finalizeAiMessagesForHistory` 后消息级 status 恒 `complete`（G6b 裁决，`message-layer-audit.md` Gap 清单）。
- **增量一致性**（`line_append_test.dart`）：`_expectedConsumed` 按 `CliTool` 键控的逐行消费期望表；增量重放（lineAppend + finalize）与全量 parse 产出同 id 序列、零分叉。
- **夹具纪律**（G-4/G-5 教训，见 `tool-layer-coverage.md`）：夹具必须基于**真实数据**并脱敏（redact commit `22790cb4`）；无发射证据**不捏造**夹具；扫描范围要覆盖子目录（flashskyai 补扫 `subagents/` 才找到真实 Edit 证据）。全链路断言：fixture → adapter → resolver（工具行全部解析出 hunk / target）。
- 注册完备性（Step 3 断言）与 wiring 测试对新 CLI **自动生效**——注册即被覆盖，无需额外用例（除非有 CLI 专属行为要固化）。

**验证命令**

```bash
cd client && flutter test test/services/cli/registry/
```

---

## Step 5: 文档

**文件**

- 格式参考页：`docs/cli-formats/<cli>.md`（新增；对照 5 个既有页结构：transcript 位置 / 文件格式 / 消息 schema / 解析入口 / 增量能力 / **已知陷阱** 章节）
- 工具层覆盖矩阵：`docs/cli-formats/tool-layer-coverage.md`（矩阵加一行，5 类别 × 新 CLI；证据引用四方证据源：src / fixture / 本机 / `spl@93c9991`）
- 消息层矩阵：`docs/cli-formats/message-layer-audit.md`（矩阵加一列；引用行号以源码为准，先 grep 回验）
- 总览：`docs/cli-formats/README.md`（总览矩阵加一行：transcript 位置 / 解析入口 / 增量能力 / 状态）
- 本文（接入清单）持续维护

**验证命令**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart
```

---

## 已知陷阱速查

各 CLI 的完整陷阱清单见各自格式页的「已知陷阱」章节：`claude.md:84` / `codex.md:74` / `cursor.md:93` / `flashskyai.md:102` / `opencode.md:131`；版本 caveat 见 `message-layer-audit.md:53`（本机快照核验，CLI 升级后需重开核验）。共性归纳：

1. **增量/全量 id 序列一致性**：`tailFallbackPrefix` 必须与 adapter 全量 fallback `'$prefix-${seq}'` 一致 + fallback 惰性求值（被丢弃事件不占号）——否则 UI 增量与全量出现不同消息条数（5 家断言锁定，D10 闭环）。
2. **lineAppend 消费语义**：只消费解析成功的行（claude：user/assistant 消息、tool 块；codex：event_msg + response_item 子集），快照/元数据/环境噪音行返回 false——不推锚点、不消耗 fallback 序号（codex 的 `session_meta` / `token_count` 等）。
3. **args 形态契约**：args 恒 Map 或 null——字符串参数先 jsonDecode（codex `_parseArgs`），非 JSON → `args=null` 且 `argsText` 保留原串（codex freeform）；`custom_tool_call.input` 双形态（String/Map）是 codex 独有坑（P3 已补：Task 5 commit `75f4cd4b`，夹具 `custom_tool_call_dual_form.jsonl` String patch + Map input 双形态 + 端到端断言）。
4. **result 回填分层**：parse 为第一通道、enricher 仅补缺失（claude 截断 sentinel / cursor `terminals/*.txt` / opencode `tool-output/` 文件回填）；codex 保持 `NoOpToolResultEnricher`——截断输出无回填机制（已调研：不可行，截断即永久）。调研结论与 opencode 实现见 [truncation-backfill-audit.md](truncation-backfill-audit.md)。
5. **夹具纪律**：真实数据 + 脱敏（redact commit `22790cb4`）；无发射证据不捏造（G-5 教训：初判"无 Edit 证据"实为扫描范围遗漏 `subagents/` 子目录）；多 project 目录 / 子目录形态都要扫。
6. **id 优先级各异，不得互读**：claude `message.id` → `uuid` → fallback；cursor `uuid` → `id` → `message.id` → fallback（与 Claude 相反）；opencode id = db 行 id 无 fallback——新增 CLI 先确定自己的优先级链并断言固化。
7. **category 跨 CLI 统一**：同语义工具跨 CLI 归类必须一致（G-3 / Task 6 裁决：`question`→`askUser` 与 cursor `AskQuestion`、claude `askuserquestion` 统一）——新增工具名先查 `tool_call_categories.dart` 共享表再决定放共享还是下沉。
8. **注册 allowed 集**：`TeamBehaviorCapability` 的 `supportsNativeTeam` / `agentPresetStyle` 只允许 {claude, flashskyai}——新 CLI 不要盲加这两个行为。

---

## 验证全链路（收尾）

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && dart run tool/run_tests.dart
```

接入清单对应的验收依据：6 个接入点全部有真实文件路径 + 接口签名（grep 可回验）；文档矩阵与测试断言同步更新。
