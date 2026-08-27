import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat/tab_member_coordination_factory.dart';
import 'package:teampilot/cubits/chat/tab_session_idle_watch.dart';
import 'package:teampilot/services/team/session_working_resolver.dart';

import '../../integration/support/connected_recording_shell.dart';
import '../../support/rust_lib_test_init.dart';

void main() {
  setUpAll(initRustLibForTests);
  test('onAfterTurnEnded fires on PTY-quiet turn end', () async {
    final store = ChatTabStore();
    final tab = ChatTab(
      info: const ChatTabInfo(id: 's1', title: 'T', subtitle: ''),
      cliTeamName: 's1',
    );
    store.registerSession(tab);

    final shell = await ConnectedRecordingShell.connect();
    tab.memberShells['s1'] = shell.session;

    final coordination = TabMemberCoordinationFactory(
      tabStore: store,
      globalPresets: () => const [],
      activeTeam: () => null,
      sessionWorking: SessionWorkingResolver(),
    );
    String? endedSession;
    String? endedMember;
    final watch = TabSessionIdleWatch(
      tabStore: store,
      coordinationFactory: coordination,
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
