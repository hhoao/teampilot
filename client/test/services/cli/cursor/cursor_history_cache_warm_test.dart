import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/cli/cursor/capabilities/history/ai_history_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../support/post_frame_test_harness.dart';

/// Cursor transcripts live under `projects/*/agent-transcripts/`, not the
/// Claude pinned `projects/{bucket}/{sessionId}.jsonl` layout. Live refresh
/// must use that path for cache tokens and tail warm — otherwise every
/// softReload re-runs page-first over the full file.
void main() {
  late Directory base;
  late LocalFilesystem fs;
  late RuntimeLayout layout;

  setUp(() {
    setUpTestAppStorage();
    base = Directory.systemTemp.createTempSync('cursor_history_cache_warm_');
    fs = LocalFilesystem();
    layout = RuntimeLayout(teampilotRoot: base.path, fs: fs);
  });

  tearDown(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
    tearDownTestAppStorage();
  });

  const chatId = 'chat-aaaa-bbbb-cccc-dddd';

  Future<AppSession> installCursorFixture() async {
    final sessionId = 'sess-cursor-warm';
    final toolRoot = sessionConfigDirForTool(
      CliTool.cursor,
      layout,
      workspaceId: 'ws-1',
      sessionId: sessionId,
    );
    await _copyTree('test/fixtures/session_history/cursor', toolRoot);
    return AppSession(
      sessionId: sessionId,
      workspaceId: 'ws-1',
      folders: const [WorkspaceFolder(path: '/work/project')],
      cli: CliTool.cursor,
      nativeSessionIds: {CliTool.cursor.value: chatId},
      createdAt: 1,
      updatedAt: 1,
    );
  }

  WorkspaceLaunchContext launchCtx(AppSession session) =>
      WorkspaceLaunchContext(
        session: session,
        workspace: Workspace(
          workspaceId: session.workspaceId,
          folders: session.folders,
          createdAt: 1,
        ),
      );

  AiHistoryLoader buildLoader() {
    final registry = CliToolRegistry.builtIn();
    return AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: fs,
        home: base.path,
        cwd: base.path,
        appDataRoot: base.path,
        paths: AppPaths(base.path),
      ),
      registry: registry,
      locator: AiHistoryLocator(registry: registry),
      // Use capability / default path token — do not inject a frozen stub.
      resolveCacheToken: null,
    );
  }

  test(
    'CursorAiHistoryCapability resolves parent path and live cache token',
    () async {
      final session = await installCursorFixture();
      final toolRoot = sessionConfigDirForTool(
        CliTool.cursor,
        layout,
        workspaceId: 'ws-1',
        sessionId: session.sessionId,
      );
      final ctx = SessionHistoryContext(
        fs: fs,
        taskId: session.sessionId,
        env: {'CURSOR_CONFIG_DIR': toolRoot},
        transcriptRoots: const [],
        bucket: '',
        persistedNativeId: chatId,
      );
      const cap = CursorAiHistoryCapability();
      final path = await cap.resolveParentTranscriptPath(ctx);
      expect(path, isNotNull);
      expect(path, contains('agent-transcripts'));
      expect(path, endsWith('$chatId.jsonl'));

      final token = await cap.liveCacheToken(ctx);
      expect(token, isNotNull);
      expect(token, startsWith(path!));
      expect(token!.split('|'), hasLength(3));
    },
  );

  test(
    'unchanged Cursor reload reuses cached messages via capability token',
    () async {
      final session = await installCursorFixture();
      final loader = buildLoader();
      final first = await loader.load(
        session: session,
        memberId: '',
        launchContext: launchCtx(session),
      );
      expect(first.messages, isNotEmpty);

      final second = await loader.load(
        session: session,
        memberId: '',
        launchContext: launchCtx(session),
      );
      expect(
        identical(second.messages, first.messages),
        isTrue,
        reason:
            'stable Cursor cache token must short-circuit; page-first churn '
            'must not rebuild the list on every softReload',
      );
    },
  );

  test(
    'Cursor append after warm keeps prior message identity',
    () async {
      final session = await installCursorFixture();
      final loader = buildLoader();
      final first = await loader.load(
        session: session,
        memberId: '',
        launchContext: launchCtx(session),
      );
      expect(first.messages, isNotEmpty);
      final firstUser = first.messages.first;

      await loader.debugAwaitTailWarm(
        sessionId: session.sessionId,
        memberId: '',
      );

      final toolRoot = sessionConfigDirForTool(
        CliTool.cursor,
        layout,
        workspaceId: 'ws-1',
        sessionId: session.sessionId,
      );
      final transcript = File(
        p.join(
          toolRoot,
          'projects',
          'home-me-proj',
          'agent-transcripts',
          chatId,
          '$chatId.jsonl',
        ),
      );
      expect(transcript.existsSync(), isTrue);
      await transcript.writeAsString(
        '\n${jsonlAssistantLine(id: 'a-late', text: 'final late flush')}\n',
        mode: FileMode.append,
      );

      final second = await loader.load(
        session: session,
        memberId: '',
        launchContext: launchCtx(session),
      );
      expect(
        identical(second.messages.first, firstUser),
        isTrue,
        reason: 'warm JSONL tail must preserve prefix message instances',
      );
      expect(
        second.messages.any(
          (m) => m.parts.any(
            (part) =>
                part is AiTextPart && part.text.contains('final late flush'),
          ),
        ),
        isTrue,
      );
    },
  );
}

String jsonlAssistantLine({required String id, required String text}) =>
    '{"role":"assistant","message":{"id":"$id","content":[{"type":"text",'
    '"text":"$text"}]},"id":"$id"}';

Future<void> _copyTree(String source, String destination) async {
  final root = Directory(source);
  await for (final entity in root.list(recursive: true)) {
    if (entity is! File) continue;
    final dest = File(
      p.join(destination, p.relative(entity.path, from: root.path)),
    );
    await dest.parent.create(recursive: true);
    await dest.writeAsBytes(await entity.readAsBytes());
  }
}
