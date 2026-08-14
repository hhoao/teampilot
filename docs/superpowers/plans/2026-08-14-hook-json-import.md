# Hook JSON 导入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 粘贴各 CLI（claude/flashskyai/codex/cursor）的 hook JSON 配置，经通用解析层（方言适配 + 事件映射 + 脚本提取 + 幂等 id）转为归一化 `HookDefinition`，预览后导入全局 hook 库。

**Architecture:** `HookImportParser` facade → `HookJsonDialect`（claude-family/codex 共享分组内核、cursor 扁平适配）→ `RawHookEntry` 中间形态 → 共享 `HookEventNameMapper`（数据驱动映射表）+ `HookScriptExtractor`（命令启发式识别脚本引用 → 内容进库 + 命令重写为库内路径；失败降级 raw）→ `HookImportDraft`（确定性 FNV-1a id 幂等）→ `HookImportService.import` 写入库。UI：列表页「导入」→ `HookImportDialog`（CLI 选择 + JSON 粘贴 → 预览勾选 → 导入）。

**Tech Stack:** Flutter/Dart、`client/lib/services/io/filesystem.dart`（`InMemoryFilesystem` 测试双）、TpDialog/TpSelect/TpTextArea（shared_ui）、l10n（app_en.arb / app_zh.arb）。

**Spec:** `docs/superpowers/specs/2026-08-14-hook-json-import-design.md`

## Global Constraints

- 验证命令：`cd client && flutter test test/<本任务测试> -v`；最终 `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`。
- 测试用 `client/test/support/in_memory_filesystem.dart` 的 `InMemoryFilesystem`。
- 只改 `client/lib/l10n/app_en.arb` / `app_zh.arb`，然后 `cd client && flutter gen-l10n`（生成文件按 repo 惯例提交）。
- 无 print（诊断用 `AppLogger`）；新共享 UI 原语进 shared_ui（本计划全部复用现有 `TpDialog`/`TpSelect`/`TpTextArea`）；页面壳在 `pages/`。
- 确定性 id 用 **FNV-1a 自实现**（不引入 `crypto` 依赖）：`import-<fnv1a('event|matcher|command|url') 十六进制前 12 位>`。
- `HookDefinition.native` 是**旁路**字段：writer/`HookEntry` 管线不消费，仅持久化保留。
- 不在归一化目录的事件（`PostCompact`/`SubagentStart`/`afterAgentResponse` 等）→ `hook_import_event_unsupported_<name>` warning 丢弃。
- 本仓库有并发开发进程——**每个任务完成后立即 commit**；若 `flutter pub get` 重写 `client/pubspec.lock`，`git checkout -- client/pubspec.lock` 恢复；提交前 `git status --short` 确认无无关文件。
- 基线：main 上存在少量 pre-existing 测试失败（codex adapter ×2、cli_config_section ×3 等，环境相关）——忽略，本功能测试必须全绿。

---

## 文件结构

**新建（lib）：**
- `client/lib/services/hook/import/hook_json_dialect.dart` — `RawHookEntry` + `HookJsonDialect` 接口 + JSON 解码小工具
- `client/lib/services/hook/import/hook_event_name_mapper.dart` — 三张数据驱动事件映射表
- `client/lib/services/hook/import/hook_grouped_json_parser.dart` — claude/codex 共享分组 JSON 内核
- `client/lib/services/hook/import/claude_family_hooks_json_dialect.dart` — claude/flashskyai 方言
- `client/lib/services/hook/import/codex_hooks_json_dialect.dart` — codex 方言（复用内核）
- `client/lib/services/hook/import/cursor_hooks_json_dialect.dart` — cursor 扁平方言
- `client/lib/services/hook/import/hook_script_extractor.dart` — 脚本引用识别 + 读取 + 降级
- `client/lib/services/hook/import/hook_import_parser.dart` — facade + `HookImportDraft`/`HookImportResult` + FNV-1a id
- `client/lib/services/hook/import/hook_import_service.dart` — 落库
- `client/lib/pages/hooks/hook_import_dialog.dart` — 导入对话框

**修改（lib）：**
- `client/lib/models/hook_definition.dart` — `native` 旁路字段
- `client/lib/app/app_shell.dart` — 构造 `HookImportParser`/`HookImportService`
- `client/lib/main.dart` — `RepositoryProvider` 提供两个实例（仿 `HookRepository` 注入）
- `client/lib/pages/hooks/hook_management_page.dart` — 「导入」按钮
- `client/lib/l10n/app_en.arb`、`app_zh.arb`

**测试（client/test/）：** `models/hook_definition_native_test.dart`、`services/hook/import/hook_json_dialect_test.dart`、`services/hook/import/hook_event_name_mapper_test.dart`、`services/hook/import/hook_grouped_json_parser_test.dart`、`services/hook/import/hook_script_extractor_test.dart`、`services/hook/import/cursor_hooks_json_dialect_test.dart`、`services/hook/import/hook_import_parser_test.dart`、`services/hook/import/hook_import_service_test.dart`、`pages/hooks/hook_import_dialog_test.dart`

---

### Task 1: HookDefinition.native 旁路字段

**Files:**
- Modify: `client/lib/models/hook_definition.dart`
- Test: `client/test/models/hook_definition_native_test.dart`

**Interfaces:**
- Consumes: 现有 `HookDefinition`（id/name/description/event/matcher/action/policy/timeoutSec/env）。
- Produces: `HookDefinition.native: Map<String, Object?>?`（构造参数、`fromJson`/`toJson`/`copyWith`/`==`/`hashCode` 同步；`toJson` 空 map 省略；`==`/`hashCode` 用 `mapEquals`/无序哈希——参照 env 的既有实现）。Task 7 的 parser 填充。

- [ ] **Step 1: Write the failing test**

`client/test/models/hook_definition_native_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';

void main() {
  test('native round-trips through json with equality', () {
    final definition = HookDefinition(
      id: 'h1',
      name: 'Guard',
      event: HookEvent.preToolUse,
      matcher: 'Bash',
      action: const CommandHookAction.raw('bash /x/guard.sh'),
      native: const {'if': 'Bash(rm *)', 'async': true, 'statusMessage': 'checking'},
    );
    final restored = HookDefinition.fromJson(definition.toJson());
    expect(restored, definition);
    expect(restored.native, {
      'if': 'Bash(rm *)',
      'async': true,
      'statusMessage': 'checking',
    });
  });

  test('native null or empty is omitted from json', () {
    const definition = HookDefinition(
      id: 'h2',
      name: 'a',
      event: HookEvent.stop,
      action: CommandHookAction.raw('echo done'),
    );
    expect(definition.toJson().containsKey('native'), isFalse);
    final withEmpty = HookDefinition(
      id: 'h2',
      name: 'a',
      event: HookEvent.stop,
      action: const CommandHookAction.raw('echo done'),
      native: const {},
    );
    expect(withEmpty.toJson().containsKey('native'), isFalse);
  });

  test('copyWith replaces native', () {
    final base = HookDefinition(
      id: 'h3',
      name: 'a',
      event: HookEvent.stop,
      action: const CommandHookAction.raw('echo done'),
      native: const {'async': true},
    );
    final next = base.copyWith(native: null);
    expect(next.native, isNull);
    expect(base.copyWith().native, {'async': true});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/models/hook_definition_native_test.dart -v`
Expected: FAIL — `native` 参数不存在。

- [ ] **Step 3: Write minimal implementation**

`client/lib/models/hook_definition.dart` 修改（在 `env` 字段之后加）：
```dart
  final Map<String, String> env;

  /// 导入时保留的原生 handler 字段（旁路，零丢失）。writer 管线不消费，
  /// 仅持久化；未来 writer 可按需读取。
  final Map<String, Object?>? native;
```
构造参数加 `this.native`；`fromJson` 加 `native: _decodeNative(json['native'])`；`toJson` 加 `if (native != null && native!.isNotEmpty) 'native': native,`；`copyWith` 加 `Map<String, Object?>? native`（注意：`native: native ?? this.native` 无法置 null——用 `Object? native = _unset` 哨兵或接受 `copyWith(native: null)` 不变更。**采用哨兵**：private static const `_unset = Object();`，参数 `Object? native = _unset`，body `native: identical(native, _unset) ? this.native : native as Map<String, Object?>?`——测试 3 要求 `copyWith(native: null)` 置 null，必须支持）；`==` 加 `mapEquals(native ?? const {}, other.native ?? const {})`；`hashCode` 加 `Object.hashAllUnordered(native?.keys ?? const []), Object.hashAllUnordered(native?.values ?? const [])`。

辅助：
```dart
  static Map<String, Object?>? _decodeNative(Object? raw) {
    if (raw is! Map || raw.isEmpty) return null;
    return Map<String, Object?>.from(raw.cast<String, Object?>());
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/models/hook_definition_native_test.dart test/models/hook_definition_test.dart -v`
Expected: PASS（旧 round-trip 测试不回归）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/hook_definition.dart client/test/models/hook_definition_native_test.dart
git commit -m "feat(hooks-import): HookDefinition.native passthrough field (zero-loss import)"
```

---

### Task 2: RawHookEntry + HookJsonDialect 接口 + JSON 工具

**Files:**
- Create: `client/lib/services/hook/import/hook_json_dialect.dart`
- Test: `client/test/services/hook/import/hook_json_dialect_test.dart`

**Interfaces:**
- Consumes: `CliTool`（`models/team_config.dart`）。
- Produces: `class RawHookEntry{nativeEvent, matcher, type, command?, url?, headers, timeoutSec?, native, unsupportedFields, warnings}`（值语义）；`abstract interface class HookJsonDialect{ CliTool get cli; List<RawHookEntry> parseJson(String jsonText, List<String> warnings); }`；共享工具 `hookJsonString(Map, key)` / `hookJsonInt` / `hookJsonStringMap` / `isPathLike(String)` / `stripQuotes(String)` / `looksLikeGroups(Map)`。Task 3-7 使用。

- [ ] **Step 1: Write the failing test**

`client/test/services/hook/import/hook_json_dialect_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/hook/import/hook_json_dialect.dart';

void main() {
  test('RawHookEntry value equality', () {
    const a = RawHookEntry(
      nativeEvent: 'PreToolUse',
      matcher: 'Bash',
      type: 'command',
      command: 'echo hi',
      timeoutSec: 5,
      native: {'async': true},
      unsupportedFields: ['async'],
    );
    const b = RawHookEntry(
      nativeEvent: 'PreToolUse',
      matcher: 'Bash',
      type: 'command',
      command: 'echo hi',
      timeoutSec: 5,
      native: {'async': true},
      unsupportedFields: ['async'],
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('json helpers parse strings, ints, maps', () {
    const map = <String, Object?>{
      'a': 'x',
      't': 5.0,
      'headers': {'X-M': 'm1'},
      'n': null,
    };
    expect(hookJsonString(map, 'a'), 'x');
    expect(hookJsonString(map, 'n'), null);
    expect(hookJsonInt(map, 't'), 5);
    expect(hookJsonInt(map, 'n'), null);
    expect(hookJsonStringMap(map, 'headers'), {'X-M': 'm1'});
    expect(hookJsonStringMap(map, 'n'), const {});
  });

  test('path and quote helpers', () {
    expect(isPathLike('/abs/x.sh'), isTrue);
    expect(isPathLike('~/x.sh'), isTrue);
    expect(isPathLike('./x.sh'), isTrue);
    expect(isPathLike('scripts/x.py'), isTrue);
    expect(isPathLike('echo'), isFalse);
    expect(isPathLike('-f'), isFalse);
    expect(stripQuotes('"/a b/x.sh"'), '/a b/x.sh');
    expect(stripQuotes("'/a/x.sh'"), '/a/x.sh');
    expect(stripQuotes('/a/x.sh'), '/a/x.sh');
  });

  test('looksLikeGroups accepts a hooks-map-shaped root', () {
    expect(
      looksLikeGroups(<String, Object?>{
        'PreToolUse': [
          {'matcher': 'Bash'},
        ],
      }),
      isTrue,
    );
    expect(
      looksLikeGroups(<String, Object?>{'version': 1, 'hooks': {}}),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/hook/import/hook_json_dialect_test.dart -v`
Expected: FAIL — 文件不存在。

- [ ] **Step 3: Write minimal implementation**

`client/lib/services/hook/import/hook_json_dialect.dart`:
```dart
import 'package:flutter/foundation.dart';

import '../../../models/team_config.dart';

/// 方言解析产出的中间形态（保持 JSON 内顺序）。
@immutable
class RawHookEntry {
  const RawHookEntry({
    required this.nativeEvent,
    this.matcher,
    required this.type,
    this.command,
    this.url,
    this.headers = const {},
    this.timeoutSec,
    this.native = const {},
    this.unsupportedFields = const [],
    this.warnings = const [],
  });

  /// 原生事件名（claude/codex PascalCase 或 cursor 小写）。
  final String nativeEvent;
  final String? matcher;

  /// handler 类型：'command' | 'http'（其余已在方言层丢弃并 warning）。
  final String type;
  final String? command;
  final String? url;
  final Map<String, String> headers;
  final int? timeoutSec;

  /// 旁路：原生 handler 完整字段（零丢失）。
  final Map<String, Object?> native;

  /// 导入后不生效的字段名（预览标注）。
  final List<String> unsupportedFields;
  final List<String> warnings;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RawHookEntry &&
          nativeEvent == other.nativeEvent &&
          matcher == other.matcher &&
          type == other.type &&
          command == other.command &&
          url == other.url &&
          mapEquals(headers, other.headers) &&
          timeoutSec == other.timeoutSec &&
          mapEquals(native, other.native) &&
          listEquals(unsupportedFields, other.unsupportedFields) &&
          listEquals(warnings, other.warnings);

  @override
  int get hashCode => Object.hash(
    nativeEvent,
    matcher,
    type,
    command,
    url,
    Object.hashAllUnordered(headers.keys),
    Object.hashAllUnordered(headers.values),
    timeoutSec,
    Object.hashAllUnordered(native.keys),
    Object.hashAllUnordered(native.values),
    Object.hashAllUnordered(unsupportedFields),
    Object.hashAllUnordered(warnings),
  );
}

/// 每 CLI 一个实现：把该 CLI 的 hook JSON 解析为 [RawHookEntry] 列表。
/// 方言层只做结构解析（事件名/分组/handler 字段），不做归一化（事件映射、
/// 脚本提取在共享层）。
abstract interface class HookJsonDialect {
  CliTool get cli;
  List<RawHookEntry> parseJson(String jsonText, List<String> warnings);
}

String? hookJsonString(Map<String, Object?> map, String key) {
  final value = map[key];
  return value is String && value.isNotEmpty ? value : null;
}

int? hookJsonInt(Map<String, Object?> map, String key) {
  final value = map[key];
  return value is num ? value.toInt() : null;
}

Map<String, String> hookJsonStringMap(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! Map) return const {};
  final out = <String, String>{};
  for (final entry in value.entries) {
    final v = entry.value;
    if (v is String) out[entry.key.toString()] = v;
  }
  return out;
}

/// 路径形态 token：以 `/`、`~/`、`./`、`../` 开头，或含 `/` 且非 `-` 开头
/// （相对路径如 `scripts/x.py`）。
bool isPathLike(String token) {
  if (token.startsWith('-')) return false;
  return token.startsWith('/') ||
      token.startsWith('~/') ||
      token.startsWith('./') ||
      token.startsWith('../') ||
      token.contains('/');
}

String stripQuotes(String token) {
  if (token.length >= 2 &&
      ((token.startsWith('"') && token.endsWith('"')) ||
          (token.startsWith("'") && token.endsWith("'")))) {
    return token.substring(1, token.length - 1);
  }
  return token;
}

/// 根对象是否本身就是 hooks map（`{<Event>: [groups...]}`）。
bool looksLikeGroups(Map<String, Object?> root) {
  if (root.isEmpty) return false;
  return root.values.every((v) => v is List);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/hook/import/hook_json_dialect_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/hook/import/hook_json_dialect.dart \
  client/test/services/hook/import/hook_json_dialect_test.dart
git commit -m "feat(hooks-import): RawHookEntry + HookJsonDialect interface + json helpers"
```

---

### Task 3: HookEventNameMapper（数据驱动事件映射表）

**Files:**
- Create: `client/lib/services/hook/import/hook_event_name_mapper.dart`
- Test: `client/test/services/hook/import/hook_event_name_mapper_test.dart`

**Interfaces:**
- Consumes: `HookEvent`、`CliTool`。
- Produces: `abstract final class HookEventNameMapper{ static const Map<CliTool, Map<String, HookEvent>> tables; static HookEvent? map(CliTool cli, String nativeEvent); }`。Task 7 parser 使用；表是数据——未来归一化目录扩展只需加表项。

- [ ] **Step 1: Write the failing test**

`client/test/services/hook/import/hook_event_name_mapper_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/hook/import/hook_event_name_mapper.dart';

void main() {
  test('claude maps PascalCase names', () {
    expect(HookEventNameMapper.map(CliTool.claude, 'PreToolUse'),
        HookEvent.preToolUse);
    expect(HookEventNameMapper.map(CliTool.claude, 'StopFailure'),
        HookEvent.stopFailure);
    expect(HookEventNameMapper.map(CliTool.claude, 'Notification'),
        HookEvent.notification);
    expect(HookEventNameMapper.map(CliTool.claude, 'PostCompact'), isNull);
  });

  test('codex maps its subset (no PostToolUseFailure/StopFailure/Notification)',
      () {
    expect(HookEventNameMapper.map(CliTool.codex, 'PreToolUse'),
        HookEvent.preToolUse);
    expect(HookEventNameMapper.map(CliTool.codex, 'PostToolUseFailure'),
        isNull);
    expect(HookEventNameMapper.map(CliTool.codex, 'PostCompact'), isNull);
  });

  test('cursor maps lowercase names incl beforeShellExecution approximation', () {
    expect(HookEventNameMapper.map(CliTool.cursor, 'beforeSubmitPrompt'),
        HookEvent.userPromptSubmit);
    expect(HookEventNameMapper.map(CliTool.cursor, 'preToolUse'),
        HookEvent.preToolUse);
    expect(HookEventNameMapper.map(CliTool.cursor, 'beforeShellExecution'),
        HookEvent.shellCommandRequest);
    expect(HookEventNameMapper.map(CliTool.cursor, 'afterAgentResponse'),
        isNull);
  });

  test('flashskyai shares claude table; opencode unsupported', () {
    expect(HookEventNameMapper.map(CliTool.flashskyai, 'Stop'),
        HookEvent.stop);
    expect(HookEventNameMapper.map(CliTool.opencode, 'PreToolUse'), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/hook/import/hook_event_name_mapper_test.dart -v`
Expected: FAIL — 文件不存在。

- [ ] **Step 3: Write minimal implementation**

`client/lib/services/hook/import/hook_event_name_mapper.dart`:
```dart
import '../../../models/hook_event.dart';
import '../../../models/team_config.dart';

/// 原生事件名 → 归一化 [HookEvent] 的映射表（数据驱动；不在目录的原生事件
/// 返回 null，由调用方 warning 丢弃）。归一化目录扩展时只加表项。
abstract final class HookEventNameMapper {
  HookEventNameMapper._();

  static const Map<CliTool, Map<String, HookEvent>> tables = {
    CliTool.claude: {
      'SessionStart': HookEvent.sessionStart,
      'SessionEnd': HookEvent.sessionEnd,
      'UserPromptSubmit': HookEvent.userPromptSubmit,
      'PreToolUse': HookEvent.preToolUse,
      'PostToolUse': HookEvent.postToolUse,
      'PostToolUseFailure': HookEvent.postToolUseFailure,
      'PermissionRequest': HookEvent.permissionRequest,
      'Stop': HookEvent.stop,
      'StopFailure': HookEvent.stopFailure,
      'SubagentStop': HookEvent.subagentStop,
      'PreCompact': HookEvent.preCompact,
      'Notification': HookEvent.notification,
    },
    CliTool.flashskyai: {
      'SessionStart': HookEvent.sessionStart,
      'SessionEnd': HookEvent.sessionEnd,
      'UserPromptSubmit': HookEvent.userPromptSubmit,
      'PreToolUse': HookEvent.preToolUse,
      'PostToolUse': HookEvent.postToolUse,
      'PostToolUseFailure': HookEvent.postToolUseFailure,
      'PermissionRequest': HookEvent.permissionRequest,
      'Stop': HookEvent.stop,
      'StopFailure': HookEvent.stopFailure,
      'SubagentStop': HookEvent.subagentStop,
      'PreCompact': HookEvent.preCompact,
      'Notification': HookEvent.notification,
    },
    CliTool.codex: {
      'SessionStart': HookEvent.sessionStart,
      'SessionEnd': HookEvent.sessionEnd,
      'UserPromptSubmit': HookEvent.userPromptSubmit,
      'PreToolUse': HookEvent.preToolUse,
      'PostToolUse': HookEvent.postToolUse,
      'PermissionRequest': HookEvent.permissionRequest,
      'Stop': HookEvent.stop,
      'SubagentStop': HookEvent.subagentStop,
      'PreCompact': HookEvent.preCompact,
    },
    CliTool.cursor: {
      'sessionStart': HookEvent.sessionStart,
      'sessionEnd': HookEvent.sessionEnd,
      'beforeSubmitPrompt': HookEvent.userPromptSubmit,
      'preToolUse': HookEvent.preToolUse,
      'postToolUse': HookEvent.postToolUse,
      'postToolUseFailure': HookEvent.postToolUseFailure,
      'stop': HookEvent.stop,
      'subagentStop': HookEvent.subagentStop,
      'preCompact': HookEvent.preCompact,
      'beforeShellExecution': HookEvent.shellCommandRequest,
    },
  };

  static HookEvent? map(CliTool cli, String nativeEvent) =>
      tables[cli]?[nativeEvent];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/hook/import/hook_event_name_mapper_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/hook/import/hook_event_name_mapper.dart \
  client/test/services/hook/import/hook_event_name_mapper_test.dart
git commit -m "feat(hooks-import): data-driven native event name mapper"
```

---

### Task 4: HookScriptExtractor（脚本引用识别 + 读取 + 降级）

**Files:**
- Create: `client/lib/services/hook/import/hook_script_extractor.dart`
- Test: `client/test/services/hook/import/hook_script_extractor_test.dart`

**Interfaces:**
- Consumes: `Filesystem`（`io/filesystem.dart`）。
- Produces:
```dart
sealed class ScriptExtraction { const ScriptExtraction(); }
final class ScriptCopy extends ScriptExtraction {
  const ScriptCopy({required this.interpreter, required this.fileName, required this.content});
  final String interpreter; final String fileName; final String content;
}
final class RawCommand extends ScriptExtraction {
  const RawCommand({this.reason});
  final String? reason;  // null=内联；'placeholder'=占位符；'unreadable'=读取失败
}
class HookScriptExtractor {
  HookScriptExtractor({required Filesystem fs, this.homeDir});
  Future<ScriptExtraction> extract(String command);
}
```
Task 7 parser 使用。

- [ ] **Step 1: Write the failing test**

`client/test/services/hook/import/hook_script_extractor_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/hook/import/hook_script_extractor.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;

  setUp(() {
    fs = InMemoryFilesystem();
  });

  HookScriptExtractor extractor({String? home}) =>
      HookScriptExtractor(fs: fs, homeDir: home);

  test('interpreter prefix extracts script and reads content', () async {
    await fs.writeString('/x/guard.sh', '#!/usr/bin/env bash\nexit 2');
    final result = await extractor().extract('bash /x/guard.sh');
    expect(result, isA<ScriptCopy>());
    final copy = result as ScriptCopy;
    expect(copy.interpreter, 'bash');
    expect(copy.fileName, 'guard.sh');
    expect(copy.content, contains('exit 2'));
  });

  test('python3 with quoted path', () async {
    await fs.writeString('/a b/x.py', 'print(1)');
    final result = await extractor()
        .extract('python3 "/a b/x.py"');
    final copy = result as ScriptCopy;
    expect(copy.interpreter, 'python3');
    expect(copy.fileName, 'x.py');
    expect(copy.content, 'print(1)');
  });

  test('-c inline command stays raw', () async {
    final result = await extractor().extract('python3 -c "print(1)"');
    expect(result, isA<RawCommand>());
    expect((result as RawCommand).reason, isNull);
  });

  test('bare absolute path uses bash interpreter', () async {
    await fs.writeString('/x/run.sh', 'echo hi');
    final result = await extractor().extract('/x/run.sh');
    final copy = result as ScriptCopy;
    expect(copy.interpreter, 'bash');
    expect(copy.fileName, 'run.sh');
  });

  test('placeholder path degrades to raw with reason', () async {
    final result = await extractor()
        .extract('bash \${CLAUDE_PROJECT_DIR}/.claude/hooks/x.sh');
    expect(result, isA<RawCommand>());
    expect((result as RawCommand).reason, 'placeholder');
  });

  test('unreadable script degrades to raw with reason', () async {
    final result = await extractor().extract('bash /missing/x.sh');
    expect(result, isA<RawCommand>());
    expect((result as RawCommand).reason, 'unreadable');
  });

  test('inline shell command stays raw', () async {
    final result = await extractor().extract("echo hi >> /tmp/log");
    expect(result, isA<RawCommand>());
    expect((result as RawCommand).reason, isNull);
  });

  test('tilde expands via homeDir', () async {
    await fs.writeString('/home/u/x.sh', 'echo hi');
    final result = await extractor(home: '/home/u').extract('bash ~/x.sh');
    final copy = result as ScriptCopy;
    expect(copy.fileName, 'x.sh');
    expect(copy.content, 'echo hi');
  });

  test('tilde without homeDir degrades to raw', () async {
    final result = await extractor().extract('bash ~/x.sh');
    expect(result, isA<RawCommand>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/hook/import/hook_script_extractor_test.dart -v`
Expected: FAIL — 文件不存在。

- [ ] **Step 3: Write minimal implementation**

`client/lib/services/hook/import/hook_script_extractor.dart`:
```dart
import '../../../io/filesystem.dart';
import 'hook_json_dialect.dart';

sealed class ScriptExtraction {
  const ScriptExtraction();
}

/// 识别为脚本引用且成功读取：解释器 + 原文件名 + 内容（库内路径重写由
/// [HookImportParser] 完成）。
final class ScriptCopy extends ScriptExtraction {
  const ScriptCopy({
    required this.interpreter,
    required this.fileName,
    required this.content,
  });

  final String interpreter;
  final String fileName;
  final String content;
}

/// 内联命令或路径不可解析：保留原命令字符串。
final class RawCommand extends ScriptExtraction {
  const RawCommand({this.reason});

  /// null = 内联命令；'placeholder' = 含占位符；'unreadable' = 读取失败。
  final String? reason;
}

/// 从 command 字符串识别脚本引用并读取内容（通用、CLI 无关）。
class HookScriptExtractor {
  HookScriptExtractor({required Filesystem fs, this.homeDir})
    : _fs = fs;

  final Filesystem _fs;

  /// `~` 展开的宿主 home；null 时含 `~` 的路径视为不可解析。
  final String? homeDir;

  static const Set<String> interpreters = {
    'bash', 'sh', 'zsh', 'python3', 'python', 'node', 'powershell', 'pwsh',
    'ruby', 'perl',
  };

  Future<ScriptExtraction> extract(String command) async {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return const RawCommand();
    final tokens = trimmed.split(RegExp(r'\s+'));
    final first = tokens.first;

    String? scriptPath;
    String interpreter = 'bash';
    if (interpreters.contains(first)) {
      if (tokens.length > 1 && tokens[1] == '-c') {
        return const RawCommand();
      }
      for (final token in tokens.skip(1)) {
        final cleaned = stripQuotes(token);
        if (isPathLike(cleaned)) {
          scriptPath = cleaned;
          interpreter = first;
          break;
        }
        if (cleaned.startsWith('-')) continue;
      }
    } else if (isPathLike(stripQuotes(first))) {
      scriptPath = stripQuotes(first);
    } else {
      return const RawCommand();
    }

    if (scriptPath == null) return const RawCommand();
    if (_hasPlaceholder(scriptPath)) return const RawCommand(reason: 'placeholder');

    var resolved = scriptPath;
    if (resolved.startsWith('~')) {
      final home = homeDir;
      if (home == null || home.isEmpty) {
        return const RawCommand(reason: 'placeholder');
      }
      resolved = '$home${resolved.substring(1)}';
    }

    final content = await _fs.readString(resolved);
    if (content == null) return const RawCommand(reason: 'unreadable');

    return ScriptCopy(
      interpreter: interpreter,
      fileName: _fs.pathContext.basename(resolved),
      content: content,
    );
  }

  static bool _hasPlaceholder(String path) =>
      path.contains(r'${') || path.contains(r'$(') || RegExp(r'\$[A-Za-z_]').hasMatch(path);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/hook/import/hook_script_extractor_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/hook/import/hook_script_extractor.dart \
  client/test/services/hook/import/hook_script_extractor_test.dart
git commit -m "feat(hooks-import): script reference extraction with raw fallback"
```

---

### Task 5: 分组 JSON 内核 + claude/codex 方言

**Files:**
- Create: `client/lib/services/hook/import/hook_grouped_json_parser.dart`
- Create: `client/lib/services/hook/import/claude_family_hooks_json_dialect.dart`
- Create: `client/lib/services/hook/import/codex_hooks_json_dialect.dart`
- Test: `client/test/services/hook/import/hook_grouped_json_parser_test.dart`

**Interfaces:**
- Consumes: `RawHookEntry`/`HookJsonDialect`（Task 2）。
- Produces: `abstract final class HookGroupedJsonParser{ static List<RawHookEntry> parse(String jsonText, List<String> warnings, {Set<String> allowedTopLevelKeys = const {}}); }`；`class ClaudeFamilyHooksJsonDialect implements HookJsonDialect`（cli=claude）；`class CodexHooksJsonDialect implements HookJsonDialect`（cli=codex，顶层多允许 `description`）。Task 7 parser 按 `cli` 分派。

- [ ] **Step 1: Write the failing test**

`client/test/services/hook/import/hook_grouped_json_parser_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/hook/import/claude_family_hooks_json_dialect.dart';
import 'package:teampilot/services/hook/import/codex_hooks_json_dialect.dart';
import 'package:teampilot/services/hook/import/hook_grouped_json_parser.dart';

void main() {
  const claude = ClaudeFamilyHooksJsonDialect();
  const codex = CodexHooksJsonDialect();

  test('claude: settings.json hooks map with matcher group and command/http',
      () {
    const json = '''
{
  "apiKeyHelper": {"enabled": true},
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [
        {"type": "command", "command": "bash /x/guard.sh", "timeout": 5,
         "if": "Bash(rm *)", "async": true},
        {"type": "http", "url": "http://127.0.0.1:1/h", "headers": {"X-A": "b"}}
      ]}
    ]
  }
}''';
    final warnings = <String>[];
    final entries = claude.parseJson(json, warnings);
    expect(warnings, isEmpty);
    expect(entries, hasLength(2));
    final cmd = entries[0];
    expect(cmd.nativeEvent, 'PreToolUse');
    expect(cmd.matcher, 'Bash');
    expect(cmd.type, 'command');
    expect(cmd.command, 'bash /x/guard.sh');
    expect(cmd.timeoutSec, 5);
    expect(cmd.native, {'if': 'Bash(rm *)', 'async': true});
    expect(cmd.unsupportedFields, containsAll(['if', 'async']));
    final http = entries[1];
    expect(http.type, 'http');
    expect(http.url, 'http://127.0.0.1:1/h');
    expect(http.headers, {'X-A': 'b'});
  });

  test('claude: pasted hooks-only fragment works (no top-level hooks key)', () {
    const json = '{"Stop": [{"hooks": [{"type": "command", "command": "echo done"}]}]}';
    final warnings = <String>[];
    final entries = claude.parseJson(json, warnings);
    expect(entries.single.nativeEvent, 'Stop');
    expect(entries.single.command, 'echo done');
  });

  test('claude: mcp_tool/prompt/agent handlers warn and are skipped', () {
    const json = '''
{"hooks": {"Stop": [
  {"hooks": [
    {"type": "command", "command": "echo a"},
    {"type": "prompt", "prompt": "is it ok?"},
    {"type": "mcp_tool", "server": "x", "tool": "y"},
    {"type": "agent", "prompt": "check"}
  ]}
]}}''';
    final warnings = <String>[];
    final entries = claude.parseJson(json, warnings);
    expect(entries, hasLength(1));
    expect(warnings, containsAll([
      'hook_import_type_unsupported_prompt',
      'hook_import_type_unsupported_mcp_tool',
      'hook_import_type_unsupported_agent',
    ]));
  });

  test('codex: description top-level ignored, statusMessage into native', () {
    const json = '''
{
  "description": "team hooks",
  "hooks": {
    "SessionStart": [
      {"matcher": "startup", "hooks": [
        {"type": "command", "command": "python3 ~/.codex/hooks/s.py",
         "statusMessage": "Loading", "additionalContextLimit": 5000,
         "timeout": 30}
      ]}
    ]
  }
}''';
    final warnings = <String>[];
    final entries = codex.parseJson(json, warnings);
    expect(entries.single.nativeEvent, 'SessionStart');
    expect(entries.single.matcher, 'startup');
    expect(entries.single.timeoutSec, 30);
    expect(entries.single.native, {
      'statusMessage': 'Loading',
      'additionalContextLimit': 5000,
    });
  });

  test('missing hooks and bad json produce warnings not throws', () {
    final w1 = <String>[];
    expect(HookGroupedJsonParser.parse('{"version": 1}', w1), isEmpty);
    expect(w1, contains('hook_import_no_hooks'));
    final w2 = <String>[];
    expect(HookGroupedJsonParser.parse('not json', w2), isEmpty);
    expect(w2, contains('hook_import_invalid_json_shape'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/hook/import/hook_grouped_json_parser_test.dart -v`
Expected: FAIL — 文件不存在。

- [ ] **Step 3: Write minimal implementation**

`client/lib/services/hook/import/hook_grouped_json_parser.dart`:
```dart
import 'dart:convert';

import 'hook_json_dialect.dart';

/// claude-family / codex 共享的分组 JSON 内核：
/// `{"hooks": {"<Event>": [{"matcher"?, "hooks": [handler...]}]}}`。
/// 支持只贴 hooks 段（根对象本身是事件 → 组 map）。
abstract final class HookGroupedJsonParser {
  HookGroupedJsonParser._();

  static List<RawHookEntry> parse(
    String jsonText,
    List<String> warnings, {
    Set<String> allowedTopLevelKeys = const {},
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      warnings.add('hook_import_invalid_json_shape');
      return const [];
    }
    if (decoded is! Map) {
      warnings.add('hook_import_invalid_json_shape');
      return const [];
    }
    final root = decoded.cast<String, Object?>();

    Map<String, Object?>? groups;
    final hooks = root['hooks'];
    if (hooks is Map) {
      groups = hooks.cast<String, Object?>();
    } else if (looksLikeGroups(root)) {
      groups = root;
    } else {
      warnings.add('hook_import_no_hooks');
      return const [];
    }

    final entries = <RawHookEntry>[];
    for (final groupEntry in groups.entries) {
      final event = groupEntry.key;
      final groupsList = groupEntry.value;
      if (groupsList is! List) {
        warnings.add('hook_import_bad_group_$event');
        continue;
      }
      for (final group in groupsList) {
        if (group is! Map) {
          warnings.add('hook_import_bad_group_$event');
          continue;
        }
        final g = group.cast<String, Object?>();
        final matcher = hookJsonString(g, 'matcher');
        final handlers = g['hooks'];
        if (handlers is! List) {
          warnings.add('hook_import_bad_group_$event');
          continue;
        }
        for (final handler in handlers) {
          if (handler is! Map) {
            warnings.add('hook_import_bad_handler_$event');
            continue;
          }
          final h = handler.cast<String, Object?>();
          final type = hookJsonString(h, 'type') ?? 'command';
          final timeout = hookJsonInt(h, 'timeout');
          final native = <String, Object?>{};
          final unsupported = <String>[];
          const consumed = {'type', 'command', 'url', 'headers', 'timeout'};
          for (final entry in h.entries) {
            if (consumed.contains(entry.key)) continue;
            native[entry.key] = entry.value;
            unsupported.add(entry.key);
          }
          switch (type) {
            case 'command':
              final command = hookJsonString(h, 'command');
              if (command == null) {
                warnings.add('hook_import_bad_handler_$event');
                continue;
              }
              entries.add(RawHookEntry(
                nativeEvent: event,
                matcher: matcher,
                type: 'command',
                command: command,
                timeoutSec: timeout,
                native: native,
                unsupportedFields: unsupported,
              ));
            case 'http':
              final url = hookJsonString(h, 'url');
              if (url == null) {
                warnings.add('hook_import_bad_handler_$event');
                continue;
              }
              entries.add(RawHookEntry(
                nativeEvent: event,
                matcher: matcher,
                type: 'http',
                url: url,
                headers: hookJsonStringMap(h, 'headers'),
                timeoutSec: timeout,
                native: native,
                unsupportedFields: unsupported,
              ));
            default:
              warnings.add('hook_import_type_unsupported_$type');
          }
        }
      }
    }
    return entries;
  }
}
```

`client/lib/services/hook/import/claude_family_hooks_json_dialect.dart`:
```dart
import '../../../models/team_config.dart';
import 'hook_grouped_json_parser.dart';
import 'hook_json_dialect.dart';

/// claude / flashskyai：settings.json 的 `hooks` map（或只贴 hooks 段）。
class ClaudeFamilyHooksJsonDialect implements HookJsonDialect {
  const ClaudeFamilyHooksJsonDialect();

  @override
  CliTool get cli => CliTool.claude;

  @override
  List<RawHookEntry> parseJson(String jsonText, List<String> warnings) =>
      HookGroupedJsonParser.parse(jsonText, warnings);
}
```

`client/lib/services/hook/import/codex_hooks_json_dialect.dart`:
```dart
import '../../../models/team_config.dart';
import 'hook_grouped_json_parser.dart';
import 'hook_json_dialect.dart';

/// codex：`~/.codex/hooks.json`（顶层允许 `description`）。
class CodexHooksJsonDialect implements HookJsonDialect {
  const CodexHooksJsonDialect();

  @override
  CliTool get cli => CliTool.codex;

  @override
  List<RawHookEntry> parseJson(String jsonText, List<String> warnings) =>
      HookGroupedJsonParser.parse(
        jsonText,
        warnings,
        allowedTopLevelKeys: const {'description'},
      );
}
```
（`allowedTopLevelKeys` 当前仅作方言声明；共享内核暂不校验顶层未知键——保持宽容。若 analyzer 报未使用参数，在 parse 内加一行 `if (allowedTopLevelKeys.isEmpty) {}` 注释说明或改用 `_ = allowedTopLevelKeys;`——以 analyzer 干净为准，不得删参数。）

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/hook/import/hook_grouped_json_parser_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/hook/import/hook_grouped_json_parser.dart \
  client/lib/services/hook/import/claude_family_hooks_json_dialect.dart \
  client/lib/services/hook/import/codex_hooks_json_dialect.dart \
  client/test/services/hook/import/hook_grouped_json_parser_test.dart
git commit -m "feat(hooks-import): grouped JSON kernel + claude/codex dialects"
```

---

### Task 6: Cursor 扁平方言

**Files:**
- Create: `client/lib/services/hook/import/cursor_hooks_json_dialect.dart`
- Test: `client/test/services/hook/import/cursor_hooks_json_dialect_test.dart`

**Interfaces:**
- Consumes: `RawHookEntry`/`HookJsonDialect`/`hookJsonString`/`hookJsonInt`（Task 2）。
- Produces: `class CursorHooksJsonDialect implements HookJsonDialect`（cli=cursor；`{"version":1,"hooks":{"<event>":[扁平条目]}}`；条目 `command`/`matcher`?/`timeout`?/`loop_limit`?/`type`?/`failClosed`?；`loop_limit`/`failClosed` → native+unsupported；`type: "prompt"` → warning 跳过）。

- [ ] **Step 1: Write the failing test**

`client/test/services/hook/import/cursor_hooks_json_dialect_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/hook/import/cursor_hooks_json_dialect.dart';

void main() {
  const dialect = CursorHooksJsonDialect();

  test('flat entries with matcher/timeout/loop_limit/failClosed', () {
    const json = '''
{"version": 1, "hooks": {
  "preToolUse": [
    {"command": "bash /x/guard.sh", "matcher": "Shell|Read", "timeout": 30,
     "loop_limit": null, "failClosed": true}
  ],
  "stop": [
    {"command": "bash /x/stop.sh", "loop_limit": null}
  ]
}}''';
    final warnings = <String>[];
    final entries = dialect.parseJson(json, warnings);
    expect(warnings, isEmpty);
    expect(entries, hasLength(2));
    final pre = entries[0];
    expect(pre.nativeEvent, 'preToolUse');
    expect(pre.matcher, 'Shell|Read');
    expect(pre.type, 'command');
    expect(pre.timeoutSec, 30);
    expect(pre.native, {'loop_limit': null, 'failClosed': true});
    expect(pre.unsupportedFields, containsAll(['loop_limit', 'failClosed']));
    final stop = entries[1];
    expect(stop.nativeEvent, 'stop');
    expect(stop.matcher, isNull);
    expect(stop.native, {'loop_limit': null});
  });

  test('prompt type warns and is skipped', () {
    const json = '''
{"version": 1, "hooks": {
  "beforeShellExecution": [
    {"type": "prompt", "prompt": "safe?", "timeout": 10},
    {"command": "bash /x/a.sh"}
  ]
}}''';
    final warnings = <String>[];
    final entries = dialect.parseJson(json, warnings);
    expect(entries, hasLength(1));
    expect(entries.single.command, 'bash /x/a.sh');
    expect(warnings, contains('hook_import_type_unsupported_prompt'));
  });

  test('missing hooks warns', () {
    final warnings = <String>[];
    expect(dialect.parseJson('{"version": 1}', warnings), isEmpty);
    expect(warnings, contains('hook_import_no_hooks'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/hook/import/cursor_hooks_json_dialect_test.dart -v`
Expected: FAIL — 文件不存在。

- [ ] **Step 3: Write minimal implementation**

`client/lib/services/hook/import/cursor_hooks_json_dialect.dart`:
```dart
import 'dart:convert';

import '../../../models/team_config.dart';
import 'hook_json_dialect.dart';

/// cursor：`~/.cursor/hooks.json`（`{"version":1,"hooks":{<event>:[扁平条目]}}`）。
/// 条目字段直接映射（matcher 在条目上）；`loop_limit`/`failClosed` 旁路保留；
/// `type: "prompt"` 跳过并 warning。
class CursorHooksJsonDialect implements HookJsonDialect {
  const CursorHooksJsonDialect();

  @override
  CliTool get cli => CliTool.cursor;

  @override
  List<RawHookEntry> parseJson(String jsonText, List<String> warnings) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      warnings.add('hook_import_invalid_json_shape');
      return const [];
    }
    if (decoded is! Map) {
      warnings.add('hook_import_invalid_json_shape');
      return const [];
    }
    final root = decoded.cast<String, Object?>();
    final hooks = root['hooks'];
    if (hooks is! Map) {
      warnings.add('hook_import_no_hooks');
      return const [];
    }
    final entries = <RawHookEntry>[];
    for (final groupEntry in hooks.cast<String, Object?>().entries) {
      final event = groupEntry.key;
      final list = groupEntry.value;
      if (list is! List) {
        warnings.add('hook_import_bad_group_$event');
        continue;
      }
      for (final item in list) {
        if (item is! Map) {
          warnings.add('hook_import_bad_handler_$event');
          continue;
        }
        final h = item.cast<String, Object?>();
        final type = hookJsonString(h, 'type') ?? 'command';
        if (type != 'command') {
          warnings.add('hook_import_type_unsupported_$type');
          continue;
        }
        final command = hookJsonString(h, 'command');
        if (command == null) {
          warnings.add('hook_import_bad_handler_$event');
          continue;
        }
        final native = <String, Object?>{};
        final unsupported = <String>[];
        const consumed = {'type', 'command', 'matcher', 'timeout'};
        for (final entry in h.entries) {
          if (consumed.contains(entry.key)) continue;
          native[entry.key] = entry.value;
          unsupported.add(entry.key);
        }
        entries.add(RawHookEntry(
          nativeEvent: event,
          matcher: hookJsonString(h, 'matcher'),
          type: 'command',
          command: command,
          timeoutSec: hookJsonInt(h, 'timeout'),
          native: native,
          unsupportedFields: unsupported,
        ));
      }
    }
    return entries;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/hook/import/cursor_hooks_json_dialect_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/hook/import/cursor_hooks_json_dialect.dart \
  client/test/services/hook/import/cursor_hooks_json_dialect_test.dart
git commit -m "feat(hooks-import): cursor flat hooks.json dialect"
```

---

### Task 7: HookImportParser facade（事件映射 + 脚本提取 + 幂等 id）

**Files:**
- Create: `client/lib/services/hook/import/hook_import_parser.dart`
- Test: `client/test/services/hook/import/hook_import_parser_test.dart`

**Interfaces:**
- Consumes: Task 1-6（`HookDefinition.native`、dialects、`HookEventNameMapper`、`HookScriptExtractor`）。
- Produces:
```dart
class HookImportDraft {
  const HookImportDraft({required this.definition, this.scriptFileName, this.scriptContent, this.unsupportedFields = const [], this.warnings = const []});
  final HookDefinition definition;
  final String? scriptFileName;   // ScriptCopy 时需写入库的脚本文件名
  final String? scriptContent;
  final List<String> unsupportedFields;
  final List<String> warnings;
}
class HookImportResult { const HookImportResult({this.drafts = const [], this.warnings = const []}); final List<HookImportDraft> drafts; final List<String> warnings; }
class HookImportParser {
  HookImportParser({required Filesystem fs, required String teampilotRoot, String? homeDir});
  Future<HookImportResult> parseJson({required CliTool cli, required String jsonText});
}
String hookImportId(HookEvent event, RawHookEntry entry);  // 'import-<fnv1a hex 12>'
```
Task 8 service、Task 9 UI 使用。

- [ ] **Step 1: Write the failing test**

`client/test/services/hook/import/hook_import_parser_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/hook/import/hook_import_parser.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;

  setUp(() {
    fs = InMemoryFilesystem();
  });

  HookImportParser parser({String? home}) =>
      HookImportParser(fs: fs, teampilotRoot: '/root', homeDir: home);

  test('claude json → drafts with mapped event and script copy', () async {
    await fs.writeString('/x/guard.sh', 'exit 2');
    final result = await parser().parseJson(
      cli: CliTool.claude,
      jsonText: '''
{"hooks": {"PreToolUse": [
  {"matcher": "Bash", "hooks": [
    {"type": "command", "command": "bash /x/guard.sh", "timeout": 5,
     "async": true}
  ]}
]}}''',
    );
    expect(result.warnings, isEmpty);
    final draft = result.drafts.single;
    expect(draft.definition.event, HookEvent.preToolUse);
    expect(draft.definition.matcher, 'Bash');
    expect(draft.definition.timeoutSec, 5);
    expect(draft.definition.native, {'async': true});
    expect(draft.unsupportedFields, ['async']);
    final action = draft.definition.action as CommandHookAction;
    expect(action.command, 'bash /root/hooks/${draft.definition.id}/guard.sh');
    expect(draft.scriptFileName, 'guard.sh');
    expect(draft.scriptContent, 'exit 2');
    expect(draft.definition.id, startsWith('import-'));
    expect(draft.definition.id, hasLength('import-'.length + 12));
  });

  test('raw command stays raw; unsupported event dropped with warning', () async {
    final result = await parser().parseJson(
      cli: CliTool.claude,
      jsonText: '''
{"hooks": {
  "PostCompact": [{"hooks": [{"type": "command", "command": "echo a"}]}],
  "Stop": [{"hooks": [{"type": "command", "command": "echo done"}]}]
}}''',
    );
    expect(result.drafts, hasLength(1));
    expect(result.warnings, ['hook_import_event_unsupported_PostCompact']);
    expect(
      (result.drafts.single.definition.action as CommandHookAction).command,
      'echo done',
    );
  });

  test('cursor json maps lowercase events; http keeps url', () async {
    final result = await parser().parseJson(
      cli: CliTool.cursor,
      jsonText: '''
{"version": 1, "hooks": {
  "beforeSubmitPrompt": [{"command": "echo a"}]
}}''',
    );
    final draft = result.drafts.single;
    expect(draft.definition.event, HookEvent.userPromptSubmit);
  });

  test('http handler becomes HttpHookAction', () async {
    final result = await parser().parseJson(
      cli: CliTool.claude,
      jsonText: '''
{"hooks": {"Stop": [
  {"hooks": [{"type": "http", "url": "http://127.0.0.1:1/h", "headers": {"X-A": "b"}}]}
]}}''',
    );
    final action = result.drafts.single.definition.action as HttpHookAction;
    expect(action.url, 'http://127.0.0.1:1/h');
    expect(action.headers, {'X-A': 'b'});
  });

  test('id is deterministic and differs across entries', () async {
    const json = '''
{"hooks": {"Stop": [
  {"hooks": [{"type": "command", "command": "echo a"}]},
  {"hooks": [{"type": "command", "command": "echo b"}]}
]}}''';
    final a = await parser().parseJson(cli: CliTool.claude, jsonText: json);
    final b = await parser().parseJson(cli: CliTool.claude, jsonText: json);
    expect(a.drafts[0].definition.id, b.drafts[0].definition.id);
    expect(a.drafts[0].definition.id, isNot(a.drafts[1].definition.id));
  });

  test('bad json produces warning and no drafts', () async {
    final result =
        await parser().parseJson(cli: CliTool.claude, jsonText: 'not json');
    expect(result.drafts, isEmpty);
    expect(result.warnings.single, startsWith('hook_import_invalid_json'));
  });

  test('opencode cli is unsupported', () async {
    final result =
        await parser().parseJson(cli: CliTool.opencode, jsonText: '{}');
    expect(result.drafts, isEmpty);
    expect(result.warnings, ['hook_import_cli_unsupported_opencode']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/hook/import/hook_import_parser_test.dart -v`
Expected: FAIL — 文件不存在。

- [ ] **Step 3: Write minimal implementation**

`client/lib/services/hook/import/hook_import_parser.dart`:
```dart
import 'dart:convert';

import '../../../models/hook_definition.dart';
import '../../../models/hook_entry.dart';
import '../../../models/hook_event.dart';
import '../../../models/team_config.dart';
import '../../../io/filesystem.dart';
import 'claude_family_hooks_json_dialect.dart';
import 'codex_hooks_json_dialect.dart';
import 'cursor_hooks_json_dialect.dart';
import 'hook_event_name_mapper.dart';
import 'hook_json_dialect.dart';
import 'hook_script_extractor.dart';

/// 一条可导入的 hook（预览与落库共用）。
class HookImportDraft {
  const HookImportDraft({
    required this.definition,
    this.scriptFileName,
    this.scriptContent,
    this.unsupportedFields = const [],
    this.warnings = const [],
  });

  final HookDefinition definition;

  /// ScriptCopy 时需写入库的脚本文件名（`hooks/{id}/{fileName}`）。
  final String? scriptFileName;
  final String? scriptContent;

  /// 导入后不生效的字段名（预览标注）。
  final List<String> unsupportedFields;
  final List<String> warnings;
}

class HookImportResult {
  const HookImportResult({this.drafts = const [], this.warnings = const []});

  final List<HookImportDraft> drafts;
  final List<String> warnings;
}

/// 通用解析入口：CLI 选择 + JSON 文本 → 归一化 drafts。
class HookImportParser {
  HookImportParser({
    required Filesystem fs,
    required String teampilotRoot,
    String? homeDir,
  }) : _fs = fs,
       _teampilotRoot = teampilotRoot,
       _homeDir = homeDir;

  final Filesystem _fs;
  final String _teampilotRoot;
  final String? _homeDir;

  static final Map<CliTool, HookJsonDialect> _dialects = {
    CliTool.claude: const ClaudeFamilyHooksJsonDialect(),
    CliTool.flashskyai: const ClaudeFamilyHooksJsonDialect(),
    CliTool.codex: const CodexHooksJsonDialect(),
    CliTool.cursor: const CursorHooksJsonDialect(),
  };

  Future<HookImportResult> parseJson({
    required CliTool cli,
    required String jsonText,
  }) async {
    final dialect = _dialects[cli];
    if (dialect == null) {
      return HookImportResult(warnings: ['hook_import_cli_unsupported_${cli.name}']);
    }
    final warnings = <String>[];
    final List<RawHookEntry> raw;
    try {
      raw = dialect.parseJson(jsonText, warnings);
    } on FormatException catch (e) {
      warnings.add('hook_import_invalid_json: ${e.message}');
      return HookImportResult(warnings: warnings);
    }

    final extractor = HookScriptExtractor(fs: _fs, homeDir: _homeDir);
    final drafts = <HookImportDraft>[];
    for (final entry in raw) {
      final event = HookEventNameMapper.map(cli, entry.nativeEvent);
      if (event == null) {
        warnings.add('hook_import_event_unsupported_${entry.nativeEvent}');
        continue;
      }
      final id = hookImportId(event, entry);
      final HookDefinition definition;
      String? scriptFileName;
      String? scriptContent;
      if (entry.type == 'http') {
        definition = HookDefinition(
          id: id,
          name: event.name,
          event: event,
          matcher: entry.matcher,
          action: HttpHookAction(
            url: entry.url!,
            headers: entry.headers,
          ),
          timeoutSec: entry.timeoutSec,
          native: entry.native.isEmpty ? null : entry.native,
        );
      } else {
        final command = entry.command!;
        final extraction = await extractor.extract(command);
        switch (extraction) {
          case ScriptCopy copy:
            scriptFileName = copy.fileName;
            scriptContent = copy.content;
            definition = HookDefinition(
              id: id,
              name: event.name,
              event: event,
              matcher: entry.matcher,
              action: CommandHookAction.raw(
                '${copy.interpreter} $_teampilotRoot/hooks/$id/${copy.fileName}',
              ),
              timeoutSec: entry.timeoutSec,
              native: entry.native.isEmpty ? null : entry.native,
            );
          case RawCommand():
            definition = HookDefinition(
              id: id,
              name: event.name,
              event: event,
              matcher: entry.matcher,
              action: CommandHookAction.raw(command),
              timeoutSec: entry.timeoutSec,
              native: entry.native.isEmpty ? null : entry.native,
            );
        }
      }
      drafts.add(HookImportDraft(
        definition: definition,
        scriptFileName: scriptFileName,
        scriptContent: scriptContent,
        unsupportedFields: entry.unsupportedFields,
        warnings: entry.warnings,
      ));
    }
    return HookImportResult(drafts: drafts, warnings: warnings);
  }
}

/// 确定性 id：`import-<fnv1a('event|matcher|command|url') 十六进制前 12 位>`。
/// 同一条目重复导入 → 同 id → upsert 覆盖（幂等）。
String hookImportId(HookEvent event, RawHookEntry entry) {
  final key =
      '${event.name}|${entry.matcher ?? ''}|${entry.command ?? entry.url ?? ''}';
  return 'import-${_fnv1aHex(key).substring(0, 12)}';
}

String _fnv1aHex(String input) {
  var hash = 0x811C9DC5;
  for (final codeUnit in input.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/hook/import/hook_import_parser_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/hook/import/hook_import_parser.dart \
  client/test/services/hook/import/hook_import_parser_test.dart
git commit -m "feat(hooks-import): parser facade with event mapping, script extraction, fnv id"
```

---

### Task 8: HookImportService（落库）

**Files:**
- Create: `client/lib/services/hook/import/hook_import_service.dart`
- Test: `client/test/services/hook/import/hook_import_service_test.dart`

**Interfaces:**
- Consumes: `HookImportDraft`（Task 7）、`HookRepository`（`save`/`writeScript`）。
- Produces: `class HookImportService{ HookImportService({required HookRepository repository}); Future<int> import(List<HookImportDraft> drafts); }`。Task 9 UI 使用。

- [ ] **Step 1: Write the failing test**

`client/test/services/hook/import/hook_import_service_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/services/hook/hook_repository.dart';
import 'package:teampilot/services/hook/import/hook_import_service.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  late HookRepository repository;
  late HookImportService service;

  setUp(() {
    fs = InMemoryFilesystem();
    repository = HookRepository(fs: fs, teampilotRoot: '/root');
    service = HookImportService(repository: repository);
  });

  test('import saves definitions and scripts', () async {
    final count = await service.import([
      HookImportDraft(
        definition: const HookDefinition(
          id: 'import-abc',
          name: 'preToolUse',
          event: HookEvent.preToolUse,
          action: CommandHookAction.raw('bash /root/hooks/import-abc/x.sh'),
        ),
        scriptFileName: 'x.sh',
        scriptContent: 'exit 2',
      ),
      HookImportDraft(
        definition: const HookDefinition(
          id: 'import-def',
          name: 'stop',
          event: HookEvent.stop,
          action: CommandHookAction.raw('echo done'),
        ),
      ),
    ]);
    expect(count, 2);
    expect(await repository.load('import-abc'), isNotNull);
    expect(await repository.readScript('import-abc', 'x.sh'), 'exit 2');
    expect(await repository.load('import-def'), isNotNull);
  });

  test('re-import with same id overwrites (idempotent upsert)', () async {
    await service.import([
      HookImportDraft(
        definition: const HookDefinition(
          id: 'import-abc',
          name: 'v1',
          event: HookEvent.stop,
          action: CommandHookAction.raw('echo one'),
        ),
      ),
    ]);
    await service.import([
      HookImportDraft(
        definition: const HookDefinition(
          id: 'import-abc',
          name: 'v2',
          event: HookEvent.stop,
          action: CommandHookAction.raw('echo two'),
        ),
      ),
    ]);
    final all = await repository.loadAll();
    expect(all, hasLength(1));
    expect(all.single.name, 'v2');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/hook/import/hook_import_service_test.dart -v`
Expected: FAIL — 文件不存在。

- [ ] **Step 3: Write minimal implementation**

`client/lib/services/hook/import/hook_import_service.dart`:
```dart
import '../hook_repository.dart';
import 'hook_import_parser.dart';

/// 把导入 drafts 落库：save 定义 + writeScript 脚本（幂等 upsert）。
class HookImportService {
  HookImportService({required HookRepository repository})
    : _repository = repository;

  final HookRepository _repository;

  Future<int> import(List<HookImportDraft> drafts) async {
    var count = 0;
    for (final draft in drafts) {
      await _repository.save(draft.definition);
      final fileName = draft.scriptFileName;
      final content = draft.scriptContent;
      if (fileName != null && content != null && content.isNotEmpty) {
        await _repository.writeScript(draft.definition.id, fileName, content);
      }
      count++;
    }
    return count;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/hook/import/hook_import_service_test.dart -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/hook/import/hook_import_service.dart \
  client/test/services/hook/import/hook_import_service_test.dart
git commit -m "feat(hooks-import): import service persists definitions and scripts"
```

---

### Task 9: HookImportDialog + 列表页入口 + 注入 + l10n

**Files:**
- Create: `client/lib/pages/hooks/hook_import_dialog.dart`
- Modify: `client/lib/app/app_shell.dart`（构造 parser/service）
- Modify: `client/lib/main.dart`（RepositoryProvider 提供）
- Modify: `client/lib/pages/hooks/hook_management_page.dart`（「导入」按钮）
- Modify: `client/lib/l10n/app_en.arb`、`app_zh.arb`
- Test: `client/test/pages/hooks/hook_import_dialog_test.dart`

**Interfaces:**
- Consumes: `HookImportParser`/`HookImportService`（Task 7-8）、`HookCubit`、`HookRepository`。
- Produces: `Future<bool?> showHookImportDialog(BuildContext context)`（返回是否导入了条目）；`HookImportDialog`（两阶段：输入 → 预览）。`app_shell.dart` 注入：
```dart
hookImportParser = HookImportParser(
  fs: AppStorage.fs,
  teampilotRoot: AppStorage.paths.basePath,
  homeDir: Platform.environment['HOME'],
);
hookImportService = HookImportService(repository: hookRepository);
```
`main.dart` 在 `RepositoryProvider<HookRepository>` 旁加 `RepositoryProvider<HookImportParser>.value(value: shell.hookImportParser)` 与 `RepositoryProvider<HookImportService>.value(value: shell.hookImportService)`（仿现有 hookRepository 注入，读 app_shell.dart 确认字段/构造传递方式并照抄模式）。

- [ ] **Step 1: Write the failing test**

`client/test/pages/hooks/hook_import_dialog_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/hook_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/hooks/hook_import_dialog.dart';
import 'package:teampilot/services/hook/hook_repository.dart';
import 'package:teampilot/services/hook/import/hook_import_parser.dart';
import 'package:teampilot/services/hook/import/hook_import_service.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  late HookRepository repository;
  late HookCubit cubit;
  late HookImportParser parser;
  late HookImportService service;

  setUp(() {
    fs = InMemoryFilesystem();
    repository = HookRepository(fs: fs, teampilotRoot: '/root');
    cubit = HookCubit(repository: repository);
    parser = HookImportParser(fs: fs, teampilotRoot: '/root');
    service = HookImportService(repository: repository);
  });

  tearDown(() => cubit.close());

  Future<void> pumpDialog(WidgetTester tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
          child: RepositoryProvider<HookRepository>.value(
            value: repository,
            child: RepositoryProvider<HookImportParser>.value(
              value: parser,
              child: RepositoryProvider<HookImportService>.value(
                value: service,
                child: BlocProvider<HookCubit>.value(
                  value: cubit,
                  child: Builder(
                    builder: (context) => Scaffold(
                      body: TextButton(
                        onPressed: () => showHookImportDialog(context),
                        child: const Text('import'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('paste json → parse → preview → import persists', (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text('import'));
    await tester.pumpAndSettle();

    // 默认 CLI 为 claude；粘贴 claude hooks 段
    await tester.enterText(
      find.byKey(const Key('hook-import-json')),
      '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo done"}]}]}}',
    );
    await tester.tap(find.byKey(const Key('hook-import-parse')));
    await tester.pumpAndSettle();

    expect(find.text('Stop'), findsOneWidget);
    expect(find.byKey(const Key('hook-import-preview')), findsOneWidget);

    await tester.tap(find.byKey(const Key('hook-import-confirm')));
    await tester.pumpAndSettle();

    final all = await repository.loadAll();
    expect(all, hasLength(1));
    expect(all.single.event.name, 'stop');
    expect(find.byKey(const Key('hook-import-confirm')), findsNothing);
  });

  testWidgets('parse errors show message and keep dialog open', (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text('import'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('hook-import-json')), 'nope');
    await tester.tap(find.byKey(const Key('hook-import-parse')));
    await tester.pumpAndSettle();

    expect(find.textContaining('hook_import_invalid_json'), findsOneWidget);
    expect(find.byKey(const Key('hook-import-confirm')), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/hooks/hook_import_dialog_test.dart -v`
Expected: FAIL — 文件不存在（另需 l10n 键）。

- [ ] **Step 3: Implement the dialog**

`client/lib/pages/hooks/hook_import_dialog.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/hook_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../services/hook/hook_repository.dart';
import '../../services/hook/import/hook_import_parser.dart';
import '../../services/hook/import/hook_import_service.dart';

/// 打开 hook 导入对话框：CLI 选择 + JSON 粘贴 → 解析预览 → 勾选导入。
/// 返回 `true` 表示至少导入了一条。
Future<bool?> showHookImportDialog(BuildContext context) {
  return showTpDialog<bool>(
    context: context,
    builder: (_) => const HookImportDialog(),
  );
}

class HookImportDialog extends StatefulWidget {
  const HookImportDialog({super.key});

  @override
  State<HookImportDialog> createState() => _HookImportDialogState();
}

class _HookImportDialogState extends State<HookImportDialog> {
  final _jsonController = TextEditingController();
  CliTool _cli = CliTool.claude;
  HookImportResult? _result;
  final _selected = <String>{};
  var _importing = false;

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    final result = await context
        .read<HookImportParser>()
        .parseJson(cli: _cli, jsonText: _jsonController.text);
    if (!mounted) return;
    setState(() {
      _result = result;
      _selected
        ..clear()
        ..addAll(result.drafts.map((d) => d.definition.id));
    });
  }

  Future<void> _import() async {
    if (_importing) return;
    final drafts = (_result?.drafts ?? const [])
        .where((d) => _selected.contains(d.definition.id))
        .toList();
    if (drafts.isEmpty) return;
    setState(() => _importing = true);
    final count = await context.read<HookImportService>().import(drafts);
    if (!mounted) return;
    setState(() => _importing = false);
    if (count > 0) {
      await context.read<HookCubit>().load();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = _result;
    return TpDialog(
      maxWidth: 640,
      maxHeight: 620,
      child: TpDialogPinnedLayout(
        header: TpDialogHeader(title: l10n.hookImport),
        body: result == null
            ? _buildInput(context, l10n)
            : _buildPreview(context, l10n, result),
        footer: TpDialogActions(
          children: [
            TextButton(
              key: const Key('hook-import-cancel'),
              onPressed: _importing
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            if (result != null)
              FilledButton(
                key: const Key('hook-import-confirm'),
                onPressed: _importing || _selected.isEmpty
                    ? null
                    : _import,
                child: Text(l10n.hookImportDone(_selected.length)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(BuildContext context, AppLocalizations l10n) {
    final l10nExt = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpFormField<CliTool>(
          initialValue: _cli,
          label: Text(l10nExt.hookImportCli),
          builder: (state) => TpSelect<CliTool>(
            key: const Key('hook-import-cli'),
            items: const [CliTool.claude, CliTool.flashskyai, CliTool.codex, CliTool.cursor],
            initialItem: _cli,
            searchable: false,
            itemLabel: (cli) => cli.name,
            onChanged: (value) {
              if (value == null) return;
              state.didChange(value);
              setState(() => _cli = value);
            },
          ),
        ),
        const SizedBox(height: 12),
        TpFormField<String>(
          initialValue: '',
          label: Text(l10n.hookImportJson),
          builder: (state) => TextField(
            key: const Key('hook-import-json'),
            controller: _jsonController,
            focusNode: state.focusNode,
            maxLines: 12,
            onChanged: state.didChange,
            decoration: InputDecoration(
              hintText: l10n.hookImportJsonHint,
              errorText: state.hasError ? '' : null,
              errorStyle: const TextStyle(height: 0, fontSize: 0),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            key: const Key('hook-import-parse'),
            onPressed: _parse,
            icon: const Icon(Icons.manage_search),
            label: Text(l10n.hookImportParse),
          ),
        ),
        if (result == null && _parseError != null) ...[
          const SizedBox(height: 8),
          Text(
            _parseError!,
            key: const Key('hook-import-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  String? get _parseError {
    final result = _result;
    if (result == null) return null;
    final errors = result.warnings.where((w) => w.startsWith('hook_import_invalid_json'));
    return errors.isEmpty ? null : errors.join('\n');
  }

  Widget _buildPreview(
    BuildContext context,
    AppLocalizations l10n,
    HookImportResult result,
  ) {
    final l10nExt = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final warning in result.warnings)
          if (!warning.startsWith('hook_import_invalid_json'))
            Text(
              warning,
              key: const Key('hook-import-warning'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.tertiary,
                fontSize: 12,
              ),
            ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            key: const Key('hook-import-preview'),
            children: [
              for (final draft in result.drafts)
                CheckboxListTile(
                  value: _selected.contains(draft.definition.id),
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _selected.add(draft.definition.id);
                      } else {
                        _selected.remove(draft.definition.id);
                      }
                    });
                  },
                  title: Text(
                    '${draft.definition.event.name}'
                    '${draft.definition.matcher == null ? '' : ' · ${draft.definition.matcher}'}',
                  ),
                  subtitle: Text(
                    _draftSubtitle(draft),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _draftSubtitle(HookImportDraft draft) {
    final action = draft.definition.action;
    final base = action is HttpHookAction
        ? action.url
        : (action as CommandHookAction).command ?? '';
    final parts = <String>[
      base,
      if (draft.scriptFileName != null) '📄 ${draft.scriptFileName}',
      if (draft.unsupportedFields.isNotEmpty)
        '⚠ ${draft.unsupportedFields.join(', ')}',
    ];
    return parts.join(' · ');
  }
}
```
注意：`_parseError` 的取值时机问题——`_buildInput` 在 result==null 时渲染，而错误信息存在 result.warnings 里（result 非 null 才进预览）。**修正设计**：解析失败（无 drafts 且含 invalid_json warning）时也保留 result 但 UI 停留输入页显示错误。简化：`_result` 非 null 即进预览；若 drafts 空且 warnings 全是错误 → 预览页顶部显示错误 + 无条目。为此把 `_parseError` 逻辑移到预览页顶部统一显示 warning；删除 `_buildInput` 里的 error 分支。测试 2 断言 `hook_import_invalid_json` 文本出现——预览页顶部 warning 行满足。实现以测试绿为准。

- [ ] **Step 4: Wire injection + list page + l10n**

`app_shell.dart`：字段 `late final HookImportParser hookImportParser;`、`late final HookImportService hookImportService;`，在 `hookRepository = ...` 之后构造（见 Interfaces）。`main.dart`：在 hookRepository 的 RepositoryProvider 旁补两个 provider（照抄现有注入模式，读 `main.dart` 中 `RepositoryProvider<HookRepository>` 的写法）。

`hook_management_page.dart`：头部按钮行（New hook 旁）加：
```dart
OutlinedButton.icon(
  key: const Key('hook-import'),
  onPressed: () async {
    final imported = await showHookImportDialog(context);
    if (imported == true && context.mounted) {
      AppToast.show(
        context,
        message: context.l10n.hookImportDoneToast,
        variant: TpToastVariant.success,
      );
    }
  },
  icon: const Icon(Icons.file_download_outlined),
  label: Text(l10n.hookImport),
),
```
（`AppToast` 在 `widgets/app_toast/app_toast.dart`；`import 'hook_import_dialog.dart';`）

l10n（`hookImport` 等，en/zh 成对；`hookImportDone(int n)` 用占位符函数——参照既有 `workspaceSkillsAssignedCount` 的 arb 写法 `"hookImportDone": "{count, plural, =1{Import {count} hook} other{Import {count} hooks}}"`，zh 用 `"导入 {count} 条"`）：
- `hookImport`: "Import" / "导入"
- `hookImportCli`: "CLI" / "CLI"
- `hookImportJson`: "Hook JSON" / "Hook JSON"
- `hookImportJsonHint`: "Paste settings.json hooks, hooks.json, or a hooks fragment…" / "粘贴 settings.json hooks、hooks.json 或 hooks 片段…"
- `hookImportParse`: "Parse" / "解析"
- `hookImportDone(count)`: en `"Import {count}"` / zh `"导入 {count} 条"`
- `hookImportDoneToast`: "Hooks imported" / "已导入 hooks"

然后 `cd client && flutter gen-l10n`。

- [ ] **Step 5: Run tests + analyzer**

Run: `cd client && flutter test test/pages/hooks/ -v && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 全绿 + 0 error。若 dialog 实现与测试断言有出入（如 parse 错误显示位置），以测试绿为准调整实现。

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/hooks/ client/lib/app/app_shell.dart client/lib/main.dart client/lib/l10n/ client/test/pages/hooks/
git commit -m "feat(hooks-import): import dialog with CLI select + JSON paste + preview"
```

---

### Task 10: 全量验证 + 文档

**Files:**
- Modify: `docs/cli-formats/hooks.md`（补「JSON 导入」一节）
- Test: 全量

- [ ] **Step 1: Full verification**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: 0 errors；全量失败仅限已知 pre-existing 基线（本分支 env 相关，见 Global Constraints）。若出现本功能相关失败，修复后重跑。

- [ ] **Step 2: Docs**

`docs/cli-formats/hooks.md` 新增「导入既有 CLI hooks」小节：支持 CLI（claude/flashskyai settings.json hooks、codex hooks.json、cursor hooks.json）、粘贴 JSON + CLI 选择、脚本复制进库与命令重写规则、占位符/不可读降级 raw、不支持字段旁路保留（`native`）、幂等 id、不在归一化目录的事件丢弃（`hook_import_event_unsupported_*`）。

- [ ] **Step 3: Commit**

```bash
git add docs/cli-formats/hooks.md
git commit -m "docs(hooks): JSON import section in CLI format reference"
```

---

## 收尾清单

- spec 每节有任务：§2.1/2.2 中间形态+方言 → Task 2/5/6；§2.2 事件映射 → Task 3；§2.3 脚本提取 → Task 4；§2.4 幂等 id → Task 7；§2.5 native 旁路 → Task 1；§2.6 服务 → Task 8；§3 UI → Task 9；§4 错误/测试 → 各任务内；§5 不在范围 → 无任务（符合预期）。
- 类型一致性：`HookImportDraft.definition.scriptFileName/scriptContent`、`hookImportId`、`HookImportParser.parseJson({cli, jsonText})`、`HookImportService.import(List<HookImportDraft>)`、`showHookImportDialog(context)` 在 Task 7-9 间一致。
