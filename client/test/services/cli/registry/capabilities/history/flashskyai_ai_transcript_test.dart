import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/flashskyai/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/tool_call_resolvers.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory base;
  final fs = LocalFilesystem();

  setUp(() async {
    base = await Directory.systemTemp.createTemp('flashskyai_ai_transcript_');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  SessionHistoryContext ctx({
    required List<String> transcriptRoots,
    String bucket = 'home-me-proj',
    String taskId = 'task-1',
  }) {
    return SessionHistoryContext(
      fs: fs,
      taskId: taskId,
      env: const {},
      transcriptRoots: transcriptRoots,
      bucket: bucket,
    );
  }

  test(
    'FlashskyaiAiTranscriptAdapter parses text and correlates tool_result',
    () async {
      final bytes = await File(
        'test/fixtures/session_history/flashskyai/basic.jsonl',
      ).readAsBytes();
      final adapter = const FlashskyaiAiTranscriptAdapter();
      final messages = await adapter.parse(
        AiTranscriptBundle(
          adapterId: adapter.id,
          fragments: [
            AiTranscriptFragment(name: 'basic.jsonl', bytes: bytes),
          ],
        ),
      );

      expect(adapter.id, 'flashskyai');
      expect(messages, hasLength(2));

      final user = messages[0];
      expect(user.id, 'u-1');
      expect(user.role, AiRole.user);
      expect((user.parts.single as AiTextPart).text, 'hello flashsky');
      expect(user.createdAt, DateTime.parse('2026-07-10T11:00:00.000Z'));

      final assistant = messages[1];
      expect(assistant.id, 'a-1');
      expect(assistant.role, AiRole.assistant);
      expect((assistant.parts[0] as AiTextPart).text, 'hi from flashsky');
      final tool = assistant.parts.whereType<AiToolCallPart>().single;
      expect(tool.toolCallId, 'toolu_fs1');
      expect(tool.toolName, 'Bash');
      expect(tool.args, {'command': 'pwd'});
      expect(tool.result, '/tmp');

      expect(messages.any((m) => m.id == 'u-2'), isFalse);
      for (final m in messages.where((m) => m.role == AiRole.user)) {
        expect(m.parts.whereType<AiToolCallPart>(), isEmpty);
      }
    },
  );

  test(
    'G1: shared parser assigns flashskyai fallback ids only to consumed events',
    () async {
      // Same compatible_jsonl.dart parser as claude; the fallback prefix is
      // the per-CLI adapter wiring. Full-parse fallback sequence must be
      // strictly sequential over consumed messages (noise skipped).
      final bytes = utf8.encode('''
{"type":"user","message":{"role":"user","content":"first"},"timestamp":"2026-07-10T11:00:00.000Z"}
not-json
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"second"}]},"timestamp":"2026-07-10T11:00:01.000Z"}
{"type":"queue-operation","operation":"enqueue"}
''');
      final messages = await const FlashskyaiAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'flashskyai',
          fragments: [
            AiTranscriptFragment(name: 'fallback.jsonl', bytes: bytes),
          ],
        ),
      );
      expect(messages.map((m) => m.id).toList(), ['flashskyai-0', 'flashskyai-1']);
    },
  );

  test(
    'G3: encrypted thinking and id-less tool_use share claude semantics',
    () async {
      // Same shared parser: empty thinking discarded, id-less tool_use
      // skipped — both must hold identically through the flashskyai adapter.
      final bytes = utf8.encode('''
{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":null},{"type":"tool_use","name":"Bash","input":{"command":"ls"}},{"type":"text","text":"ok"}]},"uuid":"a-1"}
''');
      final messages = await const FlashskyaiAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'flashskyai',
          fragments: [
            AiTranscriptFragment(name: 'shared.jsonl', bytes: bytes),
          ],
        ),
      );
      final asst = messages.single;
      expect(asst.parts.whereType<AiReasoningPart>(), isEmpty);
      expect(asst.parts.whereType<AiToolCallPart>(), isEmpty);
      expect((asst.parts.single as AiTextPart).text, 'ok');
    },
  );

  test('locateFlashskyaiTranscript returns bundle under workspaces', () async {
    final workspaces = p.join(base.path, 'workspaces', 'home-me-proj');
    await Directory(workspaces).create(recursive: true);
    final fixture = await File(
      'test/fixtures/session_history/flashskyai/basic.jsonl',
    ).readAsBytes();
    await File(p.join(workspaces, 'task-1.jsonl')).writeAsBytes(fixture);

    final bundle = await locateFlashskyaiTranscript(
      ctx(transcriptRoots: [base.path]),
    );

    expect(bundle, isNotNull);
    expect(bundle!.adapterId, 'flashskyai');
    expect(bundle.fragments, hasLength(1));
    expect(bundle.fragments.single.name, 'task-1.jsonl');
    expect(bundle.fragments.single.bytes, fixture);
  });

  test('locateFlashskyaiTranscript prefers projects over workspaces', () async {
    // Real ~/.flashskyai layout uses projects/, not workspaces/.
    final projects = p.join(base.path, 'projects', 'home-me-proj');
    await Directory(projects).create(recursive: true);
    final fixture = await File(
      'test/fixtures/session_history/flashskyai/basic.jsonl',
    ).readAsBytes();
    await File(p.join(projects, 'task-1.jsonl')).writeAsBytes(fixture);

    final bundle = await locateFlashskyaiTranscript(
      ctx(transcriptRoots: [base.path]),
    );

    expect(bundle, isNotNull);
    expect(bundle!.fragments.single.bytes, fixture);
  });

  test('locateFlashskyaiTranscript returns null when missing', () async {
    final bundle = await locateFlashskyaiTranscript(
      ctx(transcriptRoots: [base.path]),
    );
    expect(bundle, isNull);
  });

  test('merges streamed tool_use lines sharing message.id', () async {
    final bytes = await File(
      'test/fixtures/session_history/flashskyai/streamed_tools.jsonl',
    ).readAsBytes();
    final messages = await const FlashskyaiAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'flashskyai',
        fragments: [
          AiTranscriptFragment(name: 'streamed_tools.jsonl', bytes: bytes),
        ],
      ),
    );

    expect(messages, hasLength(2));
    expect(messages[0].role, AiRole.user);
    expect((messages[0].parts.single as AiTextPart).text, 'superpowers');

    final asst = messages[1];
    expect(asst.id, 'msg_d32cf90b-b4a0-4d9a-bb95-ad60ef2de28d');
    final tools = asst.parts.whereType<AiToolCallPart>().toList();
    expect(tools.map((t) => t.toolName), ['Read', 'Read', 'Bash']);
    expect(tools[0].args, {'file_path': '/tmp/demo/SKILL.md'});
    expect(tools[1].isError, isTrue);
    expect(tools[1].status, AiToolCallStatus.complete);
    expect(tools[2].result, 'tool output truncated');
  });

  test(
    'G-5 真实夹具：subagents Edit{file_path,old_string,new_string,replace_all} '
    '经 adapter + resolver 全链路解析出 hunk',
    () async {
      // Task 6 fix round：夹具来自本机真实数据（2026-08-13 补扫
      // ~/.flashskyai/projects/*/*/subagents/*.jsonl 共 16 条真实 Edit
      // tool_use，键 {file_path, old_string, new_string, replace_all}——
      // 与共享 str-replace codec 键集完全吻合；此前只扫根层漏了
      // subagents/ 子目录）。内容取自真实事件（已全量脱敏：id/slug/cwd/
      // 会话正文 → 占位/中性文本；file_path 保持 /tmp/demo 风格，与
      // cursor 夹具标准一致）。
      final bytes = await File(
        'test/fixtures/session_history/flashskyai/edit_real.jsonl',
      ).readAsBytes();
      final messages = await const FlashskyaiAiTranscriptAdapter().parse(
        AiTranscriptBundle(
          adapterId: 'flashskyai',
          fragments: [
            AiTranscriptFragment(name: 'edit_real.jsonl', bytes: bytes),
          ],
        ),
      );

      final tools = messages
          .expand((m) => m.parts)
          .whereType<AiToolCallPart>()
          .toList();
      expect(tools.map((t) => t.toolName), ['Edit', 'Edit']);

      const flashskyai = FlashskyaiToolCallResolvers();
      for (final tool in tools) {
        final target = flashskyai.editResolver.resolve(tool);
        expect(target, isNotNull,
            reason: 'flashskyai Edit 真实键形应经共享 str-replace codec 解析');
        expect(target!.hunk.path, '/tmp/demo/session-memory/summary.md');
        expect(target.hunk.removedCount, greaterThan(0));
        expect(target.hunk.addedCount, greaterThan(0));
      }
    },
  );
}
