// test/services/workbench/workbench_chat_bridge_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/services/workbench/workbench_chat_bridge.dart';

import '../../support/fake_terminal_session.dart';
import '../../support/post_frame_test_harness.dart';

const _ws = 'ws';
final _s1 = WorkbenchTabId.session('s1');

void main() {
  late WorkbenchCubit cubit;
  late ChatCubit chat;
  late WorkbenchChatBridge bridge;
  setUp(() {
    setUpTestAppStorage();
    cubit = WorkbenchCubit();
    chat = ChatCubit(
      executableResolver: () => '/bin/true',
      automationRepository: testAutomationRepository(),
    );
    bridge = WorkbenchChatBridge(workbench: cubit, chat: chat);
  });
  tearDown(() async {
    await chat.close();
    await cubit.close();
  });

  group('WorkbenchChatBridge.onSessionTabOpened', () {
    test('feeds a session open into the bar and activates it', () {
      bridge.onSessionTabOpened(_ws, 's1', preview: false);
      final center = cubit.state.bar(_ws).center;
      expect(center.order, [_s1]);
      expect(center.activeId, _s1);
      expect(center.previewIds, isEmpty);
    });

    test('preview: true surfaces the tab as a preview', () {
      bridge.onSessionTabOpened(_ws, 's1', preview: true);
      final center = cubit.state.bar(_ws).center;
      expect(center.order, [_s1]);
      expect(center.activeId, _s1);
      expect(center.previewIds, {_s1});
    });

    test('activate: false appends without activating', () {
      bridge.onSessionTabOpened(_ws, 's1', preview: false, activate: false);
      final center = cubit.state.bar(_ws).center;
      expect(center.order, [_s1]);
      expect(center.activeId, isNull);
    });

    test('tears down a preview replaced in place', () async {
      chat.tabStore.setActiveWorkspaceId('ws-1');
      chat.tabStore.registerSession(
        ChatTab(
          info: ChatTabInfo(id: 'A', title: 'a', subtitle: ''),
          cliTeamName: '',
          workspaceId: 'ws-1',
        ),
      );
      chat.tabStore.registerSession(
        ChatTab(
          info: ChatTabInfo(id: 'B', title: 'b', subtitle: ''),
          cliTeamName: '',
          workspaceId: 'ws-1',
        ),
      );

      bridge.onSessionTabOpened('ws-1', 'A', preview: true);
      bridge.onSessionTabOpened('ws-1', 'B', preview: true);
      await pumpEventQueue();

      expect(chat.tabStore.openTabBySessionId('B'), isNotNull);
      // A was replaced in place by B and must not linger as an orphan runtime.
      expect(chat.tabStore.openTabBySessionId('A'), isNull);
    });

    test('running session replaced in the preview slot is re-pinned, not torn '
        'down', () async {
      chat.tabStore.setActiveWorkspaceId('ws-1');
      final running = FakeTerminalSession();
      running.connect(workingDirectory: '/tmp');
      chat.tabStore.registerSession(
        ChatTab(
          info: ChatTabInfo(id: 'A', title: 'a', subtitle: ''),
          cliTeamName: '',
          workspaceId: 'ws-1',
        )..resumeSession = running,
      );
      chat.tabStore.registerSession(
        ChatTab(
          info: ChatTabInfo(id: 'B', title: 'b', subtitle: ''),
          cliTeamName: '',
          workspaceId: 'ws-1',
        ),
      );

      bridge.onSessionTabOpened('ws-1', 'A', preview: true);
      bridge.onSessionTabOpened('ws-1', 'B', preview: true);
      await pumpEventQueue();

      // A is running: it must survive the preview replace and re-pin into
      // the bar without stealing activation from B.
      expect(chat.tabStore.openTabBySessionId('A'), isNotNull);
      final center = cubit.state.bar('ws-1').center;
      final aTab = WorkbenchTabId.session('A');
      expect(center.contains(aTab), isTrue);
      expect(center.previewIds, isNot(contains(aTab)));
      expect(center.activeId, WorkbenchTabId.session('B'));
    });
  });

  group('WorkbenchChatBridge.replacedPreviewTeardown', () {
    test('fires for a replaced non-session preview', () {
      final teardowns = <(String, WorkbenchTabId)>[];
      final localBridge = WorkbenchChatBridge(
        workbench: cubit,
        chat: chat,
        replacedPreviewTeardown: (workspaceId, replaced) {
          teardowns.add((workspaceId, replaced));
        },
      );
      cubit.openFile(_ws, '/a.txt', preview: true);
      localBridge.onSessionTabOpened(_ws, 's1', preview: true);

      expect(teardowns, [(_ws, WorkbenchTabId.file('/a.txt'))]);
    });

    test('does not fire for a replaced session preview', () async {
      final teardowns = <WorkbenchTabId>[];
      final localBridge = WorkbenchChatBridge(
        workbench: cubit,
        chat: chat,
        replacedPreviewTeardown: (workspaceId, replaced) {
          teardowns.add(replaced);
        },
      );
      localBridge.onSessionTabOpened(_ws, 's1', preview: true);
      localBridge.onSessionTabOpened(_ws, 's2', preview: true);
      await pumpEventQueue();

      expect(teardowns, isEmpty);
    });
  });
}
