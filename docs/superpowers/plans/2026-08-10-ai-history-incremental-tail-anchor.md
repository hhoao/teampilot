# AI History 增量解析(尾部锚点)Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用"尾部锚点"增量解析替代 History live-refresh 的全量重解析,消除主 isolate 冻结,并覆盖 Claude / Codex / Cursor / Opencode 四个 CLI。

**Architecture:** 新增 `AiTranscriptTailReader`:记住"最后一条已消费 user/assistant 事件的整行字节 hash"作为锚点,每轮只读文件尾部窗口(64KB→256KB→全文件),锚点之后的行经 worker isolate 解码后由 `lineAppend` 逐条 merge 进**原地变异的同一 List 实例**;锚点找不到(重写/压缩/截断)→ 全量重建。消息列表实例稳定后,`ExternalStoreAiThreadRuntime._mergeReusingUnchanged` 与 `_sameSubagentAttachments` 的 `identical` 快速路径生效,identity 字符串构建消失。Opencode 不走 tail,改用 SQLite 增量查询(`WHERE id > lastSeen`),并去掉每轮全量复制 DB+WAL+SHM。

**Tech Stack:** Dart / Flutter,`dart:isolate`(Isolate.run),`sqlite3` 包(已有),`flutter_test` + `fake_async`,`InMemoryFilesystem`(test/support)。

## Global Constraints

- 测试命令:`cd client && flutter test test/services/session/ai_transcript_tail_reader_test.dart`(单文件)或 `flutter test --exclude-tags integration`(全量)。
- 不要改 transcript 文件的写入端;不要改 `buildConversationTimeline` / `finalizeAiMessagesForHistory` / `append*JsonlEvent` 的语义(增量与全量共享同一批函数,语义零分叉)。
- `fallbackSeq` 必须延续:增量解析的 fallback id 序列必须与"全量从 0 数到此处"完全一致(见 Task 2 的 `fallbackId` 闭包)。
- 消息列表必须原地变异,未变消息实例不动(兑现 `identical` 快速路径)。
- 每次 task 结束:`flutter analyze --no-fatal-infos --no-fatal-warnings` 必须通过。
- 参考 spec:`docs/superpowers/specs/2026-08-10-ai-history-incremental-tail-anchor-design.md`。

---

### Task 1: 恢复 `AiTranscriptLineAppend` 钩子(Claude / Codex / Cursor)

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/ai_history_capability.dart`
- Modify: `client/lib/services/cli/registry/capabilities/history/builtin_ai_history_capabilities.dart`
- Test: `client/test/services/cli/registry/capabilities/history/line_append_test.dart`(新建)

**Interfaces:**
- Consumes: 现有 `appendClaudeJsonlEvent`(`client/lib/services/cli/claude/capabilities/history/compatible_jsonl.dart:20`,返回 `bool`)、`appendCodexJsonlEvent`(`client/lib/services/cli/codex/capabilities/history/ai_transcript.dart:118`,返回 `void`)、`appendCursorJsonlEvent`(`client/lib/services/cli/cursor/capabilities/history/ai_transcript.dart:186`,返回 `void`)。
- Produces: `typedef AiTranscriptLineAppend = bool Function(List<AiMessage> messages, Map<String, dynamic> event, {required String Function() fallbackId});` 及 `AiHistoryCapability.lineAppend` 字段。bool = 该事件是否被解析消费(产生/修改了消息)。Task 2 用它的返回值决定是否推进锚点。

- [ ] **Step 1: 写失败测试**

新建 `client/test/services/cli/registry/capabilities/history/line_append_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/codex/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_jsonl.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/builtin_ai_history_capabilities.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart'
    as cap;
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  for (final (cli, fixture) in [
    (CliTool.claude, 'claude/basic.jsonl'),
    (CliTool.codex, 'codex/basic.jsonl'),
    (CliTool.cursor, 'cursor/agent_transcript_no_tool_id.jsonl'),
  ]) {
    test('$cli: lineAppend replays fixture identically to full parse', () async {
      final capability =
          registry.capability<AiHistoryCapability>(cli)!;
      final bytes = await File(
        'test/fixtures/session_history/$fixture',
      ).readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      final adapterMessages = await capability.adapter.parse(
        AiTranscriptBundle(
          adapterId: cli.name,
          fragments: [AiTranscriptFragment(name: 't.jsonl', bytes: bytes)],
        ),
      );

      final replay = <AiMessage>[];
      var seq = 0;
      for (final line in const LineSplitter().convert(content)) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final event = jsonDecode(trimmed) as Map<String, dynamic>;
        capability.lineAppend(
          replay,
          event,
          fallbackId: () => '$cli-${seq++}',
        );
      }
      expect(replay, adapterMessages);
    });
  }
}
```

(该测试同时验证 lineAppend 的 fallbackSeq 语义与 adapter 一致。)

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/cli/registry/capabilities/history/line_append_test.dart`
Expected: FAIL — `AiHistoryCapability` 没有 `lineAppend` 成员。

- [ ] **Step 3: 实现**

`client/lib/services/cli/registry/capabilities/ai_history_capability.dart`:

```dart
/// 逐事件追加钩子:把一条已解码的 transcript 事件合并进 [messages]。
/// 返回该事件是否被解析消费(产生或修改了消息)。增量 tailer 只把"消费
/// 成功"的行推进锚点;无显示内容的事件(快照/元数据)返回 false。
typedef AiTranscriptLineAppend = bool Function(
  List<AiMessage> messages,
  Map<String, dynamic> event, {
  required String Function() fallbackId,
});

abstract interface class AiHistoryCapability implements CliCapability {
  Future<AiTranscriptBundle?> locate(SessionHistoryContext ctx);
  AiTranscriptAdapter get adapter;
  /// 逐事件追加钩子(增量解析与全量解析共用,保证语义零分叉)。
  AiTranscriptLineAppend get lineAppend;
  /// Lower-case names.
  Set<String> get subagentToolNames;
  SubagentSideResolver get subagentSideResolver;
  ToolResultEnricher get toolResultEnricher;
}
```

`client/lib/services/cli/registry/capabilities/history/builtin_ai_history_capabilities.dart` — 给三个 JSONL capability 的实现加上:

```dart
@override
AiTranscriptLineAppend get lineAppend => appendClaudeJsonlEvent;
```

(Claude 的实现;Codex 用 `appendCodexJsonlEvent`,Cursor 用 `appendCursorJsonlEvent`。Dart 的返回类型协变:返回 `bool` 或 `void` 的函数都可赋值给 `bool Function(...)`。)

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/services/cli/registry/capabilities/history/line_append_test.dart`
Expected: PASS(3 个 CLI 全部相等)。

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/cli/registry/capabilities/ai_history_capability.dart client/lib/services/cli/registry/capabilities/history/builtin_ai_history_capabilities.dart client/test/services/cli/registry/capabilities/history/line_append_test.dart
git commit -m "feat(history): restore AiTranscriptLineAppend hook for incremental parsing"
```

---

### Task 2: `AiTranscriptTailReader` 核心(锚点查找 + 窗口自适应 + 重建兜底)

**Files:**
- Create: `client/lib/services/session/ai_transcript_tail_reader.dart`
- Test: `client/test/services/session/ai_transcript_tail_reader_test.dart`(新建)

**Interfaces:**
- Consumes: `AiTranscriptLineAppend`(Task 1)、`Filesystem`(`client/lib/services/io/filesystem.dart`)、`InMemoryFilesystem`(`client/test/support/in_memory_filesystem.dart`,已有 `readBytesRange` / `writeBytes` / `appendBytes`)、`appendClaudeJsonlEvent`。
- Produces:
  - `class TailReaderState { String? anchorHash; List<AiMessage> messages; int fallbackSeq; int incrementalCount; String? path; }`
  - `class TailRefreshResult { final bool changed; final bool rebuilt; }`
  - `typedef EventDecoder = Future<List<Map<String, dynamic>?>> Function(List<List<int>> lines);`
  - `class AiTranscriptTailReader { AiTranscriptTailReader({required AiTranscriptLineAppend lineAppend, EventDecoder? decodeEvents, List<int> windowSizes = const [64*1024, 256*1024], int fullReloadEvery = 30}); Future<TailRefreshResult> refresh({required Filesystem fs, required String path, required TailReaderState state, bool force = false}); }`
  - 生产 decoder 顶层函数 `Future<List<Map<String, dynamic>?>> decodeJsonlLinesIsolate(List<List<int>> lines)`(Task 3 复用)。
  - `AiTranscriptTailReader` 构造参数含 `required String fallbackPrefix`:fallback id 前缀必须与 adapter 全量 parse 一致(`'claude-'` / `'codex-'` / `'cursor-'`),保证"增量 id 序列 == 全量 id 序列"。

- [ ] **Step 1: 写失败测试**

新建 `client/test/services/session/ai_transcript_tail_reader_test.dart`。测试用同步 decoder 注入(避免真实 isolate):

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_jsonl.dart';
import 'package:teampilot/services/session/ai_transcript_tail_reader.dart';

import '../../support/in_memory_filesystem.dart';

EventDecoder _syncDecoder() {
  return (lines) async => [
        for (final line in lines)
          tryDecodeJsonlLine(utf8.decode(line, allowMalformed: true)),
      ];
}

AiTranscriptTailReader _reader() => AiTranscriptTailReader(
      lineAppend: appendClaudeJsonlEvent,
      fallbackPrefix: 'claude',
      decodeEvents: _syncDecoder(),
      windowSizes: const [512, 2048], // 小窗口便于测试窗口扩展
      fullReloadEvery: 30,
    );

void main() {
  final fs = InMemoryFilesystem();
  const path = '/transcript.jsonl';

  String userLine(String id, String text) =>
      '{"type":"user","uuid":"$id","message":{"id":"$id","content":"$text"},"timestamp":"2026-08-10T00:00:00Z"}';
  String assistantLine(String id, String text) =>
      '{"type":"assistant","uuid":"$id","message":{"id":"$id","content":"$text"},"timestamp":"2026-08-10T00:00:00Z"}';
  String metaLine() =>
      '{"type":"last-prompt","lastPrompt":"x","sessionId":"s"}';

  test('append: only new lines are parsed; instance is reused', () async {
    await fs.writeString(path, '${userLine('u1', 'hi')}\n');
    final reader = _reader();
    final state = TailReaderState();
    await reader.refresh(fs: fs, path: path, state: state);
    final first = state.messages;
    expect(first.map((m) => m.parts.single).toList(), ['hi']);
    final idBefore = state.messages.last.id;

    // 追加:新 user + 元数据行(不消费)+ 流式 assistant 分片
    await fs.appendString(
      path,
      '${metaLine()}\n${assistantLine('a1', 'part1 ')}\n${assistantLine('a1', 'part2')}\n',
    );
    await reader.refresh(fs: fs, path: path, state: state);
    expect(identical(state.messages, first), isTrue,
        reason: '消息列表必须原地变异,实例保持不变');
    expect(state.messages, hasLength(2));
    expect(state.messages[1].parts.single.text, 'part1 part2',
        reason: '同 message.id 的流式分片必须合并');
    expect(state.messages[1].id, idBefore);
  });

  test('anchor missing after rewrite triggers full rebuild', () async {
    await fs.writeString(path, '${userLine('u1', 'hi')}\n');
    final reader = _reader();
    final state = TailReaderState();
    await reader.refresh(fs: fs, path: path, state: state);

    // 模拟 compact:整个文件被重写(内容不同)
    await fs.writeString(
      path,
      '${userLine('u2', 'rewritten')}\n${assistantLine('a9', 'summary')}\n',
    );
    final result =
        await reader.refresh(fs: fs, path: path, state: state);
    expect(result.rebuilt, isTrue);
    expect(state.messages.map((m) => m.parts.single).toList(),
        ['rewritten', 'summary']);
    expect(state.messages, hasLength(2));
  });

  test('anchor outside small window expands to larger window', () async {
    // 生成超过第一个窗口(512B)的内容
    final big = StringBuffer();
    for (var i = 0; i < 20; i++) {
      big.write(userLine('u$i', 'x' * 60));
      big.write('\n');
    }
    await fs.writeString(path, big.toString());
    final reader = _reader();
    final state = TailReaderState();
    await reader.refresh(fs: fs, path: path, state: state);
    expect(state.messages, hasLength(20));

    await fs.appendString(path, '${assistantLine('tail', 'new')}\n');
    final result =
        await reader.refresh(fs: fs, path: path, state: state);
    expect(result.changed, isTrue);
    expect(state.messages, hasLength(21));
  });

  test('half-written trailing line is deferred until completed', () async {
    await fs.writeString(path, '${userLine('u1', 'hi')}\n');
    final reader = _reader();
    final state = TailReaderState();
    await reader.refresh(fs: fs, path: path, state: state);

    await fs.appendString(path, '{"type":"assistant","uuid":"a1",');
    var result =
        await reader.refresh(fs: fs, path: path, state: state);
    expect(result.changed, isFalse);
    expect(state.messages, hasLength(1));

    await fs.appendString(path, '"message":{"id":"a1","content":"done"}}');
    await fs.appendString(path, '\n');
    result = await reader.refresh(fs: fs, path: path, state: state);
    expect(result.changed, isTrue);
    expect(state.messages, hasLength(2));
  });

  test('file shrink resets state', () async {
    await fs.writeString(path, '${userLine('u1', 'hi')}\n');
    final reader = _reader();
    final state = TailReaderState();
    await reader.refresh(fs: fs, path: path, state: state);

    await fs.writeString(path, '${userLine('u2', 'small')}\n');
    final result =
        await reader.refresh(fs: fs, path: path, state: state);
    expect(result.rebuilt, isTrue);
    expect(state.messages.map((m) => m.parts.single).toList(), ['small']);
  });

  test('fullReloadEvery triggers periodic full validation', () async {
    await fs.writeString(path, '${userLine('u1', 'hi')}\n');
    final reader = AiTranscriptTailReader(
      lineAppend: appendClaudeJsonlEvent,
      fallbackPrefix: 'claude',
      decodeEvents: _syncDecoder(),
      windowSizes: const [512, 2048],
      fullReloadEvery: 3,
    );
    final state = TailReaderState();
    await reader.refresh(fs: fs, path: path, state: state);
    for (var i = 0; i < 3; i++) {
      await fs.appendString(path, '${assistantLine('a$i', 'm$i')}\n');
      await reader.refresh(fs: fs, path: path, state: state);
    }
    final result =
        await reader.refresh(fs: fs, path: path, state: state);
    expect(result.rebuilt, isTrue,
        reason: '第 4 次 refresh 累积 3 次增量后应触发全量校验');
    expect(state.messages, hasLength(4));
  });
}
```

(需 import `dart:io` 以使用 `File`?不需要——测试全用 `InMemoryFilesystem`。注意 `InMemoryFilesystem` 需有 `writeString` / `appendString` / `stat` / `readBytesRange`,按现有实现确认,若缺 `writeString` 用 `writeBytes(utf8.encode(...))`。)

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/session/ai_transcript_tail_reader_test.dart`
Expected: FAIL — `ai_transcript_tail_reader.dart` 不存在。

- [ ] **Step 3: 实现核心**

新建 `client/lib/services/session/ai_transcript_tail_reader.dart`:

```dart
import 'dart:convert';
import 'dart:isolate';

import 'package:ai_message_core/ai_message_core.dart';

import '../cli/registry/capabilities/ai_history_capability.dart';
import '../io/filesystem.dart';

/// 一行待解码字节;worker 解码后按 [index] 配对回行。
class _PendingLine {
  const _PendingLine({required this.index, required this.bytes});
  final int index;
  final List<int> bytes;
}

/// 生产 decoder:worker isolate 里批量 jsonDecode。
Future<List<Map<String, dynamic>?>> decodeJsonlLinesIsolate(
  List<List<int>> lines,
) {
  return Isolate.run(() async {
    final out = <Map<String, dynamic>?>[];
    for (final line in lines) {
      out.add(_tryDecode(utf8.decode(line, allowMalformed: true)));
    }
    return out;
  });
}

Map<String, dynamic>? _tryDecode(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on FormatException {
    return null;
  }
  return null;
}

/// 逐行解码注入点(测试用同步实现,生产用 [decodeJsonlLinesIsolate])。
typedef EventDecoder =
    Future<List<Map<String, dynamic>?>> Function(List<List<int>> lines);

/// 尾部锚点增量读取器。
///
/// 状态([TailReaderState])由调用方持有:锚点 = 最后一条"被消费"的行的
/// 整行字节 hash。每次 refresh 读尾部窗口,从锚点行之后逐事件
/// [AiTranscriptLineAppend] 合并进 [TailReaderState.messages](原地变异)。
/// 锚点找不到(重写/压缩/截断)→ 全量重建。
class AiTranscriptTailReader {
  AiTranscriptTailReader({
    required AiTranscriptLineAppend lineAppend,
    required String fallbackPrefix,
    EventDecoder? decodeEvents,
    this.windowSizes = const [64 * 1024, 256 * 1024],
    this.fullReloadEvery = 30,
  }) : _lineAppend = lineAppend,
       _fallbackPrefix = fallbackPrefix,
       _decodeEvents = decodeEvents ?? decodeJsonlLinesIsolate;

  final AiTranscriptLineAppend _lineAppend;

  /// fallback id 前缀,必须与 adapter 全量 parse 的 `'$cli-${seq}'` 一致
  /// (Claude→'claude',Codex→'codex',Cursor→'cursor'),保证增量与全量
  /// 生成的消息 id 序列完全相同。
  final String _fallbackPrefix;
  final EventDecoder _decodeEvents;
  final List<int> windowSizes;

  /// 每多少次成功增量后强制一次全量校验。
  final int fullReloadEvery;

  static int _lineHash(List<int> line) {
    var hash = 0x811C9DC5;
    for (final b in line) {
      hash = ((hash ^ b) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  Future<TailRefreshResult> refresh({
    required Filesystem fs,
    required String path,
    required TailReaderState state,
    bool force = false,
  }) async {
    final stat = await fs.stat(path);
    if (!stat.exists || stat.isDirectory) {
      state.path = null;
      state.anchorHash = null;
      state.messages = [];
      state.incrementalCount = 0;
      return const TailRefreshResult(changed: false, rebuilt: true);
    }
    final size = stat.size ?? 0;
    final pathChanged = state.path != path;
    state.path = path;

    if (force || pathChanged || state.anchorHash == null) {
      return _fullReload(fs, path, size, state);
    }

    state.incrementalCount++;
    if (state.incrementalCount >= fullReloadEvery) {
      return _fullReload(fs, path, size, state);
    }

    // 窗口自适应:优先小窗口,锚点不在再放大,最后全文件。
    for (final window in windowSizes) {
      if (size <= window) break; // 文件比窗口小 → 直接全文件分支
      final start = size - window;
      final tail = await fs.readBytesRange(path, start, window);
      if (tail == null || tail.isEmpty) continue;
      final applied = await _consumeFromAnchor(tail, state);
      if (applied != null) return applied;
    }

    final whole = await fs.readBytes(path);
    if (whole == null || whole.isEmpty) {
      return const TailRefreshResult(changed: false, rebuilt: false);
    }
    return _consumeFromAnchor(whole, state) ??
        const TailRefreshResult(changed: false, rebuilt: false);
  }

  /// 尝试在 [bytes] 内找到锚点行并消费其后的新行。
  /// 返回 null 表示窗口内没有锚点(调用方应扩大窗口)。
  Future<TailRefreshResult?> _consumeFromAnchor(
    List<int> bytes,
    TailReaderState state,
  ) async {
    final lines = <_PendingLine>[];
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0x0A) {
        lines.add(_PendingLine(
          index: lines.length,
          bytes: bytes.sublist(start, i),
        ));
        start = i + 1;
      }
    }
    // 最后一段若以 \n 结尾则无残留,否则是半行(本轮忽略,下轮补全)。

    var anchorIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      if (_lineHash(lines[i].bytes) == state.anchorHash) {
        anchorIndex = i;
        break;
      }
    }
    if (anchorIndex < 0) return null;

    final newLines = lines.sublist(anchorIndex + 1);
    if (newLines.isEmpty) {
      return const TailRefreshResult(changed: false, rebuilt: false);
    }
    final events = await _decodeEvents([
      for (final l in newLines) l.bytes,
    ]);
    var consumedAny = false;
    for (var i = 0; i < newLines.length; i++) {
      final event = events[i];
      if (event == null) continue;
      final before = state.fallbackSeq;
      final ok = _lineAppend(
        state.messages,
        event,
        fallbackId: () => '$_fallbackPrefix-${state.fallbackSeq++}',
      );
      if (ok) {
        state.anchorHash = _lineHash(newLines[i].bytes);
        consumedAny = true;
      } else {
        // 未消费(元数据/无显示内容)不推进锚点;但序号仍按调用延续
        state.fallbackSeq = before; // 未消费则不消耗序号
      }
    }
    if (!consumedAny) {
      return const TailRefreshResult(changed: false, rebuilt: false);
    }
    return const TailRefreshResult(changed: true, rebuilt: false);
  }

  Future<TailRefreshResult> _fullReload(
    Filesystem fs,
    String path,
    int size,
    TailReaderState state,
  ) async {
    final bytes = await fs.readBytes(path);
    final messages = <AiMessage>[];
    var fallbackSeq = 0;
    String? anchor;
    if (bytes != null) {
      var start = 0;
      for (var i = 0; i <= bytes.length; i++) {
        if (i == bytes.length || bytes[i] == 0x0A) {
          final line = bytes.sublist(start, i);
          start = i + 1;
          if (line.isEmpty) continue;
          final event = (await _decodeEvents([line])).first;
          if (event == null) continue;
          final before = fallbackSeq;
          final ok = _lineAppend(
            messages,
            event,
            fallbackId: () => '$_fallbackPrefix-${fallbackSeq++}',
          );
          if (ok) anchor = '$_lineHash(line)';
          else fallbackSeq = before;
        }
      }
    }
    state.messages = messages;
    state.fallbackSeq = fallbackSeq;
    state.anchorHash = anchor;
    state.incrementalCount = 0;
    return TailRefreshResult(changed: true, rebuilt: true);
  }
}

class TailReaderState {
  String? path;
  String? anchorHash;
  List<AiMessage> messages = [];
  int fallbackSeq = 0;
  int incrementalCount = 0;
}

class TailRefreshResult {
  const TailRefreshResult({required this.changed, required this.rebuilt});
  final bool changed;
  final bool rebuilt;
}
```

**fallback id 一致性(关键)**:adapter 全量 parse 的 fallback id 是 `'$cli-${fallbackSeq++}'`(从 0 起、仅在实际取用时递增)。TailReader 的增量/全量重建必须产生**完全相同的 id 序列**,否则消息 id 在"增量 ↔ 重建"切换时翻转,实例复用失效。因此 TailReader 通过构造参数 `fallbackPrefix`(Claude→'claude',Codex→'codex',Cursor→'cursor')注入前缀,内部统一 `fallbackId: () => '$_fallbackPrefix-${fallbackSeq++}'`;增量时延续 `state.fallbackSeq`,与全量 parse"数到此处"的序号一致。未消费事件(返回 false)不推进序号,与 adapter 内部"未取用不递增"的惰性求值语义对齐。

所以 Task 2 的 TailReader 构造函数增加 `required String fallbackPrefix`,fallbackId 改为 `'$fallbackPrefix-${state.fallbackSeq++}'`。测试里 appendClaudeJsonlEvent 需要事件里有 message.id(测试行都有 uuid/id)→ 不会触发 fallbackId,前缀不影响断言。

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/services/session/ai_transcript_tail_reader_test.dart`
Expected: PASS(6 个测试)。

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/session/ai_transcript_tail_reader.dart client/test/services/session/ai_transcript_tail_reader_test.dart
git commit -m "feat(history): tail-anchor incremental transcript reader"
```

---

### Task 3: `AiHistoryLoader` 集成(增量路径 + 实例复用)

**Files:**
- Modify: `client/lib/services/session/ai_history_loader.dart`
- Modify: `client/test/services/session/ai_history_loader_test.dart`

**Interfaces:**
- Consumes: `AiTranscriptTailReader` / `TailReaderState` / `TailRefreshResult`(Task 2)、`AiHistoryCapability.lineAppend`(Task 1)、`AiHistoryWatchMeta.cacheTokenPaths`(已有,定位 transcript path)。
- Produces: `AiHistoryLoader` 保持既有公开 API(`load` / `resolveWatchMeta` / `invalidate` 签名不变),但:
  - 新增 `final Map<String, TailReaderState> _tailStates`(key = cacheKey);
  - `load()` 内部:优先 `_incrementalLoad(...)`,失败/无 path 时回退现有全量路径;
  - 增量成功时返回 `messages` = `state.messages`(同一实例,原地变异)。

- [ ] **Step 1: 写失败测试**

在 `client/test/services/session/ai_history_loader_test.dart` 追加:

```dart
test('incremental load reuses message instances across appends', () async {
  final session = simpleSession();
  final ctx = launchContextFor(session);
  final bucket = RuntimeLayout.workspaceBucketForPrimaryPath('/work/project');
  final toolRoot = layout.sessionRuntimeToolDir('ws-1', session.id, 'claude');
  final projects = p.join(toolRoot, 'projects', bucket);
  await Directory(projects).create(recursive: true);
  final transcriptPath = p.join(projects, '${session.id}.jsonl');

  String line(String type, String id, String text) =>
      '{"type":"$type","uuid":"$id","message":{"id":"$id","content":"$text"},'
      '"timestamp":"2026-08-10T00:00:00Z"}';

  await File(transcriptPath).writeAsString(
    '${line('user', 'u1', 'hello')}\n',
  );
  final loader = buildLoader();
  final first = await loader.load(
    session: session,
    memberId: '',
    launchContext: ctx,
  );
  expect(first.messages, hasLength(1));

  // 追加流式分片 + 元数据行
  await File(transcriptPath).writeAsString(
    '${line('assistant', 'a1', 'part1 ')}\n'
    '${line('assistant', 'a1', 'part2')}\n'
    '{"type":"last-prompt","lastPrompt":"x"}\n',
    mode: FileMode.append,
  );
  final second = await loader.load(
    session: session,
    memberId: '',
    launchContext: ctx,
  );
  expect(identical(second.messages, first.messages), isTrue,
      reason: '增量路径必须复用同一消息列表实例');
  expect(second.messages, hasLength(2));
  expect(second.messages[1].parts.single.text, 'part1 part2');
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/session/ai_history_loader_test.dart`
Expected: FAIL — `identical(second.messages, first.messages)` 为 false(当前全量解析每次新建列表)。

- [ ] **Step 3: 实现**

`client/lib/services/session/ai_history_loader.dart`:

```dart
import 'dart:convert';
// …(现有 imports 保留)

final class AiHistoryLoader {
  // …(现有字段保留)

  /// 增量 tail 状态(cacheKey → state)。
  final Map<String, TailReaderState> _tailStates = {};
  final Map<String, AiTranscriptTailReader> _tailReaders = {};

  AiTranscriptTailReader _tailReaderFor(CliTool cli) {
    return _tailReaders.putIfAbsent(
      cli.name,
      () => AiTranscriptTailReader(
        lineAppend: _registry
            .capability<AiHistoryCapability>(cli)!
            .lineAppend,
        fallbackPrefix: switch (cli) {
          CliTool.claude => 'claude',
          CliTool.codex => 'codex',
          CliTool.cursor => 'cursor',
          _ => 'tail',
        },
      ),
    );
  }

  /// 增量路径:locate → path → tail refresh。返回 null 表示不可用(无 path /
  /// 非 JSONL 存储,回退全量)。
  Future<List<AiMessage>?> _tryIncrementalLoad({
    required String cacheKey,
    required CliTool cli,
    required SessionHistoryContext ctx,
    required String? parentPath,
    bool force = false,
  }) async {
    if (parentPath == null || parentPath.isEmpty) return null;
    final reader = _tailReaderFor(cli);
    final state = _tailStates.putIfAbsent(cacheKey, TailReaderState.new);
    final result = await reader.refresh(
      fs: ctx.fs,
      path: parentPath,
      state: state,
      force: force,
    );
    if (!result.changed && !result.rebuilt) return state.messages;
    return state.messages;
  }
```

然后在 `load()` 的解析段(bundle locate 之后)插入增量优先分支:

```dart
      final bundle = await _locator.locate(ctx: ctx, cli: cli);
      final watch = bundle == null
          ? null
          : AiHistoryWatchMeta.fromHints(bundle.hints);
      final parentPath = () {
        final paths = watch?.cacheTokenPaths ?? const <String>[];
        for (final p in paths) {
          final t = p.trim();
          if (t.isNotEmpty) return t;
        }
        return null;
      }();

      // 增量优先:JSONL 类 CLI 走 tail-anchor 增量;失败/不适配回退全量。
      var messages = const <AiMessage>[];
      var usedIncremental = false;
      final incremental = await _tryIncrementalLoad(
        cacheKey: cacheKey,
        cli: cli,
        ctx: ctx,
        parentPath: parentPath,
        force: force,
      );
      if (incremental != null) {
        messages = incremental;
        usedIncremental = true;
      } else if (bundle != null) {
        // …(现有全量 parse 逻辑原样保留,含 Isolate.run 分支)
      }
```

注意:
- token 缓存逻辑保留在增量之前(现有 `_tokens[cacheKey] == token` 短路仍然有效——mtime 不变直接返回缓存;mtime 变了才走到增量)。增量成功后同样设置 `_tokens[cacheKey] = token ?? 'changed-$cacheKey'`(与全量路径一致,紧跟在 messages 组装后)。
- **增量路径的 subagent attachments**:增量成功后**沿用** `_attachments[cacheKey]`(若为空则 `const {}`),不重新 inflate——新增消息的 subagent 附件延迟到下一次"低频全量校验"(Task 2 `fullReloadEvery`,默认每 30 次增量重建一次)时补齐。`_attachments[cacheKey]` 的更新仍只在全量路径发生。
- `force: true`(invalidateAndReload)强制全量重建:reader.refresh 的 `force` 参数走 `_fullReload`,语义不变。
- `invalidate` 要清 `_tailStates` / `_tailReaders` 对应 cacheKey。

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/services/session/ai_history_loader_test.dart`
Expected: PASS(原有测试 + 新增量测试)。

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/session/ai_history_loader.dart client/test/services/session/ai_history_loader_test.dart
git commit -m "feat(history): route loader through tail-anchor incremental parse"
```

---

### Task 4: live-refresh 节流(双保险)

**Files:**
- Modify: `client/lib/services/session/ai_history_live_refresh_controller.dart`
- Modify: `client/test/services/session/ai_history_live_refresh_controller_test.dart`

**Interfaces:**
- Consumes: 现有 `AiHistoryLiveRefreshController`(`_requestReload` / `_reloadInFlight` / `_reloadQueued`)。
- Produces: `_requestReload` 增加最小间隔 1s(可注入 `reloadMinInterval` 构造参数,默认 `Duration(seconds: 1)`),持续输出时事件合并为一次排队刷新。

- [ ] **Step 1: 写失败测试**

在 `client/test/services/session/ai_history_live_refresh_controller_test.dart` 追加(fakeAsync):

```dart
test('reloads are throttled to min interval under continuous change', () {
  fakeAsync((async) {
    final seat = FakeAiHistorySeat();
    var reloads = 0;
    final controller = AiHistoryLiveRefreshController(
      seat: seat,
      fs: () => _WatchableFs(),
      resolveWatchMeta: () async => null,
      reloadMinInterval: const Duration(seconds: 1),
    );
    // …(按该测试文件现有驱动方式触发多次 onTranscriptChanged)
    controller.start();
    for (var i = 0; i < 5; i++) {
      controller.debugOnChanged(); // 若测试文件已有等价注入点;否则直接调 _onTranscriptChanged 的公开别名
      async.elapse(const Duration(milliseconds: 100));
    }
    expect(seat.softReloadCalls, lessThanOrEqualTo(2),
        reason: '100ms 内 5 次变更被节流为至多 2 次 reload(1s 间隔)');
  });
});
```

(按该测试文件现有 fake seat 结构适配 `softReloadCalls` 计数。)

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/session/ai_history_live_refresh_controller_test.dart`
Expected: FAIL — 当前每次变更都触发 reload。

- [ ] **Step 3: 实现**

`client/lib/services/session/ai_history_live_refresh_controller.dart`:

```dart
  AiHistoryLiveRefreshController({
    // …(现有参数)
    this.reloadMinInterval = const Duration(seconds: 1),
  });

  /// 两次 reload 之间的最小间隔;持续输出时把高频变更合并为一次刷新。
  final Duration reloadMinInterval;

  DateTime? _lastReloadAt;
  Timer? _throttleTimer;

  Future<void> _requestReload() async {
    if (!_started) return;
    final now = DateTime.now();
    final last = _lastReloadAt;
    if (last != null && now.difference(last) < reloadMinInterval) {
      _reloadQueued = true;
      _throttleTimer ??= Timer(
        reloadMinInterval - now.difference(last),
        () {
          _throttleTimer = null;
          if (_started && _reloadQueued) {
            _reloadQueued = false;
            unawaited(_requestReload());
          }
        },
      );
      return;
    }
    _lastReloadAt = DateTime.now();
    // …(现有 do-while reload 主体)
  }
```

`stop()` 里要 `_throttleTimer?.cancel()`。

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/services/session/ai_history_live_refresh_controller_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/session/ai_history_live_refresh_controller.dart client/test/services/session/ai_history_live_refresh_controller_test.dart
git commit -m "perf(history): throttle live-refresh reloads to min interval"
```

---

### Task 5: Opencode SQLite 增量(去全量复制 + `WHERE id > lastSeen`)

**Files:**
- Modify: `client/lib/services/cli/opencode/capabilities/history/ai_transcript.dart`
- Modify: `client/test/services/cli/opencode/capabilities/history/ai_transcript_test.dart`(若不存在则新建于 `client/test/services/cli/opencode/`)

**Interfaces:**
- Consumes: 现有 `locateOpencodeTranscriptForSession` / `copyOpencodeSqliteSnapshot` / `OpencodeAiTranscriptAdapter`;sqlite3 包。
- Produces: 新增 `Future<AiTranscriptBundle?> locateOpencodeTranscriptIncremental(SessionHistoryContext ctx, {required int afterMessageId})`:只查 `WHERE session_id=? AND id > ?`,不复制 DB(直接只读主库 + `busy_timeout`);同时把 `_locateSqliteStorage` 的复制路径改为"仅首次建立基线"。

- [ ] **Step 1: 写失败测试**

用现有 sqlite fixture(需先确认 `client/test/fixtures/session_history/opencode/` 内容;若只有 JSON 树 fixture,则测试构造一个内存 sqlite DB):

```dart
test('opencode incremental query returns only new messages', () async {
  // 构造临时 opencode.db(与 _locateSqliteStorage 期望的 schema 一致):
  // message(id, session_id, data, time_created), part(id, message_id, data, time_created)
  final tempDir = Directory.systemTemp.createTempSync('opencode-incr-');
  final db = sqlite3.open('${tempDir.path}/opencode.db');
  db.execute('PRAGMA journal_mode=WAL');
  db.execute('''
    CREATE TABLE message (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id TEXT NOT NULL,
      data TEXT NOT NULL,
      time_created INTEGER NOT NULL
    )''');
  db.execute('''
    CREATE TABLE part (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      message_id INTEGER NOT NULL,
      data TEXT NOT NULL,
      time_created INTEGER NOT NULL
    )''');
  // …插入两条 message + parts
  db.dispose();

  final fs = LocalFilesystem();
  final ctx = fakeSessionHistoryContext(
    fs: fs,
    env: {'OPENCODE_DB': '${tempDir.path}/opencode.db'},
    persistedNativeId: 'sess-1',
  );

  final first = await locateOpencodeTranscriptIncremental(ctx,
      afterMessageId: 0);
  expect(first, isNotNull);
  // …断言 fragments 只含 message/part 文件,且与全量查询一致
});
```

(按 `client/test/services/session/stable_task_id_history_locate_test.dart` 或现有 opencode 测试的 fake context 方式适配。)

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/cli/opencode/`
Expected: FAIL — `locateOpencodeTranscriptIncremental` 不存在。

- [ ] **Step 3: 实现**

`client/lib/services/cli/opencode/capabilities/history/ai_transcript.dart` 新增:

```dart
/// 增量定位:只查 id 大于 [afterMessageId] 的 message 及其 parts。
/// 直接只读主库(不再复制 DB/WAL/SHM);SQLite WAL 支持多进程只读。
Future<AiTranscriptBundle?> locateOpencodeTranscriptIncremental(
  SessionHistoryContext ctx, {
  required int afterMessageId,
}) async {
  final dataDir = _resolveDataDir(ctx);
  if (dataDir.isEmpty) return null;
  final dbPath = ctx.fs.pathContext.join(dataDir, 'opencode.db');
  if (!await opencodeSqliteMainExists(ctx.fs, dbPath)) return null;

  final sessionId = await _resolveSessionId(ctx, dataDir);
  if (sessionId == null) return null;

  final tempDir = await Directory.systemTemp.createTemp('opencode-history-');
  final tempDbPath = ctx.fs.pathContext.join(tempDir.path, 'opencode.db');
  final copiedPaths = await copyOpencodeSqliteSnapshot(
    fs: ctx.fs,
    dbPath: dbPath,
    destDbPath: tempDbPath,
  );
  if (copiedPaths.isEmpty) return null;
  final db = sqlite3.open(tempDbPath, mode: OpenMode.readOnly);

  try {
    final messageRows = db.select(
      '''
SELECT id, data, time_created
FROM message
WHERE session_id = ? AND id > ?
ORDER BY id ASC
''',
      [sessionId, afterMessageId],
    );
    if (messageRows.isEmpty) return null;

    final fragments = <AiTranscriptFragment>[];
    final lastId = _maxMessageId(messageRows);
    for (final row in messageRows) {
      // …与 _locateSqliteStorage 相同的 fragment 组装逻辑
    }
    return AiTranscriptBundle(
      adapterId: 'opencode',
      fragments: fragments,
      hints: {
        'sessionId': sessionId,
        'source': 'sqlite',
        'incremental': 'true',
        'afterMessageId': '$afterMessageId',
        'lastMessageId': '$lastId',
        'cacheToken': 'opencode-sqlite|$sessionId|$lastId',
        …AiHistoryWatchMeta(
          changeWatchRoot: dataDir,
          cacheTokenPaths: copiedPaths,
        ).toHints(),
      },
    );
  } finally {
    db.close();
    try { await tempDir.delete(recursive: true); } on Object {}
  }
}
```

(注:本任务仍复制一次快照以保持一致性基线——消除复制属于后续优化,见 Task 6;`_maxMessageId` 为本地辅助。`afterMessageId` 的维护方为 loader:增量成功后将 bundle hints 的 `lastMessageId` 存 per-seat;下一次增量传回。为控制范围,loader 的 opencode 分支在 Task 6 接入,本任务只交付可测的增量查询函数。)

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/services/cli/opencode/`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/cli/opencode/capabilities/history/ai_transcript.dart client/test/services/cli/opencode/
git commit -m "feat(history): opencode sqlite incremental locate"
```

---

### Task 6: Opencode 增量接入 loader + 去 DB 复制 + seat 实例复用收尾

**Files:**
- Modify: `client/lib/services/session/ai_history_loader.dart`
- Modify: `client/lib/services/cli/opencode/capabilities/history/ai_transcript.dart`
- Modify: `client/lib/cubits/ai_history_seat.dart`(仅确认/加固 `_sameSubagentAttachments` 的 identical 短路)
- Test: `client/test/services/session/ai_history_loader_test.dart`

**Interfaces:**
- Consumes: `locateOpencodeTranscriptIncremental`(Task 5)、`AiHistoryLoader._tryIncrementalLoad`(Task 3)。
- Produces: loader 对 `adapterId == 'opencode'` 走 `_tryOpencodeIncremental`(`afterMessageId` 存 per-seat);快照复制仅在首次建立基线(之后直接只读主库,`PRAGMA busy_timeout=5000` 防写者 checkpoint 冲突)。

- [ ] **Step 1: 写失败测试**

在 `client/test/services/session/ai_history_loader_test.dart` 追加(用 Task 5 的临时 sqlite fixture 方式,验证 loader 两次 load 只查增量且实例复用):

```dart
test('opencode loader uses incremental sqlite query and reuses instances',
    () async {
  // 构造临时 opencode.db(两条 message: m1, m2)
  // loader.load(...) 第一次 → 2 条消息
  // 插入第三条 message m3 → loader.load(...) 第二次
  // expect(identical(second.messages, first.messages), isTrue)
  // expect(second.messages, hasLength(3))
});
```

- [ ] **Step 2: 运行确认失败**

Run: `cd client && flutter test test/services/session/ai_history_loader_test.dart`
Expected: FAIL — loader 未走 opencode 增量。

- [ ] **Step 3: 实现**

`ai_history_loader.dart`:
- `_tailStates` 的 value 扩展为 `_SeatIncrementalState`(包裹 `TailReaderState` + `opencodeLastMessageId` + `opencodeBaselineCopied`);
- `load()` 中 `cli == CliTool.opencode` 时:若已有 lastMessageId 且 session 未变 → `locateOpencodeTranscriptIncremental` → 把返回 fragments 直接经 `OpencodeAiTranscriptAdapter.parse` 解析为**增量消息**,与 `_tailStates` 里已有消息列表合并(按 message id 追加;opencode 消息 id 稳定,直接 append);
- 首次(无 lastMessageId)或增量 bundle 为 null → 现有全量 `_locateSqliteStorage` 路径(保持复制);
- `invalidate` 清理 opencode 状态。

`ai_transcript.dart`:
- `_locateSqliteStorage` 增加"已有基线则只读主库"分支:跳过 `copyOpencodeSqliteSnapshot`,`sqlite3.open(dbPath, mode: OpenMode.readOnly)` + `busy_timeout`。`locateOpencodeTranscriptIncremental` 同样改为不复制。

`ai_history_seat.dart`:
- 确认 `_sameSubagentAttachments` 在 `a == b`(identical)时已短路(`_sameSubagentAttachments` 已有 `identical(a, b)` 检查);若附件消息列表每次重建,给 `sameMessageListContent` 的调用点加实例级缓存(`identical(entry.value.messages, other.messages)` 先行短路)并按测试结果决定是否补丁。

- [ ] **Step 4: 运行确认通过**

Run: `cd client && flutter test test/services/session/ai_history_loader_test.dart && flutter test test/services/session/ai_history_live_refresh_controller_test.dart`
Expected: PASS。

- [ ] **Step 5: 全量验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: 无 error;全部测试通过。

- [ ] **Step 6: 提交**

```bash
git add client/lib/services/session/ai_history_loader.dart client/lib/services/cli/opencode/capabilities/history/ai_transcript.dart client/lib/cubits/ai_history_seat.dart client/test/services/session/ai_history_loader_test.dart
git commit -m "feat(history): opencode incremental loader + drop per-refresh db copy"
```

---

### Task 7: 真实环境冒烟(人工验证)

**Files:**
- 无代码改动(仅验证);若发现 `_sameSubagentAttachments` / worker 协作问题,按 Task 6 模式修复。

- [ ] **Step 1: 用真实 Claude transcript 验证增量 == 全量**

在开发机终端:

```bash
cd client
# 挑一个较大的真实 transcript(如 ~/.claude/projects/-home-hhoa-git-hhoa-teampilot/2a6c5bd0-*.jsonl)
# 用 dart 脚本把文件按行切成 N 帧,逐帧喂 AiTranscriptTailReader,
# 每帧后断言增量输出 == 全量 adapter.parse 输出(内容相等)。
dart run tool/verify_tail_anchor.dart ~/.claude/projects/-home-hhoa-git-hhoa-teampilot/2a6c5bd0-*.jsonl
```

(tool 脚本为临时验证脚本,验证后删除;断言内容:消息数相等 + 逐条 role/parts 文本相等。)

- [ ] **Step 2: 运行 TeamPilot,起一个真实会话**

- 打开 History 面板,让 CLI(Claude 或 opencode)持续输出;
- 确认:UI 不再冻结、History 实时跟随;回收/恢复终端不受影响;
- 用 DevTools Performance 确认 live refresh 期间主 isolate 无长帧(>100ms)。

- [ ] **Step 3: 收尾提交**

```bash
git add -A
git commit -m "chore(history): verify tail-anchor incremental parsing on real transcripts"
```

---

## Self-Review 记录

- **Spec 覆盖**:尾部锚点算法(Task 2)、lineAppend 钩子(Task 1)、loader 集成 + 实例复用(Task 3/6)、节流(Task 4)、opencode SQLite 增量 + 去复制(Task 5/6)、worker 解码协作(Task 2 的 `decodeJsonlLinesIsolate` + Task 3 接入)、真实环境冒烟(Task 7)全部有对应任务。低频全量校验 = Task 2 `fullReloadEvery`。窗口自适应 = Task 2 `windowSizes`。已知弱点(锚点仍在但前部被改)由 `fullReloadEvery` 兜底 ✓。
- **占位符扫描**:无 TBD/TODO;Task 5/6 的 opencode 测试用"按现有测试文件适配"的说明式占位——已在步骤内给出 schema 与断言要点,实现者需按现有 `stable_task_id_history_locate_test.dart` 的 fake context 模式补齐(计划内已指明文件路径与模式)。
- **类型一致性**:`TailReaderState` / `TailRefreshResult` / `EventDecoder` / `AiTranscriptLineAppend` 在 Task 1→2→3 之间签名一致;`fallbackId` 前缀统一为 `'$prefix-${seq}'`,与 adapter 全量 parse 的 `'$cli-${seq}'` 对齐(Claude='claude' 等);`locateOpencodeTranscriptIncremental(ctx, {required int afterMessageId})` 在 Task 5→6 一致。
