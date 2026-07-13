import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/history/codex_ai_transcript.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory base;
  final fs = LocalFilesystem();

  setUp(() async {
    base = await Directory.systemTemp.createTemp('codex_ai_transcript_');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  SessionHistoryContext ctx({
    required String codexHome,
    String? persistedNativeId,
  }) {
    return SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: {'CODEX_HOME': codexHome},
      transcriptRoots: const [],
      bucket: '',
      persistedNativeId: persistedNativeId,
    );
  }

  Future<void> writeRollout(String codexHome) async {
    final dayDir = p.join(codexHome, 'sessions', '2026', '07', '10');
    await Directory(dayDir).create(recursive: true);
    final fixture = await File(
      'test/fixtures/session_history/codex/basic.jsonl',
    ).readAsBytes();
    await File(
      p.join(
        dayDir,
        'rollout-2026-07-10T12-00-00-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl',
      ),
    ).writeAsBytes(fixture);
  }

  test(
    'CodexAiTranscriptAdapter parses event_msg and correlates function_call',
    () async {
      final bytes = await File(
        'test/fixtures/session_history/codex/basic.jsonl',
      ).readAsBytes();
      final adapter = const CodexAiTranscriptAdapter();
      final messages = await adapter.parse(
        AiTranscriptBundle(
          adapterId: adapter.id,
          fragments: [
            AiTranscriptFragment(name: 'rollout.jsonl', bytes: bytes),
          ],
        ),
      );

      expect(adapter.id, 'codex');
      expect(messages, hasLength(3));

      final user = messages[0];
      expect(user.role, AiRole.user);
      expect((user.parts.single as AiTextPart).text, 'list files');
      expect(user.createdAt, DateTime.parse('2026-07-10T12:00:04.000Z'));

      final toolMsg = messages[1];
      expect(toolMsg.role, AiRole.assistant);
      final tool = toolMsg.parts.whereType<AiToolCallPart>().single;
      expect(tool.toolCallId, 'call_1');
      expect(tool.toolName, 'exec_command');
      expect(tool.args, {'cmd': 'ls'});
      expect(tool.result, 'a.txt\nb.txt');

      final agent = messages[2];
      expect(agent.role, AiRole.assistant);
      expect((agent.parts.single as AiTextPart).text, 'Here are the files.');

      expect(
        messages.any(
          (m) => m.parts.any(
            (p) => p is AiTextPart && p.text.contains('environment_context'),
          ),
        ),
        isFalse,
      );
      expect(
        messages.any(
          (m) => m.parts.any(
            (p) => p is AiTextPart && p.text.contains('developer noise'),
          ),
        ),
        isFalse,
      );
      for (final m in messages.where((m) => m.role == AiRole.user)) {
        expect(m.parts.whereType<AiToolCallPart>(), isEmpty);
      }
    },
  );

  test('locateCodexTranscript returns rollout bytes under CODEX_HOME', () async {
    await writeRollout(base.path);
    final fixture = await File(
      'test/fixtures/session_history/codex/basic.jsonl',
    ).readAsBytes();

    final bundle = await locateCodexTranscript(
      ctx(
        codexHome: base.path,
        persistedNativeId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      ),
    );

    expect(bundle, isNotNull);
    expect(bundle!.adapterId, 'codex');
    expect(bundle.fragments, hasLength(1));
    expect(
      bundle.fragments.single.name,
      'rollout-2026-07-10T12-00-00-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.jsonl',
    );
    expect(bundle.fragments.single.bytes, fixture);
  });

  test('locateCodexTranscript returns null when missing', () async {
    final bundle = await locateCodexTranscript(ctx(codexHome: base.path));
    expect(bundle, isNull);
  });
}
