# CLI 消息格式与工具调用解析统一体系设计

**日期:** 2026-08-12
**状态:** 已批准（待实现）

## 背景

仓库已存在两层解析体系骨架：

- **消息层**：`ai_message_core`（`AiMessage` / `AiMessagePart` / `AiToolCallPart`，纯接口 + 纯数据）→ 每 CLI 在 `client/lib/services/cli/<cli>/capabilities/history/` 提供 `AiTranscriptAdapter` + `AiHistoryCapability`（locate / adapter.parse / lineAppend / subagent / result 增强），会话层有 `AiHistoryLoader`、`AiHistoryLiveRefreshController`
- **工具层**：`ToolCallResolversCapability` + `SharedToolCallResolvers` + 各 CLI 的 `*ToolCallResolvers`（当前嵌在 `*_tool.dart`，与约定文档目录不符）

痛点（用户确认"都有"）：

1. **可扩展性不清晰**——新增 CLI 时不知道要接哪些点，接入点分散在多个文件
2. **解析覆盖不全**——5 个 CLI × 各解析类别存在缺口，未逐项验证
3. **缺格式参考文档**——各 CLI 原生格式（Claude JSONL / opencode sqlite / Codex history.json 等）没有系统梳理，知识散落在代码里

用户明确决策：**按最优架构与可扩展性来，不考虑工作量**；范围覆盖全部五个 launch 支持 CLI（claude / codex / opencode / cursor / flashskyai）；统一模型沿用现有 `AiMessage`，不重建 schema；格式参考采用 **md 手册 + 测试校验**（非机器生成代码）。

## 总体架构（方案 A — 现有骨架上系统性补齐）

```
┌─ 统一模型层 ──────────────────────────────────────────────┐
│  ai_message_core：AiMessage / AiMessagePart / AiToolCallPart │
│  （保持纯接口 + 纯数据，零 CLI 硬编码，零实现）               │
└────────────────────────────────────────────────────────────┘
             ▲                      ▲
   消息层     │                      │ 工具层
┌────────────┴────────────┐  ┌──────┴──────────────────────┐
│ per-CLI capabilities/   │  │ per-CLI capabilities/       │
│  history/               │  │  tool_call_resolvers.dart   │
│  · AiTranscriptAdapter  │  │  · 每 CLI 独立 resolver 文件 │
│  · AiHistoryCapability  │  │  · SharedToolCallResolvers  │
│  （locate/lineAppend/   │  │    + 每 CLI 覆盖             │
│    subagent/result 增强）│  │                            │
└─────────────────────────┘  └─────────────────────────────┘
             ▲                      ▲
             └──────┬───────────────┘
                    │ 单一事实来源（人读手册）
┌───────────────────┴───────────────────┐
│  docs/cli-formats/ 格式参考库（md）      │
│  · README.md 总览矩阵                   │
│  · 每 CLI 一页：原生格式 + 消息/工具 schema │
│  · adding-a-cli.md 接入清单             │
└────────────────────────────────────────┘
        ▲ 测试校验（client/test/cli_format/）
        │ · 能力完备性：每个 CliTool 都注册了
        │   AiHistoryCapability + ToolCallResolversCapability
        │ · 配置快照：resolver 映射变化时 golden diff 驱动文档更新
```

原则：

- 统一模型层不改 schema，只按审计结果补齐缺失字段
- 消息层与工具层都收敛到 `capabilities/` 目录，与 `tool-call-parsing-convention.md` 对齐
- 文档是人读手册（md 表格手动维护）；测试是结构性校验（注册完备性 + 映射变更感知），不做代码生成

## 消息层设计

### 统一模型（保持现状 + 审计补齐）

| 模型 | 覆盖 | 待审计点 |
|------|------|---------|
| `AiMessage` | id / role / parts / createdAt / status / deliveryChannel | 是否缺 session 元数据（如 CLI 版本、cwd） |
| `AiTextPart` | 文本 | — |
| `AiReasoningPart` | thinking | 各 CLI reasoning 字段名差异（`reasoning` / `thinking` / encrypted） |
| `AiToolCallPart` | id / name / args(Map) / argsText / result / status / isError / category | args 是结构化还是纯文本（如 Cursor 纯 JSON 文本）；result 是否含结构化 payload |
| `AiSubagentAttachment` | 子代理附件 | 已存在，随 adapter 复用 |

### 每 CLI 解析职责（现有 `capabilities/history/` 结构不变）

- `locate()` — 定位原生 transcript（Claude JSONL / opencode sqlite / Codex history.json / Cursor / FlashskyAI）
- `adapter.parse()` — 全量解析 → `List<AiMessage>`
- `lineAppend` — 增量逐事件追加（无增量能力的 CLI 如 opencode 走全量回退，语义零分叉）
- `subagentToolNames` / `subagentSideResolver` / `toolResultEnricher` — 子代理与结果增强
- `tailFallbackPrefix` — 增量/全量消息 id 一致性

### 本轮动作

1. **差异矩阵先行**：内部审计表（每 CLI × AiMessage 字段），找出"哪个 CLI 哪个字段没解析/解析错"——这是格式参考库每页 md 的核心内容
2. **按矩阵补齐 adapter**：逐 CLI 修正，保证 5 个 CLI 产出同一语义的 AiMessage（相同 tool call 渲染结果一致，不管来自哪个 CLI）
3. **统一模型补字段**：矩阵审计若发现公共缺失（如 result 结构化 payload），在 `ai_message_core` 补字段并同步 adapter
4. **消息 id 序列**：保持增量/全量同 id（`tailFallbackPrefix` 已约束），作为回归测试断言之一

## 工具层设计

### 接口（保持 `ToolCallResolversCapability` 不变）

| 类别 | 解析器 | 现状 |
|------|--------|------|
| Edit | `AiEditToolTargetResolver`（codec 链：strReplace / write / unifiedDiff） | Shared 已有，每 CLI 覆盖待审计 |
| File | `AiToolFileTargetResolver`（tool names + path keys + 行号规则） | 同上 |
| Shell | `AiShellToolTargetResolver` | 同上 |
| Subagent | `AiHistoryCapability.subagentToolNames` | 已有 |
| Category | `AiToolCallCategory` 注解 | 已有（opencode camelCase 已做过） |

### 本轮动作

1. **文件迁移**：~~每 CLI 的 `*ToolCallResolvers` 从 `*_tool.dart` 迁出到各自 `capabilities/tool_call_resolvers.dart`~~ **已完成**（`9ec6a935`，5 个 CLI 均已有独立 resolver 文件，`*_tool.dart` 只保留装配）
2. **覆盖矩阵补齐**：5 CLI × 5 解析类别矩阵逐格验证，证据源为**四方**：
   - ① adapter / resolver 源码（`capabilities/history/` + `capabilities/tool_call_resolvers.dart`）
   - ② 测试夹具（`client/test/fixtures/session_history/<cli>/`）
   - ③ 本机真实数据（各 CLI 数据目录扫描）
   - ④ **外部参考：[asgeirtj/system_prompts_leaks](https://github.com/asgeirtj/system_prompts_leaks)**（CC0 许可，62k+ stars，定期更新）——各 CLI 泄露系统提示中的**工具 JSON schema** 是参数 key 的权威来源（claude/codex/opencode/cursor 四家可对照；flashskyai 闭源无）。引用时固定 `@<commit>` 或快照日期，并在 `docs/cli-formats/README.md`「外部参考」节登记
   - 验证维度：edit tool name / path / oldString / newString key 覆盖全；shell 命令、file 路径 key 无遗漏别名；category 注解与真实工具名匹配
3. **SharedToolCallResolvers 治理**：共享层只留真实共用的映射；CLI 特有的一律下沉到各自文件（追加而非覆盖，兼容旧会话——沿用 opencode camelCase 模式的追加语义）
4. **对外入口**：`CliToolRegistry.toolCallResolvers(cli)` 保持为唯一查询入口，UI 不新增 `if (cli == ...)`
5. **新 CLI 预研（可选）**：Gemini CLI / Antigravity CLI 的系统提示可作为未来接入的预研素材，产出「潜在接入点」小结

## 格式参考库

```
docs/cli-formats/
  README.md          # 总览矩阵：5 CLI × 存储位置/文件格式/解析入口/覆盖状态
  claude.md          # 每页：transcript 位置与格式、消息 schema、
  codex.md           #      工具调用 schema（tool name 表 + arg key 表）、
  opencode.md        #      reasoning/subagent 形态、增量 vs 全量、已知陷阱
  cursor.md
  flashskyai.md
  adding-a-cli.md    # 接入新 CLI 的分步清单（含接入点）
  message-layer-audit.md  # 消息层差异矩阵（子项目 2 产出）
  tool-layer-coverage.md  # 工具层覆盖矩阵（子项目 3 产出）
```

每页 md 的"工具调用 schema"表格是代码注释的权威来源——评审人看 md，改代码对照 md。
「外部参考」：`README.md` 登记 [system_prompts_leaks](https://github.com/asgeirtj/system_prompts_leaks)（CC0）为工具 schema 的第四方证据源，引用时固定快照 commit/日期。

## 测试校验

`client/test/cli_format/`：

1. **能力完备性**：断言每个 `CliTool` 都注册了 `AiHistoryCapability` + `ToolCallResolversCapability`（新增 CLI 漏接立即红）
2. **映射快照**：把每个 CLI 的 resolver 配置（tool name 集合 + arg key 列表）序列化，与 golden 快照对比——任何映射变更 diff 可见，提醒同步文档
3. **id 一致性**：增量 lineAppend 与全量 parse 产出消息 id 序列一致（有 tailer 的 CLI）
4. **新增 CLI 冒烟**：按 adding-a-cli.md 走一遍的最小断言（注册完备性测试自动覆盖新 CliTool 定义）

## 约定文档更新

- `docs/tool-call-parsing-convention.md`：补一节指向 `docs/cli-formats/` 作为格式事实来源
- `docs/cli-architecture.md`：补解析接入点说明

## 实施顺序

每个子项目独立 plan，可独立验证（analyze + test）：

1. 格式参考库：调研 5 个 CLI 原生格式 → 写 md（消息层差异矩阵 + 工具层覆盖矩阵从这产出）
2. 消息层审计补齐：按矩阵改 adapter
3. 工具层迁移 + 补齐：~~resolver 迁文件~~（已完成 `9ec6a935`）+ 覆盖矩阵逐格验证（已完成，含 system_prompts_leaks 四方证据源与共享层治理）
4. 测试校验 + 新增 CLI 清单落地：**并含已知陷阱优化**——codex/opencode 截断输出回填调研（P1/P2，先调研真实形态再决定实现/文档化）+ codex custom_tool_call.input 夹具补全（P3）
5. 约定文档收尾

## 验证

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test --exclude-tags integration
```
