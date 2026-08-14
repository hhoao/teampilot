@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/opencode/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_history_context.dart';

void main() {
  const realDbPath =
      '/home/hhoa/.local/share/com.hhoa.teampilot/workspace/workspaces/d938aa90-e26f-46bd-be4a-427faea59e5f/sessions/9112ec0e-98e1-4809-8cf9-145553355cea/runtime/opencode/opencode.db';
  const persistedId = 'ses_00b123825ffekTr4iYGfG9KXQO';

  test(
    'repro: locate + parse the stuck session DB',
    () async {
      final dir = await Directory.systemTemp.createTemp('tp-repro-');
      addTearDown(() => dir.delete(recursive: true));
      final copied = '${dir.path}/opencode.db';
      File(realDbPath).copySync(copied);
      if (File('$realDbPath-wal').existsSync()) {
        File('$realDbPath-wal').copySync('$copied-wal');
      }
      if (File('$realDbPath-shm').existsSync()) {
        File('$realDbPath-shm').copySync('$copied-shm');
      }

      final ctx = SessionHistoryContext(
        fs: LocalFilesystem(),
        taskId: '9112ec0e-98e1-4809-8cf9-145553355cea',
        env: {'OPENCODE_DB': copied},
        transcriptRoots: const [],
        bucket: 'workspace',
        persistedNativeId: persistedId,
        workspaceId: 'd938aa90-e26f-46bd-be4a-427faea59e5f',
        sessionId: '9112ec0e-98e1-4809-8cf9-145553355cea',
      );

      final stopwatch = Stopwatch()..start();
      final bundle = await locateOpencodeTranscript(ctx);
      expect(bundle, isNotNull, reason: 'locate should find the transcript');
      // ignore: avoid_print
      print('[repro] locate took ${stopwatch.elapsedMilliseconds}ms '
          'fragments=${bundle?.fragments.length}');
      final messages = await const OpencodeAiTranscriptAdapter().parse(bundle!);
      // ignore: avoid_print
      print('[repro] parse took ${stopwatch.elapsedMilliseconds}ms '
          'messages=${messages.length}');

      final cap = const OpencodeAiHistoryCapability();
      final token = await cap.liveCacheToken(ctx);
      // ignore: avoid_print
      print('[repro] liveCacheToken=$token');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
