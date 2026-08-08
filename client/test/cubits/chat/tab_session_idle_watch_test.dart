import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_session_shell_factory.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/tab_member_coordination_factory.dart';
import 'package:teampilot/cubits/chat/tab_member_pty_delivery.dart';
import 'package:teampilot/cubits/chat/tab_session_idle_watch.dart';
import 'package:teampilot/services/team/session_working_resolver.dart';

import '../../integration/support/connected_recording_shell.dart';

void main() {
  test('onAfterTurnEnded fires on PTY-quiet turn end', () async {
    final store = ChatTabStore();
    final tab = ChatTab(
      info: const ChatTabInfo(id: 's1', title: 'T', subtitle: ''),
      cliTeamName: 's1',
    );
    store.append(tab);

    final shell = await ConnectedRecordingShell.connect();
    tab.memberShells['s1'] = shell.session;

    final coordination = TabMemberCoordinationFactory(
      tabStore: store,
      globalPresets: () => const [],
      activeTeam: () => null,
      sessionWorking: SessionWorkingResolver(),
    );
    final delivery = TabMemberPtyDelivery(
      tabStore: store,
      shellFactory: ChatSessionShellFactory(
        executableResolver: () => 'true',
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                shell.session,
      ),
      globalPresets: () => const [],
      activeTeam: () => null,
      isClosed: () => false,
      coordinationFactory: coordination,
    );

    String? endedSession;
    String? endedMember;
    final watch = TabSessionIdleWatch(
      tabStore: store,
      coordinationFactory: coordination,
      delivery: delivery,
      isClosed: () => false,
      onAfterTurnEnded: (sid, mid) {
        endedSession = sid;
        endedMember = mid;
      },
    );

    shell.session.activityTracker.latchBootFrameReadyForTest(
      DateTime.now().subtract(const Duration(seconds: 5)),
    );
    shell.session.markUserTurnStarted();
    // First tick latches the turn rising edge (resets the quiet baseline).
    watch.tick();
    // Backdate a quiet gap, then a second tick ends the turn.
    shell.simulateQuietGap();
    watch.tick();
    await Future<void>.delayed(Duration.zero);

    expect(endedSession, 's1');
    expect(endedMember, 's1');
    watch.dispose();
  });
}
