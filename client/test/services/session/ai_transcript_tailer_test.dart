import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/claude_compatible_jsonl.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/cursor_ai_transcript.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/session/ai_transcript_tailer.dart';
import 'package:teampilot/services/session/session_history_context.dart';

import '../../support/in_memory_filesystem.dart';

const _path = '/proj/ses.jsonl';
const _seat = 'sess\u0000member';

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

/// Cursor agent-transcripts put the speaker on the TOP-LEVEL `role` field
/// (Claude/flashskyai use `type`). The tailer must parse both.
String _cursorLine(String role, String text) => _line({
  'role': role,
  'message': {
    'role': role,
    'content': [
      {'type': 'text', 'text': text},
    ],
  },
  'uuid': '$role-${text.hashCode}',
  'timestamp': '2026-08-08T00:00:04.000Z',
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

    final first = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);
    expect(first.changed, isTrue);
    expect(first.fullReseek, isTrue);
    expect(first.messages, hasLength(2));
    final firstSize = (await fs.readBytes(_path))!.length;
    fs.rangeReads.clear();
    fs.readStringCalls = 0;

    await _append(fs, '${_user('three')}\n', DateTime.parse('2026-08-08T00:00:10Z'));
    final secondSize = (await fs.readBytes(_path))!.length;
    final second = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);
    expect(second.changed, isTrue);
    expect(second.fullReseek, isFalse);
    expect(second.messages, hasLength(3));
    expect(fs.readStringCalls, 0, reason: 'delta path must not full-read');
    expect(
      fs.rangeReads,
      contains((firstSize, secondSize - firstSize)),
      reason: 'tail read must start at byteOffset',
    );
  });

  test('parses Cursor transcripts that use a top-level role field', () async {
    final fs = _ProbeFs();
    await fs.writeString(
      _path,
      '${_cursorLine('user', 'hello')}\n'
      '${_cursorLine('assistant', 'hi')}\n'
      '${_cursorLine('user', 'again')}\n'
      '${_cursorLine('assistant', 'bye')}\n',
    );
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:00Z'));
    final tailer = AiTranscriptTailer();

    final first = await tailer.refresh(
      ctx: _ctx(fs),
      seatKey: _seat,
      transcriptPath: _path,
      appendEvent: appendCursorJsonlEvent,
    );
    expect(first.changed, isTrue);
    expect(first.messages, hasLength(4));
    expect(first.messages[0].role, AiRole.user);
    expect((first.messages[0].parts.single as AiTextPart).text, 'hello');
    expect(first.messages[1].role, AiRole.assistant);
    expect((first.messages[1].parts.single as AiTextPart).text, 'hi');
    expect(first.messages[2].role, AiRole.user);
    expect((first.messages[2].parts.single as AiTextPart).text, 'again');
    expect(first.messages[3].role, AiRole.assistant);
    expect((first.messages[3].parts.single as AiTextPart).text, 'bye');

    // Delta refresh must keep parsing cursor rows.
    await _append(
      fs,
      '${_cursorLine('user', 'more')}\n'
      '${_cursorLine('assistant', 'final')}\n',
      DateTime.parse('2026-08-08T00:00:10Z'),
    );
    final second = await tailer.refresh(
      ctx: _ctx(fs),
      seatKey: _seat,
      transcriptPath: _path,
      appendEvent: appendCursorJsonlEvent,
    );
    expect(second.changed, isTrue);
    expect(second.fullReseek, isFalse);
    expect(second.messages, hasLength(6));
    expect(second.messages[5].role, AiRole.assistant);
    expect((second.messages[5].parts.single as AiTextPart).text, 'final');
  });

  test('unchanged refresh returns cached with zero delta work', () async {
    final fs = _ProbeFs();
    await fs.writeString(_path, '${_user('one')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:00Z'));
    final tailer = AiTranscriptTailer();
    await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);

    final again = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);
    expect(again.changed, isFalse);
    expect(again.messages, hasLength(1));
  });

  test('cross-batch streamed assistant merges into one message', () async {
    final fs = _ProbeFs();
    await fs.writeString(_path, '${_assistant('m1', 'hello')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:00Z'));
    final tailer = AiTranscriptTailer();
    await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);

    await _append(fs, '${_assistant('m1', ' world')}\n', DateTime.parse('2026-08-08T00:00:05Z'));
    final second = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);
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
    await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);

    await _append(fs, '${_toolResult('call_1', 'out')}\n', DateTime.parse('2026-08-08T00:00:05Z'));
    final second = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);
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
    await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);

    // Simulated /compact: rewrite a smaller file with a different first line.
    await fs.writeString(_path, '${_user('collapsed')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:01:00Z'));
    final again = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);
    expect(again.fullReseek, isTrue);
    expect(again.messages.map((m) => (m.parts.single as AiTextPart).text), ['collapsed']);
  });

  test('same-size in-place rewrite with changed first line full re-seeks',
      () async {
    final fs = _ProbeFs();
    await fs.writeString(_path, '${_user('aaaa')}\n${_user('bbbb')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:00Z'));
    final tailer = AiTranscriptTailer();
    await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);

    await fs.writeString(_path, '${_user('cccc')}\n${_user('bbbb')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:01:00Z'));
    final again = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);
    expect(again.fullReseek, isTrue);
    expect(again.messages.map((m) => (m.parts.single as AiTextPart).text), ['cccc', 'bbbb']);
  });

  test('partial trailing line is deferred until a newline lands', () async {
    final fs = _ProbeFs();
    await fs.writeString(_path, '${_user('one')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:00Z'));
    final tailer = AiTranscriptTailer();
    await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);

    await _append(fs, _user('partial'), DateTime.parse('2026-08-08T00:00:05Z'));
    final deferred = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);
    expect(deferred.messages, hasLength(1), reason: 'partial line must not be consumed');

    await _append(fs, '\n', DateTime.parse('2026-08-08T00:00:06Z'));
    final landed = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);
    expect(landed.messages, hasLength(2));
  });

  test('full reseek landing on a trailing partial line defers and completes',
      () async {
    final fs = _ProbeFs();
    // First write ends mid-line (no '\n'): the reseek must consume only up to
    // the last complete line and keep the partial deferred for the delta path.
    final complete = _user('lands-on-delta');
    final partial = complete.substring(0, complete.length - 1); // missing '}'
    await fs.writeString(_path, '${_user('one')}\n$partial');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:00Z'));
    final tailer = AiTranscriptTailer();

    final first = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);
    expect(first.fullReseek, isTrue);
    expect(first.messages, hasLength(1), reason: 'trailing partial line must be deferred');
    final partialStart = utf8.encode('${_user('one')}\n').length;
    fs.rangeReads.clear();
    fs.readStringCalls = 0;

    await _append(fs, '}\n', DateTime.parse('2026-08-08T00:00:05Z'));
    final secondSize = (await fs.readBytes(_path))!.length;
    final second = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);
    expect(second.changed, isTrue);
    expect(second.messages, hasLength(2), reason: 'completed line must appear, not drop');
    expect(
      fs.rangeReads,
      contains((partialStart, secondSize - partialStart)),
      reason: 'delta read must start at the partial-line start',
    );
  });

  test('full reseek landing mid-multibyte char defers until the char completes',
      () async {
    final fs = _ProbeFs();
    // A valid line whose content ends with a multi-byte char (U+4F60,
    // E4 BD A0 in UTF-8); write only the first byte of it so the reseek would
    // land mid-code-point under the old unconditional byteOffset = size.
    final complete = _user('\u4F60');
    final bytes = utf8.encode(complete);
    const t = <int>[0xE4, 0xBD, 0xA0];
    var triple = -1;
    for (var i = 0; i <= bytes.length - t.length && triple < 0; i++) {
      if (bytes[i] == t[0] && bytes[i + 1] == t[1] && bytes[i + 2] == t[2]) {
        triple = i;
      }
    }
    expect(triple, greaterThan(0), reason: 'multi-byte char must be in the line');
    final chunk1 = bytes.sublist(0, triple + 1); // ends after first byte of U+4F60
    final chunk2 = bytes.sublist(triple + 1);

    await fs.writeString(_path, '${_user('one')}\n');
    await fs.writeBytes(_path, [
      ...(await fs.readBytes(_path))!,
      ...chunk1,
    ]);
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:00Z'));
    final tailer = AiTranscriptTailer();

    final first = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);
    expect(first.fullReseek, isTrue);
    expect(first.messages, hasLength(1), reason: 'partial multibyte line deferred');

    await fs.writeBytes(_path, [
      ...(await fs.readBytes(_path))!,
      ...chunk2,
      0x0A,
    ]);
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:05Z'));
    final second = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);
    expect(second.changed, isTrue);
    expect(second.messages, hasLength(2), reason: 'completed multibyte line appears');
    expect(
      second.messages[1].parts.map((p) => (p as AiTextPart).text).join(),
      '\u4F60',
    );
  });

  test('force triggers full re-seek even when unchanged', () async {
    final fs = _ProbeFs();
    await fs.writeString(_path, '${_user('one')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:00Z'));
    final tailer = AiTranscriptTailer();
    await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);

    final forced = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, force: true, appendEvent: appendClaudeJsonlEvent);
    expect(forced.fullReseek, isTrue);
  });

  test('path change triggers full re-seek', () async {
    final fs = _ProbeFs();
    await fs.writeString(_path, '${_user('one')}\n');
    fs.setMtime(_path, DateTime.parse('2026-08-08T00:00:00Z'));
    final tailer = AiTranscriptTailer();
    await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: _path, appendEvent: appendClaudeJsonlEvent);

    const other = '/proj/other.jsonl';
    await fs.writeString(other, '${_user('other')}\n');
    fs.setMtime(other, DateTime.parse('2026-08-08T00:02:00Z'));
    final again = await tailer.refresh(ctx: _ctx(fs), seatKey: _seat, transcriptPath: other, appendEvent: appendClaudeJsonlEvent);
    expect(again.fullReseek, isTrue);
    expect(again.messages, hasLength(1));
  });
}
