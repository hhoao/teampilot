import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';

import '../support/post_frame_test_harness.dart';

const _leadSlot = TeamRosterSlot(
  id: 'team-lead',
  expertKey: 'teampilot/builtin/team-lead',
);

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  LaunchProfileCubit build(LaunchProfileRepository repo) => LaunchProfileCubit(
    repository: repo,
    sessionRepository: SessionRepository(),
    executableResolver: () => 'flashskyai',
  );

  test(
    'addClonedTeam persists ids, roster, and selects the new team',
    () async {
      final dir = await Directory.systemTemp.createTemp('clone-team-');
      final repo = testLaunchProfileRepository(dir);
      final cubit = build(repo);
      await cubit.load();

      final id = await cubit.addClonedTeam(
        name: 'Research Squad',
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
        roster: const [_leadSlot],
        skillIds: const ['anthropics/skills:deep-research'],
        pluginIds: const ['acme/plugins/linter'],
        mcpServerIds: const ['context7'],
        description: 'deep research',
        extraArgs: '--foo',
      );

      expect(id, isNotNull);
      final team = cubit.state.teams.firstWhere((t) => t.id == id);
      expect(team.name, 'Research Squad');
      expect(team.cli, CliTool.claude);
      expect(team.skillIds, ['anthropics/skills:deep-research']);
      expect(team.pluginIds, ['acme/plugins/linter']);
      expect(team.mcpServerIds, ['context7']);
      expect(cubit.state.selectedTeamId, id);

      final reloaded = await repo.loadTeamProfiles();
      expect(reloaded.any((t) => t.id == id), isTrue);

      await dir.delete(recursive: true);
    },
  );

  test('addClonedTeam auto-renames on display-name collision', () async {
    final dir = await Directory.systemTemp.createTemp('clone-team-2-');
    final repo = testLaunchProfileRepository(dir);
    final cubit = build(repo);
    await cubit.load();

    final first = await cubit.addClonedTeam(
      name: 'Squad',
      cli: CliTool.claude,
      roster: const [_leadSlot],
    );
    final second = await cubit.addClonedTeam(
      name: 'Squad',
      cli: CliTool.claude,
      roster: const [_leadSlot],
    );

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(first, isNot(second));
    final names = cubit.state.teams.map((t) => t.name).toList();
    expect(names.contains('Squad'), isTrue);
    expect(names.where((n) => n.startsWith('Squad')).length, 2);

    await dir.delete(recursive: true);
  });
}
