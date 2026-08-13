# Tool Call 解析约定

**日期:** 2026-08-13
**状态:** 生效中

`ai_message_core` 是纯接口 + 数据类型包，**不包含任何 CLI 特定的 tool name 或 argument key 映射**。所有解析实现和配置约定如下。

## 核心原则

```
ai_message_core     → 纯接口 + 纯数据类型（零实现，零硬编码）
ai_message_ui       → 纯 UI 渲染（通过 InheritedWidget 注入获取 resolver，不直接实例化实现）
client/lib/services → 解析实现 + CLI 配置（可配置的泛型实现 + 每 CLI 的具体参数）
```

新增工具气泡解析或 history 解析时，遵循同一套流程：
1. `ai_message_core` 定义接口 + 数据类型
2. `client/lib/services/ai_history/` 放可配置的泛型实现（Configurable* resolver / codec / category resolver）
3. 每个 CLI 在 `client/lib/services/cli/<cli>/capabilities/tool_call_resolvers.dart` 提供自己的配置（共享层在 `registry/capabilities/shared_tool_call_resolvers.dart`）
4. `ai_message_ui` 通过 `AiToolFileActions`（或类似 Scope）注入使用

## 目录约定

```
ai_message_core/lib/src/
  message.dart                    # AiToolCallPart, AiMessage 等核心类型
  tool_edit_hunk.dart             # AiEditLineKind, AiEditLine, AiEditHunk（纯数据）
  tool_edit_hunk_codec.dart       # AiEditHunkCodec 接口
  tool_edit_target_resolver.dart  # AiEditToolTargetResolver 接口
  tool_file_target.dart           # AiToolFileTarget 数据 + AiToolFileTargetResolver 接口
  tool_shell_target.dart          # AiShellToolTarget 数据 + AiShellToolTargetResolver 接口
  tool_category_resolver.dart     # AiToolCallCategory 数据 + AiToolCallCategoryResolver 接口
  subagent_attachment.dart        # AiSubagentAttachment 等数据类型（无 tool name 列表）

client/lib/services/ai_history/
  edit_codecs/
    tool_args.dart                        # 共享工具函数（toolCallArgsMap, firstNonEmptyString 等）
    str_replace_edit_hunk_codec.dart      # 可配置泛型 codec
    write_edit_hunk_codec.dart            # 可配置泛型 codec
    unified_diff_edit_hunk_codec.dart     # 可配置泛型 codec（含 codex freeform 分支）
  tool_call_resolvers.dart               # Configurable* resolver 实现
  tool_call_categories.dart              # ConfigurableAiToolCallCategoryResolver + 共享类别表
  tool_call_category_annotator.dart      # AiToolCallCategoryAnnotator 实现
  workspace_edit_line_highlighter.dart   # AiEditLineHighlighter 实现（UI 渲染，不属于解析层）

client/lib/services/cli/registry/capabilities/
  tool_call_resolver_capability.dart     # ToolCallResolversCapability 接口（四个 getter）
  shared_tool_call_resolvers.dart        # SharedToolCallResolverKeys + SharedToolCallResolvers

client/lib/services/cli/<cli>/capabilities/
  tool_call_resolvers.dart               # 每 CLI 的 resolver 配置（claude/flashskyai/codex/cursor/opencode）
```

## 已有的 Tool Parser 分类

| 类别 | 接口 | 数据类型 | 职责 |
|------|------|----------|------|
| **Edit** | `AiEditHunkCodec` / `AiEditToolTargetResolver` | `AiEditHunk`, `AiEditLine`, `AiEditLineKind` | 解析 tool call args 生成代码 diff hunk，渲染编辑卡片 |
| **File** | `AiToolFileTargetResolver` | `AiToolFileTarget` | 解析 tool call args 提取文件路径和行号，生成可点击文件链接 |
| **Shell** | `AiShellToolTargetResolver` | `AiShellToolTarget` | 解析 tool call args 提取 shell 命令，渲染终端命令卡片 |
| **Category** | `AiToolCallCategoryResolver` | `AiToolCallCategory` | 将 tool name 映射到展示类别（plan/askUser/subagent/…），驱动历史视图折叠分组 |
| **Subagent** | `AiHistoryCapability.subagentToolNames` | `AiSubagentAttachment` | 识别 subagent spawn tool call，渲染子代理附件 |

`ToolCallResolversCapability` 统一承载 Edit/File/Shell/Category 四个 resolver
（`registry/capabilities/tool_call_resolver_capability.dart:12-16`）；Subagent 属于 history
能力面，仍由 `AiHistoryCapability.subagentToolNames` 提供（`registry/capabilities/ai_history_capability.dart:78`）。

## 格式事实来源

工具调用格式的**唯一事实来源**是格式参考库 `docs/cli-formats/`：

| 文件 | 内容 |
|------|------|
| [README.md](../cli-formats/README.md) | 总览矩阵：5 CLI 的 transcript 位置 / 文件格式 / 消息 schema 页 / 解析入口 / 增量能力 |
| [claude.md](../cli-formats/claude.md) / [codex.md](../cli-formats/codex.md) / [opencode.md](../cli-formats/opencode.md) / [cursor.md](../cli-formats/cursor.md) / [flashskyai.md](../cli-formats/flashskyai.md) | 每 CLI 的消息 schema、工具调用 schema、增量 vs 全量、已知陷阱 |
| [message-layer-audit.md](../cli-formats/message-layer-audit.md) | 消息层差异矩阵 + Gap 清单（D10 等） |
| [tool-layer-coverage.md](../cli-formats/tool-layer-coverage.md) | **工具层覆盖矩阵（5 CLI × 5 类别）+ 缺口清单 G-1..G-6 + 治理同步结论** |
| [truncation-backfill-audit.md](../cli-formats/truncation-backfill-audit.md) | 工具输出截断回填可行性（codex 不可行 / opencode 有条件可行） |
| [adding-a-cli.md](../cli-formats/adding-a-cli.md) | 新 CLI 接入清单（6 个接入点，含 tool call resolvers 三种实现模式） |

**评审人看 md、改代码对照 md**：评审或修改任何解析代码前，先读对应 CLI 页与覆盖矩阵；
修改代码时以 md 记录的格式事实为准，行为差异需回填 md。工具调用覆盖的**四方证据源**约定
（见 `docs/cli-formats/README.md:25-31` 与 tool-layer-coverage.md）：

1. `spl@93c9991` — 泄露系统提示快照（固定 commit，禁止「最新版」表述）
2. 测试夹具 `client/test/fixtures/session_history/<cli>/` — 真实数据采样
3. 本机实测 — 真实 transcript 扫描结论
4. `docs/cli-formats/` 各页 — 沉淀后的格式文档

## 共享层治理标准

`SharedToolCallResolvers`（`registry/capabilities/shared_tool_call_resolvers.dart:64-118`）是
所有 CLI 的共享基线，其键集 `SharedToolCallResolverKeys`（`:24-60`）遵循治理标准
（文件头注释 `:14-23`，与 tool-layer-coverage.md「Task 5 治理同步」一致）：

- 共享键集内**每个名字必须有 ≥2 个 CLI 的发射证据**（矩阵证据：src / fixture / 本机 / `spl@93c9991`）
- **单 CLI 名字下沉**到该 CLI 的 resolver 文件，以**追加**语义挂在共享键集之上（不替换、不删除共享键）
- 无发射证据的名字不进共享集（G-1..G-6 全部由此治理；零证据项已移除，如 `writefile`/`create_file`/`target_file` 等）
- 类别表 `tool_call_categories.dart` 是**五 CLI 工具名的并集**（union 语义），不受共享键集治理约束

三种实现模式（详见 `docs/cli-formats/adding-a-cli.md:111-151`）：

1. **无 delta**：`class ClaudeToolCallResolvers extends SharedToolCallResolvers`（claude / flashskyai）
2. **追加覆写**：extends 共享层 + 追加单 CLI 键并 override getter（cursor：`path` / `contents`）
3. **全自定义**：`implements ToolCallResolversCapability`，共享键集仅作常量引用（opencode：camelCase 追加键）

## 反模式（禁止）

### ❌ 在 `ai_message_core` 中硬编码 tool name 列表

```dart
// 错误 — 不应该出现在 ai_message_core 中
const kEditToolNames = {'edit', 'strreplace', 'write', ...};
const kPathKeys = ['file_path', 'path', 'file', 'target_file'];
```

### ❌ 在 `ai_message_ui` 中直接实例化 Configurable* 实现

```dart
// 错误 — 不应该出现在 ai_message_ui 中
const resolver = ConfigurableAiShellToolTargetResolver(toolNames: {...});
final target = resolver.resolve(part);
```

### ❌ 在 codec/resolver 中硬编码 tool name 或 key 列表

```dart
// 错误 — codec 应该是可配置的泛型实现
class MyHunkCodec implements AiEditHunkCodec {
  static const _toolNames = {'write', 'write_file'};  // ❌ 硬编码
}
```

### ❌ 在共享层放入单 CLI 专属键

```dart
// 错误 — 共享键集只允许 ≥2 CLI 证据的名字
class SharedToolCallResolverKeys {
  static const editToolNames = {'edit', 'strreplace', 'editnotebook'};  // ❌ strreplace 仅 cursor 发射
}
// 正确 — 单 CLI 键下沉到该 CLI 的 resolver 里追加
// （cursor: 'strreplace'/'editnotebook'；opencode: 'filePath'/'oldString'/'newString'）
```

## 正确模式

### ✅ 接口 + 可配置实现

```dart
// ai_message_core — 接口
abstract class AiEditHunkCodec {
  bool matches(String toolName);
  AiEditHunk? encode(AiToolCallPart part);
}

// client/lib/services/ai_history/ — 可配置实现
class StrReplaceEditHunkCodec implements AiEditHunkCodec {
  const StrReplaceEditHunkCodec({
    required this.toolNames,     // 由 CLI 配置提供
    required this.pathKeys,      // 由 CLI 配置提供
    required this.oldStringKeys, // 由 CLI 配置提供
    required this.newStringKeys, // 由 CLI 配置提供
  });
  // ...
}
```

### ✅ 共享层提供基线 + CLI 追加配置

```dart
// registry/capabilities/shared_tool_call_resolvers.dart — 共享基线（治理标准见上节）
class SharedToolCallResolvers implements ToolCallResolversCapability {
  @override
  AiEditToolTargetResolver get editResolver => const ConfigurableAiEditToolTargetResolver(
    codecs: [_strReplaceCodec, _writeCodec, _unifiedDiffCodec],
  );
  @override
  AiToolFileTargetResolver get fileResolver => const ConfigurableAiToolFileTargetResolver(rules: _fileRules);
  @override
  AiShellToolTargetResolver get shellResolver => const ConfigurableAiShellToolTargetResolver(
    toolNames: SharedToolCallResolverKeys.shellToolNames,
  );
  @override
  AiToolCallCategoryResolver get categoryResolver => defaultToolCallCategoryResolver;
}

// cli/claude/capabilities/tool_call_resolvers.dart — 无 delta 的 CLI 配置
class ClaudeToolCallResolvers extends SharedToolCallResolvers {
  const ClaudeToolCallResolvers();
}
```

### ✅ UI 通过依赖注入获取 Resolver

```dart
// ai_message_ui — 从 scope 拿，不关心 CLI
final actions = AiToolFileActions.of(context);
final editTarget = actions.editResolver.resolve(part);

// client/lib — 从 registry 创建，注入 scope
final resolvers = registry.toolCallResolvers(session.cli);
AiToolFileActionsScope(
  actions: AiToolFileActions(
    editResolver: resolvers.editResolver,
    fileResolver: resolvers.fileResolver,
    shellResolver: resolvers.shellResolver,
  ),
);
```

（`registry.toolCallResolvers(cli)` 查询方法见 `registry/cli_tool_registry.dart:81-82`；
Category resolver 经 `AiToolCallCategoryAnnotator` 供历史视图使用，不在 `AiToolFileActions` 内。）

## 新增 Tool Parser 检查清单

当需要新增一种工具气泡解析时：

- [ ] `ai_message_core` 只新增接口 + 数据类型，不添加任何 tool name 或 key 的常量列表
- [ ] 泛型实现放在 `client/lib/services/ai_history/`，通过构造函数接受配置
- [ ] 键名先对照 `docs/cli-formats/`（对应 CLI 页 + tool-layer-coverage.md 矩阵），确认证据来源
- [ ] ≥2 CLI 证据的键进 `registry/capabilities/shared_tool_call_resolvers.dart` 共享键集；单 CLI 键在 `cli/<cli>/capabilities/tool_call_resolvers.dart` 以追加语义配置
- [ ] `CliToolRegistry` 新增查询方法（如果需要）
- [ ] `ai_message_ui` 通过 `AiToolFileActions` 或新建类似的 Scope 注入
- [ ] 不向后兼容旧代码 — 旧的 Default* 直接删除
