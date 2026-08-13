import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/tool_output_backfill_enricher.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_history_context.dart';

void main() {
  late Directory tmp;
  late LocalFilesystem fs;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('opencode_backfill_');
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

  Future<String> writeToolOutput(String name, String content) async {
    final path = fs.pathContext.join(tmp.path, name);
    await fs.writeString(path, content);
    return path;
  }

  String placeholderResult({
    required String hintPath,
    String marker = '...120935 bytes truncated...',
    String preview = 'preview line',
  }) {
    return '$preview\n\n$marker\n\n'
        'The tool call succeeded but the output was truncated. Full output saved to:\n'
        '$hintPath\n'
        'Use Grep to search the full content or Read with offset/limit to view specific sections.';
  }

  List<AiMessage> truncatedWebfetchMessage({
    required String result,
    bool isError = false,
  }) {
    return [
      AiMessage(
        id: 'm1',
        role: AiRole.assistant,
        parts: [
          AiToolCallPart(
            toolCallId: 'tool_1',
            toolName: 'webfetch',
            args: const {'url': 'https://example.com'},
            result: result,
            status: AiToolCallStatus.complete,
            isError: isError,
          ),
        ],
      ),
    ];
  }

  Future<List<AiMessage>> enrich({
    required List<AiMessage> messages,
    SessionHistoryContext? context,
  }) {
    return const OpencodeToolOutputBackfillEnricher().enrich(
      messages: messages,
      ctx: context ?? ctx(),
      rootTranscriptPath: null,
      bundle: null,
    );
  }

  group('OpencodeToolOutputBackfillEnricher', () {
    test('backfills full output read from the hint path', () async {
      final hintPath = await writeToolOutput(
        'tool_1',
        'full webfetch output\nsecond line\n第三行',
      );

      final enriched = await enrich(
        messages: truncatedWebfetchMessage(
          result: placeholderResult(hintPath: hintPath),
        ),
      );
      final part = enriched.single.parts.single as AiToolCallPart;

      expect(part.result, 'full webfetch output\nsecond line\n第三行');
      expect(part.status, AiToolCallStatus.complete);
      expect(part.isError, isFalse);
      expect(part.result, isNot(contains('truncated')));
    });

    test('backfills the lines-truncated variant', () async {
      final hintPath = await writeToolOutput('tool_2', 'line1\nline2');

      final enriched = await enrich(
        messages: truncatedWebfetchMessage(
          result: placeholderResult(
            hintPath: hintPath,
            marker: '...42 lines truncated...',
          ),
        ),
      );
      final part = enriched.single.parts.single as AiToolCallPart;

      expect(part.result, 'line1\nline2');
    });

    test('preserves isError when backfilling', () async {
      final hintPath = await writeToolOutput('tool_3', 'error body');

      final enriched = await enrich(
        messages: truncatedWebfetchMessage(
          result: placeholderResult(hintPath: hintPath),
          isError: true,
        ),
      );
      final part = enriched.single.parts.single as AiToolCallPart;

      expect(part.result, 'error body');
      expect(part.isError, isTrue);
    });

    test('keeps placeholder when hint path file is missing', () async {
      final missing = fs.pathContext.join(tmp.path, 'tool_gone');

      final messages = truncatedWebfetchMessage(
        result: placeholderResult(hintPath: missing),
      );
      final enriched = await enrich(messages: messages);
      final part = enriched.single.parts.single as AiToolCallPart;

      expect(part.result, (messages.single.parts.single as AiToolCallPart).result);
      expect(part.result, contains('...120935 bytes truncated...'));
    });

    test('keeps placeholder when result has no saved-to hint', () async {
      final messages = truncatedWebfetchMessage(
        result: 'preview\n\n...5 lines truncated...\n\n'
            'The tool call succeeded but the output was truncated.',
      );
      final enriched = await enrich(messages: messages);
      final part = enriched.single.parts.single as AiToolCallPart;

      expect(part.result, (messages.single.parts.single as AiToolCallPart).result);
    });

    test('keeps placeholder when ctx is null', () async {
      final messages = truncatedWebfetchMessage(
        result: placeholderResult(hintPath: tmp.path),
      );
      final enriched = await enrich(messages: messages, context: null);
      final part = enriched.single.parts.single as AiToolCallPart;

      expect(part.result, (messages.single.parts.single as AiToolCallPart).result);
    });

    test('leaves non-truncated results untouched', () async {
      final messages = truncatedWebfetchMessage(result: 'plain output');
      final enriched = await enrich(messages: messages);
      final part = enriched.single.parts.single as AiToolCallPart;

      expect(part.result, 'plain output');
    });
  });
}
