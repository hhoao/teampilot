import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_session_shell_factory.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/tab_member_coordination_factory.dart';
import 'package:teampilot/cubits/chat/tab_member_pty_delivery.dart';
import 'package:teampilot/services/terminal/member_pty_inject_service.dart';

({TabMemberPtyDelivery delivery, MemberPtyInjectService ptyInject})
_delivery({
  void Function(String sessionId)? onUserActivity,
  MemberPtyInjectService? ptyInject,
}) {
  final tabStore = ChatTabStore();
  final inject = ptyInject ?? MemberPtyInjectService();
  return (
    delivery: TabMemberPtyDelivery(
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
      ptyInject: inject,
      onUserActivity: onUserActivity,
    ),
    ptyInject: inject,
  );
}

void main() {
  test('abortMemberInject clears abort flag when inject is idle', () {
    final ptyInject = MemberPtyInjectService();
    final delivery = _delivery(ptyInject: ptyInject).delivery;

    delivery.abortMemberInject('s1', 'm1');

    expect(ptyInject.isAbortRequested('s1', 'm1'), isFalse);
    expect(ptyInject.isBusy('s1', 'm1'), isFalse);
  });

  test('deliverUserCommandToMember reports user activity for inject', () async {
    final activity = <String>[];
    final delivery = _delivery(onUserActivity: activity.add).delivery;

    await delivery.deliverUserCommandToMember(
      'sess-1',
      'member-1',
      '  continue  ',
      directToPty: true,
    );

    expect(activity, ['sess-1']);
  });

  test('deliverUserCommandToMember reports user activity for mailbox', () async {
    final activity = <String>[];
    final delivery = _delivery(onUserActivity: activity.add).delivery;

    await delivery.deliverUserCommandToMember(
      'sess-1',
      'member-1',
      'hello',
      directToPty: false,
    );

    expect(activity, ['sess-1']);
  });

  test('deliverUserCommandToMember skips blank inject', () async {
    final activity = <String>[];
    final delivery = _delivery(onUserActivity: activity.add).delivery;

    await delivery.deliverUserCommandToMember(
      'sess-1',
      'member-1',
      '   ',
      directToPty: true,
    );

    expect(activity, isEmpty);
  });
}
