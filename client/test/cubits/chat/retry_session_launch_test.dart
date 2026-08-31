import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/failed_message_record.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/session/failed_message_store.dart';
import 'package:teampilot/services/storage/app_storage.dart';

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

void main() {
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
}
