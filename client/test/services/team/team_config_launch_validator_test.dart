import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/team_config_launch_validator.dart';

void main() {
  const validator = TeamConfigLaunchValidator();

  TeamMemberConfig member(
    String name, {
    String provider = '',
    String model = '',
    TeamCli? cli,
  }) =>
      TeamMemberConfig(
        id: name,
        name: name,
        provider: provider,
        model: model,
        cli: cli,
      );

  group('native mode', () {
    test('passes when team has an explicit default provider', () {
      final team = TeamConfig(
        id: 'team',
        name: 'Team',
        cli: TeamCli.claude,
        teamMode: TeamMode.native,
        providerIdsByTool: const {'claude': 'prov-1'},
        members: [member('alice')],
      );

      final result = validator.validate(team);

      expect(result.hasIssues, isFalse);
    });

    test('passes when every member supplies provider + model', () {
      final team = TeamConfig(
        id: 'team',
        name: 'Team',
        cli: TeamCli.claude,
        teamMode: TeamMode.native,
        members: [
          member('alice', provider: 'prov-1', model: 'sonnet'),
          member('bob', provider: 'prov-2', model: 'opus'),
        ],
      );

      final result = validator.validate(team);

      expect(result.hasIssues, isFalse);
    });

    test('flags team default + members when nothing is configured', () {
      final team = TeamConfig(
        id: 'team',
        name: 'Team',
        cli: TeamCli.claude,
        teamMode: TeamMode.native,
        members: [member('alice')],
      );

      final result = validator.validate(team);

      expect(
        result.issues.map((i) => i.kind),
        containsAll([
          TeamConfigIssueKind.teamDefaultProviderMissing,
          TeamConfigIssueKind.memberProviderMissing,
          TeamConfigIssueKind.memberModelMissing,
        ]),
      );
      expect(result.firstMemberId, 'alice');
    });

    test('uses strict default: global sole provider is not counted', () {
      // Only providerIdsByTool[cli] counts; an empty map is "no default".
      final team = TeamConfig(
        id: 'team',
        name: 'Team',
        cli: TeamCli.claude,
        teamMode: TeamMode.native,
        members: [member('alice', model: 'sonnet')],
      );

      final result = validator.validate(team);

      expect(
        result.issues.map((i) => i.kind),
        contains(TeamConfigIssueKind.memberProviderMissing),
      );
    });

    test('does not flag team default when a member supplies a provider', () {
      final team = TeamConfig(
        id: 'team',
        name: 'Team',
        cli: TeamCli.claude,
        teamMode: TeamMode.native,
        members: [member('alice', provider: 'prov-1')],
      );

      final result = validator.validate(team);

      // alice provides a provider → only her missing model is flagged.
      expect(
        result.issues.map((i) => i.kind),
        equals([TeamConfigIssueKind.memberModelMissing]),
      );
    });
  });

  group('mixed mode', () {
    test('flags missing cli, provider, and model per member', () {
      final team = TeamConfig(
        id: 'team',
        name: 'Team',
        cli: TeamCli.flashskyai,
        teamMode: TeamMode.mixed,
        members: [member('alice')],
      );

      final result = validator.validate(team);

      expect(
        result.issues.map((i) => i.kind),
        containsAll([
          TeamConfigIssueKind.memberCliMissing,
          TeamConfigIssueKind.memberProviderMissing,
          TeamConfigIssueKind.memberModelMissing,
        ]),
      );
    });

    test('passes when each member has cli + provider + model', () {
      final team = TeamConfig(
        id: 'team',
        name: 'Team',
        cli: TeamCli.flashskyai,
        teamMode: TeamMode.mixed,
        members: [
          member('alice', cli: TeamCli.claude, provider: 'p', model: 'm'),
        ],
      );

      final result = validator.validate(team);

      expect(result.hasIssues, isFalse);
    });
  });

  test('ignores invalid (unnamed) members', () {
    final team = TeamConfig(
      id: 'team',
      name: 'Team',
      cli: TeamCli.claude,
      teamMode: TeamMode.native,
      providerIdsByTool: const {'claude': 'prov-1'},
      members: [const TeamMemberConfig(id: '', name: '  ')],
    );

    final result = validator.validate(team);

    expect(result.hasIssues, isFalse);
  });
}
