import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/member_instance.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/cli/claude/team_roster_service.dart';
import 'package:teampilot/utils/team/team_member_naming.dart';

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
    expect((members.first as Map)['name'], TeamMemberNaming.teamLeadName);
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
      members: const [TeamMemberConfig(id: 'dev', name: 'researcher')],
      cwd: '/workspace',
      teammateMode: 'in-process',
      existing: {
        'createdAt': 1,
        'members': [
          {'agentId': 'dev@runtime-team', 'name': 'dev', 'isActive': true},
        ],
      },
    );
    final members = config['members'] as List;
    final dev = members.last as Map;
    expect(dev['isActive'], isTrue);
  });

  test('mergeConfig with pods writes pod names and role agentType', () {
    final service = ClaudeTeamRosterService(fs: LocalFilesystem());
    final pods = runtimeRosterMembers(
      TeamProfile(
        id: 'default-native-team',
        name: 'Default',
        members: [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'developer', name: 'Developer', replicas: 2),
          TeamMemberConfig(id: 'reviewer', name: 'Reviewer', replicas: 0),
        ],
      ),
    );
    final config = service.mergeConfig(
      cliTeamName: 'default-native-team-5',
      members: pods,
      cwd: '/workspace',
      teammateMode: 'in-process',
    );
    final members = (config['members'] as List).cast<Map>();
    expect(members.map((m) => m['name']), [
      'team-lead',
      'developer-0',
      'developer-1',
    ]);
    expect(members.map((m) => m['agentId']), [
      'team-lead',
      'developer-0@default-native-team-5',
      'developer-1@default-native-team-5',
    ]);
    final dev0 = members.firstWhere((m) => m['name'] == 'developer-0');
    expect(dev0['agentType'], 'developer');
  });

  test('external teammateMode omits worker backendType for mailbox dispatch', () {
    final service = ClaudeTeamRosterService(fs: LocalFilesystem());
    final entry = service.buildMemberEntry(
      member: const TeamMemberConfig(id: 'developer-0', name: 'developer-0'),
      cliTeamName: 'runtime-team',
      cwd: '/workspace',
      teammateMode: 'auto',
    );
    expect(entry['tmuxPaneId'], '');
    expect(entry.containsKey('backendType'), isFalse);
  });

  test('ensureInboxes creates pod files not type file', () async {
    final root = Directory.systemTemp.createTempSync('claude-roster-');
    addTearDown(() => root.deleteSync(recursive: true));
    final fs = LocalFilesystem();
    final service = ClaudeTeamRosterService(fs: fs);
    final rosterDir = fs.pathContext.join(root.path, 'teams', 't');
    final pods = runtimeRosterMembers(
      TeamProfile(
        id: 't',
        name: 'T',
        members: [
          TeamMemberConfig(id: 'team-lead', name: 'team-lead'),
          TeamMemberConfig(id: 'developer', name: 'Developer', replicas: 2),
        ],
      ),
    );
    await service.ensureInboxes(rosterDir: rosterDir, members: pods);
    expect(
      await fs
          .stat(fs.pathContext.join(rosterDir, 'inboxes', 'developer-0.json'))
          .then((s) => s.exists),
      isTrue,
    );
    expect(
      File(fs.pathContext.join(rosterDir, 'inboxes', 'developer-0.json'))
          .existsSync(),
      isTrue,
    );
    expect(
      File(fs.pathContext.join(rosterDir, 'inboxes', 'developer-1.json'))
          .existsSync(),
      isTrue,
    );
    expect(
      File(fs.pathContext.join(rosterDir, 'inboxes', 'developer.json'))
          .existsSync(),
      isFalse,
    );
  });
}
