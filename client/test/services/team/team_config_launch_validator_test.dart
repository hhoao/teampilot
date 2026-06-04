import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/team/team_config_launch_validator.dart';

void main() {
  // Stub: provider ids starting with "official" are treated as official
  // providers (which ship their own model, so no model selection is required).
  final validator = TeamConfigLaunchValidator(
    isOfficialProvider: (cli, providerId) async =>
        providerId.startsWith('official'),
  );

  TeamMemberConfig member(
    String name, {
    String provider = '',
    String model = '',
    TeamCli? cli,
  }) => TeamMemberConfig(
    id: name,
    name: name,
    provider: provider,
    model: model,
    cli: cli,
  );

  group('native mode', () {
    test('passes when team has an explicit default provider', () async {
      final team = TeamConfig(
        id: 'team',
        name: 'Team',
        cli: TeamCli.claude,
        teamMode: TeamMode.native,
        providerIdsByTool: const {'claude': 'prov-1'},
        members: [member('alice')],
      );

      final result = await validator.validate(team);

      expect(result.hasIssues, isFalse);
    });

    test('passes when every member supplies provider + model', () async {
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

      final result = await validator.validate(team);

      expect(result.hasIssues, isFalse);
    });

    test('flags team default + provider when nothing is configured', () async {
      final team = TeamConfig(
        id: 'team',
        name: 'Team',
        cli: TeamCli.claude,
        teamMode: TeamMode.native,
        members: [member('alice')],
      );

      final result = await validator.validate(team);

      expect(
        result.issues.map((i) => i.kind),
        containsAll([
          TeamConfigIssueKind.teamDefaultProviderMissing,
          TeamConfigIssueKind.memberProviderMissing,
        ]),
      );
      // No provider → model is not flagged (its requirement depends on which
      // provider is chosen).
      expect(
        result.issues.map((i) => i.kind),
        isNot(contains(TeamConfigIssueKind.memberModelMissing)),
      );
      expect(result.firstMemberId, 'alice');
    });

    test('uses strict default: global sole provider is not counted', () async {
      // Only providerIdsByTool[cli] counts; an empty map is "no default".
      final team = TeamConfig(
        id: 'team',
        name: 'Team',
        cli: TeamCli.claude,
        teamMode: TeamMode.native,
        members: [member('alice', model: 'sonnet')],
      );

      final result = await validator.validate(team);

      expect(
        result.issues.map((i) => i.kind),
        contains(TeamConfigIssueKind.memberProviderMissing),
      );
    });

    test('flags missing model for a non-official member provider', () async {
      final team = TeamConfig(
        id: 'team',
        name: 'Team',
        cli: TeamCli.claude,
        teamMode: TeamMode.native,
        members: [member('alice', provider: 'prov-1')],
      );

      final result = await validator.validate(team);

      // alice provides a (non-official) provider → only her missing model.
      expect(
        result.issues.map((i) => i.kind),
        equals([TeamConfigIssueKind.memberModelMissing]),
      );
    });

    test('official member provider does not require a model', () async {
      final team = TeamConfig(
        id: 'team',
        name: 'Team',
        cli: TeamCli.claude,
        teamMode: TeamMode.native,
        members: [member('alice', provider: 'official-anthropic')],
      );

      final result = await validator.validate(team);

      expect(result.hasIssues, isFalse);
    });
  });

  group('mixed mode', () {
    test('flags missing cli and provider per member', () async {
      final team = TeamConfig(
        id: 'team',
        name: 'Team',
        cli: TeamCli.flashskyai,
        teamMode: TeamMode.mixed,
        members: [member('alice')],
      );

      final result = await validator.validate(team);

      expect(
        result.issues.map((i) => i.kind),
        containsAll([
          TeamConfigIssueKind.memberCliMissing,
          TeamConfigIssueKind.memberProviderMissing,
        ]),
      );
      // No provider yet → model requirement is unknown, so not flagged.
      expect(
        result.issues.map((i) => i.kind),
        isNot(contains(TeamConfigIssueKind.memberModelMissing)),
      );
    });

    test('flags missing model for a non-official member provider', () async {
      final team = TeamConfig(
        id: 'team',
        name: 'Team',
        cli: TeamCli.flashskyai,
        teamMode: TeamMode.mixed,
        members: [member('alice', cli: TeamCli.claude, provider: 'prov-x')],
      );

      final result = await validator.validate(team);

      expect(
        result.issues.map((i) => i.kind),
        equals([TeamConfigIssueKind.memberModelMissing]),
      );
    });

    test('official member provider does not require a model', () async {
      final team = TeamConfig(
        id: 'team',
        name: 'Team',
        cli: TeamCli.flashskyai,
        teamMode: TeamMode.mixed,
        members: [
          member('alice', cli: TeamCli.claude, provider: 'official-anthropic'),
        ],
      );

      final result = await validator.validate(team);

      expect(result.hasIssues, isFalse);
    });

    test('passes when each member has cli + provider + model', () async {
      final team = TeamConfig(
        id: 'team',
        name: 'Team',
        cli: TeamCli.flashskyai,
        teamMode: TeamMode.mixed,
        members: [
          member('alice', cli: TeamCli.claude, provider: 'p', model: 'm'),
        ],
      );

      final result = await validator.validate(team);

      expect(result.hasIssues, isFalse);
    });
  });

  test('ignores invalid (unnamed) members', () async {
    final team = TeamConfig(
      id: 'team',
      name: 'Team',
      cli: TeamCli.claude,
      teamMode: TeamMode.native,
      providerIdsByTool: const {'claude': 'prov-1'},
      members: [const TeamMemberConfig(id: '', name: '  ')],
    );

    final result = await validator.validate(team);

    expect(result.hasIssues, isFalse);
  });
}
