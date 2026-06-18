import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/claude_team_roster_service.dart';
import 'package:teampilot/utils/team_member_naming.dart';

void main() {
  test('slugTeamId normalizes display names for TeamIdentity.id', () {
    expect(TeamMemberNaming.slugTeamId('My Cool Team'), 'my-cool-team');
    expect(TeamMemberNaming.slugTeamId('Default Team'), 'default-team');
    expect(TeamMemberNaming.slugTeamId(''), 'team');
  });

  test('safeClaudePathSegment matches Claude Code sanitizeName', () {
    expect(
      ClaudeTeamRosterService.safeClaudePathSegment('Default Team-9'),
      'default-team-9',
    );
  });

  test('uniqueTeamId avoids collisions', () {
    expect(
      TeamMemberNaming.uniqueTeamId('Alpha', const ['alpha']),
      'alpha-2',
    );
    expect(
      TeamMemberNaming.uniqueTeamId('Beta', const ['alpha', 'beta']),
      'beta-2',
    );
  });

  test('slugMemberName normalizes spaces and case', () {
    expect(TeamMemberNaming.slugMemberName('Developer One'), 'developer-one');
    expect(TeamMemberNaming.slugMemberName('team-lead'), 'team-lead');
  });

  test('formatAgentId strips @ from name', () {
    expect(
      TeamMemberNaming.formatAgentId('bad@name', 'team-x'),
      'bad-name@team-x',
    );
  });

  test('validateMemberName rejects @', () {
    expect(TeamMemberNaming.validateMemberName('a@b'), 'at_sign');
    expect(TeamMemberNaming.validateMemberName('ok'), isNull);
  });

  test('leadAgentId stays bare team-lead for Claude leader detection', () {
    expect(TeamMemberNaming.leadAgentId('my-team'), 'team-lead');
  });

  test('defaultRoster creates team-lead, developer, and reviewer', () {
    final roster = TeamMemberNaming.defaultRoster(joinedAt: 42);
    expect(roster.map((m) => m.id).toList(), [
      'team-lead',
      'developer',
      'reviewer',
    ]);
    expect(roster.every((m) => m.joinedAt == 42), isTrue);
    expect(roster.every((m) => m.prompt.trim().isNotEmpty), isTrue);
    expect(
      roster.every((m) => m.activePresetId == TeamIdentity.inheritPresetId),
      isTrue,
    );
  });

  test('TeamMemberConfig.fromJson keeps display name and slugs id', () {
    final member = TeamMemberConfig.fromJson({
      'id': 'Developer One',
      'name': 'Developer One',
    });
    expect(member.id, 'developer-one');
    expect(member.name, 'Developer One');
  });

  test('isTeamLead detects team-lead by id', () {
    expect(
      TeamMemberNaming.isTeamLead(
        const TeamMemberConfig(id: 'team-lead', name: 'Team Lead'),
      ),
      isTrue,
    );
    expect(
      TeamMemberNaming.isTeamLead(
        const TeamMemberConfig(id: 'member', name: 'member'),
      ),
      isFalse,
    );
  });

  test('cliAgentId uses bare id for team-lead only', () {
    expect(
      TeamMemberNaming.cliAgentId(
        memberId: 'team-lead',
        cliTeamName: 'my-team',
      ),
      'team-lead',
    );
    expect(
      TeamMemberNaming.cliAgentId(
        memberId: 'developer',
        cliTeamName: 'my-team',
      ),
      'developer@my-team',
    );
  });
}
