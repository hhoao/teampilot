import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/history/flashskyai_ai_transcript.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_history_capability.dart';
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
      expect(messages, hasLength(3));

      final user = messages[0];
      expect(user.id, 'u-1');
      expect(user.role, AiRole.user);
      expect((user.parts.single as AiTextPart).text, 'hello flashsky');
      expect(user.createdAt, DateTime.parse('2026-07-10T11:00:00.000Z'));

      final hi = messages[1];
      expect(hi.id, 'a-1');
      expect(hi.role, AiRole.assistant);
      expect((hi.parts.single as AiTextPart).text, 'hi from flashsky');

      final toolMsg = messages[2];
      expect(toolMsg.id, 'a-2');
      expect(toolMsg.role, AiRole.assistant);
      final tool = toolMsg.parts.whereType<AiToolCallPart>().single;
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

  test('locateFlashskyaiTranscript returns null when missing', () async {
    final bundle = await locateFlashskyaiTranscript(
      ctx(transcriptRoots: [base.path]),
    );
    expect(bundle, isNull);
  });
}
