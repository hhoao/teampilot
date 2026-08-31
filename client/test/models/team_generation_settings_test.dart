import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('native snapshot filters by native cli and ranks after filtering', () {
    final settings = TeamGenerationSettings(
      teamMode: TeamMode.native,
      nativeCli: CliTool.claude,
      modelPool: [
        GenerateModelPoolEntry(presetId: 'codex', description: '', tags: []),
        GenerateModelPoolEntry(
          presetId: 'claude-strong',
          description: 'lead',
          tags: ['strong'],
        ),
      ],
    );

    final snapshot = resolveTeamGenerationSettingsSnapshot(
      settings: settings,
      presets: [
        _preset('codex', CliTool.codex),
        _preset('claude-strong', CliTool.claude),
      ],
      registry: CliToolRegistry.builtIn(),
      capturedAt: 42,
    );

    expect(snapshot.modelPool.single.rank, 1);
    expect(snapshot.modelPool.single.preset.id, 'claude-strong');
    expect(snapshot.capturedAt, 42);
  });

  test('native snapshot excludes launchable but non-native-team clis', () {
    final snapshot = resolveTeamGenerationSettingsSnapshot(
      settings: TeamGenerationSettings(
        teamMode: TeamMode.native,
        nativeCli: CliTool.codex,
        modelPool: [
          GenerateModelPoolEntry(
            presetId: 'codex-strong',
            description: 'looks launchable',
            tags: ['reasoning'],
          ),
        ],
      ),
      presets: [_preset('codex-strong', CliTool.codex)],
      registry: CliToolRegistry.builtIn(),
      capturedAt: 42,
    );

    expect(snapshot.modelPool, isEmpty);
  });

  test('caller tag mutations do not alter entry or snapshot revision', () {
    final sourceTags = ['reasoning'];
    final entry = GenerateModelPoolEntry(
      presetId: 'claude-strong',
      description: 'lead',
      tags: sourceTags,
    );
    final settings = TeamGenerationSettings(modelPool: [entry]);

    final firstSnapshot = resolveTeamGenerationSettingsSnapshot(
      settings: settings,
      presets: [_preset('claude-strong', CliTool.claude)],
      registry: CliToolRegistry.builtIn(),
      capturedAt: 42,
    );

    sourceTags.add('mutated');

    final secondSnapshot = resolveTeamGenerationSettingsSnapshot(
      settings: settings,
      presets: [_preset('claude-strong', CliTool.claude)],
      registry: CliToolRegistry.builtIn(),
      capturedAt: 42,
    );

    expect(entry.tags, ['reasoning']);
    expect(firstSnapshot.modelPool.single.source.tags, ['reasoning']);
    expect(secondSnapshot.modelPool.single.source.tags, ['reasoning']);
    expect(secondSnapshot.revision, firstSnapshot.revision);
  });
}

CliPreset _preset(String id, CliTool cli) {
  return CliPreset(
    id: id,
    name: id,
    cli: cli,
    provider: '${cli.value}-provider',
    model: '$id-model',
    createdAt: 1,
    updatedAt: 1,
  );
}
