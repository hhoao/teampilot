import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/failed_message_record.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/failed_message_store.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../../support/fake_ai_history_registry.dart';
import '../../support/post_frame_test_harness.dart';

class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
      );

  final connects = <SessionConnectRequest>[];
  final operatorMessages =
      <({String sessionId, String memberId, String message})>[];
  var connectSucceeds = true;

  @override
  Future<void> connectWorkspaceSession(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) async {
    connects.add(request);
    final sessionId = switch (request) {
      ExistingSessionConnect(:final session) => session.sessionId,
      _ => '',
    };
    if (sessionId.isEmpty) return;
    // Mirror production: connect returns before the shell finishes, then the
    // pod leaves launching. Redelivery must wait for settle.
    beginSessionConnect(sessionId);
    if (connectSucceeds) {
      scheduleMicrotask(() {
        clearLaunchError(sessionId);
        finishSessionConnect(sessionId);
      });
    } else {
      scheduleMicrotask(() {
        failSessionConnect(sessionId, 'still broken');
      });
    }
  }

  @override
  Future<HistoryContinueSubmitResult> submitSessionOperatorMessage({
    required String sessionId,
    required String memberId,
    required String message,
    bool preserveWorkbenchView = true,
  }) async {
    operatorMessages.add((
      sessionId: sessionId,
      memberId: memberId,
      message: message,
    ));
    return const HistoryContinueSubmitResult(
      ok: true,
      channel: HistoryContinueChannel.pty,
    );
  }
}

AppSession _session(String id) => AppSession(
  sessionId: id,
  workspaceId: 'w1',
  folders: const [WorkspaceFolder(path: '/w')],
  createdAt: 1,
  updatedAt: 1,
);

/// Adapter returning whatever the mutable [messages] closure holds at parse
/// time, so the seat can be loaded with canned transcript content.
class _HolderAdapter implements AiTranscriptAdapter {
  _HolderAdapter(this.messages);

  final List<AiMessage> Function() messages;

  @override
  String get id => 'claude';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async =>
      List.of(messages());
}

/// Locator that hands back a canned bundle when [emitBundle] is true.
class _ScriptedLocator extends AiHistoryLocator {
  bool emitBundle = false;

  @override
  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) async {
    if (!emitBundle) return null;
    return const AiTranscriptBundle(
      adapterId: 'claude',
      fragments: [AiTranscriptFragment(name: 'canned.jsonl', bytes: [])],
    );
  }
}

void main() {
  // Transcript content served by the scripted adapter for the confirm test.
  var holderMessages = <AiMessage>[];

  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test(
    'retrySessionLaunch rebuilds a preserve-workbench connect for a simple session',
    () async {
      final cubit = _RecordingChatCubit();
      addTearDown(cubit.close);

      final session = _session('s1');
      cubit.tabStore.setActiveWorkspaceId('w1');
      cubit.tabStore.registerSession(
        ChatTab(
          info: ChatTabInfo(id: session.sessionId, title: 'S', subtitle: ''),
          cliTeamName: '',
        )..persistedSession = session,
      );

      await cubit.retrySessionLaunch(session.sessionId);

      expect(cubit.connects, hasLength(1));
      final request = cubit.connects.single as ExistingSessionConnect;
      expect(request.preserveWorkbenchView, isTrue);
      expect(request.team, isNull);
      expect(request.member, isNull);
      expect(request.session.sessionId, session.sessionId);
      expect(cubit.operatorMessages, isEmpty);
    },
  );

  test('retrySessionLaunch does nothing for an unknown session id', () async {
    final cubit = _RecordingChatCubit();
    addTearDown(cubit.close);

    await cubit.retrySessionLaunch('missing');

    expect(cubit.connects, isEmpty);
    expect(cubit.operatorMessages, isEmpty);
  });

  test(
    'retrySessionLaunch redelivers the latest failed message after connect succeeds',
    () async {
      final cubit = _RecordingChatCubit();
      addTearDown(cubit.close);

      final session = _session('s-retry');
      cubit.tabStore.setActiveWorkspaceId('w1');
      cubit.tabStore.registerSession(
        ChatTab(
          info: ChatTabInfo(
            id: session.sessionId,
            title: 'S',
            subtitle: '',
            launchError: 'spawn failed',
          ),
          cliTeamName: '',
        )..persistedSession = session,
      );

      final store = FailedMessageStore(
        fs: AppStorage.fs,
        rootPath: AppStorage.appDataRoot,
      );
      await store.save(
        session.workspaceId,
        session.sessionId,
        FailedMessageRecord(
          id: 'pending:old',
          text: 'older failed',
          createdAt: DateTime.utc(2026, 1, 1),
          status: FailedMessageStatus.failed,
        ),
      );
      await store.save(
        session.workspaceId,
        session.sessionId,
        FailedMessageRecord(
          id: 'pending:new',
          text: 'please send me',
          createdAt: DateTime.utc(2026, 1, 2),
          status: FailedMessageStatus.failed,
        ),
      );

      await cubit.retrySessionLaunch(session.sessionId);

      expect(cubit.connects, hasLength(1));
      expect(cubit.operatorMessages, hasLength(1));
      expect(cubit.operatorMessages.single.message, 'please send me');
      expect(cubit.operatorMessages.single.sessionId, session.sessionId);
      expect(cubit.operatorMessages.single.memberId, session.sessionId);

      final remaining = await store.load(
        session.workspaceId,
        session.sessionId,
      );
      expect(remaining.map((r) => r.id), ['pending:old']);
    },
  );

  test(
    'retrySessionLaunch does not redeliver when connect still fails',
    () async {
      final cubit = _RecordingChatCubit()..connectSucceeds = false;
      addTearDown(cubit.close);

      final session = _session('s-fail');
      cubit.tabStore.setActiveWorkspaceId('w1');
      cubit.tabStore.registerSession(
        ChatTab(
          info: ChatTabInfo(
            id: session.sessionId,
            title: 'S',
            subtitle: '',
            launchError: 'spawn failed',
          ),
          cliTeamName: '',
        )..persistedSession = session,
      );

      final store = FailedMessageStore(
        fs: AppStorage.fs,
        rootPath: AppStorage.appDataRoot,
      );
      await store.save(
        session.workspaceId,
        session.sessionId,
        FailedMessageRecord(
          id: 'pending:keep',
          text: 'stuck',
          createdAt: DateTime.utc(2026, 1, 1),
          status: FailedMessageStatus.failed,
        ),
      );

      await cubit.retrySessionLaunch(session.sessionId);

      expect(cubit.connects, hasLength(1));
      expect(cubit.operatorMessages, isEmpty);
      final remaining = await store.load(
        session.workspaceId,
        session.sessionId,
      );
      expect(remaining.single.id, 'pending:keep');
    },
  );

  test(
    'redelivery confirms a transcript-confirmed record instead of resubmitting',
    () async {
      final cubit = _RecordingChatCubit();
      addTearDown(cubit.close);

      final session = _session('s-dup');
      cubit.tabStore.setActiveWorkspaceId('w1');
      cubit.tabStore.registerSession(
        ChatTab(
          info: ChatTabInfo(id: session.sessionId, title: 'S', subtitle: ''),
          cliTeamName: '',
        )..persistedSession = session,
      );
      // Wire a real loader-backed history store so the seat can hold transcript
      // messages for the confirm check.
      holderMessages = [
        AiMessage(
          id: 'u1',
          role: AiRole.user,
          parts: const [AiTextPart(text: 'already delivered prompt')],
          createdAt: DateTime.utc(2026, 1, 2, 10),
        ),
      ];
      cubit.historyLoader = AiHistoryLoader(
        resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
          target: RuntimeTarget.local(),
          filesystem: LocalFilesystem(),
          home: '/tmp/retry-redelivery',
          cwd: '/tmp/retry-redelivery',
          appDataRoot: '/tmp/retry-redelivery',
          paths: AppPaths('/tmp/retry-redelivery'),
        ),
        locator: _ScriptedLocator()..emitBundle = true,
        registry: fakeAiHistoryRegistry(
          cli: CliTool.claude,
          adapter: _HolderAdapter(() => holderMessages),
        ),
        resolveCacheToken: (_) async => 'token-1',
      );

      final store = FailedMessageStore(
        fs: AppStorage.fs,
        rootPath: AppStorage.appDataRoot,
      );
      // The PTY died after the CLI ingested the prompt but before the status
      // flipped: the transcript already holds the text as a user turn.
      await store.save(
        session.workspaceId,
        session.sessionId,
        FailedMessageRecord(
          id: 'pending:dup',
          text: 'already delivered prompt',
          createdAt: DateTime.utc(2026, 1, 2, 10),
          status: FailedMessageStatus.sending,
        ),
      );
      final seat = cubit.ensurePodRuntime(
        session.sessionId,
      ).history!.memberSeat(sessionId: session.sessionId, memberId: session.sessionId);
      await seat.load(
        session: session,
        memberId: session.sessionId,
        launchContext: WorkspaceLaunchContext(
          workspace: Workspace(
            workspaceId: session.workspaceId,
            folders: session.folders,
            createdAt: 0,
          ),
          session: session,
        ),
      );

      await cubit.retrySessionLaunch(session.sessionId);

      expect(cubit.operatorMessages, isEmpty);
      final remaining = await store.load(
        session.workspaceId,
        session.sessionId,
      );
      expect(remaining, isEmpty);
    },
  );
}
