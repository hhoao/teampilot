import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/terminal_tool_result_enricher.dart';
import 'package:teampilot/services/ai_history/tool_call_resolvers.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_history_context.dart';

void main() {
  late Directory tmp;
  late LocalFilesystem fs;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cursor_terminal_enricher_');
    fs = LocalFilesystem();
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  SessionHistoryContext ctx() => SessionHistoryContext(
    fs: fs,
    taskId: 'task-1',
    env: const {},
    transcriptRoots: const [],
    bucket: 'bucket',
  );

  String buildTranscriptPath({String project = 'project', String chatId = 'chat'}) {
    return fs.pathContext.join(
      tmp.path,
      project,
      'agent-transcripts',
      chatId,
      '$chatId.jsonl',
    );
  }

  Future<void> writeTerminal(
    String relativePath,
    String content,
  ) async {
    final path = fs.pathContext.join(tmp.path, relativePath);
    await fs.ensureDir(fs.pathContext.dirname(path));
    await fs.writeString(path, content);
  }

  String terminalFile({
    required String command,
    String? title,
    required String body,
    int? exitCode,
    String startedAt = '2026-07-29T10:00:00.000Z',
    String? endedAt,
  }) {
    final trailer = exitCode != null
        ? '''
---
exit_code: $exitCode
elapsed_ms: 150
ended_at: ${endedAt ?? '2026-07-29T10:00:00.150Z'}
---
'''
        : '';
    return '''
---
pid: 12345
command: "$command"
title: "${title ?? command}"
status: succeeded
started_at: $startedAt
---
$body
$trailer''';
  }

  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    required String rootTranscriptPath,
  }) {
    return const CursorTerminalToolResultEnricher(
        shellResolver: ConfigurableAiShellToolTargetResolver(
          toolNames: {
            'bash', 'shell', 'shell_command', 'exec_command',
            'run_shell_command', 'run_terminal_cmd', 'execute',
          },
        ),
      ).enrich(
      messages: messages,
      ctx: ctx(),
      rootTranscriptPath: rootTranscriptPath,
      bundle: null,
    );
  }

  group('CursorTerminalToolResultEnricher', () {
    test('fills shell result from matching description and command', () async {
      final root = buildTranscriptPath();
      await writeTerminal(
        'project/terminals/1.txt',
        terminalFile(
          command: 'git status',
          title: 'git status',
          body: 'On branch main',
        ),
      );

      final messages = [
        AiMessage(
          id: 'm1',
          role: AiRole.assistant,
          parts: [
            AiToolCallPart(
              toolCallId: 't1',
              toolName: 'Shell',
              args: {
                'command': 'git status',
                'description': 'git status',
              },
            ),
          ],
        ),
      ];

      final enriched = await enrich(messages: messages, rootTranscriptPath: root);
      final part = enriched.single.parts.single as AiToolCallPart;

      expect(part.result, 'On branch main');
      expect(part.status, AiToolCallStatus.complete);
      expect(part.isError, isFalse);
    });

    test('does not overwrite existing non-blank result', () async {
      final root = buildTranscriptPath();
      await writeTerminal(
        'project/terminals/1.txt',
        terminalFile(command: 'echo hi', body: 'terminal body'),
      );

      final messages = [
        AiMessage(
          id: 'm1',
          role: AiRole.assistant,
          parts: [
            AiToolCallPart(
              toolCallId: 't1',
              toolName: 'Shell',
              args: {'command': 'echo hi'},
              result: 'already here',
            ),
          ],
        ),
      ];

      final enriched = await enrich(messages: messages, rootTranscriptPath: root);
      final part = enriched.single.parts.single as AiToolCallPart;

      expect(part.result, 'already here');
    });

    test('sets isError when exit_code is not zero', () async {
      final root = buildTranscriptPath();
      await writeTerminal(
        'project/terminals/1.txt',
        terminalFile(
          command: 'false',
          body: 'command failed',
          exitCode: 1,
        ),
      );

      final messages = [
        AiMessage(
          id: 'm1',
          role: AiRole.assistant,
          parts: [
            AiToolCallPart(
              toolCallId: 't1',
              toolName: 'Shell',
              args: {'command': 'false'},
            ),
          ],
        ),
      ];

      final enriched = await enrich(messages: messages, rootTranscriptPath: root);
      final part = enriched.single.parts.single as AiToolCallPart;

      expect(part.result, 'command failed');
      expect(part.isError, isTrue);
      expect(part.status, AiToolCallStatus.complete);
    });

    test('binds each terminal file at most once in message order', () async {
      final root = buildTranscriptPath();
      await writeTerminal(
        'project/terminals/1.txt',
        terminalFile(command: 'echo one', body: 'first terminal'),
      );
      await writeTerminal(
        'project/terminals/2.txt',
        terminalFile(command: 'echo two', body: 'second terminal'),
      );

      final messages = [
        AiMessage(
          id: 'm1',
          role: AiRole.assistant,
          parts: [
            AiToolCallPart(
              toolCallId: 't1',
              toolName: 'Shell',
              args: {'command': 'echo one'},
            ),
            AiToolCallPart(
              toolCallId: 't2',
              toolName: 'Shell',
              args: {'command': 'echo two'},
            ),
          ],
        ),
      ];

      final enriched = await enrich(messages: messages, rootTranscriptPath: root);
      final parts = enriched.single.parts.cast<AiToolCallPart>();

      expect(parts[0].result, 'first terminal');
      expect(parts[1].result, 'second terminal');
    });

    test('returns unchanged when terminals directory is missing', () async {
      final root = buildTranscriptPath();
      final messages = [
        AiMessage(
          id: 'm1',
          role: AiRole.assistant,
          parts: [
            AiToolCallPart(
              toolCallId: 't1',
              toolName: 'Shell',
              args: {'command': 'echo hi'},
            ),
          ],
        ),
      ];

      final enriched = await enrich(messages: messages, rootTranscriptPath: root);
      final part = enriched.single.parts.single as AiToolCallPart;

      expect(part.result, isNull);
    });

    test('treats whitespace-only result as missing and fills', () async {
      final root = buildTranscriptPath();
      await writeTerminal(
        'project/terminals/1.txt',
        terminalFile(command: 'echo hi', body: 'filled output'),
      );

      final messages = [
        AiMessage(
          id: 'm1',
          role: AiRole.assistant,
          parts: [
            AiToolCallPart(
              toolCallId: 't1',
              toolName: 'Shell',
              args: {'command': 'echo hi'},
              result: '   \n  ',
            ),
          ],
        ),
      ];

      final enriched = await enrich(messages: messages, rootTranscriptPath: root);
      final part = enriched.single.parts.single as AiToolCallPart;

      expect(part.result, 'filled output');
      expect(part.status, AiToolCallStatus.complete);
    });
  });
}
