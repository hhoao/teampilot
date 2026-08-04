import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  const baseTeam = TeamProfile(id: 'team-1', name: 'Team');

  group('teamLaunchShape', () {
    test('preset when activePresetId is non-empty', () {
      const team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        activePresetId: 'deepseek',
      );
      expect(teamLaunchShape(team), TeamLaunchShape.preset);
    });

    test('custom when activePresetId is null, empty, or whitespace', () {
      expect(teamLaunchShape(baseTeam), TeamLaunchShape.custom);
      expect(
        teamLaunchShape(const TeamProfile(id: 't', name: 'T', activePresetId: '')),
        TeamLaunchShape.custom,
      );
      expect(
        teamLaunchShape(
          const TeamProfile(id: 't', name: 'T', activePresetId: '   '),
        ),
        TeamLaunchShape.custom,
      );
    });
  });

  group('normalizedLaunchConfig', () {
    test('dirty preset + custom maps → preset shape only', () {
      const dirty = TeamProfile(
        id: 'team-1',
        name: 'Team',
        activePresetId: 'deepseek',
        providerIdsByTool: {'claude': 'claude-official'},
        modelsByTool: {'claude': 'sonnet'},
        cliEffortLevels: {'claude': 'high'},
      );

      final normalized = dirty.normalizedLaunchConfig();

      expect(teamLaunchShape(normalized), TeamLaunchShape.preset);
      expect(normalized.activePresetId, 'deepseek');
      expect(normalized.providerIdsByTool, isEmpty);
      expect(normalized.modelsByTool, isEmpty);
      expect(normalized.cliEffortLevels, isEmpty);
    });

    test('custom maps only → custom shape with null activePresetId', () {
      const custom = TeamProfile(
        id: 'team-1',
        name: 'Team',
        providerIdsByTool: {'claude': 'deepseek'},
        modelsByTool: {'claude': 'deepseek-chat'},
        cliEffortLevels: {'claude': 'medium'},
      );

      final normalized = custom.normalizedLaunchConfig();

      expect(teamLaunchShape(normalized), TeamLaunchShape.custom);
      expect(normalized.activePresetId, isNull);
      expect(normalized.providerIdsByTool, custom.providerIdsByTool);
      expect(normalized.modelsByTool, custom.modelsByTool);
      expect(normalized.cliEffortLevels, custom.cliEffortLevels);
    });

    test('trims whitespace from activePresetId in preset shape', () {
      const dirty = TeamProfile(
        id: 'team-1',
        name: 'Team',
        activePresetId: ' deepseek ',
      );

      final normalized = dirty.normalizedLaunchConfig();

      expect(teamLaunchShape(normalized), TeamLaunchShape.preset);
      expect(normalized.activePresetId, 'deepseek');
    });

    test('blank activePresetId with custom maps → custom shape', () {
      const dirty = TeamProfile(
        id: 'team-1',
        name: 'Team',
        activePresetId: '  ',
        providerIdsByTool: {'codex': 'openai-official'},
      );

      final normalized = dirty.normalizedLaunchConfig();

      expect(teamLaunchShape(normalized), TeamLaunchShape.custom);
      expect(normalized.activePresetId, isNull);
      expect(normalized.providerIdsByTool, dirty.providerIdsByTool);
    });
  });

  group('asPresetLaunch', () {
    test('sets preset and clears all custom launch maps', () {
      const team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        providerIdsByTool: {'claude': 'claude-official'},
        modelsByTool: {'claude': 'sonnet'},
        cliEffortLevels: {'claude': 'high'},
      );

      final preset = team.asPresetLaunch('deepseek');

      expect(preset.activePresetId, 'deepseek');
      expect(preset.providerIdsByTool, isEmpty);
      expect(preset.modelsByTool, isEmpty);
      expect(preset.cliEffortLevels, isEmpty);
      expect(teamLaunchShape(preset), TeamLaunchShape.preset);
    });

    test('optional syncCli updates team cli', () {
      final preset = baseTeam.asPresetLaunch('deepseek', syncCli: CliTool.codex);
      expect(preset.cli, CliTool.codex);
    });
  });

  group('asCustomLaunch', () {
    test('clears preset and sets custom launch defaults for cli', () {
      const team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        activePresetId: 'deepseek',
      );

      final custom = team.asCustomLaunch(
        cli: CliTool.claude,
        providerId: 'deepseek',
        model: 'deepseek-chat',
        effort: 'medium',
      );

      expect(custom.activePresetId, isNull);
      expect(custom.providerIdsByTool, {'claude': 'deepseek'});
      expect(custom.modelsByTool, {'claude': 'deepseek-chat'});
      expect(custom.cliEffortLevels, {'claude': 'medium'});
      expect(teamLaunchShape(custom), TeamLaunchShape.custom);
    });

    test('updates only the specified cli entry in custom maps', () {
      const team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        providerIdsByTool: {'codex': 'openai-official'},
        modelsByTool: {'codex': 'gpt-5'},
        cliEffortLevels: {'codex': 'high'},
      );

      final custom = team.asCustomLaunch(
        cli: CliTool.claude,
        providerId: 'deepseek',
        model: 'deepseek-chat',
        effort: 'low',
      );

      expect(custom.providerIdsByTool, {
        'codex': 'openai-official',
        'claude': 'deepseek',
      });
      expect(custom.modelsByTool, {
        'codex': 'gpt-5',
        'claude': 'deepseek-chat',
      });
      expect(custom.cliEffortLevels, {
        'codex': 'high',
        'claude': 'low',
      });
    });
  });
}
