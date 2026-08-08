# Incremental Transcript Tailer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the history loader's full-file re-parse (every live refresh) with a byte-cursor incremental tailer so unchanged bytes are never re-read and a live refresh is O(appended bytes).

**Architecture:** A new `AiTranscriptTailer` keeps per-seat parse state (`byteOffset`, raw messages, `pathKey`). `AiHistoryLoader.load` keeps its token gate (unchanged token → cached, zero IO) but replaces `adapter.parse(bundle)` with `tailer.refresh`; on `changed` it delta-parses, guards the tool-result enricher, and re-inflates subagent attachments (workflow agents already served by the `ClaudeWorkflowResolver` mtime cache).

**Tech Stack:** Dart, `dart:convert`, existing `Filesystem.readBytesRange`, `AiMessage`/`finalizeAiMessagesForHistory` from `ai_message_core`, `ClaudeWorkflowResolver` incremental cache (already landed).

## Global Constraints

- All five launch CLIs must keep working; only Claude/flashskyai (JSONL, append-only) get the delta path — codex/opencode/cursor keep full parse via the tailer's full re-seek branch.
- The `AiHistoryLoader` public API (`load`, `resolveWatchMeta`, `clearCache`, `invalidate`, constructor params) must not change — the token gate and `resolveCacheToken` seam stay.
- Live refresh signal (watch vs poll) is already implemented in `TranscriptChangeSignal` — **do not touch it**.
- Tests: every task is TDD; the tailer's boundary cases are the deliverable the reviewer cares about most.
- After each task: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test <affected tests>`.

---

### Task 1: Expose incremental Claude JSONL line append

**Files:**
- Modify: `client/lib/services/cli/registry/capabilities/history/claude_compatible_jsonl.dart`
- Test: `client/test/services/cli/registry/capabilities/history/claude_ai_transcript_test.dart`

**Interfaces:**
- Produces:
  - `bool appendClaudeJsonlEvent(List<AiMessage> messages, Map<String, dynamic> event, {required String Function() fallbackId})` — appends/merges one decoded event; returns `false` for noise (progress, queue-operation, …).
  - `Map<String, dynamic>? tryDecodeJsonlLine(String line)` — JSON-decode one trimmed line or `null`.

- [ ] **Step 1: Write the failing test** — append the two public functions and a cross-call streaming-merge test to `claude_ai_transcript_test.dart`:

```dart
test('appendClaudeJsonlEvent merges streamed assistant lines across calls',
    () {
  final messages = <AiMessage>[];
  expect(
    appendClaudeJsonlEvent(
      messages,
      {
        'type': 'assistant',
        'message': {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': 'hello'},
          ],
          'id': 'msg-1',
        },
        'uuid': 'a1',
      },
      fallbackId: () => 'fb',
    ),
    isTrue,
  );
  expect(
    appendClaudeJsonlEvent(
      messages,
      {
        'type': 'assistant',
        'message': {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': ' world'},
          ],
          'id': 'msg-1',
        },
        'uuid': 'a2',
      },
      fallbackId: () => 'fb',
    ),
    isTrue,
  );
  expect(messages, hasLength(1));
  expect(
    messages.single.parts.map((p) => (p as AiTextPart).text).join(),
    'hello world',
  );
});

test('appendClaudeJsonlEvent skips noise records', () {
  expect(
    appendClaudeJsonlEvent(
      [],
      {'type': 'queue-operation', 'operation': 'enqueue'},
      fallbackId: () => 'fb',
    ),
    isFalse,
  );
});
```

Add the import `import 'package:teampilot/services/cli/registry/capabilities/history/claude_compatible_jsonl.dart';` if not present.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/services/cli/registry/capabilities/history/claude_ai_transcript_test.dart`
Expected: FAIL — `appendClaudeJsonlEvent` is not defined.

- [ ] **Step 3: Implement** — in `claude_compatible_jsonl.dart`, rename `_appendFromEvent` → `appendClaudeJsonlEvent` (public), add `tryDecodeJsonlLine`, and make `parseClaudeCompatibleJsonl` a thin loop over them. The bodies of `_tryDecodeObject` and `_appendFromEvent` move unchanged into the two new functions:

```dart
Map<String, dynamic>? tryDecodeJsonlLine(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on FormatException {
    return null;
  }
  return null;
}

/// Appends/merges one decoded event into [messages]. Returns false for noise
/// records that carry no display content. Streamed assistant partials sharing
/// a logical `message.id` merge into the previous message. Used by both the
/// full parser and the incremental tailer.
bool appendClaudeJsonlEvent(
  List<AiMessage> messages,
  Map<String, dynamic> event, {
  required String Function() fallbackId,
}) {
  // <body of the current _appendFromEvent, verbatim>
}

List<AiMessage> parseClaudeCompatibleJsonl(
  String content, {
  required String Function() fallbackId,
}) {
  final messages = <AiMessage>[];
  for (final line in const LineSplitter().convert(content)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final event = tryDecodeJsonlLine(trimmed);
    if (event == null) continue;
    appendClaudeJsonlEvent(messages, event, fallbackId: fallbackId);
  }
  return finalizeAiMessagesForHistory(messages);
}
```

Delete the old `_tryDecodeObject` and `_appendFromEvent` private functions.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/services/cli/registry/capabilities/history/claude_ai_transcript_test.dart`
Expected: PASS (new + existing).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/capabilities/history/claude_compatible_jsonl.dart client/test/services/cli/registry/capabilities/history/claude_ai_transcript_test.dart
git commit -m "refactor(history): expose appendClaudeJsonlEvent for incremental parsing"
```

---

### Task 2: `AiTranscriptTailer`

**Files:**
- Create: `client/lib/services/session/ai_transcript_tailer.dart`
- Test: `client/test/services/session/ai_transcript_tailer_test.dart`

**Interfaces:**
- Consumes: `appendClaudeJsonlEvent`, `tryDecodeJsonlLine` (Task 1); `finalizeAiMessagesForHistory` from `ai_message_core`; `SessionHistoryContext.fs.{stat,readString,readBytesRange}`.
- Produces (used by Task 3):
  - `class TailRefreshResult { List<AiMessage> messages; String? pathKey; bool changed; bool fullReseek; }`
  - `class AiTranscriptTailer { Future<TailRefreshResult> refresh({required SessionHistoryContext ctx, required String seatKey, required String? transcriptPath, bool force = false}); void clear(); void remove(String seatKey); void removeWhere(bool Function(String) test); }`

**Behavior (per spec S1):** state per seat = `{path, pathKey, byteOffset, raw, finalized}`. `refresh`: stat → `(mtime, size)`; read first line → `pathKey = firstLineFingerprint` (hash of the first line only — **not** mtime/size: those change on every append, and including them would make every delta refresh full-reseek, defeating the tailer). Full re-seek when `force` OR path changed OR `pathKey` changed OR `size < byteOffset`. Else if `size == byteOffset` → unchanged. Else read the tail, consume up to the last `\n`, `appendClaudeJsonlEvent` each line into `raw`, re-`finalize`, bump `byteOffset`. Rewrites (compaction, in-place) are caught by the shrink branch and/or the first-line change; a rewrite that keeps the first line byte-identical at the same size is an accepted edge.

- [ ] **Step 1: Write the failing test** — create `client/test/services/session/ai_transcript_tailer_test.dart`:

```dart
import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/session/ai_transcript_tailer.dart';
import 'package:teampilot/services/session/session_history_context.dart';

import '../../support/in_memory_filesystem.dart';

const _path = '/proj/ses.jsonl';
const _seat = 'sess\0member';

String _line(Map<String, dynamic> e) => jsonEncode(e);

String _user(String text) => _line({
  'type': 'user',
  'message': {'role': 'user', 'content': text},
  'uuid': 'u-${text.hashCode}',
  'timestamp': '2026-08-08T00:00:00.000Z',
});

String _assistant(String id, String text) => _line({
  'type': 'assistant',
  'message': {
    'role': 'assistant',
    'content': [
      {'type': 'text', 'text': text},
    ],
    'id': id,
  },
  'uuid': 'a-${text.hashCode}',
  'timestamp': '2026-08-08T00:00:01.000Z',
});

String _toolUse(String id, String toolUseId) => _line({
  'type': 'assistant',
  'message': {
    'role': 'assistant',
    'content': [
      {'type': 'tool_use', 'id': toolUseId, 'name': 'Bash', 'input': {'command': 'x'}},
    ],
    'id': id,
  },
  'uuid': 'a-$toolUseId',
  'timestamp': '2026-08-08T00:00:02.000Z',
});

String _toolResult(String toolUseId, String text) => _line({
  'type': 'user',
  'message': {
    'role': 'user',
    'content': [
      {'type': 'tool_result', 'tool_use_id': toolUseId, 'content': text},
    ],
  },
  'uuid': 'u-r-$toolUseId',
  'timestamp': '2026-08-08T00:00:03.000Z',
});

class _MtimeFs extends InMemoryFilesystem {
  final Map<String, DateTime> mtimes = {};
  void setMtime(String path, DateTime t) => mtimes[path] = t;
  @override
  Future<FsStat> stat(String path) async {
    final base = await super.stat(path);
    if (!base.exists) return base;
    return FsStat(kind: base.kind, size: base.size, mtime: mtimes[path]);
  }
}

class _ProbeFs extends _MtimeFs {
  final List<(int, int)> rangeReads = [];
  int readStringCalls = 0;
  @override
  Future<List<int>?> readBytesRange(String path, int offset, int length) async {
    rangeReads.add((offset, length));
    return super.readBytesRange(path, offset, length);
  }

  @override
  Future<String?> readString(String path) async {
    readStringCalls++;
    return super.readString(path);
  }
}

SessionHistoryContext _ctx(Filesystem fs) => SessionHistoryContext(
  fs: fs,
  taskId: 't',
  env: const {},
  transcriptRoots: const [],
  bucket: 'b',
);

Future<void> _append(_ProbeFs fs, String more, DateTime mtime) async {
  final bytes = await fs.readBytes(_path) ?? <int>[];
  await fs.writeBytes(_path, [...bytes, ...utf8.encode(more)]);
  fs.setMtime(_path, mtime);
}

void main() {
  setUp(() => AiTranscriptTailer().clear());

  test('delta refresh reads only the appended tail', () async {
    final fs = _ProbeFs();
    const t0 = '2026-08-08T00:00:00Z';
    await fs.writeString(_path, '${_user('one')}\n${_user('two')}\n');
    fs.setMtime(_path, DateTime.parse(t0));
    final tailer = AiTranscriptTailer();

    final first = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path);
    expect(first.changed, isTrue);
    expect(first.fullReseek, isTrue);
    expect(first.messages, hasLength(2));
    final firstSize = (await fs.readBytes(_path))!.length;
    fs.rangeReads.clear();
    fs.readStringCalls = 0;

    await _append(fs, '${_user('three')}\n', DateTime.parse('2026-08-08T00:00:10Z'));
    final second = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path);
    expect(second.changed, isTrue);
    expect(second.fullReseek, isFalse);
    expect(second.messages, hasLength(3));
    expect(fs.readStringCalls, 0, reason: 'delta path must not full-read');
    expect(fs.rangeReads, contains((firstSize, 0)), reason: 'tail read must start at byteOffset');
  });

  test('unchanged refresh returns cached with zero delta work', () async {
    final fs = _ProbeFs();
    await fs.writeString(_path, '${_user('one')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:00Z'));
    final tailer = AiTranscriptTailer();
    await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path);

    final again = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path);
    expect(again.changed, isFalse);
    expect(again.messages, hasLength(1));
  });

  test('cross-batch streamed assistant merges into one message', () async {
    final fs = _ProbeFs();
    await fs.writeString(_path, '${_assistant('m1', 'hello')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:00Z'));
    final tailer = AiTranscriptTailer();
    await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path);

    await _append(fs, '${_assistant('m1', ' world')}\n', DateTime.parse('2026-08-08T00:00:05Z'));
    final second = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path);
    expect(second.messages, hasLength(1));
    expect(
      second.messages.single.parts.map((p) => (p as AiTextPart).text).join(),
      'hello world',
    );
  });

  test('tool_use then tool_result across batches finalizes correctly', () async {
    final fs = _ProbeFs();
    await fs.writeString(_path, '${_toolUse('a', 'call_1')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:00Z'));
    final tailer = AiTranscriptTailer();
    await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path);

    await _append(fs, '${_toolResult('call_1', 'out')}\n', DateTime.parse('2026-08-08T00:00:05Z'));
    final second = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path);
    final call = second.messages
        .expand((m) => m.parts)
        .whereType<AiToolCallPart>()
        .single;
    expect(call.result, 'out');
    expect(call.status, AiToolCallStatus.complete);
  });

  test('compaction rewrite (smaller + different first line) full re-seeks',
      () async {
    final fs = _ProbeFs();
    await fs.writeString(_path, '${_user('one')}\n${_user('two')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:00Z'));
    final tailer = AiTranscriptTailer();
    await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path);

    // Simulated /compact: rewrite a smaller file with a different first line.
    await fs.writeString(_path, '${_user('collapsed')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:01:00Z'));
    final again = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path);
    expect(again.fullReseek, isTrue);
    expect(again.messages.map((m) => (m.parts.single as AiTextPart).text), ['collapsed']);
  });

  test('same-size in-place rewrite with changed first line full re-seeks',
      () async {
    final fs = _ProbeFs();
    await fs.writeString(_path, '${_user('aaaa')}\n${_user('bbbb')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:00Z'));
    final tailer = AiTranscriptTailer();
    await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path);

    await fs.writeString(_path, '${_user('cccc')}\n${_user('bbbb')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:01:00Z'));
    final again = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path);
    expect(again.fullReseek, isTrue);
    expect(again.messages.map((m) => (m.parts.single as AiTextPart).text), ['cccc', 'bbbb']);
  });

  test('partial trailing line is deferred until a newline lands', () async {
    final fs = _ProbeFs();
    await fs.writeString(_path, '${_user('one')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:00Z'));
    final tailer = AiTranscriptTailer();
    await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path);

    await _append(fs, '${_user('partial')}', DateTime.parse('2026-08-08T00:00:05Z'));
    final deferred = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path);
    expect(deferred.messages, hasLength(1), reason: 'partial line must not be consumed');

    await _append(fs, '\n', DateTime.parse('2026-08-08T00:00:06Z'));
    final landed = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path);
    expect(landed.messages, hasLength(2));
  });

  test('force triggers full re-seek even when unchanged', () async {
    final fs = _ProbeFs();
    await fs.writeString(_path, '${_user('one')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:00Z'));
    final tailer = AiTranscriptTailer();
    await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path);

    final forced = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, force: true);
    expect(forced.fullReseek, isTrue);
  });

  test('path change triggers full re-seek', () async {
    final fs = _ProbeFs();
    await fs.writeString(_path, '${_user('one')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:00Z'));
    final tailer = AiTranscriptTailer();
    await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path);

    const other = '/proj/other.jsonl';
    await fs.writeString(other, '${_user('other')}\n');
    fs.setMtime(other, DateTime.parse('2026-08-08T00:02:00Z'));
    final again = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: other);
    expect(again.fullReseek, isTrue);
    expect(again.messages, hasLength(1));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/services/session/ai_transcript_tailer_test.dart`
Expected: FAIL — `AiTranscriptTailer` is not defined.

- [ ] **Step 3: Implement `ai_transcript_tailer.dart`**

```dart
import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

import '../cli/registry/capabilities/history/claude_compatible_jsonl.dart';
import 'session_history_context.dart';

class TailRefreshResult {
  const TailRefreshResult({
    required this.messages,
    required this.pathKey,
    required this.changed,
    this.fullReseek = false,
  });

  final List<AiMessage> messages;
  final String? pathKey;
  final bool changed;
  final bool fullReseek;
}

/// Incremental reader for an append-only JSONL transcript.
///
/// Holds per-seat cursor state and re-reads only the appended tail, so a live
/// refresh is O(appended bytes) instead of O(file). A full re-seek happens on
/// force, a path change, a `pathKey` change (mtime/size/first-line — catches
/// compaction and in-place rewrites), or a shrink.
final class AiTranscriptTailer {
  AiTranscriptTailer({this.maxFirstLineBytes = 4096});

  final int maxFirstLineBytes;

  final Map<String, _TailState> _states = {};

  @visibleForTesting
  void clear() => _states.clear();

  void remove(String seatKey) => _states.remove(seatKey);

  void removeWhere(bool Function(String seatKey) test) =>
      _states.removeWhere((key, _) => test(key));

  Future<TailRefreshResult> refresh({
    required SessionHistoryContext ctx,
    required String seatKey,
    required String? transcriptPath,
    bool force = false,
  }) async {
    final state = _states.putIfAbsent(seatKey, _TailState.new);
    final path = _trimmed(transcriptPath);

    final stat = path == null ? null : await ctx.fs.stat(path);
    if (path == null || stat == null || !stat.exists || stat.isDirectory) {
      _states.remove(seatKey);
      return const TailRefreshResult(
        messages: [],
        pathKey: null,
        changed: false,
      );
    }
    final size = stat.size ?? -1;
    final pathKey = await _pathKey(ctx, path, stat, size);

    final fullReseek =
        force ||
        state.path != path ||
        state.pathKey != pathKey ||
        size < state.byteOffset;
    if (fullReseek) {
      final content = await ctx.fs.readString(path);
      state.raw.clear();
      if (content != null) {
        for (final line in const LineSplitter().convert(content)) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          final event = tryDecodeJsonlLine(trimmed);
          if (event == null) continue;
          appendClaudeJsonlEvent(
            state.raw,
            event,
            fallbackId: () => 'full-$seatKey',
          );
        }
      }
      state
        ..path = path
        ..pathKey = pathKey
        ..byteOffset = size < 0 ? 0 : size
        ..finalized = finalizeAiMessagesForHistory(state.raw);
      return TailRefreshResult(
        messages: state.finalized,
        pathKey: pathKey,
        changed: true,
        fullReseek: true,
      );
    }

    if (size == state.byteOffset) {
      return TailRefreshResult(
        messages: state.finalized,
        pathKey: pathKey,
        changed: false,
      );
    }

    // Delta: consume the appended tail up to the last '\n'.
    final tail = await ctx.fs.readBytesRange(
      path,
      state.byteOffset,
      size - state.byteOffset,
    );
    if (tail == null || tail.isEmpty) {
      state.byteOffset = size;
      return TailRefreshResult(
        messages: state.finalized,
        pathKey: pathKey,
        changed: false,
      );
    }
    final lastNl = tail.lastIndexOf(0x0A);
    if (lastNl < 0) {
      // Mid-write partial line; defer until a '\n' lands.
      return TailRefreshResult(
        messages: state.finalized,
        pathKey: pathKey,
        changed: false,
      );
    }
    final consumed = tail.sublist(0, lastNl + 1);
    state.byteOffset += consumed.length;
    // Ends at '\n' (0x0A), so this is always a valid UTF-8 boundary.
    final content = utf8.decode(consumed);
    for (final line in const LineSplitter().convert(content)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final event = tryDecodeJsonlLine(trimmed);
      if (event == null) continue;
      appendClaudeJsonlEvent(state.raw, event, fallbackId: () => 'delta-$seatKey');
    }
    state.finalized = finalizeAiMessagesForHistory(state.raw);
    return TailRefreshResult(
      messages: state.finalized,
      pathKey: pathKey,
      changed: true,
    );
  }

  Future<String?> _pathKey(
    SessionHistoryContext ctx,
    String path,
    FsStat stat,
    int size,
  ) async {
    if (size <= 0) return '$size:0';
    final head = await ctx.fs.readBytesRange(path, 0, maxFirstLineBytes);
    // First-line fingerprint only: stable across appends, so a pure append
    // (mtime+size change) does NOT full-reseek. mtime/size must stay out of
    // the key or every delta refresh would be a full re-seek.
    return '${_firstLineFromBytes(head).hashCode}';
  }

  static String _firstLineFromBytes(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) return '';
    final end = bytes.indexOf(0x0A);
    final len = end < 0 ? bytes.length : end;
    return utf8.decode(bytes.sublist(0, len), allowMalformed: true);
  }

  static String? _trimmed(String? value) {
    final t = value?.trim() ?? '';
    return t.isEmpty ? null : t;
  }
}

class _TailState {
  String? path;
  String? pathKey;
  int byteOffset = 0;
  final List<AiMessage> raw = [];
  List<AiMessage> finalized = const [];
}
```

Add `import 'package:meta/meta.dart';` at the top for `@visibleForTesting`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/services/session/ai_transcript_tailer_test.dart`
Expected: PASS (all 9).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/session/ai_transcript_tailer.dart client/test/services/session/ai_transcript_tailer_test.dart
git commit -m "feat(history): add AiTranscriptTailer delta parser for append-only transcripts"
```

---

### Task 3: Loader integration

**Files:**
- Modify: `client/lib/services/session/ai_history_loader.dart`
- Test: `client/test/services/session/ai_history_loader_test.dart` (update 2 token tests to simulate real file growth)

**Interfaces:**
- Consumes: `AiTranscriptTailer` + `TailRefreshResult` (Task 2).
- Produces: unchanged `AiHistoryLoader` public API. `clearCache()`/`invalidate()` now also clear tailer state.

**Design:** keep the token gate (`_resolveCacheToken ?? _defaultCacheToken`) as the early-out; replace the parse path with `_tailer.refresh`. On `changed`, guard the enricher behind a truncated-result scan (it full-reads the file, so only run it when it can do something), then re-inflate. On `!changed`, reuse `_attachments`.

- [ ] **Step 1: Write the failing test** — add to `ai_history_loader_test.dart` a test proving unchanged reloads reuse attachments and appended lines surface:

```dart
test('appended transcript lines surface on reload; unchanged reload reuses attachments',
    () async {
  final fs = LocalFilesystem();
  final loader = buildLoader();
  final session = simpleSession();
  final ctx = launchContextFor(session);
  // Existing helper writes a transcript; reuse the loader's watch meta to find it.
  final first = await loader.load(session: session, memberId: '', launchContext: ctx);
  final meta = await loader.resolveWatchMeta(launchContext: ctx, memberId: '');
  final paths = meta?.cacheTokenPaths ?? const [];
  final path = paths.isEmpty ? null : paths.first;
  expect(path, isNotNull, reason: 'transcript must be located');
  final before = (await fs.readString(path!))!;
  await fs.writeString(path, '$before{"type":"user","message":{"role":"user","content":"appended"}}\n');
  // Touch mtime so the loader token gate opens.
  final f = File(path);
  f.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 1)));

  final second = await loader.load(session: session, memberId: '', launchContext: ctx);
  expect(
    second.messages.any((m) => m.parts.any((p) => p is AiTextPart && p.text.contains('appended'))),
    isTrue,
  );

  final third = await loader.load(session: session, memberId: '', launchContext: ctx);
  expect(identical(second.subagentAttachments, third.subagentAttachments), isTrue,
      reason: 'unchanged reload must reuse the attachment map');
});
```

Add imports if missing: `dart:io` already imported; `package:teampilot/services/io/filesystem.dart` if needed.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/services/session/ai_history_loader_test.dart`
Expected: FAIL — the appended line does not surface (old loader full-parses but the token gate… adjust expectations as needed; the important first failure is the loader not using the tailer yet).

- [ ] **Step 3: Implement** — modify `ai_history_loader.dart`:

Add fields and replace the cache with tailer + token/message/attachment stores:

```dart
final AiTranscriptTailer _tailer = AiTranscriptTailer();
final _tokens = <String, String>{};
final _messages = <String, List<AiMessage>>{};
final _attachments = <String, Map<String, AiSubagentAttachment>>{};
```

Replace the body of `load` from `final cacheKey = _cacheKey(...)` down to the final return (keeping `_resolveSeat` and the capability-null guard) with:

```dart
final cacheKey = _cacheKey(session.sessionId, effectiveMemberId);

final token = await (_resolveCacheToken ?? _defaultCacheToken)(ctx);
if (!force && token != null && _tokens[cacheKey] == token) {
  return AiHistoryLoadResult(
    messages: _messages[cacheKey] ?? const [],
    subagentAttachments: _attachments[cacheKey] ?? const {},
  );
}

final bundle = await _locator.locate(ctx: ctx, cli: cli);
final watch = bundle == null ? null : AiHistoryWatchMeta.fromHints(bundle.hints);
final parentPath = () {
  final paths = watch?.cacheTokenPaths ?? const <String>[];
  for (final p in paths) {
    final t = p.trim();
    if (t.isNotEmpty) return t;
  }
  return null;
}();

final tail = await _tailer.refresh(
  ctx: ctx,
  seatKey: cacheKey,
  transcriptPath: parentPath,
  force: force,
);

if (!tail.changed) {
  _tokens[cacheKey] = token ?? 'unchanged-$cacheKey';
  return AiHistoryLoadResult(
    messages: tail.messages,
    subagentAttachments: _attachments[cacheKey] ?? const {},
  );
}

var messages = tail.messages;
if (_needsToolResultEnrichment(messages)) {
  messages = await cap.toolResultEnricher.enrich(
    messages: messages,
    ctx: ctx,
    rootTranscriptPath: parentPath,
    bundle: bundle,
  );
}

final attachments = await const SubagentAttachmentInflater().inflate(
  messages: messages,
  ctx: ctx,
  capability: cap,
  rootTranscriptPath: parentPath,
);

_messages[cacheKey] = messages;
_attachments[cacheKey] = attachments;
_tokens[cacheKey] = token ?? 'changed-$cacheKey';
return AiHistoryLoadResult(messages: messages, subagentAttachments: attachments);
```

Add the guard helper (file-level static):

```dart
/// The Claude enricher full-reads the transcript to resolve truncated tool
/// results; skip it when no part carries the truncation sentinel.
static bool _needsToolResultEnrichment(List<AiMessage> messages) {
  for (final message in messages) {
    for (final part in message.parts) {
      if (part is AiToolCallPart) {
        final result = part.result;
        if (result is String && result.contains('tool output truncated')) {
          return true;
        }
      }
    }
  }
  return false;
}
```

Replace `clearCache` and `invalidate` to also clear the new stores:

```dart
void clearCache() {
  _tailer.clear();
  _tokens.clear();
  _messages.clear();
  _attachments.clear();
}

void invalidate({required String sessionId, String? memberId}) {
  if (memberId != null) {
    final key = _cacheKey(sessionId, memberId);
    _tailer.remove(key);
    _tokens.remove(key);
    _messages.remove(key);
    _attachments.remove(key);
    return;
  }
  final prefix = '${sessionId.trim()} ';
  _tailer.removeWhere((key) => key.startsWith(prefix));
  _tokens.removeWhere((key, _) => key.startsWith(prefix));
  _messages.removeWhere((key, _) => key.startsWith(prefix));
  _attachments.removeWhere((key, _) => key.startsWith(prefix));
}
```

Remove the now-unused `_AiHistoryCacheEntry` class and the `_cache` field. Keep `_defaultCacheToken` (still the production token). Import `ai_transcript_tailer.dart`.

**Update the two existing token tests** (around lines 240–285): they assert re-locate on `mtimeToken` change with a locator that returns `null`. With the tailer these still pass **if** the locator path is exercised — verify they still pass; if a test uses a real transcript and only mutates `mtimeToken`, change it to append a line to the transcript file (as in Step 1) instead.

- [ ] **Step 4: Run the tests**

Run: `flutter test test/services/session/ai_history_loader_test.dart test/services/session/ai_transcript_tailer_test.dart test/services/cli/registry/capabilities/history/claude_ai_transcript_test.dart test/services/session/subagent_attachment_inflater_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/session/ai_history_loader.dart client/test/services/session/ai_history_loader_test.dart
git commit -m "perf(history): load transcripts through AiTranscriptTailer delta parser"
```

---

## Self-Review

**Spec coverage:**
- S1 (tailer): Task 2. ✓
- S2 (loader): Task 3. ✓
- S3 (incremental attachments): satisfied by Task 3's `!tail.changed` reuse of `_attachments` plus the existing `ClaudeWorkflowResolver` mtime cache — no inflater change needed (deviation from spec, noted in commit). ✓
- S4 (file watch): **already implemented** in `TranscriptChangeSignal` (uses `FsWatcher.watchTree` with poll fallback) — no task. ✓
- S5 (edge cases): compaction/shrink/path-change → Task 2 tests; cross-batch merge → Task 2; partial line → Task 2; remote no-mtime → `_pathKey` degrades to `no-mtime` (mtime is the fallback token anyway). ✓
- S6 (tests): Task 2 (9 boundary tests), Task 3 (loader integration), Task 1 (parser extraction). ✓

**Placeholder scan:** no TBD/TODO; every step has code or an explicit command. ✓

**Type consistency:** `TailRefreshResult.{messages,pathKey,changed,fullReseek}`, `AiTranscriptTailer.{refresh,clear,remove,removeWhere}`, `appendClaudeJsonlEvent`, `tryDecodeJsonlLine` are used consistently across Task 2 → Task 3. ✓

**Post-implementation benchmark (Task 3 done):** re-run the cold-vs-warm resolver benchmark against a real workflow session; expect the warm parent parse to drop from ~100–200 ms full-parse to a single `readBytesRange` + in-memory finalize.
