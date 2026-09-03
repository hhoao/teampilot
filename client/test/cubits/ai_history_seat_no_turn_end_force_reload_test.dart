import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/history_awaiting_working_sync.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../support/fake_ai_history_registry.dart';
import '../support/post_frame_test_harness.dart';

void main() {
  late Map<String, List<AiMessage>> messagesBySession;
  late _ScriptedLocator locator;
  late AiHistoryCubit cubit;

  AppSession simpleSession({String id = 'sess-a'}) => AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/work/project')],
    cli: CliTool.claude,
    createdAt: 1,
    updatedAt: 1,
  );

  WorkspaceLaunchContext launchCtx(AppSession s) => WorkspaceLaunchContext(
    session: s,
    workspace: Workspace(
      workspaceId: s.workspaceId,
      folders: s.folders,
      createdAt: 0,
    ),
  );

  List<AiMessage> transcript(String marker, {bool withFinal = false}) => [
    AiMessage(
      id: 'u-$marker',
      role: AiRole.user,
      parts: [AiTextPart(text: 'ask-$marker')],
    ),
    AiMessage(
      id: 'a-$marker',
      role: AiRole.assistant,
      parts: [
        AiTextPart(text: 'tools-$marker'),
        if (withFinal) AiTextPart(text: 'final-$marker'),
      ],
    ),
  ];

  setUp(() {
    setUpTestAppStorage();
    messagesBySession = {'sess-a': transcript('A')};
    locator = _ScriptedLocator();
    final fs = LocalFilesystem();
    final loader = AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: fs,
        home: '/tmp/ai-history-turn-end-settle',
        cwd: '/tmp/ai-history-turn-end-settle',
        appDataRoot: '/tmp/ai-history-turn-end-settle',
        paths: AppPaths('/tmp/ai-history-turn-end-settle'),
      ),
      locator: locator,
      registry: fakeAiHistoryRegistry(
        cli: CliTool.claude,
        adapter: _SessionMapAdapter(() => messagesBySession),
      ),
      // Frozen token: live softReload must not see in-memory fixture edits.
      resolveCacheToken: (_) async => 'frozen',
    );
    cubit = AiHistoryCubit(loader: loader);
  });

  tearDown(() async {
    await cubit.close();
    tearDownTestAppStorage();
  });

  test(
    'flushHeldTip endAwaiting does not softReload under frozen cache token',
    () async {
      locator.emitBundle = true;
      final session = simpleSession();
      await cubit.load(
        session: session,
        memberId: '',
        launchContext: launchCtx(session),
      );
      final seat = cubit.ensureSeat(
        sessionId: session.sessionId,
        selectedMemberId: '',
      );
      expect(seat.state.totalMessageCount, 2);

      messagesBySession['sess-a'] = transcript('A', withFinal: true);

      seat.enqueuePendingUser('ask-A');
      seat.applyWorkingSessionSync(sessionWorking: true);
      expect(
        seat.applyWorkingSessionSync(sessionWorking: false),
        HistoryAwaitingWorkingAction.clearAwaiting,
      );
      await pumpEventQueue();
      // Guard against a re-added delayed settle (900ms > former settle window).
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await pumpEventQueue();

      expect(
        seat.loadedMessages
            .where((m) => m.role == AiRole.assistant)
            .expand(
              (m) => m.parts.whereType<AiTextPart>().map((p) => p.text),
            ),
        ['tools-A'],
        reason:
            'turn-end chrome must not force-reload; live watch owns late flush',
      );
      expect(seat.state.awaitingAssistant, isFalse);
    },
  );
}

AiTranscriptBundle _bundleForSession(String sessionId) => AiTranscriptBundle(
  adapterId: 'claude',
  fragments: const [
    AiTranscriptFragment(name: 'canned.jsonl', bytes: []),
  ],
  hints: {'sessionId': sessionId},
);

class _SessionMapAdapter implements AiTranscriptAdapter {
  _SessionMapAdapter(this._messagesBySession);

  final Map<String, List<AiMessage>> Function() _messagesBySession;

  @override
  String get id => 'claude';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async {
    final sessionId = bundle.hints['sessionId'] ?? '';
    return List.of(_messagesBySession()[sessionId] ?? const []);
  }
}

class _ScriptedLocator extends AiHistoryLocator {
  bool emitBundle = false;

  @override
  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) async {
    if (!emitBundle) return null;
    final sessionId = ctx.sessionId?.trim() ?? '';
    return _bundleForSession(sessionId);
  }
}
