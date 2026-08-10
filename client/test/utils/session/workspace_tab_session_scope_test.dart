import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/services/workbench/workbench_chat_bridge.dart';
import 'package:teampilot/utils/session/workspace_tab_session_scope.dart';
import '../../support/post_frame_test_harness.dart';

ChatCubit _cubit() => ChatCubit(
  executableResolver: () => '/bin/true',
  automationRepository: testAutomationRepository(),
);

ChatTab _tab(String id) => ChatTab(
  info: ChatTabInfo(id: id, title: id, subtitle: ''),
  cliTeamName: id,
);

/// Wires the bar behind [cubit] via the bridge.
WorkbenchCubit _wireWorkbench(ChatCubit cubit) {
  final workbench = WorkbenchCubit();
  final bridge = WorkbenchChatBridge(workbench: workbench, chat: cubit);
  workbench.port = bridge;
  cubit.workbenchPort = bridge;
  return workbench;
}

/// Feeds a session runtime + bar entry for [workspaceId].
void _openSession(
  ChatCubit cubit,
  WorkbenchCubit workbench,
  String workspaceId,
  String sessionId, {
  bool activate = true,
}) {
  cubit.setActiveWorkspace(workspaceId);
  cubit.tabStore.registerSession(_tab(sessionId));
  workbench.openSession(workspaceId, sessionId, activate: activate);
}

void main() {
  group('scopedActiveSessionId', () {
    test('reads the bar center-active session for the workspace', () {
      final cubit = _cubit();
      addTearDown(cubit.close);
      final workbench = _wireWorkbench(cubit);
      addTearDown(workbench.close);

      _openSession(cubit, workbench, 'tab-A', 'a1');
      _openSession(cubit, workbench, 'tab-A', 'a2');

      expect(scopedActiveSessionId(workbench, 'tab-A'), 'a2');
    });

    test('background workspace keeps its own bar active session', () {
      final cubit = _cubit();
      addTearDown(cubit.close);
      final workbench = _wireWorkbench(cubit);
      addTearDown(workbench.close);

      _openSession(cubit, workbench, 'tab-A', 'a1');
      _openSession(cubit, workbench, 'tab-A', 'a2');
      _openSession(cubit, workbench, 'tab-B', 'b1');

      expect(scopedActiveSessionId(workbench, 'tab-A'), 'a2');
      expect(scopedActiveSessionId(workbench, 'tab-B'), 'b1');
    });

    test('landing active resolves null', () {
      final cubit = _cubit();
      addTearDown(cubit.close);
      final workbench = _wireWorkbench(cubit);
      addTearDown(workbench.close);

      _openSession(cubit, workbench, 'tab-A', 'a1');
      workbench.enterLanding('tab-A');

      expect(scopedActiveSessionId(workbench, 'tab-A'), isNull);
    });
  });

  group('scopedActiveChatTab', () {
    test('resolves the runtime for the bar center-active session', () {
      final cubit = _cubit();
      addTearDown(cubit.close);
      final workbench = _wireWorkbench(cubit);
      addTearDown(workbench.close);

      _openSession(cubit, workbench, 'tab-A', 'a1');
      _openSession(cubit, workbench, 'tab-A', 'a2');

      expect(scopedActiveChatTab(workbench, cubit, 'tab-A')?.info.id, 'a2');
    });

    test('background workspace resolves its own active runtime', () {
      final cubit = _cubit();
      addTearDown(cubit.close);
      final workbench = _wireWorkbench(cubit);
      addTearDown(workbench.close);

      _openSession(cubit, workbench, 'tab-A', 'a1');
      _openSession(cubit, workbench, 'tab-A', 'a2');
      _openSession(cubit, workbench, 'tab-B', 'b1');

      expect(scopedActiveChatTab(workbench, cubit, 'tab-A')?.info.id, 'a2');
      expect(scopedActiveChatTab(workbench, cubit, 'tab-B')?.info.id, 'b1');
    });

    test('non-session active (file tab) resolves null', () {
      final cubit = _cubit();
      addTearDown(cubit.close);
      final workbench = _wireWorkbench(cubit);
      addTearDown(workbench.close);

      _openSession(cubit, workbench, 'tab-A', 'a1');
      workbench.openFile('tab-A', '/tmp/x.dart');

      expect(scopedActiveChatTab(workbench, cubit, 'tab-A'), isNull);
    });
  });
}
