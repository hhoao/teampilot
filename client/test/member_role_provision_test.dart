import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/member_role_provision.dart';

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
        memberClaudeToolDir: root,
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
        memberClaudeToolDir: root,
        member: member.copyWith(prompt: ''),
      );
      expect((await fs.stat(path!)).exists, isFalse);
    } finally {
      await fs.removeRecursive(root);
    }
  });

  test('syncRolePromptFile writes anti-self-loop addendum for team-lead', () async {
    final fs = LocalFilesystem();
    final root = await fs.createTempDir(prefix: 'role_lead_');
    try {
      const lead = TeamMemberConfig(id: 'lead', name: 'team-lead', prompt: '');
      final path = await MemberRoleProvision.syncRolePromptFile(
        fs: fs,
        memberClaudeToolDir: root,
        member: lead,
      );
      expect(path, isNotNull);
      final text = await fs.readString(path!);
      expect(text, contains('SendMessage'));
      expect(text, contains('team-lead'));
    } finally {
      await fs.removeRecursive(root);
    }
  });

  test('applyTeamSessionPolicy denies TeamCreate for all members', () {
    final settings = MemberRoleProvision.applyTeamSessionPolicy(const {});
    final deny = settings['permissions']! as Map;
    expect(deny['deny'], contains('TeamCreate'));
    expect(deny['deny'], isNot(contains('Bash')));
    expect(deny['deny'], isNot(contains('Edit')));
  });
}
