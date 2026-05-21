import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/claude_team_roster_service.dart';
import 'package:teampilot/utils/team_member_naming.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  test('mergeConfig injects team-lead when missing from UI members', () {
    final service = ClaudeTeamRosterService(fs: LocalFilesystem());
    final config = service.mergeConfig(
      cliTeamName: 'runtime-team',
      members: const [
        TeamMemberConfig(id: 'dev', name: 'researcher', joinedAt: 1),
      ],
      cwd: '/workspace',
      teammateMode: 'in-process',
    );
    final members = config['members'] as List;
    expect(members.length, 2);
    expect(
      (members.first as Map)['name'],
      TeamMemberNaming.teamLeadName,
    );
  });

  test('mergeConfig preserves createdAt from existing roster', () {
    final service = ClaudeTeamRosterService(fs: LocalFilesystem());
    final config = service.mergeConfig(
      cliTeamName: 't',
      members: const [TeamMemberConfig(id: 'lead', name: 'team-lead')],
      cwd: '/ws',
      teammateMode: 'in-process',
      existing: {'createdAt': 42, 'leadSessionId': 'old-lead'},
    );
    expect(config['createdAt'], 42);
    expect(config['leadSessionId'], 'old-lead');
    expect(config.containsKey('env'), isFalse);
  });
}
