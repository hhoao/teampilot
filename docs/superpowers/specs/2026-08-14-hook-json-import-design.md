# Hook JSON 导入（粘贴 JSON + CLI 选择 → 通用解析层 → 全局库）— 设计

日期：2026-08-14
状态：已评审（brainstorming 各节通过；用户委托定案：最优架构、可扩展性优先、不设工作量约束）

## 1. Context

TeamPilot 的 hook 管线目前是**单向**的：`HookDefinition → HookEntry → HookWriterCapability`（每个 CLI 一个 writer，渲染为各 CLI 原生配置）。用户已有各 CLI 的原生 hook 配置（`~/.claude/settings.json` 的 hooks、`~/.codex/hooks.json`、`~/.cursor/hooks.json`），希望**导入**进 TeamPilot 全局 hook 库——把 CLI 原生 JSON 解析为归一化 `HookDefinition`，让所有 CLI 都能复用。

用户定案（brainstorming）：
- 输入形态：**粘贴 JSON 文本 + CLI 选择器**（CLI 决定 JSON 结构语义）。
- 覆盖：claude/flashskyai（settings.json hooks map）、codex（`hooks.json`）、cursor（`hooks.json`）三种 JSON 格式。codex 的 `config.toml` 内联 `[hooks]`（TOML）与 opencode（无原生 hooks）**不在本次范围**。
- 脚本引用：解析到**通用层**——脚本内容提取进库、命令重写为库内引用，产出 CLI 无关的 `HookDefinition`，所有 CLI 的 writer 都能用。
- 委托定案：① 脚本提取用完整启发式 + 降级 raw；② 不支持字段**旁路保留**（`HookDefinition.native`）零丢失；③ 条目 id 用确定性哈希实现幂等去重。

### 各 CLI JSON 结构（官方文档核实，2026-08-14）

| CLI | 文件 | 结构 | 与共享内核差异 |
|---|---|---|---|
| claude/flashskyai | `~/.claude/settings.json`（或 `.claude/settings.json`） | `{"hooks": {"<Event>": [{"matcher"?, "hooks": [{"type": command\|http\|mcp_tool\|prompt\|agent, "command"\|"url", "timeout"?, "headers"?, "args"?, "if"?, "async"?, "shell"?, ...}]}]}}` | 事件 PascalCase；顶层可有非 hooks 键（settings.json 其它配置） |
| codex | `~/.codex/hooks.json` / `<repo>/.codex/hooks.json` | `{"description"?, "hooks": {"<Event>": [{"matcher"?, "hooks": [{"type": "command", "command", "timeout"?, "statusMessage"?, "additionalContextLimit"?, "commandWindows"?, "async"?}]}]}}` | 与 claude 同构（共享内核）；handler 仅 command 实际运行；顶层 `description` 可选 |
| cursor | `~/.cursor/hooks.json` | `{"version": 1, "hooks": {"<event>": [{"command", "matcher"?, "timeout"?, "loop_limit"?, "type"?: "command"\|"prompt", "failClosed"?}]}}` | **扁平条目**（matcher 在条目上，无嵌套 groups）；事件小写；`version` 顶层 |

## 2. 架构

```
HookImportParser（facade：parseJson(cli, jsonText) → HookImportResult）
 ├─ HookJsonDialect（接口）
 │   ├─ ClaudeFamilyHooksJsonDialect   ← claude/flashskyai
 │   ├─ CodexHooksJsonDialect          ← 与 claude 共享解析内核，仅方言参数不同
 │   └─ CursorHooksJsonDialect         ← 扁平条目适配（归一为单元素 group）
 ├─ 共享：HookEventNameMapper（事件名 → 归一化，数据驱动映射表）
 ├─ 共享：HookHandlerNormalizer（handler → action/native/警告）
 └─ HookScriptExtractor（command → 脚本引用识别 + 内容读取 + 库内路径重写）
```

### 2.1 解析中间形态

```dart
class ParsedHookEntry {
  final String nativeEvent;      // 原生事件名（PascalCase 或 cursor 小写）
  final String? matcher;
  final HookAction action;       // CommandHookAction（raw 或 script）| HttpHookAction
  final int? timeoutSec;
  final Map<String, Object?> native; // 旁路：完整原生 handler 字段（零丢失）
  final List<String> unsupportedFields; // 导入后不生效的字段名
  final List<String> warnings;
}
```

方言解析产出 `List<ParsedHookEntry>`（保持 JSON 内顺序）；共享层负责：
- 事件名映射（`HookEventNameMapper`：`nativeEvent → HookEvent?`，不在归一化目录 → warning `hook_import_event_unsupported_<name>` 丢弃）；
- handler 归一化（`type`: `command` → 脚本提取；`http` → `HttpHookAction(url, headers)`；`mcp_tool`/`prompt`/`agent` → warning 丢弃）；
- 未知/不支持字段（`args`/`if`/`async`/`statusMessage`/`additionalContextLimit`/`commandWindows`/`loop_limit`/`failClosed`/`version`/`description` 等）→ **写入 `native` 旁路** + `unsupportedFields` 标注（预览展示"导入后不生效"）。

### 2.2 事件映射表（数据驱动，可扩展）

每方言一张映射表（`Map<String, HookEvent>`）：
- claude-family / codex：`SessionStart→sessionStart`、`SessionEnd→sessionEnd`、`UserPromptSubmit→userPromptSubmit`、`PreToolUse→preToolUse`、`PostToolUse→postToolUse`、`PostToolUseFailure→postToolUseFailure`（claude 有，codex 无）、`PermissionRequest→permissionRequest`、`Stop→stop`、`StopFailure→stopFailure`（claude 有，codex 无）、`SubagentStop→subagentStop`、`PreCompact→preCompact`、`Notification→notification`（claude 有，codex 无）、codex `ShellCommandRequest`（无原生，忽略）；
- cursor：`sessionStart→sessionStart`、`sessionEnd→sessionEnd`、`beforeSubmitPrompt→userPromptSubmit`、`preToolUse→preToolUse`、`postToolUse→postToolUse`、`postToolUseFailure→postToolUseFailure`、`stop→stop`、`subagentStop→subagentStop`、`preCompact→preCompact`、`beforeShellExecution→shellCommandRequest`（≈）。
- **不在目录的原生事件**（claude `Setup`/`PostCompact`/`SubagentStart`/`MessageDisplay`/…、codex `PostCompact`/`SubagentStart`、cursor `subagentStart`/`afterAgentResponse`/`afterShellExecution`/…）→ `hook_import_event_unsupported_<name>` warning 丢弃（映射表是数据，未来扩展归一化目录只需加枚举 + 表项 + matrix/writer 支持——独立决策，不塞进本次）。

### 2.3 脚本提取（HookScriptExtractor，通用、CLI 无关）

输入：command 字符串 + 宿主 `Filesystem`；输出 `ScriptExtraction`：

```dart
sealed class ScriptExtraction {
  // 识别为脚本引用且成功读取 → script action + 库内重写命令
  ScriptCopy(interpreter: String, fileName: String, content: String,
             rewrittenCommand: String);
  // 内联命令或路径不可解析 → raw action 保留原命令
  RawOnly(command: String, reason: String?);
}
```

识别规则（启发式，顺序尝试）：
1. **解释器前缀**：首 token ∈ {`bash`, `sh`, `zsh`, `python3`, `python`, `node`, `powershell`, `pwsh`, `ruby`, `perl`}（或 `bash -c`/`python3 -c` 带 `-c` → 内联，不提取）→ 剩余参数中第一个**路径形态** token（引号包裹或裸）为脚本路径；
2. **裸路径开头**：命令以 `/`、`~/`、`./`、`../` 或相对路径开头（且非 `-` 开头）→ 该路径为脚本（无解释器 → `bash <path>` 语义，interpreter 记 `bash`）；
3. **占位符检测**：路径含 `${…}`、`$(`、`$(…)`、环境变量（`$VAR`）→ 不可解析 → `RawOnly`（reason: `placeholder`）；
4. **内联命令**：无脚本引用 → `RawOnly`（reason: null）。

读取成功 → `ScriptCopy`：内容写入库 `hooks/{id}/{fileName}`（**保留原文件名**，含扩展名——跨平台脚本不都是 `.sh`），`rewrittenCommand = "<interpreter> <库内绝对路径>"`；`~` 展开用宿主 home；读取失败 → `RawOnly`（reason: `unreadable`）。

### 2.4 条目 id（确定性哈希，幂等）

`id = 'import-' + sha1('$nativeEvent|$matcher|$command|$url')[0..12]`。
- 重复导入同一条 → 同 id → `HookRepository.save` 覆盖（upsert 语义），天然去重；
- 预览时 `HookRepository.load(id)` 非空 → 标「将覆盖」；
- id 稳定 → 已导入的 hook 在源 JSON 变更后重贴可原地更新。

### 2.5 HookDefinition 扩展（旁路 native）

`HookDefinition` 新增可选字段：
```dart
final Map<String, Object?>? native;  // 原生 handler 完整字段（零丢失旁路）
```
`fromJson`/`toJson`/`copyWith`/`==`/`hashCode` 同步；**writer 管线不消费**（本次范围外——未来 writer 可按需读取）。`HookEntry` 不变。

### 2.6 服务与结果

```dart
class HookImportDraft {
  final HookDefinition definition;   // 归一化后（action 已解析/重写）
  final String? scriptFileName;      // 需要写入库的脚本（ScriptCopy 时）
  final String? scriptContent;
  final bool existing;               // id 已在库中（将覆盖）
  final List<String> unsupportedFields; // 导入后不生效字段（预览标注）
  final List<String> warnings;
}

class HookImportResult {
  final List<HookImportDraft> drafts;
  final List<String> warnings;       // 全局 warning（事件不支持等）
}

class HookImportParser {
  HookImportParser({required Filesystem fs, String? homeDir});
  Future<HookImportResult> parseJson({required CliTool cli, required String jsonText});
}

class HookImportService {
  HookImportService({required HookRepository repository, required HookImportParser parser});
  Future<int> import(List<HookImportDraft> drafts); // save + writeScript，返回导入数
}
```

`HookImportParser` 构造注入 `Filesystem`（脚本读取走宿主 fs，测试用 `InMemoryFilesystem`）。

## 3. UI（列表页「导入」入口）

`HookManagementPage` 头部加「导入」按钮 → `HookImportDialog`（`showTpDialog`，与编辑对话框同风格）：

1. **第一步（输入）**：`TpSelect<CliTool>` CLI 选择（claude/flashskyai/codex/cursor，label 用 `CliTool.name`）+ `TpTextArea` JSON 粘贴（占满剩余高度）+「解析」按钮；
2. **第二步（预览）**：解析结果列表（每条：事件名 / matcher / 来源命令或 url / 脚本徽标：`将复制脚本`·`保留原命令`·`⚠ 不支持`；库中已存在 → 「将覆盖」徽标；`unsupportedFields` → 折叠提示「导入后不生效：args, async, …」）+ 全选/勾选 + 「导入」按钮；
3. 导入成功 → 关对话框 + 列表刷新（`HookCubit.load`）+ `AppToast` 成功提示（条数）。

l10n：`hookImport`、`hookImportCli`、`hookImportJson`、`hookImportParse`、`hookImportPreview`、`hookImportScriptCopied`、`hookImportScriptRaw`、`hookImportUnsupported`、`hookImportOverwrite`、`hookImportDone(n)` 等（en+zh）。

## 4. 错误处理与测试

- **坏 JSON**：解析失败 → 预览区显示错误信息（`jsonDecode` 异常消息），不崩溃；
- **非 hooks 形态**：JSON 无 `hooks` 键且整体不是 hooks map → 提示「未找到 hooks 配置」；
- **零可导入条目**（全部事件不支持）：提示并禁用导入；
- **脚本读取失败/占位符**：降级 raw + 预览徽标 `保留原命令`（tooltip 原因）；
- **测试**：
  - 三方言解析单测（claude 全 handler 类型、codex description/commandWindows/statusMessage、cursor 扁平+version+loop_limit+failClosed）；
  - 事件映射表（支持/不支持边界）；
  - `HookScriptExtractor`：解释器前缀、引号包裹、占位符降级、`~` 展开、读取失败降级、内联命令；
  - 确定性 id（同输入同 id、不同输入不同 id）；
  - `HookDefinition.native` round-trip（fromJson/toJson/==）；
  - `HookImportParser` 端到端（InMemoryFilesystem 注入，脚本落库、raw 保留）；
  - `HookImportDialog` widget 测试（解析→预览→勾选→导入→列表刷新）。

## 5. 不在范围（明确）

- codex `config.toml` 内联 `[hooks]`（TOML 解析——后续独立功能，复用 `HookJsonDialect` 输出的同一中间形态）；
- 磁盘文件路径导入（解析器吃字符串，文件读取只是加一个读文件按钮）；
- 归一化事件目录扩展（`PostCompact`/`SubagentStart` 等入目录需要 matrix/writer/UI 全链路——独立决策）；
- writer 消费 `HookDefinition.native`（旁路仅保数据，本次不生效）；
- opencode（无原生 hooks）。
