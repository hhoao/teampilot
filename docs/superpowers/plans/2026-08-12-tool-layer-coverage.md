# 工具层覆盖补齐实施计划（子项目 3/5）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用四方证据源（adapter/resolver 源码 + 测试夹具 + 本机真实数据 + 外部 system_prompts_leaks）逐格验证 5 CLI × 5 解析类别的工具调用覆盖矩阵，补齐所有缺口，治理 `SharedToolCallResolvers`，确认入口唯一。

**Architecture:** 审计先行（Task 1 产出 `docs/cli-formats/tool-layer-coverage.md` 矩阵 + 缺口清单，引用 `system_prompts_leaks@<commit>` 快照），然后按缺口分组修复（Task 2 共享族 / Task 3 cursor / Task 4 opencode，每项 TDD：失败断言 → 修 resolver → 单测），Task 5 治理共享层 + 入口唯一性，Task 6 收尾回填 + 全量验证。

**Tech Stack:** Dart / flutter_test / `ToolCallResolversCapability` / `SharedToolCallResolvers` / 各 CLI `capabilities/tool_call_resolvers.dart` / `AiToolCallCategory`。

## Global Constraints

- **四方证据源约束**：矩阵里每个 tool name / arg key 必须能归因到至少一个证据源（源码行号 / 夹具路径 / 本机数据 / system_prompts_leaks@commit）；引用外部源必须固定 commit 或快照日期，禁止"最新版"表述
- **共享层治理**：`SharedToolCallResolvers` 只保留真实共用的映射；CLI 特有 key/tool name 一律下沉到各自 `capabilities/tool_call_resolvers.dart`，per-CLI 配置对共享 key 追加而非替换（兼容旧 snake_case 会话）
- **回归约束**：子项目 2 产出的契约测试（`message_layer_contract_test.dart`）与消息层固化断言全绿；不改消息层 adapter
- **验证命令**：`cd client && flutter test <具体测试文件>`；收尾 `flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
- commit 沿用仓库规范：`fix(history): <desc>` / `test(history): <desc>` / `docs(cli-formats): <desc>` / `refactor(history): <desc>`
- 执行在隔离 worktree：`.worktrees/tool-layer-coverage`（分支 `tool-layer-coverage`）

---

### Task 1: 工具层覆盖矩阵审计（含外部参考登记 + 新 CLI 预研）

**Files:**
- Create: `docs/cli-formats/tool-layer-coverage.md`
- Modify: `docs/cli-formats/README.md`（「外部参考」节）
- Research sources（只读）: 5 个 `capabilities/tool_call_resolvers.dart`、`shared_tool_call_resolvers.dart`、`client/lib/services/ai_history/tool_call_categories.dart`、`docs/cli-formats/*.md` 各页工具调用 schema 表、外部 `system_prompts_leaks`

**Interfaces:**
- Consumes: 格式参考库各页（子项目 1）、契约测试（子项目 2）
- Produces: `tool-layer-coverage.md`（矩阵 + 缺口清单，Task 2-4 的修复依据）；README「外部参考」节；Task 6 回填结论

- [ ] **Step 1: 固定外部证据源快照**

```bash
# 记录 system_prompts_leaks 当前 commit（后续所有引用用该 commit 的 raw URL）
curl -s https://api.github.com/repos/asgeirtj/system_prompts_leaks/commits/main | jq -r .sha
```

记为 `SPL_COMMIT`。后续取文件一律用 `https://raw.githubusercontent.com/asgeirtj/system_prompts_leaks/<SPL_COMMIT>/<path>`。相关文件路径：
- Claude Code: `Anthropic/Claude%20Code/claude-code-sonnet-5.md`（及同目录其他模型变体）
- Codex: `OpenAI/Codex/gpt-5.5.md`
- opencode: `OpenCode/opencode.md`
- Cursor: `Cursor/cursor.md`
- 新 CLI 预研: `Google/gemini-cli.md`、`Google/antigravity-cli.md`

- [ ] **Step 2: 提取四家工具 schema**

对 claude / codex / opencode / cursor 四家：下载对应系统提示文件，提取其中的**工具定义段**（工具名 + 参数 key，如 `file_path`、`old_string` 等）。**注意**：若某家系统提示不含工具 JSON schema（部分提示只含行为指令），如实记录「提示中无工具定义段，证据源降级为源码+夹具+本机」，不要编造。输出为矩阵的前置素材。

- [ ] **Step 3: 写覆盖矩阵**

创建 `docs/cli-formats/tool-layer-coverage.md`：

```markdown
# 工具层覆盖矩阵

**日期:** 2026-08-12
**外部证据源:** asgeirtj/system_prompts_leaks @ <SPL_COMMIT>（CC0）
**状态:** 审计中（Task 6 回填结论）

## 矩阵（5 CLI × 5 类别）

| CLI | Edit | File | Shell | Subagent | Category | 缺口数 |
|-----|------|------|-------|----------|----------|--------|
| claude | ✅/❌ + 证据 | | | | | |
| codex | | | | | | |
| opencode | | | | | | |
| cursor | | | | | | |
| flashskyai | | | | | | |

每格填：「覆盖结论（✅ 完整 / ⚠️ 缺口描述）+ 证据源标注（src:行号 / fixture:路径 / 本机 / spl@<SPL_COMMIT>）」

## 缺口清单（Task 2-4 的修复依据）

| # | CLI | 类别 | 缺口 | 涉及配置 | 修复方向 |
|---|-----|------|------|---------|---------|
```

**逐格验证方法（每格都要做）：**
1. 读该 CLI 的 `capabilities/tool_call_resolvers.dart` + `SharedToolCallResolvers` 实际生效的映射
2. 对照 `docs/cli-formats/<cli>.md` 工具调用 schema 表（夹具/本机实测的工具名 + key）
3. 对照 Step 2 提取的系统提示工具 schema（重点查：系统提示里出现的工具/参数是否都在 resolver 映射里；resolver 里的别名是否真实存在）
4. 结论入矩阵，缺口入清单

- [ ] **Step 4: 写新 CLI 预研小结**

在矩阵文档末尾加「新 CLI 预研」小节：从 `Google/gemini-cli.md` 与 `Google/antigravity-cli.md` 提取工具名/参数形态，给出「未来接入的潜在接入点」2-3 条要点（如 Gemini CLI 的 transcript 位置、工具命名风格），明确标注为预研非承诺。

- [ ] **Step 5: 登记外部参考**

`docs/cli-formats/README.md` 增加：

```markdown
## 外部参考

| 仓库 | 用途 | 引用方式 |
|------|------|---------|
| [asgeirtj/system_prompts_leaks](https://github.com/asgeirtj/system_prompts_leaks)（CC0） | 各 CLI 泄露系统提示中的工具 JSON schema，工具调用覆盖的第四方证据源 | 固定 commit 快照（本库引用 `@<SPL_COMMIT>`），禁止"最新版"表述 |
```

- [ ] **Step 6: 交叉校验 + 提交**

矩阵每格证据必须可验证（grep 回源码 / 打开夹具 / 记录本机路径 / raw URL 可下载）；修正后提交（一个 commit）：

```bash
git add docs/cli-formats/tool-layer-coverage.md docs/cli-formats/README.md
git commit -m "docs(cli-formats): tool layer coverage matrix"
```

---

### Task 2: 共享族补齐 — claude / codex / flashskyai

**Files:**
- Modify: `client/lib/services/cli/{claude,codex,flashskyai}/capabilities/tool_call_resolvers.dart`（按缺口；若纯共享即可满足则不改）
- Modify: `client/lib/services/cli/registry/capabilities/shared_tool_call_resolvers.dart`（仅当缺口在共享层且属"真实共用"）
- Test: `client/test/services/cli/registry/capabilities/tool_call_resolvers_test.dart`（新建，三个共享族 CLI 的典型工具断言）

**Interfaces:**
- Consumes: Task 1 矩阵缺口清单中 claude/codex/flashskyai 三行的缺口
- Produces: 三 CLI 的工具解析覆盖与矩阵一致；`SharedToolCallResolvers` 判定（哪些 key 属共享、哪些该下沉）

- [ ] **Step 1: 写典型工具断言（TDD 载体）**

新建 `client/test/services/cli/registry/capabilities/tool_call_resolvers_test.dart`，对三个共享族 CLI 的**典型工具**各写断言（工具名与 key 以矩阵/格式页为准，示例结构如下，**必须替换为矩阵实证的工具名与 key**）：

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/tool_call_resolvers.dart';
import 'package:teampilot/services/cli/codex/capabilities/tool_call_resolvers.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/tool_call_resolvers.dart';

AiToolCallPart part(String name, {String? argsText, Map<String, Object?>? args}) {
  return AiToolCallPart(toolCallId: 'call_1', toolName: name, args: args, argsText: argsText);
}

void main() {
  const claude = ClaudeToolCallResolvers();
  const codex = CodexToolCallResolvers();
  const flashskyai = FlashskyaiToolCallResolvers();

  test('claude: Edit 工具解析出 hunk（file_path/old_string/new_string）', () {
    final target = claude.editResolver.resolve(part(
      'Edit',
      args: {
        'file_path': 'a.txt',
        'old_string': 'foo',
        'new_string': 'bar',
      },
    ));
    expect(target, isNotNull);
    expect(target!.hunk.removedLines.first, 'foo');
    expect(target.hunk.addedLines.first, 'bar');
  });
  // ... 每 CLI 至少 2 个典型工具断言（Edit/Write/Read/Bash/apply_patch 等，以矩阵实证为准）
}
```

- [ ] **Step 2: 运行确认失败项**

Run: `cd client && flutter test test/services/cli/registry/capabilities/tool_call_resolvers_test.dart`

预期：断言失败项 = 矩阵缺口清单中该族的真实缺口（若全绿 = 共享配置已满足，记录后直接进 Step 4）。

- [ ] **Step 3: 修复缺口**

对每个失败断言：修 `shared_tool_call_resolvers.dart`（若 key 属真实共用，如 Claude/FlashskyAI 同源的 `NotebookEdit`）或对应 CLI 的 `capabilities/tool_call_resolvers.dart`（若属 CLI 特有）。**修复遵循追加语义**（per-CLI 配置在共享 key 基础上追加，不替换）。

- [ ] **Step 4: 验证 + 提交**

Run: `flutter test test/services/cli/registry/capabilities/tool_call_resolvers_test.dart test/services/cli/registry/capabilities/history/message_layer_contract_test.dart`

```bash
git add client/lib/services/cli/ client/test/services/cli/registry/capabilities/tool_call_resolvers_test.dart
git commit -m "fix(history): align claude/codex/flashskyai tool call resolvers with coverage matrix"
```

---

### Task 3: cursor 补齐

**Files:**
- Modify: `client/lib/services/cli/cursor/capabilities/tool_call_resolvers.dart`（按矩阵缺口）
- Test: `client/test/services/cli/registry/capabilities/cursor_tool_call_resolvers_test.dart`（新建）

**Interfaces:**
- Consumes: Task 1 矩阵 cursor 行缺口
- Produces: cursor 覆盖补齐；`execute` 别名等既有覆写经断言固化

- [ ] **Step 1: 写断言**

cursor 已知覆写：`shellResolver` 加 `execute`（cursor_tool.dart:113 装配时可见）。按矩阵缺口 + 格式页 cursor 工具表（Shell/Read/agent/task + terminals 相关）写断言，覆盖：既有覆写不回归 + 矩阵缺口项。文件与结构同 Task 2。

- [ ] **Step 2: 运行确认失败项**（失败 = 真实缺口）
- [ ] **Step 3: 修复缺口**（追加语义，不动共享层）
- [ ] **Step 4: 验证 + 提交**

```bash
flutter test test/services/cli/registry/capabilities/cursor_tool_call_resolvers_test.dart test/services/cli/registry/capabilities/history/message_layer_contract_test.dart
git add client/lib/services/cli/cursor/ client/test/services/cli/registry/capabilities/cursor_tool_call_resolvers_test.dart
git commit -m "fix(history): align cursor tool call resolvers with coverage matrix"
```

---

### Task 4: opencode 补齐

**Files:**
- Modify: `client/lib/services/cli/opencode/capabilities/tool_call_resolvers.dart`（按矩阵缺口）
- Test: `client/test/services/cli/registry/capabilities/opencode_tool_call_resolvers_test.dart`（扩展既有测试）

**Interfaces:**
- Consumes: Task 1 矩阵 opencode 行缺口；既有 opencode 单测（camelCase 场景已覆盖）
- Produces: opencode 覆盖补齐

- [ ] **Step 1: 对照矩阵写新增断言**（既有测试文件追加；camelCase + snake_case 兼容、bash/skill/question/webfetch 等矩阵缺口项）
- [ ] **Step 2: 运行确认失败项**
- [ ] **Step 3: 修复缺口**（追加语义）
- [ ] **Step 4: 验证 + 提交**

```bash
flutter test test/services/cli/registry/capabilities/opencode_tool_call_resolvers_test.dart test/services/cli/registry/capabilities/history/message_layer_contract_test.dart
git add client/lib/services/cli/opencode/ client/test/services/cli/registry/capabilities/opencode_tool_call_resolvers_test.dart
git commit -m "fix(history): align opencode tool call resolvers with coverage matrix"
```

---

### Task 5: SharedToolCallResolvers 治理 + 入口唯一性

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/shared_tool_call_resolvers.dart`（若 Task 2-4 判定需下沉 CLI 特有项）
- Test: `client/test/services/cli/registry/capabilities/shared_tool_call_resolvers_test.dart`（新建）+ `client/test/services/cli/registry/ai_history_capability_wiring_test.dart`（扩展）

**Interfaces:**
- Consumes: Task 2-4 各任务的共享层判定
- Produces: 共享层纯净性验证 + 注册完备性 + 入口唯一性断言

- [ ] **Step 1: 共享层治理**

核对 `SharedToolCallResolvers` 每个 toolName/key 是否"真实共用"（矩阵中至少 2 个 CLI 的实测/夹具证据支持它属于共用；单 CLI 特有的从共享层下沉到该 CLI 的 resolver 文件——下沉后该 CLI 用"共享常量 + 自身常量"追加组合）。**任何下沉必须伴随对应 CLI 的单测仍然全绿**。

- [ ] **Step 2: 入口唯一性检查**

```bash
# 全仓查找 toolCallResolvers 查询入口与散落的 CLI 分支
rg -n "toolCallResolvers\(|if \(cli ==|switch \(.*cli" client/lib --glob "*.dart" | head -40
```

预期：`CliToolRegistry.toolCallResolvers(cli)` 是唯一查询入口；UI/服务层无 `if (cli == ...)` 分支工具解析。发现违规则移除（改用 registry 查询）。

- [ ] **Step 3: 注册完备性断言**

在 `ai_history_capability_wiring_test.dart`（或新建 `tool_call_resolver_wiring_test.dart`）加断言：**每个 `CliTool` 枚举值**（claude/codex/opencode/cursor/flashskyai）通过 `CliToolRegistry.builtIn()` 后 `toolCallResolvers(cli)` 非空。参考既有 wiring 测试的构造模式。

- [ ] **Step 4: 验证 + 提交**

```bash
cd client && flutter test test/services/cli/registry/capabilities/shared_tool_call_resolvers_test.dart test/services/cli/registry/ai_history_capability_wiring_test.dart test/services/cli/registry/capabilities/ test/services/cli/registry/capabilities/history/message_layer_contract_test.dart
git add client/lib/services/cli/registry/ client/test/
git commit -m "refactor(history): governance pass on shared tool call resolvers and entry uniqueness"
```

---

### Task 6: 收尾 — 矩阵回填 + 全量验证

**Files:**
- Modify: `docs/cli-formats/tool-layer-coverage.md`（回填结论与缺口状态）
- Review: 全部改动

**Interfaces:**
- Consumes: Task 1-5 全部产出
- Produces: 矩阵结论（每个缺口：已修复+commit / 接受差异+理由）；可交付状态

- [ ] **Step 1: 回填矩阵**

「状态」列 → 完成；缺口清单每条标记：已修复（+commit）/ 接受差异（+理由）/ 非缺口（矩阵误判）。README 总览矩阵如需增列工具层状态一并更新。

- [ ] **Step 2: 全量验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`

注意：全量测试已知有 10 个 main 既有 pre-existing 失败（cli_config_section ×3、codex_cli_tool_adapter ×2、plugin_provisioning_chain ×3、cli_plugin_layout ×1、app_shell_smoke ×1），与本分支无关——如失败用例文件未被本分支 touch，直接判 pre-existing。

- [ ] **Step 3: 提交**

```bash
git add docs/cli-formats/tool-layer-coverage.md docs/cli-formats/README.md
git commit -m "docs(cli-formats): finalize tool layer coverage conclusions"
```

## 完成定义

- [ ] `docs/cli-formats/tool-layer-coverage.md` 5 CLI × 5 类别矩阵全部落结论，缺口清单全部有状态
- [ ] 每格证据可归因到四方证据源之一（含 `system_prompts_leaks@<SPL_COMMIT>` 引用）
- [ ] 每个 CLI resolver 单测全绿（新建：共享族 3 合一 / cursor / shared；既有：opencode）+ 契约测试全绿
- [ ] `SharedToolCallResolvers` 无单 CLI 特有项残留；`CliToolRegistry.toolCallResolvers` 唯一入口；每个 `CliTool` 注册完备断言通过
- [ ] `flutter analyze` + 全量测试通过（10 个 pre-existing 失败除外）
- [ ] README「外部参考」节已登记 system_prompts_leaks@commit；矩阵含 Gemini CLI / Antigravity CLI 预研小结
- [ ] 产出可支撑子项目 4（测试校验 + adding-a-cli.md）
