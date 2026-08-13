# 约定文档收尾实施计划（子项目 5/5）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 收尾两篇约定文档：`docs/tool-call-parsing-convention.md` 对齐实际代码布局（resolver 已迁至 `<cli>/capabilities/`）并指向 `docs/cli-formats/` 作为格式事实来源；`docs/cli-architecture.md` 补解析接入点说明。

**Architecture:** 纯文档子项目（spec 实施顺序第 5 步）。Task 1 更新解析约定文档（目录约定对齐 + 事实来源节），Task 2 更新 CLI 架构文档（解析接入点说明），Task 3 交叉校验（文档 ↔ 代码 ↔ 格式库三方一致）。

**Tech Stack:** Markdown / grep。

## Global Constraints

- 文档语言：中文（与既有约定文档一致）
- **目录约定必须对齐实际代码布局**：per-CLI resolver 在 `client/lib/services/cli/<cli>/capabilities/tool_call_resolvers.dart`（迁移已完成 `9ec6a935` + 子项目 3 治理），`registry/capabilities/` 只留共享层 `SharedToolCallResolvers` 与能力接口
- 事实来源引用：`docs/cli-formats/`（README / 5 页 / message-layer-audit / tool-layer-coverage / adding-a-cli / truncation-backfill-audit）作为格式与覆盖的单一事实来源，两篇约定文档只做指针不做搬运
- 每处引用的文件路径/行号必须真实存在（grep 验证）
- 不修改生产 `.dart` 文件
- 验证：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`（文档改动不影响，跑一遍确认）；交叉校验用 grep
- commit 沿用仓库规范：`docs: <desc>`
- 执行在隔离 worktree：`.worktrees/convention-docs`（分支 `convention-docs`）

---

### Task 1: tool-call-parsing-convention.md 更新

**Files:**
- Modify: `docs/tool-call-parsing-convention.md`

**Interfaces:**
- Consumes: 子项目 1-4 全部产出（格式库、矩阵、adding-a-cli.md）
- Produces: 更新后的解析约定文档

- [ ] **Step 1: 核对现状与实际的偏差**

通读 `docs/tool-call-parsing-convention.md`（155 行），用 grep 对照实际代码，列出所有过时表述。已知偏差（以实际代码为准核验）：
- 「目录约定」节：`registry/capabilities/` 下的 `claude_tool_call_resolvers.dart` 等 → 实际在 `client/lib/services/cli/<cli>/capabilities/tool_call_resolvers.dart`（`ClaudeToolCallResolvers` 等）
- 共享解析器路径：`shared_tool_call_resolvers.dart` 位置与内容（治理后只剩真实共用键）
- 「正确模式」示例代码与当前接口签名是否一致（`ToolCallResolversCapability` 四个 getter：editResolver/fileResolver/shellResolver/categoryResolver）

- [ ] **Step 2: 更新文档**

1. 「目录约定」节改为实际布局（per-CLI `capabilities/tool_call_resolvers.dart` + `registry/capabilities/shared_tool_call_resolvers.dart`）
2. 新增「格式事实来源」节：指向 `docs/cli-formats/`（README 总览 / 5 个 CLI 页 / message-layer-audit.md / tool-layer-coverage.md / adding-a-cli.md / truncation-backfill-audit.md），说明「评审人看 md、改代码对照 md」的流程与四方证据源约定
3. 治理标准引用：共享层只留 ≥2 CLI 证据的映射（子项目 3 产出），per-CLI 追加语义
4. 修正反模式示例中与新接口不一致的部分（如有）

- [ ] **Step 3: 交叉校验 + 提交**

每处新引用的路径/行号 grep 回代码与格式库；提交：

```bash
git add docs/tool-call-parsing-convention.md
git commit -m "docs: sync tool call parsing convention with cli-formats source of truth"
```

---

### Task 2: cli-architecture.md 补解析接入点

**Files:**
- Modify: `docs/cli-architecture.md`

**Interfaces:**
- Consumes: Task 1 更新后的约定文档；adding-a-cli.md
- Produces: 更新后的 CLI 架构文档

- [ ] **Step 1: 定位插入点**

通读 `docs/cli-architecture.md`（505 行），找解析相关章节的合适位置（能力接口清单附近或目录结构节后）。

- [ ] **Step 2: 补解析接入点说明**

新增/扩充一节「消息与工具调用解析接入点」，至少覆盖：
1. **三层职责**：`ai_message_core`（纯接口 + 数据）/ `client/lib/services/ai_history/`（可配置泛型实现）/ per-CLI `capabilities/`（具体配置）——引用约定文档
2. **两个 capability**：`AiHistoryCapability`（locate/adapter/lineAppend/tailFallbackPrefix/subagentToolNames/enricher/liveCacheToken）与 `ToolCallResolversCapability`（四解析器）——引用 `registry/capabilities/` 下的接口文件
3. **截断回填机制**：`ToolResultEnricher` 接口（含 `matchesTruncationMarker`）与 enricher 装配点（history capability 默认值）——引用子项目 4 产出（opencode 回填实现为范例）
4. **接入指引**：指向 `docs/cli-formats/adding-a-cli.md`（6 步清单）
5. **格式事实来源**：指向 `docs/cli-formats/`（与 Task 1 措辞一致）

- [ ] **Step 3: 交叉校验 + 提交**

每处引用 grep 验证；提交：

```bash
git add docs/cli-architecture.md
git commit -m "docs: add parsing integration points to cli architecture"
```

---

### Task 3: 收尾 — 交叉校验 + 全量验证

**Files:**
- Review: 两篇更新后的文档 + 格式库

**Interfaces:**
- Consumes: Task 1-2 产出
- Produces: 可交付状态

- [ ] **Step 1: 三方一致性校验**

1. 两篇文档引用的格式库文件全部存在（`docs/cli-formats/` 6 个文件 + 2 个矩阵）
2. 两篇文档引用的代码路径/接口全部真实（grep `ToolCallResolversCapability` / `AiHistoryCapability` / `ToolResultEnricher` / `SharedToolCallResolvers` 等）
3. 两篇文档之间措辞一致（「格式事实来源」指向同一组文件）

- [ ] **Step 2: 验证 + 提交（如有修正）**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

无修正则报告「校验通过」；有修正则提交 `docs: finalize convention docs cross-check`。

## 完成定义

- [ ] `tool-call-parsing-convention.md`：目录约定与实际布局一致；含「格式事实来源」节；治理标准引用
- [ ] `cli-architecture.md`：含「消息与工具调用解析接入点」节（三层职责 + 两 capability + 截断回填 + adding-a-cli 指引）
- [ ] 两篇文档所有引用经 grep 验证
- [ ] `flutter analyze` 通过
- [ ] 五个子项目全部完成，统一解析体系可交付
