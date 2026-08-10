# Tool Call Resolver 重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `ai_message_core` 重构为纯接口 + 数据类型包，把所有 Default 实现和 CLI 特定的 tool name/key 映射移出到 `client/lib/services/` 和 CLI registry 中。

**Architecture:** `ai_message_core` 只保留接口（`AiEditHunkCodec`、`AiEditToolTargetResolver`、`AiToolFileTargetResolver`、`AiShellToolTargetResolver`）+ 纯数据类型（`AiEditHunk`、`AiEditLine`、`AiToolFileTarget`、`AiShellToolTarget`）。Codec 实现变为可配置泛型类，放在 `client/lib/services/ai_history/edit_codecs/`。每个 CLI 通过 `ToolCallResolvers` capability 提供自己的 tool name → arg key 配置。UI 层通过 `AiToolFileActionsScope` 依赖注入获取 resolver。

**Tech Stack:** Dart, Flutter, ai_message_core, ai_message_ui

**关联 Spec:** `docs/superpowers/specs/2026-08-10-tool-call-resolver-refactor-design.md`

---

### Task 1: 创建共享工具函数模块

**Files:**
- Create: `client/lib/services/ai_history/edit_codecs/tool_args.dart`
- Test: `client/test/services/ai_history/edit_codecs/tool_args_test.dart`

把原来散落在 `tool_edit_args.dart`、`tool_file_target.dart`、`tool_shell_target.dart` 的泛型工具函数统一到一个位置。

- [ ] **Step 1: 创建 `tool_args.dart`**

```dart
// client/lib/services/ai_history/edit_codecs/tool_args.dart
import 'dart:convert';
import 'package:ai_message_core/ai_message_core.dart';

Map<String, Object?>? toolCallArgsMap(AiToolCallPart part) {
  if (part.args != null && part.args!.isNotEmpty) return part.args;
  final text = part.argsText?.trim();
  if (text == null || text.isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map) return null;
    return {
      for (final e in decoded.entries) e.key.toString(): e.value,
    };
  } catch (_) {
    return null;
  }
}

String? firstNonEmptyString(Map<String, Object?>? args, List<String> keys) {
  if (args == null) return null;
  for (final key in keys) {
    final value = args[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

/// Returns the string when [keys] is present with a String value (including
/// empty). Null when no key is present or the value is not a String.
String? optionalString(Map<String, Object?>? args, List<String> keys) {
  if (args == null) return null;
  for (final key in keys) {
    if (!args.containsKey(key)) continue;
    final value = args[key];
    return value is String ? value : null;
  }
  return null;
}

int? firstPositiveInt(Map<String, Object?>? args, List<String> keys) {
  if (args == null) return null;
  for (final key in keys) {
    final parsed = parsePositiveInt(args[key]);
    if (parsed != null) return parsed;
  }
  return null;
}

int? parsePositiveInt(Object? value) {
  if (value is int && value >= 1) return value;
  if (value is num && value >= 1) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null && parsed >= 1) return parsed;
  }
  return null;
}

List<String> splitLines(String text) {
  if (text.isEmpty) return const [];
  return text.split('\n');
}
```

- [ ] **Step 2: 创建测试文件 `tool_args_test.dart`**

```dart
// client/test/services/ai_history/edit_codecs/tool_args_test.dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:teampilot/services/ai_history/edit_codecs/tool_args.dart';
import 'package:test/test.dart';

void main() {
  group('toolCallArgsMap', () {
    test('returns args when non-empty', () {
      final part = AiToolCallPart(
        toolCallId: '1',
        toolName: 'test',
        args: {'key': 'value'},
      );
      expect(toolCallArgsMap(part), {'key': 'value'});
    });

    test('parses argsText JSON when args is empty', () {
      final part = AiToolCallPart(
        toolCallId: '1',
        toolName: 'test',
        args: {},
        argsText: '{"key": "value"}',
      );
      expect(toolCallArgsMap(part), {'key': 'value'});
    });

    test('returns null for empty args and invalid argsText', () {
      final part = AiToolCallPart(
        toolCallId: '1',
        toolName: 'test',
        args: {},
      );
      expect(toolCallArgsMap(part), isNull);
    });
  });

  group('firstNonEmptyString', () {
    test('finds first match in key list', () {
      final args = {'b': '  ', 'c': 'hello'};
      expect(firstNonEmptyString(args, ['a', 'b', 'c']), 'hello');
    });

    test('returns null when no key matches', () {
      expect(firstNonEmptyString({'x': 'y'}, ['a', 'b']), isNull);
    });

    test('returns null for null args', () {
      expect(firstNonEmptyString(null, ['a']), isNull);
    });
  });

  group('optionalString', () {
    test('returns string even if empty', () {
      expect(optionalString({'a': ''}, ['a']), '');
    });

    test('returns null when key not present', () {
      expect(optionalString({'x': 'y'}, ['a']), isNull);
    });
  });

  group('firstPositiveInt', () {
    test('parses int >= 1', () {
      expect(firstPositiveInt({'a': 5}, ['a']), 5);
    });

    test('parses string int', () {
      expect(firstPositiveInt({'a': '10'}, ['a']), 10);
    });

    test('returns null for zero', () {
      expect(firstPositiveInt({'a': 0}, ['a']), isNull);
    });
  });

  group('splitLines', () {
    test('splits on newline', () {
      expect(splitLines('a\nb\nc'), ['a', 'b', 'c']);
    });

    test('returns empty list for empty string', () {
      expect(splitLines(''), isEmpty);
    });
  });
}
```

- [ ] **Step 3: 运行测试确认通过**

```bash
cd client && flutter test test/services/ai_history/edit_codecs/tool_args_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/ai_history/edit_codecs/tool_args.dart client/test/services/ai_history/edit_codecs/tool_args_test.dart
git commit -m "feat: add shared tool_args utilities for edit codecs

Move generic arg-parsing helpers out of ai_message_core into a shared
module under services/ai_history/edit_codecs/.
"
```

---

### Task 2: 移植 StrReplaceEditHunkCodec 为可配置泛型类

**Files:**
- Create: `client/lib/services/ai_history/edit_codecs/str_replace_edit_hunk_codec.dart`
- Test: `client/test/services/ai_history/edit_codecs/str_replace_edit_hunk_codec_test.dart`

- [ ] **Step 1: 创建可配置的 `StrReplaceEditHunkCodec`**

```dart
// client/lib/services/ai_history/edit_codecs/str_replace_edit_hunk_codec.dart
import 'package:ai_message_core/ai_message_core.dart';
import 'tool_args.dart';

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
    if (!matches(part.toolName)) return null;

    final args = toolCallArgsMap(part);
    final path = firstNonEmptyString(args, pathKeys);
    if (path == null) return null;

    final oldString = optionalString(args, oldStringKeys);
    if (oldString == null) return null;

    final newString = optionalString(args, newStringKeys);
    if (newString == null) return null;

    final oldLines = splitLines(oldString);
    final newLines = splitLines(newString);
    if (oldLines.isEmpty && newLines.isEmpty) return null;

    final startLine = firstPositiveInt(args, startLineKeys);
    final lines = <AiEditLine>[];
    var lineNumber = startLine;

    for (final text in oldLines) {
      lines.add(AiEditLine(
        kind: AiEditLineKind.remove,
        text: text,
        lineNumber: lineNumber,
      ));
      if (lineNumber != null) lineNumber = lineNumber! + 1;
    }

    for (final text in newLines) {
      lines.add(AiEditLine(
        kind: AiEditLineKind.add,
        text: text,
        lineNumber: lineNumber,
      ));
      if (lineNumber != null) lineNumber = lineNumber! + 1;
    }

    return AiEditHunk(
      path: path,
      lines: lines,
      addedCount: newLines.length,
      removedCount: oldLines.length,
      startLine: startLine,
    );
  }
}
```

- [ ] **Step 2: 创建测试**

```dart
// client/test/services/ai_history/edit_codecs/str_replace_edit_hunk_codec_test.dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:teampilot/services/ai_history/edit_codecs/str_replace_edit_hunk_codec.dart';
import 'package:test/test.dart';

void main() {
  const codec = StrReplaceEditHunkCodec(
    toolNames: {'edit', 'strreplace'},
    pathKeys: ['file_path', 'path'],
    oldStringKeys: ['old_string', 'oldString'],
    newStringKeys: ['new_string', 'newString'],
    startLineKeys: ['start_line', 'startLine'],
  );

  group('matches', () {
    test('matches edit', () => expect(codec.matches('edit'), isTrue));
    test('matches Edit (case-insensitive)', () => expect(codec.matches('Edit'), isTrue));
    test('does not match write', () => expect(codec.matches('write'), isFalse));
  });

  group('encode', () {
    test('returns AiEditHunk with add and remove lines', () {
      final part = AiToolCallPart(
        toolCallId: '1',
        toolName: 'edit',
        args: {
          'file_path': 'a.dart',
          'old_string': 'old',
          'new_string': 'new',
        },
      );
      final hunk = codec.encode(part)!;
      expect(hunk.path, 'a.dart');
      expect(hunk.addedCount, 1);
      expect(hunk.removedCount, 1);
      expect(hunk.lines[0].kind, AiEditLineKind.remove);
      expect(hunk.lines[0].text, 'old');
      expect(hunk.lines[1].kind, AiEditLineKind.add);
      expect(hunk.lines[1].text, 'new');
    });

    test('returns null for missing path', () {
      final part = AiToolCallPart(
        toolCallId: '1',
        toolName: 'edit',
        args: {'old_string': 'a', 'new_string': 'b'},
      );
      expect(codec.encode(part), isNull);
    });
  });
}
```

- [ ] **Step 3: 运行测试确认通过**

```bash
cd client && flutter test test/services/ai_history/edit_codecs/str_replace_edit_hunk_codec_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/ai_history/edit_codecs/str_replace_edit_hunk_codec.dart client/test/services/ai_history/edit_codecs/str_replace_edit_hunk_codec_test.dart
git commit -m "feat: add configurable StrReplaceEditHunkCodec"
```

---

### Task 3: 移植 WriteEditHunkCodec 为可配置泛型类

**Files:**
- Create: `client/lib/services/ai_history/edit_codecs/write_edit_hunk_codec.dart`
- Test: `client/test/services/ai_history/edit_codecs/write_edit_hunk_codec_test.dart`

- [ ] **Step 1: 创建可配置的 `WriteEditHunkCodec`**

```dart
// client/lib/services/ai_history/edit_codecs/write_edit_hunk_codec.dart
import 'package:ai_message_core/ai_message_core.dart';
import 'tool_args.dart';

class WriteEditHunkCodec implements AiEditHunkCodec {
  const WriteEditHunkCodec({
    required this.toolNames,
    required this.pathKeys,
    this.contentKeys = const ['content', 'contents'],
  });

  final Set<String> toolNames;
  final List<String> pathKeys;
  final List<String> contentKeys;

  static const _maxEncodedLines = 500;

  @override
  bool matches(String toolName) => toolNames.contains(toolName.toLowerCase());

  @override
  AiEditHunk? encode(AiToolCallPart part) {
    if (!matches(part.toolName)) return null;

    final args = toolCallArgsMap(part);
    final path = firstNonEmptyString(args, pathKeys);
    if (path == null) return null;

    final contents = firstNonEmptyString(args, contentKeys);
    if (contents == null) return null;

    final contentLines = splitLines(contents);
    if (contentLines.isEmpty) return null;

    final encodedLines = <AiEditLine>[];
    final limit = contentLines.length < _maxEncodedLines
        ? contentLines.length
        : _maxEncodedLines;
    for (var i = 0; i < limit; i++) {
      encodedLines.add(AiEditLine(
        kind: AiEditLineKind.add,
        text: contentLines[i],
      ));
    }

    return AiEditHunk(
      path: path,
      lines: encodedLines,
      addedCount: contentLines.length,
      removedCount: 0,
    );
  }
}
```

- [ ] **Step 2: 创建测试**

```dart
// client/test/services/ai_history/edit_codecs/write_edit_hunk_codec_test.dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:teampilot/services/ai_history/edit_codecs/write_edit_hunk_codec.dart';
import 'package:test/test.dart';

void main() {
  const codec = WriteEditHunkCodec(
    toolNames: {'write', 'write_file', 'writefile'},
    pathKeys: ['file_path', 'path', 'file'],
  );

  test('matches write and write_file', () {
    expect(codec.matches('write'), isTrue);
    expect(codec.matches('Write_File'), isTrue);
    expect(codec.matches('bash'), isFalse);
  });

  test('encodes write with content lines', () {
    final part = AiToolCallPart(
      toolCallId: '1',
      toolName: 'write',
      args: {
        'file_path': 'b.dart',
        'content': 'line1\nline2',
      },
    );
    final hunk = codec.encode(part)!;
    expect(hunk.path, 'b.dart');
    expect(hunk.addedCount, 2);
    expect(hunk.removedCount, 0);
  });
}
```

- [ ] **Step 3: 运行测试确认通过**

```bash
cd client && flutter test test/services/ai_history/edit_codecs/write_edit_hunk_codec_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/ai_history/edit_codecs/write_edit_hunk_codec.dart client/test/services/ai_history/edit_codecs/write_edit_hunk_codec_test.dart
git commit -m "feat: add configurable WriteEditHunkCodec"
```

---

### Task 4: 移植 UnifiedDiffEditHunkCodec 为可配置泛型类

**Files:**
- Create: `client/lib/services/ai_history/edit_codecs/unified_diff_edit_hunk_codec.dart`
- Test: `client/test/services/ai_history/edit_codecs/unified_diff_edit_hunk_codec_test.dart`

- [ ] **Step 1: 创建可配置的 `UnifiedDiffEditHunkCodec`**

```dart
// client/lib/services/ai_history/edit_codecs/unified_diff_edit_hunk_codec.dart
import 'package:ai_message_core/ai_message_core.dart';
import 'tool_args.dart';

class UnifiedDiffEditHunkCodec implements AiEditHunkCodec {
  const UnifiedDiffEditHunkCodec({
    required this.toolNames,
    required this.pathKeys,
    this.patchKeys = const ['patch', 'diff', 'input'],
  });

  final Set<String> toolNames;
  final List<String> pathKeys;
  final List<String> patchKeys;

  static final _hunkHeader = RegExp(r'@@\s*-\d+(?:,\d+)?\s*\+(\d+)');

  @override
  bool matches(String toolName) => toolNames.contains(toolName.toLowerCase());

  @override
  AiEditHunk? encode(AiToolCallPart part) {
    if (!matches(part.toolName)) return null;

    final args = toolCallArgsMap(part);
    final patch = firstNonEmptyString(args, patchKeys);
    if (patch == null) return null;

    var path = firstNonEmptyString(args, pathKeys);
    int? startLine;
    final lines = <AiEditLine>[];
    var addedCount = 0;
    var removedCount = 0;

    for (final rawLine in splitLines(patch)) {
      if (rawLine.startsWith('@@')) {
        if (startLine == null) {
          final match = _hunkHeader.firstMatch(rawLine);
          if (match != null) {
            startLine = int.tryParse(match.group(1)!);
          }
        }
        continue;
      }

      if (rawLine.startsWith('---')) {
        path ??= _pathFromDiffHeader(rawLine);
        continue;
      }

      if (rawLine.startsWith('+++')) {
        final headerPath = _pathFromDiffHeader(rawLine);
        if (headerPath != null) path = path ?? headerPath;
        continue;
      }

      if (rawLine.isEmpty) continue;

      final prefix = rawLine[0];
      if (prefix == '+') {
        lines.add(AiEditLine(kind: AiEditLineKind.add, text: rawLine.substring(1)));
        addedCount++;
      } else if (prefix == '-') {
        lines.add(AiEditLine(kind: AiEditLineKind.remove, text: rawLine.substring(1)));
        removedCount++;
      } else if (prefix == ' ') {
        lines.add(AiEditLine(kind: AiEditLineKind.context, text: rawLine.substring(1)));
      } else {
        lines.add(AiEditLine(kind: AiEditLineKind.context, text: rawLine));
      }
    }

    if (path == null || (addedCount == 0 && removedCount == 0)) return null;

    return AiEditHunk(
      path: path,
      lines: lines,
      addedCount: addedCount,
      removedCount: removedCount,
      startLine: startLine,
    );
  }

  static String? _pathFromDiffHeader(String line) {
    String rest;
    if (line.startsWith('--- ')) {
      rest = line.substring(4).trim();
    } else if (line.startsWith('+++ ')) {
      rest = line.substring(4).trim();
    } else {
      return null;
    }
    if (rest.startsWith('a/')) rest = rest.substring(2);
    if (rest.startsWith('b/')) rest = rest.substring(2);
    return rest.isEmpty ? null : rest;
  }
}
```

- [ ] **Step 2: 创建测试**

```dart
// client/test/services/ai_history/edit_codecs/unified_diff_edit_hunk_codec_test.dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:teampilot/services/ai_history/edit_codecs/unified_diff_edit_hunk_codec.dart';
import 'package:test/test.dart';

void main() {
  const codec = UnifiedDiffEditHunkCodec(
    toolNames: {'applypatch', 'apply_patch'},
    pathKeys: ['file_path', 'path', 'file'],
  );

  test('matches applypatch', () {
    expect(codec.matches('applypatch'), isTrue);
    expect(codec.matches('Apply_Patch'), isTrue);
    expect(codec.matches('edit'), isFalse);
  });

  test('parses unified diff patch', () {
    final part = AiToolCallPart(
      toolCallId: '1',
      toolName: 'applypatch',
      args: {
        'file_path': 'c.dart',
        'patch': '@@ -1,2 +3 @@\n-old line\n+new line',
      },
    );
    final hunk = codec.encode(part)!;
    expect(hunk.path, 'c.dart');
    expect(hunk.addedCount, 1);
    expect(hunk.removedCount, 1);
  });
}
```

- [ ] **Step 3: 运行测试确认通过**

```bash
cd client && flutter test test/services/ai_history/edit_codecs/unified_diff_edit_hunk_codec_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/ai_history/edit_codecs/unified_diff_edit_hunk_codec.dart client/test/services/ai_history/edit_codecs/unified_diff_edit_hunk_codec_test.dart
git commit -m "feat: add configurable UnifiedDiffEditHunkCodec"
```

---

### Task 5: 创建 Default* Resolver 实现

**Files:**
- Create: `client/lib/services/ai_history/tool_call_resolvers.dart`

- [ ] **Step 1: 创建 `tool_call_resolvers.dart`**

将三个 Default* resolver 实现统一放在这里，接受配置参数而非硬编码。

```dart
// client/lib/services/ai_history/tool_call_resolvers.dart
import 'package:ai_message_core/ai_message_core.dart';
import 'edit_codecs/tool_args.dart';

// --- Edit resolver ---

class ConfigurableAiEditToolTargetResolver implements AiEditToolTargetResolver {
  const ConfigurableAiEditToolTargetResolver({required this.codecs});

  final List<AiEditHunkCodec> codecs;

  @override
  AiEditToolTarget? resolve(AiToolCallPart part) {
    for (final codec in codecs) {
      if (!codec.matches(part.toolName)) continue;
      final hunk = codec.encode(part);
      if (hunk != null) return AiEditToolTarget(hunk: hunk);
    }
    return null;
  }
}

// --- File resolver ---

class AiToolFileTargetRule {
  const AiToolFileTargetRule({
    required this.toolNames,
    this.pathKeys = const ['file_path', 'path', 'file', 'target_file'],
    this.startLineKeys = const ['start_line', 'startLine'],
    this.endLineKeys = const ['end_line', 'endLine'],
    this.useOffsetLimit = false,
  });

  final Set<String> toolNames;
  final List<String> pathKeys;
  final List<String> startLineKeys;
  final List<String> endLineKeys;
  final bool useOffsetLimit;
}

class ConfigurableAiToolFileTargetResolver implements AiToolFileTargetResolver {
  const ConfigurableAiToolFileTargetResolver({required this.rules});

  final List<AiToolFileTargetRule> rules;

  @override
  AiToolFileTarget? resolve(AiToolCallPart part) {
    final toolLower = part.toolName.toLowerCase();
    AiToolFileTargetRule? rule;
    for (final candidate in rules) {
      if (candidate.toolNames.contains(toolLower)) {
        rule = candidate;
        break;
      }
    }
    if (rule == null) return null;

    final path = firstNonEmptyString(part.args, rule.pathKeys);
    if (path == null) return null;

    final lines = _extractLines(part, rule);
    return AiToolFileTarget(
      path: path,
      startLine: lines.$1,
      endLine: lines.$2,
    );
  }

  static final _lineRangePattern = RegExp(r'L(\d+)(?:-(\d+))?');

  static (int?, int?) _extractLines(
      AiToolCallPart part, AiToolFileTargetRule rule) {
    final args = part.args;
    if (args != null) {
      if (rule.useOffsetLimit) {
        final offset = parsePositiveInt(args['offset']);
        final limit = parsePositiveInt(args['limit']);
        if (offset != null && limit != null) {
          return (offset, offset + limit - 1);
        }
      }

      final start = firstPositiveInt(args, rule.startLineKeys);
      final end = firstPositiveInt(args, rule.endLineKeys);
      if (start != null || end != null) {
        if (start == null && end != null) return (end, end);
        return (start, end);
      }
    }

    return _parseLineRangeFromArgsText(part.argsText);
  }

  static (int?, int?) _parseLineRangeFromArgsText(String? argsText) {
    if (argsText == null || argsText.isEmpty) return (null, null);
    final match = _lineRangePattern.firstMatch(argsText);
    if (match == null) return (null, null);

    final start = int.tryParse(match.group(1)!);
    if (start == null || start < 1) return (null, null);

    final endGroup = match.group(2);
    if (endGroup == null) return (start, start);

    final end = int.tryParse(endGroup);
    if (end == null || end < 1) return (start, null);

    return (start, end);
  }
}

// --- Shell resolver ---

class ConfigurableAiShellToolTargetResolver
    implements AiShellToolTargetResolver {
  const ConfigurableAiShellToolTargetResolver({
    required this.toolNames,
    required this.commandKeys,
    this.descriptionKeys = const ['description'],
  });

  final Set<String> toolNames;
  final List<String> commandKeys;
  final List<String> descriptionKeys;

  @override
  AiShellToolTarget? resolve(AiToolCallPart part) {
    if (!toolNames.contains(part.toolName.toLowerCase())) return null;

    final map = toolCallArgsMap(part);
    final command = firstNonEmptyString(map, commandKeys);
    if (command == null) return null;

    final description = firstNonEmptyString(map, descriptionKeys);
    return AiShellToolTarget(command: command, description: description);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add client/lib/services/ai_history/tool_call_resolvers.dart
git commit -m "feat: add configurable Default* resolver implementations

Move DefaultAiEditToolTargetResolver, DefaultAiToolFileTargetResolver, and
DefaultAiShellToolTargetResolver out of ai_message_core into configurable
versions under services/ai_history/.
"
```

---

### Task 6: 创建 ToolCallResolvers capability 接口 + 各 CLI 实现

**Files:**
- Create: `client/lib/services/cli/registry/capabilities/tool_call_resolver_capability.dart`
- Create: `client/lib/services/cli/registry/capabilities/claude_tool_call_resolvers.dart`
- Create: `client/lib/services/cli/registry/capabilities/flashskyai_tool_call_resolvers.dart`
- Create: `client/lib/services/cli/registry/capabilities/codex_tool_call_resolvers.dart`
- Create: `client/lib/services/cli/registry/capabilities/opencode_tool_call_resolvers.dart`
- Create: `client/lib/services/cli/registry/capabilities/cursor_tool_call_resolvers.dart`

- [ ] **Step 1: 创建 `ToolCallResolvers` capability 接口**

```dart
// client/lib/services/cli/registry/capabilities/tool_call_resolver_capability.dart
import 'package:ai_message_core/ai_message_core.dart';
import '../../../../services/ai_history/tool_call_resolvers.dart' as resolvers;
import '../cli_capability.dart';

abstract class ToolCallResolversCapability implements CliCapability {
  AiEditToolTargetResolver get editResolver;
  AiToolFileTargetResolver get fileResolver;
  AiShellToolTargetResolver get shellResolver;
}
```

- [ ] **Step 2: 创建 Claude Code 的 ToolCallResolvers**

```dart
// client/lib/services/cli/registry/capabilities/claude_tool_call_resolvers.dart
import 'package:ai_message_core/ai_message_core.dart';
import '../../../../services/ai_history/edit_codecs/str_replace_edit_hunk_codec.dart';
import '../../../../services/ai_history/edit_codecs/write_edit_hunk_codec.dart';
import '../../../../services/ai_history/edit_codecs/unified_diff_edit_hunk_codec.dart';
import '../../../../services/ai_history/tool_call_resolvers.dart' as resolvers;
import 'tool_call_resolver_capability.dart';

final class ClaudeToolCallResolversCapability
    implements ToolCallResolversCapability {
  const ClaudeToolCallResolversCapability();

  @override
  late final editResolver = resolvers.ConfigurableAiEditToolTargetResolver(
    codecs: [
      const StrReplaceEditHunkCodec(
        toolNames: {'edit', 'strreplace'},
        pathKeys: ['file_path', 'path', 'file'],
        oldStringKeys: ['old_string', 'oldString'],
        newStringKeys: ['new_string', 'newString'],
        startLineKeys: ['start_line', 'startLine'],
      ),
      const WriteEditHunkCodec(
        toolNames: {'write', 'writefile', 'write_file'},
        pathKeys: ['file_path', 'path', 'file'],
        contentKeys: ['content', 'contents'],
      ),
      const UnifiedDiffEditHunkCodec(
        toolNames: {'applypatch', 'apply_patch'},
        pathKeys: ['file_path', 'path', 'file'],
        patchKeys: ['patch', 'diff', 'input'],
      ),
    ],
  );

  @override
  late final fileResolver = resolvers.ConfigurableAiToolFileTargetResolver(
    rules: [
      const resolvers.AiToolFileTargetRule(
        toolNames: {'read', 'readfile', 'read_file'},
        useOffsetLimit: true,
      ),
      const resolvers.AiToolFileTargetRule(
        toolNames: {
          'write',
          'writefile',
          'write_file',
          'create',
          'create_file',
        },
      ),
      const resolvers.AiToolFileTargetRule(
        toolNames: {
          'edit',
          'strreplace',
          'applypatch',
          'apply_patch',
        },
      ),
    ],
  );

  @override
  late final shellResolver = resolvers.ConfigurableAiShellToolTargetResolver(
    toolNames: {'bash', 'shell'},
    commandKeys: ['command', 'cmd'],
  );
}
```

- [ ] **Step 3: 创建 Flashskyai 的 ToolCallResolvers（与 Claude 相同）**

```dart
// client/lib/services/cli/registry/capabilities/flashskyai_tool_call_resolvers.dart
// flashskyai 使用与 Claude 相同的 tool name 和 key 约定
import 'claude_tool_call_resolvers.dart';
import 'tool_call_resolver_capability.dart';

final class FlashskyaiToolCallResolversCapability
    extends ClaudeToolCallResolversCapability {
  const FlashskyaiToolCallResolversCapability();
}
```

- [ ] **Step 4: 创建 Codex 的 ToolCallResolvers**

```dart
// client/lib/services/cli/registry/capabilities/codex_tool_call_resolvers.dart
import 'package:ai_message_core/ai_message_core.dart';
import '../../../../services/ai_history/edit_codecs/str_replace_edit_hunk_codec.dart';
import '../../../../services/ai_history/edit_codecs/write_edit_hunk_codec.dart';
import '../../../../services/ai_history/edit_codecs/unified_diff_edit_hunk_codec.dart';
import '../../../../services/ai_history/tool_call_resolvers.dart' as resolvers;
import 'tool_call_resolver_capability.dart';

final class CodexToolCallResolversCapability
    implements ToolCallResolversCapability {
  const CodexToolCallResolversCapability();

  @override
  late final editResolver = resolvers.ConfigurableAiEditToolTargetResolver(
    codecs: [
      const StrReplaceEditHunkCodec(
        toolNames: {'strreplace', 'edit'},
        pathKeys: ['file_path', 'path', 'file'],
        oldStringKeys: ['old_string', 'oldString'],
        newStringKeys: ['new_string', 'newString'],
        startLineKeys: ['start_line', 'startLine'],
      ),
      const WriteEditHunkCodec(
        toolNames: {'write', 'writefile', 'write_file'},
        pathKeys: ['file_path', 'path', 'file'],
        contentKeys: ['content', 'contents'],
      ),
      const UnifiedDiffEditHunkCodec(
        toolNames: {'applypatch', 'apply_patch'},
        pathKeys: ['file_path', 'path', 'file'],
        patchKeys: ['patch', 'diff', 'input'],
      ),
    ],
  );

  @override
  late final fileResolver = resolvers.ConfigurableAiToolFileTargetResolver(
    rules: [
      const resolvers.AiToolFileTargetRule(
        toolNames: {'read', 'readfile', 'read_file'},
        useOffsetLimit: true,
      ),
      const resolvers.AiToolFileTargetRule(
        toolNames: {
          'write',
          'writefile',
          'write_file',
          'create',
          'create_file',
        },
      ),
      const resolvers.AiToolFileTargetRule(
        toolNames: {
          'edit',
          'strreplace',
          'applypatch',
          'apply_patch',
        },
      ),
    ],
  );

  @override
  late final shellResolver = resolvers.ConfigurableAiShellToolTargetResolver(
    toolNames: {'bash', 'shell', 'exec_command', 'run_terminal_cmd'},
    commandKeys: ['command', 'cmd'],
  );
}
```

- [ ] **Step 5: 创建 Opencode 和 Cursor 的 ToolCallResolvers**

```dart
// client/lib/services/cli/registry/capabilities/opencode_tool_call_resolvers.dart
import '../../../../services/ai_history/edit_codecs/str_replace_edit_hunk_codec.dart';
import '../../../../services/ai_history/edit_codecs/write_edit_hunk_codec.dart';
import '../../../../services/ai_history/edit_codecs/unified_diff_edit_hunk_codec.dart';
import '../../../../services/ai_history/tool_call_resolvers.dart' as resolvers;
import 'tool_call_resolver_capability.dart';

final class OpencodeToolCallResolversCapability
    implements ToolCallResolversCapability {
  const OpencodeToolCallResolversCapability();

  @override
  late final editResolver = resolvers.ConfigurableAiEditToolTargetResolver(
    codecs: [
      const StrReplaceEditHunkCodec(
        toolNames: {'edit', 'strreplace'},
        pathKeys: ['file_path', 'path', 'file'],
        oldStringKeys: ['old_string', 'oldString'],
        newStringKeys: ['new_string', 'newString'],
        startLineKeys: ['start_line', 'startLine'],
      ),
      const WriteEditHunkCodec(
        toolNames: {'write', 'writefile', 'write_file'},
        pathKeys: ['file_path', 'path', 'file'],
      ),
      const UnifiedDiffEditHunkCodec(
        toolNames: {'applypatch', 'apply_patch'},
        pathKeys: ['file_path', 'path', 'file'],
      ),
    ],
  );

  @override
  late final fileResolver = resolvers.ConfigurableAiToolFileTargetResolver(
    rules: [
      const resolvers.AiToolFileTargetRule(
        toolNames: {'read', 'readfile', 'read_file'},
        useOffsetLimit: true,
      ),
      const resolvers.AiToolFileTargetRule(
        toolNames: {
          'write',
          'writefile',
          'write_file',
        },
      ),
      const resolvers.AiToolFileTargetRule(
        toolNames: {'edit', 'strreplace', 'applypatch', 'apply_patch'},
      ),
    ],
  );

  @override
  late final shellResolver = resolvers.ConfigurableAiShellToolTargetResolver(
    toolNames: {'bash', 'shell'},
    commandKeys: ['command', 'cmd'],
  );
}
```

```dart
// client/lib/services/cli/registry/capabilities/cursor_tool_call_resolvers.dart
import '../../../../services/ai_history/edit_codecs/str_replace_edit_hunk_codec.dart';
import '../../../../services/ai_history/edit_codecs/write_edit_hunk_codec.dart';
import '../../../../services/ai_history/edit_codecs/unified_diff_edit_hunk_codec.dart';
import '../../../../services/ai_history/tool_call_resolvers.dart' as resolvers;
import 'tool_call_resolver_capability.dart';

final class CursorToolCallResolversCapability
    implements ToolCallResolversCapability {
  const CursorToolCallResolversCapability();

  @override
  late final editResolver = resolvers.ConfigurableAiEditToolTargetResolver(
    codecs: [
      const StrReplaceEditHunkCodec(
        toolNames: {'edit', 'strreplace'},
        pathKeys: ['file_path', 'path', 'file'],
        oldStringKeys: ['old_string', 'oldString'],
        newStringKeys: ['new_string', 'newString'],
        startLineKeys: ['start_line', 'startLine'],
      ),
      const WriteEditHunkCodec(
        toolNames: {'write', 'writefile', 'write_file'},
        pathKeys: ['file_path', 'path', 'file'],
      ),
      const UnifiedDiffEditHunkCodec(
        toolNames: {'applypatch', 'apply_patch'},
        pathKeys: ['file_path', 'path', 'file'],
      ),
    ],
  );

  @override
  late final fileResolver = resolvers.ConfigurableAiToolFileTargetResolver(
    rules: [
      const resolvers.AiToolFileTargetRule(
        toolNames: {'read', 'readfile', 'read_file'},
        useOffsetLimit: true,
      ),
      const resolvers.AiToolFileTargetRule(
        toolNames: {
          'write',
          'writefile',
          'write_file',
        },
      ),
      const resolvers.AiToolFileTargetRule(
        toolNames: {'edit', 'strreplace', 'applypatch', 'apply_patch'},
      ),
    ],
  );

  @override
  late final shellResolver = resolvers.ConfigurableAiShellToolTargetResolver(
    toolNames: {'bash', 'shell', 'execute'},
    commandKeys: ['command', 'cmd', 'CommandLine'],
  );
}
```

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/tool_call_resolver_capability.dart \
        client/lib/services/cli/registry/capabilities/claude_tool_call_resolvers.dart \
        client/lib/services/cli/registry/capabilities/flashskyai_tool_call_resolvers.dart \
        client/lib/services/cli/registry/capabilities/codex_tool_call_resolvers.dart \
        client/lib/services/cli/registry/capabilities/opencode_tool_call_resolvers.dart \
        client/lib/services/cli/registry/capabilities/cursor_tool_call_resolvers.dart
git commit -m "feat: add ToolCallResolvers capability + per-CLI implementations

Each CLI now provides its own tool name -> arg key mapping via
ToolCallResolversCapability, isolating CLI-specific naming conventions
within the registry.
"
```

---

### Task 7: 在 CliToolRegistry 中添加查询方法，各 CLI 定义注册 capability

**Files:**
- Modify: `client/lib/services/cli/registry/cli_tool_registry.dart`
- Modify: `client/lib/services/cli/claude/claude_tool.dart`
- Modify: `client/lib/services/cli/flashskyai/flashskyai_tool.dart`
- Modify: `client/lib/services/cli/codex/codex_tool.dart`
- Modify: `client/lib/services/cli/opencode/opencode_tool.dart`
- Modify: `client/lib/services/cli/cursor/cursor_tool.dart`

- [ ] **Step 1: 在 `CliToolRegistry` 添加 `toolCallResolvers` 方法**

在 `cli_tool_registry.dart` 中添加 import 和方法：

```dart
// 在 imports 区域添加:
import 'capabilities/tool_call_resolver_capability.dart';

// 在 CliToolRegistry 类中添加方法（在 lifecycleFor 方法之后）:
ToolCallResolversCapability? toolCallResolvers(CliTool cli) =>
    capability<ToolCallResolversCapability>(cli);
```

- [ ] **Step 2: 在 Claude CLI 定义中注册**

在 `claude_tool.dart` 中添加 import：

```dart
import '../registry/capabilities/claude_tool_call_resolvers.dart';
```

在 `ClaudeCliTool` 类中添加字段：

```dart
final toolCallResolvers = const ClaudeToolCallResolversCapability();
```

在 `capabilities` getter 中添加：

```dart
toolCallResolvers,
```

- [ ] **Step 3: 在其他 4 个 CLI 定义中同样注册**

对 `flashskyai_tool.dart`：
```dart
import '../registry/capabilities/flashskyai_tool_call_resolvers.dart';
// ...
final toolCallResolvers = const FlashskyaiToolCallResolversCapability();
// 在 capabilities getter 中添加 toolCallResolvers,
```

对 `codex_tool.dart`：
```dart
import '../registry/capabilities/codex_tool_call_resolvers.dart';
// ...
final toolCallResolvers = const CodexToolCallResolversCapability();
// 在 capabilities getter 中添加 toolCallResolvers,
```

对 `opencode_tool.dart`：
```dart
import '../registry/capabilities/opencode_tool_call_resolvers.dart';
// ...
final toolCallResolvers = const OpencodeToolCallResolversCapability();
// 在 capabilities getter 中添加 toolCallResolvers,
```

对 `cursor_tool.dart`：
```dart
import '../registry/capabilities/cursor_tool_call_resolvers.dart';
// ...
final toolCallResolvers = const CursorToolCallResolversCapability();
// 在 capabilities getter 中添加 toolCallResolvers,
```

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/cli/registry/cli_tool_registry.dart \
        client/lib/services/cli/claude/claude_tool.dart \
        client/lib/services/cli/flashskyai/flashskyai_tool.dart \
        client/lib/services/cli/codex/codex_tool.dart \
        client/lib/services/cli/opencode/opencode_tool.dart \
        client/lib/services/cli/cursor/cursor_tool.dart
git commit -m "feat: register ToolCallResolversCapability on all CLI definitions"
```

---

### Task 8: 扩展 AiToolFileActions 携带三个 resolver

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/tool_file_actions.dart`

- [ ] **Step 1: 修改 `AiToolFileActions`**

把 `resolver` 重命名为 `fileResolver`，新增 `editResolver` 和 `shellResolver`，去掉默认值。

```dart
// client/packages/ai_message_ui/lib/src/tool_file_actions.dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';

import 'edit/edit_line_highlighter.dart';

/// Host-injected resolver + open handler for tool-call file targets.
@immutable
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

  static AiToolFileActions of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_AiToolFileActionsScope>()
            ?.actions ??
        _fallback;
  }

  static const _fallback = AiToolFileActions(
    fileResolver: _NoopFileResolver._(),
    editResolver: _NoopEditResolver._(),
    shellResolver: _NoopShellResolver._(),
  );
}

class _NoopFileResolver implements AiToolFileTargetResolver {
  const _NoopFileResolver._();
  @override
  AiToolFileTarget? resolve(AiToolCallPart part) => null;
}

class _NoopEditResolver implements AiEditToolTargetResolver {
  const _NoopEditResolver._();
  @override
  AiEditToolTarget? resolve(AiToolCallPart part) => null;
}

class _NoopShellResolver implements AiShellToolTargetResolver {
  const _NoopShellResolver._();
  @override
  AiShellToolTarget? resolve(AiToolCallPart part) => null;
}

// _AiToolFileActionsScope, AiToolFileActionsScope 保持不变 ...
```

注意：`_AiToolFileActionsScope` 和 `AiToolFileActionsScope` 的代码保持不变，这里省略。

- [ ] **Step 2: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/tool_file_actions.dart
git commit -m "refactor: extend AiToolFileActions with edit/shell resolvers

Replace single 'resolver' field with fileResolver, editResolver, and
shellResolver. Remove default values that depended on ai_message_core
Default* implementations.
"
```

---

### Task 9: 更新 tool_call_part_view.dart 使用注入的 resolver

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart`

- [ ] **Step 1: 修改 tool_call_part_view.dart**

将 `const DefaultAiShellToolTargetResolver()` 和 `const DefaultAiEditToolTargetResolver()` 替换为从 `fileActions` 获取。

```dart
// 删除这两行:
// const shellResolver = DefaultAiShellToolTargetResolver();
// const editResolver = DefaultAiEditToolTargetResolver();

// 替换为:
final shellTarget = useSubagentChrome ? null : fileActions.shellResolver.resolve(part);
final editTarget = useSubagentChrome || shellTarget != null
    ? null
    : fileActions.editResolver.resolve(part);
final target = useSubagentChrome || shellTarget != null || editTarget != null
    ? null
    : fileActions.fileResolver.resolve(part);
```

同时删除顶部不再需要的 import（如果有对 `DefaultAiShellToolTargetResolver` 或 `DefaultAiEditToolTargetResolver` 的直接引用）。

- [ ] **Step 2: Commit**

```bash
git add client/packages/ai_message_ui/lib/src/parts/tool_call_part_view.dart
git commit -m "refactor: use injected resolvers in tool_call_part_view

Replace direct instantiation of DefaultAiShellToolTargetResolver and
DefaultAiEditToolTargetResolver with resolvers from AiToolFileActions.
"
```

---

### Task 10: 更新 session_chat_message_area.dart 注入 resolver

**Files:**
- Modify: `client/lib/pages/chat/session_chat_message_area.dart`

- [ ] **Step 1: 修改 `AiToolFileActionsScope` 创建**

从 `CliToolRegistry` 获取当前 session CLI 的 `ToolCallResolvers`，传入 `AiToolFileActions`。

```dart
// 在 build() 方法中，找到 AiToolFileActionsScope 创建处
// 添加获取 registry 和 resolvers 的代码:

final registry = CliToolRegistryScope.of(context);
final toolResolvers = registry.toolCallResolvers(session.cli ?? CliTool.claude);
// 如果 registry 没有返回 resolvers，使用 noop fallback（不应该发生）

// 修改 AiToolFileActions 构造:
actions: AiToolFileActions(
  fileResolver: toolResolvers?.fileResolver ?? const _NoopFileResolver._(),
  editResolver: toolResolvers?.editResolver ?? const _NoopEditResolver._(),
  shellResolver: toolResolvers?.shellResolver ?? const _NoopShellResolver._(),
  onOpenFile: (target) async { /* 不变 */ },
  lineHighlighter: WorkspaceAiEditLineHighlighter(/* 不变 */),
),
```

注意：需要在 `session_chat_message_area.dart` 中添加如下 import：
```dart
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
```

由于不再需要 `Default*` resolver 的 import，无需修改 import 区域（当前也没有直接 import 它们，是通过 `ai_message_core` 包引入的）。

- [ ] **Step 2: Commit**

```bash
git add client/lib/pages/chat/session_chat_message_area.dart
git commit -m "feat: inject ToolCallResolvers from registry into session chat

SessionChatMessageArea now resolves the session's CLI tool call resolvers
from CliToolRegistry and injects them via AiToolFileActionsScope.
"
```

---

### Task 11: 更新 CursorTerminalToolResultEnricher + CursorAiHistoryCapability

**Files:**
- Modify: `client/lib/services/cli/cursor/capabilities/history/terminal_tool_result_enricher.dart`
- Modify: `client/lib/services/cli/registry/capabilities/history/builtin_ai_history_capabilities.dart`
- Modify: `client/lib/services/cli/cursor/cursor_tool.dart`

- [ ] **Step 1: 移除 `CursorTerminalToolResultEnricher` 的 Default 默认值**

```dart
// terminal_tool_result_enricher.dart — 只改构造函数签名
final class CursorTerminalToolResultEnricher implements ToolResultEnricher {
  const CursorTerminalToolResultEnricher({
    required this.shellResolver,  // 原来是 = const DefaultAiShellToolTargetResolver()
  });
  // rest unchanged
}
```

- [ ] **Step 2: 将 `shellResolver` 参数传播到 `CursorAiHistoryCapability`**

```dart
// builtin_ai_history_capabilities.dart
final class CursorAiHistoryCapability implements AiHistoryCapability {
  const CursorAiHistoryCapability({
    this.subagentSideResolver = const CursorSideResolver(),
    this.toolResultEnricher = const CursorTerminalToolResultEnricher(
      shellResolver: /* 必须提供，去掉默认值 */,
    ),
  });
```

由于 `shellResolver` 现在必传，`toolResultEnricher` 也不能再用默认值。
改为在 `CursorAiHistoryCapability` 上接收 `shellResolver`：

```dart
final class CursorAiHistoryCapability implements AiHistoryCapability {
  const CursorAiHistoryCapability({
    required this.shellResolver,
    this.subagentSideResolver = const CursorSideResolver(),
  }) : toolResultEnricher = CursorTerminalToolResultEnricher(
         shellResolver: shellResolver,
       );

  final AiShellToolTargetResolver shellResolver;

  @override
  final SubagentSideResolver subagentSideResolver;

  @override
  late final ToolResultEnricher toolResultEnricher;
  // rest unchanged
}
```

- [ ] **Step 3: 在 `cursor_tool.dart` 中传入 shellResolver**

```dart
// cursor_tool.dart — 在 CursorCliTool 中添加 toolCallResolvers 字段后:
this.aiHistory = const CursorAiHistoryCapability(
  shellResolver: toolCallResolvers.shellResolver,
  // toolCallResolvers 通过构造函数传入或初始化列表访问
),
```

- [ ] **Step 4: Commit**

```bash
git add client/lib/services/cli/cursor/capabilities/history/terminal_tool_result_enricher.dart \
        client/lib/services/cli/registry/capabilities/history/builtin_ai_history_capabilities.dart \
        client/lib/services/cli/cursor/cursor_tool.dart
git commit -m "refactor: require shellResolver injection in CursorTerminalToolResultEnricher

Propagate ToolCallResolvers.shellResolver through CursorAiHistoryCapability
to CursorTerminalToolResultEnricher, removing the dependency on
DefaultAiShellToolTargetResolver default constructor.
"
```

---

### Task 12: 清理 ai_message_core 包

**Files:**
- Delete: `client/packages/ai_message_core/lib/src/tool_edit_args.dart`
- Delete: `client/packages/ai_message_core/lib/src/codecs/str_replace_edit_hunk_codec.dart`
- Delete: `client/packages/ai_message_core/lib/src/codecs/write_edit_hunk_codec.dart`
- Delete: `client/packages/ai_message_core/lib/src/codecs/unified_diff_edit_hunk_codec.dart`
- Modify: `client/packages/ai_message_core/lib/src/tool_edit_target_resolver.dart` — 去掉 Default* 实现
- Modify: `client/packages/ai_message_core/lib/src/tool_file_target.dart` — 去掉 Default* 和 Rule 实现
- Modify: `client/packages/ai_message_core/lib/src/tool_shell_target.dart` — 去掉 Default* 实现
- Modify: `client/packages/ai_message_core/lib/ai_message_core.dart` — 更新 exports

- [ ] **Step 1: 删除 `tool_edit_args.dart`**

```bash
rm client/packages/ai_message_core/lib/src/tool_edit_args.dart
```

- [ ] **Step 2: 删除三个 codec 文件**

```bash
rm client/packages/ai_message_core/lib/src/codecs/str_replace_edit_hunk_codec.dart
rm client/packages/ai_message_core/lib/src/codecs/write_edit_hunk_codec.dart
rm client/packages/ai_message_core/lib/src/codecs/unified_diff_edit_hunk_codec.dart
```

- [ ] **Step 3: 精简 `tool_edit_target_resolver.dart`**

只保留接口：

```dart
// client/packages/ai_message_core/lib/src/tool_edit_target_resolver.dart
import 'message.dart';
import 'tool_edit_hunk.dart';

abstract class AiEditToolTargetResolver {
  AiEditToolTarget? resolve(AiToolCallPart part);
}
```

- [ ] **Step 4: 精简 `tool_file_target.dart`**

移除 `AiToolFileTargetRule`、`DefaultAiToolFileTargetResolver`、`CompositeAiToolFileTargetResolver`、私有函数。
只保留 `AiToolFileTarget` 数据类型和 `AiToolFileTargetResolver` 接口：

```dart
// client/packages/ai_message_core/lib/src/tool_file_target.dart（精简后）
import 'message.dart';

class AiToolFileTarget {
  const AiToolFileTarget({
    required this.path,
    this.startLine,
    this.endLine,
  });

  final String path;
  final int? startLine;
  final int? endLine;
}

abstract class AiToolFileTargetResolver {
  AiToolFileTarget? resolve(AiToolCallPart part);
}
```

- [ ] **Step 5: 精简 `tool_shell_target.dart`**

移除 `DefaultAiShellToolTargetResolver` 和私有函数。只保留 `AiShellToolTarget` 数据类型和 `AiShellToolTargetResolver` 接口：

```dart
// client/packages/ai_message_core/lib/src/tool_shell_target.dart（精简后）
class AiShellToolTarget {
  const AiShellToolTarget({
    required this.command,
    this.description,
  });

  final String command;
  final String? description;

  static const summaryMaxChars = 80;

  String get summary {
    final d = description?.trim();
    if (d != null && d.isNotEmpty) return d;
    return truncateCommand(command);
  }

  static String truncateCommand(String command) {
    final oneLine = command.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= summaryMaxChars) return oneLine;
    return '${oneLine.substring(0, summaryMaxChars)}…';
  }
}

abstract class AiShellToolTargetResolver {
  AiShellToolTarget? resolve(AiToolCallPart part);
}
```

- [ ] **Step 6: 更新 `ai_message_core.dart` exports**

```dart
// client/packages/ai_message_core/lib/ai_message_core.dart
library ai_message_core;

export 'src/message.dart';
export 'src/subagent_attachment.dart';
export 'src/tool_edit_hunk.dart';
export 'src/tool_edit_hunk_codec.dart';
export 'src/tool_edit_target_resolver.dart';
export 'src/tool_file_target.dart';
export 'src/tool_shell_target.dart';
export 'src/message_content_identity.dart';
export 'src/message_export.dart';
export 'src/runtime.dart';
export 'src/thread_message_like.dart';
export 'src/transcript_adapter.dart';
```

删除 codecs 的 export。

删除整个 `codecs/` 目录和 `tool_edit_args.dart`。

- [ ] **Step 7: Commit**

```bash
git add client/packages/ai_message_core/
git commit -m "refactor: strip ai_message_core to pure interfaces + data types

Remove tool_edit_args.dart, codec implementations, Default* resolvers,
AiToolFileTargetRule, and all cross-CLI naming knowledge from
ai_message_core. The package now exports only interfaces and data types.
"
```

---

### Task 13: 移动和更新测试

**Files:**
- Delete: `client/packages/ai_message_core/test/str_replace_edit_hunk_codec_test.dart`
- Delete: `client/packages/ai_message_core/test/write_edit_hunk_codec_test.dart`
- Delete: `client/packages/ai_message_core/test/unified_diff_edit_hunk_codec_test.dart`
- Modify: `client/packages/ai_message_core/test/tool_edit_target_resolver_test.dart` — 删除或更新
- Modify: `client/packages/ai_message_core/test/tool_file_target_resolver_test.dart` — 更新为只测试类型
- Modify: `client/packages/ai_message_core/test/tool_shell_target_resolver_test.dart` — 更新为只测试类型
- Create: `client/test/services/ai_history/edit_codecs/tool_call_resolvers_test.dart`

- [ ] **Step 1: 删除旧的 codec 测试**

```bash
rm client/packages/ai_message_core/test/str_replace_edit_hunk_codec_test.dart
rm client/packages/ai_message_core/test/write_edit_hunk_codec_test.dart
rm client/packages/ai_message_core/test/unified_diff_edit_hunk_codec_test.dart
```

- [ ] **Step 2: 更新 `tool_edit_target_resolver_test.dart`**

该测试依赖 `DefaultAiEditToolTargetResolver`。改为测试新的 `ConfigurableAiEditToolTargetResolver`：

```dart
// 用 ConfigurableAiEditToolTargetResolver + 配置好的 codec 重写
```

或直接删除，因为逻辑已由新的 codec 测试 + `tool_call_resolvers_test.dart` 覆盖。

- [ ] **Step 3: 将 `tool_file_target_resolver_test.dart` 改为测试 `ConfigurableAiToolFileTargetResolver`**

保持测试用例不变，只是将：
```dart
const resolver = DefaultAiToolFileTargetResolver();
```
替换为：
```dart
import 'package:teampilot/services/ai_history/tool_call_resolvers.dart' as resolvers;

final resolver = resolvers.ConfigurableAiToolFileTargetResolver(rules: [
  const resolvers.AiToolFileTargetRule(toolNames: {'read', 'readfile', 'read_file'}, useOffsetLimit: true),
  const resolvers.AiToolFileTargetRule(toolNames: {'write', 'writefile', 'write_file', 'create', 'create_file'}),
  const resolvers.AiToolFileTargetRule(toolNames: {'edit', 'strreplace', 'applypatch', 'apply_patch'}),
]);
```

同时删除 `CompositeAiToolFileTargetResolver` 相关的测试组，因为该类型已从 `ai_message_core` 移除。用户如需组合 resolver 可自行实现 interface。

- [ ] **Step 4: 将 `tool_shell_target_resolver_test.dart` 改为测试 `ConfigurableAiShellToolTargetResolver`**

```dart
import 'package:teampilot/services/ai_history/tool_call_resolvers.dart' as resolvers;

final resolver = resolvers.ConfigurableAiShellToolTargetResolver(
  toolNames: {'bash', 'shell', 'shell_command', 'exec_command', 'run_shell_command', 'run_terminal_cmd', 'execute'},
  commandKeys: ['command', 'cmd', 'CommandLine'],
);
```

- [ ] **Step 4: 添加 resolver 集成测试**

```dart
// client/test/services/ai_history/edit_codecs/tool_call_resolvers_test.dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:teampilot/services/ai_history/tool_call_resolvers.dart' as resolvers;
import 'package:teampilot/services/ai_history/edit_codecs/str_replace_edit_hunk_codec.dart';
import 'package:test/test.dart';

void main() {
  group('ConfigurableAiEditToolTargetResolver', () {
    test('chains codecs and returns first match', () {
      final resolver = resolvers.ConfigurableAiEditToolTargetResolver(
        codecs: [
          const StrReplaceEditHunkCodec(
            toolNames: {'edit'},
            pathKeys: ['file_path'],
            oldStringKeys: ['old_string'],
            newStringKeys: ['new_string'],
          ),
        ],
      );

      final target = resolver.resolve(AiToolCallPart(
        toolCallId: '1',
        toolName: 'edit',
        args: {
          'file_path': 'a.dart',
          'old_string': 'old',
          'new_string': 'new',
        },
      ));
      expect(target, isNotNull);
      expect(target!.hunk.path, 'a.dart');
    });

    test('returns null when no codec matches', () {
      final resolver = resolvers.ConfigurableAiEditToolTargetResolver(
        codecs: [
          const StrReplaceEditHunkCodec(
            toolNames: {'edit'},
            pathKeys: ['file_path'],
            oldStringKeys: ['old_string'],
            newStringKeys: ['new_string'],
          ),
        ],
      );

      expect(
        resolver.resolve(AiToolCallPart(
          toolCallId: '1',
          toolName: 'unknown_tool',
          args: {},
        )),
        isNull,
      );
    });
  });
}
```

- [ ] **Step 5: 删除旧的 codec 目录**

```bash
rmdir client/packages/ai_message_core/lib/src/codecs/
# 如果目录非空则手动清理残留文件
```

- [ ] **Step 6: Commit**

```bash
git add client/packages/ai_message_core/test/ client/test/
git commit -m "test: move codec tests to client/test/ and update for new architecture"
```

---

### Task 14: 运行全量分析 + 测试，修复问题

- [ ] **Step 1: 运行 flutter analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

修复所有编译错误。可能出现的问题：
- `ai_message_core` 导出符号缺失 — 补充 export
- 旧的 import 路径 — 更新为新的 import 目标
- `_Noop*Resolver` 符号未导出 — 从 `tool_file_actions.dart` 改为 private class 即可

- [ ] **Step 2: 运行 flutter test**

```bash
cd client && flutter test --exclude-tags integration
```

修复所有测试失败。

- [ ] **Step 3: 运行 ai_message_core 包的测试**

```bash
cd client/packages/ai_message_core && flutter test
```

- [ ] **Step 4: 运行 ai_message_ui 包的测试**

```bash
cd client/packages/ai_message_ui && flutter test 2>/dev/null || echo "No tests or test failures (check manually)"
```

- [ ] **Step 5: Commit 所有修复**

```bash
git add -A
git commit -m "fix: resolve analysis warnings and test failures after resolver refactor"
```

---

### 验证检查清单

- [ ] `ai_message_core` 的公开 API 只包含接口和数据类型，不包含任何 "Default" 类
- [ ] 所有 5 个 CLI 都注册了 `ToolCallResolversCapability`
- [ ] `tool_call_part_view.dart` 不再直接引用 `DefaultAiShellToolTargetResolver` 或 `DefaultAiEditToolTargetResolver`
- [ ] `AiToolFileActions` 不再有指向 `ai_message_core` Default 实现的默认值
- [ ] `CursorTerminalToolResultEnricher` 不再有 Default 默认值
- [ ] `flutter analyze` 无错误
- [ ] `flutter test` 全量通过
