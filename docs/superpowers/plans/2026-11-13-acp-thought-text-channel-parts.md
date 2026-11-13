# ACP thought / text 通道 part Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ACP 流式 thought/text 在同一工具边界内各自追加到一条 reasoning / 一条 text，交错到达不再切成上百个「思考过程 · 1 步」。

**Architecture:** 抽出纯函数 `appendAcpStreamChannelPart`：工具调用开启新段，段内越过另一通道把增量拼到已有同类型 part。Cubit 的 live/replay append 对 incoming 调用它（不重折 existing，以保留 8KB 文本分段）。Transcript `_MessageBuilder.build()` 对 assistant 从空列表归约一遍，旧碎 jsonl 重开即恢复。

**Tech Stack:** Flutter / Dart 3, flutter_bloc (Cubit), ai_message_core, flutter_test, fake_async.

**Spec:** `docs/superpowers/specs/2026-11-13-acp-thought-text-channel-parts-design.md`

## Global Constraints

- **Never** invoke `flutter test` directly. Every test run is: `cd client && dart run tool/run_tests.dart <test paths>`.
- Inner loop is `cd client && flutter analyze`; do not run the full suite for these local changes.
- Do not change `groupMessageParts`, CoT 组件、统计文案、auto-expand。
- Do not add size/count heuristics（「太碎就合」「步数太多就合」）.
- Do not rewrite on-disk jsonl as a migration. Loading folds in memory; the next `saveMessages` may compact via existing v2 rewrite rules.
- `_queueStreamChunk` 60ms 批处理 stays as a performance window. Channel semantics live only in the fold function.
- Empty text/reasoning parts are dropped by existing `_isEmptyStreamPart` before fold. The fold function does not special-case empty strings.

## File map

- Create: `client/lib/services/acp/acp_stream_channel_parts.dart` — `appendAcpStreamChannelPart` + `foldAcpStreamChannelParts`
- Create: `client/test/services/acp/acp_stream_channel_parts_test.dart`
- Modify: `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` — `_coalesceStreamingParts` calls append; delete `_mergeStreamParts`
- Modify: `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart` — interleaved live tests + 8KB split × thought
- Modify: `client/lib/services/acp/acp_chat_transcript_replay.dart` — `_MessageBuilder.build()` folds assistant parts
- Modify: `client/test/services/acp/acp_chat_transcript_replay_test.dart` — decoder fold test

---

### Task 1: Channel-append pure function

**Files:**
- Create: `client/lib/services/acp/acp_stream_channel_parts.dart`
- Test: `client/test/services/acp/acp_stream_channel_parts_test.dart`

**Interfaces:**
- Consumes: `AiTextPart` / `AiReasoningPart` / `AiToolCallPart` from `package:ai_message_core/ai_message_core.dart`
- Produces:
  - `void appendAcpStreamChannelPart(List<AiMessagePart> out, AiMessagePart part)`
  - `List<AiMessagePart> foldAcpStreamChannelParts(Iterable<AiMessagePart> parts)`

- [ ] **Step 1: Write the failing pure-function tests**

Create `client/test/services/acp/acp_stream_channel_parts_test.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_stream_channel_parts.dart';

const tool = AiToolCallPart(toolCallId: 't1', toolName: 'Read');

void main() {
  test('interleaved thought and text fold onto two channels', () {
    final parts = foldAcpStreamChannelParts(const [
      AiReasoningPart(text: 'a'),
      AiTextPart(text: '1'),
      AiReasoningPart(text: 'b'),
      AiTextPart(text: '2'),
    ]);

    expect(parts, hasLength(2));
    expect((parts[0] as AiReasoningPart).text, 'ab');
    expect((parts[1] as AiTextPart).text, '12');
  });

  test('a tool call starts a new segment', () {
    final parts = foldAcpStreamChannelParts(const [
      AiReasoningPart(text: 'a'),
      tool,
      AiReasoningPart(text: 'b'),
    ]);

    expect(parts, hasLength(3));
    expect((parts[0] as AiReasoningPart).text, 'a');
    expect(parts[1], same(tool));
    expect((parts[2] as AiReasoningPart).text, 'b');
  });

  test('channels resume independently after a tool call', () {
    final parts = foldAcpStreamChannelParts(const [
      AiReasoningPart(text: 'a'),
      AiTextPart(text: '1'),
      tool,
      AiReasoningPart(text: 'b'),
      AiTextPart(text: '2'),
    ]);

    expect(parts, hasLength(5));
    expect((parts[0] as AiReasoningPart).text, 'a');
    expect((parts[1] as AiTextPart).text, '1');
    expect(parts[2], same(tool));
    expect((parts[3] as AiReasoningPart).text, 'b');
    expect((parts[4] as AiTextPart).text, '2');
  });

  test('first-seen type in a segment keeps its position', () {
    final parts = foldAcpStreamChannelParts(const [
      AiTextPart(text: '1'),
      AiReasoningPart(text: 'a'),
      AiTextPart(text: '2'),
    ]);

    expect(parts, hasLength(2));
    expect((parts[0] as AiTextPart).text, '12');
    expect((parts[1] as AiReasoningPart).text, 'a');
  });

  test('append mutates the list in place and skips the other channel', () {
    final out = <AiMessagePart>[
      const AiReasoningPart(text: 'a'),
      const AiTextPart(text: '1'),
    ];
    appendAcpStreamChannelPart(out, const AiReasoningPart(text: 'b'));
    expect(out, hasLength(2));
    expect((out[0] as AiReasoningPart).text, 'ab');
    expect((out[1] as AiTextPart).text, '1');
  });

  test('already-folded channel parts stay the same', () {
    const folded = [
      AiReasoningPart(text: 'ab'),
      AiTextPart(text: '12'),
    ];
    final again = foldAcpStreamChannelParts(folded);
    expect(again, hasLength(2));
    expect((again[0] as AiReasoningPart).text, 'ab');
    expect((again[1] as AiTextPart).text, '12');
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_stream_channel_parts_test.dart`

Expected: FAIL — `acp_stream_channel_parts.dart` does not exist (`uri_does_not_exist` / compile error).

- [ ] **Step 3: Implement the fold functions**

Create `client/lib/services/acp/acp_stream_channel_parts.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';

/// Appends [part] onto [out] in place.
///
/// Tool calls start a new segment. Within a segment, a text (reasoning)
/// part concatenates onto the last text (reasoning) part, skipping the
/// other channel; if none exists yet in the segment, [part] is appended.
void appendAcpStreamChannelPart(
  List<AiMessagePart> out,
  AiMessagePart part,
) {
  switch (part) {
    case AiToolCallPart():
      out.add(part);
    case AiTextPart(:final text):
      for (var i = out.length - 1; i >= 0; i--) {
        final current = out[i];
        if (current is AiToolCallPart) break;
        if (current is AiTextPart) {
          out[i] = AiTextPart(text: '${current.text}$text');
          return;
        }
      }
      out.add(part);
    case AiReasoningPart(:final text):
      for (var i = out.length - 1; i >= 0; i--) {
        final current = out[i];
        if (current is AiToolCallPart) break;
        if (current is AiReasoningPart) {
          out[i] = AiReasoningPart(text: '${current.text}$text');
          return;
        }
      }
      out.add(part);
  }
}

/// Folds [parts] from an empty list through [appendAcpStreamChannelPart].
List<AiMessagePart> foldAcpStreamChannelParts(Iterable<AiMessagePart> parts) {
  final out = <AiMessagePart>[];
  for (final part in parts) {
    appendAcpStreamChannelPart(out, part);
  }
  return out;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_stream_channel_parts_test.dart`

Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp/acp_stream_channel_parts.dart \
  client/test/services/acp/acp_stream_channel_parts_test.dart
git commit -m "feat(acp): fold thought and text onto two stream channels"
```

---

### Task 2: Live / replay cubit uses channel append

**Files:**
- Modify: `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart`
- Test: `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

**Interfaces:**
- Consumes: `appendAcpStreamChannelPart(List<AiMessagePart> out, AiMessagePart part)` from Task 1
- Produces: `_coalesceStreamingParts` still `static List<AiMessagePart> _coalesceStreamingParts(List<AiMessagePart> existing, List<AiMessagePart> incoming)` — copies `existing`, then appends each incoming part. Does **not** re-fold `existing` (keeps `_splitStreamingText` heads).

- [ ] **Step 1: Write the failing cubit tests**

In `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`, add immediately after the existing test `'empty stream chunks do not open extra parts'` (after the `await cubit.close();` / `},` of that test, still outside the `stream chunk coalescing` group):

```dart
  test('interleaved thought and text coalesce onto two parts', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'a',
        isThought: true,
      ),
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: '1',
        isThought: false,
      ),
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'b',
        isThought: true,
      ),
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: '2',
        isThought: false,
      ),
    );
    await pumpEventQueue();

    final parts = cubit.state.messages.single.parts;
    expect(parts, hasLength(2));
    expect((parts[0] as AiReasoningPart).text, 'ab');
    expect((parts[1] as AiTextPart).text, '12');
    await cubit.close();
  });

  test('a tool call keeps later thought on a new reasoning part', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'a',
        isThought: true,
      ),
    );
    runtime.emit(
      const AcpToolCallUpdate(
        toolCallId: 't1',
        title: 'read file',
        status: AcpToolCallStatus.inProgress,
      ),
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'b',
        isThought: true,
      ),
    );
    await pumpEventQueue();

    final parts = cubit.state.messages.single.parts;
    expect(parts, hasLength(3));
    expect((parts[0] as AiReasoningPart).text, 'a');
    expect(parts[1], isA<AiToolCallPart>());
    expect((parts[2] as AiReasoningPart).text, 'b');
    await cubit.close();
  });

  test('channels resume independently after a tool call', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'a',
        isThought: true,
      ),
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: '1',
        isThought: false,
      ),
    );
    runtime.emit(
      const AcpToolCallUpdate(
        toolCallId: 't1',
        title: 'read file',
        status: AcpToolCallStatus.inProgress,
      ),
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'b',
        isThought: true,
      ),
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: '2',
        isThought: false,
      ),
    );
    await pumpEventQueue();

    final parts = cubit.state.messages.single.parts;
    expect(parts, hasLength(5));
    expect((parts[0] as AiReasoningPart).text, 'a');
    expect((parts[1] as AiTextPart).text, '1');
    expect(parts[2], isA<AiToolCallPart>());
    expect((parts[3] as AiReasoningPart).text, 'b');
    expect((parts[4] as AiTextPart).text, '2');
    await cubit.close();
  });

  test('text that arrives first stays in front of later thought', () async {
    final cubit = bootCubit();
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: '1',
        isThought: false,
      ),
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'a',
        isThought: true,
      ),
    );
    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: '2',
        isThought: false,
      ),
    );
    await pumpEventQueue();

    final parts = cubit.state.messages.single.parts;
    expect(parts, hasLength(2));
    expect((parts[0] as AiTextPart).text, '12');
    expect((parts[1] as AiReasoningPart).text, 'a');
    await cubit.close();
  });
```

Inside the existing `group('stream chunk coalescing')`, after `'keeps text/reasoning order across interleaved chunks'`, add:

```dart
    test('coalesce window still folds thought/text switches onto two parts', () {
      fakeAsync((async) {
        final cubit = bootCubit(chunkCoalesceWindow: window);
        startCubit(cubit);
        async.flushMicrotasks();

        runtime.emit(chunk('a', thought: true));
        runtime.emit(chunk('1'));
        runtime.emit(chunk('b', thought: true));
        runtime.emit(chunk('2'));
        async.flushMicrotasks();
        async.elapse(window);

        final parts = cubit.state.messages.single.parts;
        expect(parts, hasLength(2));
        expect((parts[0] as AiReasoningPart).text, 'ab');
        expect((parts[1] as AiTextPart).text, '12');

        unawaited(cubit.close());
        async.flushMicrotasks();
      });
    });
```

Inside the existing `group('streaming text split')`, after `'splits oversized prose at a paragraph boundary'`, add:

```dart
    test('a later thought does not glue split text heads', () async {
      final cubit = await startedCubit();
      final first = 'A' * 5000;
      final second = 'B' * 5000;
      runtime.emit(
        AcpMessageChunk(
          role: AcpRole.assistant,
          content: '$first\n\n$second',
          isThought: false,
        ),
      );
      await pumpEventQueue();
      final textsBefore = cubit.state.messages.single.parts
          .whereType<AiTextPart>()
          .toList();
      expect(textsBefore.length, greaterThan(1));
      final head = textsBefore.first;

      runtime.emit(
        const AcpMessageChunk(
          role: AcpRole.assistant,
          content: 'hmm',
          isThought: true,
        ),
      );
      await pumpEventQueue();

      final parts = cubit.state.messages.single.parts;
      final texts = parts.whereType<AiTextPart>().toList();
      expect(texts.length, textsBefore.length);
      expect(identical(texts.first, head), isTrue);
      expect(texts.map((p) => p.text).join(), '$first\n\n$second');
      expect(parts.last, isA<AiReasoningPart>());
      expect((parts.last as AiReasoningPart).text, 'hmm');
      await cubit.close();
    });
```

- [ ] **Step 2: Run the cubit tests to verify the new ones fail**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

Expected: FAIL on `'interleaved thought and text coalesce onto two parts'` — `parts` has length 4 (`a`,`1`,`b`,`2`) instead of 2. Existing tests still pass.

- [ ] **Step 3: Wire `_coalesceStreamingParts` and drop `_mergeStreamParts`**

Add the import to `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` (with the other `services/acp/` imports):

```dart
import '../../../services/acp/acp_stream_channel_parts.dart';
```

Replace the doc comment on `_appendMessageParts` so it describes channels, not only adjacent same-type:

```dart
  /// Appends parts onto the tip assistant message (streaming continuation),
  /// or opens a new assistant message when the tip is not appendable.
  ///
  /// Thought and text are two channels punctuated by tool calls: a chunk
  /// concatenates onto the last same-kind part in the current segment.
  /// Interleaved token streams therefore stay one reasoning part and one
  /// text part, instead of one thinking-process step per switch.
```

Replace `_coalesceStreamingParts` / `_mergeStreamParts` with:

```dart
  static List<AiMessagePart> _coalesceStreamingParts(
    List<AiMessagePart> existing,
    List<AiMessagePart> incoming,
  ) {
    final out = [...existing];
    for (final part in incoming) {
      appendAcpStreamChannelPart(out, part);
    }
    return out;
  }
```

Delete `_mergeStreamParts` entirely.

- [ ] **Step 4: Run the cubit tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

Expected: PASS, including the pre-existing tests:

- `consecutive thought chunks coalesce into one reasoning part`
- `consecutive text chunks coalesce; thought stays a separate part`
- `keeps text/reasoning order across interleaved chunks`
- `empty stream chunks do not open extra parts`
- `splits oversized prose at a paragraph boundary`

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart \
  client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart
git commit -m "fix(acp): coalesce interleaved thought and text during live turns"
```

---

### Task 3: Transcript load folds assistant parts

**Files:**
- Modify: `client/lib/services/acp/acp_chat_transcript_replay.dart`
- Test: `client/test/services/acp/acp_chat_transcript_replay_test.dart`

**Interfaces:**
- Consumes: `foldAcpStreamChannelParts(Iterable<AiMessagePart> parts)` from Task 1
- Produces: `_MessageBuilder.build()` returns channel-folded parts when `role == AiRole.assistant`; user/system parts are unchanged. Full decode, delta replay, and `loadMessages` all go through this method.

- [ ] **Step 1: Write the failing decoder tests**

In `client/test/services/acp/acp_chat_transcript_replay_test.dart`, add after `'round-trips user, assistant parts, and system'`:

```dart
  test('decoder folds interleaved thought and text on assistant messages', () {
    final jsonl = [
      _line({'v': 2, 'type': 'assistant', 'id': 'acp-a-1'}),
      _line({
        'v': 2,
        'type': 'part',
        'mid': 'acp-a-1',
        'i': 0,
        'part': {'kind': 'reasoning', 'text': 'a'},
      }),
      _line({
        'v': 2,
        'type': 'part',
        'mid': 'acp-a-1',
        'i': 1,
        'part': {'kind': 'text', 'text': '1'},
      }),
      _line({
        'v': 2,
        'type': 'part',
        'mid': 'acp-a-1',
        'i': 2,
        'part': {'kind': 'reasoning', 'text': 'b'},
      }),
      _line({
        'v': 2,
        'type': 'part',
        'mid': 'acp-a-1',
        'i': 3,
        'part': {'kind': 'text', 'text': '2'},
      }),
    ].join('\n');

    final loaded = decodeAcpChatTranscript(jsonl);
    expect(loaded, hasLength(1));
    final parts = loaded.single.parts;
    expect(parts, hasLength(2));
    expect((parts[0] as AiReasoningPart).text, 'ab');
    expect((parts[1] as AiTextPart).text, '12');
  });

  test('decoder leaves user parts unfolded', () {
    final jsonl = [
      _line({'v': 2, 'type': 'user', 'id': 'acp-u-1'}),
      _line({
        'v': 2,
        'type': 'part',
        'mid': 'acp-u-1',
        'i': 0,
        'part': {'kind': 'text', 'text': 'one'},
      }),
      _line({
        'v': 2,
        'type': 'part',
        'mid': 'acp-u-1',
        'i': 1,
        'part': {'kind': 'text', 'text': 'two'},
      }),
    ].join('\n');

    final loaded = decodeAcpChatTranscript(jsonl);
    expect(loaded.single.parts, hasLength(2));
    expect((loaded.single.parts[0] as AiTextPart).text, 'one');
    expect((loaded.single.parts[1] as AiTextPart).text, 'two');
  });

  test('decoder keeps a tool call as a segment boundary', () {
    final jsonl = [
      _line({'v': 2, 'type': 'assistant', 'id': 'acp-a-1'}),
      _line({
        'v': 2,
        'type': 'part',
        'mid': 'acp-a-1',
        'i': 0,
        'part': {'kind': 'reasoning', 'text': 'a'},
      }),
      _line({
        'v': 2,
        'type': 'part',
        'mid': 'acp-a-1',
        'i': 1,
        'part': {
          'kind': 'tool',
          'toolCallId': 't1',
          'title': 'Read',
          'status': 'complete',
          'isError': false,
        },
      }),
      _line({
        'v': 2,
        'type': 'part',
        'mid': 'acp-a-1',
        'i': 2,
        'part': {'kind': 'reasoning', 'text': 'b'},
      }),
    ].join('\n');

    final parts = decodeAcpChatTranscript(jsonl).single.parts;
    expect(parts, hasLength(3));
    expect((parts[0] as AiReasoningPart).text, 'a');
    expect((parts[1] as AiToolCallPart).toolCallId, 't1');
    expect((parts[2] as AiReasoningPart).text, 'b');
  });
```

- [ ] **Step 2: Run the decoder tests to verify the new ones fail**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_chat_transcript_replay_test.dart`

Expected: FAIL on `'decoder folds interleaved thought and text on assistant messages'` — `parts` has length 4. `'decoder leaves user parts unfolded'` already PASSES (user parts are not folded today). Keep it as a regression guard for Step 3.

- [ ] **Step 3: Fold assistant parts in `_MessageBuilder.build()`**

Add the import at the top of `client/lib/services/acp/acp_chat_transcript_replay.dart`:

```dart
import 'acp_stream_channel_parts.dart';
```

Replace `_MessageBuilder.build()` with:

```dart
  AiMessage build() {
    final raw = [
      for (final part in parts)
        if (part != null) part,
    ];
    return AiMessage(
      id: id,
      role: role,
      parts: role == AiRole.assistant ? foldAcpStreamChannelParts(raw) : raw,
      createdAt: createdAt,
      status: status,
      deliveryChannel: deliveryChannel,
    );
  }
```

- [ ] **Step 4: Run decoder and cubit tests**

Run: `cd client && dart run tool/run_tests.dart test/services/acp/acp_chat_transcript_replay_test.dart test/services/acp/acp_stream_channel_parts_test.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

Expected: PASS. Existing `'round-trips user, assistant parts, and system'` still passes: that assistant is already `[reasoning, text, tool]` which folds to itself.

Then: `cd client && flutter analyze lib/services/acp/acp_stream_channel_parts.dart lib/services/acp/acp_chat_transcript_replay.dart lib/cubits/session/acp/acp_chat_runtime_cubit.dart test/services/acp/acp_stream_channel_parts_test.dart test/services/acp/acp_chat_transcript_replay_test.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/acp/acp_chat_transcript_replay.dart \
  client/test/services/acp/acp_chat_transcript_replay_test.dart
git commit -m "fix(acp): fold interleaved thought and text when loading transcripts"
```
