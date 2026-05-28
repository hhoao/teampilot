import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/claude_team_roster_service.dart';
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
      members: const [TeamMemberConfig(id: 'team-lead', name: 'team-lead')],
      cwd: '/ws',
      teammateMode: 'in-process',
      existing: {'createdAt': 42, 'leadSessionId': 'old-lead'},
    );
    expect(config['createdAt'], 42);
    expect(config['leadSessionId'], 'old-lead');
    expect(config.containsKey('env'), isFalse);
  });

  test('buildMemberEntry omits isActive; merge preserves prior', () {
    final service = ClaudeTeamRosterService(fs: LocalFilesystem());
    final entry = service.buildMemberEntry(
      member: const TeamMemberConfig(id: 'dev', name: 'researcher'),
      cliTeamName: 'runtime-team',
      cwd: '/workspace',
      teammateMode: 'in-process',
    );
    expect(entry.containsKey('isActive'), isFalse);

    final config = service.mergeConfig(
      cliTeamName: 'runtime-team',
      members: const [
        TeamMemberConfig(id: 'dev', name: 'researcher'),
      ],
      cwd: '/workspace',
      teammateMode: 'in-process',
      existing: {
        'createdAt': 1,
        'members': [
          {
            'agentId': 'dev@runtime-team',
            'name': 'dev',
            'isActive': true,
          },
        ],
      },
    );
    final members = config['members'] as List;
    final dev = members.last as Map;
    expect(dev['isActive'], isTrue);
  });
}
