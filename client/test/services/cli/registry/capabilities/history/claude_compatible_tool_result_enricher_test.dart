import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_jsonl.dart';
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
    ClaudeCompatibleToolResultEnricher? enricher,
    String? sourceToken,
  }) {
    return (enricher ?? ClaudeCompatibleToolResultEnricher()).enrich(
      messages: messages,
      ctx: ctx(),
      rootTranscriptPath: rootTranscriptPath,
      bundle: bundle,
      sourceToken: sourceToken,
    );
  }

  String truncatedUserLine({
    required String toolUseId,
    required String stdout,
  }) {
    return jsonEncode({
      'type': 'user',
      'message': {
        'role': 'user',
        'content': [
          {
            'tool_use_id': toolUseId,
            'type': 'tool_result',
            'content': 'tool output truncated',
            'is_error': false,
          },
        ],
      },
      'toolUseResult': {'stdout': stdout, 'stderr': '', 'exitCode': 0},
    });
  }

  ({
    ClaudeCompatibleToolResultEnricher enricher,
    int Function() batches,
    int Function() lines,
  }) countingEnricher() {
    var batches = 0;
    var lines = 0;
    final enricher = ClaudeCompatibleToolResultEnricher(
      decodeLines: (rawLines) {
        batches++;
        lines += rawLines.length;
        return [
          for (final line in rawLines) tryDecodeJsonlLine(line),
        ];
      },
    );
    return (enricher: enricher, batches: () => batches, lines: () => lines);
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

  group('matchesTruncationMarker', () {
    test('matches the sentinel case-insensitively', () {
      final enricher = ClaudeCompatibleToolResultEnricher();
      expect(enricher.matchesTruncationMarker('tool output truncated'), isTrue);
      expect(enricher.matchesTruncationMarker('TOOL OUTPUT TRUNCATED'), isTrue);
      expect(enricher.matchesTruncationMarker('full output here'), isFalse);
    });
  });

  group('tool-result index cache', () {
    test('reuses tool result index for unchanged transcript', () async {
      final counted = countingEnricher();
      final line = truncatedUserLine(toolUseId: 'call_02', stdout: 'from cache');
      final jsonl = '$line\n';
      final bundle = AiTranscriptBundle(
        adapterId: 'claude',
        fragments: [
          AiTranscriptFragment(
            name: 'session.jsonl',
            bytes: utf8.encode(jsonl),
          ),
        ],
      );
      const token = 'session.jsonl|v1|1';

      final first = await enrich(
        messages: truncatedBashMessage(),
        bundle: bundle,
        enricher: counted.enricher,
        sourceToken: token,
      );
      expect((first.single.parts.single as AiToolCallPart).result, 'from cache');
      expect(counted.batches(), 1);
      expect(counted.lines(), 1);

      final second = await enrich(
        messages: truncatedBashMessage(),
        bundle: bundle,
        enricher: counted.enricher,
        sourceToken: token,
      );
      expect((second.single.parts.single as AiToolCallPart).result, 'from cache');
      expect(
        counted.batches(),
        1,
        reason: 'unchanged transcript must not re-decode or re-index',
      );
      expect(counted.lines(), 1);
    });

    test('indexes only the appended transcript portion', () async {
      final counted = countingEnricher();
      final firstLine = truncatedUserLine(
        toolUseId: 'call_02',
        stdout: 'first',
      );
      final firstJsonl = '$firstLine\n';
      const identity = 'session.jsonl';

      await enrich(
        messages: truncatedBashMessage(),
        bundle: AiTranscriptBundle(
          adapterId: 'claude',
          fragments: [
            AiTranscriptFragment(
              name: 'session.jsonl',
              bytes: utf8.encode(firstJsonl),
            ),
          ],
        ),
        enricher: counted.enricher,
        sourceToken: '$identity|t1|${utf8.encode(firstJsonl).length}',
      );
      expect(counted.batches(), 1);
      expect(counted.lines(), 1);

      final secondLine = truncatedUserLine(
        toolUseId: 'call_03',
        stdout: 'appended',
      );
      final appendedJsonl = '$firstJsonl$secondLine\n';
      final appended = await enrich(
        messages: truncatedBashMessage(toolCallId: 'call_03'),
        bundle: AiTranscriptBundle(
          adapterId: 'claude',
          fragments: [
            AiTranscriptFragment(
              name: 'session.jsonl',
              bytes: utf8.encode(appendedJsonl),
            ),
          ],
        ),
        enricher: counted.enricher,
        sourceToken: '$identity|t2|${utf8.encode(appendedJsonl).length}',
      );
      expect(
        (appended.single.parts.single as AiToolCallPart).result,
        'appended',
      );
      expect(counted.batches(), 2);
      expect(
        counted.lines(),
        2,
        reason: 'append must decode only the new line, not the prefix',
      );
    });

    test('rebuilds tool result index when transcript is rewritten', () async {
      final counted = countingEnricher();
      final original = '${truncatedUserLine(toolUseId: 'call_02', stdout: 'old')}\n'
          '${truncatedUserLine(toolUseId: 'call_extra', stdout: 'extra')}\n';
      const identity = 'session.jsonl';

      await enrich(
        messages: truncatedBashMessage(),
        bundle: AiTranscriptBundle(
          adapterId: 'claude',
          fragments: [
            AiTranscriptFragment(
              name: 'session.jsonl',
              bytes: utf8.encode(original),
            ),
          ],
        ),
        enricher: counted.enricher,
        sourceToken: '$identity|t1|${utf8.encode(original).length}',
      );
      expect(counted.lines(), 2);

      final rewritten =
          '${truncatedUserLine(toolUseId: 'call_02', stdout: 'rewritten')}\n';
      final result = await enrich(
        messages: truncatedBashMessage(),
        bundle: AiTranscriptBundle(
          adapterId: 'claude',
          fragments: [
            AiTranscriptFragment(
              name: 'session.jsonl',
              bytes: utf8.encode(rewritten),
            ),
          ],
        ),
        enricher: counted.enricher,
        sourceToken: '$identity|t2|${utf8.encode(rewritten).length}',
      );
      expect(
        (result.single.parts.single as AiToolCallPart).result,
        'rewritten',
      );
      expect(counted.batches(), 2);
      expect(
        counted.lines(),
        3,
        reason: 'rewrite/shrink must discard the index and decode the new file',
      );
    });

    test('canReuseIndex follows path identity used by enrich', () async {
      final counted = countingEnricher();
      final jsonl =
          '${truncatedUserLine(toolUseId: 'call_02', stdout: 'from path')}\n';
      final bytes = utf8.encode(jsonl);
      final path = await writeJsonl('session.jsonl', jsonl);
      const loaderToken = '2026-01-01T00:00:00.000Z';

      await enrich(
        messages: truncatedBashMessage(),
        rootTranscriptPath: path,
        bundle: AiTranscriptBundle(
          adapterId: 'claude',
          fragments: [
            AiTranscriptFragment(name: 'session.jsonl', bytes: bytes),
          ],
        ),
        enricher: counted.enricher,
        sourceToken: loaderToken,
      );
      expect(counted.batches(), 1);
      expect(
        counted.enricher.canReuseIndex(
          sourceToken: loaderToken,
          rootTranscriptPath: path,
          contentLength: bytes.length,
        ),
        isTrue,
      );

      await enrich(
        messages: truncatedBashMessage(),
        rootTranscriptPath: path,
        bundle: AiTranscriptBundle(
          adapterId: 'claude',
          fragments: [
            AiTranscriptFragment(name: 'session.jsonl', bytes: bytes),
          ],
        ),
        enricher: counted.enricher,
        sourceToken: loaderToken,
      );
      expect(
        counted.batches(),
        1,
        reason: 'path identity plus loader token must reuse the index',
      );
    });
  });
}
