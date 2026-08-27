import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_jsonl.dart';
import 'package:teampilot/services/cli/codex/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/session/ai_history_page.dart';
import 'package:teampilot/services/session/ai_transcript_tail_reader.dart';
import 'package:teampilot/services/session/jsonl_transcript_page_reader.dart';
import 'package:teampilot/services/session/session_history_context.dart';

import '../../support/in_memory_filesystem.dart' as test_fs;

EventDecoder _syncDecoder() {
  return (lines) async => [
    for (final line in lines)
      tryDecodeJsonlLine(utf8.decode(line, allowMalformed: true)),
  ];
}

void main() {
  test('cursor rejects a changed source token', () async {
    final fs = InMemoryFilesystem();
    final path = '/transcript.jsonl';
    await fs.writeString(
      path,
      '${_userLine('u1', 'one')}${_userLine('u2', 'two')}',
    );
    final reader = JsonlTranscriptPageReader(
      fs: fs,
      lineAppend: appendClaudeJsonlEvent,
      fallbackPrefix: 'claude',
      decodeEvents: _syncDecoder(),
      sourcePath: (_) async => path,
    );
    final ctx = SessionHistoryContext(
      fs: fs,
      taskId: 'task',
      env: const {},
      transcriptRoots: const [],
      bucket: 'bucket',
    );

    final page = await reader.readLatest(ctx: ctx, limit: 1);
    expect(page, isNotNull);
    expect(page!.nextCursor, isNotNull);

    await fs.writeString('/other.jsonl', _userLine('u2', 'two'));
    final changedSourceReader = JsonlTranscriptPageReader(
      fs: fs,
      lineAppend: appendClaudeJsonlEvent,
      fallbackPrefix: 'claude',
      decodeEvents: _syncDecoder(),
      sourcePath: (_) async => '/other.jsonl',
    );

    expect(
      await changedSourceReader.readOlder(
        ctx: ctx,
        cursor: page.nextCursor!,
        limit: 1,
      ),
      isNull,
    );
  });

  test('page retains message and cursor values while remaining immutable', () {
    final message = AiMessage(
      id: 'm1',
      role: AiRole.user,
      parts: const [AiTextPart(text: 'hello')],
    );
    final cursor = const AiHistoryCursor(
      sourceToken: 'source-token',
      offset: 12,
      lineHash: 34,
    );
    final page = AiHistoryPage(
      messages: [message],
      hasOlder: true,
      nextCursor: cursor,
      sourceToken: 'source-token',
      rebuilt: false,
    );

    expect(page.messages, hasLength(1));
    expect(page.messages.single, same(message));
    expect(page.nextCursor, same(cursor));
    expect(() => page.messages.add(message), throwsUnsupportedError);
  });

  test('empty page reports whether an older cursor exists', () {
    const cursor = AiHistoryCursor(
      sourceToken: 'source-token',
      offset: 0,
      lineHash: 0,
    );
    final empty = AiHistoryPage(
      messages: const [],
      hasOlder: false,
      nextCursor: null,
      sourceToken: 'source-token',
      rebuilt: true,
    );
    final emptyWithOlder = AiHistoryPage(
      messages: const [],
      hasOlder: true,
      nextCursor: cursor,
      sourceToken: 'source-token',
      rebuilt: false,
    );

    expect(empty.hasOlder, isFalse);
    expect(empty.nextCursor, isNull);
    expect(emptyWithOlder.hasOlder, isTrue);
    expect(emptyWithOlder.nextCursor, same(cursor));
  });

  test(
    'latest and older pages cover the transcript without duplicates',
    () async {
      final fs = InMemoryFilesystem();
      final path = '/transcript.jsonl';
      await fs.writeString(
        path,
        [for (var i = 0; i < 6; i++) _userLine('u$i', 'message-$i')].join(),
      );
      final reader = JsonlTranscriptPageReader(
        fs: fs,
        lineAppend: appendClaudeJsonlEvent,
        fallbackPrefix: 'claude',
        decodeEvents: _syncDecoder(),
        sourcePath: (_) async => path,
        windowSizes: const [80, 256],
      );
      final ctx = SessionHistoryContext(
        fs: fs,
        taskId: 'task',
        env: const {},
        transcriptRoots: const [],
        bucket: 'bucket',
      );

      final latest = await reader.readLatest(ctx: ctx, limit: 2);
      expect(latest, isNotNull);
      expect(_texts(latest!.messages), ['message-4', 'message-5']);
      expect(latest.hasOlder, isTrue);

      final older = await reader.readOlder(
        ctx: ctx,
        cursor: latest.nextCursor!,
        limit: 2,
      );
      expect(older, isNotNull);
      expect(_texts(older!.messages), ['message-2', 'message-3']);
      expect(older.hasOlder, isTrue);

      final oldest = await reader.readOlder(
        ctx: ctx,
        cursor: older.nextCursor!,
        limit: 2,
      );
      expect(oldest, isNotNull);
      expect(_texts(oldest!.messages), ['message-0', 'message-1']);
      expect(oldest.hasOlder, isFalse);
      expect(oldest.nextCursor, isNull);
    },
  );

  test('latest page never decodes a partial leading line', () async {
    final fs = InMemoryFilesystem();
    final path = '/transcript.jsonl';
    await fs.writeString(
      path,
      [for (var i = 0; i < 4; i++) _userLine('u$i', 'x' * 50)].join(),
    );
    final reader = JsonlTranscriptPageReader(
      fs: fs,
      lineAppend: appendClaudeJsonlEvent,
      fallbackPrefix: 'claude',
      decodeEvents: _syncDecoder(),
      sourcePath: (_) async => path,
      windowSizes: const [100, 300],
    );
    final ctx = SessionHistoryContext(
      fs: fs,
      taskId: 'task',
      env: const {},
      transcriptRoots: const [],
      bucket: 'bucket',
    );

    final page = await reader.readLatest(ctx: ctx, limit: 1);
    expect(page, isNotNull);
    expect(_texts(page!.messages), ['x' * 50]);
  });

  test('latest page keeps a streamed assistant boundary intact', () async {
    final fs = InMemoryFilesystem();
    final path = '/transcript.jsonl';
    await fs.writeString(
      path,
      [
        for (var i = 0; i < 4; i++) _userLine('prefix-$i', 'x' * 50),
        _assistantLine('a1', 'first '),
        _assistantLine('a1', 'second'),
      ].join(),
    );
    final reader = JsonlTranscriptPageReader(
      fs: fs,
      lineAppend: appendClaudeJsonlEvent,
      fallbackPrefix: 'claude',
      decodeEvents: _syncDecoder(),
      sourcePath: (_) async => path,
      windowSizes: const [150, 600],
    );
    final ctx = SessionHistoryContext(
      fs: fs,
      taskId: 'task',
      env: const {},
      transcriptRoots: const [],
      bucket: 'bucket',
    );

    final page = await reader.readLatest(ctx: ctx, limit: 1);
    expect(page, isNotNull);
    expect(page!.messages, hasLength(1));
    expect(
      (page.messages.single.parts.single as AiTextPart).text,
      'first second',
    );
  });

  test('older page invalidates after the source size changes', () async {
    final fs = InMemoryFilesystem();
    final path = '/transcript.jsonl';
    await fs.writeString(
      path,
      '${_userLine('u1', 'one')}${_userLine('u2', 'two')}',
    );
    final reader = JsonlTranscriptPageReader(
      fs: fs,
      lineAppend: appendClaudeJsonlEvent,
      fallbackPrefix: 'claude',
      decodeEvents: _syncDecoder(),
      sourcePath: (_) async => path,
    );
    final ctx = SessionHistoryContext(
      fs: fs,
      taskId: 'task',
      env: const {},
      transcriptRoots: const [],
      bucket: 'bucket',
    );
    final latest = await reader.readLatest(ctx: ctx, limit: 1);
    expect(latest, isNotNull);
    await fs.appendString(path, _userLine('u3', 'three'));

    expect(
      await reader.readOlder(ctx: ctx, cursor: latest!.nextCursor!, limit: 1),
      isNull,
    );
  });

  test('older page invalidates when its anchor line is rewritten', () async {
    final fs = InMemoryFilesystem();
    final path = '/transcript.jsonl';
    final original = [
      _userLine('u1', 'one'),
      _userLine('u2', 'two'),
      _userLine('u3', 'three'),
    ].join();
    await fs.writeString(path, original);
    final reader = JsonlTranscriptPageReader(
      fs: fs,
      lineAppend: appendClaudeJsonlEvent,
      fallbackPrefix: 'claude',
      decodeEvents: _syncDecoder(),
      sourcePath: (_) async => path,
    );
    final ctx = SessionHistoryContext(
      fs: fs,
      taskId: 'task',
      env: const {},
      transcriptRoots: const [],
      bucket: 'bucket',
    );
    final latest = await reader.readLatest(ctx: ctx, limit: 1);
    expect(latest, isNotNull);
    await fs.writeString(
      path,
      original.replaceFirst('"content":"three"', '"content":"xxxxx"'),
    );

    expect(
      await reader.readOlder(ctx: ctx, cursor: latest!.nextCursor!, limit: 1),
      isNull,
    );
  });

  test('suffix fallback ids make the page source unavailable', () async {
    final fs = InMemoryFilesystem();
    final path = '/transcript.jsonl';
    await fs.writeString(
      path,
      '{"type":"user","uuid":"u-1","message":{"content":"one"}}\n'
      '{"type":"user","message":{"content":"two needs fallback"}}\n',
    );
    final reader = JsonlTranscriptPageReader(
      fs: fs,
      lineAppend: appendClaudeJsonlEvent,
      fallbackPrefix: 'claude',
      decodeEvents: _syncDecoder(),
      sourcePath: (_) async => path,
      windowSizes: const [24],
    );
    final ctx = SessionHistoryContext(
      fs: fs,
      taskId: 'task',
      env: const {},
      transcriptRoots: const [],
      bucket: 'bucket',
    );

    expect(await reader.readLatest(ctx: ctx, limit: 1), isNull);
  });

  test('empty JSONL source returns an empty latest page', () async {
    final fs = InMemoryFilesystem();
    final path = '/transcript.jsonl';
    await fs.writeString(path, '');
    final reader = JsonlTranscriptPageReader(
      fs: fs,
      lineAppend: appendClaudeJsonlEvent,
      fallbackPrefix: 'claude',
      decodeEvents: _syncDecoder(),
      sourcePath: (_) async => path,
    );
    final ctx = SessionHistoryContext(
      fs: fs,
      taskId: 'task',
      env: const {},
      transcriptRoots: const [],
      bucket: 'bucket',
    );

    final page = await reader.readLatest(ctx: ctx, limit: 1);
    expect(page, isNotNull);
    expect(page!.messages, isEmpty);
    expect(page.hasOlder, isFalse);
    expect(page.nextCursor, isNull);
  });

  test(
    'rejects a page with a tool result whose call is outside the window',
    () async {
      final fs = InMemoryFilesystem();
      final path = '/transcript.jsonl';
      await fs.writeString(
        path,
        [
          _toolCallLine(),
          for (var i = 0; i < 8; i++) _userLine('filler-$i', 'x' * 80),
          _toolResultLine(),
          _userLine('tail', 'newest'),
        ].join(),
      );
      final page = await _claudeReader(
        fs,
        path,
        windowSizes: const [180],
      ).readLatest(ctx: _ctxFor(fs), limit: 1);

      expect(
        page,
        isNull,
        reason: 'an unclosed tool dependency must use full-parse fallback',
      );
    },
  );

  test(
    'rejects a Codex custom tool result whose call is outside the window',
    () async {
      final fs = InMemoryFilesystem();
      const path = '/transcript.jsonl';
      await fs.writeString(
        path,
        [
          for (var i = 0; i < 8; i++)
            '{"type":"event_msg","payload":{"type":"item_started"}}\n',
          '{"type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"call-1","output":"result"}}\n',
        ].join(),
      );
      final page = await JsonlTranscriptPageReader(
        fs: fs,
        lineAppend: appendCodexJsonlEvent,
        fallbackPrefix: 'codex',
        decodeEvents: _syncDecoder(),
        sourcePath: (_) async => path,
        windowSizes: const [160],
      ).readLatest(ctx: _ctxFor(fs), limit: 1);

      expect(page, isNull);
    },
  );

  test('keeps an arbitrary adjacent assistant run on one page', () async {
    final fs = InMemoryFilesystem();
    final path = '/transcript.jsonl';
    await fs.writeString(
      path,
      '${_assistantLine('a1', 'one')}'
      '${_assistantLine('a2', 'two')}'
      '${_assistantLine('a3', 'three')}'
      '${_userLine('u1', 'done')}',
    );
    final page = await _claudeReader(
      fs,
      path,
    ).readLatest(ctx: _ctxFor(fs), limit: 2);

    expect(page, isNotNull);
    expect(
      [
        for (final message in page!.messages)
          [
            for (final part in message.parts)
              if (part is AiTextPart) part.text,
          ],
      ],
      [
        ['one', 'two', 'three'],
        ['done'],
      ],
    );
  });

  test(
    'rejects a page when an assistant run begins before its window',
    () async {
      final fs = InMemoryFilesystem();
      final path = '/transcript.jsonl';
      await fs.writeString(
        path,
        [
          _userLine('u1', 'prefix'),
          for (var i = 0; i < 4; i++) _assistantLine('a$i', 'x' * 50),
        ].join(),
      );

      final page = await _claudeReader(
        fs,
        path,
        windowSizes: const [120],
      ).readLatest(ctx: _ctxFor(fs), limit: 1);

      expect(
        page,
        isNull,
        reason:
            'a truncated assistant run cannot be equivalent to full parsing',
      );
    },
  );

  test(
    'rejects a page when noise precedes a truncated assistant run',
    () async {
      final fs = InMemoryFilesystem();
      const path = '/transcript.jsonl';
      await fs.writeString(
        path,
        [
          _userLine('u1', 'prefix'),
          _assistantLine('a1', 'x' * 50),
          '{"type":"progress","message":{"id":"noise"}}\n',
          _assistantLine('a2', 'x' * 50),
        ].join(),
      );

      final page = await _claudeReader(
        fs,
        path,
        windowSizes: const [120],
      ).readLatest(ctx: _ctxFor(fs), limit: 1);

      expect(page, isNull);
    },
  );

  test('invalidates a cursor when an earlier same-size line changes', () async {
    final fs = InMemoryFilesystem();
    final path = '/transcript.jsonl';
    final original = [
      _userLine('u1', '11111'),
      _userLine('u2', '22222'),
      _userLine('u3', '33333'),
      _userLine('u4', '44444'),
    ].join();
    await fs.writeString(path, original);
    final reader = _claudeReader(fs, path);
    final latest = await reader.readLatest(ctx: _ctxFor(fs), limit: 1);
    expect(latest, isNotNull);
    await fs.writeString(
      path,
      original.replaceFirst('"content":"11111"', '"content":"aaaaa"'),
    );

    expect(
      await reader.readOlder(
        ctx: _ctxFor(fs),
        cursor: latest!.nextCursor!,
        limit: 1,
      ),
      isNull,
    );
  });

  test('page model rejects contradictory older metadata', () {
    expect(
      () => AiHistoryPage(
        messages: const [],
        hasOlder: true,
        nextCursor: null,
        sourceToken: 'source',
        rebuilt: false,
      ),
      throwsArgumentError,
    );
  });

  test('Claude and flashskyai pages match their full adapters', () async {
    final fixture = [
      _userLine('u1', 'hello'),
      _assistantLine('a1', 'part one'),
      _assistantLine('a1', 'part two'),
      _userLine('u2', 'bye'),
    ].join();
    for (final setup in [
      (
        prefix: 'claude',
        adapter: const ClaudeAiTranscriptAdapter(),
        append: appendClaudeJsonlEvent,
      ),
      (
        prefix: 'flashskyai',
        adapter: const FlashskyaiAiTranscriptAdapter(),
        append: appendClaudeJsonlEvent,
      ),
    ]) {
      final fs = InMemoryFilesystem();
      const path = '/transcript.jsonl';
      await fs.writeString(path, fixture);
      final reader = JsonlTranscriptPageReader(
        fs: fs,
        lineAppend: setup.append,
        fallbackPrefix: setup.prefix,
        decodeEvents: _syncDecoder(),
        sourcePath: (_) async => path,
      );
      final page = await reader.readLatest(ctx: _ctxFor(fs), limit: 2);
      final full = await setup.adapter.parse(
        AiTranscriptBundle(
          adapterId: setup.prefix,
          fragments: [
            AiTranscriptFragment(
              name: 'fixture.jsonl',
              bytes: utf8.encode(fixture),
            ),
          ],
        ),
      );
      expect(page, isNotNull);
      final older = await reader.readOlder(
        ctx: _ctxFor(fs),
        cursor: page!.nextCursor!,
        limit: 2,
      );
      expect(older, isNotNull);
      expect(
        _messageShapes([...older!.messages, ...page.messages]),
        _messageShapes(full),
      );
    }
  });

  test(
    'Cursor latest and older pages match full adapter with tool parts',
    () async {
      const fixture =
          '{"role":"user","message":{"id":"u1","content":"hello"}}\n'
          '{"role":"assistant","message":{"id":"a1","content":['
          '{"type":"text","text":"answer"},'
          '{"type":"tool_use","id":"call-1","name":"read","input":{"path":"x"}}]}}\n'
          '{"role":"assistant","message":{"id":"a2","content":"after tool"}}\n'
          '{"role":"user","message":{"id":"u2","content":"bye"}}\n';
      final fs = InMemoryFilesystem();
      const path = '/transcript.jsonl';
      await fs.writeString(path, fixture);
      final reader = JsonlTranscriptPageReader(
        fs: fs,
        lineAppend: appendCursorJsonlEvent,
        fallbackPrefix: 'cursor',
        decodeEvents: _syncDecoder(),
        sourcePath: (_) async => path,
      );
      final latest = await reader.readLatest(ctx: _ctxFor(fs), limit: 2);
      final full = await const CursorAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'cursor',
          fragments: [
            AiTranscriptFragment(
              name: 'fixture.jsonl',
              bytes: utf8.encode(fixture),
            ),
          ],
        ),
      );
      expect(latest, isNotNull);
      final older = await reader.readOlder(
        ctx: _ctxFor(fs),
        cursor: latest!.nextCursor!,
        limit: 2,
      );
      expect(older, isNotNull);
      expect(
        latest.messages.first.parts.whereType<AiTextPart>().map(
          (part) => part.text,
        ),
        ['answer', 'after tool'],
        reason: 'adjacent Cursor assistant fragments must remain one turn',
      );
      expect(
        _messageShapes([...older!.messages, ...latest.messages]),
        _messageShapes(full),
      );
    },
  );

  test('Cursor pages match the full adapter including tool parts', () async {
    const fixture =
        '{"role":"user","message":{"id":"u1","content":"hello"}}\n'
        '{"role":"assistant","message":{"id":"a1","content":['
        '{"type":"text","text":"answer"},'
        '{"type":"tool_use","id":"call-1","name":"read","input":{"path":"x"}}]}}\n';
    final fs = InMemoryFilesystem();
    const path = '/transcript.jsonl';
    await fs.writeString(path, fixture);
    final reader = JsonlTranscriptPageReader(
      fs: fs,
      lineAppend: appendCursorJsonlEvent,
      fallbackPrefix: 'cursor',
      decodeEvents: _syncDecoder(),
      sourcePath: (_) async => path,
    );
    final page = await reader.readLatest(ctx: _ctxFor(fs), limit: 2);
    final full = await const CursorAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'cursor',
        fragments: [
          AiTranscriptFragment(
            name: 'fixture.jsonl',
            bytes: utf8.encode(fixture),
          ),
        ],
      ),
    );
    expect(page, isNotNull);
    expect(_messageShapes(page!.messages), _messageShapes(full));
  });

  test('Codex fallback-id fixture safely uses the full adapter', () async {
    const fixture =
        '{"type":"event_msg","payload":{"type":"user_message",'
        '"message":"hello"}}\n'
        '{"type":"event_msg","payload":{"type":"agent_message",'
        '"message":"answer"}}\n';
    final fs = InMemoryFilesystem();
    const path = '/transcript.jsonl';
    await fs.writeString(path, fixture);
    final reader = JsonlTranscriptPageReader(
      fs: fs,
      lineAppend: appendCodexJsonlEvent,
      fallbackPrefix: 'codex',
      decodeEvents: _syncDecoder(),
      sourcePath: (_) async => path,
    );
    final page = await reader.readLatest(ctx: _ctxFor(fs), limit: 2);
    final full = await const CodexAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'codex',
        fragments: [
          AiTranscriptFragment(
            name: 'fixture.jsonl',
            bytes: utf8.encode(fixture),
          ),
        ],
      ),
    );
    expect(full.map((message) => message.id), ['codex-0', 'codex-1']);
    expect(page, isNotNull);
    expect(page!.messages.map((message) => message.id), ['codex-0', 'codex-1']);
  });

  test('uses stat source version without a full-transcript read', () async {
    final fs = _VersionedInMemoryFilesystem();
    const path = '/transcript.jsonl';
    await fs.writeString(
      path,
      '${_userLine('u1', 'one')}${_userLine('u2', 'two')}',
    );
    final page = await _claudeReader(
      fs,
      path,
    ).readLatest(ctx: _ctxFor(fs), limit: 1);

    expect(page, isNotNull);
    final older = await _claudeReader(
      fs,
      path,
    ).readOlder(ctx: _ctxFor(fs), cursor: page!.nextCursor!, limit: 1);
    expect(older, isNotNull);
    expect(fs.fullReadCount, 0);
  });

  test('returns null when stat has no stable source version', () async {
    final fs = test_fs.InMemoryFilesystem();
    const path = '/transcript.jsonl';
    await fs.writeString(path, _userLine('u1', 'one'));

    expect(
      await _claudeReader(fs, path).readLatest(ctx: _ctxFor(fs), limit: 1),
      isNull,
    );
  });

  test('returns null for a second-precision stat source version', () async {
    final fs = _SecondPrecisionInMemoryFilesystem();
    const path = '/transcript.jsonl';
    await fs.writeString(
      path,
      '${_userLine('u1', 'one')}${_userLine('u2', 'two')}',
    );

    expect(
      await _claudeReader(fs, path).readLatest(ctx: _ctxFor(fs), limit: 1),
      isNull,
    );
    expect(fs.fullReadCount, 0);
  });

  test('uses an injected stable version for a coarse stat backend', () async {
    final fs = _SecondPrecisionInMemoryFilesystem();
    const path = '/transcript.jsonl';
    await fs.writeString(
      path,
      '${_userLine('u1', 'one')}${_userLine('u2', 'two')}',
    );
    final reader = JsonlTranscriptPageReader(
      fs: fs,
      lineAppend: appendClaudeJsonlEvent,
      fallbackPrefix: 'claude',
      decodeEvents: _syncDecoder(),
      sourcePath: (_) async => path,
      sourceVersion: (_, _) async => fs.sourceVersion,
    );
    final latest = await reader.readLatest(ctx: _ctxFor(fs), limit: 1);

    expect(latest, isNotNull);
    expect(
      await reader.readOlder(
        ctx: _ctxFor(fs),
        cursor: latest!.nextCursor!,
        limit: 1,
      ),
      isNotNull,
    );
    await fs.writeString(
      path,
      '${_userLine('u1', 'ONE')}${_userLine('u2', 'two')}',
    );
    expect(
      await reader.readOlder(
        ctx: _ctxFor(fs),
        cursor: latest.nextCursor!,
        limit: 1,
      ),
      isNull,
    );
    expect(fs.fullReadCount, 0);
  });
}

String _userLine(String id, String text) =>
    '{"type":"user","uuid":"$id","message":{"id":"$id","content":"$text"}}\n';

String _assistantLine(String id, String text) =>
    '{"type":"assistant","uuid":"$id","message":{"id":"$id","content":"$text"}}\n';

String _toolCallLine() =>
    '{"type":"assistant","uuid":"call-message","message":{"id":"call-message","content":[{"type":"tool_use","id":"call-1","name":"read","input":{"path":"x"}}]}}\n';

String _toolResultLine() =>
    '{"type":"user","uuid":"result-message","message":{"id":"result-message","content":[{"type":"tool_result","tool_use_id":"call-1","content":"result"}]}}\n';

List<String> _texts(List<AiMessage> messages) => [
  for (final message in messages)
    for (final part in message.parts)
      if (part is AiTextPart) part.text,
];

JsonlTranscriptPageReader _claudeReader(
  Filesystem fs,
  String path, {
  List<int> windowSizes = const [64 * 1024, 256 * 1024],
}) => JsonlTranscriptPageReader(
  fs: fs,
  lineAppend: appendClaudeJsonlEvent,
  fallbackPrefix: 'claude',
  decodeEvents: _syncDecoder(),
  sourcePath: (_) async => path,
  windowSizes: windowSizes,
);

SessionHistoryContext _ctxFor(Filesystem fs) => SessionHistoryContext(
  fs: fs,
  taskId: 'task',
  env: const {},
  transcriptRoots: const [],
  bucket: 'bucket',
);

List<List<Object?>> _messageShapes(List<AiMessage> messages) => [
  for (final message in messages)
    [
      message.id,
      message.role,
      [
        for (final part in message.parts)
          if (part is AiTextPart)
            ['text', part.text]
          else if (part is AiReasoningPart)
            ['reasoning', part.text]
          else if (part is AiToolCallPart)
            ['tool', part.toolCallId, part.toolName, part.args, part.result],
      ],
    ],
];

class InMemoryFilesystem extends test_fs.InMemoryFilesystem {
  DateTime _mtime = DateTime.utc(2026, 8, 27);

  void _advanceVersion() {
    _mtime = _mtime.add(const Duration(microseconds: 1));
  }

  @override
  Future<FsStat> stat(String path) async {
    final current = await super.stat(path);
    return current.isFile
        ? FsStat(kind: current.kind, size: current.size, mtime: _mtime)
        : current;
  }

  @override
  Future<void> writeString(String path, String content) async {
    await super.writeString(path, content);
    _advanceVersion();
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    await super.writeBytes(path, bytes);
    _advanceVersion();
  }
}

final class _VersionedInMemoryFilesystem extends InMemoryFilesystem {
  int fullReadCount = 0;

  @override
  Future<List<int>?> readBytes(String path) async {
    fullReadCount++;
    return super.readBytes(path);
  }

  @override
  Future<List<int>?> readBytesRange(String path, int offset, int length) async {
    final bytes = byteFiles[path] ?? files[path]?.codeUnits;
    if (bytes == null) return null;
    if (offset >= bytes.length) return <int>[];
    return bytes.sublist(offset, (offset + length).clamp(0, bytes.length));
  }
}

final class _SecondPrecisionInMemoryFilesystem
    extends test_fs.InMemoryFilesystem {
  final DateTime _mtime = DateTime.utc(2026, 8, 27);
  var _version = 0;
  int fullReadCount = 0;

  String get sourceVersion => 'version-$_version';

  @override
  Future<FsStat> stat(String path) async {
    final current = await super.stat(path);
    return current.isFile
        ? FsStat(kind: current.kind, size: current.size, mtime: _mtime)
        : current;
  }

  @override
  Future<void> writeString(String path, String content) async {
    await super.writeString(path, content);
    _version++;
  }

  @override
  Future<List<int>?> readBytes(String path) async {
    fullReadCount++;
    return super.readBytes(path);
  }

  @override
  Future<List<int>?> readBytesRange(String path, int offset, int length) async {
    final bytes = byteFiles[path] ?? files[path]?.codeUnits;
    if (bytes == null) return null;
    if (offset >= bytes.length) return <int>[];
    return bytes.sublist(offset, (offset + length).clamp(0, bytes.length));
  }
}
