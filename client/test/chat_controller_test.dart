import 'package:flashskyai_client/controllers/chat_controller.dart';
import 'package:flashskyai_client/models/team_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const team = TeamConfig(
    id: 'team-1',
    name: 'Default Team',
    workingDirectory: '/work/current',
    members: [
      TeamMemberConfig(id: 'lead', name: 'team-lead'),
      TeamMemberConfig(id: 'coder', name: 'coder'),
    ],
  );

  test('selects team-lead as the default target', () {
    final controller = ChatController();

    controller.syncTeam(team);

    expect(controller.selectedMemberId, 'lead');
    expect(controller.selectedMemberName(team), 'team-lead');
  });

  test('selected target member can change', () {
    final controller = ChatController();
    controller.syncTeam(team);

    controller.selectMember('coder');

    expect(controller.selectedMemberId, 'coder');
    expect(controller.selectedMemberName(team), 'coder');
  });

  test('ensureSession creates a disconnected session', () {
    final controller = ChatController();
    controller.syncTeam(team);

    final session = controller.ensureSession(team);

    expect(session.isRunning, false);
    expect(controller.session, same(session));
  });

  test('addSystemMessage writes to terminal when session exists', () {
    final controller = ChatController();
    controller.syncTeam(team);
    controller.ensureSession(team);

    controller.addSystemMessage('Hello world');

    // terminal buffer should contain the message
    final buffer = controller.session!.terminal.buffer;
    expect(buffer.lines.length, greaterThan(0));
  });
}
