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
      expect(messages, hasLength(2));

      final user = messages[0];
      expect(user.role, AiRole.user);
      expect((user.parts.single as AiTextPart).text, 'list files');
      expect(user.createdAt, DateTime.parse('2026-07-10T12:00:04.000Z'));

      final assistant = messages[1];
      expect(assistant.role, AiRole.assistant);
      expect(assistant.parts[0], isA<AiToolCallPart>());
      expect(assistant.parts[1], isA<AiTextPart>());
      final tool = assistant.parts[0] as AiToolCallPart;
      expect(tool.toolCallId, 'call_1');
      expect(tool.toolName, 'exec_command');
      expect(tool.args, {'cmd': 'ls'});
      expect(tool.result, 'a.txt\nb.txt');
      expect((assistant.parts[1] as AiTextPart).text, 'Here are the files.');

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

  test(
      'parses user/assistant text from response_item.message (codex >=0.147 '
      'rollout format)',
      () async {
    final bytes = await File(
      'test/fixtures/session_history/codex/response_item_messages.jsonl',
    ).readAsBytes();
    final messages = await const CodexAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'codex',
        fragments: [
          AiTranscriptFragment(
            name: 'response_item_messages.jsonl',
            bytes: bytes,
          ),
        ],
      ),
    );

    expect(messages, hasLength(2));

    final user = messages[0];
    expect(user.role, AiRole.user);
    expect((user.parts.single as AiTextPart).text, 'hello');

    final assistant = messages[1];
    expect(assistant.role, AiRole.assistant);
    expect(assistant.parts[0], isA<AiReasoningPart>());
    expect(assistant.parts[1], isA<AiToolCallPart>());
    expect(assistant.parts[2], isA<AiTextPart>());
    final tool = assistant.parts[1] as AiToolCallPart;
    expect(tool.toolCallId, 'call_1');
    expect(tool.toolName, 'exec_command');
    expect(tool.result, 'a.txt\nb.txt');
    expect(
      (assistant.parts[2] as AiTextPart).text,
      'Hello! Here are the files.',
    );

    // System/developer and AGENTS.md+environment_context noise stay filtered.
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
  });

  test(
      'response_item.message echo does not duplicate event_msg user/agent '
      'text (older codex wrote both)',
      () async {
    final bytes = await File(
      'test/fixtures/session_history/codex/response_item_message_echo.jsonl',
    ).readAsBytes();
    final messages = await const CodexAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'codex',
        fragments: [
          AiTranscriptFragment(
            name: 'response_item_message_echo.jsonl',
            bytes: bytes,
          ),
        ],
      ),
    );

    expect(messages, hasLength(2));
    expect(messages[0].role, AiRole.user);
    expect((messages[0].parts.single as AiTextPart).text, 'list files');
    expect(messages[1].role, AiRole.assistant);
    expect(
      (messages[1].parts.single as AiTextPart).text,
      'Here are the files.',
    );
  });

  test('parses reasoning summary and shell_command from real rollout shape',
      () async {
    final bytes = await File(
      'test/fixtures/session_history/codex/reasoning_and_tools.jsonl',
    ).readAsBytes();
    final messages = await const CodexAiTranscriptAdapter().parse(
      AiTranscriptBundle(
        adapterId: 'codex',
        fragments: [
          AiTranscriptFragment(
            name: 'reasoning_and_tools.jsonl',
            bytes: bytes,
          ),
        ],
      ),
    );

    expect(messages, hasLength(2));
    expect(messages[0].role, AiRole.user);
    expect((messages[0].parts.single as AiTextPart).text, 'create issue tracker');

    final assistant = messages[1];
    expect(assistant.role, AiRole.assistant);
    expect(assistant.parts[0], isA<AiReasoningPart>());
    expect(assistant.parts[1], isA<AiToolCallPart>());
    expect(assistant.parts[2], isA<AiTextPart>());

    final reasoning = assistant.parts[0] as AiReasoningPart;
    expect(reasoning.text, contains('Issue management'));

    final tool = assistant.parts[1] as AiToolCallPart;
    expect(tool.toolName, 'shell_command');
    expect(tool.toolCallId, 'call_demo1');
    expect(tool.result, contains('/tmp/demo'));

    expect(
      (assistant.parts[2] as AiTextPart).text,
      'I will inspect the plan first.',
    );
  });
}
