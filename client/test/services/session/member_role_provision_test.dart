import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/member_role_provision.dart';

void main() {
  test('syncRolePromptFile writes and removes role.md', () async {
    final fs = LocalFilesystem();
    final root = await fs.createTempDir(prefix: 'role_prompt_');
    try {
      const member = TeamMemberConfig(
        id: 'dev',
        name: 'Developer One',
        prompt: 'Implement only assigned tasks.',
      );
      final path = await MemberRoleProvision.syncRolePromptFile(
        fs: fs,
        memberToolDir: root,
        member: member,
      );
      expect(path, isNotNull);
      expect(
        path,
        p.join(root, 'prompts', 'developer-one', 'role.md'),
      );
      expect(await fs.readString(path!), contains('Implement only'));

      await MemberRoleProvision.syncRolePromptFile(
        fs: fs,
        memberToolDir: root,
        member: member.copyWith(prompt: ''),
      );
      expect((await fs.stat(path!)).exists, isFalse);
    } finally {
      await fs.removeRecursive(root);
    }
  });

  test('syncRolePromptFile writes team-lead role addendum', () async {
    final fs = LocalFilesystem();
    final root = await fs.createTempDir(prefix: 'role_lead_');
    try {
      const lead = TeamMemberConfig(id: 'lead', name: 'team-lead', prompt: '');
      final path = await MemberRoleProvision.syncRolePromptFile(
        fs: fs,
        memberToolDir: root,
        member: lead,
      );
      expect(path, isNotNull);
      final text = await fs.readString(path!);
      expect(text, contains('team-lead'));
      expect(text, contains('Team Leader'));
      expect(text, isNot(contains('Delegate-only mode')));
    } finally {
      await fs.removeRecursive(root);
    }
  });

  test('syncRolePromptFile adds delegate addendum when flag is on', () async {
    final fs = LocalFilesystem();
    final root = await fs.createTempDir(prefix: 'role_delegate_');
    try {
      const lead = TeamMemberConfig(id: 'lead', name: 'team-lead', prompt: '');
      await MemberRoleProvision.syncRolePromptFile(
        fs: fs,
        memberToolDir: root,
        member: lead,
        forceTeamLeadDelegateMode: true,
      );
      final path = MemberRoleProvision.rolePromptPath(root, lead);
      final text = await fs.readString(path);
      expect(text, contains('Delegate-only mode'));
    } finally {
      await fs.removeRecursive(root);
    }
  });

  test('applyTeamSessionPolicy denies TeamCreate and TeamDelete for all members', () {
    final settings = MemberRoleProvision.applyTeamSessionPolicy(const {});
    final deny = settings['permissions']! as Map;
    expect(deny['deny'], contains('TeamCreate'));
    expect(deny['deny'], contains('TeamDelete'));
    expect(deny['deny'], isNot(contains('Bash')));
    expect(deny['deny'], isNot(contains('Edit')));
  });
}
