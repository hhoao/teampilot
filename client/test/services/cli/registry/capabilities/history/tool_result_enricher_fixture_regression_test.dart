import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/registry/capabilities/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/history/builtin_ai_history_capabilities.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_watch_meta.dart';
import 'package:teampilot/services/session/session_history_context.dart';

void main() {
  late Directory base;
  final fs = LocalFilesystem();

  setUp(() async {
    base = await Directory.systemTemp.createTemp(
      'tool_result_enricher_fixture_',
    );
    final fixtureRoot = Directory('test/fixtures/session_history/cursor');
    await for (final entity in fixtureRoot.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: fixtureRoot.path);
      final dest = File(p.join(base.path, rel));
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(await entity.readAsBytes());
    }
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  SessionHistoryContext cursorCtx({required String chatId}) {
    return SessionHistoryContext(
      fs: fs,
      taskId: 'task-1',
      env: {'CURSOR_CONFIG_DIR': base.path},
      transcriptRoots: const [],
      bucket: '',
      persistedNativeId: chatId,
    );
  }

  Future<List<AiMessage>> parseAndEnrich({
    required AiHistoryCapability cap,
    required AiTranscriptBundle bundle,
    required SessionHistoryContext ctx,
  }) async {
    final messages = await cap.adapter.parse(bundle);
    final watch = AiHistoryWatchMeta.fromHints(bundle.hints);
    String? parentPath;
    for (final path in watch?.cacheTokenPaths ?? const <String>[]) {
      final trimmed = path.trim();
      if (trimmed.isNotEmpty) {
        parentPath = trimmed;
        break;
      }
    }
    return cap.toolResultEnricher.enrich(
      messages: messages,
      ctx: ctx,
      rootTranscriptPath: parentPath,
      bundle: bundle,
    );
  }

  test(
    'Cursor fixture: Shell without tool_result enriches stdout from terminals',
    () async {
      const cap = CursorAiHistoryCapability(
        shellResolver: DefaultAiShellToolTargetResolver(),
      );
      const chatId = 'chat-shell-missing-result';

      final bundle = await locateCursorTranscript(cursorCtx(chatId: chatId));
      expect(bundle, isNotNull);

      final enriched = await parseAndEnrich(
        cap: cap,
        bundle: bundle!,
        ctx: cursorCtx(chatId: chatId),
      );

      final shell = enriched
          .expand((m) => m.parts)
          .whereType<AiToolCallPart>()
          .single;
      expect(shell.toolName, 'Shell');
      expect(shell.args?['command'], 'pwd');
      expect(shell.result, '/home/hhoa/proj');
      expect(shell.status, AiToolCallStatus.complete);
      expect(shell.isError, isFalse);
    },
  );

  test('Claude fixture: truncated Bash enriches stdout from toolUseResult', () async {
    const cap = ClaudeAiHistoryCapability();
    final bytes = await File(
      'test/fixtures/session_history/claude/truncated_bash.jsonl',
    ).readAsBytes();
    final bundle = AiTranscriptBundle(
      adapterId: 'claude',
      fragments: [
        AiTranscriptFragment(name: 'truncated_bash.jsonl', bytes: bytes),
      ],
      hints: const AiHistoryWatchMeta(
        changeWatchRoot: '/proj',
        cacheTokenPaths: ['/proj/truncated_bash.jsonl'],
      ).toHints(),
    );

    final enriched = await parseAndEnrich(
      cap: cap,
      bundle: bundle,
      ctx: SessionHistoryContext(
        fs: fs,
        taskId: 'task-1',
        env: const {},
        transcriptRoots: const [],
        bucket: 'bucket',
      ),
    );

    final bash = enriched
        .expand((m) => m.parts)
        .whereType<AiToolCallPart>()
        .single;
    expect(bash.toolName, 'Bash');
    expect(
      bash.result,
      "manpath: can't set the locale; make sure \$LC_* and \$LANG are correct\n"
      'ONBOARDING.md\ndemo-cli\nflashskyai',
    );
    expect(bash.isError, isFalse);
    expect(bash.status, AiToolCallStatus.complete);
  });

  test(
    'flashskyai streamed_tools fixture: truncated Bash enriches stdout',
    () async {
      const cap = FlashskyaiAiHistoryCapability();
      final bytes = await File(
        'test/fixtures/session_history/flashskyai/streamed_tools.jsonl',
      ).readAsBytes();
      final bundle = AiTranscriptBundle(
        adapterId: 'flashskyai',
        fragments: [
          AiTranscriptFragment(name: 'streamed_tools.jsonl', bytes: bytes),
        ],
      );

      final enriched = await parseAndEnrich(
        cap: cap,
        bundle: bundle,
        ctx: SessionHistoryContext(
          fs: fs,
          taskId: 'task-1',
          env: const {},
          transcriptRoots: const [],
          bucket: 'bucket',
        ),
      );

      final bash = enriched
          .expand((m) => m.parts)
          .where((part) => part is AiToolCallPart && part.toolName == 'Bash')
          .cast<AiToolCallPart>()
          .single;
      expect(bash.toolCallId, 'call_02_VW6kZqO7JDda0dvu8J2z2200');
      expect(bash.result, contains('ONBOARDING.md'));
      expect(bash.result, isNot(contains('tool output truncated')));
      expect(bash.status, AiToolCallStatus.complete);
    },
  );
}
