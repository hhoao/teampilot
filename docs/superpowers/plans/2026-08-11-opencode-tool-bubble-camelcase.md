# opencode 工具气泡适配（camelCase filePath）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** opencode 的 `edit` / `write` / `read` 工具调用（camelCase `filePath` 参数）能正确渲染编辑卡片 / 写文件卡片 / 文件链接气泡。

**Architecture:** 遵循 docs/tool-call-parsing-convention.md —— 共享解析层（`SharedToolCallResolvers`）保持纯净，把 key/toolName 列表提取为 public static const；`OpencodeToolCallResolvers` 改为独立配置（`implements ToolCallResolversCapability`），在共享 key 基础上追加 `filePath`（追加而非替换，兼容旧 snake_case 会话）。

**Tech Stack:** Flutter / Dart, `ai_message_core`（纯接口 + 数据）, `client/lib/services/ai_history/`（可配置泛型 codec + resolver）。

## Global Constraints

- **禁止**在 `ai_message_core` / 共享 codec 中硬编码 CLI 特定的 tool name 或 argument key 映射（tool-call-parsing-convention.md）。
- 共享层行为对其它 CLI（claude / codex / cursor / flashskyai）**零变化** —— 只做常量提取，不改变任何解析结果。
- opencode 配置在 per-CLI 目录 `client/lib/services/cli/opencode/capabilities/`（enforce-per-CLI-directory-layout 约定），不放 registry 目录。
- key 列表**追加** `'filePath'`，不得替换原有 snake_case key（旧会话向后兼容）。
- 验证命令：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`。
- 每次 commit 只暂存本任务相关文件（工作区已有其它未提交改动，不要 `git add -A`）。

---

### Task 1: 共享 key/toolName 常量提取

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/shared_tool_call_resolvers.dart`

**Interfaces:**
- Consumes: 无
- Produces: `abstract final class SharedToolCallResolverKeys` 及静态常量（Task 3 使用）：
  - `Set<String> editToolNames`, `writeToolNames`, `diffToolNames`, `fileReadToolNames`, `fileWriteToolNames`, `fileEditToolNames`, `shellToolNames`
  - `List<String> editPathKeys`, `editOldStringKeys`, `editNewStringKeys`, `editStartLineKeys`, `writePathKeys`, `writeContentKeys`, `diffPatchKeys`

- [ ] **Step 1: 提取常量为 public static**

在 `SharedToolCallResolvers` 类前新增：

```dart
/// Baseline tool-name / argument-key lists for the shared resolvers.
/// Per-CLI resolvers reuse these and extend them (e.g. OpenCode's camelCase
/// `filePath`), keeping CLI-specific keys out of the shared package.
abstract final class SharedToolCallResolverKeys {
  static const editToolNames = {
    'strreplace',
    'edit',
    'editnotebook',
    'notebookedit',
  };
  static const editPathKeys = ['file_path', 'path', 'file', 'target_file'];
  static const editOldStringKeys = ['old_string', 'oldString'];
  static const editNewStringKeys = ['new_string', 'newString'];
  static const editStartLineKeys = ['start_line', 'startLine'];

  static const writeToolNames = {
    'write',
    'writefile',
    'write_file',
    'create',
    'create_file',
  };
  static const writePathKeys = ['file_path', 'path', 'file', 'target_file'];
  static const writeContentKeys = ['content', 'contents'];

  static const diffToolNames = {'applypatch', 'apply_patch'};
  static const diffPatchKeys = ['patch', 'diff', 'input'];

  static const fileReadToolNames = {'read', 'readfile', 'read_file'};
  static const fileWriteToolNames = {
    'write',
    'writefile',
    'write_file',
    'create',
    'create_file',
  };
  static const fileEditToolNames = {
    'edit',
    'strreplace',
    'applypatch',
    'editnotebook',
    'notebookedit',
  };

  static const shellToolNames = {
    'bash',
    'shell',
    'shell_command',
    'exec_command',
    'run_shell_command',
    'run_terminal_cmd',
  };
}
```

- [ ] **Step 2: SharedToolCallResolvers 内部改引用常量**

把 `_strReplaceCodec` / `_writeCodec` / `_unifiedDiffCodec` / `_fileRules` / `_shellToolNames` 的硬编码列表替换为 `SharedToolCallResolverKeys.*` 引用，例如：

```dart
  static const _strReplaceCodec = StrReplaceEditHunkCodec(
    toolNames: SharedToolCallResolverKeys.editToolNames,
    pathKeys: SharedToolCallResolverKeys.editPathKeys,
    oldStringKeys: SharedToolCallResolverKeys.editOldStringKeys,
    newStringKeys: SharedToolCallResolverKeys.editNewStringKeys,
    startLineKeys: SharedToolCallResolverKeys.editStartLineKeys,
  );

  static const _writeCodec = WriteEditHunkCodec(
    toolNames: SharedToolCallResolverKeys.writeToolNames,
    pathKeys: SharedToolCallResolverKeys.writePathKeys,
    contentKeys: SharedToolCallResolverKeys.writeContentKeys,
  );

  static const _unifiedDiffCodec = UnifiedDiffEditHunkCodec(
    toolNames: SharedToolCallResolverKeys.diffToolNames,
    pathKeys: SharedToolCallResolverKeys.editPathKeys,
    patchKeys: SharedToolCallResolverKeys.diffPatchKeys,
  );

  static const _fileRules = <AiToolFileTargetRule>[
    AiToolFileTargetRule(
      toolNames: SharedToolCallResolverKeys.fileReadToolNames,
      useOffsetLimit: true,
    ),
    AiToolFileTargetRule(
      toolNames: SharedToolCallResolverKeys.fileWriteToolNames,
    ),
    AiToolFileTargetRule(
      toolNames: SharedToolCallResolverKeys.fileEditToolNames,
    ),
  ];
```

`_shellToolNames` 替换为 `SharedToolCallResolverKeys.shellToolNames`。列表值保持与原来**逐字符一致**（`_fileRules` 原样保留默认 pathKeys，即不传）。

- [ ] **Step 3: 验证无行为变化**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: analyze 0 issues；全部测试 PASS（无 resolver 相关测试断言会变）。

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/shared_tool_call_resolvers.dart
git commit -m "refactor(cli): expose shared tool call resolver key constants"
```

---

### Task 2: opencode resolver 测试（TDD 先红）

**Files:**
- Create: `client/test/services/cli/registry/capabilities/opencode_tool_call_resolvers_test.dart`

**Interfaces:**
- Consumes: `OpencodeToolCallResolvers`（已存在，`client/lib/services/cli/opencode/capabilities/tool_call_resolvers.dart`，当前 extends SharedToolCallResolvers）
- Produces: 测试覆盖 edit/write/read 的 camelCase `filePath`、snake_case 兼容、bash 不受影响

- [ ] **Step 1: 写失败测试**

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/opencode/capabilities/tool_call_resolvers.dart';

void main() {
  const resolvers = OpencodeToolCallResolvers();

  AiToolCallPart toolCall(String name, Map<String, Object?> args) {
    return AiToolCallPart(
      toolCallId: 'call-1',
      toolName: name,
      args: args,
    );
  }

  group('editResolver', () {
    test('edit with camelCase filePath/oldString/newString resolves to hunk',
        () {
      final target = resolvers.editResolver.resolve(toolCall('edit', {
        'filePath': '/src/main.dart',
        'oldString': 'hello',
        'newString': 'goodbye',
      }));
      expect(target, isNotNull);
      expect(target!.hunk.path, '/src/main.dart');
      expect(target.hunk.removedCount, 1);
      expect(target.hunk.addedCount, 1);
      expect(target.hunk.lines[0].kind, AiEditLineKind.remove);
      expect(target.hunk.lines[1].kind, AiEditLineKind.add);
    });

    test('write with camelCase filePath/content resolves to hunk', () {
      final target = resolvers.editResolver.resolve(toolCall('write', {
        'filePath': '/lib/app.dart',
        'content': 'line1\nline2',
      }));
      expect(target, isNotNull);
      expect(target!.hunk.path, '/lib/app.dart');
      expect(target.hunk.addedCount, 2);
      expect(target.hunk.removedCount, 0);
    });

    test('legacy snake_case file_path still resolves', () {
      final target = resolvers.editResolver.resolve(toolCall('edit', {
        'file_path': '/old.dart',
        'old_string': 'a',
        'new_string': 'b',
      }));
      expect(target, isNotNull);
      expect(target!.hunk.path, '/old.dart');
    });

    test('bash tool does not resolve as edit', () {
      final target =
          resolvers.editResolver.resolve(toolCall('bash', {'command': 'ls'}));
      expect(target, isNull);
    });
  });

  group('fileResolver', () {
    test('read with filePath + offset/limit resolves with line range', () {
      final target = resolvers.fileResolver.resolve(toolCall('read', {
        'filePath': '/a.dart',
        'offset': 10,
        'limit': 5,
      }));
      expect(target, isNotNull);
      expect(target!.path, '/a.dart');
      expect(target.startLine, 10);
      expect(target.endLine, 14);
    });

    test('edit with filePath resolves to file target', () {
      final target = resolvers.fileResolver.resolve(toolCall('edit', {
        'filePath': '/a.dart',
        'oldString': 'x',
        'newString': 'y',
      }));
      expect(target, isNotNull);
      expect(target!.path, '/a.dart');
    });

    test('write with filePath resolves to file target', () {
      final target = resolvers.fileResolver.resolve(toolCall('write', {
        'filePath': '/b.dart',
        'content': 'c',
      }));
      expect(target, isNotNull);
      expect(target!.path, '/b.dart');
    });
  });

  group('shellResolver', () {
    test('bash with command resolves', () {
      final target =
          resolvers.shellResolver.resolve(toolCall('bash', {'command': 'ls -la'}));
      expect(target, isNotNull);
      expect(target!.command, 'ls -la');
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && flutter test test/services/cli/registry/capabilities/opencode_tool_call_resolvers_test.dart`
Expected: FAIL —— 所有 camelCase 断言失败（`edit` / `write` / `read` 的 editResolver 与 fileResolver 均因 pathKeys 无 `filePath` 返回 null）；`legacy snake_case` 与 `bash` 测试当前 PASS。

---

### Task 3: OpencodeToolCallResolvers 独立配置

**Files:**
- Modify: `client/lib/services/cli/opencode/capabilities/tool_call_resolvers.dart`

**Interfaces:**
- Consumes: `SharedToolCallResolverKeys`（Task 1）、`ConfigurableAiEditToolTargetResolver` / `ConfigurableAiToolFileTargetResolver` / `ConfigurableAiShellToolTargetResolver` / `defaultToolCallCategoryResolver`（均在 `client/lib/services/ai_history/`）
- Produces: `OpencodeToolCallResolvers implements ToolCallResolversCapability`（const 构造，与 Task 2 测试的用法一致）

- [ ] **Step 1: 实现 opencode 专属配置**

完整替换文件内容：

```dart
import 'package:ai_message_core/ai_message_core.dart'
    hide
        StrReplaceEditHunkCodec,
        WriteEditHunkCodec,
        UnifiedDiffEditHunkCodec;

import '../../ai_history/edit_codecs/str_replace_edit_hunk_codec.dart';
import '../../ai_history/edit_codecs/unified_diff_edit_hunk_codec.dart';
import '../../ai_history/edit_codecs/write_edit_hunk_codec.dart';
import '../../ai_history/tool_call_categories.dart';
import '../../ai_history/tool_call_resolvers.dart';
import '../../registry/capabilities/shared_tool_call_resolvers.dart';
import '../../registry/capabilities/tool_call_resolver_capability.dart';

/// OpenCode tool-call resolvers: shared baseline plus the camelCase
/// `filePath` argument key OpenCode emits for `edit` / `write` / `read`.
class OpencodeToolCallResolvers implements ToolCallResolversCapability {
  const OpencodeToolCallResolvers();

  static const _pathKeys = [
    ...SharedToolCallResolverKeys.editPathKeys,
    'filePath',
  ];

  static const _strReplaceCodec = StrReplaceEditHunkCodec(
    toolNames: SharedToolCallResolverKeys.editToolNames,
    pathKeys: _pathKeys,
    oldStringKeys: SharedToolCallResolverKeys.editOldStringKeys,
    newStringKeys: SharedToolCallResolverKeys.editNewStringKeys,
    startLineKeys: SharedToolCallResolverKeys.editStartLineKeys,
  );

  static const _writeCodec = WriteEditHunkCodec(
    toolNames: SharedToolCallResolverKeys.writeToolNames,
    pathKeys: _pathKeys,
    contentKeys: SharedToolCallResolverKeys.writeContentKeys,
  );

  static const _unifiedDiffCodec = UnifiedDiffEditHunkCodec(
    toolNames: SharedToolCallResolverKeys.diffToolNames,
    pathKeys: _pathKeys,
    patchKeys: SharedToolCallResolverKeys.diffPatchKeys,
  );

  static const _fileRules = <AiToolFileTargetRule>[
    AiToolFileTargetRule(
      toolNames: SharedToolCallResolverKeys.fileReadToolNames,
      pathKeys: _pathKeys,
      useOffsetLimit: true,
    ),
    AiToolFileTargetRule(
      toolNames: SharedToolCallResolverKeys.fileWriteToolNames,
      pathKeys: _pathKeys,
    ),
    AiToolFileTargetRule(
      toolNames: SharedToolCallResolverKeys.fileEditToolNames,
      pathKeys: _pathKeys,
    ),
  ];

  @override
  AiEditToolTargetResolver get editResolver =>
      const ConfigurableAiEditToolTargetResolver(
        codecs: [_strReplaceCodec, _writeCodec, _unifiedDiffCodec],
      );

  @override
  AiToolFileTargetResolver get fileResolver =>
      const ConfigurableAiToolFileTargetResolver(rules: _fileRules);

  @override
  AiShellToolTargetResolver get shellResolver =>
      const ConfigurableAiShellToolTargetResolver(
        toolNames: SharedToolCallResolverKeys.shellToolNames,
      );

  @override
  AiToolCallCategoryResolver get categoryResolver =>
      defaultToolCallCategoryResolver;
}
```

- [ ] **Step 2: 运行测试确认通过**

Run: `cd client && flutter test test/services/cli/registry/capabilities/opencode_tool_call_resolvers_test.dart`
Expected: 全部 PASS（含 Task 2 的 camelCase 测试）。

- [ ] **Step 3: Commit**

```bash
git add client/lib/services/cli/opencode/capabilities/tool_call_resolvers.dart client/test/services/cli/registry/capabilities/opencode_tool_call_resolvers_test.dart
git commit -m "feat(cli): adapt opencode edit/write/read tool bubbles to camelCase filePath"
```

---

### Task 4: 全量验证

**Files:** 无代码改动

- [ ] **Step 1: 全量 analyze + test**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: analyze 0 issues；全部测试 PASS。

- [ ] **Step 2: 确认共享层未受影响**

Run: `cd client && git diff HEAD --stat -- client/lib/services/cli/registry/capabilities/shared_tool_call_resolvers.dart`
Expected: 该文件 diff 仅包含常量提取（无逻辑变化）。其余 CLI（claude / codex / cursor / flashskyai）文件无改动。

- [ ] **Step 3: 汇报完成**

向用户汇报：opencode `edit` / `write` / `read` 气泡适配完成；说明改动文件与验证结果。
