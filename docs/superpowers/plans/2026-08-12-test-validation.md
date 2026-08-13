# 测试校验 + 接入清单实施计划（子项目 4/5）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立解析体系的校验闭环（能力完备性 + 映射快照 + id 一致性测试审计补齐）、产出 `adding-a-cli.md` 接入清单、并调研/优化两个已知陷阱（codex / opencode 截断输出无回填）与补 codex 夹具缺口。

**Architecture:** 文档先行（Task 1 adding-a-cli.md），测试审计补齐（Task 2-3，基于子项目 2/3 已固化的断言体系做覆盖审计，不重复建设），陷阱调研（Task 4 真实数据形态调查 → 可行性结论），低风险夹具先做（Task 5），按结论实现或文档化（Task 6），收尾全量验证（Task 7）。

**Tech Stack:** Dart / flutter_test / `CliToolRegistry` / `AiHistoryCapability` / `ToolCallResolversCapability` / 各 CLI enricher / 测试夹具。

## Global Constraints

- **不重复建设**：子项目 2 已产出契约测试（`message_layer_contract_test.dart`）、Task 5 已产出 exact-set 断言（`shared_tool_call_resolvers_test.dart` 18 块钉死治理后集合）与注册完备性断言（`ai_history_capability_wiring_test.dart` 遍历 `CliTool.values`）。本子项目的测试工作 = **审计覆盖缺口 + 补齐**，不是新建平行体系
- **快照机制裁决**：映射快照 = 既有 exact-set 断言（对治理后集合的精确钉死，等价 golden，且带失败信息）——除非审计发现缺口（如某 CLI 无 exact-set 覆盖），否则不引入 JSON 快照文件
- **调研结论驱动**：P1/P2（截断回填）先调研真实数据形态再决定实现/文档化；禁止在无证据时实现 enricher
- 回归：契约测试 + 全部 resolver 单测全绿；不改消息层 adapter（enricher 属既有扩展点，实现时不动 parse 主路径）
- 验证命令：`cd client && flutter test <具体测试文件>`；收尾 `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`（10 个已知 pre-existing 失败除外）
- commit 沿用仓库规范：`docs(cli-formats): <desc>` / `test(history): <desc>` / `feat(history): <desc>` / `fix(history): <desc>`
- 执行在隔离 worktree：`.worktrees/test-validation`（分支 `test-validation`）

---

### Task 1: adding-a-cli.md 接入清单

**Files:**
- Create: `docs/cli-formats/adding-a-cli.md`
- Modify: `docs/cli-formats/README.md`（「新增 CLI」节指向生效）

**Interfaces:**
- Consumes: 子项目 1-3 全部产出（格式库 5 页、消息层矩阵、工具层覆盖矩阵、注册完备性断言）
- Produces: 接入清单文档（子项目 5 与未来 CLI 接入的指引）

- [ ] **Step 1: 梳理接入点**

从既有 5 个 CLI 的实现归纳接入点（对照 `client/lib/services/cli/claude/` 作为完整范例），至少覆盖：
1. **CliTool 定义**：`client/lib/services/cli/registry/tools/` 或各 CLI 目录的 `<cli>_tool.dart`（`CliToolDefinition` + 枚举值）
2. **history capability**：`capabilities/history/`（`AiHistoryCapability`：locate / adapter / lineAppend / tailFallbackPrefix / subagentToolNames / enricher）
3. **tool call resolvers**：`capabilities/tool_call_resolvers.dart`（共享常量 + CLI 特有追加，追加语义）
4. **注册**：`CliToolRegistry.builtIn()` 注册 + 注册完备性断言自动覆盖（`CliTool.values` 遍历）
5. **测试**：契约测试用例 + 各 CLI resolver 单测 + 夹具（`client/test/fixtures/session_history/<cli>/`）
6. **文档**：格式参考页 + 覆盖矩阵 + 消息层矩阵 + 本清单

- [ ] **Step 2: 写清单文档**

`docs/cli-formats/adding-a-cli.md`：分步清单（Step 0 新增 CliTool 枚举 → Step N 文档），每步给出文件路径、接口签名要点、验证命令、与既有 CLI 的对照文件。末尾附「已知陷阱速查」（引用 5 页的 已知陷阱 章节 + 子项目 4 新增结论）。

- [ ] **Step 3: 更新 README + 提交**

README「新增 CLI」节改为指向已落地的 adding-a-cli.md。

```bash
git add docs/cli-formats/adding-a-cli.md docs/cli-formats/README.md
git commit -m "docs(cli-formats): add adding-a-cli guide"
```

---

### Task 2: 能力完备性 + 映射快照审计补齐

**Files:**
- Review: `client/test/services/cli/registry/ai_history_capability_wiring_test.dart`、`client/test/services/cli/registry/capabilities/shared_tool_call_resolvers_test.dart`、`client/test/services/cli/registry/capabilities/tool_call_resolvers_test.dart`
- Test（按缺口）: 上述文件或新增

**Interfaces:**
- Consumes: 子项目 3 Task 5 的断言体系
- Produces: 覆盖审计结论 + 补齐的断言

- [ ] **Step 1: 能力完备性审计**

读 `ai_history_capability_wiring_test.dart`，核对：每个 `CliTool` 是否断言了 `AiHistoryCapability` 与 `ToolCallResolversCapability` 双注册 + 四解析器非空。列出缺口（如有：某 CLI 缺某侧断言）。

- [ ] **Step 2: 映射快照审计**

读 `shared_tool_call_resolvers_test.dart` 与各 CLI resolver 单测，核对每个 CLI 的**生效映射集**（共享 + CLI 特有合并后）是否有 exact-set 钉死。特别检查：opencode（Task 4 追加过 camelCase 键）、cursor（Task 3/5 下沉过 edit/file/shell 键）的合并后集合是否被精确钉死。缺口 → 补断言。

- [ ] **Step 3: 验证 + 提交**

```bash
cd client && flutter test test/services/cli/registry/ test/services/cli/registry/capabilities/
```

有缺口才提交：`git commit -m "test(history): completeness audit assertions"`；无缺口在报告记录「审计通过，无新增」。

---

### Task 3: id 一致性测试补齐

**Files:**
- Review: `client/test/services/cli/registry/capabilities/history/line_append_test.dart`、`message_layer_contract_test.dart`、各 CLI history 测试
- Test（按缺口）: 上述文件或新增

**Interfaces:**
- Consumes: 子项目 2 的 id 一致性机制（`tailFallbackPrefix` + 增量/全量同源）
- Produces: 5 CLI 增量/全量 id 序列一致的测试覆盖

- [ ] **Step 1: 覆盖审计**

对 5 个 CLI 逐一核对：是否有「增量 lineAppend 与全量 parse 产出**相同 id 序列**」的断言（不是各自独立测试，而是对比断言）。已知：line_append_test.dart 有 claude/codex/cursor/flashskyai 的方言测试；opencode 走 sqlite 增量 locate（`id > afterMessageId` 窗口 = 全量子集断言已有）。列出每 CLI 的缺口。

- [ ] **Step 2: 补齐缺口**

对缺对比断言的 CLI 补：同一夹具 → 全量 parse 得 id 序列 A；逐行 lineAppend 得 id 序列 B；断言 A == B（或 opencode 的窗口子集语义）。**复用既有夹具，不新建数据。**

- [ ] **Step 3: 验证 + 提交**

```bash
cd client && flutter test test/services/cli/registry/capabilities/history/
git commit -m "test(history): id sequence parity assertions"
```

（无缺口则报告记录，不提交。）

---

### Task 4: 截断回填调研（P1 codex + P2 opencode）

**Files:**
- Create: `docs/cli-formats/truncation-backfill-audit.md`（调研结论）
- Research sources: 各 CLI 真实数据（`~/.codex/sessions`、`~/.local/share/opencode/opencode.db`）、adapter 源码、现有 enricher（`ClaudeCompatibleToolResultEnricher` 作为对照）

**Interfaces:**
- Consumes: 已知陷阱（codex/opencode 无截断回填）
- Produces: 可行性结论（实现方案 / 不可行原因），Task 6 按此执行

- [ ] **Step 1: codex 截断形态调查**

在 `~/.codex/sessions` 扫描：工具输出被截断的记录长什么样？关键问题：
1. `function_call_output` 的 `output` 里截断占位文本（如 `... truncated` / `[output truncated]`）出现时，**同会话是否有完整输出的副本**（如 rollout 其他字段、日志文件）？
2. codex 是否存在 `call_id` 关联的扩展字段（如 `usage`、`truncation` 标记）？

结论落文档：可实现（有副本可回填）/ 不可行（无副本，截断即永久）。

- [ ] **Step 2: opencode 截断形态调查**

在 `~/.local/share/opencode/opencode.db` 扫描：`tool` part 的 `state.output` 截断形态 + 同会话是否有完整输出（如 `state` 的其他字段、patch part、日志）。同样三问。注意 `part` 表可能有多行（截断 + 完整并行）。

- [ ] **Step 3: 方案设计**

若可行：设计 enricher（参考 `ClaudeCompatibleToolResultEnricher` 的接口与回填语义——`result` / `status=complete` / `isError` 约定），明确数据来源路径与判定条件（何时回填、何时保持占位）。若不可行：文档化结论 + 建议（如 UI 层展示策略）。

- [ ] **Step 4: 提交调研文档**

```bash
git add docs/cli-formats/truncation-backfill-audit.md
git commit -m "docs(cli-formats): truncation backfill feasibility audit"
```

---

### Task 5: P3 — codex custom_tool_call.input 夹具补全

**Files:**
- Test: `client/test/services/cli/registry/capabilities/history/codex_ai_transcript_test.dart`
- Fixture（如需）: `client/test/fixtures/session_history/codex/`

**Interfaces:**
- Consumes: 已知陷阱「custom_tool_call.input 双形态」（源码有分支、夹具无覆盖）
- Produces: 双形态断言（String → argsText；Map → args）

- [ ] **Step 1: 写双形态断言**

构造两个 `custom_tool_call` 场景（String input / Map input），断言：String → `args=null` + `argsText` 保留（或按 Task 3 修复后的实际语义：JSON 字符串 → args Map）；Map → args Map。以 `_parseArgs`/`_asArgs` 的实际语义为准（子项目 2 Task 3 修复过此分支）。

- [ ] **Step 2: 验证 + 提交**

```bash
cd client && flutter test test/services/cli/registry/capabilities/history/codex_ai_transcript_test.dart
git commit -m "test(history): codex custom_tool_call input dual-form coverage"
```

---

### Task 6: 按调研结论实现截断回填（若可行）

**Files:**
- Modify（若实现）: `client/lib/services/cli/codex/capabilities/history/tool_result_enricher.dart`（或对应 opencode 文件，以 Task 4 结论为准）
- Modify: 对应 CLI 的 history capability 装配（`NoOpToolResultEnricher` → 新 enricher）
- Test: 对应 CLI 测试

**Interfaces:**
- Consumes: Task 4 可行性结论
- Produces: 截断回填实现（若可行）或文档化收尾（若不可行）

- [ ] **Step 1: 若可行 — TDD 实现**

写失败断言（截断占位 → 期望回填完整输出）→ 实现 enricher（复用 `ClaudeCompatibleToolResultEnricher` 的回填语义约定）→ 装配到 history capability → 全绿。enricher 不可用时（无 bundle/无 root 路径）保持占位文本（与 claude 行为一致）。

- [ ] **Step 2: 若不可行 — 文档化收尾**

在 `docs/cli-formats/<cli>.md` 已知陷阱章节更新该条（标注「已调研：不可行 + 原因 + 建议」），并把 `truncation-backfill-audit.md` 结论链接进格式库 README。

- [ ] **Step 3: 提交**

```bash
# 实现路径
git add client/lib/services/cli/ client/test/
git commit -m "feat(history): backfill truncated tool output for <cli>"
# 文档路径
git commit -m "docs(cli-formats): document truncation backfill infeasibility"
```

---

### Task 7: 收尾 — 全量验证 + 矩阵更新

**Files:**
- Modify: `docs/cli-formats/tool-layer-coverage.md`（如有新结论）、`docs/cli-formats/README.md`（链接 truncation audit）
- Review: 全部改动

**Interfaces:**
- Consumes: Task 1-6 全部产出
- Produces: 可交付状态

- [ ] **Step 1: 全量验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`

已知 10 个 pre-existing 失败（cli_config_section ×3、codex_cli_tool_adapter ×2、plugin_provisioning_chain ×3、cli_plugin_layout ×1、app_shell_smoke ×1）——失败文件未被本分支 touch 即判 pre-existing。

- [ ] **Step 2: 更新文档（如有新结论）**

截断调研结论、id 一致性审计结论同步进相关文档。

- [ ] **Step 3: 提交**

```bash
git add docs/cli-formats/
git commit -m "docs(cli-formats): finalize sub-project 4 conclusions"
```

## 完成定义

- [ ] `adding-a-cli.md` 落地（6 个接入点 + 验证命令 + 陷阱速查），README 指向生效
- [ ] 能力完备性 + 映射快照审计结论（每 CLI 生效映射集有 exact-set 钉死），缺口已补
- [ ] 5 CLI 增量/全量 id 序列对比断言覆盖（opencode 为窗口子集语义）
- [ ] `truncation-backfill-audit.md` 产出 codex/opencode 截断形态可行性结论
- [ ] codex custom_tool_call.input 双形态断言
- [ ] Task 6 按结论实现（或文档化）
- [ ] `flutter analyze` + 全量测试通过（10 个 pre-existing 失败除外）
- [ ] 产出可支撑子项目 5（约定文档收尾）
