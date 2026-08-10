# Tool Call Resolver 重构设计

**日期:** 2026-08-10
**状态:** 待实施

## 问题

`ai_message_core` 包当前既定义了接口，又包含了带有跨 CLI fallback 逻辑的 "Default" 实现：

- `tool_edit_args.dart` — 硬编码 `editPathKeys` / `editOldStringKeys` / `editNewStringKeys` / `editStartLineKeys`，混合
  snake_case 和 camelCase 以兼容不同 CLI
- 三个 codec 实现（`StrReplaceEditHunkCodec`、`WriteEditHunkCodec`、`UnifiedDiffEditHunkCodec`）— 各自硬编码
  tool name 集合和参数 key 列表
- `DefaultAiEditToolTargetResolver` — 硬编码 chain 三个 codec
- `DefaultAiToolFileTargetResolver` — 硬编码 `AiToolFileTargetRule`，跨 CLI 混合 tool name
- `DefaultAiShellToolTargetResolver` — 硬编码 tool name 集合和 `_commandKeys`

当新增 CLI 或现有 CLI 的 tool name / 参数命名发生变化时，需要修改 `ai_message_core` 包——这是错误的修改层。
`ai_message_core` 应该只定义接口和数据类型，不嵌入任何 CLI 特定的命名知识。

## 目标

- `ai_message_core` = 纯接口 + 纯数据类型，零实现
- 每个 CLI 在自己的 capability 里提供 tool name → arg key 映射
- 解析逻辑（codec）保持通用且可配置，不因 CLI 而异
- `ai_message_ui` 通过依赖注入获取 resolver，不直接实例化任何 Default 实现
- CLI 特定的 tool name / key 命名差异隔离在 `services/cli/registry/` 中

## 设计

### 1. `ai_message_core` — 纯接口 + 数据类型

保留（公开 API）：

| 文件 | 内容 |
|------|------|
| `message.dart` | `AiToolCallPart` 等（不变） |
| `tool_edit_hunk.dart` | `AiEditLineKind`、`AiEditLine`、`AiEditHunk`、`AiEditToolTarget`（不变） |
| `tool_edit_hunk_codec.dart` | `AiEditHunkCodec` 接口 — `matches(String)` + `encode(AiToolCallPart)` |
| `tool_edit_target_resolver.dart` | `AiEditToolTargetResolver` 接口 — `resolve(AiToolCallPart)`（去掉 Default* 和 defaultCodecs） |
| `tool_file_target.dart` | `AiToolFileTarget` 数据类型 + `AiToolFileTargetResolver` 接口 |
| `tool_shell_target.dart` | `AiShellToolTarget` 数据类型 + `AiShellToolTargetResolver` 接口 |

删除：

- ❌ `tool_edit_args.dart` — 整个文件，包括 key 列表常量和工具函数
- ❌ `codecs/str_replace_edit_hunk_codec.dart`
- ❌ `codecs/write_edit_hunk_codec.dart`
- ❌ `codecs/unified_diff_edit_hunk_codec.dart`
- ❌ `DefaultAiEditToolTargetResolver` + `defaultCodecs`
- ❌ `DefaultAiToolFileTargetResolver` + `AiToolFileTargetRule` + `CompositeAiToolFileTargetResolver`
- ❌ `DefaultAiShellToolTargetResolver` + `defaultToolNames`

另外 `tool_file_target.dart` 和 `tool_shell_target.dart` 中的私有工具函数（`_firstNonEmptyString`、`_firstPositiveInt`、
`_parsePositiveInt`、`_argsMap`）在新架构中由移到 `edit_codecs/` 的共享工具模块提供，消除重复。

### 2. Codec 实现 — 可配置的泛型类

解析逻辑（怎么从 args 构建 `AiEditHunk`）是通用的，不因 CLI 而异。三个 codec 变成可配置的泛型类，
放在 `client/lib/services/ai_history/edit_codecs/`。

同时，从 `tool_edit_args.dart` 移出的泛型工具函数也放在这里，提供统一的 args 解码和 key 查找能力：

```dart
// edit_codecs/tool_args.dart — 共享工具函数
Map<String, Object?>? toolCallArgsMap(AiToolCallPart part) { ... }
String? firstNonEmptyString(Map<String, Object?>? args, List<String> keys) { ... }
String? optionalString(Map<String, Object?>? args, List<String> keys) { ... }
int? firstPositiveInt(Map<String, Object?>? args, List<String> keys) { ... }
int? parsePositiveInt(Object? value) { ... }
List<String> splitLines(String text) { ... }
```

这些函数替代了原来散落在 `tool_edit_args.dart`、`tool_file_target.dart`、`tool_shell_target.dart` 中的各自私有版本。

```dart
// str_replace_edit_hunk_codec.dart
class StrReplaceEditHunkCodec implements AiEditHunkCodec {
  const StrReplaceEditHunkCodec({
    required this.toolNames,
    required this.pathKeys,
    required this.oldStringKeys,
    required this.newStringKeys,
    this.startLineKeys = const [],
  });

  final Set<String> toolNames;
  final List<String> pathKeys;
  final List<String> oldStringKeys;
  final List<String> newStringKeys;
  final List<String> startLineKeys;

  @override
  bool matches(String toolName) => toolNames.contains(toolName.toLowerCase());

  @override
  AiEditHunk? encode(AiToolCallPart part) {
    // 逻辑不变，key 列表从构造参数获取
  }
}
```

`WriteEditHunkCodec`、`UnifiedDiffEditHunkCodec` 同理。

### 3. Resolver 的 Default 实现

`DefaultAiEditToolTargetResolver`（chain 多个 codec）、`DefaultAiToolFileTargetResolver`（根据 rule 列表匹配）、
`DefaultAiShellToolTargetResolver`——这些解析策略本身是通用的，只是配置不同。放在 `client/lib/services/ai_history/tool_call_resolvers.dart`：

```dart
class DefaultAiEditToolTargetResolver implements AiEditToolTargetResolver {
  const DefaultAiEditToolTargetResolver({required this.codecs});
  final List<AiEditHunkCodec> codecs;
  // resolve() 逻辑不变
}

class DefaultAiToolFileTargetResolver implements AiToolFileTargetResolver {
  const DefaultAiToolFileTargetResolver({required this.rules});
  final List<AiToolFileTargetRule> rules;
  // resolve() 逻辑不变
}

class DefaultAiShellToolTargetResolver implements AiShellToolTargetResolver {
  const DefaultAiShellToolTargetResolver({
    required this.toolNames,
    required this.commandKeys,
  });
  final Set<String> toolNames;
  final List<String> commandKeys;
  // resolve() 逻辑不变
}
```

### 4. CLI Registry — `ToolCallResolvers` capability

新增一个 capability 类型，把 edit / file / shell 三个 resolver 打包：

```dart
// client/lib/services/cli/registry/capabilities/tool_call_resolver_capability.dart
abstract class ToolCallResolvers {
  AiEditToolTargetResolver get editResolver;
  AiToolFileTargetResolver get fileResolver;
  AiShellToolTargetResolver get shellResolver;
}
```

每个 CLI 提供自己的实现。示例——Claude Code：

```dart
// claude_tool_call_resolvers.dart
class ClaudeToolCallResolvers implements ToolCallResolvers {
  @override
  late final editResolver = DefaultAiEditToolTargetResolver(codecs: [
    StrReplaceEditHunkCodec(
      toolNames: {'edit', 'strreplace'},
      pathKeys: ['file_path', 'path', 'file'],
      oldStringKeys: ['old_string', 'oldString'],
      newStringKeys: ['new_string', 'newString'],
      startLineKeys: ['start_line', 'startLine'],
    ),
    WriteEditHunkCodec(
      toolNames: {'write', 'write_file', 'writefile'},
      pathKeys: ['file_path', 'path', 'file'],
      contentKeys: ['content', 'contents'],
    ),
    UnifiedDiffEditHunkCodec(
      toolNames: {'applypatch', 'apply_patch'},
      pathKeys: ['file_path', 'path', 'file'],
      patchKeys: ['patch', 'diff', 'input'],
    ),
  ]);

  @override
  late final fileResolver = DefaultAiToolFileTargetResolver(rules: [
    AiToolFileTargetRule(toolNames: {'read', 'readfile', 'read_file'}, useOffsetLimit: true),
    AiToolFileTargetRule(toolNames: {'write', 'write_file', 'writefile', 'create', 'create_file'}),
    AiToolFileTargetRule(toolNames: {'edit', 'strreplace', 'applypatch', 'apply_patch', 'editnotebook', 'notebookedit'}),
  ]);

  @override
  late final shellResolver = DefaultAiShellToolTargetResolver(
    toolNames: {'bash', 'shell'},
    commandKeys: ['command', 'cmd'],
  );
}
```

`CliToolRegistry` 新增查询方法，遵循现有 capability 查询模式（`registry.capability<T>(cli)`）：

```dart
ToolCallResolvers toolCallResolvers(CliTool cli);
```

每个 CLI 的 `CliToolDefinition` 在 `built_in_cli_tools.dart` 中注册时提供自己的 `ToolCallResolvers` 实现，
与现有的 `ExecutableResolverCapability`、`TerminalBehaviorCapability` 注册方式一致。

### 5. UI 注入层

`ai_message_ui` 本身不依赖任何 Default 实现。`AiToolFileActions` 扩展为同时携带三个 resolver：

```dart
class AiToolFileActions {
  const AiToolFileActions({
    required this.fileResolver,
    required this.editResolver,
    required this.shellResolver,
    this.onOpenFile,
    this.lineHighlighter = const PlainEditLineHighlighter(),
  });

  final AiToolFileTargetResolver fileResolver;
  final AiEditToolTargetResolver editResolver;
  final AiShellToolTargetResolver shellResolver;
  final Future<void> Function(AiToolFileTarget target)? onOpenFile;
  final AiEditLineHighlighter lineHighlighter;
}
```

`tool_call_part_view.dart` 改为从 scope 获取，不再 `const Default*()`：

```dart
final actions = AiToolFileActions.of(context);
final shellTarget = actions.shellResolver.resolve(part);
final editTarget = actions.editResolver.resolve(part);
final fileTarget = actions.fileResolver.resolve(part);
```

App 层（`client/lib`）在创建 session UI 时负责注入：

```
registry.toolCallResolvers(session.cli)
  → AiToolFileActions(fileResolver: ..., editResolver: ..., shellResolver: ...)
  → AiToolFileActionsScope
```

### 6. 文件结构总览

```
ai_message_core/lib/src/
  message.dart                          # AiToolCallPart（不变）
  tool_edit_hunk.dart                   # 纯数据类型（不变）
  tool_edit_hunk_codec.dart             # AiEditHunkCodec 接口
  tool_edit_target_resolver.dart        # AiEditToolTargetResolver 接口
  tool_file_target.dart                 # AiToolFileTarget + AiToolFileTargetResolver 接口
  tool_shell_target.dart                # AiShellToolTarget + AiShellToolTargetResolver 接口

client/lib/services/ai_history/
  edit_codecs/
    tool_args.dart                      # 共享工具函数（argsMap, firstNonEmptyString 等）
    str_replace_edit_hunk_codec.dart    # 泛型 codec
    write_edit_hunk_codec.dart          # 泛型 codec
    unified_diff_edit_hunk_codec.dart   # 泛型 codec
  tool_call_resolvers.dart              # Default* resolver 实现
  workspace_edit_line_highlighter.dart  # WorkspaceAiEditLineHighlighter（不变）

client/lib/services/cli/registry/capabilities/
  tool_call_resolver_capability.dart    # ToolCallResolvers 接口
  claude_tool_call_resolvers.dart       # Claude 配置
  codex_tool_call_resolvers.dart        # Codex 配置
  flashskyai_tool_call_resolvers.dart   # flashskyai 配置
  opencode_tool_call_resolvers.dart     # opencode 配置
  cursor_tool_call_resolvers.dart       # cursor 配置

client/packages/ai_message_ui/lib/src/
  tool_file_actions.dart               # 扩展为携带三个 resolver
  parts/tool_call_part_view.dart        # 从 scope 拿 resolver
```

## 测试

- 每个 codec 的单元测试移到 `client/test/services/ai_history/edit_codecs/`，参数化测试不同的 key 列表
- 每个 CLI 的 `ToolCallResolvers` 实现需要单元测试，验证 tool name 匹配和 arg 解析
- `ai_message_core` 的接口和数据类型的序列化/反序列化测试保留在原包中

## 不涉及范围

- `AiEditLineHighlighter` / `PlainEditLineHighlighter` / `WorkspaceAiEditLineHighlighter` — 这些是纯 UI 渲染，不受影响
- `message.dart`、`subagent_attachment.dart`、`transcript_adapter.dart` 等 ai_message_core 的其他模块不受影响
