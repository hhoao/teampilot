import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/history/cursor_ai_transcript.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_history_capability.dart';
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
  });

  test('locateCursorTranscript returns null when missing', () async {
    final bundle = await locateCursorTranscript(ctx(configDir: base.path));
    expect(bundle, isNull);
  });
}
