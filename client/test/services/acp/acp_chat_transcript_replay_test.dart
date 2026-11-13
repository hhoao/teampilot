import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_chat_transcript.dart';
import 'package:teampilot/services/acp/acp_chat_transcript_replay.dart';

import '../../support/in_memory_filesystem.dart';

String _line(Map<String, Object?> entry) => jsonEncode(entry);

/// Counts writes and makes them slow enough for a burst to overlap.
class _SlowFilesystem extends InMemoryFilesystem {
  int writes = 0;

  @override
  Future<void> atomicWrite(String path, String content) async {
    writes++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await super.atomicWrite(path, content);
  }
}

/// Separates full rewrites from appends so tests can assert the hot path
/// never rewrites the transcript.
class _RecordingFilesystem extends InMemoryFilesystem {
  int atomicWrites = 0;
  int appends = 0;
  int appendedBytes = 0;

  @override
  Future<void> atomicWrite(String path, String content) async {
    atomicWrites++;
    await super.atomicWrite(path, content);
  }

  @override
  Future<void> appendString(String path, String content) async {
    appends++;
    appendedBytes += content.length;
    await super.appendString(path, content);
  }
}

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
      _line({'v': 1, 'type': 'user', 'id': 'acp-u-1', 'text': 'hi'}),
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

  test('round-trips TodoWrite args and task category', () {
    final original = [
      AiMessage(
        id: 'acp-a-todo',
        role: AiRole.assistant,
        parts: const [
          AiToolCallPart(
            toolCallId: 'TodoWrite',
            toolName: 'TodoWrite',
            category: AiToolCallCategory.task,
            status: AiToolCallStatus.complete,
            args: {
              'merge': true,
              'todos': [
                {'id': 'a', 'content': 'Task A', 'status': 'completed'},
                {'id': 'b', 'content': 'Task B', 'status': 'pending'},
              ],
            },
          ),
        ],
      ),
    ];
    final loaded = decodeAcpChatTranscript(encodeAcpChatTranscript(original));
    expect(loaded, hasLength(1));
    final part = loaded.single.parts.single as AiToolCallPart;
    expect(part.toolName, 'TodoWrite');
    expect(part.category, AiToolCallCategory.task);
    expect(part.args?['merge'], isTrue);
    expect(part.args?['todos'], [
      {'id': 'a', 'content': 'Task A', 'status': 'completed'},
      {'id': 'b', 'content': 'Task B', 'status': 'pending'},
    ]);
  });

  test('round-trips generate_image filePath in args', () {
    final original = [
      AiMessage(
        id: 'acp-a-img',
        role: AiRole.assistant,
        parts: const [
          AiToolCallPart(
            toolCallId: 'img-1',
            toolName: 'generate_image',
            status: AiToolCallStatus.complete,
            args: {'description': 'a cat', 'filePath': '/tmp/cat.png'},
          ),
        ],
      ),
    ];
    final loaded = decodeAcpChatTranscript(encodeAcpChatTranscript(original));
    final part = loaded.single.parts.single as AiToolCallPart;
    expect(part.toolName, 'generate_image');
    expect(part.args, {'description': 'a cat', 'filePath': '/tmp/cat.png'});
  });

  test('round-trips a tool result so task ids survive a restart', () {
    final original = [
      AiMessage(
        id: 'acp-a-task',
        role: AiRole.assistant,
        parts: const [
          AiToolCallPart(
            toolCallId: 'c1',
            toolName: 'TaskCreate',
            status: AiToolCallStatus.complete,
            args: {'subject': 'Write implementation plan'},
            result: 'Task #6 created successfully: Write implementation plan',
          ),
        ],
      ),
    ];
    final loaded = decodeAcpChatTranscript(encodeAcpChatTranscript(original));
    final part = loaded.single.parts.single as AiToolCallPart;
    expect(part.args, {'subject': 'Write implementation plan'});
    expect(
      part.result,
      'Task #6 created successfully: Write implementation plan',
    );
  });

  test('old tool lines without args or category still decode', () {
    final jsonl = _line({
      'v': 1,
      'type': 'assistant',
      'id': 'acp-a-1',
      'parts': [
        {
          'kind': 'tool',
          'toolCallId': 't1',
          'title': 'Read',
          'status': 'complete',
          'isError': false,
        },
      ],
    });
    final loaded = decodeAcpChatTranscript(jsonl);
    final part = loaded.single.parts.single as AiToolCallPart;
    expect(part.toolCallId, 't1');
    expect(part.toolName, 'Read');
    expect(part.status, AiToolCallStatus.complete);
    expect(part.category, AiToolCallCategory.other);
    expect(part.args, isNull);
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
    expect(fs.files[path], contains('"v":2'));
    expect(fs.files[path], isNot(contains('"type":"chunk"')));
  });

  test('loadMessages treats a missing file as empty', () async {
    final writer = AcpChatTranscriptWriter(
      fs: InMemoryFilesystem(),
      path: '/tp/missing.jsonl',
    );
    expect(await writer.loadMessages(), isEmpty);
  });

  test('saveMessages coalesces a burst into the newest snapshot', () async {
    final fs = _SlowFilesystem();
    const path = '/tp/acp-transcript.jsonl';
    final writer = AcpChatTranscriptWriter(fs: fs, path: path);

    // ACP tool-call updates arrive far faster than a snapshot write; every
    // call must still resolve, but only the newest state needs encoding.
    final saves = [
      for (var i = 0; i < 20; i++)
        writer.saveMessages([
          AiMessage(
            id: 'acp-a-$i',
            role: AiRole.assistant,
            parts: [AiTextPart(text: 'v$i')],
          ),
        ]),
    ];
    await Future.wait(saves);

    expect(fs.writes, lessThan(20));
    final loaded = await writer.loadMessages();
    expect((loaded.single.parts.single as AiTextPart).text, 'v19');
  });

  test('loadMessages waits for an in-flight save', () async {
    final fs = _SlowFilesystem();
    const path = '/tp/acp-transcript.jsonl';
    final writer = AcpChatTranscriptWriter(fs: fs, path: path);

    final save = writer.saveMessages([
      AiMessage(
        id: 'acp-a-1',
        role: AiRole.assistant,
        parts: const [AiTextPart(text: 'streamed')],
      ),
    ]);
    final loaded = await writer.loadMessages();
    await save;
    expect((loaded.single.parts.single as AiTextPart).text, 'streamed');
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

  test('v2 round-trip preserves status and deliveryChannel', () {
    final loaded = decodeAcpChatTranscript(
      encodeAcpChatTranscript([
        const AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: [AiTextPart(text: 'x')],
          status: AiMessageStatus.incomplete,
          deliveryChannel: 'mailbox',
        ),
      ]),
    );
    expect(loaded.single.status, AiMessageStatus.incomplete);
    expect(loaded.single.deliveryChannel, 'mailbox');
  });

  test('decode flags legacy v1 records', () {
    final legacy = encodeAcpChatTranscriptV1([
      const AiMessage(
        id: 'u1',
        role: AiRole.user,
        parts: [AiTextPart(text: 'hi')],
      ),
    ]);
    final result = decodeAcpChatTranscriptResult(legacy);
    expect(result.hasLegacyRecords, isTrue);
    expect(result.messages, hasLength(1));
    expect(
      decodeAcpChatTranscriptResult(
        encodeAcpChatTranscript([]),
      ).hasLegacyRecords,
      isFalse,
    );
  });

  test('mixed v1 and v2 records fold in order', () {
    final legacy = encodeAcpChatTranscriptV1([
      const AiMessage(
        id: 'u1',
        role: AiRole.user,
        parts: [AiTextPart(text: 'hi')],
      ),
    ]);
    final v2 = [
      _line({'v': 2, 'type': 'assistant', 'id': 'a1'}),
      _line({
        'v': 2,
        'type': 'part',
        'mid': 'a1',
        'i': 0,
        'part': {'kind': 'text', 'text': 'Hello'},
      }),
    ].join('\n');
    final loaded = decodeAcpChatTranscript('$legacy\n$v2');
    expect(loaded, hasLength(2));
    expect(loaded.first.id, 'u1');
    expect(loaded.last.id, 'a1');
    expect((loaded.last.parts.single as AiTextPart).text, 'Hello');
  });

  test('legacy v1 transcript is migrated to v2 on the next save', () async {
    final fs = _RecordingFilesystem();
    const path = '/tp/t.jsonl';
    await fs.atomicWrite(
      path,
      encodeAcpChatTranscriptV1([
        const AiMessage(
          id: 'u1',
          role: AiRole.user,
          parts: [AiTextPart(text: 'hi')],
        ),
      ]),
    );
    final writer = AcpChatTranscriptWriter(fs: fs, path: path);
    expect(await writer.loadMessages(), hasLength(1));
    await writer.saveMessages([
      const AiMessage(
        id: 'u1',
        role: AiRole.user,
        parts: [AiTextPart(text: 'hi')],
      ),
      const AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'Hello')],
      ),
    ]);
    final raw = fs.files[path]!;
    expect(raw, isNot(contains('"v":1')));
    expect(raw, contains('"v":2'));
    expect(await writer.loadMessages(), hasLength(2));
  });

  test(
    'delta appends only changed parts without rewriting the prefix',
    () async {
      final fs = _RecordingFilesystem();
      const path = '/tp/t.jsonl';
      final writer = AcpChatTranscriptWriter(fs: fs, path: path);
      final text = AiTextPart(text: 'hello');
      final tool = AiToolCallPart(toolCallId: 't1', toolName: 'Read');
      await writer.saveMessages([
        AiMessage(id: 'a1', role: AiRole.assistant, parts: [text, tool]),
      ]);
      final first = fs.files[path]!;

      await writer.saveMessages([
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: [
            text, // unchanged instance: no record emitted
            tool.copyWith(status: AiToolCallStatus.complete, result: 'ok'),
          ],
        ),
      ]);

      expect(fs.atomicWrites, 1); // only the initial compact write
      expect(fs.appends, 1);
      expect(fs.files[path]!.startsWith(first), isTrue);
      expect(fs.appendedBytes, lessThan(500));
      final loaded = await writer.loadMessages();
      expect(loaded, hasLength(1));
      expect(loaded.single.parts, hasLength(2));
      expect((loaded.single.parts.last as AiToolCallPart).result, 'ok');
    },
  );

  test(
    'streaming text growth appends only suffixes, not cumulative text',
    () async {
      final fs = _RecordingFilesystem();
      const path = '/tp/t.jsonl';
      final writer = AcpChatTranscriptWriter(fs: fs, path: path);
      var text = 'x';
      for (var i = 0; i < 200; i++) {
        await writer.saveMessages([
          AiMessage(
            id: 'a1',
            role: AiRole.assistant,
            parts: [AiTextPart(text: text)],
          ),
        ]);
        text = '${text}y';
      }
      expect(fs.atomicWrites, 1);
      // 200 commits of a 200-char growing part must not write ~200*200 bytes.
      expect(fs.appendedBytes, lessThan(200 * 120));
      final loaded = await writer.loadMessages();
      expect((loaded.single.parts.single as AiTextPart).text, 'x${'y' * 199}');
    },
  );

  test('dropping a message appends a drop record', () async {
    final fs = _RecordingFilesystem();
    const path = '/tp/t.jsonl';
    final writer = AcpChatTranscriptWriter(fs: fs, path: path);
    await writer.saveMessages([
      const AiMessage(
        id: 'u1',
        role: AiRole.user,
        parts: [AiTextPart(text: 'first')],
      ),
    ]);
    await writer.saveMessages([
      const AiMessage(
        id: 'u2',
        role: AiRole.user,
        parts: [AiTextPart(text: 'second')],
      ),
    ]);
    expect(fs.files[path], contains('"type":"drop"'));
    final loaded = await writer.loadMessages();
    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'u2');
    expect((loaded.single.parts.single as AiTextPart).text, 'second');
  });

  test('a no-op save writes nothing', () async {
    final fs = _RecordingFilesystem();
    const path = '/tp/t.jsonl';
    final writer = AcpChatTranscriptWriter(fs: fs, path: path);
    final messages = [
      const AiMessage(
        id: 'u1',
        role: AiRole.user,
        parts: [AiTextPart(text: 'hi')],
      ),
    ];
    await writer.saveMessages(messages);
    final writes = fs.atomicWrites + fs.appends;
    await writer.saveMessages(messages);
    expect(fs.atomicWrites + fs.appends, writes);
  });

  test('compacts the log after the append threshold', () async {
    final fs = _RecordingFilesystem();
    const path = '/tp/t.jsonl';
    final writer = AcpChatTranscriptWriter(
      fs: fs,
      path: path,
      compactAfterAppendedBytes: 200,
    );
    var text = '';
    for (var i = 0; i < 40; i++) {
      text = '${text}chunk-$i;';
      await writer.saveMessages([
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: [AiTextPart(text: text)],
        ),
      ]);
    }
    expect(fs.atomicWrites, greaterThan(1));
    // Compaction collapses duplicate text-delta records.
    expect(fs.files[path]!.length, lessThan(fs.appendedBytes));
    final loaded = await writer.loadMessages();
    expect((loaded.single.parts.single as AiTextPart).text, text);
  });

  test('applies a text delta without rebuilding untouched messages', () {
    final user = const AiMessage(
      id: 'u1',
      role: AiRole.user,
      parts: [AiTextPart(text: 'hi')],
    );
    final assistant = const AiMessage(
      id: 'a1',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'Hel')],
    );
    final previous = [user, assistant];
    final next = [
      user,
      const AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'Hello')],
      ),
    ];
    final records = buildAcpChatTranscriptDelta(previous: previous, next: next);
    expect(records, isNotNull);
    final result = applyAcpChatTranscriptDelta(
      current: previous,
      jsonl: records!.map(_line).join('\n'),
    );
    expect(result.replaceAll, isFalse);
    expect(result.removedIds, isEmpty);
    expect(result.messages, hasLength(1));
    expect((result.messages.single.parts.single as AiTextPart).text, 'Hello');
  });

  test('fullParts makes a text patch idempotent', () {
    final user = const AiMessage(
      id: 'u1',
      role: AiRole.user,
      parts: [AiTextPart(text: 'hi')],
    );
    final assistant = const AiMessage(
      id: 'a1',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'Hel')],
    );
    final next = const AiMessage(
      id: 'a1',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'Hello')],
    );
    final records = buildAcpChatTranscriptDelta(
      previous: [user, assistant],
      next: [user, next],
      fullParts: true,
    );
    expect(records, isNotNull);
    expect(records!.single['type'], 'part');
    final jsonl = records.map(_line).join('\n');

    final once = applyAcpChatTranscriptDelta(
      current: [user, assistant],
      jsonl: jsonl,
    );
    expect((once.messages.single.parts.single as AiTextPart).text, 'Hello');
    final twice = applyAcpChatTranscriptDelta(
      current: [user, once.messages.single],
      jsonl: jsonl,
    );
    expect((twice.messages.single.parts.single as AiTextPart).text, 'Hello');
  });

  test('applies a drop and reports the removed id', () {
    final user = const AiMessage(
      id: 'u1',
      role: AiRole.user,
      parts: [AiTextPart(text: 'hi')],
    );
    final assistant = const AiMessage(
      id: 'a1',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'gone')],
    );
    final records = buildAcpChatTranscriptDelta(
      previous: [user, assistant],
      next: [user],
    );
    final result = applyAcpChatTranscriptDelta(
      current: [user, assistant],
      jsonl: records!.map(_line).join('\n'),
    );
    expect(result.replaceAll, isFalse);
    expect(result.removedIds, {'a1'});
    expect(result.messages, isEmpty);
  });

  test('reset replaces the whole list', () {
    final user = const AiMessage(
      id: 'u1',
      role: AiRole.user,
      parts: [AiTextPart(text: 'hi')],
    );
    final result = applyAcpChatTranscriptDelta(
      current: [user],
      jsonl: '${_line({'v': 2, 'type': 'reset'})}\n',
    );
    expect(result.replaceAll, isTrue);
    expect(result.messages, isEmpty);
  });

  test('reset snapshot drops parts missing from the new snapshot', () {
    final current = [
      const AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: [
          AiTextPart(text: 'one'),
          AiTextPart(text: 'two'),
        ],
      ),
    ];
    final next = [
      const AiMessage(
        id: 'a1',
        role: AiRole.assistant,
        parts: [AiTextPart(text: 'only')],
      ),
    ];
    final result = applyAcpChatTranscriptDelta(
      current: current,
      jsonl:
          '${_line({'v': 2, 'type': 'reset'})}\n'
          '${encodeAcpChatTranscript(next)}',
    );
    expect(result.replaceAll, isTrue);
    expect(result.messages.single.parts, hasLength(1));
    expect((result.messages.single.parts.single as AiTextPart).text, 'only');
  });

  test('reordering is not expressible as a keyed delta', () {
    final a = const AiMessage(
      id: 'a',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'a')],
    );
    final b = const AiMessage(
      id: 'b',
      role: AiRole.assistant,
      parts: [AiTextPart(text: 'b')],
    );
    expect(buildAcpChatTranscriptDelta(previous: [a, b], next: [b, a]), isNull);
  });
}
