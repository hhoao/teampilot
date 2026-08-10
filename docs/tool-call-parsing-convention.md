# Tool Call 解析约定

**日期:** 2026-08-10
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
2. `client/lib/services/ai_history/` 放可配置的泛型实现
3. `client/lib/services/cli/registry/capabilities/` 放每 CLI 的具体配置
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
  subagent_attachment.dart        # AiSubagentAttachment 等数据类型（无 tool name 列表）

client/lib/services/ai_history/
  edit_codecs/
    tool_args.dart                        # 共享工具函数（toolCallArgsMap, firstNonEmptyString 等）
    str_replace_edit_hunk_codec.dart      # 可配置泛型 codec
    write_edit_hunk_codec.dart            # 可配置泛型 codec
    unified_diff_edit_hunk_codec.dart     # 可配置泛型 codec
  tool_call_resolvers.dart               # Configurable* resolver 实现
  workspace_edit_line_highlighter.dart    # AiEditLineHighlighter 实现（UI 渲染，不属于解析层）

client/lib/services/cli/registry/capabilities/
  tool_call_resolver_capability.dart     # ToolCallResolversCapability 接口
  claude_tool_call_resolvers.dart        # Claude 配置
  flashskyai_tool_call_resolvers.dart    # flashskyai 配置
  codex_tool_call_resolvers.dart         # Codex 配置
  opencode_tool_call_resolvers.dart      # opencode 配置
  cursor_tool_call_resolvers.dart        # cursor 配置
```

## 已有的 Tool Parser 分类

| 类别 | 接口 | 数据类型 | 职责 |
|------|------|----------|------|
| **Edit** | `AiEditHunkCodec` / `AiEditToolTargetResolver` | `AiEditHunk`, `AiEditLine`, `AiEditLineKind` | 解析 tool call args 生成代码 diff hunk，渲染编辑卡片 |
| **File** | `AiToolFileTargetResolver` | `AiToolFileTarget` | 解析 tool call args 提取文件路径和行号，生成可点击文件链接 |
| **Shell** | `AiShellToolTargetResolver` | `AiShellToolTarget` | 解析 tool call args 提取 shell 命令，渲染终端命令卡片 |
| **Subagent** | `AiHistoryCapability.subagentToolNames` | `AiSubagentAttachment` | 识别 subagent spawn tool call，渲染子代理附件 |

## 反模式（禁止）

### ❌ 在 `ai_message_core` 中硬编码 tool name 列表

```dart
// 错误 — 不应该出现在 ai_message_core 中
const kEditToolNames = {'edit', 'strreplace', 'write', ...};
const kPathKeys = ['file_path', 'path', 'file', 'target_file'];
```

### ❌ 在 `ai_message_ui` 中直接实例化 Default* 实现

```dart
// 错误 — 不应该出现在 ai_message_ui 中
const resolver = DefaultAiShellToolTargetResolver();
final target = resolver.resolve(part);
```

### ❌ 在 codec/resolver 中硬编码 tool name 或 key 列表

```dart
// 错误 — codec 应该是可配置的泛型实现
class MyHunkCodec implements AiEditHunkCodec {
  static const _toolNames = {'write', 'write_file'};  // ❌ 硬编码
}
```

## 正确模式

### ✅ 接口 + 可配置实现

```dart
// ai_message_core — 接口
abstract class AiEditHunkCodec {
  bool matches(String toolName);
  AiEditHunk? encode(AiToolCallPart part);
}

// client/lib/services/ — 可配置实现
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

### ✅ CLI 通过 Capability 注册配置

```dart
// 每个 CLI 提供自己的 ToolCallResolvers
class ClaudeToolCallResolvers implements ToolCallResolversCapability {
  @override
  late final editResolver = ConfigurableAiEditToolTargetResolver(codecs: [
    StrReplaceEditHunkCodec(
      toolNames: {'edit', 'strreplace'},
      pathKeys: ['file_path', 'path', 'file'],
      oldStringKeys: ['old_string', 'oldString'],
      newStringKeys: ['new_string', 'newString'],
    ),
    // ...
  ]);
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
    // ...
  ),
);
```

## 新增 Tool Parser 检查清单

当需要新增一种工具气泡解析时：

- [ ] `ai_message_core` 只新增接口 + 数据类型，不添加任何 tool name 或 key 的常量列表
- [ ] 泛型实现放在 `client/lib/services/ai_history/`，通过构造函数接受配置
- [ ] 每个 CLI 在 `registry/capabilities/` 提供自己的配置实例
- [ ] `CliToolRegistry` 新增查询方法（如果需要）
- [ ] `ai_message_ui` 通过 `AiToolFileActions` 或新建类似的 Scope 注入
- [ ] 不向后兼容旧代码 — 旧的 Default* 直接删除
