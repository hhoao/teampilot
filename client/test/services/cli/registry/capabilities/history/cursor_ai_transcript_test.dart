import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/cursor/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/cursor/capabilities/tool_call_resolvers.dart';
import 'package:teampilot/services/session/ai_history_watch_meta.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory base;
  final fs = LocalFilesystem();

  setUp(() async {
    base = await Directory.systemTemp.createTemp('cursor_ai_transcript_');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  SessionHistoryContext ctx({
    required String configDir,
    String? persistedNativeId,
  }) {
    return SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: {'CURSOR_CONFIG_DIR': configDir},
      transcriptRoots: const [],
      bucket: '',
      persistedNativeId: persistedNativeId,
    );
  }

  Future<void> copyFixtureTree() async {
    final fixtureRoot = Directory('test/fixtures/session_history/cursor');
    await for (final entity in fixtureRoot.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: fixtureRoot.path);
      final dest = File(p.join(base.path, rel));
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(await entity.readAsBytes());
    }
  }

  test(
    'CursorAiTranscriptAdapter parses role content and correlates tool_result',
    () async {
      final bytes = await File(
        'test/fixtures/session_history/cursor/projects/home-me-proj/'
        'agent-transcripts/chat-aaaa-bbbb-cccc-dddd/'
        'chat-aaaa-bbbb-cccc-dddd.jsonl',
      ).readAsBytes();
      final adapter = const CursorAiTranscriptAdapter();
      final messages = await adapter.parse(
        AiTranscriptBundle(
          adapterId: adapter.id,
          fragments: [
            AiTranscriptFragment(
              name: 'chat-aaaa-bbbb-cccc-dddd.jsonl',
              bytes: bytes,
            ),
          ],
        ),
      );

      expect(adapter.id, 'cursor');
      expect(messages, hasLength(2));

      final user = messages[0];
      expect(user.role, AiRole.user);
      expect((user.parts.single as AiTextPart).text, 'hello cursor');

      final asst = messages[1];
      expect(asst.role, AiRole.assistant);
      expect(
        asst.parts.whereType<AiTextPart>().single.text,
        'hi from cursor',
      );
      final tool = asst.parts.whereType<AiToolCallPart>().single;
      expect(tool.toolCallId, 'toolu_c1');
      expect(tool.toolName, 'Shell');
      expect(tool.args, {'command': 'pwd'});
      expect(tool.result, '/tmp/proj');

      for (final m in messages.where((m) => m.role == AiRole.user)) {
        expect(m.parts.whereType<AiToolCallPart>(), isEmpty);
      }
    },
  );

  test(
    'parses tool_use without id and drops [REDACTED] text sentinel',
    () async {
      // Mirrors real Cursor agent-transcripts: tool_use often has no id,
      // and a literal [REDACTED] text block sits next to the tools.
      const raw = '''
{"role":"assistant","message":{"content":[{"type":"text","text":"先查 working→idle\\n\\n[REDACTED]"},{"type":"tool_use","name":"Grep","input":{"pattern":"workingSessionIds"}},{"type":"tool_use","name":"Read","input":{"path":"/tmp/a.dart"}}]}}
{"role":"assistant","message":{"content":[{"type":"text","text":"[REDACTED]"},{"type":"tool_use","name":"Shell","input":{"command":"pwd"}}]}}
''';
      final messages = await const CursorAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'cursor',
          fragments: [
            AiTranscriptFragment(name: 't.jsonl', bytes: utf8.encode(raw)),
          ],
        ),
      );

      // Consecutive assistant lines merge into one turn.
      expect(messages, hasLength(1));
      expect(messages.single.parts.whereType<AiTextPart>().single.text,
          '先查 working→idle');
      expect(
        messages.single.parts.whereType<AiToolCallPart>().map((t) => t.toolName),
        ['Grep', 'Read', 'Shell'],
      );
    },
  );

  test(
    'unwraps Cursor <user_query> and strips <timestamp>',
    () async {
      const raw = '''
{"role":"user","message":{"content":[{"type":"text","text":"<timestamp>Sat</timestamp>\\n<user_query>\\nhello world\\n</user_query>"}]}}
''';
      final messages = await const CursorAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'cursor',
          fragments: [
            AiTranscriptFragment(name: 'u.jsonl', bytes: utf8.encode(raw)),
          ],
        ),
      );
      expect(messages, hasLength(1));
      expect((messages.single.parts.single as AiTextPart).text, 'hello world');
    },
  );

  test(
    'parses TeamPilot runtime agent-transcript (no tool id, split lines)',
    () async {
      final bytes = await File(
        'test/fixtures/session_history/cursor/agent_transcript_no_tool_id.jsonl',
      ).readAsBytes();
      final messages = await const CursorAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'cursor',
          fragments: [
            AiTranscriptFragment(
              name: 'agent_transcript_no_tool_id.jsonl',
              bytes: bytes,
            ),
          ],
        ),
      );

      expect(messages, hasLength(2));
      expect(messages[0].role, AiRole.user);
      expect(
        (messages[0].parts.single as AiTextPart).text,
        'hello',
      );

      final asst = messages[1];
      expect(asst.role, AiRole.assistant);
      expect(asst.parts.whereType<AiToolCallPart>().single.toolName, 'Read');
      expect(
        asst.parts.whereType<AiTextPart>().single.text,
        '你好。需要我帮你做什么？',
      );
    },
  );

  test(
    'message id priority is uuid -> event id -> message.id -> lazy '
    'fallback cursor-{seq} (G1)',
    () async {
      // Cursor's own id policy differs from claude/flashskyai (event-level
      // uuid/id first, message.id only as third channel). Real parent-facing
      // transcripts carry none of these (all-message.content scan), so the
      // chain is defensive and the contract only requires uniqueness +
      // incremental/full consistency (same appendCursorJsonlEvent both ways,
      // lazy fallback). Priority order is thus an established per-CLI policy.
      const raw = '''
{"role":"user","uuid":"uuid-wins","message":{"id":"mid","content":"a"}}
{"role":"user","id":"evt-id","message":{"id":"mid2","content":"b"}}
{"role":"user","message":{"id":"mid3","content":"c"}}
{"role":"assistant","message":{"content":"[REDACTED]"}}
{"role":"user","message":{"content":"d"}}
''';
      final messages = await const CursorAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'cursor',
          fragments: [
            AiTranscriptFragment(name: 'ids.jsonl', bytes: utf8.encode(raw)),
          ],
        ),
      );

      expect(messages.map((m) => m.id), [
        'uuid-wins',
        'evt-id',
        'mid3',
        'cursor-0',
      ]);
      // Discarded event (whole [REDACTED]) must not consume a fallback seq.
      expect(messages.last.parts.single, isA<AiTextPart>());
      expect((messages.last.parts.single as AiTextPart).text, 'd');
    },
  );

  test(
    'thinking blocks produce no reasoning part; [REDACTED] never surfaces '
    '(G3)',
    () async {
      // Cursor parent-facing transcripts have no thinking blocks: a scan of
      // 100+ real agent-transcripts found zero `type: "thinking"` — thinking
      // is replaced by a literal `[REDACTED]` placeholder. So "no thinking ->
      // no AiReasoningPart" is the established semantic (unlike claude's
      // thinking -> AiReasoningPart), and [REDACTED] must never surface as
      // user-visible text.
      const raw = '''
{"role":"assistant","message":{"content":[{"type":"thinking","thinking":"internal plan"},{"type":"text","text":"visible answer"}]}}
{"role":"assistant","message":{"content":[{"type":"thinking","text":"draft"},{"type":"text","text":"[REDACTED]"}]}}
''';
      final messages = await const CursorAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'cursor',
          fragments: [
            AiTranscriptFragment(name: 'thinking.jsonl', bytes: utf8.encode(raw)),
          ],
        ),
      );

      expect(messages.whereType<AiMessage>().expand((m) => m.parts),
          isNot(contains(isA<AiReasoningPart>())));
      expect(messages, hasLength(1));
      expect((messages.single.parts.single as AiTextPart).text,
          'visible answer');
    },
  );

  test(
    'id-less tool_use gets non-empty synthetic {messageId}-tool-{seq} '
    'toolCallId (G4)',
    () async {
      // Real cursor agent-transcripts omit tool_use ids (verified: zero
      // tool_use `id` fields across real transcripts), so the synthetic id is
      // the normal path — the contract requires a non-empty toolCallId so
      // tool_result can still correlate.
      const raw = '''
{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Grep","input":{}},{"type":"tool_use","id":"toolu_x","name":"Read","input":{}},{"type":"tool_use","name":"Shell","input":{}}]}}
''';
      final messages = await const CursorAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'cursor',
          fragments: [
            AiTranscriptFragment(name: 'tools.jsonl', bytes: utf8.encode(raw)),
          ],
        ),
      );

      final tools = messages.single.parts.cast<AiToolCallPart>();
      expect(tools.map((t) => t.toolCallId),
          ['cursor-0-tool-0', 'toolu_x', 'cursor-0-tool-1']);
      expect(tools.map((t) => t.toolCallId).toSet(), hasLength(3));
    },
  );

  test('non-Map tool input yields args null, never a bare string (G2)',
      () async {
    const raw = '''
{"role":"assistant","message":{"content":[{"type":"tool_use","name":"Shell","input":"pwd"},{"type":"tool_use","name":"Read","input":{"path":"a"}}]}}
''';
    final messages = await const CursorAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'cursor',
        fragments: [
          AiTranscriptFragment(name: 'args.jsonl', bytes: utf8.encode(raw)),
        ],
      ),
    );

    final tools = messages.single.parts.cast<AiToolCallPart>();
    expect(tools[0].args, isNull);
    expect(tools[1].args, {'path': 'a'});
  });

  test('ApplyPatch 字符串 input 保留到 argsText（FREEFORM，Task 6 G-4 重校）',
      () async {
    // 本机实测（2026-08-13 ~/.cursor 扫描）：ApplyPatch 的 input 为 patch
    // 原始文本（`*** Begin Patch` / `*** Update File:`，76 次），此前
    // adapter 仅保留 args（非 Map → null）导致 freeform 无法解析；现
    // argsText 保留字符串供 unified-diff codec freeform 分支使用。
    const raw = '''
{"role":"assistant","message":{"content":[{"type":"tool_use","name":"ApplyPatch","input":"*** Begin Patch\\n*** Update File: lib/a.dart\\n@@\\n-old\\n+new\\n*** End Patch"}]}}
''';
    final messages = await const CursorAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'cursor',
        fragments: [
          AiTranscriptFragment(name: 'patch.jsonl', bytes: utf8.encode(raw)),
        ],
      ),
    );

    final tool = messages.single.parts.cast<AiToolCallPart>().single;
    expect(tool.args, isNull);
    expect(tool.argsText, contains('*** Update File: lib/a.dart'));
  });

  test(
    'fixture: chat-strreplace-write（真实键形 StrReplace/Write/ApplyPatch）'
    '经 adapter + resolver 全链路解析出 hunk',
    () async {
      // Task 6 G-4 夹具增补：工具行来自本机实测键形（2026-08-13
      // ~/.cursor agent-transcripts 扫描），消除 spl 散文级证据降级。
      final bytes = await File(
        'test/fixtures/session_history/cursor/projects/home-me-proj/'
        'agent-transcripts/chat-strreplace-write/chat-strreplace-write.jsonl',
      ).readAsBytes();
      final messages = await const CursorAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'cursor',
          fragments: [
            AiTranscriptFragment(
              name: 'chat-strreplace-write.jsonl',
              bytes: bytes,
            ),
          ],
        ),
      );

      final tools = messages
          .expand((m) => m.parts)
          .whereType<AiToolCallPart>()
          .toList();
      expect(tools.map((t) => t.toolName),
          ['StrReplace', 'Write', 'ApplyPatch']);

      const cursor = CursorToolCallResolvers();
      final strTarget = cursor.editResolver.resolve(tools[0]);
      expect(strTarget, isNotNull, reason: 'StrReplace 真实键形应解析');
      expect(strTarget!.hunk.path, '/home/x/lib/a.dart');
      expect(strTarget.hunk.removedCount, 1);
      expect(strTarget.hunk.addedCount, 1);

      final writeTarget = cursor.editResolver.resolve(tools[1]);
      expect(writeTarget, isNotNull, reason: 'Write 真实键形应解析');
      expect(writeTarget!.hunk.path, '/home/x/lib/new.dart');
      expect(writeTarget.hunk.addedCount, 2);

      final patchTarget = cursor.editResolver.resolve(tools[2]);
      expect(patchTarget, isNotNull, reason: 'ApplyPatch freeform 应解析');
      expect(patchTarget!.hunk.path, '/home/x/lib/b.dart');
      expect(patchTarget.hunk.addedCount, 1);
      expect(patchTarget.hunk.removedCount, 1);
    },
  );

  test('locateCursorTranscript returns agent-transcripts jsonl', () async {
    await copyFixtureTree();
    final fixture = await File(
      'test/fixtures/session_history/cursor/projects/home-me-proj/'
      'agent-transcripts/chat-aaaa-bbbb-cccc-dddd/'
      'chat-aaaa-bbbb-cccc-dddd.jsonl',
    ).readAsBytes();

    final bundle = await locateCursorTranscript(
      ctx(
        configDir: base.path,
        persistedNativeId: 'chat-aaaa-bbbb-cccc-dddd',
      ),
    );

    expect(bundle, isNotNull);
    expect(bundle!.adapterId, 'cursor');
    expect(bundle.fragments, hasLength(1));
    expect(bundle.fragments.single.name, 'chat-aaaa-bbbb-cccc-dddd.jsonl');
    expect(bundle.fragments.single.bytes, fixture);

    final watchMeta = AiHistoryWatchMeta.fromHints(bundle.hints);
    expect(
      watchMeta?.changeWatchRoot,
      p.join(base.path, 'projects', 'home-me-proj'),
    );
    expect(bundle.hints['cacheToken'], contains('shell-pwd.txt'));
    expect(bundle.hints['cacheToken'], isNot(contains('terminals:empty')));
  });

  test('locateCursorTranscript cacheToken changes when terminal file added',
      () async {
    await copyFixtureTree();
    final context = ctx(
      configDir: base.path,
      persistedNativeId: 'chat-aaaa-bbbb-cccc-dddd',
    );

    final before = await locateCursorTranscript(context);
    expect(before, isNotNull);
    final tokenBefore = before!.hints['cacheToken'];

    final terminalsDir = p.join(base.path, 'projects', 'home-me-proj', 'terminals');
    await Directory(terminalsDir).create(recursive: true);
    await File(p.join(terminalsDir, '1.txt')).writeAsString('''
---
pid: 1
command: "echo hi"
started_at: 2026-07-29T10:00:00.000Z
---
hello
''');

    final after = await locateCursorTranscript(context);
    expect(after, isNotNull);
    final tokenAfter = after!.hints['cacheToken'];

    expect(tokenAfter, isNot(equals(tokenBefore)));
    expect(tokenAfter, contains('terminals'));
    expect(tokenAfter, isNot(contains('terminals:empty')));
  });

  test('locateCursorTranscript returns null when missing', () async {
    final bundle = await locateCursorTranscript(ctx(configDir: base.path));
    expect(bundle, isNull);
  });
}
