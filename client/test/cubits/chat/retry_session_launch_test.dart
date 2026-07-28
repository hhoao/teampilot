import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/models/workspace_folder.dart';

import '../../support/post_frame_test_harness.dart';

class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
      );

  final connects = <SessionConnectRequest>[];

  @override
  Future<void> connectWorkspaceSession(
    SessionConnectRequest request, {
    SessionRepository? repo,
  }) async {
    connects.add(request);
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test(
    'retrySessionLaunch rebuilds a preserve-workbench connect for a simple session',
    () async {
      final cubit = _RecordingChatCubit();
      addTearDown(cubit.close);

      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        folders: const [WorkspaceFolder(path: '/w')],
        createdAt: 1,
        updatedAt: 1,
      );

      cubit.tabStore.setActiveWorkspace('w1');
      cubit.tabStore.append(
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
    },
  );

  test('retrySessionLaunch does nothing for an unknown session id', () async {
    final cubit = _RecordingChatCubit();
    addTearDown(cubit.close);

    await cubit.retrySessionLaunch('missing');

    expect(cubit.connects, isEmpty);
  });
}
