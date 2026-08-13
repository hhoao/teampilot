import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/session/member_role_provision.dart';

void main() {
  test('composeWorkspaceDirectoriesPrompt lists absolute paths', () {
    final prompt = MemberRoleProvision.composeWorkspaceDirectoriesPrompt(
      <String>['/repo/a', '/repo/b'],
    );
    expect(prompt, contains('## Workspace directories'));
    expect(prompt, contains('- /repo/a'));
    expect(prompt, contains('- /repo/b'));
    expect(prompt, contains('absolute paths'));
  });

  test('composeWorkspaceDirectoriesPrompt is empty without dirs', () {
    expect(
      MemberRoleProvision.composeWorkspaceDirectoriesPrompt(const []),
      isEmpty,
    );
    expect(
      MemberRoleProvision.composeWorkspaceDirectoriesPrompt(const ['  ']),
      isEmpty,
    );
  });

  test('composeRolePrompt appends workspace directories section', () {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      responsibilities: 'You are the reviewer.',
    );
    final prompt = MemberRoleProvision.composeRolePrompt(
      member: member,
      additionalDirectories: const ['/repo/a'],
    );
    expect(prompt, contains('You are the reviewer.'));
    expect(prompt, contains('## Workspace directories'));
    expect(prompt, contains('- /repo/a'));
  });

  test('composeRolePrompt without dirs keeps body unchanged', () {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      responsibilities: 'You are the reviewer.',
    );
    final withDirs = MemberRoleProvision.composeRolePrompt(
      member: member,
      additionalDirectories: const [],
    );
    final without = MemberRoleProvision.composeRolePrompt(member: member);
    expect(withDirs, without);
  });
}
