import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/chat/launch/session/member_role_provision.dart';

void main() {
  test('composeRolePrompt does not append workspace directories section', () {
    const member = TeamMemberConfig(
      id: 'm1',
      name: 'Member',
      responsibilities: 'You are the reviewer.',
    );
    final prompt = MemberRoleProvision.composeRolePrompt(member: member);
    expect(prompt, contains('You are the reviewer.'));
    expect(prompt, isNot(contains('## Workspace directories')));
  });

  test(
    'composeRolePrompt dirs-only body has no workspace directories chapter',
    () {
      const member = TeamMemberConfig(id: 'm1', name: 'Member');
      final prompt = MemberRoleProvision.composeRolePrompt(member: member);
      expect(prompt, isNot(contains('## Workspace directories')));
      expect(prompt, isEmpty);
    },
  );

  test('mixed role prompt documents the TeamBus XML envelope', () {
    const member = TeamMemberConfig(id: 'm1', name: 'Member');
    final prompt = MemberRoleProvision.composeRolePrompt(
      member: member,
      mixed: true,
    );
    expect(prompt, contains('<teambus type="...">...</teambus>'));
  });

  test(
    'syncRolePromptFile skips dirs-only role.md for empty-role member',
    () async {
      final fs = LocalFilesystem();
      final root = await fs.createTempDir(prefix: 'role_dirs_');
      try {
        const member = TeamMemberConfig(id: 'm1', name: 'Member');
        final path = await MemberRoleProvision.syncRolePromptFile(
          fs: fs,
          memberToolDir: root,
          member: member,
        );
        expect(path, isNull);
      } finally {
        await fs.removeRecursive(root);
      }
    },
  );
}
