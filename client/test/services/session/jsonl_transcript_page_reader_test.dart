import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_jsonl.dart';
import 'package:teampilot/services/session/ai_history_page.dart';
import 'package:teampilot/services/session/ai_transcript_tail_reader.dart';
import 'package:teampilot/services/session/jsonl_transcript_page_reader.dart';
import 'package:teampilot/services/session/session_history_context.dart';

import '../../support/in_memory_filesystem.dart';

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

  test('fallback ids make the page source unavailable', () async {
    final fs = InMemoryFilesystem();
    final path = '/transcript.jsonl';
    await fs.writeString(path, '{"type":"user","message":{"content":"one"}}\n');
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
}

String _userLine(String id, String text) =>
    '{"type":"user","uuid":"$id","message":{"id":"$id","content":"$text"}}\n';

String _assistantLine(String id, String text) =>
    '{"type":"assistant","uuid":"$id","message":{"id":"$id","content":"$text"}}\n';

List<String> _texts(List<AiMessage> messages) => [
  for (final message in messages)
    for (final part in message.parts)
      if (part is AiTextPart) part.text,
];
