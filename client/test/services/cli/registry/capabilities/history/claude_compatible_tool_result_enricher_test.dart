import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_tool_result_enricher.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_history_context.dart';

void main() {
  late Directory tmp;
  late LocalFilesystem fs;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('claude_compatible_enricher_');
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

  Future<String> writeJsonl(String name, String content) async {
    final path = fs.pathContext.join(tmp.path, name);
    await fs.writeString(path, content);
    return path;
  }

  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    String? rootTranscriptPath,
    AiTranscriptBundle? bundle,
  }) {
    return const ClaudeCompatibleToolResultEnricher().enrich(
      messages: messages,
      ctx: ctx(),
      rootTranscriptPath: rootTranscriptPath,
      bundle: bundle,
    );
  }

  List<AiMessage> truncatedBashMessage({
    String toolCallId = 'call_02',
    String result = 'tool output truncated',
    bool isError = false,
  }) {
    return [
      AiMessage(
        id: 'm1',
        role: AiRole.assistant,
        parts: [
          AiToolCallPart(
            toolCallId: toolCallId,
            toolName: 'Bash',
            args: {'command': 'pwd'},
            result: result,
            status: AiToolCallStatus.complete,
            isError: isError,
          ),
        ],
      ),
    ];
  }

  group('ClaudeCompatibleToolResultEnricher', () {
    test(
      'replaces truncated map toolUseResult with stdout and stderr',
      () async {
        final path = await writeJsonl(
          'truncated_map.jsonl',
          '''
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"call_02","type":"tool_result","content":"tool output truncated","is_error":false}]},"toolUseResult":{"stdout":"line1\\nline2","stderr":"err line","exitCode":1,"isTruncated":true}}
''',
        );

        final enriched = await enrich(
          messages: truncatedBashMessage(),
          rootTranscriptPath: path,
        );
        final part = enriched.single.parts.single as AiToolCallPart;

        expect(part.result, 'line1\nline2\nerr line');
        expect(part.isError, isTrue);
        expect(part.status, AiToolCallStatus.complete);
      },
    );

    test('replaces truncated result with string toolUseResult', () async {
      final path = await writeJsonl(
        'truncated_string.jsonl',
        '''
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"call_02","type":"tool_result","content":"tool output truncated","is_error":false}]},"toolUseResult":"Error: file not found"}
''',
      );

      final enriched = await enrich(
        messages: truncatedBashMessage(),
        rootTranscriptPath: path,
      );
      final part = enriched.single.parts.single as AiToolCallPart;

      expect(part.result, 'Error: file not found');
      expect(part.isError, isFalse);
    });

    test('leaves full non-truncated result unchanged', () async {
      final path = await writeJsonl(
        'full_result.jsonl',
        '''
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"call_02","type":"tool_result","content":"full output here","is_error":false}]},"toolUseResult":{"stdout":"ignored","stderr":"","exitCode":0}}
''',
      );

      final enriched = await enrich(
        messages: truncatedBashMessage(result: 'full output here'),
        rootTranscriptPath: path,
      );
      final part = enriched.single.parts.single as AiToolCallPart;

      expect(part.result, 'full output here');
    });

    test('leaves truncated result unchanged when toolUseResult is absent', () async {
      final path = await writeJsonl(
        'truncated_no_side.jsonl',
        '''
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"call_02","type":"tool_result","content":"tool output truncated","is_error":false}]}}
''',
      );

      final enriched = await enrich(
        messages: truncatedBashMessage(),
        rootTranscriptPath: path,
      );
      final part = enriched.single.parts.single as AiToolCallPart;

      expect(part.result, 'tool output truncated');
    });

    test('reads transcript bytes from bundle fragments when provided', () async {
      const jsonl = '''
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"call_02","type":"tool_result","content":"tool output truncated","is_error":false}]},"toolUseResult":{"stdout":"from bundle","stderr":"","exitCode":0}}
''';

      final enriched = await enrich(
        messages: truncatedBashMessage(),
        bundle: AiTranscriptBundle(
          adapterId: 'claude',
          fragments: [
            AiTranscriptFragment(
              name: 'session.jsonl',
              bytes: utf8.encode(jsonl),
            ),
          ],
        ),
      );
      final part = enriched.single.parts.single as AiToolCallPart;

      expect(part.result, 'from bundle');
    });

    test('uses stdout only when stderr is empty', () async {
      final path = await writeJsonl(
        'stdout_only.jsonl',
        '''
{"type":"user","message":{"role":"user","content":[{"tool_use_id":"call_02","type":"tool_result","content":"tool output truncated","is_error":false}]},"toolUseResult":{"stdout":"only stdout","stderr":"","exitCode":0}}
''',
      );

      final enriched = await enrich(
        messages: truncatedBashMessage(),
        rootTranscriptPath: path,
      );
      final part = enriched.single.parts.single as AiToolCallPart;

      expect(part.result, 'only stdout');
      expect(part.isError, isFalse);
    });
  });
}
