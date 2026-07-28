import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_session_shell_factory.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/tab_member_coordination_factory.dart';
import 'package:teampilot/cubits/chat/tab_member_pty_delivery.dart';
import 'package:teampilot/services/terminal/member_pty_inject_service.dart';

void main() {
  test('abortMemberInject clears abort flag when inject is idle', () {
    final tabStore = ChatTabStore();
    final ptyInject = MemberPtyInjectService();
    final delivery = TabMemberPtyDelivery(
      tabStore: tabStore,
      shellFactory: ChatSessionShellFactory(executableResolver: () => 'unused'),
      globalPresets: () => const [],
      activeTeam: () => null,
      isClosed: () => false,
      coordinationFactory: TabMemberCoordinationFactory(
        tabStore: tabStore,
        globalPresets: () => const [],
        activeTeam: () => null,
      ),
      ptyInject: ptyInject,
    );

    delivery.abortMemberInject('s1', 'm1');

    expect(ptyInject.isAbortRequested('s1', 'm1'), isFalse);
    expect(ptyInject.isBusy('s1', 'm1'), isFalse);
  });
}
