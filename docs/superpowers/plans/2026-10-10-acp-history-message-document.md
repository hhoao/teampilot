# ACP History Message Document Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist each ACP session as a Zed-style v1 message snapshot (not a chunk event log), reopen through the PTY loading pane, and window the seat to the latest 30 turns.

**Architecture:** `AcpChatTranscriptWriter.saveMessages` atomically rewrites `acp-transcript.jsonl` from the cubit's folded `AiMessage` list on commit (user / tool / stop / system / close). Chunks stay in memory. `AiHistorySeat.adoptExternalMessages` cold-applies with the existing 30-turn window and live-patches the tail without PTY tip-hold.

**Tech Stack:** Flutter / Dart, `Filesystem.atomicWrite`, `AiHistorySeat` window (`kSessionHistoryInitialTurns`), existing ACP cubit fakes.

**Spec:** `docs/superpowers/specs/2026-10-10-acp-history-message-document-design.md`

## Global Constraints

- **Never invoke `flutter test` directly.** Always `cd client && PUB_HOSTED_URL=https://pub.flutter-io.cn dart run tool/run_tests.dart <paths/options>`.
- Inner loop: `flutter analyze` + one test file (`--plain-name` to narrow). Full suite once, in the background, before claiming done.
- Logging: diagnostics via `AppLogger`; no `print`.
- No legacy chunk-JSONL compatibility. Old `type: chunk|tool_call|stop` files load as empty history.
- Do not plug ACP into `AiHistoryLoader` or `GeminiAiHistoryCapability`. Do not call `seat.load()` for ACP.
- Do not add SQLite/zstd, per-turn files, or `session/load`.
- Do not commit unless the user asked for commits in that turn; if they did, never skip hooks.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `client/lib/services/acp/acp_chat_transcript_replay.dart` | v1 encode/decode + `mergeHydratedAcpMessages` | Replace chunk fold |
| `client/lib/services/acp/acp_chat_transcript.dart` | Snapshot I/O | `saveMessages` / `loadMessages` only |
| `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart` | Live fold + persist on commit | Stop per-chunk records |
| `client/lib/cubits/ai_history_seat.dart` | Windowed adopt | First = `_applyMessages`; live = identity + window, no tip-hold |
| `client/test/services/acp/acp_chat_transcript_replay_test.dart` | Codec + writer tests | Rewrite |
| `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart` | Persist timing + hydrate | Update |
| `client/test/cubits/ai_history_seat_acp_adopt_test.dart` | Seat window | Create |

`acp_seat_message_sync.dart` and `session_chat_view.dart` stay as they are (loading guards already land).

---

### Task 1: v1 message codec

**Files:**
- Modify: `client/lib/services/acp/acp_chat_transcript_replay.dart`
- Test: `client/test/services/acp/acp_chat_transcript_replay_test.dart`

**Interfaces:**
- Consumes: `AiMessage` / `AiTextPart` / `AiReasoningPart` / `AiToolCallPart` / `AiToolCallStatus` from `package:ai_message_core/ai_message_core.dart`.
- Produces:
  - `String encodeAcpChatTranscript(List<AiMessage> messages)`
  - `List<AiMessage> decodeAcpChatTranscript(String? jsonl)`
  - Keep `List<AiMessage> mergeHydratedAcpMessages({required List<AiMessage> loaded, required List<AiMessage> live})` unchanged.
  - Delete `replayAcpChatTranscript` and `_AcpChatTranscriptFold`.

Line schema (JSONL, one message per line):

```json
{"v":1,"type":"user","id":"acp-u-1","text":"hi","at":"2026-10-10T06:00:00.000Z"}
{"v":1,"type":"assistant","id":"acp-a-1","at":"2026-10-10T06:00:01.000Z","parts":[
  {"kind":"text","text":"Hello"},
  {"kind":"reasoning","text":"think"},
  {"kind":"tool","toolCallId":"t1","title":"Read","status":"complete","isError":false}
]}
{"v":1,"type":"system","id":"acp-sys-1","message":"Turn failed","at":"2026-10-10T06:00:02.000Z"}
```

Encode rules: `v` is always `1`; `at` is `createdAt?.toUtc().toIso8601String()` omitted when null; user text is joined `AiTextPart`s; assistant parts emit `text` / `reasoning` / `tool` only (skip unknown part types); tool `status` is `part.status.name`, `title` is `part.toolName`; system `message` is joined `AiTextPart`s (no `kind` field — `AiMessage` does not carry it). Skip messages with empty user/system text or empty assistant parts after filtering.

Decode rules: skip blank lines; skip `jsonDecode` failures; skip maps with `v != 1`; skip unknown `type` / `kind`; unknown tool status → `AiToolCallStatus.incomplete`. Legacy chunk JSONL has no `v: 1` → empty list.

- [ ] **Step 1: Replace the replay tests with v1 codec tests**

Overwrite `client/test/services/acp/acp_chat_transcript_replay_test.dart` so `main()` is:

```dart
import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_chat_transcript_replay.dart';

String _line(Map<String, Object?> entry) => jsonEncode(entry);

void main() {
  test('missing or empty jsonl decodes to no messages', () {
    expect(decodeAcpChatTranscript(null), isEmpty);
    expect(decodeAcpChatTranscript(''), isEmpty);
    expect(decodeAcpChatTranscript('\n\n'), isEmpty);
  });

  test('legacy chunk jsonl without v:1 decodes to empty', () {
    final jsonl = _line({
      'type': 'chunk',
      'role': 'assistant',
      'text': 'Hello',
      'seq': 0,
    });
    expect(decodeAcpChatTranscript(jsonl), isEmpty);
  });

  test('garbage and non-v1 lines are skipped', () {
    final jsonl = [
      'not-json',
      _line({'v': 1, 'type': 'nope', 'id': 'x'}),
      _line({
        'v': 1,
        'type': 'user',
        'id': 'acp-u-1',
        'text': 'hi',
      }),
    ].join('\n');
    final messages = decodeAcpChatTranscript(jsonl);
    expect(messages, hasLength(1));
    expect((messages.single.parts.single as AiTextPart).text, 'hi');
  });

  test('round-trips user, assistant parts, and system', () {
    final original = [
      AiMessage(
        id: 'acp-u-1',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'hi')],
        createdAt: DateTime.utc(2026, 10, 10, 6),
      ),
      AiMessage(
        id: 'acp-a-1',
        role: AiRole.assistant,
        parts: const [
          AiReasoningPart(text: 'think'),
          AiTextPart(text: 'Hello'),
          AiToolCallPart(
            toolCallId: 't1',
            toolName: 'Read',
            status: AiToolCallStatus.complete,
            isError: false,
          ),
        ],
        createdAt: DateTime.utc(2026, 10, 10, 6, 0, 1),
      ),
      AiMessage(
        id: 'acp-sys-1',
        role: AiRole.system,
        parts: const [AiTextPart(text: 'Turn failed')],
        createdAt: DateTime.utc(2026, 10, 10, 6, 0, 2),
      ),
    ];
    final loaded = decodeAcpChatTranscript(encodeAcpChatTranscript(original));
    expect(loaded, hasLength(3));
    expect(loaded[0].id, 'acp-u-1');
    expect(loaded[0].role, AiRole.user);
    expect((loaded[0].parts.single as AiTextPart).text, 'hi');
    expect(loaded[1].id, 'acp-a-1');
    final parts = loaded[1].parts;
    expect(parts[0], isA<AiReasoningPart>());
    expect((parts[0] as AiReasoningPart).text, 'think');
    expect((parts[1] as AiTextPart).text, 'Hello');
    final tool = parts[2] as AiToolCallPart;
    expect(tool.toolCallId, 't1');
    expect(tool.toolName, 'Read');
    expect(tool.status, AiToolCallStatus.complete);
    expect(tool.isError, isFalse);
    expect((loaded[2].parts.single as AiTextPart).text, 'Turn failed');
  });

  test('mergeHydratedAcpMessages appends a live landing prompt', () {
    final loaded = [
      AiMessage(
        id: 'acp-u-old',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'old')],
      ),
    ];
    final live = [
      AiMessage(
        id: 'acp-u-next',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'next')],
      ),
    ];
    final merged = mergeHydratedAcpMessages(loaded: loaded, live: live);
    expect(merged, hasLength(2));
    expect((merged.last.parts.single as AiTextPart).text, 'next');
  });
}
```

- [ ] **Step 2: Run the codec tests (expect fail)**

Run: `cd client && PUB_HOSTED_URL=https://pub.flutter-io.cn dart run tool/run_tests.dart test/services/acp/acp_chat_transcript_replay_test.dart`

Expected: FAIL — `encodeAcpChatTranscript` / `decodeAcpChatTranscript` not defined, or `replayAcpChatTranscript` leftover.

- [ ] **Step 3: Replace the fold with encode/decode**

Overwrite `client/lib/services/acp/acp_chat_transcript_replay.dart`:

```dart
import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';

String encodeAcpChatTranscript(List<AiMessage> messages) {
  final buffer = StringBuffer();
  for (final message in messages) {
    final line = _encodeMessage(message);
    if (line == null) continue;
    buffer.writeln(jsonEncode(line));
  }
  return buffer.toString();
}

List<AiMessage> decodeAcpChatTranscript(String? jsonl) {
  if (jsonl == null || jsonl.isEmpty) return const [];
  final messages = <AiMessage>[];
  for (final raw in jsonl.split('\n')) {
    if (raw.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) continue;
      final message = _decodeMessage(Map<String, Object?>.from(decoded));
      if (message != null) messages.add(message);
    } on FormatException {
      continue;
    }
  }
  return messages;
}

List<AiMessage> mergeHydratedAcpMessages({
  required List<AiMessage> loaded,
  required List<AiMessage> live,
}) {
  if (loaded.isEmpty) return live;
  if (live.isEmpty) return loaded;
  final skipLiveFirst =
      _userText(loaded.last) != null &&
      _userText(loaded.last) == _userText(live.first);
  return [...loaded, ...live.skip(skipLiveFirst ? 1 : 0)];
}

String? _userText(AiMessage message) {
  if (message.role != AiRole.user) return null;
  return message.parts.whereType<AiTextPart>().map((p) => p.text).join();
}

Map<String, Object?>? _encodeMessage(AiMessage message) {
  final at = message.createdAt?.toUtc().toIso8601String();
  switch (message.role) {
    case AiRole.user:
      final text = message.parts.whereType<AiTextPart>().map((p) => p.text).join();
      if (text.isEmpty) return null;
      return {
        'v': 1,
        'type': 'user',
        'id': message.id,
        'text': text,
        if (at != null) 'at': at,
      };
    case AiRole.system:
      final text = message.parts.whereType<AiTextPart>().map((p) => p.text).join();
      if (text.isEmpty) return null;
      return {
        'v': 1,
        'type': 'system',
        'id': message.id,
        'message': text,
        if (at != null) 'at': at,
      };
    case AiRole.assistant:
      final parts = <Map<String, Object?>>[
        for (final part in message.parts)
          if (_encodePart(part) case final encoded?) encoded,
      ];
      if (parts.isEmpty) return null;
      return {
        'v': 1,
        'type': 'assistant',
        'id': message.id,
        if (at != null) 'at': at,
        'parts': parts,
      };
  }
}

Map<String, Object?>? _encodePart(AiMessagePart part) {
  switch (part) {
    case AiTextPart(:final text):
      if (text.isEmpty) return null;
      return {'kind': 'text', 'text': text};
    case AiReasoningPart(:final text):
      if (text.isEmpty) return null;
      return {'kind': 'reasoning', 'text': text};
    case AiToolCallPart():
      return {
        'kind': 'tool',
        'toolCallId': part.toolCallId,
        'title': part.toolName,
        'status': part.status.name,
        'isError': part.isError,
      };
    default:
      return null;
  }
}

AiMessage? _decodeMessage(Map<String, Object?> entry) {
  if (entry['v'] != 1) return null;
  final id = entry['id'];
  if (id is! String || id.isEmpty) return null;
  final at = _at(entry);
  switch (entry['type']) {
    case 'user':
      final text = entry['text'];
      if (text is! String || text.isEmpty) return null;
      return AiMessage(
        id: id,
        role: AiRole.user,
        parts: [AiTextPart(text: text)],
        createdAt: at,
      );
    case 'system':
      final message = entry['message'];
      if (message is! String || message.isEmpty) return null;
      return AiMessage(
        id: id,
        role: AiRole.system,
        parts: [AiTextPart(text: message)],
        createdAt: at,
      );
    case 'assistant':
      final rawParts = entry['parts'];
      if (rawParts is! List) return null;
      final parts = <AiMessagePart>[
        for (final item in rawParts)
          if (item is Map && _decodePart(Map<String, Object?>.from(item)) case final part?)
            part,
      ];
      if (parts.isEmpty) return null;
      return AiMessage(
        id: id,
        role: AiRole.assistant,
        parts: parts,
        createdAt: at,
      );
    default:
      return null;
  }
}

AiMessagePart? _decodePart(Map<String, Object?> entry) {
  switch (entry['kind']) {
    case 'text':
      final text = entry['text'];
      if (text is! String || text.isEmpty) return null;
      return AiTextPart(text: text);
    case 'reasoning':
      final text = entry['text'];
      if (text is! String || text.isEmpty) return null;
      return AiReasoningPart(text: text);
    case 'tool':
      final toolCallId = entry['toolCallId'];
      if (toolCallId is! String || toolCallId.isEmpty) return null;
      final title = entry['title'];
      return AiToolCallPart(
        toolCallId: toolCallId,
        toolName: title is String && title.isNotEmpty ? title : toolCallId,
        status: _status(entry['status']),
        isError: entry['isError'] == true,
      );
    default:
      return null;
  }
}

AiToolCallStatus _status(Object? raw) {
  if (raw is! String) return AiToolCallStatus.incomplete;
  for (final value in AiToolCallStatus.values) {
    if (value.name == raw) return value;
  }
  return AiToolCallStatus.incomplete;
}

DateTime? _at(Map<String, Object?> entry) {
  final at = entry['at'];
  if (at is! String || at.isEmpty) return null;
  return DateTime.tryParse(at);
}
```

Fix any analyzer issue with switch-on-sealed `AiMessagePart` if `default` is unreachable: drop `default` and use `case AiToolCallPart():` plus other sealed cases as `return null`.

- [ ] **Step 4: Re-run codec tests**

Run: `cd client && PUB_HOSTED_URL=https://pub.flutter-io.cn dart run tool/run_tests.dart test/services/acp/acp_chat_transcript_replay_test.dart`

Expected: All tests passed.

- [ ] **Step 5: Commit (only if the user asked to commit)**

```bash
git add client/lib/services/acp/acp_chat_transcript_replay.dart \
  client/test/services/acp/acp_chat_transcript_replay_test.dart
git commit -m "$(cat <<'EOF'
feat(acp): encode chat history as a v1 message snapshot

Replace the chunk-event fold with encode/decode of folded AiMessage rows
so reopen reads a Zed-style document instead of a token log.
EOF
)"
```

---

### Task 2: Snapshot writer

**Files:**
- Modify: `client/lib/services/acp/acp_chat_transcript.dart`
- Modify: `client/test/services/acp/acp_chat_transcript_replay_test.dart` (append writer tests)

**Interfaces:**
- Consumes: `encodeAcpChatTranscript` / `decodeAcpChatTranscript` from Task 1; `Filesystem.atomicWrite` / `readString`.
- Produces:
  - `Future<void> saveMessages(List<AiMessage> messages)`
  - `Future<List<AiMessage>> loadMessages()`
  - Delete `recordUserPrompt`, `recordChunk`, `recordToolCall`, `recordStop`, `recordSystem`, `_seq`, `_ensureHydrated`, `_append`.

`saveMessages` must enqueue on the existing `_pending` chain, then `atomicWrite(path, encodeAcpChatTranscript(messages))`. `loadMessages` awaits `_pending`, `readString`, then decode. If the file is non-empty and decode returns empty, log with `AppLogger` (`appLogger.w('[acp-transcript] ignored non-v1 snapshot path=$path')`) and return `[]`.

- [ ] **Step 1: Add writer tests to the codec file**

Append inside `main()`:

```dart
  test('saveMessages round-trips through loadMessages', () async {
    final fs = InMemoryFilesystem();
    const path = '/tp/acp-transcript.jsonl';
    final writer = AcpChatTranscriptWriter(fs: fs, path: path);
    await writer.saveMessages([
      AiMessage(
        id: 'acp-u-1',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'hello')],
      ),
    ]);
    final loaded = await writer.loadMessages();
    expect(loaded, hasLength(1));
    expect((loaded.single.parts.single as AiTextPart).text, 'hello');
    expect(fs.files[path], contains('"v":1'));
    expect(fs.files[path], isNot(contains('"type":"chunk"')));
  });

  test('loadMessages treats a missing file as empty', () async {
    final writer = AcpChatTranscriptWriter(
      fs: InMemoryFilesystem(),
      path: '/tp/missing.jsonl',
    );
    expect(await writer.loadMessages(), isEmpty);
  });

  test('second saveMessages replaces the previous snapshot', () async {
    final fs = InMemoryFilesystem();
    const path = '/tp/acp-transcript.jsonl';
    final writer = AcpChatTranscriptWriter(fs: fs, path: path);
    await writer.saveMessages([
      AiMessage(
        id: 'acp-u-1',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'first')],
      ),
    ]);
    await writer.saveMessages([
      AiMessage(
        id: 'acp-u-2',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'second')],
      ),
    ]);
    final loaded = await writer.loadMessages();
    expect(loaded, hasLength(1));
    expect((loaded.single.parts.single as AiTextPart).text, 'second');
  });
```

Add imports: `package:teampilot/services/acp/acp_chat_transcript.dart` and `../../support/in_memory_filesystem.dart`.

- [ ] **Step 2: Run writer tests (expect fail)**

Run: `cd client && PUB_HOSTED_URL=https://pub.flutter-io.cn dart run tool/run_tests.dart test/services/acp/acp_chat_transcript_replay_test.dart --plain-name saveMessages`

Expected: FAIL — `saveMessages` is not defined (or `recordUserPrompt` still exists and tests call the new API).

- [ ] **Step 3: Rewrite the writer**

Replace `client/lib/services/acp/acp_chat_transcript.dart` with:

```dart
import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';

import '../io/filesystem.dart';
import '../../utils/logging/logger.dart';
import 'acp_chat_transcript_replay.dart';

/// Append-free snapshot of one ACP chat session's folded messages.
class AcpChatTranscriptWriter {
  AcpChatTranscriptWriter({required Filesystem fs, required this.path})
    : _fs = fs;

  final Filesystem _fs;
  final String path;

  Future<void> _pending = Future<void>.value();

  Future<List<AiMessage>> loadMessages() async {
    await _pending;
    final raw = await _fs.readString(path);
    final loaded = decodeAcpChatTranscript(raw);
    if ((raw != null && raw.trim().isNotEmpty) && loaded.isEmpty) {
      appLogger.w('[acp-transcript] ignored non-v1 snapshot path=$path');
    }
    return loaded;
  }

  Future<void> saveMessages(List<AiMessage> messages) {
    final next = _pending.then((_) async {
      await _fs.atomicWrite(path, encodeAcpChatTranscript(messages));
    });
    _pending = next.catchError((Object _) {});
    return next;
  }
}
```

- [ ] **Step 4: Re-run the transcript tests**

Run: `cd client && PUB_HOSTED_URL=https://pub.flutter-io.cn dart run tool/run_tests.dart test/services/acp/acp_chat_transcript_replay_test.dart`

Expected: All tests passed.

- [ ] **Step 5: Commit (only if the user asked to commit)**

```bash
git add client/lib/services/acp/acp_chat_transcript.dart \
  client/test/services/acp/acp_chat_transcript_replay_test.dart
git commit -m "$(cat <<'EOF'
feat(acp): rewrite acp-transcript.jsonl as an atomic message snapshot

Save the folded AiMessage list via atomicWrite instead of appending
protocol chunks, matching Zed's replace-the-document persistence.
EOF
)"
```

---

### Task 3: Cubit persists on commit, not per chunk

**Files:**
- Modify: `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart`
- Modify: `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

**Interfaces:**
- Consumes: `AcpChatTranscriptWriter.saveMessages` / `loadMessages` from Task 2.
- Produces: cubit helper `_persist()` that saves `_messagesForDisk()`; no remaining `record*` calls.

Persist after: user prompt is in `state.messages`; tool update applied; `_onStop` finished (including turn_error system row); `_endWith` when `kind != AcpChatErrorKind.processExited`; `close()` (await the save so tests can read the file). Do **not** persist on `AcpMessageChunk`.

`_messagesForDisk()`: if `state.error?.kind == AcpChatErrorKind.processExited`, drop system messages whose joined text equals `state.error!.message`; otherwise `state.messages`. Auth rows are never in `messages`.

I/O errors: `try/on Object` + `appLogger.e('[acp-chat] persist failed session=$sessionId: $error', error: error, stackTrace: st)` — do not rethrow into the turn.

Hydrate still uses `loadMessages` + `mergeHydratedAcpMessages` + `historyHydrated: true`.

- [ ] **Step 1: Rewrite the cubit transcript tests**

In `client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`:

1. Change `'messages are recorded into the app-side transcript store'` so after prompt + chunk + stop + `pumpEventQueue()` it loads via `transcript.loadMessages()` and asserts:
   - length 2
   - user text `hi`
   - assistant text `Hello`
   - joined file content has `"v":1` and `"type":"user"` / `"type":"assistant"` and does **not** contain `"type":"chunk"` or `"type":"stop"`.
2. Keep `'start hydrates prior transcript into messages'` (it already write-then-reopen via cubit; after Task 2 the file is v1).
3. Replace the two tests that call `recordUserPrompt` / `recordChunk` with `saveMessages` of the equivalent folded `AiMessage`s:

```dart
await transcript.saveMessages([
  AiMessage(
    id: 'acp-u-old',
    role: AiRole.user,
    parts: const [AiTextPart(text: 'hi')],
  ),
  AiMessage(
    id: 'acp-a-old',
    role: AiRole.assistant,
    parts: const [AiTextPart(text: 'Hello')],
  ),
]);
```

(and `'old'` / `'prior'` for the landing-prompt test).

4. Add:

```dart
  test('streaming chunks do not rewrite the snapshot until stop', () async {
    final fs = InMemoryFilesystem();
    final transcript = AcpChatTranscriptWriter(fs: fs, path: '/tp/acp.jsonl');
    final cubit = bootCubit(transcript: transcript);
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    cubit.sendPrompt('hi');
    await pumpEventQueue();
    final afterUser = await transcript.loadMessages();
    expect(afterUser, hasLength(1));

    runtime.emit(
      const AcpMessageChunk(
        role: AcpRole.assistant,
        content: 'Hel',
        isThought: false,
      ),
    );
    await pumpEventQueue();
    final afterChunk = await transcript.loadMessages();
    expect(afterChunk, hasLength(1));
    expect(afterChunk.single.role, AiRole.user);

    runtime.emit(const AcpStop(kind: AcpStopKind.endTurn));
    await pumpEventQueue();
    final afterStop = await transcript.loadMessages();
    expect(afterStop, hasLength(2));
    expect((afterStop.last.parts.single as AiTextPart).text, 'Hel');
    await cubit.close();
  });

  test('tool call updates rewrite the snapshot', () async {
    final fs = InMemoryFilesystem();
    final transcript = AcpChatTranscriptWriter(fs: fs, path: '/tp/acp.jsonl');
    final cubit = bootCubit(transcript: transcript);
    await cubit.start(
      executable: 'gemini',
      sessionToolDir: '/tmp/tool',
      workingDirectory: '/w',
    );
    cubit.sendPrompt('hi');
    runtime.emit(
      const AcpToolCallUpdate(
        toolCallId: 't1',
        title: 'Read',
        status: AcpToolCallStatus.completed,
      ),
    );
    await pumpEventQueue();
    final loaded = await transcript.loadMessages();
    expect(loaded, hasLength(2));
    final tool = loaded.last.parts.whereType<AiToolCallPart>().single;
    expect(tool.toolCallId, 't1');
    expect(tool.status, AiToolCallStatus.complete);
    await cubit.close();
  });
```

5. Keep `'intentional close does not record a process-exited crash'` asserting `loadMessages()` has no system text containing `exited` / `退出`. After close, `loadMessages` must still contain the user prompt `hi`.

- [ ] **Step 2: Run cubit tests (expect fail)**

Run: `cd client && PUB_HOSTED_URL=https://pub.flutter-io.cn dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart --plain-name "streaming chunks"`

Expected: FAIL — `recordUserPrompt` missing and/or chunks still written / persist API not wired.

- [ ] **Step 3: Wire persist in the cubit**

In `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart`:

Add:

```dart
List<AiMessage> _messagesForDisk() {
  final error = state.error;
  if (error == null || error.kind != AcpChatErrorKind.processExited) {
    return state.messages;
  }
  return [
    for (final message in state.messages)
      if (!(message.role == AiRole.system &&
          message.parts.whereType<AiTextPart>().map((p) => p.text).join() ==
              error.message))
        message,
  ];
}

Future<void> _persist() async {
  final transcript = _transcript;
  if (transcript == null) return;
  try {
    await transcript.saveMessages(_messagesForDisk());
  } on Object catch (error, stackTrace) {
    appLogger.e(
      '[acp-chat] persist failed session=$sessionId: $error',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
```

Call sites (await so order is stable; `_persist` already swallows errors):

- `_showUserMessage` / `sendPrompt` path after the user `AiMessage` is emitted: `unawaited(_persist());` is OK if tests `pumpEventQueue`, but prefer `await _persist()` inside `_recordAndPrompt` **after** the user message is already in state (today `_recordAndPrompt` records then `prompt()` — emit the user message before persist, then prompt).
- `_applyToolCall`: after each successful `emit`, `unawaited(_persist());`
- `_onStop`: after mutating messages (turn_error append), `unawaited(_persist());` then `_endTurn()`. Remove `recordSystem('turn_error', ...)`.
- `_endWith`: `_appendSystemMessage` then `emit` ended; if `kind != AcpChatErrorKind.processExited` then `unawaited(_persist());`. Remove `recordSystem(kind.name, message)`.
- `close`: `await _persist();` after `_closing = true` and before `_runtime.close()`.
- `_onUpdate` `AcpMessageChunk`: delete `await _transcript?.recordChunk(update);` — only update memory.
- Delete every remaining `recordUserPrompt` / `recordChunk` / `recordToolCall` / `recordStop` / `recordSystem`.

`_recordAndPrompt` should become: user already emitted by `sendPrompt`; persist; then `prompt()`. Today `sendPrompt` emits the user bubble then calls `_recordAndPrompt` which recorded then prompted. Keep that emit, persist in `_recordAndPrompt` before `prompt()`.

- [ ] **Step 4: Re-run cubit tests**

Run: `cd client && PUB_HOSTED_URL=https://pub.flutter-io.cn dart run tool/run_tests.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart`

Expected: All tests passed.

- [ ] **Step 5: Commit (only if the user asked to commit)**

```bash
git add client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart \
  client/test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart
git commit -m "$(cat <<'EOF'
fix(acp): persist folded history on commit, not on every chunk

Keep streaming in memory and rewrite the message snapshot when a user
turn, tool card, stop, or system row lands so reopen stays cheap.
EOF
)"
```

---

### Task 4: Seat windows ACP history

**Files:**
- Modify: `client/lib/cubits/ai_history_seat.dart` (`adoptExternalMessages` ~941)
- Create: `client/test/cubits/ai_history_seat_acp_adopt_test.dart`

**Interfaces:**
- Consumes: `kSessionHistoryInitialTurns` (30) and `kSessionHistoryOlderPageSize` (20) from `client/lib/services/chat/conversation/history/session_history_pagination.dart`; `reuseHistoryMessageIdentity` from the same library.
- Produces: `adoptExternalMessages(List<AiMessage> messages)` that:
  - Returns immediately if `isClosed`.
  - Sets `_cliMessages = List.unmodifiable(messages)`.
  - **Cold** when `state.status` is `loading` or `empty` or `_allMessages.isEmpty`: call `_applyMessages(messages, state.sessionId ?? '', state.memberId ?? '')` (this already windows to 30 and sets `hasOlder` via `_visibleCount < _committedLength`).
  - **Live** otherwise: do **not** call `_applySoftReloadMessages` (that path holds the assistant tip while `awaitingAssistant`, which would hide ACP streaming). Instead:
    1. `messages = reuseHistoryMessageIdentity(previous: _allMessages, next: messages);`
    2. `oldLength` / `oldVisible` snapshots; `_allMessages = messages`; `_committedLength = _allMessages.length` always.
    3. If length shrinks: `_visibleCount = min(oldVisible, newLength)`.
    4. If length grows: `_visibleCount = min(newLength, oldVisible + max(0, newLength - oldLength))`.
    5. If length is unchanged: keep `_visibleCount` (the mutated tip is already inside the slice).
    6. Empty → `_emitEmptyOrPendingReady`; else `_emitReadyWindow`.
  - Skip `_loader.annotate` (ACP never sets `_lastCli` on this path; `_applyMessages` already no-ops annotate when `_lastCli == null`).

Keep `markExternalLoading` as it is.

- [ ] **Step 1: Write seat adopt tests**

Create `client/test/cubits/ai_history_seat_acp_adopt_test.dart`:

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_seat.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/conversation/history/ai_history_loader.dart';
import 'package:teampilot/services/chat/conversation/history/session_history_pagination.dart';
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../support/fake_ai_history_registry.dart';
import '../support/post_frame_test_harness.dart';

class _EmptyAdapter implements AiTranscriptAdapter {
  const _EmptyAdapter();

  @override
  String get id => 'claude';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async => const [];
}

void main() {
  late AiHistorySeat seat;

  List<AiMessage> nMessages(int count) => [
    for (var i = 0; i < count; i++)
      AiMessage(
        id: 'm-$i',
        role: AiRole.user,
        parts: [AiTextPart(text: 'msg-$i')],
      ),
  ];

  setUp(() {
    setUpTestAppStorage();
    final fs = LocalFilesystem();
    seat = AiHistorySeat(
      loader: AiHistoryLoader(
        resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
          target: RuntimeTarget.local(),
          filesystem: fs,
          home: '/tmp/acp-adopt',
          cwd: '/tmp/acp-adopt',
          appDataRoot: '/tmp/acp-adopt',
          paths: AppPaths('/tmp/acp-adopt'),
        ),
        registry: fakeAiHistoryRegistry(
          cli: CliTool.claude,
          adapter: const _EmptyAdapter(),
        ),
      ),
    );
  });

  tearDown(() async {
    await seat.close();
    tearDownTestAppStorage();
  });

  test('first adopt after loading windows to the latest 30 turns', () {
    seat.markExternalLoading();
    seat.adoptExternalMessages(nMessages(35));
    expect(seat.state.status, AiHistoryViewStatus.ready);
    expect(seat.loadedMessages, hasLength(35));
    expect(seat.runtime.messages, hasLength(kSessionHistoryInitialTurns));
    expect(seat.runtime.messages.first.id, 'm-5');
    expect(seat.runtime.messages.last.id, 'm-34');
    expect(seat.state.hasOlder, isTrue);
    expect(seat.state.totalMessageCount, 35);
  });

  test('loadOlder expands the in-memory ACP window', () async {
    seat.markExternalLoading();
    seat.adoptExternalMessages(nMessages(35));
    await seat.loadOlder();
    expect(seat.runtime.messages, hasLength(35));
    expect(seat.state.hasOlder, isFalse);
  });

  test('live adopt grows the tail without resetting the window to 30', () {
    seat.markExternalLoading();
    seat.adoptExternalMessages(nMessages(35));
    expect(seat.runtime.messages, hasLength(30));
    seat.adoptExternalMessages([
      ...nMessages(35),
      AiMessage(
        id: 'm-35',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'msg-35')],
      ),
    ]);
    expect(seat.loadedMessages, hasLength(36));
    expect(seat.runtime.messages, hasLength(31));
    expect(seat.runtime.messages.last.id, 'm-35');
  });

  test('live adopt with the same length keeps the window and updates the tip', () {
    seat.markExternalLoading();
    final first = [
      AiMessage(
        id: 'u1',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'hi')],
      ),
      AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: const [AiTextPart(text: 'Hel')],
      ),
    ];
    seat.adoptExternalMessages(first);
    seat.setAwaitingAssistant(true);
    seat.adoptExternalMessages([
      first[0],
      AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: const [AiTextPart(text: 'Hello')],
      ),
    ]);
    expect(seat.runtime.messages, hasLength(2));
    expect(
      (seat.runtime.messages.last.parts.single as AiTextPart).text,
      'Hello',
    );
  });
}
```

If `fakeAiHistoryRegistry()` needs arguments, copy the `cli:` / `adapter:` usage from `client/test/cubits/ai_history_seat_no_blank_test.dart`. Unused `AppSession` imports can be dropped. `WorkspaceLaunchContext` is unused — omit those imports.

- [ ] **Step 2: Run seat tests (expect fail)**

Run: `cd client && PUB_HOSTED_URL=https://pub.flutter-io.cn dart run tool/run_tests.dart test/cubits/ai_history_seat_acp_adopt_test.dart --plain-name "first adopt"`

Expected: FAIL — `hasOlder` is false and `runtime.messages` has length 35.

- [ ] **Step 3: Implement windowed adopt**

Replace `adoptExternalMessages` in `client/lib/cubits/ai_history_seat.dart`:

```dart
  void adoptExternalMessages(List<AiMessage> messages) {
    if (isClosed) return;
    _cliMessages = List.unmodifiable(messages);
    final sessionId = state.sessionId ?? '';
    final memberId = state.memberId ?? '';
    final cold =
        state.status == AiHistoryViewStatus.loading ||
        state.status == AiHistoryViewStatus.empty ||
        _allMessages.isEmpty;
    if (cold) {
      _applyMessages(messages, sessionId, memberId);
      return;
    }
    messages = reuseHistoryMessageIdentity(
      previous: _allMessages,
      next: messages,
    );
    final oldLength = _allMessages.length;
    final oldVisible = _visibleCount;
    _allMessages = messages;
    final newLength = _allMessages.length;
    _committedLength = newLength;
    if (newLength < oldLength) {
      _visibleCount = math.min(oldVisible, newLength);
    } else if (newLength > oldLength) {
      _visibleCount = math.min(
        newLength,
        oldVisible + (newLength - oldLength),
      );
    }
    if (newLength == 0) {
      _emitEmptyOrPendingReady(sessionId, memberId);
      return;
    }
    _emitReadyWindow(sessionId, memberId);
  }
```

Confirm `reuseHistoryMessageIdentity` is already imported via `session_history_pagination.dart` (it is exported from that file). If the analyzer complains, add:

`import '../services/chat/conversation/history/session_history_pagination.dart';`

(the seat file already imports that library for `kSessionHistoryInitialTurns`).

- [ ] **Step 4: Re-run seat + ACP view tests**

Run: `cd client && PUB_HOSTED_URL=https://pub.flutter-io.cn dart run tool/run_tests.dart test/cubits/ai_history_seat_acp_adopt_test.dart test/pages/chat/session_chat_view_acp_test.dart test/pages/chat/acp_seat_message_sync_test.dart test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart test/services/acp/acp_chat_transcript_replay_test.dart`

Expected: All tests passed.

Then: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/acp/acp_chat_transcript.dart lib/services/acp/acp_chat_transcript_replay.dart lib/cubits/session/acp/acp_chat_runtime_cubit.dart lib/cubits/ai_history_seat.dart`

Expected: `No issues found` (or only pre-existing infos unrelated to these files).

Grep the tree for leftover `recordChunk` / `recordUserPrompt` / `replayAcpChatTranscript` under `client/` and delete any leftover production call. Tests must not reference those names.

- [ ] **Step 5: Commit (only if the user asked to commit)**

```bash
git add client/lib/cubits/ai_history_seat.dart \
  client/test/cubits/ai_history_seat_acp_adopt_test.dart
git commit -m "$(cat <<'EOF'
fix(acp): window restored history like PTY instead of mounting every bubble

Cold adopt uses the 30-turn slice and loadOlder; live adopt patches the
tail so streaming stays visible without resetting the window.
EOF
)"
```

After Task 4, start the full suite in the background:

`cd client && PUB_HOSTED_URL=https://pub.flutter-io.cn dart run tool/run_tests.dart`

Do not claim done until that run finishes with `All tests passed` or remaining failures are shown to be unrelated.
