import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/chat/history_continue_delivery.dart';
import 'package:teampilot/services/chat/launch/session_launch_host.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';

import '../../support/post_frame_test_harness.dart';

/// Records the bar calls the session domain makes.
final class _RecordingWorkbenchPort implements ChatWorkbenchPort {
  final promoted = <(String, String)>[];

  @override
  void promoteSessionTab(String workspaceId, String sessionId) =>
      promoted.add((workspaceId, sessionId));

  @override
  void onSessionTabClosed(String workspaceId, String sessionId) {}

  @override
  void enterLanding(
    String workspaceId, {
    String? initialText,
    String? referencedSessionId,
  }) {}

  @override
  void onSessionDeleted(String workspaceId, String sessionId) {}

  @override
  void closeAll(String workspaceId) {}

  @override
  CenterActiveScope centerActiveForScope(String workspaceId) =>
      const CenterActiveScope.landing();
}

/// Skips the real delivery pipeline, which waits on a member shell this fixture
/// has none of. The promote decision under test happens before it.
final class _NoDeliveryChatCubit extends ChatCubit {
  _NoDeliveryChatCubit()
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        storage: testHomeStorage,
      );

  @override
  Future<T> withCancellableOperatorDelivery<T>(
    String sessionId,
    Future<T> Function(bool Function() cancelled) action,
  ) async {
    if (T == HistoryContinueSubmitResult) {
      return const HistoryContinueSubmitResult(
            ok: true,
            channel: HistoryContinueChannel.pty,
          )
          as T;
    }
    return action(() => false);
  }
}

void main() {
  late ChatCubit cubit;
  late _RecordingWorkbenchPort port;

  setUp(() {
    setUpTestAppStorage();
    cubit = _NoDeliveryChatCubit();
    port = _RecordingWorkbenchPort();
    cubit.workbenchPort = port;
    cubit.tabStore.setActiveWorkspaceId('workspace-1');
    cubit.tabStore.registerSession(
      ChatTab(
          info: const ChatTabInfo(id: 'session-1', title: 'S', subtitle: ''),
          cliTeamName: '',
          workspaceId: 'workspace-1',
        )
        ..persistedSession = AppSession(
          sessionId: 'session-1',
          workspaceId: 'workspace-1',
          sessionTeam: '',
          cli: CliTool.claude,
          createdAt: 0,
        ),
    );
  });

  tearDown(() async {
    await cubit.close();
    tearDownTestAppStorage();
  });

  test(
    'an operator send promotes the session tab out of the preview slot',
    () async {
      await cubit.submitSessionOperatorMessage(
        sessionId: 'session-1',
        memberId: 'session-1',
        message: 'hello',
      );

      // The tab was opened from the sidebar as a replaceable preview; a send is
      // the commit point, so it must leave the preview slot before the delivery
      // pipeline runs.
      expect(port.promoted, [('workspace-1', 'session-1')]);
    },
  );

  test('an empty message does not promote', () async {
    await cubit.submitSessionOperatorMessage(
      sessionId: 'session-1',
      memberId: 'session-1',
      message: '   ',
    );

    expect(port.promoted, isEmpty);
  });
}
